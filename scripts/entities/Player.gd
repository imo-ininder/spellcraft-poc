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
## 2026-10-13：0.15 太短，使用者實測覺得符文輸入視窗抓太緊，拉長到 0.35（demo 階段示範值，
## 還可以再調）。
const COMBO_MAX_GAP := 0.35
## Dash 是短時間內的高速衝刺，不是瞬移（Blink）——用 move_and_slide() 讓它跟一般移動一樣貼牆滑行，
## 不是 move_and_collide() 那種單次跳到終點。DASH_DISTANCE 是設計意圖（原本 220px，2026-10-12
## 使用者要求改成 50px），DASH_DURATION 維持不變。
##
## 2026-10-13：原本直接 `const DASH_SPEED := 50.0/DASH_DURATION`，`velocity = dash_direction
## * DASH_SPEED`——使用者指出這是系統性問題：純世界座標的 `方向 * 純量`，在壓扁視角（Y軸
## 壓縮）下往垂直方向衝刺，視覺上移動的距離會比往水平方向衝刺明顯短。改成在 _start_dash()
## 当下用 GroundProjection.offset_towards(dash_direction, DASH_DISTANCE) 算出「不管往哪個
## 方向，視覺/判定距離都是 DASH_DISTANCE」的世界座標位移向量，再除以 DASH_DURATION 變成
## 這次衝刺要用的速度——所以不能再是 const 了（跟方向有關，每次衝刺都要重算一次）。
const DASH_DURATION := 0.12
const DASH_DISTANCE := 50.0
var dash_velocity := Vector2.ZERO

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

## === Phase 6（docs/DEMO_PLAN.md §10）：火焰護盾 ===
## ShieldSpell.cast() 直接呼叫 start_shield() 寫這兩個欄位，不經過 active_buffs/SpellEffect
## 那套（那是給「同一時間可能疊加多種不同 buff」設計的，火焰護盾目前是唯一的自身防護類法術，
## 不需要那層通用性）。take_damage()/take_dot_damage() 都會套用 shield_damage_mult。
## 「對攻擊自己的敵人造成火焰傷害」（docs/FIRE_PROTOTYPE.md §6.3 提到的反傷效果）這次沒做——
## take_damage() 目前不知道攻擊者是誰，要做反傷得幫近戰/兩種投射物/DamageZone 全部呼叫點加上
## 攻擊者參數，範圍超出這次，使用者 review 規劃時同意先跳過，只做減傷。
var shield_timer := 0.0
var shield_damage_mult := 1.0

func start_shield(duration: float, damage_mult: float) -> void:
	shield_timer = duration
	shield_damage_mult = damage_mult

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

## === Phase 6（docs/DEMO_PLAN.md §10）：火焰撤離專用位移 ===
## 2026-10-13：使用者明確要求不要重用 apply_knockback()（力道+摩擦力衰減）或 Dash，即使
## 「短暫位移＋move_and_slide() 貼牆滑行」看起來很像——這個專案這階段已經講過好幾次，每把
## 法術的運行邏輯該各自獨立，不要因為形狀相似就借用別的系統，所以這裡是完全獨立的一組
## 狀態/計時器，固定速度（不是力道衰減），時間到準確停在目標距離。
var is_retreating := false
var retreat_timer := 0.0
var retreat_velocity := Vector2.ZERO
const RETREAT_DURATION := 0.18

## distance 是「投影後／視覺上看起來的距離」，不是世界座標位移量——2026-10-13 系統性修正：
## 原本直接 `direction.normalized() * (distance/RETREAT_DURATION)`，往垂直方向撤離時實際
## 移動的視覺距離會比水平方向短（壓扁視角，見 GroundProjection.offset_towards() 註解）。
## 呼叫端（FireRetreatSpell.cast()）算身後軌跡位置/長度時也要用同一個函式重算一次世界座標
## 位移量，不能假設跟這裡用的是同一份（兩邊各自呼叫純函式，結果保證一致，不是共用一份狀態）。
func start_retreat(direction: Vector2, distance: float) -> void:
	is_retreating = true
	retreat_timer = RETREAT_DURATION
	retreat_velocity = GroundProjection.offset_towards(direction, distance) / RETREAT_DURATION

