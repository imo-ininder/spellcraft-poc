class_name FurnaceGuardian
extends CharacterBody2D

## 熔爐守衛（Prototype Boss，見使用者提供的設計文件 v0.1）。Phase 1：
## Observe/Telegraph/Attack/Recovery 四狀態機 + 橫掃（Heavy Sweep）+ 熔岩重擊（Magma Slam）。
## 衝鋒（Furnace Charge，文件自己排的 Phase 5）這一輪刻意不做。
##
## 2026-10-13：玩家角色接進場景了，Observe 狀態改成真的會朝玩家移動/維持交戰距離，
## 選招那一刻會鎖定玩家當下的方向/位置（見 _lock_attack_target()）——之後 Telegraph/Attack
## 全程不再重新瞄準，這是刻意的：攻擊要能被「預判+走位閃開」，如果一路跟蹤到攻擊判定那一刻
## 才鎖定，玩家幾乎不可能閃掉，前搖期間的走位就沒有意義了。Observe 逼近時還會閃避玩家放在
## 地上的範圍法術（Phase 3，見 _hazard_avoidance_offset()），熔岩重擊前搖時核心會短暫暴露、
## 打中有傷害加成（Phase 4，見 _is_weak_point_exposed()）。
##
## 不跟 TestDummy.gd 共用任何東西（使用者明確要求不要被 dummy 的極簡風格影響）——TestDummy
## 是「純粹挨打的測試靶」，這是真正要驗證戰鬥節奏/讀招的 Boss，兩者的設計目標完全不同，長相
## /回饋強度本來就不該一樣。命中判定延續這個專案一路以來的慣例：不靠物理碰撞形狀，純距離/
## 角度數學（跟 Player 近戰/ExplosiveImpact/DamageZone 同一套手法），CharacterBody2D 自己的
## CollisionShape2D 只是給之後玩家投射物一個物理存在，不是攻擊判定本身。

enum State { OBSERVE, TELEGRAPH, ATTACK, RECOVERY }

## === 生命值 ===
const MAX_HP := 300.0
var hp := MAX_HP
var is_dead := false
signal hp_changed(ratio)
signal died

## === Phase 4（docs/BOSS_PROTOTYPE.md §6：弱點暴露）===
## 熔岩重擊前搖時胸口核心短暫暴露，這段期間打中的傷害有加成。文件自己說「第一版可以先讓
## 核心只是一個額外傷害判定」，所以不另外開一個只在這個窗口才啟用的小 Area2D 去精準判定
## 「有沒有打中核心那個小範圍」——簡化成：這段窗口內，不管投射物實際打在身體哪個像素，
## 一律算「打中暴露的核心」拿加成。之後如果要做更精細的版本，再補一個獨立的核心 Area2D。
const WEAK_POINT_DAMAGE_MULT := 1.5

func _is_weak_point_exposed() -> bool:
	return state == State.TELEGRAPH and current_attack == "slam"

func take_damage(amount: float) -> void:
	if is_dead:
		return
	var final_amount := amount
	if _is_weak_point_exposed():
		final_amount *= WEAK_POINT_DAMAGE_MULT
	hp = max(0.0, hp - final_amount)
	hazard_flash_timer = 0.2
	hp_changed.emit(hp / MAX_HP)
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(1, 0.7, 0.3), 14, 180.0)
	if hp <= 0.0:
		_die()

func _die() -> void:
	is_dead = true
	state = State.RECOVERY
	state_timer = 999999.0
	died.emit()

## 2026-10-14（使用者要求）：原地重生——`scripts/BossTestRange.gd` 把這個函式接到
## `died` 訊號，血量歸零後回到 `_ready()` 記錄的 `_spawn_position`、補滿血、重新進
## Observe。跟 Player.respawn() 同一次需求、同一個理由（見該函式註解）：這是測試場景
## 專屬行為，故意不寫進 _die() 本體。
func respawn() -> void:
	is_dead = false
	hp = MAX_HP
	global_position = _spawn_position
	velocity = Vector2.ZERO
	hazard_flash_timer = 0.0
	hp_changed.emit(1.0)
	_enter_observe()

