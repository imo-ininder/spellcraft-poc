class_name Boss
extends StaticBody2D

## Demo boss：遠程型法師，核心哲學是「盡量保持距離、靠魔法消耗玩家」，不是迎面肉搏的怪物。
## 取代舊的 TargetDummy（起跳+範圍落地），見 docs/BOSS_DESIGN.md。怪物招式不走
## Spell/SpellDelivery/SpellEffect 架構（跟玩家討論過），直接把狀態機/數值寫在這個腳本裡，
## 不掛進 GameState.CATALOG。
##
## 血量/死亡這次刻意不碰：take_damage() 扣到0還是重置滿血+閃光，跟舊 TargetDummy 的佔位行為
## 完全一樣，是下一輪才要討論的範圍。這次新增的「真正會讓東西消失」的血量只有分身的3HP。
##
## 場地改成內圈玩家場地＋外圈boss環道、中間隔一圈淨空縫隙之後（見 Arena.gd），boss跟玩家
## 物理上永遠碰不到面——走位邏輯也整個換掉：不再是「以玩家為中心保持距離」，是「在外圈固定
## 軌道上巡邏」（位置＝場地中心 + 方向(track_angle)*BOSS_TRACK_RADIUS，不理會玩家在哪），
## 施法時（前搖/連發/讀氣）才停下來，放完再繼續繞。
##
## 巡邏本身不是連續緩慢繞圈，是「停頓→快速跳位80度→停頓→再跳」的頓挫節奏：停頓
## PATROL_PAUSE_TIME 秒，接著用 PATROL_MOVE_TIME 秒（刻意很短）快速移動 PATROL_MOVE_ANGLE
## （80度）到下一個定點，角度用 ease-out 插值讓這段移動有「快速衝出去、尾段收斂」的動感，
## 不是等速。見 _process_patrol()。分身的巡邏角度每幀都是「本體角度+固定偏移」（見
## _sync_clone_formation()），不需要自己另外維護一套停頓/跳位的計時狀態，本體這段頓挫節奏
## 會自動原封不動地同步反映到所有分身身上。
##
## 三種招式，定位完全不同：
## - 火球雨／光球連擊：兩個「遠程消耗」招式，`next_attack` 50/50 隨機，不需要額外走位——
##   boss固定在環道上，攻擊本身負責跨越縫隙打到玩家。
## - 吸引懲罰：不是這兩個的平行選項，是「玩家欺身太近」時的個體反射動作——本體或任一分身
##   只要有人被玩家貼到 SUCTION_TRIGGER_RANGE 以內，就由那一位（不是全體）觸發，把玩家拉近
##   後給一記重擊再彈飛。改成固定軌道場地之後，boss/分身跟玩家之間永遠隔著縫隙，這招理論上
##   不會再被觸發到了（縫隙寬度通常大於觸發距離），但還是保留整套邏輯，只是用 SUCTION_ENABLED
##   =false 關掉（只擋觸發判定這一步），之後如果場地數值調整到會重疊，隨時可以打開。
##
## 分身術 CD（5秒，開場前 CLONE_SUMMON_OPENING_GRACE=15 秒完全不能用）跟週期招式 CD（7秒）
## 獨立計算、互不暫停。分身術永遠優先於週期招式：
## 閒置等待中（IDLE）分身術轉好就立刻插隊；週期招式執行中轉好的話，等招式完全結束、
## 再等 1 秒緩衝（CLONE_SUMMON_BUFFER），才開始分身術讀氣——不會打斷正在執行中的招式。
## 分身數量是逐批累加到上限（CLONE_MAX=4隻分身，連本體一起算總共最多5個會行動的個體），
## 不是一次性的「本體+2分身」三角陣型——每次分身術只多召喚 CLONE_SUMMON_BATCH(2) 隻，直到
## 總數觸頂；分身越多，整群（含本體）的巡邏速度越快（SPEED_PER_CLONE 疊加），呼應「分身越多、
## 壓力越大」的曲線。讀氣召喚新分身期間，本體跟既有分身都會停下來，分身還會一起亮起「假裝在
## 讀氣」的光環（實際上只有本體真的在讀氣、真的會生出東西，分身只是視覺上假裝同步施法，
## 見 _start_clone_summon()）。分身也在外圈環道上巡邏，跟本體錯開角度分散站（見
## _sync_clone_formation()），不是繼續圍著玩家——玩家現在是物理上搆不到的，圍著玩家站沒意義。

const MAX_HP := 200.0
const KNOCKBACK_FRICTION := 900.0

