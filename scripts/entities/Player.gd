extends CharacterBody2D

func _ready() -> void:
	add_to_group("player")
	equipped_spells = GameState.get_equipped_or_default()
	equipped_spell = equipped_spells[0]

const SPEED := 130.0 # 原本260，使用者嫌跟boss都太快，砍半
const COMBO_MAX_GAP := 0.15
const RIGHTCLICK_CD := 3.0
const INSTANT_CAST_DAMAGE_MULT := 0.8
## Dash 是短時間內的高速衝刺，不是瞬移（Blink）——用 move_and_slide() 讓它跟一般移動一樣貼牆滑行，
## 不是 move_and_collide() 那種單次跳到終點。DASH_SPEED*DASH_DURATION ≈ 總衝刺距離（約220px）。
const DASH_SPEED := 1800.0
const DASH_DURATION := 0.12

## 空白鍵按下時設 true，實際觸發延到 _physics_process 做（跟其他移動/物理操作在同一個時機點）。
var dash_requested := false
var is_dashing := false
var dash_timer := 0.0
var dash_direction := Vector2.ZERO
## 上一次 WASD 有輸入時的方向，Dash 站著不動時用這個當衝刺方向
var last_move_direction := Vector2.DOWN

## 外部效果（目前是 Boss 吸引懲罰）對移動速度的乘數，1.0＝正常。由施加效果的那一方
## （Boss 統一處理）每幀直接設定／重置，Player 自己不追蹤「目前中了什麼減速」。
var speed_multiplier := 1.0

## === DURATION 類 buff（SpellEffect.gd 的 on_start()/on_expire()，SPELL_SYSTEM.md §2.2）===
## active_buffs：[{effect: SpellEffect, timer: float}]，倒數狀態存在這裡（角色節點身上），
## 不存在 SpellEffect 這個 Resource 上——CLAUDE.md 架構規則1，Resource 是共享引用，兩個角色
## 裝備同一份 .tres 的話，倒數計時器不能共用。同一個 buff_id 再次命中時刷新時間，不疊加兩份
## 獨立倒數（目前沒有任何法術要求疊加同類 buff，見 add_buff()）。
var active_buffs: Array = []

## 隱形術（InvisibilityEffect）直接讀寫這個欄位，不是算出來的——Boss.gd/BossFireball.gd/
## BossOrb.gd/BossSuctionZone.gd 的 _find_player() 在這是 true 時一律回傳 null，讓 boss
## 「找不到玩家」。施放任意法術會中斷隱形，判斷點在 _fire_spell()/_fire_instant_spell() 開頭，
## 不是這個欄位自己的邏輯（中斷的是「玩家做了什麼」，不是倒數到期，兩件事分開處理）。
var is_invisible := false

## 速度提升（SpeedBuffEffect）直接讀寫這個欄位。刻意跟 speed_multiplier（上面，Boss 吸引懲罰
## 減速專用）分開存，兩者在 _process_movement() 相乘生效，不會互相覆蓋——這正是 SPELL_SYSTEM.md
## §2.2 點名的風險（同一個欄位被多個獨立來源寫入會互相蓋掉），這次新增第二個速度來源時刻意避開。
var speed_boost_mult := 0.0

## 同類型 buff 再次命中時刷新倒數，不是疊加兩份（沒有法術要求疊加，保持最簡單的規則）。
func add_buff(effect: SpellEffect) -> void:
	for entry in active_buffs:
		if entry.effect.buff_id == effect.buff_id:
			entry.timer = effect.duration
			return
	active_buffs.append({"effect": effect, "timer": effect.duration})
	effect.on_start(self)

func has_buff(buff_id: String) -> bool:
	for entry in active_buffs:
		if entry.effect.buff_id == buff_id:
			return true
	return false

func _process_buffs(delta: float) -> void:
	for i in range(active_buffs.size() - 1, -1, -1):
		var entry = active_buffs[i]
		entry.timer -= delta
		if entry.timer <= 0.0:
			entry.effect.on_expire(self)
			active_buffs.remove_at(i)

## 隱形中斷：施放任意法術（吟唱完成或右鍵瞬發）當下，如果正在隱形就立即結束，不等自然倒數——
## 重新施放隱形術本身也會先在這裡被中斷一次，再被這次施放重新安裝，等於無縫刷新，不需要特判。
func _break_invisibility_on_cast() -> void:
	if not is_invisible:
		return
	for i in range(active_buffs.size() - 1, -1, -1):
		var entry = active_buffs[i]
		if entry.effect.buff_id == "invisibility":
			entry.effect.on_expire(self)
			active_buffs.remove_at(i)

