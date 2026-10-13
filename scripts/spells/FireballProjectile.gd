class_name FireballProjectile
extends SpellProjectile

## 火球術（`basic.tres` 節點、Player._fire_charged_fireball() 共用）專屬的投射物：這支檔案
## 裡的每一行都只跟火球術有關，不會被火焰箭影響、也不會影響火焰箭——長相（旋轉光球+火花
## 拖尾）、碰撞形狀都在這一支檔案裡自己定義，沒有對應的 .tscn（碰撞形狀就一個固定半徑的圓，
## 用程式碼建就好，不需要為此多開一個場景檔案）。飛到底/命中都用 SpellProjectile 基底的預設
## 行為（直接消失），火球術沒有特殊收尾動畫。

var spin := 0.0
var orb_color := Color(1.0, 0.45, 0.15)
var trail: CPUParticles2D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = size
	shape.shape = circle
	add_child(shape)

	super._ready()
	trail_color = orb_color
	trail = MagicFX.make_sparkle_trail(self, orb_color)
	trail.emitting = true

## 旋轉純粹是視覺（光點環繞），跟飛行物理無關，獨立用 _process() 跑，不混進
## SpellProjectile._physics_process() 那段飛行邏輯裡。
func _process(delta: float) -> void:
	spin += delta * 20.0
	queue_redraw()

## 三個同心圓跟環繞光點的半徑都按 size 等比縮放（size=8 時數字跟改用 size 之前一樣，
## 是舊的寫死數值直接換算回來的比例，不是重新設計視覺）。
func _draw() -> void:
	draw_circle(Vector2.ZERO, size * 1.125, Color(orb_color, 0.35))
	draw_circle(Vector2.ZERO, size * 0.75, orb_color)
	draw_circle(Vector2.ZERO, size * 0.3125, Color(1, 1, 1))
	for i in range(3):
		var a := spin + i * (TAU / 3.0)
		draw_circle(Vector2(cos(a), sin(a)) * size * 1.25, size * 0.1875, Color(1, 1, 1, 0.8))
