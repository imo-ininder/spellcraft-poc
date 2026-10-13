class_name FireArrowProjectile
extends SpellProjectile

## 火焰箭（`fire_arrow.tres` 節點）專屬的投射物：這支檔案裡的每一行都只跟火焰箭有關，不會被
## 火球術影響、也不會影響火球術——長相（有寬度的紅色射線）、收尾動畫（延遲+尾巴追頭）、
## 碰撞形狀都在這一支檔案裡自己定義，沒有對應的 .tscn（碰撞形狀就一個固定半徑的圓，用程式碼
## 建就好，不需要為此多開一個場景檔案）。

var orb_color := Color(1.0, 0.2, 0.15)

## 頭（節點本身的位置，一路正常飛到 max_range）飛到底之後不會立刻消失，停頓 RETRACT_DELAY
## 秒，再讓尾巴（tail_distance，從 0 追到 max_range）追上頭，追到了才真正 queue_free()。
## 見 _draw()／_on_max_range_reached()／_process_retract()。
var retracting := false
var tail_distance := 0.0
var _retract_delay_timer := 0.0
const RETRACT_DELAY := 0.12
const RETRACT_SPEED_MULT := 1.6 ## 尾巴追頭的速度比頭飛行時快，收尾動作要比伸出快、俐落

func _ready() -> void:
	collision_layer = 2
	collision_mask = 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = size
	shape.shape = circle
	add_child(shape)

	super._ready()
	trail_color = orb_color
	## 射線本身已經是一條長長的紅色實體，不需要再疊一條火花拖尾（跟 FireballProjectile 不
	## 一樣，那邊是小光點才需要拖尾撐場面）。

func _physics_process(delta: float) -> void:
	if _resolved:
		return
	if retracting:
		_process_retract(delta)
		queue_redraw()
		return
	super._physics_process(delta)

## 飛到底之後不會直接消失——頭先停在原地，進入收尾階段（見 _process_retract()），這段期間
## 不會再判定新的命中（頭已經不動了），純粹是視覺收尾。
func _on_max_range_reached() -> void:
	retracting = true
	_retract_delay_timer = RETRACT_DELAY

## 2026-10-13 系統性修正：原本比較 `tail_distance >= max_range`，但 max_range 現在是
## 「投影後」的距離門檻（見 SpellProjectile.projected_distance_traveled），頭實際飛到的
## 原始世界座標 distance_traveled 往垂直方向射出時會小於 max_range（往水平方向射出時兩者
## 才會剛好相等）——如果尾巴還是追向 max_range，往垂直方向射出時尾巴會追過頭（tail_x 變成
## 正值，射線反向拉長，視覺上明顯錯誤）。改成比較 `tail_distance >= distance_traveled`
## （頭實際停在哪，尾巴就追到哪），不管往哪個方向射出都正確，而且邏輯上也更直接：收尾本來
## 就該是「尾巴追上頭」，不是「尾巴追上一個理論上限」。
func _process_retract(delta: float) -> void:
	if _retract_delay_timer > 0.0:
		_retract_delay_timer -= delta
		return
	tail_distance += velocity.length() * RETRACT_SPEED_MULT * delta
	if tail_distance >= distance_traveled:
		_resolve(null)

## 本地 +X 軸是飛行方向（setup() 時 rotation 已經對齊，畫的時候不用再轉一次）。節點本身的
## 位置（本地原點）永遠是射線的「頭」；「尾」的本地 x 座標是 -(distance_traveled - tail_distance)
## ——飛行階段 tail_distance 恆為 0，尾巴固定釘在出生點，頭往前飛多遠，射線就跟著拉長多少，
## 直到頭飛滿 max_range；飄到底之後進入收尾階段，頭不再動、tail_distance 從 0 追向
## max_range，尾巴才真的「跑向最長距離」追上頭，射線縮短到 0 時整條線才消失。
func _draw() -> void:
	var tail_x: float = -(distance_traveled - tail_distance)
	var half_w := size * 0.5
	var points := PackedVector2Array([
		Vector2(tail_x, -half_w), Vector2(0, -half_w), Vector2(0, half_w), Vector2(tail_x, half_w),
	])
	draw_colored_polygon(points, Color(orb_color, 0.25))
	draw_line(Vector2(tail_x, 0), Vector2.ZERO, Color(orb_color, 0.9), size * 0.45, true)
	draw_line(Vector2(tail_x, 0), Vector2.ZERO, Color(1, 0.85, 0.75, 0.9), size * 0.15, true)
	draw_circle(Vector2.ZERO, half_w * 0.6, Color(1, 1, 1, 1.0))
