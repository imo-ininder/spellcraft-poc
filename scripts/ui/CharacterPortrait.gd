class_name CharacterPortrait
extends Control

## 大廳左半邊的角色形象，純展示用、沒有互動。跟 Player.gd 的 _draw() 用同一套配色（長袍紫、尖帽、法杖發光球），
## 但這是獨立畫法，不是把 Player 塞進來——大廳不需要 CharacterBody2D 的物理/輸入邏輯，只需要畫面。
##
## 3/4俯視角風格（使用者確認：地板維持純俯視方格不變，只有角色造型改成「有正面、帶高度感」的畫法，
## 不是真正的等角投影）——跟純俯視版比，差異只在三件事：腳下加橢圓陰影讓角色「站」在地上而不是
## 貼在地面的平面圖案；長袍改成左右兩片不同明暗色塊模擬簡單立體感；臉部疊在長袍肩線之上、加兩個
## 眼睛點，讓人看得出是正面臉而不是俯視頭頂。地板/碰撞/座標系統完全不動。

var bob := 0.0

func _process(delta: float) -> void:
	bob += delta * 1.5
	queue_redraw()

## 人物造型本身不是上下對稱的——帽尖球心掛在 face_center 之上94、球本身還有6的半徑，所以最頂點
## 離 center 實際是 -138（不是帽尖這個點本身的-94，要把球的半徑也算進去）；陰影底到中心 +49；
## 整體垂直跨度 138+49=187。只算「剛好塞滿框」（跨度==框高）還不夠：截圖驗證過，剛好頂到邊緣
## 看起來還是很擠、帽尖幾乎貼著框線，跟「被切掉」在視覺上沒什麼差別。乘上 MARGIN（<1）讓造型
## 只佔框的一部分，上下都留一點呼吸空間。
const SPAN := 187.0
const MARGIN := 0.82

func _draw() -> void:
	var s: float = min(size.x, size.y) / SPAN * MARGIN
	var center := Vector2(size.x / 2.0, size.y / 2.0 + 44.5 * s)
	var robe_color := Color(0.42, 0.3, 0.75)
	var robe_shade := Color(0.32, 0.21, 0.58)
	# glow_color 只用在法杖球的發光，不像 Player.gd 還有一圈「吟唱光環脈動」的 draw_arc——那個光環
	# 在 Player.gd 是包在 if is_casting 裡面才畫的，這裡的大廳展示角色沒有吟唱狀態可言，之前誤把
	# 它複製成無條件常駐，半徑/位置又是照 Player 的「身體中心」抓，貼到這邊「臉中心」上剛好卡在
	# 帽子底部那圈，才是使用者一直覺得「帽子很怪」的真正原因——不是帽子本身畫錯，拿掉這圈就好了。
	var glow_color := Color(0.7, 0.5, 1.0, 0.4)

	# 腳下陰影：3/4視角最便宜的立體感來源，沒有這個角色看起來會像貼在地上的平面貼紙。
	var shadow_center := center + Vector2(0, 40) * s
	var shadow_points := PackedVector2Array()
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		shadow_points.append(shadow_center + Vector2(cos(a) * 26.0 * s, sin(a) * 9.0 * s))
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.35))

	# 長袍：比純俯視版窄、高，左右兩片不同明暗色塊（左暗右亮）模擬簡單立體感，不是單一平塗三角形。
	var robe_left := PackedVector2Array([
		center + Vector2(-2, -34) * s,
		center + Vector2(-20, 40) * s,
		center + Vector2(0, 44) * s,
		center + Vector2(0, -34) * s,
	])
	var robe_right := PackedVector2Array([
		center + Vector2(2, -34) * s,
		center + Vector2(20, 40) * s,
		center + Vector2(0, 44) * s,
		center + Vector2(0, -34) * s,
	])
	draw_colored_polygon(robe_left, robe_shade)
	draw_colored_polygon(robe_right, robe_color)

	# 臉：疊在長袍肩線上方（不是嵌進長袍頂端），加兩個眼睛點，看得出是正面臉，不是俯視頭頂。
	var face_center := center + Vector2(0, -38) * s
	draw_circle(face_center, 18 * s, Color(0.95, 0.82, 0.65))
	draw_circle(face_center + Vector2(-6, 2) * s, 1.8 * s, Color(0.2, 0.15, 0.15))
	draw_circle(face_center + Vector2(6, 2) * s, 1.8 * s, Color(0.2, 0.15, 0.15))

	var tilt := sin(bob) * 0.08
	var hat_points := PackedVector2Array()
	for offset in [Vector2(-22, -42), Vector2(22, -42), Vector2(0, -94)]:
		hat_points.append(face_center + (offset * s).rotated(tilt))
	draw_colored_polygon(hat_points, Color(0.25, 0.15, 0.5))
	draw_circle(face_center + (Vector2(0, -94) * s).rotated(tilt), 6 * s, Color(1, 0.85, 0.3))

	var staff_base := center + Vector2(24, 2) * s
	var staff_tip := center + Vector2(48, -48) * s
	draw_line(staff_base, staff_tip, Color(0.4, 0.28, 0.15), 3.0 * s)
	draw_circle(staff_tip, 7 * s, glow_color)
	draw_circle(staff_tip, 3.5 * s, Color(1, 1, 1, 0.9))
