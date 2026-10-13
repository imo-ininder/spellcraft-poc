class_name ZoneSpell
extends Spell

## 「持續範圍傷害」這個類別本身只放真正通用、不保證每把法術都需要的屬性會被拆出去——跟
## ProjectileSpell.gd 同一個判斷準則。這裡只留「這是一個會持續造成範圍傷害的東西」一定會有
## 的屬性：tick 傷害/間隔/持續時間/半徑，加上 `damage_mode`（HIT/DOT，決定傷害「感覺」，
## 跟 ProjectileSpell.piercing 一樣是結構性描述，各子類別的 cast() 已經直接知道自己是哪種，
## 不會真的拿這個值做分支）。
##
## 「生成位置怎麼算」「要不要有額外的視覺特效」完全不在這裡決定——那是每把法術自己的事：
## `FireGroundSpell`（施法者面前固定距離，生成純 DamageZone）、`FireRainSpell`（滑鼠瞄準
## 位置夾限，生成 FireRainZone，額外帶掉落物特效）各自完整實作 `cast()`。

enum DamageMode { HIT, DOT }

@export var damage_per_tick: float = 5.0
@export var tick_interval: float = 0.5
@export var duration: float = 3.0
@export var radius: float = 80.0
@export var damage_mode: DamageMode = DamageMode.DOT

func cast(_caster: Node2D, _aim_dir: Vector2) -> void:
	push_error("ZoneSpell.cast() not implemented on " + get_class())
