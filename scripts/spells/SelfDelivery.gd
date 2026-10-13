class_name SelfDelivery
extends SpellDelivery

## 以施法者為中心，對半徑內的 "enemies" 群組成員造成傷害並擊退，沒有飛行階段，不經過 ProjectileImpact。
## 別跟 SelfBuffDelivery 搞混：這個命中的是「周圍的敵人」（ForceWave 用），SelfBuffDelivery
## 命中的是「施法者自己」（buff類法術用）——兩者雖然都叫「Self」、都沒有飛行階段，但命中對象
## 本質不同，所以是兩個獨立的 delivery，不是同一個加參數切換行為。
@export var radius: float = 140.0
@export var knockback_force: float = 500.0

## 法術迴響（echo）：整個範圍判定＋特效跑完才等 ECHO_DELAY 秒，再整個重跑一次（擊退也會
## 套用兩次，跟傷害同一輪判定邏輯，不特別拆開處理）。
func fire(caster: Node2D, _direction: Vector2, stats: Dictionary, _max_range: float, _effects: Array = [], echo: bool = false) -> void:
	_resolve(caster, stats.damage)
	if echo:
		await caster.get_tree().create_timer(ECHO_DELAY).timeout
		_resolve(caster, stats.damage)

func _resolve(caster: Node2D, damage: float) -> void:
	for target in caster.get_tree().get_nodes_in_group("enemies"):
		if not target.has_method("take_damage"):
			continue
		var offset: Vector2 = target.global_position - caster.global_position
		if GroundProjection.projected_length(offset) > radius:
			continue
		target.take_damage(damage)
		if target.has_method("apply_knockback"):
			target.apply_knockback(offset.normalized() * knockback_force)
	MagicFX.spawn_burst(caster.get_tree().current_scene, caster.global_position, Color(0.75, 0.55, 1.0), 32, 320.0)
	MagicFX.spawn_explosion_ring(caster.get_tree().current_scene, caster.global_position, radius, Color(0.75, 0.5, 1.0))

func scale_radius(mult: float) -> void:
	radius *= mult

func has_scalable_radius() -> bool:
	return true

func get_radius() -> float:
	return radius
