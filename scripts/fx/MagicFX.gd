class_name MagicFX

static func spawn_burst(parent: Node, pos: Vector2, color: Color, amount: int = 16, speed: float = 220.0) -> void:
	var p := CPUParticles2D.new()
	parent.add_child(p)
	p.global_position = pos
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
