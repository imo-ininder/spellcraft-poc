extends CharacterBody2D

## 2026-10-12：角色外觀改用 PlayerSpriteAnimator（AnimatedSprite2D 子節點，見
## scripts/entities/PlayerSpriteAnimator.gd）取代原本整套 _draw() 手繪造型，_draw() 現在
## 只剩腳下陰影（靜態，不隨狀態變化，見檔案底部）。
@onready var sprite_animator: PlayerSpriteAnimator = $SpriteAnimator

## 2026-10-13：GameState.gd（舊的法術總表/超魔專長表/裝備清單）跟著舊戰鬥系統一起刪除，見
## docs/GDD.md。equipped_spells/equipped_spell 現在沒有任何東西會填值，維持空/null——
## 下面吟唱相關的函式都已經補上 null 檢查，這是過渡期的刻意狀態，不是忘了接資料來源。
func _ready() -> void:
	add_to_group("player")
	current_node_id = current_graph.start_node_id
	queue_redraw() # 陰影是靜態的，只需要畫一次，不用每幀呼叫

const SPEED := 130.0 # 原本260，使用者嫌跟boss都太快，砍半
const COMBO_MAX_GAP := 0.15
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

## 隱形術（InvisibilityEffect）直接讀寫這個欄位，不是算出來的。2026-10-13 現況：舊的
## boss 腳本（_find_player() 讀這個欄位判斷找不找得到玩家）跟舊的施法函式（會呼叫
## _break_invisibility_on_cast() 中斷隱形）都已經刪除，這個欄位跟下面 _break_invisibility_on_cast()
## 目前都是孤兒狀態，沒有任何東西在讀/寫/呼叫，等新系統有敵人/施法機制時再重新接上。
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

## 目前裝備的法術。2026-10-13：舊的大廳裝備流程（GameState.equipped_spells）跟輪盤切換
## 系統一起刪除了，這兩個欄位現在沒有任何地方會填值——下面吟唱相關函式都已經補上 null
## 檢查，左鍵/右鍵現在暫時什麼都不會發生，這是過渡期的刻意狀態（見 docs/GDD.md）。
var equipped_spells: Array[Spell] = []
var equipped_spell: Spell

## === Phase 2（docs/DEMO_PLAN.md §6）：法術圖譜 ===
## 目前只有一張火系圖譜，這次 Demo 範圍不處理多元素/切換元素（docs/GDD.md §6 待定），
## 直接 preload，不需要總表/選擇機制。current_node_id 永遠從 current_graph.start_node_id
## 開始衍生，每次進入專注狀態都重置回起點（不是記住上次停在哪個節點）——跟 combo_buffer/
## pending_combo 進入時清空是同一個邏輯慣例：專注狀態是一個乾淨的新開始。
var current_graph: SpellGraph = preload("res://resources/spells/fire/fire_graph.tres")
var current_node_id: String = ""

signal node_changed(node_id)

## 符文緩衝欄位，見 _handle_rune_key()。前綴比對的對象是 KNOWN_RUNES（全域符文語法表），
## 不是目前節點的 transitions——玩家在任何節點都該有一致的「要不要繼續等下一鍵」手感，
## 不會因為某節點不接受某符文就提早打斷輸入；要等打出一個完整合法的符文之後，才去查
## 目前節點是否真的有這條路，查不到的話，玩家會停在原節點，不影響目前法術依然可以施放
## （docs/DEMO_PLAN.md §6 這次拍板的設計，§4 原始判定表沒寫清楚「查不到 transition」要
## 怎麼辦，是這次補上的釐清）。
## 這次用得到的4種符文（UU/DD/LL/RR，見 docs/FIRE_PROTOTYPE.md §4.1）彼此沒有前綴重疊
## （長度都2、首字母都不同），has_longer_prefix 分支目前用不到，是刻意保留給之後 R9
## （上右下左，4鍵序列）用的骨架。
const KNOWN_RUNES := ["UU", "DD", "LL", "RR"]

