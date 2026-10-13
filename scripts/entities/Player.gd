extends CharacterBody2D

## 2026-10-12：角色外觀改用 PlayerSpriteAnimator（AnimatedSprite2D 子節點，見
## scripts/entities/PlayerSpriteAnimator.gd）取代原本整套 _draw() 手繪造型，_draw() 現在
## 只剩腳下陰影（靜態，不隨狀態變化，見檔案底部）。
@onready var sprite_animator: PlayerSpriteAnimator = $SpriteAnimator

func _ready() -> void:
	add_to_group("player")
	equipped_spells = GameState.get_equipped_or_default()
	equipped_spell = equipped_spells[0]
	queue_redraw() # 陰影是靜態的，只需要畫一次，不用每幀呼叫

const SPEED := 130.0 # 原本260，使用者嫌跟boss都太快，砍半
const COMBO_MAX_GAP := 0.15
const RIGHTCLICK_CD := 3.0
const INSTANT_CAST_DAMAGE_MULT := 0.8
## Dash 是短時間內的高速衝刺，不是瞬移（Blink）——用 move_and_slide() 讓它跟一般移動一樣貼牆滑行，
## 不是 move_and_collide() 那種單次跳到終點。DASH_SPEED*DASH_DURATION ＝ 總衝刺距離（2026-10-12
## 使用者要求從原本約220px改成50px，DASH_DURATION維持不變，直接用除法算出對應的速度，數值本身
## 就是「50px」這個意圖，不是另外存一個容易跟DASH_DURATION改動脫鉤的獨立常數）。
const DASH_DURATION := 0.12
const DASH_SPEED := 50.0 / DASH_DURATION

## 空白鍵按下時設 true，實際觸發延到 _physics_process 做（跟其他移動/物理操作在同一個時機點）。
var dash_requested := false
var is_dashing := false
var dash_timer := 0.0
var dash_direction := Vector2.ZERO
## 上一次 WASD 有輸入時的方向，Dash 站著不動時用這個當衝刺方向
var last_move_direction := Vector2.DOWN

## 8方向 sprite 目前該面向哪個方向的字串鍵（"down"/"down_right"/"right"/...，對應
## PlayerSpriteAnimator 的 "walk_<這個值>" 動畫名稱）。只在真的有移動/衝刺方向時更新，
## 站著不動/吟唱中維持上一次的方向，不會被重置成預設值。
var facing_direction := "down"

## 外部效果（目前是 Boss 吸引懲罰）對移動速度的乘數，1.0＝正常。由施加效果的那一方
## （Boss 統一處理）每幀直接設定／重置，Player 自己不追蹤「目前中了什麼減速」。
var speed_multiplier := 1.0

## === HP／死亡（2026-10-12 新增，取代原本「只閃光不扣血」的佔位行為）===
## 跟 Boss.gd/TestDummy.gd 同一套慣例：const MAX_HP + var hp，take_damage() 直接扣血、
## clamp 在 0。玩家這邊血量歸零**不**比照 Boss 重置滿血（那是 Boss 的佔位行為，這次的範圍只
## 包含玩家），而是真正的死亡——停止移動/吟唱/輸入，交給 DeathScreen（scenes/ui/DeathScreen.tscn）
## 顯示「你死了」畫面。hp_changed 訊號給左下角血量圓球 UI（scripts/ui/HealthOrb.gd）用，跟
## Boss.gd 的 hp_changed(ratio) 同一個慣例（ratio = hp/MAX_HP，不是傳原始血量數值）。
const MAX_HP := 100.0
var hp := MAX_HP
var is_dead := false
signal hp_changed(ratio)
signal died

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

## 目前裝備的法術，順序對應輪盤各格，由 GameState.equipped_spells（大廳配置結果）在 _ready() 填入。
## 數量不固定（DEMO_GOALS.md §2.5 的格數預算允許任意把數塞滿 6 格），輪盤的角度公式本來就支援任意數量。
var equipped_spells: Array[Spell] = []
var equipped_spell: Spell