## 被擊退時（目前只有 Boss 吸引懲罰的「拉近後重擊」會觸發）：跟怪物的 apply_knockback() 同一套
## 「力道+摩擦力線性衰減」做法，不是瞬間改 global_position 跳過去——這樣玩家會看到自己被
## move_and_slide() 推著滑開（會自然貼牆/碰撞），是一段有過程的位移，不是閃現。
## KNOCKBACK_FRICTION 數值刻意跟 Boss.gd 的同名常數一樣，純粹是手感一致，兩邊沒有程式上的關聯。
const KNOCKBACK_FRICTION := 900.0
var knockback_velocity := Vector2.ZERO

func apply_knockback(force: Vector2) -> void:
	knockback_velocity += force

## 角色大致朝左還是朝右（不是連續旋轉角度），每個 physics frame 依滑鼠相對位置更新，
## _draw() 用這個決定法杖畫在哪一側，見 _physics_process() 裡原本 look_at() 的位置。
var facing_right := true

## 目前裝備的法術，順序對應輪盤各格，由 GameState.equipped_spells（大廳配置結果）在 _ready() 填入。
## 數量不固定（DEMO_GOALS.md §2.5 的格數預算允許任意把數塞滿 6 格），輪盤的角度公式本來就支援任意數量。
var equipped_spells: Array[Spell] = []
var equipped_spell: Spell

## 法術切換輪盤狀態（DEMO_GOALS.md §3）：按住 Ctrl 彈出，子彈時間，滑鼠角度決定選中哪一格，
## 放開 Ctrl 或點擊左鍵確認。輪盤只負責畫面呈現，選取判定在這裡做。
var wheel_open := false
var wheel_hover_index := -1
var wheel_center := Vector2.ZERO
var wheel_suppress_reopen := false

signal spell_wheel_opened(center, current_index)
signal spell_wheel_hover_changed(index)
signal spell_wheel_closed(selected_index)

# 超魔專長組合表搬到 GameState.ARCANE_FEATS（大廳的唯讀一覽分頁也需要讀這份表，見該檔案註解）。

const DIR_KEYS := {
	"move_up": "U",
	"move_down": "D",
	"move_left": "L",
	"move_right": "R",
}

var is_casting := false
var cast_timer := 0.0
## 吟唱速度調整值的總和，0.0＝正常，+1.0＝+100%。實際吟唱時長＝base_cast_time / (1 + cast_speed_bonus)，
## 不是直接線性扣減——`RR`/`LL` 超魔專長在吟唱途中即時調整，不是套在發射數值上
var cast_speed_bonus := 0.0
var combo_buffer := ""
var pending_combo := ""
var combo_last_input_time := 0.0
var accumulated_feats: Array = []
var rightclick_cd_timer := 0.0
var fail_flash_timer := 0.0
var success_flash_timer := 0.0
var cast_pulse := 0.0
var hat_bob := 0.0
var hazard_flash_timer := 0.0

signal cast_started
signal cast_progress(ratio)
signal cast_ended
signal feat_added(feat_data)
signal combo_failed
signal rightclick_cd_updated(ratio)

## 目前只有基礎 Dash（DEMO_GOALS.md §2.4 的「未裝備位移法術」分支）——還沒有任何位移類法術，
## 「已裝備位移法術時改走 AoETargetingDelivery」那條分支留給之後真的有位移法術時再加。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		dash_requested = true