## === 狀態機 ===
var state: State = State.OBSERVE
var state_timer := 0.0
var state_duration := 1.0 ## 目前這個狀態總共要花多久，跟 state_timer（剩餘時間）配合算進度比例，給前搖視覺用
var current_attack: String = "" ## "sweep" | "slam"
var facing_dir := Vector2.DOWN

## 短暫變色回饋（受擊），不是戰鬥核心邏輯，純視覺。
var hazard_flash_timer := 0.0

## Observe：朝玩家移動、維持 ENGAGE_RANGE 交戰距離（太遠就靠近，夠近就停下只轉面向）。
## 固定等滿 OBSERVE_DURATION 秒才選招，不是一進入交戰距離就立刻出手——給玩家一段「看得出
## Boss 正在觀察/逼近」的節奏感，不是一接近就被打。沒有玩家在場（_find_player() 找不到）
## 時退回原地等待，是給沒有玩家的場景（例如這支檔案最早落地時用的 BossTestRange）當保底，
## 不會因為找不到目標就整個卡住。
const OBSERVE_DURATION := 1.4
const ENGAGE_RANGE := 170.0 ## 近戰系攻擊才打得到，太遠先靠近
const MOVE_SPEED := 70.0    ## 追擊速度，刻意比玩家 SPEED(130) 慢，demo 階段先這樣，不是最終平衡
## 熔岩重擊鎖定的目標點離 Boss 最遠多遠，超過就夾限到這個距離（用 GroundProjection.clamp_to_radius，
## 跟這個 session 稍早修過的壓扁視角一致性問題同一套工具）——不然玩家站得老遠，重擊還是能跨半個
## 場地打中，不合理。
const SLAM_MAX_TARGET_DISTANCE := 260.0

var _attack_target_point := Vector2.ZERO ## 選招當下鎖定的世界座標目標點，Telegraph/Attack 全程不變

## 2026-10-13（使用者提出的設計問題）：地面系攻擊（熔岩重擊）本來就該用「玩家站的那個點」
## 精準判定，不用管身體多大；近戰揮擊/未來的直線衝鋒則該算進玩家的身體範圍，不是只有正中心
## 那一個像素點才算中——只加在 Sweep（跟之後的 Charge）這類「掃過一塊範圍」的攻擊上，Slam
## 刻意不用，兩種攻擊的判定哲學不一樣。
const PLAYER_HIT_RADIUS := 16.0

## === 橫掃（Heavy Sweep）：近距離寬扇形，一般攻擊 ===
## 2026-10-14（使用者實測回饋）：原本的前搖/硬直取文件建議區間中段，打起來偏「重」，使用者
## 要求改成距離更短、節奏更快的普攻手感——刻意跳出文件 §4.1 建議的 0.8–1.2s/0.8–1.5s 區間，
## 這是使用者明確要求的偏離，不是沒看文件。
const SWEEP_TELEGRAPH_DURATION := 0.6
const SWEEP_ATTACK_DURATION := 0.2     ## 判定/揮擊動畫本身的時間
const SWEEP_RECOVERY_DURATION := 0.7
const SWEEP_RANGE := 75.0
const SWEEP_HALF_ANGLE := 1.74         ## 約100度半角，總張角約200度，算「寬廣扇形」
const SWEEP_DAMAGE := 18.0
const SWEEP_KNOCKBACK := 500.0

## === 熔岩重擊（Magma Slam）：地面圓形範圍，強力攻擊 ===
const SLAM_TELEGRAPH_DURATION := 1.3   ## 文件建議 1.0–1.5s
const SLAM_ATTACK_DURATION := 0.25
const SLAM_RECOVERY_DURATION := 2.0    ## 文件建議「強力攻擊」1.5–2.5s
const SLAM_RADIUS := 170.0 ## 2026-10-14 使用者要求加大（原 130），地面系強力攻擊的範圍感要更明顯
const SLAM_DAMAGE := 26.0
const SLAM_KNOCKBACK := 350.0
## 命中當下留下的灼熱地面，見 BossMagmaGround.gd——文件 §4.2 流程第4步「命中區域短暫留下
## 灼熱地面」，獨立一支檔案，不跟玩家法術的 DamageZone.gd 共用（對象是 "player" 群組，不是
## "enemies"，概念上是完全不同方向的傷害來源，硬套會變成互相牽制）。
const GROUND_DAMAGE_PER_TICK := 5.0
const GROUND_TICK_INTERVAL := 0.5
const GROUND_DURATION := 2.5