## 法術強效/法術增遠/法術擴展/法術極效縮放出來的複製品（_apply_scaling_feats()）要在這裡
## 存一份強引用，不能只當 _fire_spell() 的區域變數——AoETargetingDelivery.fire() 內部有
## await reticle.finished，複製品的 delivery 子物件如果在這段非同步等待期間完全沒有任何
## 地方持有引用（區域變數在 _fire_spell() 返回後就離開作用域），GDScript 的協程機制不保證
## 會把 self 算進引用計數裡，複製品有可能在等待選點確認的過程中被垃圾回收，之後玩家點擊
## 確認、finished 訊號觸發時，協程所屬的物件已經不在了，不會有任何東西被恢復，paused 永遠
## 卡 true——只有套用縮放（duplicate(true) 產生複製品）且剛好又是 await-based 的 delivery
## （目前只有 AoETargetingDelivery）這個組合才會踩到，沒套用縮放時用的是 equipped_spell.delivery
## 本身（被 equipped_spell 欄位長期持有，不會被回收）所以不會卡。這個欄位存在的唯一目的就是
## 讓複製品在整段非同步流程期間都有一個不會消失的強引用持有者，不會被實際讀取用到。
var _active_cast_spell: Spell

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
## 三個 flash timer（失敗/成功/受擊）現在用來驅動 sprite_animator.modulate 的短暫變色，
## 不是改 _draw() 畫出來的袍子顏色了（_draw() 現在只剩靜態陰影），見 _update_sprite_tint()。
var fail_flash_timer := 0.0
var success_flash_timer := 0.0
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
	if is_dead:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		dash_requested = true

func _physics_process(delta: float) -> void:
	if is_dead:
		return
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
		_update_sprite_animation()
		_update_sprite_tint(delta)
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
		_update_sprite_animation()
		_update_sprite_tint(delta)
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

	_update_sprite_animation()
	_update_sprite_tint(delta)

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
	facing_direction = _direction_name(dash_direction)
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
		facing_direction = _direction_name(last_move_direction)
	# 上下移動套 GroundProjection.projected_velocity()（世界座標速度乘上 squash，變慢）——
	# 範圍判定（AoETargetingDelivery/HomingMissile...）現在用 projected_distance() 計算，
	# Y方向差距的影響力被放大了，上下方向移動天生比左右方向更快縮短「判定距離」，這裡把移動
	# 速度對應調慢抵銷掉，確保「走進某個範圍要花多久」不管從哪個方向接近都一致，見
	# scripts/core/GroundProjection.gd 開頭註解。speed_multiplier/speed_boost_mult 維持在
	# 外面相乘，不受這個方向性調整影響（純量倍率，跟方向無關）。
	velocity = GroundProjection.projected_velocity(dir.normalized(), SPEED) * speed_multiplier * (1.0 + speed_boost_mult)
	move_and_slide()

## 把一個方向向量轉成 PlayerSpriteAnimator 的 8 方向動畫鍵名（"down"/"down_right"/...），
## 用 45 度一格的八分儀判斷，0 度＝正右方（Godot 螢幕座標 y 正方向朝下，所以角度 90 度＝正下方）。
const DIRECTION_OCTANTS := ["right", "down_right", "down", "down_left", "left", "up_left", "up", "up_right"]
func _direction_name(dir: Vector2) -> String:
	var octant := int(round(dir.angle() / (PI / 4.0))) % 8
	if octant < 0:
		octant += 8
	return DIRECTION_OCTANTS[octant]

## 照目前狀態決定 sprite_animator 要播哪個動畫——純粹讀取現有狀態欄位做選擇，不持有自己的
## 狀態（跟讀條 CastBar.gd 同一個「純粹反映現有狀態」的慣例）。法術釋放/受擊的一次性動畫
## 不在這裡觸發（那兩個是事件觸發，見 _finish_casting()/take_damage()），這裡呼叫
## play_state() 即使在一次性動畫播放中也會被忽略，播完後下一幀自動接回這裡算出的狀態。
func _update_sprite_animation() -> void:
	if is_casting:
		sprite_animator.play_state("cast_charge")
	elif is_dashing or velocity.length() > 1.0:
		sprite_animator.play_state("walk_" + facing_direction)
	else:
		sprite_animator.play_state("walk_" + facing_direction, true)

## 失敗/成功/受擊三種短暫變色回饋，現在是疊在 sprite 上的 modulate 濾色，不是改手繪袍子顏色
## （_draw() 現在只剩靜態陰影）。三者互斥，依序判斷優先權：受擊 > 成功 > 失敗，沒有任何一個
## 在倒數時恢復白色（不染色）。
func _update_sprite_tint(delta: float) -> void:
	if fail_flash_timer > 0.0:
		fail_flash_timer -= delta
	if success_flash_timer > 0.0:
		success_flash_timer -= delta
	if hazard_flash_timer > 0.0:
		hazard_flash_timer -= delta

	if hazard_flash_timer > 0.0:
		sprite_animator.modulate = Color(1.0, 0.55, 0.1)
	elif success_flash_timer > 0.0:
		sprite_animator.modulate = Color(0.4, 1.0, 0.55)
	elif fail_flash_timer > 0.0:
		sprite_animator.modulate = Color(1.0, 0.35, 0.35)
	else:
		sprite_animator.modulate = Color(1, 1, 1)

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

