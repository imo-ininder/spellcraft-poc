class_name SlotGrid
extends Control

## 法術配置面板裡的格數視覺化：已填/未填兩種顏色，不分法術上色。方格是固定像素大小，
## 不隨容器寬度縮放——不管面板多寬，一格永遠是 SQUARE_SIZE，容器只是單純並排畫出去。

const SQUARE_SIZE := 48.0
const GAP := 8.0
const FILLED_COLOR := Color(0.7, 0.55, 1.0)
const EMPTY_COLOR := Color(1, 1, 1, 0.08)

var total_slots := 6
var used_slots := 0

func update_slots(used: int, total: int) -> void:
	used_slots = used
	total_slots = total
	custom_minimum_size = Vector2(total_slots * (SQUARE_SIZE + GAP) - GAP, SQUARE_SIZE)
	queue_redraw()

func _draw() -> void:
	for i in range(total_slots):
		var rect := Rect2(i * (SQUARE_SIZE + GAP), 0, SQUARE_SIZE, SQUARE_SIZE)
		draw_rect(rect, FILLED_COLOR if i < used_slots else EMPTY_COLOR)
		draw_rect(rect, Color(1, 1, 1, 0.5), false, 2.0)