const CLONE_HP := 3.0
const CLONE_MAX := 4 # 這是「分身」數量上限，不是總數——本體+分身加起來最多5個，所以分身上限要扣掉本體自己這1個
const CLONE_SUMMON_BATCH := 2 # 每次分身術只多召喚這麼多隻，不是一次補滿上限
const CLONE_SUMMON_CD := 5.0
const CLONE_SUMMON_OPENING_GRACE := 15.0 # 開場前這段時間完全不能用分身術，不是一進場就分身
const CLONE_SUMMON_CHANNEL := 4.0
const CLONE_SUMMON_INTERRUPT_THRESHOLD := 10.0
const CLONE_READY_BUFFER := 1.0

const ATTACK_CD := 7.0

const FIREBALL_TELEGRAPH_DELAY := 0.5
const FIREBALL_DAMAGE := 10.0

const ORB_COUNT := 3 # 每個施法者一次連續丟幾顆光球
const ORB_THROW_INTERVAL := 0.3 # 同一個施法者前後兩發光球的間隔，營造「連續節奏」感
const ORB_CASTER_STAGGER := 0.25 # 有分身時，第一個施法者丟出第一顆之後，隔這麼久下一個才開始丟自己的連擊——不是全體同時開火
const ORB_DAMAGE := 12.0

## 「太近懲罰」：不是週期招式輪盤裡的選項，是玩家欺身過近時的個體反射動作，見上方說明。
## 先關掉（SUCTION_ENABLED=false），之後可能會再打開，整套邏輯/場景/Player擊退都刻意保留，
## 不要因為暫時關掉就動手刪程式碼。
const SUCTION_ENABLED := false
const SUCTION_RANGE := 200.0 # 只要比 SUCTION_TRIGGER_RANGE 稍微長一點就夠，太長(一度拉到320)反而不像「貼身懲罰」
const SUCTION_HALF_ANGLE := 0.35 # 約20度，共40度張角——原本45度(90度張角)改窄很多，只懲罰正對著欺身的玩家，不是整圈都中
const SUCTION_TRIGGER_RANGE := 170.0 # 進入這個距離開始有機會觸發，不是一進來就保證觸發，見 _roll_for_suction_trigger()
const SUCTION_TRIGGER_CHANCE_PER_SEC := 3.0 # 貼到最近（距離=0）時的每秒觸發機率密度，距離越遠線性衰減到0
const SUCTION_TELEGRAPH_DELAY := 0.4 # 觸發後的小動畫/預警時間，扇形先畫外框不拉扯，過了才真正啟動
const SUCTION_CLOSE_RANGE := 70.0 # 玩家被拉到離施法者這麼近，立刻觸發大傷害+擊退，招式提前結束
const SUCTION_BURST_DAMAGE := 25.0
const SUCTION_KNOCKBACK_DISTANCE := 260.0 # 擊退要走完的總距離，實際套用的是反推出來的初速（見 _resolve_suction_punish()），不是瞬移的目標點
const SUCTION_KNOCKBACK_FRICTION := 900.0 # 要跟 Player.gd 的 KNOCKBACK_FRICTION 保持一致，下面反推初速時數學才會準
const SUCTION_SLOW := 0.5
const SUCTION_PULL_SPEED := 100.0
const SUCTION_DURATION := 3.0 # 給玩家一段時間可能逃脫，不是無限等到拉近為止
const SUCTION_EARLY_CANCEL_WINDOW := 0.5 # 連續這麼久沒拉到玩家就提前取消，全程持續監控，不是只在開場判定一次

## 固定軌道巡邏：跟舊版「以玩家為中心保持距離」完全不同的走位哲學——boss 不理會玩家在哪，
## 單純沿著 Arena.BOSS_TRACK_RADIUS 這個固定半徑、以「停頓→快速跳位→停頓」的頓挫節奏移動，
## track_angle 是目前巡邏到的角度（跳位過程中是插值中間值，不是只有到站那一刻才更新）。
const PATROL_PAUSE_TIME := 0.9 # 每次跳位之間停頓的秒數；每多一個分身疊加 SPEED_PER_CLONE 縮短
const PATROL_MOVE_ANGLE := deg_to_rad(80.0) # 每次跳位轉動的角度，不是連續緩慢繞圈
const PATROL_MOVE_TIME := 0.22 # 跳位本身的動畫時間，刻意很短，製造「移動很快」的感覺
const SPEED_PER_CLONE := 0.1 # 每多一個分身，整群（含本體）的停頓時間縮短 10%，疊加分身數量，不是固定值

enum BossState { IDLE, CLONE_SUMMON_BUFFER, CASTING_CLONE_SUMMON, ATTACK_FIREBALL, ATTACK_ORB_BARRAGE, ATTACK_SUCTION }
enum AttackChoice { FIREBALL, ORB_BARRAGE }