## 給 scripts/SpellTestRange.gd 用的測試捷徑：跳過即時方向鍵輸入判定，直接視同這個超魔專長
## 已經在這次吟唱中被成功觸發（呼叫到的仍是正式的 _commit_combo()，不是另外複製一份判定邏輯，
## cast_speed_bonus／feat_added／特效全部照正式流程跑，只是觸發方式換成勾選而不是真的打鍵盤）。
func debug_force_feat(key_string: String) -> void:
	_commit_combo(key_string)

## 給 scripts/SpellTestRange.gd 的數值 before/after 除錯視窗用：不實際施放，只回傳「如果
## 現在用這組 feats 施放，法術會被縮放成什麼樣子」的預覽複製品。呼叫的是正式的
## _apply_scaling_feats()，不是另外複製一份縮放邏輯——純函式、沒有副作用，呼叫幾次都安全。
func debug_preview_scaled_spell(feats: Array) -> Spell:
	return _apply_scaling_feats(equipped_spell, feats)

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
	# buff類（SelfBuffDelivery，例如隱形術/速度提升）用法杖舉高過頭的釋放動畫，其餘攻擊類
	# 用法杖往前指的釋放動畫——看 equipped_spell 本身的 delivery 型別就夠，縮放専長（法術強效等）
	# 只會動數值，不會換掉 delivery 的類別。
	sprite_animator.play_one_shot("cast_release_buff" if equipped_spell.delivery is SelfBuffDelivery else "cast_release_attack")
	_fire_spell(accumulated_feats)
	cast_ended.emit()

func _feat_to_effects(feat: Dictionary) -> Array:
	var effects: Array = []
	if feat.has("damage_mult"):
		effects.append(DamageEffect.new(0.0, 0.0, float(feat["damage_mult"])))
	return effects

## DURATION 類效果（buff）跳過不呼叫 apply()——那條路徑是給 INSTANT 類效果疊加數值用的，
## DURATION 類效果由 delivery（SelfBuffDelivery）直接拿 spell.base_effects 原始陣列
## 呼叫 add_buff()，不經過這個攤平後的 stats dict，見 _fire_spell()/_fire_instant_spell()。
## 吃一個 spell 參數（不是固定讀 equipped_spell）——法術強效/法術極效這類超魔專長要在
## equipped_spell 的縮放複製品上算 stats，不是原本那份，見 _apply_scaling_feats()。
func _base_stats(spell: Spell) -> Dictionary:
	var stats := {"damage": 0.0}
	for effect in spell.base_effects:
		if effect.apply_mode == SpellEffect.ApplyMode.INSTANT:
			effect.apply(stats)
	return stats

## 法術迴響（echo）不是數值縮放，是「這次施放的效果重複一次」——不經過 _apply_scaling_feats()
## 那套 duplicate(true) 複製邏輯（它沒有要改 Resource 任何欄位，不需要複製保護）。2026-10-12
## 改成把 echo 當參數傳進 spell.delivery.fire()，不在這裡自己呼叫 fire() 兩次——「重複」具體
## 要做什麼交給各個 delivery 自己決定（見 SpellDelivery.fire() 的參數註解）：AoETargetingDelivery
## 只會開一次選點介面，重複的是「選好的點再爆炸一次」，不是「再選一次」；其餘 delivery 才是整串
## 效果重跑一次。兩次效果共用同一份 stats（不重新 roll 傷害區間）——跟「量詞」類超魔專長
## （法術強效縮放 count）同一個既有慣例：count=3 的魔法飛彈，3 發本來就共用同一個
## stats.damage，不是各自獨立 roll，法術迴響比照辦理。
func _fire_spell(feats: Array) -> void:
	_break_invisibility_on_cast()
	var spell := _apply_scaling_feats(equipped_spell, feats)
	_active_cast_spell = spell # 見欄位註解：避免縮放複製品在 await 期間被回收
	var stats := _base_stats(spell)
	for f in feats:
		for effect in _feat_to_effects(f):
			effect.apply(stats)
	var dir := (get_global_mouse_position() - global_position).normalized()
	var echo := false
	for f in feats:
		if f.get("echo", false):
			echo = true
	spell.delivery.fire(self, dir, stats, spell.max_range, spell.base_effects, echo)

