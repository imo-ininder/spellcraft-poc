class_name FireRetreatTrailZone
extends Node2D

## 火焰撤離身後留下的長方形火焰軌跡（docs/FIRE_PROTOTYPE.md §6.4）。使用者 2026-10-13
## 明確要求不要跟 DamageZone.gd（圓形範圍，火焰地面/火雨術在用）共用——這支檔案完全獨立
## 管理自己的 tick/存活計時器跟長方形命中判定，固定不動（跟會往前飛的東西不一樣，這是
## 「原地留下」的痕跡，不是射出去的）。類別名稱從 RetreatTrailZone 改成 FireRetreatTrailZone
## ——只有火焰撤離這把法術在用，不是「位移類法術共用的軌跡」，命名不該暗示會被別的法術重用。
##
## 命中判定：把目標位置轉成這個節點的本地座標（to_local()，連同 rotation 一起算，所以軌跡
## 不需要跟世界座標軸對齊），本地 x 是沿撤離方向、本地 y 是垂直方向，分別跟半長/半寬比較，
## 跟 FireArrowProjectile.gd 的射線判定是同一種「轉本地座標再用矩形範圍判斷」手法，但這裡
## 整個矩形固定不動，沒有頭尾伸縮的概念。

var length := 60.0 ## 沿軌跡方向的長度，通常等於撤離距離
var width := 50.0  ## 垂直軌跡方向的寬度
var damage_per_tick := 3.0
var tick_interval := 0.5
var duration := 3.0

var _tick_timer := 0.0
var _life_timer := 0.0

func setup(direction: Vector2, len: float, w: float, dmg: float, interval: float, dur: float) -> void:
	rotation = direction.angle()
	length = len
	width = w
	damage_per_tick = dmg
	tick_interval = interval
	duration = dur
	_tick_timer = tick_interval ## 一落地立刻判定一次，不用等滿一個 interval
	queue_redraw()

func _process(delta: float) -> void:
	_life_timer += delta
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		_apply_tick()
	if _life_timer >= duration:
		queue_free()
	queue_redraw()

func _apply_tick() -> void:
	var half_l := length * 0.5
	var half_w := width * 0.5
	for target in get_tree().get_nodes_in_group("enemies"):
		var local: Vector2 = to_local(target.global_position)
		if absf(local.x) <= half_l and absf(local.y) <= half_w:
			if target.has_method("take_dot_damage"):
				target.take_dot_damage(damage_per_tick)

func _draw() -> void:
	var fade: float = clamp((duration - _life_timer) / 0.5, 0.0, 1.0) if duration - _life_timer < 0.5 else 1.0
	var half_l := length * 0.5
	var half_w := width * 0.5
	var points := PackedVector2Array([
		Vector2(-half_l, -half_w), Vector2(half_l, -half_w), Vector2(half_l, half_w), Vector2(-half_l, half_w),
	])
	draw_colored_polygon(points, Color(0.8, 0.25, 0.05, 0.3 * fade))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.8, 0.25, 0.05, 0.7 * fade), 2.0, true)
