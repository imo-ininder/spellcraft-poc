class_name SingleHitImpact
extends ProjectileImpact

## 最單純的變體：命中第一個東西就扣血、消失。飛行距離耗盡時什麼都不做，直接消失。
func resolve(projectile: Node, body: Node) -> bool:
	if body != null and body.has_method("take_damage"):
		body.take_damage(projectile.damage)
		MagicFX.spawn_burst(projectile.get_parent(), projectile.global_position, projectile.orb_color, 10, 140.0)
	return true