const DIR_KEYS := {
	"move_up": "U",
	"move_down": "D",
	"move_left": "L",
	"move_right": "R",
}

var combo_buffer := ""
var pending_combo := ""
var combo_last_input_time := 0.0
## 三個 flash timer（失敗/成功/受擊）現在用來驅動 sprite_animator.modulate 的短暫變色，
## 不是改 _draw() 畫出來的袍子顏色了（_draw() 現在只剩靜態陰影），見 _update_sprite_tint()。
var fail_flash_timer := 0.0
var success_flash_timer := 0.0
var hazard_flash_timer := 0.0

signal combo_failed

## === Phase 1（docs/DEMO_PLAN.md §5）：專注狀態殼 ===
## 右鍵（instant_cast action）切換進出，世界時間跟著縮放（子彈時間，不是真的暫停——
## 數值沿用舊法術輪盤用過的 0.25，見 docs/SYSTEMS.md）。這個 phase 只做「能不能順暢進出、
## 時間縮放手感如何」，專注狀態下 WASD 不會移動角色，但還不會真的拿來輸入符文（Phase 2）。
var is_focused := false
const FOCUS_TIME_SCALE := 0.25

## === Phase 1：普通攻擊三連段 + 蓄力火球（一般狀態下 cast_spell 的行為）===
## tap（快按快放）＝近戰一下；按住超過 CHARGE_THRESHOLD 秒才放開＝蓄力火球。近戰判定複用
## Boss 吸引懲罰用過的「不靠物理形狀、純算距離+朝向夾角」手法，對 "enemies" 群組成員判定。
## 三段循環（combo_stage）這個 phase 刻意不做傷害/演出差異化，純粹先把循環骨架搭起來。
## 全部數值都是佔位值，比照 CLAUDE.md「法術數值目前仍是 Demo 階段的示範值」的既有慣例。
const MELEE_RANGE := 55.0
const MELEE_HALF_ANGLE := 0.6 # 約70度張角
const MELEE_DAMAGE := 8.0
const MELEE_COOLDOWN := 0.35
const CHARGE_THRESHOLD := 0.35
const CHARGED_FIREBALL_DAMAGE := 12.0
const CHARGED_FIREBALL_RANGE := 500.0
const CHARGED_FIREBALL_SPEED := 600.0
const CHARGED_FIREBALL_RADIUS := 70.0

var combo_stage := 0
var combo_cooldown_timer := 0.0
var is_charging := false
var charge_timer := 0.0

## 目前只有基礎 Dash，見 docs/SYSTEMS.md §1——還沒有任何位移類法術，「裝備位移法術時改走
## AoETargetingDelivery」那條分支留給之後真的有位移法術時再加（docs/FIRE_PROTOTYPE.md 的
## 「火焰撤離」節點可能會是第一個用到這條分支的法術）。
func _input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		dash_requested = true

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_process_buffs(delta)

	## instant_cast action（右鍵）2026-10-13 起不再是法術瞬發，改成專注狀態的進出開關——
	## 不管正在做什麼（移動/近戰/蓄力中）都能切換（符合 Fire Prototype §3「右鍵控制專注狀態
	## 的進入與退出」，沒有排除條件）。
	if Input.is_action_just_pressed("instant_cast"):
		_toggle_focus()

	if knockback_velocity.length() > 1.0:
		_process_knockback(delta)
		_update_sprite_animation()
		_update_sprite_tint(delta)
		return

	if is_focused:
		_process_focused(delta)
		if Input.is_action_just_pressed("cast_spell"):
			_cast_current_node()
		_update_sprite_animation()
		_update_sprite_tint(delta)
		return

	if dash_requested:
		dash_requested = false
		if not is_dashing:
			_start_dash()

	if combo_cooldown_timer > 0.0:
		combo_cooldown_timer -= delta
	if is_charging:
		charge_timer += delta

	if is_dashing:
		_process_dash(delta)
	else:
		_process_movement()

	_update_sprite_animation()
	_update_sprite_tint(delta)

	if Input.is_action_just_pressed("cast_spell") and not is_dashing:
		is_charging = true
		charge_timer = 0.0
	if Input.is_action_just_released("cast_spell") and is_charging:
		is_charging = false
		if charge_timer >= CHARGE_THRESHOLD:
			_fire_charged_fireball()
		elif combo_cooldown_timer <= 0.0:
			_perform_melee_hit()

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

