extends StaticBody2D

const MAX_HP := 200.0

const SLAM_RADIUS := 90.0
const SLAM_DAMAGE := 15.0
const IDLE_DURATION := 2.5
const TELEGRAPH_DURATION := 0.6
const RISING_DURATION := 0.7
const JUMP_PEAK_HEIGHT := 90.0
const RECOVER_DURATION := 0.4
const KNOCKBACK_FRICTION := 900.0

enum AiState { IDLE, TELEGRAPH, RISING, SLAM, RECOVER }

var hp := MAX_HP
var flash_timer := 0.0
var squash := 1.0
var idle_bob := 0.0
var knockback_velocity := Vector2.ZERO

var ai_state: AiState = AiState.IDLE
var ai_timer := IDLE_DURATION
var jump_height := 0.0
var jump_origin := Vector2.ZERO
var jump_target := Vector2.ZERO

signal hp_changed(ratio)

func _ready() -> void:
	add_to_group("enemies")

## 擊退疊加在 AI 狀態機當幀已經設定的位置上，不改 AI 邏輯本身，見 _process()
func apply_knockback(force: Vector2) -> void:
	knockback_velocity += force

func take_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	flash_timer = 0.15
	hp_changed.emit(hp / MAX_HP)
	_spawn_damage_label(amount)
	_bounce()
	queue_redraw()
	if hp <= 0.0:
		hp = MAX_HP
		hp_changed.emit(1.0)

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
	_process_ai(delta)
	if knockback_velocity.length() > 1.0:
		global_position += knockback_velocity * delta
		global_position.x = clamp(global_position.x, 0.0, Arena.ARENA_WIDTH)
		global_position.y = clamp(global_position.y, 0.0, Arena.ARENA_HEIGHT)
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		knockback_velocity = Vector2.ZERO
	queue_redraw()

func _process_ai(delta: float) -> void:
	ai_timer -= delta
	match ai_state:
		AiState.IDLE:
			if ai_timer <= 0.0:
				_enter_state(AiState.TELEGRAPH)
		AiState.TELEGRAPH:
			if ai_timer <= 0.0:
				_enter_state(AiState.RISING)
		AiState.RISING:
			var progress: float = 1.0 - maxf(ai_timer, 0.0) / RISING_DURATION
			jump_height = sin(progress * PI) * JUMP_PEAK_HEIGHT
			global_position = jump_origin.lerp(jump_target, progress)
			if ai_timer <= 0.0:
				_enter_state(AiState.SLAM)
		AiState.SLAM:
			global_position = jump_target
			_do_slam()
			_enter_state(AiState.RECOVER)
		AiState.RECOVER:
			jump_height = maxf(ai_timer, 0.0) / RECOVER_DURATION * 10.0
			if ai_timer <= 0.0:
				jump_height = 0.0
				_enter_state(AiState.IDLE)

func _enter_state(state: AiState) -> void:
	ai_state = state
	match state:
		AiState.IDLE:
			ai_timer = IDLE_DURATION
		AiState.TELEGRAPH:
			ai_timer = TELEGRAPH_DURATION
			jump_origin = global_position
			jump_target = _find_player_position()
		AiState.RISING:
			ai_timer = RISING_DURATION
		AiState.SLAM:
			ai_timer = 0.0
		AiState.RECOVER:
			ai_timer = RECOVER_DURATION

func _find_player_position() -> Vector2:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return global_position
	return players[0].global_position

func _do_slam() -> void:
	MagicFX.spawn_burst(get_parent(), global_position, Color(1, 0.6, 0.2), 24, 260.0)
	for body in get_tree().get_nodes_in_group("player"):
		if body.global_position.distance_to(global_position) <= SLAM_RADIUS:
			if body.has_method("take_damage"):
				body.take_damage(SLAM_DAMAGE)

func _draw() -> void:
	# 警示圈：TELEGRAPH 階段畫在「跳躍目標位置」而非怪物當前位置，讓玩家能預判要落在哪裡
	if ai_state == AiState.TELEGRAPH:
		var warn_center := jump_target - global_position
		var warn_ratio: float = 1.0 - maxf(ai_timer, 0.0) / TELEGRAPH_DURATION
		var warn_alpha := 0.3 + sin(warn_ratio * TAU * 3.0) * 0.15
		draw_circle(warn_center, SLAM_RADIUS, Color(1, 0.3, 0.1, max(warn_alpha, 0.1)))
		draw_arc(warn_center, SLAM_RADIUS, 0, TAU, 32, Color(1, 0.5, 0.2, 0.8), 3.0, true)

	var crystal_color := Color(1, 0.5, 0.5) if flash_timer > 0.0 else Color(0.55, 0.35, 0.85)
	if ai_state == AiState.RISING or ai_state == AiState.SLAM:
		crystal_color = Color(1, 0.75, 0.3)
	var bob := sin(idle_bob) * 3.0 - jump_height
	var scale_x := 1.0 / squash
	var scale_y := squash

	var body_points := PackedVector2Array([
		Vector2(0, -50 + bob) * Vector2(scale_x, scale_y),
		Vector2(-22, -10 + bob) * Vector2(scale_x, scale_y),
		Vector2(-14, 25 + bob) * Vector2(scale_x, scale_y),
		Vector2(14, 25 + bob) * Vector2(scale_x, scale_y),
		Vector2(22, -10 + bob) * Vector2(scale_x, scale_y),
	])
	draw_colored_polygon(body_points, crystal_color)
	draw_polyline(body_points, Color(1, 1, 1, 0.4), 2.0, true)
	draw_circle(Vector2(-7, -5 + bob) * Vector2(scale_x, scale_y), 4, Color(1, 1, 1, 0.6))
	draw_circle(Vector2(6, 10 + bob) * Vector2(scale_x, scale_y), 3, Color(1, 1, 1, 0.4))

	var hp_ratio := hp / MAX_HP
	draw_rect(Rect2(-30, -70, 60, 8), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(-30, -70, 60 * hp_ratio, 8), Color(0.9, 0.3, 0.9))
