extends CollisionPolygon2D

## 玩家場地的牆壁碰撞形狀。2026-10-12 之前這裡的 polygon 是手刻寫死的 48 點正圓座標
## （跟 Arena.PLAYER_ZONE_RADIUS 對齊但完全不受 GroundProjection.squash 影響）；使用者
## 要求整個場地改成壓扁橢圓之後，改成在 _ready() 用 GroundProjection.ellipse_points() 動態
## 產生——這樣以後調整 PLAYER_ZONE_RADIUS 或 squash 係數，牆壁碰撞形狀會自動跟著變，不會
## 變成又一份容易跟 Arena.gd 視覺畫面脫鉤的寫死座標。
func _ready() -> void:
	# ellipse_points() 回傳 segments+1 個點（頭尾重複、方便畫 draw_polyline 的封閉線），
	# CollisionPolygon2D 的 polygon 會自動封閉，不需要也不該留這個重複的收尾點（留著會多一條
	# 長度為0的邊），所以這裡去掉最後一個。
	var points := GroundProjection.ellipse_points(Arena.ARENA_CENTER, Arena.PLAYER_ZONE_RADIUS, 48)
	points.remove_at(points.size() - 1)
	polygon = points
