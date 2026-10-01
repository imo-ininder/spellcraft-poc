extends CharacterBody2D

func _ready() -> void:
	add_to_group("player")

const SPEED := 260.0
const CAST_DURATION := 2.0
const COMBO_MAX_GAP := 0.15
const RIGHTCLICK_CD := 3.0
const BASE_DAMAGE := 10.0
const BASE_PROJECTILE_SPEED := 500.0

# 符紋組合表：按鍵序列 -> 效果。序列越長/越難打，效果越強。
const RUNE_COMBOS := {
	"UU": {"label": "+傷害", "color": Color(1, 0.3, 0.3), "damage_mult": 0.5},
	"DD": {"label": "+穿透", "color": Color(0.3, 0.6, 1), "pierce": 1},
	"LR": {"label": "+彈速", "color": Color(0.3, 1, 0.4), "speed_mult": 0.6},
	"RL": {"label": "+彈速", "color": Color(0.3, 1, 0.4), "speed_mult": 0.6},
	"UDU": {"label": "+強力傷害", "color": Color(1, 0.1, 0.6), "damage_mult": 1.2},
	"UULR": {"label": "+終極爆發", "color": Color(1, 0.8, 0.1), "damage_mult": 1.8, "pierce": 2},
}

const DIR_KEYS := {
	"move_up": "U",
	"move_down": "D",
	"move_left": "L",
	"move_right": "R",
}

var is_casting := false
var cast_timer := 0.0
var combo_buffer := ""
var pending_combo := ""
var combo_last_input_time := 0.0
var accumulated_runes: Array = []
var rightclick_cd_timer := 0.0
var fail_flash_timer := 0.0
var success_flash_timer := 0.0
var cast_pulse := 0.0
var hat_bob := 0.0
var hazard_flash_timer := 0.0

signal cast_started
signal cast_progress(ratio)
signal cast_ended
signal rune_added(rune_data)
signal combo_failed
signal rightclick_cd_updated(ratio)

func _physics_process(delta: float) -> void:
	if is_casting:
		_process_casting(delta)
	else:
		_process_movement()

	if rightclick_cd_timer > 0.0:
		rightclick_cd_timer = max(0.0, rightclick_cd_timer - delta)
		rightclick_cd_updated.emit(1.0 - rightclick_cd_timer / RIGHTCLICK_CD)

	look_at(get_global_mouse_position())

	if fail_flash_timer > 0.0:
		fail_flash_timer -= delta
	if success_flash_timer > 0.0:
		success_flash_timer -= delta
	if hazard_flash_timer > 0.0:
		hazard_flash_timer -= delta
	cast_pulse += delta * (6.0 if is_casting else 1.5)
	hat_bob += delta * 4.0
	queue_redraw()

	if Input.is_action_just_pressed("cast_spell") and not is_casting:
		_start_casting()
	if Input.is_action_just_released("cast_spell") and is_casting:
		_cancel_casting()

	if Input.is_action_just_pressed("instant_cast") and rightclick_cd_timer <= 0.0:
		_fire_instant_spell()

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
	velocity = dir.normalized() * SPEED
	move_and_slide()

func _process_casting(delta: float) -> void:
	velocity = Vector2.ZERO
	cast_timer -= delta
	cast_progress.emit(1.0 - max(cast_timer, 0.0) / CAST_DURATION)

	if combo_buffer.length() > 0:
		var elapsed := Time.get_ticks_msec() / 1000.0 - combo_last_input_time
		if pending_combo != "" and elapsed >= COMBO_MAX_GAP:
			_commit_combo(pending_combo)
		elif pending_combo == "" and elapsed > COMBO_MAX_GAP:
			_fail_combo()

	for action in DIR_KEYS.keys():
		if Input.is_action_just_pressed(action):
			_handle_combo_key(DIR_KEYS[action])

	if cast_timer <= 0.0:
		_finish_casting()

