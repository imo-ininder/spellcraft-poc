extends Area2D

const BASE_SPEED := 500.0
const LIFETIME := 3.0

var velocity := Vector2.ZERO
var damage := 10.0
var hits_left := 1
var spin := 0.0
var orb_color := Color(1, 0.9, 0.2)
var trail: CPUParticles2D

func setup(direction: Vector2, dmg: float, pierce_count: int, speed_mult: float) -> void:
	damage = dmg
	hits_left = pierce_count + 1
	velocity = direction * BASE_SPEED * speed_mult
	rotation = velocity.angle()
	if pierce_count > 0:
		orb_color = Color(0.4, 0.7, 1.0)
	if speed_mult > 1.3:
		orb_color = Color(0.4, 1.0, 0.5)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	trail = MagicFX.make_sparkle_trail(self, orb_color)
	trail.emitting = true
	await get_tree().create_timer(LIFETIME).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	position += velocity * delta
	spin += delta * 20.0
	queue_redraw()

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
		hits_left -= 1
		MagicFX.spawn_burst(get_parent(), global_position, orb_color, 10, 140.0)
		if hits_left <= 0:
			queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 9, Color(orb_color, 0.35))
	draw_circle(Vector2.ZERO, 6, orb_color)
	draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1))
	for i in range(3):
		var a := spin + i * (TAU / 3.0)
		draw_circle(Vector2(cos(a), sin(a)) * 10, 1.5, Color(1, 1, 1, 0.8))