func _physics_process(delta: float) -> void:
	_process_buffs(delta)

	var ctrl_held := Input.is_key_pressed(KEY_CTRL)
	if not ctrl_held:
		wheel_suppress_reopen = false
	if ctrl_held and not wheel_open and not wheel_suppress_reopen:
		_open_wheel()
	elif not ctrl_held and wheel_open:
		_close_wheel()

	if knockback_velocity.length() > 1.0:
		_process_knockback(delta)
		queue_redraw()
		return

	if wheel_open:
		dash_requested = false
		is_dashing = false
		velocity = Vector2.ZERO
		move_and_slide()
		_update_wheel_hover()
		if Input.is_action_just_pressed("cast_spell"):
			_close_wheel()
			wheel_suppress_reopen = true
		queue_redraw()
		return

	if dash_requested:
		dash_requested = false
		if not is_casting and not is_dashing:
			_start_dash()

	if is_dashing:
		_process_dash(delta)
	elif is_casting:
		_process_casting(delta)
	else:
		_process_movement()

	if rightclick_cd_timer > 0.0:
		rightclick_cd_timer = max(0.0, rightclick_cd_timer - delta)
		rightclick_cd_updated.emit(1.0 - rightclick_cd_timer / RIGHTCLICK_CD)

	# 不用 look_at() 整個角色跟著滑鼠連續旋轉——3/4視角風格只需要知道「大致朝左還是朝右」，
	# 用來決定法杖畫在哪一側，不是真的要角色轉向瞄準方向（使用者覺得連續旋轉很怪）。
	facing_right = get_global_mouse_position().x >= global_position.x

	if fail_flash_timer > 0.0:
		fail_flash_timer -= delta
	if success_flash_timer > 0.0:
		success_flash_timer -= delta
	if hazard_flash_timer > 0.0:
		hazard_flash_timer -= delta
	cast_pulse += delta * (6.0 if is_casting else 1.5)
	hat_bob += delta * 4.0
	queue_redraw()

	if Input.is_action_just_pressed("cast_spell") and not is_casting:
		_start_casting()
	if Input.is_action_just_released("cast_spell") and is_casting:
		_cancel_casting()

	if Input.is_action_just_pressed("instant_cast") and rightclick_cd_timer <= 0.0:
		_fire_instant_spell()

## 彈出輪盤時取消任何進行中的吟唱——輪盤開啟時玩家唯一能做的操作是選法術，兩者不能同時進行。
func _open_wheel() -> void:
	wheel_open = true
	wheel_hover_index = -1
	wheel_center = get_viewport().get_mouse_position()
	if is_casting:
		_cancel_casting()
	Engine.time_scale = 0.25
	spell_wheel_opened.emit(wheel_center, equipped_spells.find(equipped_spell))

## 用滑鼠相對輪盤中心的角度決定選中哪一格，跟 SpellWheel.gd 畫圖時用的角度基準一致（正上方＝第0格）。
func _update_wheel_hover() -> void:
	var offset := get_viewport().get_mouse_position() - wheel_center
	var new_index := -1
	if offset.length() >= SpellWheel.DEAD_ZONE:
		var slice := TAU / float(equipped_spells.size())
		var rel := fposmod(offset.angle() + PI / 2.0, TAU)
		new_index = int(round(rel / slice)) % equipped_spells.size()
	if new_index != wheel_hover_index:
		wheel_hover_index = new_index
		spell_wheel_hover_changed.emit(wheel_hover_index)

func _close_wheel() -> void:
	wheel_open = false
	Engine.time_scale = 1.0
	if wheel_hover_index >= 0:
		equipped_spell = equipped_spells[wheel_hover_index]
	spell_wheel_closed.emit(wheel_hover_index)

## 基礎 Dash：短時間（DASH_DURATION）內用高速朝「目前移動方向」衝刺，不是朝滑鼠——滑鼠是瞄準法術用的，
## 跟移動方向是兩件不同的事，用滑鼠方向衝刺會很不自然。方向取目前按著的 WASD；站著不動時用
## last_move_direction（上一次真的有在移動的方向），不走 Spell/SpellDelivery 架構、不佔用法術欄位。
func _start_dash() -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	dash_direction = dir.normalized() if dir != Vector2.ZERO else last_move_direction
	is_dashing = true
	dash_timer = DASH_DURATION
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(0.6, 0.8, 1.0), 16, 200.0)

## 跟一般移動一樣用 move_and_slide()，貼牆會自然滑行、停下，不是瞬間跳到終點（那是 Blink，不是 Dash）。
func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = dash_direction * DASH_SPEED
	move_and_slide()
	if dash_timer <= 0.0:
		is_dashing = false
		velocity = Vector2.ZERO

## 擊退期間玩家拿不回操作權（跟移動/吟唱互斥），直到速度衰減到接近 0——跟 Boss.gd 擊退處理
## 的 if knockback_velocity.length() > 1.0: ... else: knockback_velocity = Vector2.ZERO 是同一套邏輯。
func _process_knockback(delta: float) -> void:
	velocity = knockback_velocity
	move_and_slide()
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)

func _process_movement() -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if dir != Vector2.ZERO:
		last_move_direction = dir.normalized()
	velocity = dir.normalized() * SPEED * speed_multiplier * (1.0 + speed_boost_mult)
	move_and_slide()

