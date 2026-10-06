class_name MagicFX

## 3/4視角風格：特效壓扁成橢圓（跟角色腳下陰影、Arena 磚塊同一套「貼地」視覺語言），不是正圓
## 往四面八方炸開——這樣爆炸/特效看起來才像發生在地面上，不是懸浮在半空的正圓形。
const GROUND_SQUASH := 0.5

static func spawn_burst(parent: Node, pos: Vector2, color: Color, amount: int = 16, speed: float = 220.0) -> void:
	var p := CPUParticles2D.new()
	parent.add_child(p)
	p.global_position = pos
	p.scale = Vector2(1.0, GROUND_SQUASH)
	p.emitting = true
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	p.gravity = Vector2(0, 260)
	await parent.get_tree().create_timer(p.lifetime + 0.1).timeout
	if is_instance_valid(p):
		p.queue_free()

## 爆炸範圍圈：從 radius*0.5 擴張到 radius 同時淡出，讓範圍型效果的實際命中半徑看得出來
static func spawn_explosion_ring(parent: Node, pos: Vector2, radius: float, color: Color, duration: float = 0.3) -> void:
	var ring := Node2D.new()
	parent.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector2(1.0, GROUND_SQUASH)
	ring.z_index = 10
	ring.set_meta("t", 0.0)
	ring.draw.connect(func():
		var t: float = ring.get_meta("t")
		var alpha := 1.0 - t
		var r: float = radius * lerp(0.5, 1.0, t)
		ring.draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, alpha * 0.2))
		ring.draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(color.r, color.g, color.b, alpha), 4.0, true)
	)
	var tween := ring.create_tween()
	tween.tween_method(func(t: float): ring.set_meta("t", t); ring.queue_redraw(), 0.0, 1.0, duration)
	tween.tween_callback(ring.queue_free)

static func make_sparkle_trail(parent: Node, color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	parent.add_child(p)
	p.emitting = false
	p.amount = 20
	p.lifetime = 0.5
	p.explosiveness = 0.0
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 30.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = color
	p.gravity = Vector2.ZERO
	return p
