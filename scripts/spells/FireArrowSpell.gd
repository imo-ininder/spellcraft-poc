class_name FireArrowSpell
extends ProjectileSpell

## 火焰箭的完整設定值+效果：這把法術自己的 `damage`，不跟火球術共用——`ProjectileSpell`
## 基底只提供「這是一個會飛的東西」的通用屬性，命中後做什麼完全是這支檔案自己的事。

@export var damage: float = 7.0

func cast(caster: Node2D, aim_dir: Vector2) -> void:
	var impact := PiercingImpact.new()

	var projectile := FireArrowProjectile.new()
	projectile.size = size
	caster.get_tree().current_scene.add_child(projectile)
	projectile.global_position = caster.global_position
	projectile.setup(aim_dir, damage, travel_range, speed, impact)
