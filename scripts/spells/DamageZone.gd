class_name DamageZone
extends Node2D

## 共用的「圓形持續範圍傷害」骨架——不用 Area2D 實際碰撞形狀，跟 ExplosiveImpact/近戰判定
## 同一套手法，每個 tick 直接對 "enemies" 群組成員算 GroundProjection.projected_distance()，
## 純距離判定，不靠物理重疊事件（這樣目標在 tick 之間移動進出範圍都能正確抓到）。
##
## 這支檔案只放「任何圓形持續範圍」都通用的東西：tick 判定、存活計時、畫圓形範圍——跟
## SpellProjectile.gd（直線飛行骨架）是同一種分層方式。火焰地面（`FireGroundSpell`）、
## 火牆術的火柱（`FireWallSpell`）直接用這個類別，不需要額外行為。**火雨術的掉落物特效
## 不放在這裡**——那是火雨術自己的長相，使用者 2026-10-13 明確指出放在這個共用類別裡會
## 「又 expose 了不必要的參數」（調火雨術的掉落頻率不該牽動這支共用檔案），獨立開
## `FireRainZone extends DamageZone` 處理，見該檔案。

var damage_per_tick := 5.0
var tick_interval := 0.5
var duration := 3.0
var radius := 80.0
var damage_mode: int = ZoneSpell.DamageMode.DOT

var _tick_timer := 0.0
var _life_timer := 0.0

func setup(dmg: float, interval: float, dur: float, r: float, mode: int) -> void:
	damage_per_tick = dmg
	tick_interval = interval
	duration = dur
	radius = r
	damage_mode = mode
	## 2026-10-13（docs/BOSS_PROTOTYPE.md §5：「火焰地面應該影響 Boss 移動路徑」）：掛進
	## "player_hazard_zone" 群組，給 FurnaceGuardian 的 Observe 逼近邏輯讀，繞開玩家擺在
	## 地上的範圍（火焰地面/火牆火柱/火雨術都繼承或直接用這個類別，一次掛好）。純粹是給 Boss
	## 讀的額外標籤，不影響這支檔案原本的傷害/畫法邏輯。
	add_to_group("player_hazard_zone")
	queue_redraw()

func _process(delta: float) -> void:
	_life_timer += delta
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		_apply_tick()
	if _life_timer >= duration:
		queue_free()

func _apply_tick() -> void:
	for target in get_tree().get_nodes_in_group("enemies"):
		if GroundProjection.projected_distance(target.global_position, global_position) > radius:
			continue
		if damage_mode == ZoneSpell.DamageMode.DOT and target.has_method("take_dot_damage"):
			target.take_dot_damage(damage_per_tick)
		elif target.has_method("take_damage"):
			target.take_damage(damage_per_tick)

## 火雨術（HIT）畫得比較亮/飽和，火焰地面/火柱（DOT）畫得比較暗/燒灼感——純粹用顏色區分
## 兩種模式，不是功能的一部分。剩餘存活時間用透明度淡出，讓玩家看得出範圍快消失了。
func _draw() -> void:
	var fade: float = clamp((duration - _life_timer) / 0.5, 0.0, 1.0) if duration - _life_timer < 0.5 else 1.0
	var base_color: Color = Color(1.0, 0.55, 0.1) if damage_mode == ZoneSpell.DamageMode.HIT else Color(0.8, 0.25, 0.05)
	var points := GroundProjection.ellipse_points(Vector2.ZERO, radius)
	draw_colored_polygon(points, Color(base_color, 0.3 * fade))
	draw_polyline(points, Color(base_color, 0.7 * fade), 2.0, true)
