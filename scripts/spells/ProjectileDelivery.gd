class_name ProjectileDelivery
extends SpellDelivery

@export var projectile_scene: PackedScene
## 命中/飛行距離耗盡時要發生什麼事（單體傷害／爆炸範圍傷害...），是獨立的可替換變體
@export var impact: ProjectileImpact
## 法術固定要在這麼多秒內飛到 max_range，速度由這個時間跟 max_range 反推出來，不是獨立數值。
## `fixed_speed > 0` 時這個欄位會被忽略，改用 fixed_speed 當固定速度——會反彈/飛很久的法術（例如雷電箭）
## 用「時間反推速度」這套會跟著 max_range 一起爆炸性增快，不適合，見 docs/SPELL_SYSTEM.md。
@export var travel_time: float = 0.1
## >0 時優先於 travel_time：直接當作固定飛行速度（px/s），不受 max_range 影響
@export var fixed_speed: float = 0.0
## 碰到場地邊界會不會反彈，不是物理碰撞（不影響既有法術的牆壁穿越手感），見 SpellProjectile.gd
@export var bounces_off_walls: bool = false
## 量詞（「這次射出幾道」），法術強效縮放的目標，見 SpellDelivery.scale_count() 的註解。count>1
## 時朝同一個瞄準方向依序射出，不是同時射出——跟 HomingMissileDelivery.missile_count 的
## launch_interval 依序發射同一套模式，2026-10-12 使用者確認的手感。
@export var count: int = 1
@export var launch_interval: float = 0.08

## 法術迴響（echo）：整串 count 發射完（不是只射一發）才等 ECHO_DELAY 秒，再整串重射一次——
## 跟 AoETargetingDelivery 同一個原則，「重複」指的是這次施放的完整效果，不是單一發。
func fire(caster: Node2D, direction: Vector2, stats: Dictionary, max_range: float, _effects: Array = [], echo: bool = false) -> void:
	var speed := fixed_speed if fixed_speed > 0.0 else (max_range / travel_time)
	await _fire_volley(caster, direction, stats.damage, max_range, speed)
	if echo:
		await caster.get_tree().create_timer(ECHO_DELAY).timeout
		await _fire_volley(caster, direction, stats.damage, max_range, speed)

func _fire_volley(caster: Node2D, direction: Vector2, damage: float, max_range: float, speed: float) -> void:
	for i in range(count):
		_launch(caster, direction, damage, max_range, speed)
		if i < count - 1:
			await caster.get_tree().create_timer(launch_interval).timeout

func _launch(caster: Node2D, direction: Vector2, damage: float, max_range: float, speed: float) -> void:
	var projectile := projectile_scene.instantiate()
	caster.get_tree().current_scene.add_child(projectile)
	projectile.global_position = caster.global_position
	projectile.setup(direction, damage, max_range, speed, impact, bounces_off_walls)

## 這個 delivery 自己沒有半徑概念，委派給 impact（例如 ExplosiveImpact 才有半徑；
## SingleHitImpact/PiercingImpact 維持 ProjectileImpact 的空實作，委派了也不會有效果）。
func scale_radius(mult: float) -> void:
	if impact:
		impact.scale_radius(mult)

func has_scalable_radius() -> bool:
	return impact != null and impact.has_scalable_radius()

func get_radius() -> float:
	return impact.get_radius() if impact else -1.0

## floor 無條件捨去、下限夾在1，跟 HomingMissileDelivery.scale_count() 同一條規則。
func scale_count(mult: float) -> void:
	count = maxi(1, int(floor(count * mult)))

func has_scalable_count() -> bool:
	return true

func get_count() -> int:
	return count
