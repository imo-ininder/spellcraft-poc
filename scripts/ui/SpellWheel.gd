class_name SpellWheel
extends Control

const RADIUS := 110.0
const DEAD_ZONE := 12.0
## 每格的底色，跟各法術本身在遊戲裡的特效色保持一致（火球=橘、力場波=紫、雷電箭=電光藍）
const SLOT_COLORS := [Color(1, 0.5, 0.15), Color(0.75, 0.55, 1.0), Color(0.3, 0.9, 1.0)]

var spells: Array = []
var hover_index := -1
var current_index := -1
var wheel_visible := false
var center := Vector2.ZERO

func open(spell_list: Array, wheel_center: Vector2, current: int) -> void:
	spells = spell_list
	center = wheel_center
	current_index = current
	hover_index = -1
	wheel_visible = true
	queue_redraw()

func update_hover(index: int) -> void:
	hover_index = index
	queue_redraw()

func close() -> void:
	wheel_visible = false
	queue_redraw()

## 角度基準跟 Player.gd:_update_wheel_hover() 一致：正上方（-PI/2）＝第 0 格中心，依序順時針排列，
## 每格實際跨 slice 角度（中心 ± slice/2），跟 hover 判定用的「取最接近的格中心」完全對應。
func _draw() -> void:
	if not wheel_visible or spells.is_empty():
		return
	var n := spells.size()
	var slice := TAU / float(n)
	var font := ThemeDB.fallback_font
	for i in range(n):
		var mid := -PI / 2.0 + slice * i
		var start_angle := mid - slice / 2.0
		var end_angle := mid + slice / 2.0
		var color: Color = SLOT_COLORS[i % SLOT_COLORS.size()]
		var is_hovered := i == hover_index
		_draw_pie_slice(start_angle, end_angle, Color(color, 0.85 if is_hovered else 0.45))
		var label_pos := center + Vector2(cos(mid), sin(mid)) * (RADIUS * 0.62)
		var spell = spells[i]
		draw_string(font, label_pos - Vector2(44, 0), spell.display_name, HORIZONTAL_ALIGNMENT_CENTER, 88, 16, Color.WHITE)
		# 分隔線
		draw_line(center, center + Vector2(cos(start_angle), sin(start_angle)) * RADIUS, Color(0.1, 0.1, 0.12, 0.8), 2.0)
		# 目前裝備中的那一格，外緣用實白線標出來
		if i == current_index:
			draw_arc(center, RADIUS, start_angle, end_angle, 16, Color.WHITE, 4.0, false)
	draw_arc(center, RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.9), 3.0, true)
	draw_circle(center, DEAD_ZONE, Color(0.05, 0.05, 0.08, 0.7))

func _draw_pie_slice(start_angle: float, end_angle: float, color: Color) -> void:
	var points := PackedVector2Array()
	points.append(center)
	const STEPS := 20
	for s in range(STEPS + 1):
		var a: float = lerp(start_angle, end_angle, float(s) / float(STEPS))
		points.append(center + Vector2(cos(a), sin(a)) * RADIUS)
	draw_colored_polygon(points, color)