var hp := MAX_HP
var flash_timer := 0.0
var squash := 1.0
var idle_bob := 0.0
var knockback_velocity := Vector2.ZERO

## 閒置時不是真的「閒置」，是持續沿外圈固定軌道巡邏（track_angle 持續增加），讀氣/出招時
## 才停下。由 _set_wandering() 統一開關本體跟分身（分身自己也有同一套邏輯，見 BossClone.gd，
## 是複製的一份，不是共用呼叫）。
var is_wandering := true
var track_angle := 0.0
## 「停頓→跳位80度→停頓」節奏的狀態：is_patrol_moving=false 時在倒數停頓，true 時在倒數
## 跳位動畫（patrol_from_angle→patrol_to_angle 之間插值）。is_wandering=false（施法中）時
## _process_patrol() 整個不會被呼叫，這兩個計時器會原地凍結，恢復巡邏時從凍結的進度接著走。
var is_patrol_moving := false
var patrol_phase_timer := 0.0
var patrol_from_angle := 0.0
var patrol_to_angle := 0.0
var next_attack: AttackChoice = AttackChoice.FIREBALL

var state: BossState = BossState.IDLE
var attack_cd_timer := ATTACK_CD
var clone_cd_timer := CLONE_SUMMON_OPENING_GRACE # 開場要等這段時間才第一次就緒，不是一進場就能分身
var has_clones := false
var clones: Array = []
var buffer_timer := 0.0
var channel_timer := 0.0
var channel_damage_taken := 0.0
var is_channeling_clone_summon := false

signal hp_changed(ratio)

func _ready() -> void:
	add_to_group("enemies")
	next_attack = AttackChoice.FIREBALL if randf() < 0.5 else AttackChoice.ORB_BARRAGE
	track_angle = randf() * TAU
	patrol_phase_timer = PATROL_PAUSE_TIME

func take_damage(amount: float) -> void:
	if state == BossState.CASTING_CLONE_SUMMON:
		channel_damage_taken += amount
		if channel_damage_taken >= CLONE_SUMMON_INTERRUPT_THRESHOLD:
			_interrupt_clone_summon()
	hp = max(0.0, hp - amount)
	flash_timer = 0.15
	hp_changed.emit(hp / MAX_HP)
	_spawn_damage_label(amount)
	_bounce()
	queue_redraw()
	if hp <= 0.0:
		hp = MAX_HP
		hp_changed.emit(1.0)

func apply_knockback(force: Vector2) -> void:
	knockback_velocity += force

func _bounce() -> void:
	squash = 1.35
	var tween := create_tween()
	tween.tween_property(self, "squash", 1.0, 0.25).set_trans(Tween.TRANS_ELASTIC)

func _spawn_damage_label(amount: float) -> void:
	var label := Label.new()
	label.text = str(int(amount))
	label.position = Vector2(randf_range(-10, 10), -50)
	label.modulate = Color(1, 0.8, 0.2)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
	idle_bob += delta * 2.0
	if clone_cd_timer > 0.0:
		clone_cd_timer = max(0.0, clone_cd_timer - delta)
	_process_ai(delta)
	if is_wandering:
		_process_patrol(delta)
	# _sync_clone_formation() 不掛在 is_wandering 底下：即使本體這一幀沒在動，分身的巡邏角度
	# 目標還是要持續算好、隨時可用，不會因為本體恰好停下來就卡在舊資料。
	if has_clones:
		_sync_clone_formation()
	if knockback_velocity.length() > 1.0:
		global_position += knockback_velocity * delta
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		knockback_velocity = Vector2.ZERO
	# 固定軌道巡邏本身永遠落在環道範圍內（track_angle算出來的位置就是BOSS_TRACK_RADIUS，
	# 一定在[BOSS_RING_INNER_RADIUS, ARENA_RADIUS]之間），這裡的夾限主要是防止被擊退
	# （apply_knockback，例如玩家的力場波打中boss）之後飄出環道範圍。
	_clamp_to_arena()
	queue_redraw()

func _clamp_to_arena() -> void:
	var offset: Vector2 = global_position - Arena.ARENA_CENTER
	var dist := offset.length()
	if dist > Arena.ARENA_RADIUS:
		global_position = Arena.ARENA_CENTER + offset.normalized() * Arena.ARENA_RADIUS
	elif dist < Arena.BOSS_RING_INNER_RADIUS and dist > 0.1:
		global_position = Arena.ARENA_CENTER + offset.normalized() * Arena.BOSS_RING_INNER_RADIUS

