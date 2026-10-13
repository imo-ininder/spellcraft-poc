extends Node2D

## 法術測試場（scripts/SpellTestRange.gd）用的簡化圓形地板，跟 Arena.gd 的三圈 boss 場地
## 設計無關（那是給正式戰鬥場景用的，這裡不需要玩家/boss分隔）——只是一個單純的圓形地板，
## 外加每 100px 一圈的同心圓參考線＋距離標籤，讓開發時能用肉眼對照法術的 max_range 數值
## （例如 Fireball 500px／MagicMissile 750px／LightningBolt 1800px）在畫面上實際長怎樣。
##
## docs/DESIGN.md §5.1：地板／牆壁本身維持純俯視正圓（不套壓扁，跟 Arena.gd 的地板磚塊/
## 圓形牆壁一致，因為要對得上實際碰撞形狀）；但這裡的同心圓參考線功能上等同「範圍選取圈」
## （純粹讓人對照法術 max_range，不是結構性的碰撞邊界），要套 GroundProjection.squash
## 壓扁成橢圓，跟 AoETargetingReticle.gd／BossFireball.gd 的範圍預告圈同一套 3/4 視角語言——
## 現在這條參考線用的壓扁比例，跟 GroundProjection.projected_distance() 判定範圍時用的是
## 同一個係數，畫出來的橢圓邊界就是實際判定的邊界，這正是這個測試場原本要驗證的東西。

const ARENA_CENTER := Vector2(600.0, 400.0)
const ARENA_RADIUS := 1000.0 # 比 LightningBolt 以外所有法術的 max_range 都大，留夠觀察空間
const RING_STEP := 100.0

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_circle(ARENA_CENTER, ARENA_RADIUS, Color(0.16, 0.16, 0.19))
	draw_arc(ARENA_CENTER, ARENA_RADIUS, 0, TAU, 128, Color(0.4, 0.4, 0.46), 4.0, true)

	var ring_count := int(ARENA_RADIUS / RING_STEP)
	var font := ThemeDB.fallback_font
	for i in range(1, ring_count + 1):
		var r: float = i * RING_STEP
		_draw_ground_ellipse_outline(ARENA_CENTER, r, Color(1, 1, 1, 0.22), 1.5)
		# 文字本身不跟著壓扁（壓扁的是橢圓的幾何，不是字型），位置用 r*squash 對齊橢圓最高點。
		var label_pos := ARENA_CENTER + Vector2(6, -r * GroundProjection.squash + 14)
		draw_string(font, label_pos, "%dpx" % int(r), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))

## 頂點座標統一呼叫 GroundProjection.ellipse_points()（集中管理），純描邊不填色（這裡是
## 測距參考線，不是範圍填色警示）。
func _draw_ground_ellipse_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	draw_polyline(GroundProjection.ellipse_points(center, radius), color, width, true)
