class_name FireGroundSpell
extends ZoneSpell

## 火焰地面：在施法者面前固定距離處生成一片安靜燃燒的 DOT 地板（「在身前創造」，不是以
## 自身為中心）。生成的是基底 `DamageZone`——這把法術沒有額外的長相/特效需求，不需要
## 自己的 Zone 子類別（跟火雨術不一樣，見 FireRainZone.gd）。

## 2026-10-13：spawn_distance 的意義是「投影後／視覺上的距離」，不是世界座標像素數——跟
## FireWallSpell.distance_ahead 同一個系統性修正，見 GroundProjection.offset_towards()。
@export var spawn_distance: float = 60.0

func cast(caster: Node2D, aim_dir: Vector2) -> void:
	var zone := DamageZone.new()
	caster.get_tree().current_scene.add_child(zone)
	zone.global_position = caster.global_position + GroundProjection.offset_towards(aim_dir, spawn_distance)
	zone.setup(damage_per_tick, tick_interval, duration, radius, damage_mode)