## 固定軌道巡邏：不理會玩家在哪，沿著 Arena.BOSS_TRACK_RADIUS 這個固定半徑、以「停頓→快速
## 跳位80度→停頓」的頓挫節奏移動，不是連續勻速繞圈。跳位本身用 ease-out 插值（快速衝出去、
## 尾段收斂），不是等速直線插值，動作才會有「很快」的感覺，不是只是「比較快的勻速」。
func _process_patrol(delta: float) -> void:
	var speed_scale: float = 1.0 + SPEED_PER_CLONE * float(clones.size())
	patrol_phase_timer -= delta
	if is_patrol_moving:
		if patrol_phase_timer <= 0.0:
			track_angle = patrol_to_angle
			is_patrol_moving = false
			patrol_phase_timer = PATROL_PAUSE_TIME / speed_scale
		else:
			var t: float = 1.0 - clamp(patrol_phase_timer / PATROL_MOVE_TIME, 0.0, 1.0)
			t = 1.0 - pow(1.0 - t, 3.0) # ease-out cubic
			track_angle = lerp_angle(patrol_from_angle, patrol_to_angle, t)
	else:
		if patrol_phase_timer <= 0.0:
			is_patrol_moving = true
			patrol_from_angle = track_angle
			patrol_to_angle = track_angle + PATROL_MOVE_ANGLE
			patrol_phase_timer = PATROL_MOVE_TIME
	global_position = Arena.ARENA_CENTER + Vector2(cos(track_angle), sin(track_angle)) * Arena.BOSS_TRACK_RADIUS

## 分身也在同一條固定軌道上巡邏，跟本體錯開角度、盡量維持等分角度（總人數等分 360 度）分散
## 站——用本體自己的 track_angle 當基準，直接把每個分身的 track_angle 設成「本體角度+等分偏移」，
## 不是像舊版那樣寫入角度/距離再讓分身自己 move_toward 追過去：因為巡邏位置本來就是
## 「角度→座標」的純函式（BossClone._process_patrol() 做一樣的事），直接指定角度，分身的位置
## 自然跟著平滑移動（本體角度持續增加，分身角度=本體角度+固定偏移，也就跟著平滑增加），
## 不需要額外的追趕邏輯。
func _sync_clone_formation() -> void:
	var total := 1 + clones.size()
	if total < 2:
		return
	var slice := TAU / float(total)
	for i in range(clones.size()):
		var c = clones[i]
		if is_instance_valid(c):
			c.track_angle = track_angle + slice * float(i + 1)

## 讀氣/出招時本體跟分身都要停下來，統一由這裡開關——分身自己沒有狀態機，純粹聽本體指揮。
## 重新開始巡邏（active=true）時幫本體重新抽一個 track_angle，避免每次都從同一個角度起算。
func _set_wandering(active: bool, include_clones: bool = true) -> void:
	is_wandering = active
	if include_clones:
		for c in clones:
			if is_instance_valid(c):
				c.is_wandering = active

func _clone_summon_ready() -> bool:
	return clones.size() < CLONE_MAX and clone_cd_timer <= 0.0

## ATTACK_FIREBALL/ATTACK_ORB_BARRAGE/ATTACK_SUCTION 的時間流程各自用 await 自己跑完，
## 結束時呼叫 _on_attack_finished()，這裡不用額外倒數。
func _process_ai(delta: float) -> void:
	match state:
		BossState.IDLE:
			if _clone_summon_ready():
				_start_clone_summon()
				return
			if SUCTION_ENABLED:
				var trigger := _roll_for_suction_trigger(delta)
				if trigger != null:
					_start_suction_punish(trigger)
					return
			attack_cd_timer -= delta
			if attack_cd_timer <= 0.0:
				_start_random_attack()
		BossState.CLONE_SUMMON_BUFFER:
			buffer_timer -= delta
			if buffer_timer <= 0.0:
				_start_clone_summon()
		BossState.CASTING_CLONE_SUMMON:
			channel_timer -= delta
			var progress: float = 1.0 - clamp(channel_timer / CLONE_SUMMON_CHANNEL, 0.0, 1.0)
			for c in clones:
				if is_instance_valid(c):
					c.pretend_progress = progress
			if channel_timer <= 0.0:
				_finish_clone_summon()

## 回到 IDLE 的統一入口：順便先決定好下一個要用的週期招式（next_attack）——走位已經跟
## next_attack 無關了（固定軌道巡邏不管下一招是什麼都一樣繞），純粹是攻擊選擇邏輯。
func _enter_idle() -> void:
	state = BossState.IDLE
	attack_cd_timer = ATTACK_CD
	next_attack = AttackChoice.FIREBALL if randf() < 0.5 else AttackChoice.ORB_BARRAGE
	_set_wandering(true)

