class_name SelfDelivery
extends SpellDelivery

## 以施法者為中心，對半徑內的 "enemies" 群組成員造成傷害並擊退，沒有飛行階段，不經過 ProjectileImpact
@export var radius: float = 140.0
@export var knockback_force: float = 500.0

func fire(caster: Node2D, _direction: Vector2, stats: Dictionary, _max_range: float) -> void:
	for target in caster.get_tree().get_nodes_in_group("enemies"):
		if not target.has_method("take_damage"):
			continue
		var offset: Vector2 = target.global_position - caster.global_position
		if offset.length() > radius:
			continue
		target.take_damage(stats.damage)
		if target.has_method("apply_knockback"):
			target.apply_knockback(offset.normalized() * knockback_force)
	MagicFX.spawn_burst(caster.get_tree().current_scene, caster.global_position, Color(0.75, 0.55, 1.0), 32, 320.0)
	MagicFX.spawn_explosion_ring(caster.get_tree().current_scene, caster.global_position, radius, Color(0.75, 0.5, 1.0))
