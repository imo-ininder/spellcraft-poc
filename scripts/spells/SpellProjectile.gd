extends Area2D

var velocity := Vector2.ZERO
var damage := 10.0
var spin := 0.0
var orb_color := Color(1, 0.9, 0.2)
var trail: CPUParticles2D
var max_range := 650.0
var distance_traveled := 0.0
var impact: ProjectileImpact
var bounces_off_walls := false
var _resolved := false

## speed 由呼叫端（ProjectileDelivery.fire()）算好：預設是「travel_time 秒內飛完 max_range」反推出來的
## （見 docs/SPELL_SYSTEM.md §8.8），但 fixed_speed>0 的法術（例如雷電箭，見 §8.12）會直接給固定值，
## 不隨 max_range 變動——SpellProjectile 自己不管是哪一種，只負責照給定的 speed 飛。
func setup(direction: Vector2, dmg: float, range_limit: float, speed: float, impact_behavior: ProjectileImpact, bounce: bool = false) -> void:
	damage = dmg
	max_range = range_limit
	velocity = direction * speed
	impact = impact_behavior
	bounces_off_walls = bounce
	rotation = velocity.angle()
	if impact is ExplosiveImpact:
		orb_color = Color(1.0, 0.45, 0.15)
	elif impact is PiercingImpact:
		orb_color = Color(0.3, 0.9, 1.0)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	trail = MagicFX.make_sparkle_trail(self, orb_color)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if _resolved:
		return
	var step := velocity * delta
	position += step
	distance_traveled += step.length()
	if bounces_off_walls:
		_bounce_off_arena_bounds()
	spin += delta * 20.0
	queue_redraw()
	if distance_traveled >= max_range:
		_resolve(null)

## 用場地邊界的位置判斷做反彈，不是物理碰撞——SpellProjectile 的 collision_mask 刻意不偵測牆壁
## （見 docs/SPELL_SYSTEM.md），這樣才不會影響 Fireball 等其他法術既有的飛越牆壁手感。
func _bounce_off_arena_bounds() -> void:
	var bounced := false
	if position.x < 0.0 or position.x > Arena.ARENA_WIDTH:
		position.x = clamp(position.x, 0.0, Arena.ARENA_WIDTH)
		velocity.x = -velocity.x
		bounced = true
	if position.y < 0.0 or position.y > Arena.ARENA_HEIGHT:
		position.y = clamp(position.y, 0.0, Arena.ARENA_HEIGHT)
		velocity.y = -velocity.y
		bounced = true
	if bounced:
		rotation = velocity.angle()
		MagicFX.spawn_burst(get_parent(), global_position, orb_color, 8, 120.0)

func _on_body_entered(body: Node) -> void:
	if _resolved:
		return
	_resolve(body)

func _resolve(body: Node) -> void:
	if impact.resolve(self, body):
		_resolved = true
		queue_free()

const BOLT_LENGTH := 44.0
const BOLT_SEGMENTS := 6

func _draw() -> void:
	if impact is PiercingImpact:
		_draw_bolt()
	else:
		_draw_orb()

func _draw_orb() -> void:
	draw_circle(Vector2.ZERO, 9, Color(orb_color, 0.35))
	draw_circle(Vector2.ZERO, 6, orb_color)
	draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1))
	for i in range(3):
		var a := spin + i * (TAU / 3.0)
		draw_circle(Vector2(cos(a), sin(a)) * 10, 1.5, Color(1, 1, 1, 0.8))

## 雷電箭專用畫法：沿著飛行方向（本地 +X 軸，setup()/反彈時都會更新 rotation）拖出一條
## 會抖動的鋸齒長條，頭尖尾散，用 spin 讓它邊飛邊electric crackle，不是一個圓點。
func _draw_bolt() -> void:
	var points := PackedVector2Array()
	for i in range(BOLT_SEGMENTS + 1):
		var t := float(i) / float(BOLT_SEGMENTS)
		var x: float = lerp(8.0, -BOLT_LENGTH, t)
		var taper := sin(t * PI)
		var jitter := sin(spin * 4.0 + i * 2.3) * 5.0 * taper
		points.append(Vector2(x, jitter))
	draw_polyline(points, Color(orb_color, 0.3), 11.0, true)
	draw_polyline(points, Color(orb_color, 0.7), 5.5, true)
	draw_polyline(points, Color(1, 1, 1, 0.95), 2.0, true)
	draw_circle(points[0], 3.5, Color(1, 1, 1, 1.0))