## === 熔爐衝鋒（Furnace Charge）：直線突進，Phase 5 ===
## 跟橫掃/熔岩重擊不一樣——這招的判定不是 Telegraph 結束那一瞬間算完就好，是整個 Attack
## 狀態持續幾幀的「移動 + 每幀檢查有沒有撞到玩家」，所以需要自己的一組移動狀態變數
## （_charge_dir/_charge_traveled/_charge_hit_player），見 _process_charge_step()。
const CHARGE_TELEGRAPH_DURATION := 1.0  ## 文件建議 0.8–1.2s
const CHARGE_RECOVERY_DURATION := 2.2   ## 文件沒明講衝鋒的硬直，照「強力攻擊」1.5–2.5s 取值。
## 衝鋒結束（撞到人或跑滿距離）一律進 Recovery、velocity 清零站定——不管有沒有撞到人都走
## 同一個硬直（見 _enter_recovery()/_process_recovery()），「沒撞到人時原地停留製造破綻」
## 本來就是這個狀態機既有的行為，不需要額外分支。
const CHARGE_DISTANCE := 480.0 ## 2026-10-14 使用者要求拉長（原 320），讓衝鋒更有威脅、更能
## 追上風箏的玩家——跟上面同一次回饋，見 docs/BOSS_PROTOTYPE.md Phase 6 第一筆回饋記錄。
const CHARGE_SPEED := 420.0             ## 遠比 MOVE_SPEED(70) 快，才有「突進」的威脅感
const CHARGE_HALF_WIDTH := 44.0         ## 衝鋒路徑判定的半寬——是一條直線走廊，不是扇形
const CHARGE_DAMAGE := 22.0
const CHARGE_KNOCKBACK := 600.0

var _charge_dir := Vector2.ZERO
var _charge_traveled := 0.0
var _charge_hit_player := false

## 給 respawn() 用：場景裡擺放的初始位置，_ready() 當下記錄一次。
var _spawn_position := Vector2.ZERO

func _ready() -> void:
	add_to_group("enemies") ## 玩家法術已經是對 "enemies" 群組判定，這裡先掛上，之後接玩家互動時不用再補
	_spawn_position = global_position
	_enter_observe()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if hazard_flash_timer > 0.0:
		hazard_flash_timer -= delta
	state_timer -= delta
	match state:
		State.OBSERVE:
			_process_observe()
		State.TELEGRAPH:
			_process_telegraph()
		State.ATTACK:
			_process_attack(delta)
		State.RECOVERY:
			_process_recovery()
	queue_redraw()

## 0~1，目前這個狀態已經走了多少比例——前搖預覽的透明度/強度跟著這個漲，讓玩家感覺得到
## 「還有多久」，不是前搖一開始跟結束前一刻長得一樣突兀。
func _state_progress() -> float:
	if state_duration <= 0.0:
		return 1.0
	return clamp(1.0 - (state_timer / state_duration), 0.0, 1.0)

func _enter_observe() -> void:
	state = State.OBSERVE
	state_duration = OBSERVE_DURATION
	state_timer = OBSERVE_DURATION
	current_attack = ""