func _process_casting(delta: float) -> void:
	velocity = Vector2.ZERO
	# 時長倍率 = 1/(1+cast_speed_bonus)：+100% 速度時長變一半。時長變短＝消耗 cast_timer 的速率要反過來乘 (1+cast_speed_bonus)。
	cast_timer -= delta * (1.0 + cast_speed_bonus)
	cast_progress.emit(1.0 - max(cast_timer, 0.0) / equipped_spell.cast_time)

	if combo_buffer.length() > 0:
		var elapsed := Time.get_ticks_msec() / 1000.0 - combo_last_input_time
		if pending_combo != "" and elapsed >= COMBO_MAX_GAP:
			_commit_combo(pending_combo)
		elif pending_combo == "" and elapsed > COMBO_MAX_GAP:
			_fail_combo()

	for action in DIR_KEYS.keys():
		if Input.is_action_just_pressed(action):
			_handle_combo_key(DIR_KEYS[action])

	if cast_timer <= 0.0:
		_finish_casting()

func _handle_combo_key(key: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	if combo_buffer.length() > 0:
		var gap := now - combo_last_input_time
		if gap > COMBO_MAX_GAP:
			_fail_combo()
			return

	combo_last_input_time = now
	var attempt := combo_buffer + key

	var is_exact := GameState.ARCANE_FEATS.has(attempt)
	var has_longer_prefix := false
	for combo in GameState.ARCANE_FEATS.keys():
		if combo.length() > attempt.length() and combo.begins_with(attempt):
			has_longer_prefix = true
			break

	if is_exact and not has_longer_prefix:
		_commit_combo(attempt)
		return

	if is_exact and has_longer_prefix:
		combo_buffer = attempt
		pending_combo = attempt
		return

	if has_longer_prefix:
		combo_buffer = attempt
		pending_combo = ""
		return

	_fail_combo()

func _commit_combo(key_string: String) -> void:
	var feat = GameState.ARCANE_FEATS[key_string]
	accumulated_feats.append(feat)
	feat_added.emit(feat)
	success_flash_timer = 0.2
	combo_buffer = ""
	pending_combo = ""
	if feat.has("cast_speed_bonus"):
		# clamp 在 -0.9，避免疊加太多減速專長讓 (1+cast_speed_bonus) 變成 0 或負數、讀條卡死或倒退
		cast_speed_bonus = max(cast_speed_bonus + float(feat["cast_speed_bonus"]), -0.9)
	MagicFX.spawn_burst(get_tree().current_scene, global_position + Vector2(0, -24), feat.get("color", Color.WHITE), 14, 160.0)

func _fail_combo() -> void:
	combo_buffer = ""
	pending_combo = ""
	fail_flash_timer = 0.3
	combo_failed.emit()
	MagicFX.spawn_burst(get_tree().current_scene, global_position + Vector2(0, -24), Color(0.3, 0.3, 0.3), 8, 90.0)

func _start_casting() -> void:
	is_casting = true
	cast_timer = equipped_spell.cast_time
	cast_speed_bonus = 0.0
	combo_buffer = ""
	pending_combo = ""
	accumulated_feats.clear()
	cast_started.emit()

func _cancel_casting() -> void:
	is_casting = false
	cast_ended.emit()

func _finish_casting() -> void:
	is_casting = false
	_fire_spell(accumulated_feats)
	cast_ended.emit()

func _feat_to_effects(feat: Dictionary) -> Array:
	var effects: Array = []
	if feat.has("damage_mult"):
		effects.append(DamageEffect.new(0.0, 0.0, float(feat["damage_mult"])))
	return effects

## DURATION 類效果（buff）跳過不呼叫 apply()——那條路徑是給 INSTANT 類效果疊加數值用的，
## DURATION 類效果由 delivery（SelfBuffDelivery）直接拿 equipped_spell.base_effects 原始陣列
## 呼叫 add_buff()，不經過這個攤平後的 stats dict，見 _fire_spell()/_fire_instant_spell()。
func _base_stats() -> Dictionary:
	var stats := {"damage": 0.0}
	for effect in equipped_spell.base_effects:
		if effect.apply_mode == SpellEffect.ApplyMode.INSTANT:
			effect.apply(stats)
	return stats

func _fire_spell(feats: Array) -> void:
	_break_invisibility_on_cast()
	var stats := _base_stats()
	for f in feats:
		for effect in _feat_to_effects(f):
			effect.apply(stats)
	var dir := (get_global_mouse_position() - global_position).normalized()
	equipped_spell.delivery.fire(self, dir, stats, equipped_spell.max_range, equipped_spell.base_effects)

func _fire_instant_spell() -> void:
	_break_invisibility_on_cast()
	rightclick_cd_timer = RIGHTCLICK_CD
	var stats := _base_stats()
	stats.damage *= INSTANT_CAST_DAMAGE_MULT
	var dir := (get_global_mouse_position() - global_position).normalized()
	equipped_spell.delivery.fire(self, dir, stats, equipped_spell.max_range, equipped_spell.base_effects)

func take_damage(_amount: float) -> void:
	hazard_flash_timer = 0.25
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(1, 0.5, 0.1), 10, 150.0)