func _process_retreat(delta: float) -> void:
	retreat_timer -= delta
	velocity = retreat_velocity
	move_and_slide()
	if retreat_timer <= 0.0:
		is_retreating = false
		velocity = Vector2.ZERO

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
## 右鍵（instant_cast action）2026-10-13 四次修正：改回開關式（按一下進、再按一下取消），
## 不是按住/放開——使用者實測按住的手感「蠻彆扭」。完整邏輯：
## 1. 左鍵蓄力到 CHARGE_THRESHOLD（「可以放出 basic 法術」的那一刻）之後，右鍵才有效。
## 2. 按右鍵（press）進入專注狀態，世界時間跟著縮放（子彈時間，不是真的暫停——數值沿用舊
##    法術輪盤用過的 0.25，見 docs/SYSTEMS.md）。
## 3. 專注狀態中 WASD 符文輸入邏輯不變（見 KNOWN_RUNES／_process_focused()）。
## 4. 專注狀態中再按一次右鍵（press）＝取消，不施放任何法術，直接退出。
## 5. 只有在左鍵「放開」的那一刻才會施放目前節點的法術，施放完畢專注狀態跟著結束——左鍵從
##    蓄力開始到這裡必須全程按著沒放開，放開這個動作本身才是出招的觸發點，右鍵全程只負責
##    開關子彈時間，不負責出招。
var is_focused := false
const FOCUS_TIME_SCALE := 0.25

## === Phase 4（docs/DEMO_PLAN.md §8）：專注值資源 ===
## 進專注持續消耗，離開（不管手動取消還是耗盡）就停止消耗、隨時間回滿。全部是佔位值。
## 消耗用「真實未縮放的秒數」量測，不是 _physics_process() 收到的 delta（那個已經被
## Engine.time_scale 縮放過了）——這樣「能撐幾秒」是用現實時間量測，不會因為子彈時間倍率
## 調整就跟著變長/變短。這點 Fire Prototype 文件沒有明講，是這次補上的設計選擇，覺得不對
## 可以改成用縮放後的 delta（讓子彈時間越慢，専注撐得越久，是另一種合理設計）。
const FOCUS_MAX := 5.0
const FOCUS_DRAIN_PER_SEC := 1.0
const FOCUS_REGEN_PER_SEC := 1.5
var focus_value := FOCUS_MAX

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

## 基礎 Dash 見 docs/SYSTEMS.md §1。火焰撤離（Phase 6）最後沒有走 AoETargetingDelivery 或
## 重用 Dash，是獨立一套位移（見 start_retreat()/_process_retreat()），這裡原本預留的那條
## 分支沒有用到，已經拿掉。
func _input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		dash_requested = true

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_process_buffs(delta)

	## 不管正在做什麼（專注/被擊退/撤離中）都照常倒數，不要讓進專注之類的狀態變相延長護盾
	## 持續時間。
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			shield_damage_mult = 1.0

	## 開關式右鍵，見上面 is_focused 欄位宣告處的完整邏輯說明。進專注之後 is_charging 被
	## _enter_focus() 清掉（這份蓄力已經「用掉」），但 Input 的 just_released 判定讀的是
	## 引擎自己追蹤的按鍵狀態、不是我們自己的 is_charging 變數，所以就算 is_charging 已經
	## 被清成 false，左鍵真正放開時 is_action_just_released("cast_spell") 還是能正確偵測到。
	if is_focused:
		if Input.is_action_just_pressed("instant_cast"):
			_exit_focus() ## 取消，不施放
		elif Input.is_action_just_released("cast_spell"):
			_cast_current_node() ## 施放目前節點，內部會呼叫 _exit_focus() 收尾
	## Phase 4：除了左鍵蓄力到位，還要 focus_value > 0 才能進——避免剛好耗盡、還沒回一點點
	## 就馬上又能進去，進去立刻又被下面的耗盡判定強制出招，變成無意義的空轉。
	elif Input.is_action_just_pressed("instant_cast") and is_charging and charge_timer >= CHARGE_THRESHOLD and focus_value > 0.0:
		_enter_focus()

	if knockback_velocity.length() > 1.0:
		_process_knockback(delta)
		_update_sprite_animation()
		_update_sprite_tint(delta)
		return

	if is_retreating:
		_process_retreat(delta)
		_update_sprite_animation()
		_update_sprite_tint(delta)
		return

	if is_focused:
		_process_focused(delta)
		_process_focus_drain(delta)
		_update_sprite_animation()
		_update_sprite_tint(delta)
		return

	if focus_value < FOCUS_MAX:
		focus_value = min(FOCUS_MAX, focus_value + FOCUS_REGEN_PER_SEC * delta)

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
	## 見 DASH_DISTANCE 欄位宣告處註解：方向相關，每次衝刺重算一次，不能是 const。
	dash_velocity = GroundProjection.offset_towards(dash_direction, DASH_DISTANCE) / DASH_DURATION
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(0.6, 0.8, 1.0), 16, 200.0)

## 跟一般移動一樣用 move_and_slide()，貼牆會自然滑行、停下，不是瞬間跳到終點（那是 Blink，不是 Dash）。
func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = dash_velocity
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

## 退出專注的出口，兩條路徑都會走到這裡：① 專注中再按一次右鍵＝取消，不施放任何法術，
## 直接呼叫這個函式；② 左鍵放開＝施放，_cast_current_node() 施放完目前節點之後呼叫這個
## 函式收尾。is_charging/charge_timer 其實進專注那一刻就已經被 _enter_focus() 清過一次了，
## 這裡重置是保險，但也確保「取消」這條路徑不會把蓄力殘留帶回一般狀態（不然取消後左鍵
## 還握著，之後放開會意外又在一般狀態觸發一次蓄力火球）。
func _exit_focus() -> void:
	is_focused = false
	Engine.time_scale = 1.0
	is_charging = false
	charge_timer = 0.0

