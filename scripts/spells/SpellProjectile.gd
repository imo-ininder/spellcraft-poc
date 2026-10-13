extends Area2D

var velocity := Vector2.ZERO
var damage := 10.0
var spin := 0.0
var orb_color := Color(1, 0.9, 0.2)
var trail: CPUParticles2D
var max_range := 650.0
var distance_traveled := 0.0
var impact: ProjectileImpact
var bounces_off_walls := false
var _resolved := false

## speed 由呼叫端（ProjectileDelivery.fire()）算好：預設是「travel_time 秒內飛完 max_range」反推出來的，
## 但 fixed_speed>0 的法術（例如雷電箭）會直接給固定值，不隨 max_range 變動——SpellProjectile 自己
## 不管是哪一種，只負責照給定的 speed 飛，細節見 docs/SPELL_SYSTEM.md。
func setup(direction: Vector2, dmg: float, range_limit: float, speed: float, impact_behavior: ProjectileImpact, bounce: bool = false) -> void:
	damage = dmg
	max_range = range_limit
	velocity = direction * speed
	impact = impact_behavior
	bounces_off_walls = bounce
	rotation = velocity.angle()
	if impact is ExplosiveImpact:
		orb_color = Color(1.0, 0.45, 0.15)
	elif impact is PiercingImpact:
		orb_color = Color(0.3, 0.9, 1.0)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	trail = MagicFX.make_sparkle_trail(self, orb_color)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if _resolved:
		return
	var step := velocity * delta
	position += step
	distance_traveled += step.length()
	if bounces_off_walls:
		_bounce_off_arena_bounds()
	spin += delta * 20.0
	queue_redraw()
	if distance_traveled >= max_range:
		_resolve(null)

## 用場地邊界的位置判斷做反彈，不是物理碰撞——SpellProjectile 的 collision_mask 刻意不偵測牆壁
## （見 docs/SPELL_SYSTEM.md），這樣才不會影響 Fireball 等其他法術既有的飛越牆壁手感。
## 圓形場地：超出半徑時夾回圓周上，velocity 用該點的圓周法線（圓心→該點方向）反射，
## 跟矩形時代「水平/垂直分別判斷、各自翻轉」的做法不同，但效果一樣是「撞到邊界彈回來」。
## 場地改成內圈玩家場地+外圈boss環道之後，這裡要用 PLAYER_ZONE_RADIUS（玩家自己的場地邊界），
## 不是 ARENA_RADIUS（那是外圈boss環道的外緣）——雷電箭是玩家法術，玩家本人被牆物理擋在
## PLAYER_ZONE_RADIUS 以內，投射物的反彈邊界理當跟著玩家能站的範圍走，不是場地最外圈那麼遠
## （用 ARENA_RADIUS 的話，投射物會直接飛穿過縫隙、飛進 boss 環道，在那邊彈來彈去，不合理）。
##
## 2026-10-12 修正：`Arena.ARENA_CENTER`/`Arena.PLAYER_ZONE_RADIUS` 是宣告在 Arena 腳本類別上
## 的 const，不管目前在哪個場景、場景裡有沒有真的放一個 Arena 節點，都讀得到同一組寫死數值
## （Main.tscn 專用的座標）——`scenes/SpellTestRange.tscn` 沒有 Arena 節點、也沒有牆，但雷電箭
## 照樣會拿 Main.tscn 的場地座標來反彈，導致看起來「沒有從角色位置發射」（玩家出生點離
## Arena.ARENA_CENTER 的距離本來就超出 PLAYER_ZONE_RADIUS，第一幀就被夾限彈飛）＋「沒有牆的
## 地方也會反彈」兩個症狀，其實是同一個根因。改成先確認目前場景真的有 Arena 節點（代表真的在
## Main.tscn 那種有圍牆的場地）才套用這段邊界判斷，沒有的場景（SpellTestRange 這種開放測試場）
## 直接跳過，讓投射物單純飛到 max_range 自然消失，不套用任何場地邊界反彈。
##
## 2026-10-12：場地改成壓扁橢圓後，夾限改用 GroundProjection.clamp_to_radius()（跟
## AoETargetingReticle.gd 選點夾限同一套數學），反彈法線改用 GroundProjection.ellipse_normal()
## 算真正的橢圓法線——不能再用 offset.normalized()（那是正圓公式，橢圓上任一點的法線方向跟
## 「圓心→該點」方向不同，尤其長短軸差距越大偏差越明顯，用正圓公式會讓反彈角度肉眼可見地不對）。
func _bounce_off_arena_bounds() -> void:
	if not get_tree().current_scene.has_node("Arena"):
		return
	if GroundProjection.projected_distance(global_position, Arena.ARENA_CENTER) <= Arena.PLAYER_ZONE_RADIUS:
		return
	global_position = GroundProjection.clamp_to_radius(Arena.ARENA_CENTER, global_position, Arena.PLAYER_ZONE_RADIUS)
	var normal := GroundProjection.ellipse_normal(Arena.ARENA_CENTER, Arena.PLAYER_ZONE_RADIUS, global_position)
	velocity = velocity.bounce(normal)
	rotation = velocity.angle()
	MagicFX.spawn_burst(get_parent(), global_position, orb_color, 8, 120.0)

func _on_body_entered(body: Node) -> void:
	if _resolved:
		return
	_resolve(body)

func _resolve(body: Node) -> void:
	if impact.resolve(self, body):
		_resolved = true
		queue_free()

const BOLT_LENGTH := 44.0
const BOLT_SEGMENTS := 6

func _draw() -> void:
	if impact is PiercingImpact:
		_draw_bolt()
	else:
		_draw_orb()

func _draw_orb() -> void:
	draw_circle(Vector2.ZERO, 9, Color(orb_color, 0.35))
	draw_circle(Vector2.ZERO, 6, orb_color)
	draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1))
	for i in range(3):
		var a := spin + i * (TAU / 3.0)
		draw_circle(Vector2(cos(a), sin(a)) * 10, 1.5, Color(1, 1, 1, 0.8))

## 雷電箭專用畫法：沿著飛行方向（本地 +X 軸，setup()/反彈時都會更新 rotation）拖出一條
## 會抖動的鋸齒長條，頭尖尾散，用 spin 讓它邊飛邊electric crackle，不是一個圓點。
func _draw_bolt() -> void:
	var points := PackedVector2Array()
	for i in range(BOLT_SEGMENTS + 1):
		var t := float(i) / float(BOLT_SEGMENTS)
		var x: float = lerp(8.0, -BOLT_LENGTH, t)
		var taper := sin(t * PI)
		var jitter := sin(spin * 4.0 + i * 2.3) * 5.0 * taper
		points.append(Vector2(x, jitter))
	draw_polyline(points, Color(orb_color, 0.3), 11.0, true)
	draw_polyline(points, Color(orb_color, 0.7), 5.5, true)
	draw_polyline(points, Color(1, 1, 1, 0.95), 2.0, true)
	draw_circle(points[0], 3.5, Color(1, 1, 1, 1.0))