func _draw() -> void:
	var robe_color := Color(0.42, 0.3, 0.75)
	var glow_color := Color(0.7, 0.5, 1.0, 0.5)
	if hazard_flash_timer > 0.0:
		robe_color = Color(1.0, 0.55, 0.1)
		glow_color = Color(1.0, 0.6, 0.2, 0.6)
	elif success_flash_timer > 0.0:
		robe_color = Color(0.3, 0.85, 0.5)
		glow_color = Color(0.5, 1.0, 0.6, 0.6)
	elif fail_flash_timer > 0.0:
		robe_color = Color(0.8, 0.25, 0.25)
		glow_color = Color(1.0, 0.4, 0.4, 0.6)
	elif is_casting:
		robe_color = Color(0.55, 0.35, 0.9)
	var robe_shade := robe_color.darkened(0.25)

	# 腳下陰影：3/4視角風格的立體感來源（跟 CharacterPortrait.gd 同一套做法）。角色不再用 look_at()
	# 連續旋轉，所以不需要反向 transform 抵銷旋轉這種麻煩事——角色本身就是固定朝向，陰影直接畫。
	var shadow_points := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		shadow_points.append(Vector2(0, 20) + Vector2(cos(a) * 13.0, sin(a) * 5.0))
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.3))

	# 吟唱光環脈動
	if is_casting:
		var pulse_r := 26.0 + sin(cast_pulse) * 6.0
		draw_arc(Vector2.ZERO, pulse_r, 0, TAU, 32, glow_color, 3.0, true)

	# 長袍身體：左右兩片不同明暗模擬簡單立體感，不是單一平塗三角形（3/4視角風格）。
	var robe_left := PackedVector2Array([Vector2(0, -20), Vector2(-16, 18), Vector2(0, 18)])
	var robe_right := PackedVector2Array([Vector2(0, -20), Vector2(16, 18), Vector2(0, 18)])
	draw_colored_polygon(robe_left, robe_shade)
	draw_colored_polygon(robe_right, robe_color)
	draw_circle(Vector2(0, -20), 10, Color(0.95, 0.82, 0.65))
	draw_circle(Vector2(-3.5, -18), 1.2, Color(0.2, 0.15, 0.15))
	draw_circle(Vector2(3.5, -18), 1.2, Color(0.2, 0.15, 0.15))

	# 尖帽子，隨 hat_bob 輕微搖晃
	var hat_tilt := sin(hat_bob) * 0.08
	var hat_points := PackedVector2Array([
		Vector2(-12, -22).rotated(hat_tilt), Vector2(12, -22).rotated(hat_tilt), Vector2(0, -46).rotated(hat_tilt)
	])
	draw_colored_polygon(hat_points, Color(0.25, 0.15, 0.5))
	draw_circle(Vector2(0, -46).rotated(hat_tilt), 3, Color(1, 0.85, 0.3))

	# 法杖：不再朝滑鼠方向延伸，改成固定舉在身體側邊，依 facing_right 決定畫在左側還是右側
	# （x 座標整個鏡射），頂端發光球隨吟唱脈動。
	var side := 1.0 if facing_right else -1.0
	var staff_base := Vector2(6 * side, 4)
	var staff_tip := Vector2(28 * side, 0)
	draw_line(staff_base, staff_tip, Color(0.4, 0.28, 0.15), 3.0)
	var orb_pulse := 4.0 + (sin(cast_pulse * 2.0) * 2.0 if is_casting else 0.0)
	draw_circle(staff_tip, orb_pulse, glow_color)
	draw_circle(staff_tip, orb_pulse * 0.5, Color(1, 1, 1, 0.9))