func _on_attack_finished() -> void:
	if _clone_summon_ready():
		state = BossState.CLONE_SUMMON_BUFFER
		buffer_timer = CLONE_READY_BUFFER
	else:
		_enter_idle()

## === 分身術：逐批累加到上限，不是一次性的三角陣型 ===

## 讀氣時本體真的在讀，既有分身其實什麼都沒做——但畫面上要讓它們一起「假裝」在放分身術
## （停下來、頭上也一起亮起同一圈讀氣光環），看起來像一整群同步在施法，不是只有本體一個人
## 在忙、其他分身呆站在旁邊。is_pretend_channeling/pretend_progress 是 BossClone.gd 專門給這個
## 視覺效果用的欄位，跟它本身完全沒有狀態機/會不會真的生出東西無關。
func _start_clone_summon() -> void:
	state = BossState.CASTING_CLONE_SUMMON
	channel_timer = CLONE_SUMMON_CHANNEL
	channel_damage_taken = 0.0
	is_channeling_clone_summon = true
	_set_wandering(false)
	_set_pretend_channeling(true)

func _set_pretend_channeling(active: bool) -> void:
	for c in clones:
		if is_instance_valid(c):
			c.is_pretend_channeling = active
			if active:
				c.pretend_progress = 0.0

func _interrupt_clone_summon() -> void:
	is_channeling_clone_summon = false
	clone_cd_timer = CLONE_SUMMON_CD
	_set_pretend_channeling(false)
	_enter_idle()
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(0.3, 0.3, 0.3), 12, 140.0)

## 召喚出新一批分身，不是一次補滿上限——每次最多生 CLONE_SUMMON_BATCH(2) 隻，直到總數觸頂
## CLONE_MAX(4) 為止（分身死亡釋出名額的話，下次分身術也能再補）。新分身一出現就要站在
## 「外圈環道上等分角度」的陣位上，不是生在本體旁邊再花時間走過去——用跟 _sync_clone_formation()
## 同一套等分角度公式，直接算出新分身生成那一刻（含新生的這幾隻）最終應該落在哪個陣位角度，
## 分身一出生就定位好。CD 在這裡就重設（不是等分身死光才重算）：下一批要不要生得出來，純粹
## 看 clones.size() 有沒有觸頂，不再跟「分身是否已死光」綁在一起。
func _finish_clone_summon() -> void:
	is_channeling_clone_summon = false
	_set_pretend_channeling(false)
	var spawn_count: int = min(CLONE_SUMMON_BATCH, CLONE_MAX - clones.size())
	var total_after: int = 1 + clones.size() + spawn_count
	var slice := TAU / float(total_after)
	for i in range(spawn_count):
		var slot_index: int = clones.size() + 1 + i # 第0個陣位是本體，已有的分身依序往後排
		_spawn_clone(track_angle + slice * float(slot_index))
	has_clones = not clones.is_empty()
	clone_cd_timer = CLONE_SUMMON_CD
	_enter_idle()

func _spawn_clone(angle: float) -> void:
	var clone_scene: PackedScene = load("res://scenes/entities/boss/BossClone.tscn")
	var clone := clone_scene.instantiate()
	get_tree().current_scene.add_child(clone)
	clone.track_angle = angle
	clone.global_position = Arena.ARENA_CENTER + Vector2(cos(angle), sin(angle)) * Arena.BOSS_TRACK_RADIUS
	clone.died.connect(_on_clone_died.bind(clone))
	clones.append(clone)

func _on_clone_died(clone) -> void:
	clones.erase(clone)
	has_clones = not clones.is_empty()

## === 週期招式（本體＋分身一起觸發，兩個都是遠程消耗招式） ===

## 不是這裡才隨機決定——next_attack 在進入 IDLE 那一刻就已經決定好了（_enter_idle()），
## 這裡只是照著執行。
func _start_random_attack() -> void:
	match next_attack:
		AttackChoice.FIREBALL:
			_start_fireball_attack()
		AttackChoice.ORB_BARRAGE:
			_start_orb_barrage()

## 有分身時嚴格依序發射：等上一顆火球在地上爆炸完（exploded signal）才讓下一個施法者開始丟，
## 不是固定錯開時間的並行版本——跟玩家確認過的規則（曾經短暫改成「同時預告、錯開0.1秒丟出」，
## 使用者後來要求改回這一版，見 BOSS_DESIGN.md §8.6）。
func _start_fireball_attack() -> void:
	state = BossState.ATTACK_FIREBALL
	_set_wandering(false)
	var casters: Array = [self] + clones
	for caster in casters:
		if not is_instance_valid(caster):
			continue
		var fireball := _spawn_fireball(caster.global_position)
		await fireball.exploded
	_on_attack_finished()

