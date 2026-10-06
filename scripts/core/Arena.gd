class_name Arena
extends Node2D

## 場地分成三個同心圓區域：玩家只能待在內圈圓形場地，boss（含分身）固定在外圈環狀軌道上
## 巡邏施法，兩者中間隔著一圈完全淨空的縫隙（不鋪磚、沒有牆面裝飾，純粹是視覺/空間上的
## 「不能互通」）——玩家跟 boss 物理上永遠碰不到面，所有互動只能靠法術隔空進行，見
## docs/BOSS_DESIGN.md 的場地設計小節。
##
## 半徑常數由內而外：PLAYER_ZONE_RADIUS（玩家場地）→ 縫隙（寬度 GAP_WIDTH）→
## BOSS_RING_INNER_RADIUS（boss 環道內緣）→ BOSS_TRACK_RADIUS（boss 實際巡邏的固定半徑，
## 算成環道內外緣的正中央，讓 boss 視覺上穩穩站在甜甜圈路面正中間——原本刻意偏內緣是想讓
## 短程法術更有機會構到，但使用者實測後覺得巡邏路徑偏一邊很奇怪，要求置中，見 BOSS_DESIGN.md）→
## ARENA_RADIUS（boss 環道外緣，整個場地的最外圈）。ARENA_CENTER/ARENA_RADIUS 這兩個
## 常數名稱沿用改圓形場地時就有的慣例，其他腳本（Boss/BossClone/BossOrb/SpellProjectile）
## 直接拿這些常數當全域座標的邊界判斷用，不用額外處理節點位移。
##
## Main.tscn 的玩家牆壁碰撞（Walls/Boundary，CollisionPolygon2D）現在只圍 PLAYER_ZONE_RADIUS
## 這一圈——boss/分身不走物理碰撞（手動控制位置，collision_mask=0），場景裡不需要為外圈
## 另外做碰撞形狀，純粹靠 Boss.gd 自己的巡邏公式跟 _clamp_to_arena() 的邊界夾限維持在環道內。

const TILE_SIZE := 56.0
const ARENA_CENTER := Vector2(600.0, 350.0)

const PLAYER_ZONE_RADIUS := 260.0 # 玩家場地：只能在這個圓圈裡移動（Main.tscn 的牆壁碰撞也圍這一圈）；原本220，使用者要求稍微放大
const GAP_WIDTH := 100.0 # 內圈跟外圈之間完全淨空的縫隙寬度，兩個場地靠這個隔開、不能互通
const BOSS_RING_INNER_RADIUS := PLAYER_ZONE_RADIUS + GAP_WIDTH # 360，縫隙外緣＝boss 環道內緣
const ARENA_RADIUS := 450.0 # boss 環道外緣，整個場地的最外圈；原本500，配合環道縮窄一半下修
const BOSS_TRACK_RADIUS := (BOSS_RING_INNER_RADIUS + ARENA_RADIUS) / 2.0 # 405，環道正中央，見上方說明

const WALL_THICKNESS := 24.0 # 原本36→改薄成16後使用者反映太薄，調回中間值
const BRICK_SEED := 9173

## key=Vector2i(x,y) 格子索引，只存內圈場地或外圈環帶裡的格子，縫隙範圍內的格子不產生、不畫。
var tile_colors: Dictionary = {}

func _ready() -> void:
	_generate_tile_colors()
	queue_redraw()

