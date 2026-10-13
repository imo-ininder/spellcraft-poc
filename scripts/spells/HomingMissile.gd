extends Area2D

## 魔法飛彈專用的追蹤投射物，跟 SpellProjectile.gd 刻意不是同一支腳本（見 HomingMissileDelivery.gd
## 開頭註解）——這支會持續轉向鎖定的目標飛出弧線，SpellProjectile.gd 是固定方向直線飛行，兩者飛行
## 模型本質不同，硬塞進同一支腳本只會讓單純直線飛行也要認一個「有沒有在追蹤」的分支，不划算。
##
## 整條飛行路徑的算法分兩層：
## 1. **基準方向**：有目標時是「這一幀當下朝向目標」的直線方向；沒有目標（目標死亡/消失、或
##    範圍內完全找不到下一個）時維持目前飛行方向，不會憑空亂轉。
## 2. **隨機漂移**：在基準方向上疊加一個連續漂移的隨機角度偏移（_wobble，角速度本身也是隨機
##    游走、有阻尼拉回0），讓整條路徑（不只是起步那一下）都是彎彎曲曲、不規則的弧線，不是導引
##    系統算出來的那種乾淨平滑曲線——先用 _wobble_velocity 隨機游走決定「漂移角度現在要往哪偏、
##    偏多快」，阻尼讓它不會越漂越誇張，再疊加到基準方向上，這就是「先算出直線路徑，再 random
##    成曲線路徑前進」的實作方式。
## 最終朝向用 rotate_toward() 把目前速度方向往「基準方向+漂移偏移」轉一點（受 turn_rate 限制轉
## 多快），速度大小全程不變，只有方向在變。
##
## **目標死亡後會在範圍內自動找下一個目標，不是直接變成無導引直線彈**：每幀只要 target 失效
## 就立刻重新掃一次 "enemies" 群組找最近的（範圍 = max_range，以飛彈「目前位置」為準，不是
## 施法者當初的位置——飛彈飛了一段距離，用自己現在的位置找附近目標才合理），找不到才真的
## 退化成維持目前方向的直線彈。
##
## max_range 只在「目前沒有目標可追」時才拿來當飛行距離上限——只要還在追蹤（不管是原本的目標
## 還是中途換的新目標）就不會因為飛行距離超過 max_range 放棄，只受 MAX_LIFETIME 這個時間制的
## 保底安全網限制（防止極端情況下變成永遠不消失的孤兒節點，不是用來限制「有沒有機會追到」）。
const MAX_LIFETIME := 6.0

## 隨機漂移參數：WOBBLE_MAX_ANGLE 是漂移能偏離基準方向多少（徑度），WOBBLE_ACCEL 是漂移角速度
## 本身隨機變化的加速度上限，WOBBLE_DAMPING 是阻尼係數（角速度每秒衰減的比例，避免越漂越快）。
const WOBBLE_MAX_ANGLE := 0.6
const WOBBLE_ACCEL := 9.0
const WOBBLE_DAMPING := 3.0

var velocity := Vector2.ZERO
var damage := 10.0
var speed := 850.0
var turn_rate := 5.0
var target: Node2D = null
var orb_color := Color(0.65, 0.25, 1.0)
var trail: CPUParticles2D
var max_range := 750.0
var distance_traveled := 0.0
var lifetime := 0.0
var impact: ProjectileImpact
var spin := 0.0
var _wobble := 0.0
var _wobble_velocity := 0.0
var _resolved := false

func setup(launch_direction: Vector2, dmg: float, range_limit: float, missile_speed: float, impact_behavior: ProjectileImpact, homing_target: Node2D, missile_turn_rate: float) -> void:
	velocity = launch_direction * missile_speed
	damage = dmg
	max_range = range_limit
	speed = missile_speed
	impact = impact_behavior
	target = homing_target
	turn_rate = missile_turn_rate
	rotation = velocity.angle()

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	trail = MagicFX.make_sparkle_trail(self, orb_color)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if _resolved:
		return
	lifetime += delta

	if not is_instance_valid(target):
		target = _find_target()
	var tracking := is_instance_valid(target)

	var base_angle: float = (target.global_position - global_position).angle() if tracking else velocity.angle()
	_update_wobble(delta)
	var desired_angle: float = base_angle + _wobble
	var new_angle: float = rotate_toward(velocity.angle(), desired_angle, turn_rate * delta)
	velocity = Vector2(cos(new_angle), sin(new_angle)) * speed

	var step := velocity * delta
	position += step
	distance_traveled += step.length()
	rotation = velocity.angle()
	spin += delta * 20.0
	queue_redraw()

	if tracking:
		if lifetime >= MAX_LIFETIME:
			_resolve(null)
	elif distance_traveled >= max_range:
		_resolve(null)

## 角速度隨機游走＋阻尼拉回0，疊加出來的角度夾在 ±WOBBLE_MAX_ANGLE 之間——跟直接每幀
## randf() 亂跳不同，這樣偏移量是連續變化的，看起來像「飄」而不是「抖」。
func _update_wobble(delta: float) -> void:
	_wobble_velocity += randf_range(-WOBBLE_ACCEL, WOBBLE_ACCEL) * delta
	_wobble_velocity -= _wobble_velocity * WOBBLE_DAMPING * delta
	_wobble = clamp(_wobble + _wobble_velocity * delta, -WOBBLE_MAX_ANGLE, WOBBLE_MAX_ANGLE)

## 以飛彈目前位置為準，在 max_range 範圍內找最近的下一個敵人——跟 HomingMissileDelivery._pick_target()
## 是同一個邏輯但各自一份（飛彈自己也要能獨立換目標，不依賴 delivery），專案裡這種「行為共用、
## 程式碼各自複製」的慣例在 boss 那群檔案的 _find_player() 已經用過。
func _find_target() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Node2D or not node.has_method("take_damage"):
			continue
		var d: float = GroundProjection.projected_distance(global_position, node.global_position)
		if d <= max_range and d < best_dist:
			best = node
			best_dist = d
	return best

func _on_body_entered(body: Node) -> void:
	if _resolved:
		return
	_resolve(body)

func _resolve(body: Node) -> void:
	if impact.resolve(self, body):
		_resolved = true
		queue_free()

## 帶尖端方向的小飛鏢造型（本地 +X 軸＝飛行方向，rotation 每幀跟著 velocity 更新），
## 跟 SpellProjectile.gd 的圓形光點造型區分開，視覺上一眼就能認出這是會轉向的飛彈。
func _draw() -> void:
	draw_circle(Vector2.ZERO, 7, Color(orb_color, 0.3))
	var tip := Vector2(11, 0)
	var back_a := Vector2(-6, 4.5)
	var back_b := Vector2(-6, -4.5)
	draw_colored_polygon(PackedVector2Array([tip, back_a, back_b]), orb_color)
	draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.9))
	for i in range(2):
		var a := spin + i * PI
		draw_circle(Vector2(cos(a), sin(a)) * 9, 1.2, Color(1, 1, 1, 0.6))
