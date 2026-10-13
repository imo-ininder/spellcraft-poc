class_name FireWallSpell
extends Spell

## 火牆術（docs/FIRE_PROTOTYPE.md §6.7）：使用者 2026-10-13 修正——不是投射物，不會飛行，
## 是在施法者前方固定距離處「一次創造」一排火柱，使用者的描述是「很多根火柱的集合」，直接
## 重用現成的 DamageZone（圓形 DOT 範圍，火焰地面也在用的那個類別），不用為了「火牆」這個
## 概念另外設計長方形/連續形狀。
##
## 2026-10-13 二次修正：火柱排列方向原本做成「瞄準方向的垂直線」（一面擋在前面的牆），
## 使用者糾正——要沿著瞄準方向本身排開（一路往前延伸的一排），不是垂直線；距離也要拉長。
##
## 2026-10-13 三次修正：spacing 要小於 pillar_radius*2（火柱直徑），讓相鄰火柱的圓形範圍
## 稍微重疊——使用者要求的，視覺上連成一道連續的牆，不要留明顯空隙。
##
## 2026-10-13 四次修正：類別名稱從 WallSpell 改成 FireWallSpell——使用者指出「Wall」是按
## 「效果類型」取的名字，暗示「所有牆類法術都長這樣」，但這支檔案裡「直線 cascade」這個排列
## 方式完全是這把法術自己的設計決定，不代表任何「牆」都該這樣長（之後如果有別的元素也有牆類
## 法術，形狀/排列完全可能不同）。跟 FireballSpell/FireArrowSpell 同一個命名慣例：類別名稱
## 綁定「這把法術」，不是「這種機制分類」。
##
## cast() 用 await 依序間隔生成每根火柱，所以是一個協程——呼叫端（Player._cast_current_node()）
## 不需要、也沒有 await 它，GDScript 允許這樣「射後不理」，協程會在背景繼續跑完剩下的火柱。
##
## 2026-10-13 五次修正（系統性問題）：spacing/distance_ahead 原本直接用 `aim_dir * 數值`
## 算世界座標位移，使用者發現往水平方向射出時火柱會重疊（符合預期），往垂直方向射出時卻
## 不會重疊——因為壓扁視角（Y軸壓縮）下，純世界座標的垂直位移「看起來」比水平位移短，詳見
## GroundProjection.offset_towards() 的註解。改用該函式統一校正，spacing/distance_ahead
## 現在的意義是「投影後／視覺上的距離」，不是世界座標像素數，不管往哪個方向施放，火柱間的
## 視覺重疊程度都一致。

@export var pillar_count: int = 6
@export var spacing: float = 65.0         ## 小於 pillar_radius*2=80，讓相鄰火柱稍微重疊
@export var distance_ahead: float = 100.0 ## 第一根火柱離施法者多遠
@export var cascade_delay: float = 0.08   ## 每根火柱之間點燃的間隔，0 的話全部同時出現
@export var pillar_radius: float = 40.0
@export var damage_per_tick: float = 4.0
@export var tick_interval: float = 0.4
@export var duration: float = 2.5

func cast(caster: Node2D, aim_dir: Vector2) -> void:
	var scene_tree := caster.get_tree()
	var origin: Vector2 = caster.global_position + GroundProjection.offset_towards(aim_dir, distance_ahead)
	var step := GroundProjection.offset_towards(aim_dir, spacing)

	for i in range(pillar_count):
		_spawn_pillar(scene_tree, origin + step * i)
		if i < pillar_count - 1 and cascade_delay > 0.0:
			await scene_tree.create_timer(cascade_delay).timeout

func _spawn_pillar(scene_tree: SceneTree, pos: Vector2) -> void:
	var zone := DamageZone.new()
	scene_tree.current_scene.add_child(zone)
	zone.global_position = pos
	zone.setup(damage_per_tick, tick_interval, duration, pillar_radius, ZoneSpell.DamageMode.DOT)