func _handle_combo_key(key: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	if combo_buffer.length() > 0:
		var gap := now - combo_last_input_time
		if gap > COMBO_MAX_GAP:
			_fail_combo()
			return

	combo_last_input_time = now
	var attempt := combo_buffer + key

	var is_exact := RUNE_COMBOS.has(attempt)
	var has_longer_prefix := false
	for combo in RUNE_COMBOS.keys():
		if combo.length() > attempt.length() and combo.begins_with(attempt):
			has_longer_prefix = true
			break

	if is_exact and not has_longer_prefix:
		_commit_combo(attempt)
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

func _commit_combo(key_string: String) -> void:
	var rune = RUNE_COMBOS[key_string]
	accumulated_runes.append(rune)
	rune_added.emit(rune)
	success_flash_timer = 0.2
	combo_buffer = ""
	pending_combo = ""
	MagicFX.spawn_burst(get_tree().current_scene, global_position + Vector2(0, -24), rune.get("color", Color.WHITE), 14, 160.0)

func _fail_combo() -> void:
	combo_buffer = ""
	pending_combo = ""
	fail_flash_timer = 0.3
	combo_failed.emit()
	MagicFX.spawn_burst(get_tree().current_scene, global_position + Vector2(0, -24), Color(0.3, 0.3, 0.3), 8, 90.0)

func _start_casting() -> void:
	is_casting = true
	cast_timer = CAST_DURATION
	combo_buffer = ""
	pending_combo = ""
	accumulated_runes.clear()
	cast_started.emit()

func _cancel_casting() -> void:
	is_casting = false
	cast_ended.emit()

func _finish_casting() -> void:
	is_casting = false
	_fire_spell(accumulated_runes)
	cast_ended.emit()

func _fire_spell(runes: Array) -> void:
	var damage := BASE_DAMAGE
	var pierce := 0
	var speed_mult := 1.0
	for r in runes:
		damage += damage * float(r.get("damage_mult", 0.0))
		pierce += int(r.get("pierce", 0))
		speed_mult += float(r.get("speed_mult", 0.0))
	_spawn_projectile(damage, pierce, speed_mult)

func _fire_instant_spell() -> void:
	rightclick_cd_timer = RIGHTCLICK_CD
	_spawn_projectile(BASE_DAMAGE * 0.8, 0, 1.0)

func _spawn_projectile(damage: float, pierce: int, speed_mult: float) -> void:
	var projectile_scene := preload("res://scenes/spells/SpellProjectile.tscn")
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position
	var dir := (get_global_mouse_position() - global_position).normalized()
	projectile.setup(dir, damage, pierce, speed_mult)

func take_damage(_amount: float) -> void:
	hazard_flash_timer = 0.25
	MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(1, 0.5, 0.1), 10, 150.0)

func _draw() -> void:
	var robe_color := Color(0.42, 0.3, 0.75)
	var glow_color := Color(0.7, 0.5, 1.0, 0.5)
	if hazard_flash_timer > 0.0:
		robe_color = Color(1.0, 0.55, 0.1)
		glow_color = Color(1.0, 0.6, 0.2, 0.6)
	elif success_flash_timer > 0.0:
		robe_color = Color(0.3, 0.85, 0.5)
		glow_color = Color(0.5, 1.0, 0.6, 0.6)
	elif fail_flash_timer > 0.0:
		robe_color = Color(0.8, 0.25, 0.25)
		glow_color = Color(1.0, 0.4, 0.4, 0.6)
	elif is_casting:
		robe_color = Color(0.55, 0.35, 0.9)

	# 吟唱光環脈動
	if is_casting:
		var pulse_r := 26.0 + sin(cast_pulse) * 6.0
		draw_arc(Vector2.ZERO, pulse_r, 0, TAU, 32, glow_color, 3.0, true)

	# 長袍身體 (圓錐狀，用多邊形模擬)
	var robe_points := PackedVector2Array([
		Vector2(0, -20), Vector2(-16, 18), Vector2(16, 18)
	])
	draw_colored_polygon(robe_points, robe_color)
	draw_circle(Vector2(0, -20), 10, Color(0.95, 0.82, 0.65))

	# 尖帽子，隨 hat_bob 輕微搖晃
	var hat_tilt := sin(hat_bob) * 0.08
	var hat_points := PackedVector2Array([
		Vector2(-12, -22).rotated(hat_tilt), Vector2(12, -22).rotated(hat_tilt), Vector2(0, -46).rotated(hat_tilt)
	])
	draw_colored_polygon(hat_points, Color(0.25, 0.15, 0.5))
	draw_circle(Vector2(0, -46).rotated(hat_tilt), 3, Color(1, 0.85, 0.3))

	# 法杖 (朝向滑鼠方向延伸)，頂端發光球隨吟唱脈動
	var staff_tip := Vector2(28, 0)
	draw_line(Vector2(6, 4), staff_tip, Color(0.4, 0.28, 0.15), 3.0)
	var orb_pulse := 4.0 + (sin(cast_pulse * 2.0) * 2.0 if is_casting else 0.0)
	draw_circle(staff_tip, orb_pulse, glow_color)
	draw_circle(staff_tip, orb_pulse * 0.5, Color(1, 1, 1, 0.9))