func _spawn_fireball(from_pos: Vector2) -> Node:
	var fireball_scene: PackedScene = load("res://scenes/entities/boss/BossFireball.tscn")
	var fireball := fireball_scene.instantiate()
	get_tree().current_scene.add_child(fireball)
	fireball.setup(from_pos, FIREBALL_TELEGRAPH_DELAY, FIREBALL_DAMAGE)
	return fireball

## 光球連擊：跟火球雨的「嚴格依序、等上一顆結束才換下一個」完全相反——這招要的是「一個接一個
## 開始打，但各自獨立連打」的壓迫感。第一個施法者立刻開始丟自己的 ORB_COUNT 連發，隔
## ORB_CASTER_STAGGER 秒後下一個施法者才開始丟自己的連發（不等前一個丟完），每個人的連發節奏
## 彼此獨立並行——`_throw_orb_sequence()` 呼叫後不 await，讓它自己在背景跑完整個連發序列，
## 這裡只負責控制「什麼時候輪到下一個人開始」。
func _start_orb_barrage() -> void:
	state = BossState.ATTACK_ORB_BARRAGE
	_set_wandering(false)
	var casters: Array = [self] + clones
	for i in range(casters.size()):
		var caster = casters[i]
		if is_instance_valid(caster):
			_throw_orb_sequence(caster)
		if i < casters.size() - 1:
			await get_tree().create_timer(ORB_CASTER_STAGGER).timeout
	var tail: float = ORB_THROW_INTERVAL * float(ORB_COUNT - 1) + 0.3
	await get_tree().create_timer(tail).timeout
	_on_attack_finished()

func _throw_orb_sequence(caster: Node2D) -> void:
	for i in range(ORB_COUNT):
		if not is_instance_valid(caster):
			return
		_spawn_orb(caster.global_position)
		if i < ORB_COUNT - 1:
			await get_tree().create_timer(ORB_THROW_INTERVAL).timeout

func _spawn_orb(from_pos: Vector2) -> void:
	var orb_scene: PackedScene = load("res://scenes/entities/boss/BossOrb.tscn")
	var orb := orb_scene.instantiate()
	get_tree().current_scene.add_child(orb)
	var player := _find_player()
	var dir: Vector2 = (player.global_position - from_pos).normalized() if player else Vector2.DOWN
	orb.setup(from_pos, dir, ORB_DAMAGE)

## === 吸引懲罰：玩家欺身過近時的個體反射動作，不是團體招式（目前關閉，見上方說明） ===

## 不是「一踏進 SUCTION_TRIGGER_RANGE 就保證觸發」的硬邊界——那樣等於一道隱形絆線，太生硬。
## 距離越近，每幀觸發機率越高（線性：貼到最近=0距離時機率密度是 SUCTION_TRIGGER_CHANCE_PER_SEC，
## 剛踏進範圍邊緣時機率趨近0），玩家在警戒邊緣晃一下不會每次都中獎，但真的欺身欺到很近，
## 幾乎必定很快觸發。每個施法者（本體+所有分身）各自獨立骰一次——不是只看最近的那一位，
## 分身越多、同時貼近玩家的人越多，整體觸發機率也會跟著疊加（呼應「分身多了更有壓力」的設計），
## 不是全體一起出招（跟火球雨/光球連擊不同，那兩招是「boss 這整隻怪物」的團體行為，這招永遠
## 只有骰中的那一位單獨出手）。
func _roll_for_suction_trigger(delta: float) -> Node2D:
	var player := _find_player()
	if player == null:
		return null
	var casters: Array = [self] + clones
	for caster in casters:
		if not is_instance_valid(caster):
			continue
		var d: float = caster.global_position.distance_to(player.global_position)
		if d >= SUCTION_TRIGGER_RANGE:
			continue
		var proximity: float = 1.0 - d / SUCTION_TRIGGER_RANGE
		var chance: float = SUCTION_TRIGGER_CHANCE_PER_SEC * proximity * delta
		if randf() < chance:
			return caster
	return null

