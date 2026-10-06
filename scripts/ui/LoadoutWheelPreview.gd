class_name LoadoutWheelPreview
extends Control

## 大廳法術配置頁的輪盤排序編排工具，常駐顯示（不是模擬戰鬥時按住 Ctrl 才彈出的那個輪盤），
## 單純用滑鼠拖拽交換兩個位置。角度基準跟 SpellWheel.gd:_draw() / Player.gd:_update_wheel_hover()
## 一致（正上方＝第0格中心，TAU/n 等分、順時針），差別是中心固定在自己 Control 的 size/2（local
## 座標），不是戰鬥輪盤那種「按下 Ctrl 當下的滑鼠位置」（viewport 座標）。
##
## 拿起來的那一格會變成一個跟著滑鼠跑的懸浮扇形（跟它在輪盤裡的形狀/角度/半徑完全一樣，不是縮成
## 一個圓片），滑鼠對齊的是扇形的重心（不是圓心/尖端，見 _draw_floating_chip() 註解），可以拖到
## 整個畫面任意位置（不只是輪盤範圍內）——
## 所以滑鼠放開/移動要用 _input() 接（Control:_gui_input() 只有滑鼠在自己範圍內才會收到事件，
## 離開輪盤之後就收不到了）。原本的格子在拿起來的這段時間顯示變暗/留空；拖回輪盤上方指到別的格子
## 時，那一格會亮起來提示「放開的話會跟手上這把交換」。真正的 spells 陣列要放開滑鼠才會變。

const RADIUS := 90.0
const DEAD_ZONE := 12.0

## 內部持有自己的複本，不是外部傳進來的同一個 Array 參照——GDScript 的 Array 跟 Resource 一樣是
## 參照型別，拖拽時 in-place 交換若直接用同一個陣列，會不小心連動改到呼叫端（Lobby.gd 的 selected），
## 繞過它該走的「透過 order_changed signal 回傳新順序」流程，見 DESIGN.md §4.9。
var spells: Array = []
var dragging_index := -1
var hover_index := -1
var drag_visual_pos := Vector2.ZERO

signal order_changed(new_order: Array)

func update_spells(new_spells: Array) -> void:
	spells = new_spells.duplicate()
	dragging_index = -1
	hover_index = -1
	queue_redraw()

## Lobby.gd 放開 Ctrl、把這個輪盤藏起來之前呼叫——如果當下正好拖到一半，直接取消（不套用這次
## 交換），不是強制完成。拖到一半被打斷照理說是例外狀況，取消比「幫使用者決定要交換」安全。
func cancel_drag() -> void:
	dragging_index = -1
	hover_index = -1
	queue_redraw()

func _slice_index_at(local_pos: Vector2) -> int:
	var n := spells.size()
	if n == 0:
		return -1
	var offset := local_pos - size / 2.0
	var dist := offset.length()
	if dist < DEAD_ZONE or dist > RADIUS:
		return -1
	var slice := TAU / float(n)
	var rel := fposmod(offset.angle() + PI / 2.0, TAU)
	return int(round(rel / slice)) % n

## 只負責「在輪盤範圍內按下滑鼠=拿起一格」，拿起來之後的移動/放開交給 _input()（見上方註解）。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var idx := _slice_index_at(event.position)
		if idx != -1:
			dragging_index = idx
			hover_index = idx
			drag_visual_pos = event.position
			queue_redraw()

