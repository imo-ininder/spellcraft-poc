class_name AoETargetingDelivery
extends SpellDelivery

## 鎖定選點的範圍法術：吟唱結束後暫停遊戲、顯示跟隨滑鼠的指示圈（受 max_range 限制），
## 確認後恢復遊戲並在選定點造成範圍傷害。右鍵瞬發跳過的是吟唱/符紋累積階段，不是這個暫停選點流程——
## 瞬發一樣要暫停等玩家選位置，只是少了符紋強化、傷害用固定倍率（見 Player.gd:_fire_instant_spell）。
@export var radius: float = 90.0

func fire(caster: Node2D, _direction: Vector2, stats: Dictionary, max_range: float) -> void:
	var reticle: AoETargetingReticle = caster.get_tree().current_scene.get_node("AoETargetingReticle")
	caster.get_tree().paused = true
	reticle.start(caster, max_range, radius)
	var point = await reticle.finished
	caster.get_tree().paused = false
	if point != null:
		_resolve(caster, point, stats.damage)

func _resolve(caster: Node2D, point: Vector2, damage: float) -> void:
	for target in caster.get_tree().get_nodes_in_group("enemies"):
		if target.has_method("take_damage") and target.global_position.distance_to(point) <= radius:
			target.take_damage(damage)
	MagicFX.spawn_burst(caster.get_tree().current_scene, point, Color(1, 0.5, 0.1), 28, 260.0)
	MagicFX.spawn_explosion_ring(caster.get_tree().current_scene, point, radius, Color(1, 0.35, 0.1))