## 單一施法者觸發，narrow+long 的扇形鎖定玩家方向展開，先有一小段預警動畫（TELEGRAPH，扇形
## 只畫外框不拉扯），正式啟動後持續拉扯/減速玩家；只要玩家被拉到離施法者 SUCTION_CLOSE_RANGE
## 以內，立刻觸發大傷害+往反方向擊退，整招提前結束——這就是這招真正要懲罰的時刻，不是比誰
## 忍耐久。玩家若全程都沒進過範圍、或命中後中途逃脫，連續 SUCTION_EARLY_CANCEL_WINDOW 秒都
## 沒咬住就提前取消；完全沒被懲罰到、也沒提前取消的話，撐滿 SUCTION_DURATION 自然結束。
func _start_suction_punish(caster: Node2D) -> void:
	state = BossState.ATTACK_SUCTION
	_set_wandering(false)
	var zone := _spawn_suction_zone(caster)

	var elapsed := 0.0
	var miss_timer := 0.0
	var punished := false
	while elapsed < SUCTION_DURATION and is_instance_valid(zone) and is_instance_valid(caster):
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		var player := _find_player()
		if player == null:
			break
		var active: bool = zone.is_active()
		var inside: bool = active and zone.is_player_inside()
		if inside:
			player.speed_multiplier = SUCTION_SLOW
			miss_timer = 0.0
		else:
			if player.speed_multiplier != 1.0:
				player.speed_multiplier = 1.0
			miss_timer += delta
		if active and player.global_position.distance_to(caster.global_position) <= SUCTION_CLOSE_RANGE:
			_resolve_suction_punish(caster, player)
			punished = true
			break
		if miss_timer >= SUCTION_EARLY_CANCEL_WINDOW:
			break

	if is_instance_valid(zone):
		zone.queue_free()
	if not punished:
		var player_end := _find_player()
		if player_end and player_end.speed_multiplier != 1.0:
			player_end.speed_multiplier = 1.0
	_on_attack_finished()

## 大傷害 + 往施法者反方向擊退——是一段有過程的推開動畫（Player.apply_knockback() + 摩擦力衰減，
## 跟怪物被擊退同一套做法），不是瞬間把玩家閃現到某個座標。push_speed 用運動學公式反推：等速度
## 衰減到 0 時，剛好已經走完 SUCTION_KNOCKBACK_DISTANCE 這段距離（d = v²/(2a) → v = sqrt(2*a*d)），
## 這裡的 a 要用 SUCTION_KNOCKBACK_FRICTION，必須跟 Player.gd 的 KNOCKBACK_FRICTION 對上才準確。
func _resolve_suction_punish(caster: Node2D, player: Node2D) -> void:
	player.speed_multiplier = 1.0
	player.take_damage(SUCTION_BURST_DAMAGE)
	var away: Vector2 = player.global_position - caster.global_position
	if away.length() < 1.0:
		away = Vector2.RIGHT.rotated(randf() * TAU)
	var push_speed: float = sqrt(2.0 * SUCTION_KNOCKBACK_FRICTION * SUCTION_KNOCKBACK_DISTANCE)
	player.apply_knockback(away.normalized() * push_speed)
	MagicFX.spawn_burst(get_tree().current_scene, player.global_position, Color(0.7, 0.2, 0.9), 20, 260.0)

func _spawn_suction_zone(caster: Node2D) -> Node:
	var zone_scene: PackedScene = load("res://scenes/entities/boss/BossSuctionZone.tscn")
	var zone := zone_scene.instantiate()
	get_tree().current_scene.add_child(zone)
	zone.setup(caster, SUCTION_RANGE, SUCTION_HALF_ANGLE, SUCTION_DURATION, SUCTION_PULL_SPEED, SUCTION_TELEGRAPH_DELAY)
	return zone

## 玩家隱形時（InvisibilityEffect）回傳 null，等於「boss 找不到玩家」——這個函式是本體/分身
## 鎖定玩家位置的唯一入口（火球雨丟出瞬間、光球連擊的方向、吸引懲罰的距離判定都經過這裡），
## 單點擋住就能讓所有攻擊同時失去目標，不用每個呼叫點各自檢查一次 is_invisible。
func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty() or players[0].is_invisible:
		return null
	return players[0]

func _draw() -> void:
	_draw_boss_body(self, hp, MAX_HP, flash_timer, squash, idle_bob)
	if is_channeling_clone_summon:
		var progress: float = 1.0 - clamp(channel_timer / CLONE_SUMMON_CHANNEL, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 46, -PI / 2.0, -PI / 2.0 + progress * TAU, 32, Color(1, 0.3, 0.9, 0.9), 4.0, false)
		draw_arc(Vector2.ZERO, 46, 0, TAU, 32, Color(1, 0.3, 0.9, 0.25), 2.0, true)

