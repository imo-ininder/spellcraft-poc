class_name FireballSpell
extends ProjectileSpell

## 火球術的完整設定值+效果：這把法術自己的 `damage`/`explosion_radius`，不跟任何其他法術
## 共用——`ProjectileSpell` 基底只提供「這是一個會飛的東西」的通用屬性（travel_range/speed/
## size/piercing），命中後做什麼完全是這支檔案自己的事。

@export var damage: float = 12.0
@export var explosion_radius: float = 90.0

func cast(caster: Node2D, aim_dir: Vector2) -> void:
	var impact := ExplosiveImpact.new()
	impact.radius = explosion_radius

	var projectile := FireballProjectile.new()
	projectile.size = size
	caster.get_tree().current_scene.add_child(projectile)
	projectile.global_position = caster.global_position
	projectile.setup(aim_dir, damage, travel_range, speed, impact)