## 拿起來之後用全域 _input() 追蹤，這樣才能拖到輪盤範圍以外、甚至整個畫面任意位置。
## visible 檢查是必要的：Godot 的 _input() 不會因為節點不可見就自動不觸發，Lobby.gd 現在會在
## 放開 Ctrl 時把這個輪盤整個藏起來（見 Lobby.gd 的 Ctrl 切換邏輯），如果當下使用者正好在拖拽
## 中途放開 Ctrl，沒有這個檢查的話還是會繼續收事件、更新一個使用者看不到的拖拽狀態。
func _input(event: InputEvent) -> void:
	if not visible or dragging_index == -1:
		return
	if event is InputEventMouseMotion:
		drag_visual_pos = make_input_local(event).position
		var idx := _slice_index_at(drag_visual_pos)
		if idx != hover_index:
			hover_index = idx
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if hover_index != -1 and hover_index != dragging_index:
			var tmp = spells[dragging_index]
			spells[dragging_index] = spells[hover_index]
			spells[hover_index] = tmp
			order_changed.emit(spells)
		dragging_index = -1
		hover_index = -1
		queue_redraw()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	var n := spells.size()
	if n == 0:
		return
	var center := size / 2.0
	var slice := TAU / float(n)
	var font := ThemeDB.fallback_font

	for i in range(n):
		var mid := -PI / 2.0 + slice * i
		var start_angle := mid - slice / 2.0
		var end_angle := mid + slice / 2.0
		var color: Color = GameState.color_for(spells[i])
		var alpha := 0.45
		if i == dragging_index:
			# 被拿起來了，這一格暫時留空/變暗
			color = color.darkened(0.45)
			alpha = 0.22
		elif i == hover_index and dragging_index != -1:
			# 放開的話會跟手上這把交換的目標格
			alpha = 0.85
		_draw_pie_slice(center, start_angle, end_angle, Color(color, alpha), RADIUS)
		var label_pos := center + Vector2(cos(mid), sin(mid)) * (RADIUS * 0.6)
		draw_string(font, label_pos - Vector2(40, 0), spells[i].display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.WHITE)
		draw_line(center, center + Vector2(cos(start_angle), sin(start_angle)) * RADIUS, Color(0.1, 0.1, 0.12, 0.8), 2.0)
		if i == hover_index and dragging_index != -1 and hover_index != dragging_index:
			draw_arc(center, RADIUS, start_angle, end_angle, 48, Color.WHITE, 3.0, true)
	draw_arc(center, RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.8), 2.0, true)
	draw_circle(center, DEAD_ZONE, Color(0.05, 0.05, 0.08, 0.6))

	if dragging_index != -1:
		_draw_floating_chip()

## 懸浮扇形跟它在輪盤裡的 start_angle/end_angle/RADIUS 完全一樣（保持原本的形狀），不受輪盤半徑/
## 範圍限制——可以超出這個 Control 的邊界（Godot 的 _draw() 沒有自動裁切，畫超出 rect 範圍一樣會
## 顯示）。滑鼠對齊的點是扇形的「重心」，不是圓心/尖端，拿尖端對著游標會讓懸浮的圖案看起來偏一邊。
##
## 重心原本想用「圓心+兩個弧端點」近似成三角形來算（忽略圓弧），但只有 2 把法術時，一格剛好是
## 半圓（180°），兩個弧端點會變成圓心正對面的兩個點，三角形退化成一條線，三點平均就直接等於圓心
## 本身——等於完全沒修正，而半圓的質量明顯偏向弧那一側，不是真的在圓心上。
## 改用扇形重心的精確公式（不需要為 n=2 另外特例處理，任意張角都適用）：半徑 R、半張角 half_angle
## 的扇形，重心在對稱軸（mid 方向）上，離圓心距離 = 2R·sin(half_angle) / (3·half_angle)。
## n=1（半張角=π，sin(π)=0）算出來距離剛好是 0，等於整圓的重心就是圓心本身，一樣不用特例。
func _draw_floating_chip() -> void:
	var font := ThemeDB.fallback_font
	var n := spells.size()
	var slice := TAU / float(n)
	var mid := -PI / 2.0 + slice * dragging_index
	var start_angle := mid - slice / 2.0
	var end_angle := mid + slice / 2.0

	var half_angle := slice / 2.0
	var centroid_dist := (2.0 * RADIUS * sin(half_angle)) / (3.0 * half_angle)
	var centroid_offset := Vector2(cos(mid), sin(mid)) * centroid_dist
	var apex_pos := drag_visual_pos - centroid_offset

	var color: Color = GameState.color_for(spells[dragging_index])
	_draw_pie_slice(apex_pos, start_angle, end_angle, Color(color, 0.95), RADIUS)
	draw_arc(apex_pos, RADIUS, start_angle, end_angle, 48, Color.WHITE, 3.0, true)
	var label_pos := apex_pos + Vector2(cos(mid), sin(mid)) * (RADIUS * 0.6)
	draw_string(font, label_pos - Vector2(40, 0), spells[dragging_index].display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.WHITE)

func _draw_pie_slice(center: Vector2, start_angle: float, end_angle: float, color: Color, radius: float = RADIUS) -> void:
	var points := PackedVector2Array()
	points.append(center)
	const STEPS := 48
	for s in range(STEPS + 1):
		var a: float = lerp(start_angle, end_angle, float(s) / float(STEPS))
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, color)