## 右鍵切換進出專注狀態（docs/DEMO_PLAN.md Phase 1）。
func _toggle_focus() -> void:
	if is_focused:
		_exit_focus()
	else:
		_enter_focus()

## 進入時清空符文緩衝/中斷衝刺跟蓄力——專注狀態是一個乾淨的新開始，不會帶著「剛好按到
## 一半的蓄力」或「上一輪殘留的符文輸入」進來。current_node_id 永遠重置回圖譜起點
## （docs/DEMO_PLAN.md §6，見欄位宣告處的註解），不是沿用上次退出時停在哪個節點。
func _enter_focus() -> void:
	is_focused = true
	Engine.time_scale = FOCUS_TIME_SCALE
	is_dashing = false
	is_charging = false
	combo_buffer = ""
	pending_combo = ""
	current_node_id = current_graph.start_node_id
	node_changed.emit(current_node_id)

## 手動退出（右鍵再按一次）：Engine.time_scale 恢復正常，不觸發任何法術效果——「手動退出時
## 尚未施放的法術如何處理」是 docs/GDD.md §12 列的待定項，Phase 4 開工前才需要跟使用者
## 確認（docs/DEMO_PLAN.md §8），這裡先維持「不施放，單純退出」的行為。施放後退出走
## _cast_current_node() 自己呼叫這個函式，不是透過這條手動路徑。
func _exit_focus() -> void:
	is_focused = false
	Engine.time_scale = 1.0