## 2026-10-13 修正：原本不管距離多遠，state_timer（固定 OBSERVE_DURATION）一到就出手，
## 結果玩家站得遠（例如一開場 300px），Boss 根本還沒走到 ENGAGE_RANGE 內就已經鎖定目標點
## 選招了——熔岩重擊雖然有 SLAM_MAX_TARGET_DISTANCE 夾限落點，但橫掃是純近戰，這樣會變成
## 「人明明在很遠的地方，Boss 卻對著空氣揮空」，讀起來不合理。改成：沒進 ENGAGE_RANGE 前
## 持續逼近、state_timer 照常倒數但不觸發選招；進了 ENGAGE_RANGE 之後 state_timer 多半已經
## 歸零，會立刻選招——逼近所花的時間本身就是「觀察／接近」的節奏感，不需要進了範圍後還要
## 再額外等。沒有玩家在場時退回原本「原地等滿固定時間」的保底行為。
## 2026-10-14（使用者實測發現：蓄力火球射程 500 遠超任何近戰距離、玩家移速 130 又比
## MOVE_SPEED(70) 快，純粹後退放火球可以讓 Boss 永遠進不了 ENGAGE_RANGE，整場選不到任何
## 攻擊——純風箏。使用者選擇的對策：讓熔爐衝鋒不受 ENGAGE_RANGE 限制，可以在交戰距離外被
## 選到，讓 Boss 有辦法對風箏做出反應，不是只能傻站著一路被追著跑；橫掃/熔岩重擊這兩招
## 維持原樣只能在交戰距離內選到，見 _choose_attack()）。
func _process_observe() -> void:
	var player := _find_player()
	if player == null:
		if state_timer <= 0.0:
			_choose_attack(0.0, true)
		return
	var offset: Vector2 = player.global_position - global_position
	if offset.length() > 0.01:
		facing_dir = offset.normalized()
	var distance := GroundProjection.projected_length(offset)
	var in_engage_range := distance <= ENGAGE_RANGE
	if in_engage_range:
		velocity = Vector2.ZERO
	else:
		var steer_dir := facing_dir
		var avoidance := _hazard_avoidance_offset()
		if avoidance != Vector2.ZERO:
			steer_dir = (steer_dir + avoidance * HAZARD_AVOID_WEIGHT).normalized()
		velocity = GroundProjection.projected_velocity(steer_dir, MOVE_SPEED)
		move_and_slide()
	if state_timer <= 0.0:
		_choose_attack(distance, in_engage_range)

## === Phase 3（docs/BOSS_PROTOTYPE.md §5：「火焰地面應該影響 Boss 移動路徑」）===
## 純 steering（往遠離危險區的方向推一把疊加到「朝玩家走」的方向上），不是真正的路徑規劃
## （A*/navmesh 對這個 demo 階段太重，而且場地目前也沒有任何靜態障礙物需要繞）。只有「正在
## 逼近玩家」的時候會閃，站定交戰距離內維持位置時不閃——這樣才看得出「Boss 真的在繞開我放的
## 範圍」，不是隨便亂飄。
const HAZARD_AVOID_MARGIN := 24.0  ## 範圍外再留一點緩衝，不要貼著邊緣走
const HAZARD_AVOID_WEIGHT := 1.6   ## 閃避力道相對「朝玩家走」的比重，越大繞得越明顯

func _hazard_avoidance_offset() -> Vector2:
	var push := Vector2.ZERO
	for zone in get_tree().get_nodes_in_group("player_hazard_zone"):
		if not is_instance_valid(zone):
			continue
		var zone_radius_value = zone.get("radius")
		var zone_radius: float = zone_radius_value if zone_radius_value != null else 0.0
		var avoid_radius: float = zone_radius + HAZARD_AVOID_MARGIN
		var offset: Vector2 = global_position - zone.global_position
		var dist := GroundProjection.projected_length(offset)
		if dist >= avoid_radius or avoid_radius <= 0.0:
			continue
		var strength: float = 1.0 - (dist / avoid_radius)
		push += (offset.normalized() if offset.length() > 0.01 else Vector2.UP) * strength
	return push

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if not players.is_empty() else null

## 鎖定這次攻擊要用的方向/目標點——有玩家就瞄準玩家「當下」的位置（之後不會再更新，見檔案
## 開頭註解的理由），沒有玩家就退回隨機方向（保底，不會卡住）。_choose_attack() 跟
## debug_force_attack() 共用，兩條路徑的鎖定邏輯要一致。
func _lock_attack_target() -> void:
	velocity = Vector2.ZERO
	var player := _find_player()
	if player != null:
		var offset: Vector2 = player.global_position - global_position
		if offset.length() > 0.01:
			facing_dir = offset.normalized()
		_attack_target_point = GroundProjection.clamp_to_radius(global_position, player.global_position, SLAM_MAX_TARGET_DISTANCE)
	else:
		facing_dir = Vector2.from_angle(randf() * TAU)
		_attack_target_point = global_position

