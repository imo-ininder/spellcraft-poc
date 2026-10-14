class_name BossMagmaGround
extends Node2D

## 熔岩重擊命中瞬間留下的灼熱地面（設計文件 §4.2 流程第4步）。刻意不跟玩家法術的
## DamageZone.gd 共用——那支檔案的傷害對象寫死是 "enemies" 群組，這裡要打的是 "player"
## 群組，概念上是完全不同方向的傷害來源（玩家法術 vs Boss 攻擊），硬套同一支檔案只會讓
## 兩個互不相干的系統綁在一起、改一邊要擔心另一邊。純距離判定，不靠物理重疊，跟 DamageZone
## 同一種手法但各自獨立實作。
##
## 安靜持續傷害（take_dot_damage 優先，沒有就退回 take_damage）——灼熱地面應該是站上去持續
## 流血的感覺，不是每個 tick 都像被揍一次，跟 Player.gd 的 fire_ground 設計理由一致。

var damage_per_tick := 5.0
var tick_interval := 0.5
var duration := 2.5
var radius := 90.0

var _tick_timer := 0.0
var _life_timer := 0.0

func setup(dmg: float, interval: float, dur: float, r: float) -> void:
	damage_per_tick = dmg
	tick_interval = interval
	duration = dur
	radius = r
	_tick_timer = tick_interval ## 落地立刻判定一次，不用等滿一個 interval
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
	for target in get_tree().get_nodes_in_group("player"):
		if GroundProjection.projected_distance(target.global_position, global_position) > radius:
			continue
		if target.has_method("take_dot_damage"):
			target.take_dot_damage(damage_per_tick)
		elif target.has_method("take_damage"):
			target.take_damage(damage_per_tick)

func _draw() -> void:
	var fade: float = clamp((duration - _life_timer) / 0.5, 0.0, 1.0) if duration - _life_timer < 0.5 else 1.0
	var points := GroundProjection.ellipse_points(Vector2.ZERO, radius)
	draw_colored_polygon(points, Color(1.0, 0.3, 0.05, 0.28 * fade))
	draw_polyline(points, Color(1.0, 0.5, 0.1, 0.65 * fade), 2.0, true)
