class_name ProjectileDelivery
extends SpellDelivery

@export var projectile_scene: PackedScene
## 命中/飛行距離耗盡時要發生什麼事（單體傷害／爆炸範圍傷害...），是獨立的可替換變體
@export var impact: ProjectileImpact
## 法術固定要在這麼多秒內飛到 max_range，速度由這個時間跟 max_range 反推出來，不是獨立數值。
## `fixed_speed > 0` 時這個欄位會被忽略，改用 fixed_speed 當固定速度——會反彈/飛很久的法術（例如雷電箭）
## 用「時間反推速度」這套會跟著 max_range 一起爆炸性增快，不適合，見 SPELL_SYSTEM.md §8.12。
@export var travel_time: float = 0.1
## >0 時優先於 travel_time：直接當作固定飛行速度（px/s），不受 max_range 影響
@export var fixed_speed: float = 0.0
## 碰到場地邊界會不會反彈，不是物理碰撞（不影響既有法術的牆壁穿越手感），見 SpellProjectile.gd
@export var bounces_off_walls: bool = false

func fire(caster: Node2D, direction: Vector2, stats: Dictionary, max_range: float) -> void:
	var projectile := projectile_scene.instantiate()
	caster.get_tree().current_scene.add_child(projectile)
	projectile.global_position = caster.global_position
	var speed := fixed_speed if fixed_speed > 0.0 else (max_range / travel_time)
	projectile.setup(direction, stats.damage, max_range, speed, impact, bounces_off_walls)
