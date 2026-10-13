class_name ProjectileSpell
extends Spell

## 「會飛的投射物」這個類別本身只放真正通用、不保證每把法術都會有的屬性會被拆出去——
## 使用者 2026-10-13 指出 `damage`/`explosion_radius` 不該放在這裡：不是每個投射物都保證會
## 造成傷害（以後可能有純位移/純視覺的投射物），`explosion_radius` 更是火球術專屬的效果細節。
## 這裡只留「這是一個會飛的東西」本身一定會有的 4 個屬性：
## 1. `travel_range`——飛多遠算到底，取代舊的（跟 `ZoneSpell` 共用、意義卻不同的）`max_range`，
##    改名是因為飛行路徑不保證是直線（之後可能有會轉彎/反彈的投射物），這是「總路徑長度」，
##    不是「終點距離施法者多遠」。
## 2. `speed`——飛行速度，通用屬性。
## 3. `size`——投射物的大小/寬度，影響碰撞判定半徑跟長相的比例尺，兩把法術各自決定自己
##    要多大，不是寫死在場景/腳本裡的常數。
## 4. `piercing`——命中後要不要消失。目前主要是描述性欄位（`FireballSpell`/`FireArrowSpell`
##    各自的 `cast()` 已經直接知道要生成哪種 Impact/投射物類別，不會真的去讀這個值做分支），
##    留著給以後 UI 顯示/篩選用。
##
## 「命中後做什麼」（傷害多少、有沒有爆炸範圍、要不要套某種特殊效果）完全不在這裡決定——那是
## 每把法術自己的事，`cast()` 維持虛函式，`FireballSpell`/`FireArrowSpell` 各自完整實作。

@export var travel_range: float = 650.0
@export var speed: float = 600.0
@export var size: float = 8.0
@export var piercing: bool = false

func cast(_caster: Node2D, _aim_dir: Vector2) -> void:
	push_error("ProjectileSpell.cast() not implemented on " + get_class())
