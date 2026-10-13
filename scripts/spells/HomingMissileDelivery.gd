class_name HomingMissileDelivery
extends SpellDelivery

## 魔法飛彈專用的發射機制，跟 ProjectileDelivery 本質不同，不是加個參數就能表達：
## 1. 不吃瞄準方向——施放當下自動從 max_range 範圍內挑最近的一個 "enemies" 群組目標鎖定，
##    玩家不用瞄準，`direction` 參數整個忽略。
## 2. missile_count 發飛彈依序發射（launch_interval 間隔），不是同時射出。
## 3. 發射方向直接對準目標（不另外加起手偏移角）——彎曲不規則的弧線效果全部交給
##    HomingMissile.gd 自己全程持續的隨機漂移處理，這裡只負責「決定目標」跟「依序射出」。
##
## 三發飛彈鎖定同一個目標，但不代表目標死了其他發就沒事做——目標中途死亡/消失時，已經射出
## 還在飛的那幾發會各自在 HomingMissile.gd 裡自動找範圍內下一個最近的敵人繼續追，不會對著
## 空氣飛，細節見 HomingMissile.gd 開頭註解。
##
## fire() 是非同步的（await 發射間隔），呼叫端不會等它，見 AoETargetingDelivery.gd 同樣的呼叫慣例。

@export var missile_scene: PackedScene
@export var impact: ProjectileImpact
@export var missile_count: int = 3
@export var missile_speed: float = 850.0
@export var turn_rate: float = 5.0 # 徑度/秒，飛彈最大轉向速率，決定弧線彎曲的急緩
@export var launch_interval: float = 0.12 # 每發飛彈之間的發射間隔

func fire(caster: Node2D, _direction: Vector2, stats: Dictionary, max_range: float, _effects: Array = []) -> void:
	var target := _pick_target(caster, max_range)
	if target == null:
		return
	for i in range(missile_count):
		_launch_missile(caster, target, stats.damage, max_range)
		if i < missile_count - 1:
			await caster.get_tree().create_timer(launch_interval).timeout

## 範圍內最近的敵人——目標在施放當下就決定好、鎖定整組飛彈，不是每發各自重新挑。
func _pick_target(caster: Node2D, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in caster.get_tree().get_nodes_in_group("enemies"):
		if not node.has_method("take_damage"):
			continue
		var d: float = GroundProjection.projected_distance(caster.global_position, node.global_position)
		if d <= max_range and d < best_dist:
			best = node
			best_dist = d
	return best

func _launch_missile(caster: Node2D, target: Node2D, damage: float, max_range: float) -> void:
	var missile := missile_scene.instantiate()
	caster.get_tree().current_scene.add_child(missile)
	missile.global_position = caster.global_position
	var launch_direction: Vector2 = (target.global_position - caster.global_position).normalized()
	missile.setup(launch_direction, damage, max_range, missile_speed, impact, target, turn_rate)
