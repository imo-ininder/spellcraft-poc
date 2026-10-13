class_name FireRainSpell
extends ZoneSpell

## 火雨術：在滑鼠瞄準位置（夾限在 placement_range 內，跟投射物瞄準共用
## GroundProjection.clamp_to_radius()，不需要額外的選點確認步驟）生成一片會持續造成「真正
## 擊中」的範圍，並且範圍內會隨機冒出掉落物特效，模擬雨點落地——這個特效是這把法術專屬的
## 長相，生成 FireRainZone（extends DamageZone，見該檔案），不是共用的 DamageZone。
## rain_spawn_interval 直接是這份資源自己的欄位，要調火雨術的掉落頻率就改這裡，不會牽動
## 任何其他法術。

@export var placement_range: float = 450.0
@export var rain_spawn_interval: float = 0.12

func cast(caster: Node2D, _aim_dir: Vector2) -> void:
	var zone := FireRainZone.new()
	zone.rain_spawn_interval = rain_spawn_interval
	caster.get_tree().current_scene.add_child(zone)
	var mouse_pos: Vector2 = caster.get_global_mouse_position()
	zone.global_position = GroundProjection.clamp_to_radius(caster.global_position, mouse_pos, placement_range)
	zone.setup(damage_per_tick, tick_interval, duration, radius, damage_mode)
