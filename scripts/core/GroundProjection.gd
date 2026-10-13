class_name GroundProjection

## 統一管理「Y軸地面視角壓縮」係數，取代原本散落在 MagicFX.gd/AoETargetingReticle.gd/
## BossFireball.gd/TestRangeFloor.gd/TestDummy.gd 各自土炮的 GROUND_SQUASH 常數——現在
## 全部改讀這裡的 squash，數值要調全部連動，不用每個檔案分別改。
##
## 一開始「地面距離」判定（技能範圍/AoE半徑/怪物目標搜尋/移動速度）跟「結構性的東西」（場地
## 圓形牆壁、boss固定巡邏半徑、SpellProjectile的牆壁反彈）是分開的——後者當時刻意不套，因為
## 要跟 Main.tscn 實際的 CollisionPolygon2D 碰撞形狀對齊。2026-10-12 使用者要求把結構性的
## 東西也改成壓扁橢圓（場地視覺上一直是正圓競技場，跟其他全部套壓扁的範圍圈不協調）——`Walls/
## Boundary` 的 `CollisionPolygon2D` 現在改成在執行期用 `ellipse_points()` 動態產生橢圓頂點
## （取代原本寫死的正圓頂點），boss 巡邏軌道／分身出生位置改用 `ellipse_point()`，
## `SpellProjectile` 牆壁反彈改用 `clamp_to_radius()`／`ellipse_normal()`，細節見
## `docs/DESIGN.md` §4／§5.1。
##
## 碰撞形狀（CircleShape2D）本身也不受這個系統影響——範圍判定是程式碼手動算距離，碰撞形狀
## 是 Godot 物理引擎的實際重疊偵測，兩者是不同機制，這次只處理前者。
static var squash: float = 0.5

## 把一個世界座標差距向量轉換成「投影後的長度」——Y方向的差距除以squash（squash<1時，
## Y方向的差距「放大」成更大的距離），地面上兩點之間的判定距離統一用這個算，不要直接用
## Vector2.length()/distance_to()，不然會跟畫面上壓扁成橢圓的範圍圈對不上。
static func projected_length(delta: Vector2) -> float:
	return Vector2(delta.x, delta.y / squash).length()

static func projected_distance(a: Vector2, b: Vector2) -> float:
	return projected_length(a - b)

## 給「移動」用：direction 是已正規化的移動方向，speed 是原本的純量速度常數。Y 方向乘 squash
## （變慢，不是除以squash變快）——往上下移動在 projected_distance() 的度量裡天生縮短得比較快
## （因為那是 Y 差距除以 squash），所以要用變慢的世界座標速度抵銷，才能讓「往任何方向移動、
## 要花多久才能走進某個範圍」維持一致，不會變成「從上面接近永遠比較容易」。
static func projected_velocity(direction: Vector2, speed: float) -> Vector2:
	return Vector2(direction.x, direction.y * squash) * speed

## 把 to 點夾限在「以 from 為中心、投影後距離最多 max_dist」的橢圓邊界內——沿著 from→to
## 的直線方向夾限，不是沿著橢圓角度走（跟正圓時代的 offset.normalized() * max_dist 是同一個
## 概念，只是距離換算要先除以沿著這個方向的投影比例）。AoETargetingReticle.gd 的滑鼠選點夾限、
## 任何「預覽這把法術大概會打在哪」的地方都共用這個，不要各自複製一份夾限數學，不然兩邊會
## 慢慢漂移走樣（教訓見 CLAUDE.md 架構規則6）。
static func clamp_to_radius(from: Vector2, to: Vector2, max_dist: float) -> Vector2:
	var offset := to - from
	if projected_length(offset) <= max_dist:
		return to
	var raw_dir := offset.normalized()
	var scale: float = max_dist / projected_length(raw_dir)
	return from + raw_dir * scale

## 貼地橢圓的頂點座標（squash 套在 Y 軸），畫輪廓用 draw_polyline(points, ..., true) 或填色用
## draw_colored_polygon(points, ...) 都可以直接吃這組點。集中在這裡，AoETargetingReticle.gd／
## BossFireball.gd／TestRangeFloor.gd 都改呼叫這個，不要各自複製一份「cos/sin 乘squash湊橢圓」
## 的迴圈——這個迴圈雖然目前很穩定，但既然已經有 4 份重複（再加上這次新的法術範圍預覽），
## 一次收斂掉，以後要統一調整精細度/演算法只要改一個地方。
static func ellipse_points(center: Vector2, radius: float, segments: int = 64) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var a: float = TAU * float(i) / float(segments)
		points.append(ellipse_point(center, radius, a))
	return points

## ellipse_points() 單點版——給「角度→固定半徑橢圓上的座標」這種用法（boss固定軌道巡邏、
## 分身出生定位），不用為了一個點也跑迴圈/重複同一條 cos/sin*squash 公式。2026-10-12 新增：
## 場地圍牆/boss巡邏軌道這次改成跟著壓扁（之前 docs/DESIGN.md §5.1 明確記錄「結構性的東西
## 刻意不套」是舊決定，使用者這次要求改掉）。
static func ellipse_point(center: Vector2, radius: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle) * radius, sin(angle) * radius * squash)

## 跟 clamp_to_radius() 同一套「沿著 from→to 方向」的夾限邏輯，但同時限制最小／最大投影距離——
## 給 boss 巡邏環道「不能飄出外緣、也不能縮進內緣」這種環狀邊界用（被擊退之類外力推出環道時
## 夾回來）。min_dist<=0 時不夾下限，等同只有 clamp_to_radius() 的行為。
static func clamp_to_ring(from: Vector2, to: Vector2, min_dist: float, max_dist: float) -> Vector2:
	var offset := to - from
	var dist := projected_length(offset)
	if dist < 0.0001:
		return to
	var raw_dir := offset.normalized()
	if dist > max_dist:
		return from + raw_dir * (max_dist / projected_length(raw_dir))
	if min_dist > 0.0 and dist < min_dist:
		return from + raw_dir * (min_dist / projected_length(raw_dir))
	return to

## 給橢圓邊界反彈用：point 是（大約）落在以 center 為圓心、radius 為橢圓長軸半徑的橢圓邊界上
## 的一點，算出該點的橢圓法線方向（已 normalize）。不能直接用 (point-center).normalized()
## （那是正圓公式）——橢圓上任一點的法線方向跟「圓心到該點」的方向不同（除非剛好在長軸/短軸
## 頂點上），尤其長短軸差距越大（squash 越小）兩者差越多，用正圓公式會讓反彈角度明顯不對。
## 橢圓 x²/a² + y²/b² = 1 上一點 (x,y) 的法線方向正比於 (x/a², y/b²)。
static func ellipse_normal(center: Vector2, radius: float, point: Vector2) -> Vector2:
	var local := point - center
	var a := radius
	var b := radius * squash
	return Vector2(local.x / (a * a), local.y / (b * b)).normalized()
