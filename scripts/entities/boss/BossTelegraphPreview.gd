extends Node2D

## 攻擊前搖/判定範圍的危險預告（扇形/圓形/直線走廊）——FurnaceGuardian 的子節點，2026-10-14
## 從 FurnaceGuardian._draw() 拆出來獨立成一個節點，不是隨便重構：
##
## 這塊預告原本直接畫在 FurnaceGuardian._draw() 裡，跟角色本體（_draw_shadow()/_draw_body()）
## 共用同一個 CanvasItem。Boss 進 Y-sort（見 scenes/BossTestRange.tscn 的 Entities 容器，
## 讓玩家/Boss 依 Y 座標正確互相遮擋）之後，因為 z_index 是整個節點套用、沒辦法只套在
## 同一個 _draw() 裡的一部分內容，這塊預告被迫跟著角色本體一起參與排序——而 Boss 選招時
## 通常 Y 值比站在前面的玩家小，所以這塊預告幾乎永遠被排到玩家後面，不管視覺上延伸到玩家
## 腳下多遠都蓋不過去，變成「警戒範圍其實永遠不會蓋過任何角色」的奇怪結果（使用者實測發現）。
##
## 概念上這塊預告更接近「地面標記」，跟 DamageZone/BossMagmaGround 是同一類東西——本來就該
## 永遠貼在地面層級，不受「誰站在誰前面」影響，角色（不管玩家還是 Boss）永遠疊在它上面，
## 玩家才能一直看清楚自己是不是正站在警戒範圍裡。拆成獨立子節點、`z_as_relative = false`
## 是關鍵：不這樣設的話，這個子節點的 z_index 會疊加父節點 FurnaceGuardian 的 z_index（1），
## 變成總和還是 1、跟角色同一層，等於沒拆乾淨。

@onready var boss: FurnaceGuardian = get_parent()

func _ready() -> void:
	z_as_relative = false
	z_index = 0

func _process(_delta: float) -> void:
	queue_redraw()

## 扇形（橫掃）／圓形（重擊）危險範圍預告，透明度隨 boss._state_progress() 漲，只在
## Telegraph 狀態畫——Attack 當下再疊一層更亮的瞬間閃光，Recovery/Observe 不畫任何預告。
## 衝鋒不一樣：只在 Telegraph 畫（Attack 階段 Boss 本人就在走廊上衝，疊一個固定在舊位置的
## 走廊預告反而混淆，見 _draw_charge_preview()）。
func _draw() -> void:
	if boss.current_attack == "charge":
		if boss.state == FurnaceGuardian.State.TELEGRAPH:
			_draw_charge_preview(Color(1.0, 0.25, 0.05, boss._state_progress() * 0.55))
		return
	if boss.state != FurnaceGuardian.State.TELEGRAPH and boss.state != FurnaceGuardian.State.ATTACK:
		return
	var alpha: float = boss._state_progress() * 0.55 if boss.state == FurnaceGuardian.State.TELEGRAPH else 0.8
	var color := Color(1.0, 0.25, 0.05, alpha)
	if boss.current_attack == "sweep":
		_draw_sweep_preview(color)
	elif boss.current_attack == "slam":
		_draw_slam_preview(color)

## 預告範圍用 SWEEP_RANGE + PLAYER_HIT_RADIUS（跟 FurnaceGuardian._perform_sweep() 的實際
## 判定門檻一致）——不然畫出來的扇形會比真正判定範圍小一圈，玩家站在扇形外緣一點點的地方
## 看起來沒事，實際上因為身體範圍判定還是會中，等於預告在騙人。
func _draw_sweep_preview(color: Color) -> void:
	var points := PackedVector2Array([Vector2.ZERO])
	const SEGMENTS := 24
	var r := boss.SWEEP_RANGE + boss.PLAYER_HIT_RADIUS
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / float(SEGMENTS)
		var angle: float = boss.facing_dir.angle() - boss.SWEEP_HALF_ANGLE + boss.SWEEP_HALF_ANGLE * 2.0 * t
		points.append(GroundProjection.ellipse_point(Vector2.ZERO, r, angle))
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(1, 0.6, 0.2, color.a + 0.2), 2.0, true)

## 畫在 boss._attack_target_point 對應的本地座標位置，不是固定畫在原點——選招當下鎖定的
## 目標點可能離 Boss 自己的位置有一段距離（朝玩家方向，夾限在 SLAM_MAX_TARGET_DISTANCE
## 內），危險預告要出現在「真正會打到的地方」，不是 Boss 腳下。Boss 在 Telegraph 階段不會
## 再移動（移動只發生在 Observe），所以這裡用「目前」的 boss.global_position 反推本地座標
## 是安全的，不會跟鎖定當下的位置脫鉤。這個節點本身位置跟著父節點（Boss）走，local (0,0)
## 等同 boss 的 local (0,0)，所以這裡的座標換算邏輯跟原本畫在 FurnaceGuardian 裡時完全一樣。
func _draw_slam_preview(color: Color) -> void:
	var local_target: Vector2 = boss._attack_target_point - boss.global_position
	var points := GroundProjection.ellipse_points(local_target, boss.SLAM_RADIUS)
	draw_colored_polygon(points, color)
	draw_polyline(points, Color(1, 0.6, 0.2, color.a + 0.2), 2.5, true)

## 直線走廊預告：用 GroundProjection.offset_towards() 算前方/側邊的壓扁視角正確位移
## （跟 FireWallSpell 的火柱間距同一個系統性修正，不會因為朝哪個方向衝鋒而長度/寬度跑掉）。
func _draw_charge_preview(color: Color) -> void:
	var dir := boss.facing_dir
	var perp := Vector2(-dir.y, dir.x)
	var forward := GroundProjection.offset_towards(dir, boss.CHARGE_DISTANCE)
	var side := GroundProjection.offset_towards(perp, boss.CHARGE_HALF_WIDTH)
	var points := PackedVector2Array([-side, side, forward + side, forward - side])
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(1, 0.6, 0.2, color.a + 0.2), 2.0, true)