## 三招等權重隨機（1/3 各一），跟使用者文件 §5 的核心規則一致：「Boss 不應被設計成只有某個
## 法術才能有效對付」——招式本身也不該有某一招被選到的機率特別低/高，不然玩家練習/應對的
## 機會不平均。
##
## in_engage_range＝false 時（2026-10-14，風箏對策）：橫掃/熔岩重擊都是近戰距離攻擊，
## 玩家根本不在範圍內選了也打不到，直接鎖定熔爐衝鋒——這是目前唯一能在交戰距離外使用、
## 真正會位移關上距離的招式。
##
## 2026-10-14（使用者實測發現：橫掃空揮）：ENGAGE_RANGE（170）跟橫掃實際判定距離
## （SWEEP_RANGE + PLAYER_HIT_RADIUS，改短之後只剩 91）對不上——玩家站在 92~170px 之間，
## Boss 一樣會停下來選招，橫掃卻完全搆不到人，照樣有機率被選到。熔岩重擊/熔爐衝鋒不會有
## 這個問題（重擊有 SLAM_MAX_TARGET_DISTANCE 夾限、衝鋒本來就有自己的遠距選招邏輯），
## 只有橫掃需要額外比對「選招當下的真實距離」是否真的在它自己的命中範圍內，不能只看
## 泛用的 ENGAGE_RANGE 夠不夠近——在 ENGAGE_RANGE 內但橫掃搆不到的距離，候選池直接不放
## 橫掃進去（這段距離只剩熔岩重擊／熔爐衝鋒二選一，不是永遠嚴格 1/3，但三招各自能不能被
## 選到本來就該看「這一招物理上打不打得到」，跟熔爐衝鋒本來就不嚴格 1/3 是同一個道理）。
func _choose_attack(distance: float, in_engage_range: bool) -> void:
	_lock_attack_target()
	if not in_engage_range:
		current_attack = "charge"
	else:
		var pool: Array[String] = ["slam", "charge"]
		if distance <= SWEEP_RANGE + PLAYER_HIT_RADIUS:
			pool.append("sweep")
		current_attack = pool[randi() % pool.size()]
	state = State.TELEGRAPH
	state_duration = _telegraph_duration_for(current_attack)
	state_timer = state_duration

func _telegraph_duration_for(attack: String) -> float:
	match attack:
		"sweep":
			return SWEEP_TELEGRAPH_DURATION
		"slam":
			return SLAM_TELEGRAPH_DURATION
		"charge":
			return CHARGE_TELEGRAPH_DURATION
	return SWEEP_TELEGRAPH_DURATION

func _recovery_duration_for(attack: String) -> float:
	match attack:
		"sweep":
			return SWEEP_RECOVERY_DURATION
		"slam":
			return SLAM_RECOVERY_DURATION
		"charge":
			return CHARGE_RECOVERY_DURATION
	return SWEEP_RECOVERY_DURATION

func _process_telegraph() -> void:
	if state_timer <= 0.0:
		_execute_attack()

func _execute_attack() -> void:
	state = State.ATTACK
	match current_attack:
		"sweep":
			_perform_sweep()
			state_duration = SWEEP_ATTACK_DURATION
		"slam":
			_perform_slam()
			state_duration = SLAM_ATTACK_DURATION
		"charge":
			_start_charge()
			state_duration = CHARGE_DISTANCE / CHARGE_SPEED  ## 粗估的時間上限，真正結束條件是
			## _charge_traveled 跑滿 CHARGE_DISTANCE（見 _process_attack()），這裡只是保底
			## 不要讓衝鋒因為撞牆/卡住之類的狀況無限卡在 Attack 狀態。
	state_timer = state_duration

## 衝鋒需要每幀持續移動+判定，跟橫掃/熔岩重擊「Telegraph 一結束就一次算完」不一樣，所以多一個
## delta 參數專門給 _process_charge_step() 用。
func _process_attack(delta: float) -> void:
	if current_attack == "charge":
		_process_charge_step(delta)
	if state_timer <= 0.0 or (current_attack == "charge" and _charge_traveled >= CHARGE_DISTANCE):
		_enter_recovery()

func _enter_recovery() -> void:
	velocity = Vector2.ZERO
	state = State.RECOVERY
	state_duration = _recovery_duration_for(current_attack)
	state_timer = state_duration

func _process_recovery() -> void:
	if state_timer <= 0.0:
		_enter_observe()