## WASD 在專注狀態下不移動角色，改讀成符文輸入（_handle_rune_key()）；每個 frame 檢查
## pending_combo 的超時處理，跟舊系統 _process_casting() 的邏輯對稱，只是查表對象換了，
## 見 KNOWN_RUNES 欄位宣告處的註解。
func _process_focused(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	if combo_buffer.length() > 0:
		var elapsed := Time.get_ticks_msec() / 1000.0 - combo_last_input_time
		if pending_combo != "" and elapsed >= COMBO_MAX_GAP:
			_commit_rune(pending_combo)
		elif pending_combo == "" and elapsed > COMBO_MAX_GAP:
			_fail_combo()

	for action in DIR_KEYS.keys():
		if Input.is_action_just_pressed(action):
			_handle_rune_key(DIR_KEYS[action])

## 專注狀態下左鍵＝立即施放目前節點對應的法術並退出專注（docs/FIRE_PROTOTYPE.md §3：
## 「施法後退出專注，恢復正常時間」）。任何有效節點都可以是施法終點，不需要先抵達葉節點
## （docs/GDD.md §5.3）。
func _cast_current_node() -> void:
	var node: SpellGraphNode = current_graph.get_node_by_id(current_node_id)
	if node == null or node.spell == null or node.spell.delivery == null:
		return
	var stats := _base_stats(node.spell)
	var dir := (get_global_mouse_position() - global_position).normalized()
	node.spell.delivery.fire(self, dir, stats, node.spell.max_range, node.spell.base_effects)
	facing_direction = _direction_name(dir)
	sprite_animator.play_one_shot("cast_release_attack")
	_exit_focus()

## 近戰三連段的單次判定：朝滑鼠方向、距離+夾角判定（不靠物理形狀，複用舊 boss 吸引懲罰用過的
## 手法）命中 MELEE_RANGE 內、朝向 MELEE_HALF_ANGLE 夾角內的所有 "enemies" 群組成員。
## combo_stage 這個 phase 只負責循環（0→1→2→0），三段傷害/判定完全一樣，不做差異化演出
## （docs/DEMO_PLAN.md Phase 1 明確排除項目），之後要做連段加成/不同演出再從這裡擴充。
func _perform_melee_hit() -> void:
	var aim := (get_global_mouse_position() - global_position)
	var aim_dir := aim.normalized() if aim.length() > 0.01 else last_move_direction
	for target in get_tree().get_nodes_in_group("enemies"):
		if not target.has_method("take_damage"):
			continue
		var offset: Vector2 = target.global_position - global_position
		if GroundProjection.projected_length(offset) > MELEE_RANGE:
			continue
		if offset.length() > 0.01 and absf(aim_dir.angle_to(offset)) > MELEE_HALF_ANGLE:
			continue
		target.take_damage(MELEE_DAMAGE)
	combo_stage = (combo_stage + 1) % 3
	combo_cooldown_timer = MELEE_COOLDOWN
	facing_direction = _direction_name(aim_dir)
	sprite_animator.play_one_shot("cast_release_attack")
	MagicFX.spawn_burst(get_tree().current_scene, global_position + aim_dir * MELEE_RANGE * 0.5, Color(1, 0.6, 0.3), 10, 140.0)

## 蓄力火球：一般狀態下按住 cast_spell 超過 CHARGE_THRESHOLD 秒才放開觸發。docs/DEMO_PLAN.md
## 明講這個 phase 「先直接用 SpellProjectile.tscn+ProjectileDelivery 兜一顆最簡單的投射物即可，
## 不用等 Phase 2 的圖譜資料結構」——這裡沒有透過 Spell/SpellDelivery Resource，直接手動組一顆
## ExplosiveImpact 塞給 SpellProjectile.setup()，等 Phase 2/3 有了真正的 fire_graph.tres，
## 這顆「Basic 火球術」的實作會被圖譜節點的 Spell 資源取代，不是定案的最終做法。
func _fire_charged_fireball() -> void:
	var dir := (get_global_mouse_position() - global_position).normalized()
	var impact := ExplosiveImpact.new()
	impact.radius = CHARGED_FIREBALL_RADIUS
	var projectile_scene: PackedScene = load("res://scenes/spells/SpellProjectile.tscn")
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position
	projectile.setup(dir, CHARGED_FIREBALL_DAMAGE, CHARGED_FIREBALL_RANGE, CHARGED_FIREBALL_SPEED, impact)
	facing_direction = _direction_name(dir)
	sprite_animator.play_one_shot("cast_release_attack")

## 把一個方向向量轉成 PlayerSpriteAnimator 的 8 方向動畫鍵名（"down"/"down_right"/...），
## 用 45 度一格的八分儀判斷，0 度＝正右方（Godot 螢幕座標 y 正方向朝下，所以角度 90 度＝正下方）。
const DIRECTION_OCTANTS := ["right", "down_right", "down", "down_left", "left", "up_left", "up", "up_right"]
func _direction_name(dir: Vector2) -> String:
	var octant := int(round(dir.angle() / (PI / 4.0))) % 8
	if octant < 0:
		octant += 8
	return DIRECTION_OCTANTS[octant]

## 照目前狀態決定 sprite_animator 要播哪個動畫——純粹讀取現有狀態欄位做選擇，不持有自己的
## 狀態。法術釋放/受擊的一次性動畫不在這裡觸發（那兩個是事件觸發，見 _perform_melee_hit()/
## _fire_charged_fireball()/take_damage()），這裡呼叫 play_state() 即使在一次性動畫播放中
## 也會被忽略，播完後下一幀自動接回這裡算出的狀態。專注狀態／蓄力中都複用 cast_charge
## 循環動畫（兩者視覺上都是「蓄力/專注中」，這個 phase 不特別區分演出）。
func _update_sprite_animation() -> void:
	if is_focused or is_charging:
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

## 符文輸入判定：前綴比對永遠查全域的 KNOWN_RUNES，跟目前節點無關（見該常數宣告處的
## 註解）——這樣「要不要繼續等下一鍵」在所有節點手感一致，只有打出完整符文之後，才在
## _commit_rune() 裡去查目前節點是否真的有這條路。
func _handle_rune_key(key: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	if combo_buffer.length() > 0:
		var gap := now - combo_last_input_time
		if gap > COMBO_MAX_GAP:
			_fail_combo()
			return

	combo_last_input_time = now
	var attempt := combo_buffer + key

	var is_exact: bool = attempt in KNOWN_RUNES
	var has_longer_prefix := false
	for rune in KNOWN_RUNES:
		if rune.length() > attempt.length() and rune.begins_with(attempt):
			has_longer_prefix = true
			break

	if is_exact and not has_longer_prefix:
		_commit_rune(attempt)
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

## 打出一個完整合法的符文之後，才在這裡查目前節點是否真的有這條轉換路徑——查不到的話
## 玩家停在原節點（不是回到起點，也不是任何懲罰性的狀態），跟輸入錯誤鍵（_fail_combo()）
## 用同一套視覺回饋，因為對玩家來說兩者都是「這次輸入沒有造成任何改變」，不需要刻意區分
## 「鍵按錯」跟「鍵對但這招沒有這條路」（docs/DEMO_PLAN.md §6 這次拍板的設計）。
func _commit_rune(rune: String) -> void:
	combo_buffer = ""
	pending_combo = ""
	var node: SpellGraphNode = current_graph.get_node_by_id(current_node_id)
	if node != null and node.transitions.has(rune):
		current_node_id = node.transitions[rune]
		success_flash_timer = 0.2
		node_changed.emit(current_node_id)
		MagicFX.spawn_burst(get_tree().current_scene, global_position + Vector2(0, -24), Color.WHITE, 14, 160.0)
	else:
		_fail_combo()

## 給 scripts/SpellTestRange.gd 用的測試捷徑：跳過即時方向鍵輸入判定，直接視同一組合法符文
## 已經在這次吟唱中被觸發（也是 headless 環境下驗證圖譜轉換唯一能用的方式——headless 無法
## 模擬真實鍵盤輸入時序）。
func debug_force_rune(rune: String) -> void:
	_commit_rune(rune)

func _fail_combo() -> void:
	combo_buffer = ""
	pending_combo = ""
	fail_flash_timer = 0.3
	combo_failed.emit()
	MagicFX.spawn_burst(get_tree().current_scene, global_position + Vector2(0, -24), Color(0.3, 0.3, 0.3), 8, 90.0)

## 2026-10-13：舊的「按住 cast_spell 固定時長吟唱」系統（is_casting/cast_timer/
## _start_casting()/_cancel_casting()/_finish_casting()/_fire_spell()/_fire_instant_spell()）
## 整個移除——新戰鬥系統裡，左鍵在一般狀態下是近戰/蓄力火球（見 _perform_melee_hit()/
## _fire_charged_fireball()），在專注狀態下會是「立即施放目前節點法術」（Phase 2），兩者
## 都不是「按住累積一段固定時間」的概念，沒有對應物可以保留骨架。equipped_spell/
## equipped_spells 兩個欄位也跟著沒有用途了，但先不刪（之後符文圖譜可能需要類似概念）。
##
## _base_stats() 留著：從 Spell.base_effects 組出 stats dict 這個邏輯是通用的，
## docs/DEMO_PLAN.md Phase 2/3 讓玩家施放圖譜節點法術時會直接重用這個函式。
func _base_stats(spell: Spell) -> Dictionary:
	var stats := {"damage": 0.0}
	for effect in spell.base_effects:
		if effect.apply_mode == SpellEffect.ApplyMode.INSTANT:
			effect.apply(stats)
	return stats

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

## 死亡：停止移動/輸入（_physics_process()/_input() 開頭的 is_dead 檢查），不比照 Boss
## 歸零重置滿血——這是真正的死亡，交給 died 訊號的接收端顯示死亡畫面。順便把專注狀態/
## 子彈時間一起收掉，不然死在專注狀態中會卡在 0.25 倍速。
func _die() -> void:
	is_dead = true
	is_dashing = false
	is_focused = false
	is_charging = false
	Engine.time_scale = 1.0
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