## 在不在場地範圍內的判斷現在分兩種：內圈（距離 <= PLAYER_ZONE_RADIUS）或外圈環帶
## （BOSS_RING_INNER_RADIUS <= 距離 <= ARENA_RADIUS）——落在中間縫隙的格子直接跳過不產生，
## 這就是兩個場地視覺上「不能互通」的來源：縫隙那一圈螢幕上只會露出背景色，沒有地板可走。
func _generate_tile_colors() -> void:
	var span := int(ceil(ARENA_RADIUS * 2.0 / TILE_SIZE)) + 2
	var rng := RandomNumberGenerator.new()
	rng.seed = BRICK_SEED
	tile_colors.clear()
	for y in range(span):
		var row_offset: float = (TILE_SIZE / 2.0) if y % 2 == 1 else 0.0
		for x in range(span):
			var cx: float = x * TILE_SIZE - row_offset + TILE_SIZE / 2.0 - ARENA_RADIUS
			var cy: float = y * TILE_SIZE + TILE_SIZE / 2.0 - ARENA_RADIUS
			var dist := Vector2(cx, cy).length()
			var in_player_zone := dist <= PLAYER_ZONE_RADIUS
			var in_boss_ring := dist >= BOSS_RING_INNER_RADIUS and dist <= ARENA_RADIUS
			if not (in_player_zone or in_boss_ring):
				continue
			var shade: float = rng.randf_range(-0.05, 0.05)
			tile_colors[Vector2i(x, y)] = Color(0.4 + shade, 0.4 + shade, 0.43 + shade)

## 磚塊加一個簡單的浮雕邊（左上亮、右下暗），模擬磚塊本身有一點高度、不是完全貼平的色塊。
func _draw() -> void:
	for key in tile_colors:
		var row_offset: float = (TILE_SIZE / 2.0) if key.y % 2 == 1 else 0.0
		var rect := Rect2(
			ARENA_CENTER.x + key.x * TILE_SIZE - row_offset - ARENA_RADIUS,
			ARENA_CENTER.y + key.y * TILE_SIZE - ARENA_RADIUS,
			TILE_SIZE - 2, TILE_SIZE - 2
		)
		var base_color: Color = tile_colors[key]
		draw_rect(rect, base_color)
		var highlight := base_color.lightened(0.18)
		var shade := base_color.darkened(0.18)
		draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), highlight, 2.0)
		draw_line(rect.position, rect.position + Vector2(0, rect.size.y), highlight, 2.0)
		draw_line(rect.position + Vector2(0, rect.size.y), rect.position + rect.size, shade, 2.0)
		draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, shade, 2.0)
		draw_rect(rect, Color(0.22, 0.22, 0.24), false, 1.5)

	# 三道牆各自都有「內緣亮/外緣暗」的浮雕邊（離場地中心較近的那一側是亮面）：玩家場地外牆、
	# boss 環道內牆（縫隙那一側）、boss 環道外牆（場地最外圈）。縫隙本身完全不畫任何裝飾，
	# 純粹是背景色露出來，視覺上就是兩個場地之間一圈空蕩蕩的深淵。
	_draw_ring_wall(PLAYER_ZONE_RADIUS, Color(0.28, 0.26, 0.3), true)
	_draw_ring_wall(BOSS_RING_INNER_RADIUS, Color(0.3, 0.22, 0.24), false)
	_draw_ring_wall(ARENA_RADIUS, Color(0.28, 0.26, 0.3), true)

## grow_outward=true：牆體從 radius 往外凸（適用「牆在地板外側」的情況，例如玩家場地外牆、
## boss 環道外牆）。grow_outward=false：牆體從 radius 往內凸（適用「牆在地板內側、朝縫隙凸」
## 的情況，目前只有 boss 環道內牆）。不管哪個方向，亮邊永遠在離 ARENA_CENTER 較近的那一側、
## 暗邊在較遠的那一側——這樣三道牆的明暗方向看起來才一致，不會因為凸出方向不同而兩道牆
## 亮暗相反、看起來不協調。
func _draw_ring_wall(radius: float, border_color: Color, grow_outward: bool) -> void:
	var band_start: float = radius if grow_outward else radius - WALL_THICKNESS
	var band_end: float = radius + WALL_THICKNESS if grow_outward else radius
	var mid: float = (band_start + band_end) / 2.0
	draw_arc(ARENA_CENTER, mid, 0, TAU, 96, border_color, WALL_THICKNESS, true)
	draw_arc(ARENA_CENTER, band_start + 2.0, 0, TAU, 96, border_color.lightened(0.35), 4.0, true)
	draw_arc(ARENA_CENTER, band_end - 2.0, 0, TAU, 96, border_color.darkened(0.4), 4.0, true)