## 法術強效/法術增遠/法術擴展/法術極效/法術延時都是「原地放大/最大化這次施放的法術數值」，
## 不是像 damage_mult 那樣疊加獨立加成的效果——如果直接改 equipped_spell/delivery/base_effects
## 任何一個欄位會污染共用的 .tres Resource（CLAUDE.md 架構規則1：Resource 是共享引用），
## 之後這把法術、甚至其他角色裝備同一份資源都會被永久動到。沒有任何相關專長觸發時直接回傳
## 原本的 spell，不用白白複製一份；一旦要縮放，整個 Spell（含 delivery/base_effects 底下
## 每個 SpellEffect）都要是 duplicate(true) 深層複製出來的獨立複製品。縮放邏輯本身不在這裡
## 判斷型別，交給各類別自己覆寫的 scale_potency()/scale_radius()/maximize()/scale_duration()
## （見 SpellEffect.gd/SpellDelivery.gd/ProjectileImpact.gd），這裡只負責觸發。法術迴響
## （echo）不在這裡處理——它不改任何 Resource 欄位，不需要複製保護，見 _fire_spell()。
func _apply_scaling_feats(spell: Spell, feats: Array) -> Spell:
	var potency_mult := 1.0
	var range_mult := 1.0
	var radius_mult := 1.0
	var duration_mult := 1.0
	var maximize := false
	for f in feats:
		if f.has("potency_mult"):
			potency_mult *= float(f["potency_mult"])
		if f.has("range_mult"):
			range_mult *= float(f["range_mult"])
		if f.has("radius_mult"):
			radius_mult *= float(f["radius_mult"])
		if f.has("duration_mult"):
			duration_mult *= float(f["duration_mult"])
		if f.get("maximize", false):
			maximize = true

	if potency_mult == 1.0 and range_mult == 1.0 and radius_mult == 1.0 and duration_mult == 1.0 and not maximize:
		return spell

	var scaled: Spell = spell.duplicate(true)
	if range_mult != 1.0:
		scaled.max_range *= range_mult
	if radius_mult != 1.0:
		scaled.delivery.scale_radius(radius_mult)
	if potency_mult != 1.0:
		scaled.delivery.scale_count(potency_mult)
	for effect in scaled.base_effects:
		if potency_mult != 1.0:
			effect.scale_potency(potency_mult)
		if duration_mult != 1.0:
			effect.scale_duration(duration_mult)
		if maximize:
			effect.maximize()
	return scaled

func _fire_instant_spell() -> void:
	_break_invisibility_on_cast()
	rightclick_cd_timer = RIGHTCLICK_CD
	var stats := _base_stats(equipped_spell)
	stats.damage *= INSTANT_CAST_DAMAGE_MULT
	var dir := (get_global_mouse_position() - global_position).normalized()
	equipped_spell.delivery.fire(self, dir, stats, equipped_spell.max_range, equipped_spell.base_effects)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	hp = max(0.0, hp - amount)
	hazard_flash_timer = 0.25
	hp_changed.emit(hp / MAX_HP)
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(1, 0.5, 0.1), 10, 150.0)
	sprite_animator.play_one_shot("hurt")
	if hp <= 0.0:
		_die()

## 死亡：停止移動/吟唱/輸入（_physics_process()/_input() 開頭的 is_dead 檢查），不比照 Boss
## 歸零重置滿血——這是真正的死亡，交給 died 訊號的接收端（Main.gd）顯示「你死了」畫面。
func _die() -> void:
	is_dead = true
	is_casting = false
	is_dashing = false
	velocity = Vector2.ZERO
	died.emit()

## 2026-10-12：角色本體（袍子/帽子/法杖/吟唱光環）改由 sprite_animator（PlayerSpriteAnimator）
## 顯示，這裡只剩腳下陰影——3/4視角風格的立體感來源，跟 Boss._draw_boss_body() 的陰影同一套
## 做法。陰影本身不隨任何狀態變化，只在 _ready() 呼叫一次 queue_redraw()，不需要每幀重畫。
##
## 陰影中心 y 座標原本是 20（沿用改用 sprite 之前、手繪長袍版本的數字——那個版本的長袍底部畫
## 在本地座標 y=18，陰影落在它正下方才合理）。换成 PlayerSpriteAnimator 之後，角色的「腳」
## 不是畫在這個數字上——PlayerSpriteAnimator.TRANSFORM_BY_CATEGORY 裡每個動畫類別的 offset
## 本來就是校正成「讓角色腳底落在節點原點（本地 y=0）」，陰影卻還留在舊版的 y=20，兩者對不上，
## 才會看起來「陰影沒有貼在腳下」（明顯偏低、跟角色脫節）。改成 y=0 試過一次又踩到新坑：
## 陰影形狀（半徑13x5橢圓）正好整個落在角色腳/褲管的不透明像素底下，被蓋住完全看不見——
## 角色本人的深色褲管跟半透明黑色陰影疊在一起混成一塊，不是陰影沒畫出來，是畫出來了但被
## 自己的腳蓋住、顏色又太接近。最後定案 y=10：陰影中心落在腳底下方一點，只有上緣被腳遮住，
## 下緣露在地板上才看得見，視覺上才是「貼著腳、不是飄在空中也不是完全重疊」。
func _draw() -> void:
	var shadow_points := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		shadow_points.append(Vector2(0, 10) + Vector2(cos(a) * 13.0, sin(a) * 5.0))
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.3))