## === 攻擊判定：純距離/角度數學，不靠物理碰撞，跟 Player._perform_melee_hit() 同一套手法 ===
func _perform_sweep() -> void:
	for target in get_tree().get_nodes_in_group("player"):
		if not target.has_method("take_damage"):
			continue
		var offset: Vector2 = target.global_position - global_position
		if GroundProjection.projected_length(offset) > SWEEP_RANGE + PLAYER_HIT_RADIUS:
			continue
		if offset.length() > 0.01 and absf(facing_dir.angle_to(offset)) > SWEEP_HALF_ANGLE:
			continue
		target.take_damage(SWEEP_DAMAGE)
		if target.has_method("apply_knockback"):
			target.apply_knockback(offset.normalized() * SWEEP_KNOCKBACK)
	MagicFX.spawn_burst(get_tree().current_scene, global_position + facing_dir * SWEEP_RANGE * 0.6, Color(1, 0.4, 0.1), 24, 260.0)

func _perform_slam() -> void:
	var point := _attack_target_point
	for target in get_tree().get_nodes_in_group("player"):
		if not target.has_method("take_damage"):
			continue
		if GroundProjection.projected_distance(target.global_position, point) > SLAM_RADIUS:
			continue
		target.take_damage(SLAM_DAMAGE)
		if target.has_method("apply_knockback"):
			var offset: Vector2 = target.global_position - point
			target.apply_knockback((offset.normalized() if offset.length() > 0.01 else Vector2.UP) * SLAM_KNOCKBACK)
	MagicFX.spawn_burst(get_tree().current_scene, point, Color(1, 0.3, 0.05), 32, 300.0)
	MagicFX.spawn_explosion_ring(get_tree().current_scene, point, SLAM_RADIUS, Color(1, 0.35, 0.05), 0.4)

	var ground := BossMagmaGround.new()
	get_tree().current_scene.add_child(ground)
	ground.global_position = point
	## 2026-10-14 使用者要求：灼熱地面範圍要跟打擊範圍一樣大，原本故意縮一圈（* 0.8）取消。
	ground.setup(GROUND_DAMAGE_PER_TICK, GROUND_TICK_INTERVAL, GROUND_DURATION, SLAM_RADIUS)

func _start_charge() -> void:
	_charge_dir = facing_dir
	_charge_traveled = 0.0
	_charge_hit_player = false

## 每幀移動一步＋檢查有沒有撞到玩家——只在真正撞到的那一幀造成一次傷害（_charge_hit_player
## 擋掉後續重複判定，不然衝鋒整段路徑上每一幀都會重複命中，變成誇張的連續傷害）。判定用
## Boss「目前所在位置」跟玩家的距離，不是精確算一條線段的垂直距離——跟橫掃/熔岩重擊同一種
## 「整個身體範圍」的簡化判定哲學，衝鋒途中 Boss 身體本來就一直在移動，沒必要另外算線段距離。
func _process_charge_step(delta: float) -> void:
	var step_velocity := GroundProjection.projected_velocity(_charge_dir, CHARGE_SPEED)
	velocity = step_velocity
	move_and_slide()
	_charge_traveled += GroundProjection.projected_length(step_velocity * delta)
	if _charge_hit_player:
		return
	var player := _find_player()
	if player == null:
		return
	var offset: Vector2 = player.global_position - global_position
	if GroundProjection.projected_length(offset) > CHARGE_HALF_WIDTH + PLAYER_HIT_RADIUS:
		return
	player.take_damage(CHARGE_DAMAGE)
	if player.has_method("apply_knockback"):
		player.apply_knockback((offset.normalized() if offset.length() > 0.01 else _charge_dir) * CHARGE_KNOCKBACK)
	_charge_hit_player = true
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(1, 0.45, 0.1), 20, 240.0)

