class_name ExplosiveImpact
extends ProjectileImpact

## 命中東西、或飛行距離耗盡時都會爆炸：對爆炸點 radius 範圍內所有 "enemies" 群組成員造成傷害。
@export var radius: float = 90.0

func resolve(projectile: Node, body: Node) -> bool:
	var point: Vector2 = body.global_position if body != null else projectile.global_position
	for target in projectile.get_tree().get_nodes_in_group("enemies"):
		if target.has_method("take_damage") and target.global_position.distance_to(point) <= radius:
			target.take_damage(projectile.damage)
	MagicFX.spawn_burst(projectile.get_parent(), point, Color(1, 0.5, 0.1), 28, 260.0)
	MagicFX.spawn_explosion_ring(projectile.get_parent(), point, radius, Color(1, 0.35, 0.1))
	return true