## 跟 BossClone.gd 的 _draw() 共用同一套畫法（同一段程式碼各自複製一份，不是呼叫共用函式——
## 兩邊維持「視覺上看起來一樣」才是重點，讓玩家分不出哪個是本體，不是程式碼本身要共用）。
##
## 使用者要求 boss 不要走水晶怪造型，改成跟 Player.gd 同款法師（長袍/臉，同一套3/4視角立體感
## 做法：腳下陰影、長袍左右分色、正面臉+眼睛），紅袍、多一件披風，用來跟玩家的紫袍做區別。
## 不畫帽子——加了帽子之後在不同解析度下反覆截圖測試，帽子的大小/位置關係（跟血條、跟披風）
## 一直沒調好看，使用者乾脆要求拿掉，法師造型光靠紅袍+披風+臉就能跟玩家區分，不缺帽子這個細節。
## boss 不會旋轉（沒有 look_at()，不像 Player 需要分朝左右），所以不用處理鏡射，固定朝下畫就好，
## 比例大致是 Player 造型的 1.5 倍（boss 要比玩家看起來更有存在感）。
static func _draw_boss_body(node: CanvasItem, cur_hp: float, max_hp: float, flash: float, sq: float, bob_phase: float) -> void:
	var robe_color := Color(1.0, 0.55, 0.55) if flash > 0.0 else Color(0.75, 0.12, 0.12)
	var robe_shade := robe_color.darkened(0.25)
	var cape_color := Color(0.3, 0.04, 0.04)
	var bob := sin(bob_phase) * 3.0
	var scale := Vector2(1.0 / sq, sq)

	# 腳下陰影：位置要在披風最底端（+50）之下，不然會被後面畫的披風整個蓋住看不見
	# （第一版陰影畫在+30，披風寬到±39、垂到+50，兩者重疊，陰影等於白畫了，截圖才發現）。
	var shadow_points := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		shadow_points.append((Vector2(0, 58 + bob) + Vector2(cos(a) * 22.0, sin(a) * 8.0)) * scale)
	node.draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.3))

	# 披風：故意比長袍寬很多、垂得更低，兩側跟底部都要明顯超出長袍輪廓一截，不然會完全被長袍蓋住
	# 看不出來是披風（第一版只寬6px，截圖出來幾乎看不見，改成寬15px、底部多垂12px）。
	var cape_points := PackedVector2Array([
		Vector2(-10, -34 + bob) * scale,
		Vector2(-39, 34 + bob) * scale,
		Vector2(0, 50 + bob) * scale,
		Vector2(39, 34 + bob) * scale,
		Vector2(10, -34 + bob) * scale,
	])
	node.draw_colored_polygon(cape_points, cape_color)

	# 兩隻腳：畫在長袍跟陰影之間，故意分兩段——腳的上半段(20~27)被長袍下擺蓋住，只露出下半段
	# (27~40)，看起來像從長袍下襬伸出來；腳底(40)到陰影頂(58-8=50)之間刻意留空隙不相連，
	# 不讓腳直接踩在陰影正中央，製造一點懸空感（使用者原文：要在影子上面，營造浮空的感覺）。
	var boot_color := Color(0.15, 0.1, 0.08)
	for side in [-1.0, 1.0]:
		var leg_points := PackedVector2Array([
			Vector2(4.0 * side, 20 + bob) * scale,
			Vector2(9.0 * side, 20 + bob) * scale,
			Vector2(9.0 * side, 40 + bob) * scale,
			Vector2(3.5 * side, 40 + bob) * scale,
		])
		node.draw_colored_polygon(leg_points, boot_color)

	# 長袍：左右兩片不同明暗模擬立體感，跟 Player.gd 同款做法，只是紅色系。
	var robe_left := PackedVector2Array([Vector2(0, -30 + bob) * scale, Vector2(-24, 27 + bob) * scale, Vector2(0, 27 + bob) * scale])
	var robe_right := PackedVector2Array([Vector2(0, -30 + bob) * scale, Vector2(24, 27 + bob) * scale, Vector2(0, 27 + bob) * scale])
	node.draw_colored_polygon(robe_left, robe_shade)
	node.draw_colored_polygon(robe_right, robe_color)

	# 臉：疊在長袍肩線之上，加兩個眼睛點。沒有帽子了，頭頂直接露出髮色（跟臉同一塊膚色偷懶畫，
	# demo階段不特別畫頭髮）。
	var face_center := Vector2(0, -30 + bob) * scale
	node.draw_circle(face_center, 15, Color(0.95, 0.82, 0.65))
	node.draw_circle(face_center + Vector2(-5.3, 3) * scale, 1.8, Color(0.2, 0.1, 0.1))
	node.draw_circle(face_center + Vector2(5.3, 3) * scale, 1.8, Color(0.2, 0.1, 0.1))

	# HP 血條：沒有帽子要避開了，直接放在臉的上方留一點空隙就好。
	var hp_ratio := cur_hp / max_hp
	node.draw_rect(Rect2(-30, -58, 60, 8), Color(0.15, 0.15, 0.15))
	node.draw_rect(Rect2(-30, -58, 60 * hp_ratio, 8), Color(0.9, 0.3, 0.3))