## 每個 physics frame 在專注狀態下呼叫：把 delta 換算回真實秒數（見 FOCUS_MAX 欄位宣告處的
## 註解）扣 focus_value，耗盡時強制施放目前節點並退出——跟左鍵放開是同一個出口
## （_cast_current_node()，內部會呼叫 _exit_focus()），玩家耗盡資源時不會被晾在原地，
## 一定會有個結果（施放），不是單純被踢出專注狀態。Engine.time_scale 理論上不會是 0（最小
## 就是 FOCUS_TIME_SCALE=0.25），這裡還是防一下除以 0。
func _process_focus_drain(delta: float) -> void:
	var real_delta: float = delta / Engine.time_scale if Engine.time_scale > 0.0 else delta
	focus_value = max(0.0, focus_value - FOCUS_DRAIN_PER_SEC * real_delta)
	if focus_value <= 0.0:
		_cast_current_node()

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

## 左鍵放開＝立即施放目前節點對應的法術並退出專注（docs/FIRE_PROTOTYPE.md §3：
## 「施法後退出專注，恢復正常時間」）。2026-10-13 四次修正：出招鍵從右鍵改成左鍵——右鍵
## 現在純粹是開關子彈時間，不負責出招，見 is_focused 欄位宣告處的完整邏輯說明。進專注的
## 「門票」（左鍵蓄力到 CHARGE_THRESHOLD）在按右鍵那一刻就審過了，這裡不用再檢查一次。
## 任何有效節點都可以是施法終點，不需要先抵達葉節點（docs/GDD.md §5.3）。_exit_focus()
## 永遠執行，就算節點沒有可施放的法術（null 檢查）——左鍵放開這個動作本身就是「結束子彈
## 時間」，不能因為節點沒配法術就卡在專注狀態裡出不來。
func _cast_current_node() -> void:
	var node: SpellGraphNode = current_graph.get_node_by_id(current_node_id)
	if node != null and node.spell != null:
		var dir := (get_global_mouse_position() - global_position).normalized()
		node.spell.cast(self, dir)
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

## 蓄力火球：一般狀態下按住 cast_spell 超過 CHARGE_THRESHOLD 秒才放開觸發。這裡沒有透過
## Spell/ProjectileSpell Resource，直接手動組一顆 ExplosiveImpact 塞給
## FireballProjectile.setup()（跟圖譜節點「basic」用的是同一支投射物類別，兩邊長相/飛行物理
## 一致），不是定案的最終做法——概念上是同一把火球術，但目前各自獨立觸發，還沒有真的共用
## 同一份 `.tres`。
func _fire_charged_fireball() -> void:
	var dir := (get_global_mouse_position() - global_position).normalized()
	var impact := ExplosiveImpact.new()
	impact.radius = CHARGED_FIREBALL_RADIUS
	var projectile := FireballProjectile.new()
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
## 2026-10-13 Phase 3：原本這裡還有一個 _base_stats()，從 Spell.base_effects 組出 stats
## dict 給 _cast_current_node() 用——Phase 3 把 SpellDelivery/SpellEffect 那套通用組合換成
## 每個 Spell 子類別自己的 cast()（見 scripts/spells/Spell.gd 開頭註解），stats dict 這個
## 中間層不需要了，_base_stats() 跟著刪除。

func take_damage(amount: float) -> void:
	if is_dead:
		return
	var final_amount: float = amount * shield_damage_mult if shield_timer > 0.0 else amount
	hp = max(0.0, hp - final_amount)
	hazard_flash_timer = 0.25
	hp_changed.emit(hp / MAX_HP)
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(1, 0.5, 0.1), 10, 150.0)
	sprite_animator.play_one_shot("hurt")
	if hp <= 0.0:
		_die()

## 安靜扣血（DamageZone.gd 的 DOT 模式用，跟 TestDummy.gd 的同名函式同一個理由：持續燃燒
## 傷害不該每 tick 都觸發完整的受擊反應——沒有 hazard_flash/MagicFX 爆裂/hurt 動畫，只扣血、
## 更新血量 UI、死亡時照常走 _die()。護盾減傷（shield_damage_mult）兩個入口都套用，持續
## 傷害不該因為走安靜扣血這條路就繞過防禦力。
func take_dot_damage(amount: float) -> void:
	if is_dead:
		return
	var final_amount: float = amount * shield_damage_mult if shield_timer > 0.0 else amount
	hp = max(0.0, hp - final_amount)
	hp_changed.emit(hp / MAX_HP)
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
	is_retreating = false
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
