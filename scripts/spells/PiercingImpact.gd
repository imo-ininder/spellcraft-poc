class_name PiercingImpact
extends ProjectileImpact

## 無限穿透：命中任何東西都造成傷害，但永遠不會因為命中而消失，只有飛行距離耗盡（body 為 null）才真正結束。
## 跟之前刪掉的版本不一樣——那個版本有限定次數（pierce_count），這個是法術天生的行為，不是符紋疊加出來的。
func resolve(projectile: Node, body: Node) -> bool:
	if body == null:
		return true
	if body.has_method("take_damage"):
		body.take_damage(projectile.damage)
		MagicFX.spawn_burst(projectile.get_parent(), projectile.global_position, projectile.orb_color, 10, 140.0)
	return false