## === 畫法：狀態用顏色區分 ===
## Observe=灰藍（平靜）、Telegraph=橘紅漸強（警告）、Attack=白色閃光（命中瞬間）、
## Recovery=暗紫灰（硬直，露出破綻）——四個狀態一眼就能分辨，不需要看計時器數字。
##
## 2026-10-14：危險範圍預告（扇形/圓形/走廊）**不在這裡畫了**，拆到子節點
## `TelegraphPreview`（scripts/entities/boss/BossTelegraphPreview.gd）——原本畫在這支
## _draw() 裡，跟角色本體共用同一個 CanvasItem，Boss 進 Y-sort（見 scenes/BossTestRange.tscn
## 的 Entities 容器）之後，z_index 沒辦法只套用在同一個節點的部分畫面，預告被迫跟著角色
## 本體一起參與排序——Boss 選招時通常 Y 值比站在前面的玩家小，預告幾乎永遠被排到玩家後面，
## 不管視覺上延伸到玩家腳下多遠都蓋不過去。拆成獨立子節點、z_index 比照地面特效
## （DamageZone/BossMagmaGround）設定不受 Y-sort 影響，詳細理由見該檔案開頭註解。
func _draw() -> void:
	_draw_shadow()
	_draw_body()

func _draw_shadow() -> void:
	var shadow_points := PackedVector2Array()
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		shadow_points.append(Vector2(0, 18) + Vector2(cos(a) * 34.0, sin(a) * 14.0))
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.35))

func _body_color() -> Color:
	match state:
		State.OBSERVE:
			return Color(0.32, 0.3, 0.34)
		State.TELEGRAPH:
			return Color(0.32, 0.3, 0.34).lerp(Color(1.0, 0.35, 0.05), _state_progress())
		State.ATTACK:
			return Color(1, 1, 0.9)
		State.RECOVERY:
			return Color(0.4, 0.3, 0.45)
	return Color(0.32, 0.3, 0.34)

func _draw_body() -> void:
	var c := _body_color()
	if hazard_flash_timer > 0.0:
		c = c.lerp(Color(1, 1, 1), hazard_flash_timer / 0.2)
	# 厚重裝甲身軀：梯形肩膀+矩形軀幹，比一般角色大上一圈，符合「巨大守衛」的份量感。
	var body := PackedVector2Array([
		Vector2(-30, -80), Vector2(30, -80), Vector2(40, -40), Vector2(34, 10),
		Vector2(-34, 10), Vector2(-40, -40),
	])
	draw_colored_polygon(body, c)
	draw_polyline(body + PackedVector2Array([body[0]]), Color(0.1, 0.08, 0.08, 0.8), 3.0, true)
	# 胸口核心：持續發光的熔爐心臟，任何前搖都會讓它從橘漸變亮黃（泛用的「快出招了」提示）。
	var core_color: Color = Color(1.0, 0.5, 0.1).lerp(Color(1, 0.9, 0.3), _state_progress() if state == State.TELEGRAPH else 0.0)
	draw_circle(Vector2(0, -35), 10.0, core_color)
	draw_circle(Vector2(0, -35), 10.0 + sin(Time.get_ticks_msec() / 150.0) * 1.5, Color(core_color, 0.35))
	# 弱點暴露（Phase 4）：只有熔岩重擊前搖才加這一圈脈動白框，跟上面「任何前搖都會變亮」的
	# 泛用提示區分開——玩家要能一眼分辨「這次前搖是橫掃（沒有加成）」還是「這次是熔岩重擊
	# （這段時間打中有 1.5 倍加成，核心外露）」，不是靠猜。
	if _is_weak_point_exposed():
		var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 90.0)
		draw_arc(Vector2(0, -35), 17.0, 0.0, TAU, 28, Color(1, 1, 1, pulse), 2.5, true)
	# 面向指示：一個朝 facing_dir 的小三角，確認扇形攻擊真的跟著這個方向轉。
	var nose := Vector2(0, -35) + facing_dir * 14.0
	draw_circle(nose, 4.0, Color(1, 1, 1, 0.8))

## === 除錯用：手動指定下一招，不用等隨機選到才能測試特定攻擊 ===
func debug_force_attack(attack_name: String) -> void:
	if state != State.OBSERVE:
		return
	_lock_attack_target()
	current_attack = attack_name
	state = State.TELEGRAPH
	state_duration = _telegraph_duration_for(attack_name)
	state_timer = state_duration

func debug_state_text() -> String:
	return "%s (%s) %.2fs/%.2fs" % [State.keys()[state], current_attack, max(state_timer, 0.0), state_duration]
