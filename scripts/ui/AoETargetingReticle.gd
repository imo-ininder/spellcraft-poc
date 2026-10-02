class_name AoETargetingReticle
extends Node2D

## 世界座標的選點介面（跟 SpellWheel 不一樣，SpellWheel 是純螢幕座標 UI）。
## 暫停時要繼續運作，所以 process_mode 設 ALWAYS，不受 SceneTree.paused 影響。

signal finished(point)

var active := false
var caster: Node2D
var max_range := 0.0
var preview_radius := 0.0
var target_point := Vector2.ZERO
var in_range := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start(caster_node: Node2D, range_limit: float, radius: float) -> void:
	caster = caster_node
	max_range = range_limit
	preview_radius = radius
	target_point = caster.global_position
	in_range = true
	active = true
	queue_redraw()

func _process(_delta: float) -> void:
	if not active:
		return
	var mouse_world := caster.get_global_mouse_position()
	var offset := mouse_world - caster.global_position
	if offset.length() > max_range:
		in_range = false
		target_point = caster.global_position + offset.normalized() * max_range
	else:
		in_range = true
		target_point = mouse_world
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("cast_spell"):
		active = false
		queue_redraw()
		finished.emit(target_point)
	elif event.is_action_pressed("instant_cast") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		active = false
		queue_redraw()
		finished.emit(null)

func _draw() -> void:
	if not active:
		return
	var ring_color := Color(0.4, 1.0, 0.5, 0.9) if in_range else Color(0.6, 0.6, 0.6, 0.6)
	draw_arc(caster.global_position, max_range, 0, TAU, 64, Color(1, 1, 1, 0.25), 2.0, true)
	draw_line(caster.global_position, target_point, Color(1, 1, 1, 0.3), 1.5)
	draw_arc(target_point, preview_radius, 0, TAU, 32, ring_color, 3.0, true)
	draw_circle(target_point, 4.0, ring_color)
