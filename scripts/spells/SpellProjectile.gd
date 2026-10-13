class_name SpellProjectile
extends Area2D

## 共用的「直線投射物飛行骨架」——怎麼往前飛、飛多遠算到底、撞牆怎麼反彈、撞到東西怎麼交給
## impact.resolve() 處理。這些純粹是飛行物理，任何一把法術的直線投射物都需要一模一樣的版本，
## 不是「法術差異化」會發生的地方（2026-10-13 討論定案：法術的長相/收尾手感要各自拆開，但
## 純直線飛行的數學沒有「選擇意義」，複製只會製造維護負擔，不會讓任何一把法術感覺更獨特——
## 細節見 docs/SPELL_SYSTEM.md）。
##
## 這個類別不會被直接拿來生成，實際場景永遠是子類別：
## - `FireballProjectile`（火球術）：命中/飛到底爆炸範圍傷害，圓球+火花拖尾的長相。
## - `FireArrowProjectile`（火焰箭）：全程穿透不消失，紅色射線伸展+收尾的長相。
## 子類別各自覆寫自己的「長相」（`_draw()`）跟「飛到底之後要做什麼」（`_on_max_range_reached()`，
## 預設是立刻 `_resolve(null)`），兩邊的程式碼完全不會互相碰到。之後如果某把法術的移動方式
## 根本不是直線飛行（例如射出型火牆、位移類），不需要繼承這個類別，直接寫自己的場景/腳本
## 即可，不受這裡的架構綁住。

var velocity := Vector2.ZERO
var damage := 10.0
var max_range := 650.0
## 世界座標（原始、未校正）累積飛行距離——子類別的本地座標長相（例如 FireArrowProjectile
## 的射線長度）要用這個，因為 position 本身也是用原始世界座標在移動，兩者要對得上。
var distance_traveled := 0.0
## 2026-10-13 系統性修正：max_range 的「到底了沒」判斷不能用上面的原始距離——使用者發現
## 投射物往垂直方向飛的視覺飛行距離，會比往水平方向飛明顯短（壓扁視角下，同樣的世界座標
## 位移量，Y 方向「看起來」比 X 方向短，詳見 GroundProjection.offset_towards() 的註解）。
## 這裡另外累積一份投影後距離，只用在 max_range 判斷，不影響 distance_traveled 的其他用途。
var projected_distance_traveled := 0.0
var impact: ProjectileImpact
var bounces_off_walls := false
var _resolved := false

## 投射物的大小/寬度，由 `ProjectileSpell.size`（見該檔案）傳進來——子類別各自決定這個數字
## 要怎麼影響碰撞形狀半徑跟長相比例尺，基底類別本身不畫東西、不建碰撞形狀，純粹代為保存這個
## 設定值，在子類別 `_ready()` 真正用到之前（子類別必須在呼叫 `add_child()` 把自己放進場景樹
## 之前就設定好這個欄位，因為碰撞形狀是在 `_ready()` 建的）。
var size := 8.0

## 給 `_bounce_off_arena_bounds()` 反彈火花用的顏色，子類別各自在 `_ready()` 設定自己的主題色。
var trail_color := Color(1, 1, 1)

## speed 由呼叫端（`ProjectileSpell.cast()`）算好，直接當固定飛行速度，不隨 max_range 變動
## ——SpellProjectile 自己只負責照給定的 speed 飛，細節見 docs/SPELL_SYSTEM.md。
func setup(direction: Vector2, dmg: float, range_limit: float, speed: float, impact_behavior: ProjectileImpact, bounce: bool = false) -> void:
	damage = dmg
	max_range = range_limit
	velocity = direction * speed
	impact = impact_behavior
	bounces_off_walls = bounce
	rotation = velocity.angle()

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if _resolved:
		return
	var step := velocity * delta
	position += step
	distance_traveled += step.length()
	projected_distance_traveled += GroundProjection.projected_length(step)
	if bounces_off_walls:
		_bounce_off_arena_bounds()
	queue_redraw()
	if projected_distance_traveled >= max_range:
		_on_max_range_reached()

## 飛到底之後要做什麼——預設直接消失。子類別可以覆寫成別的收尾行為（例如
## `PiercingBoltProjectile` 的延遲+射線收尾），基底類別本身不知道、也不需要知道有這種變化。
func _on_max_range_reached() -> void:
	_resolve(null)

## 用場地邊界的位置判斷做反彈，不是物理碰撞——SpellProjectile 的 collision_mask 刻意不偵測牆壁
## （見 docs/SPELL_SYSTEM.md），這樣才不會影響其他法術既有的飛越牆壁手感。
## 圓形場地：超出半徑時夾回圓周上，velocity 用該點的圓周法線（圓心→該點方向）反射，
## 跟矩形時代「水平/垂直分別判斷、各自翻轉」的做法不同，但效果一樣是「撞到邊界彈回來」。
## 場地改成內圈玩家場地+外圈boss環道之後，這裡要用 PLAYER_ZONE_RADIUS（玩家自己的場地邊界），
## 不是 ARENA_RADIUS（那是外圈boss環道的外緣）——投射物本身是玩家法術，玩家本人被牆物理擋在
## PLAYER_ZONE_RADIUS 以內，投射物的反彈邊界理當跟著玩家能站的範圍走，不是場地最外圈那麼遠
## （用 ARENA_RADIUS 的話，投射物會直接飛穿過縫隙、飛進 boss 環道，在那邊彈來彈去，不合理）。
##
## 2026-10-12 修正：`Arena.ARENA_CENTER`/`Arena.PLAYER_ZONE_RADIUS` 是宣告在 Arena 腳本類別上
## 的 const，不管目前在哪個場景、場景裡有沒有真的放一個 Arena 節點，都讀得到同一組寫死數值
## （Main.tscn 專用的座標）——`scenes/SpellTestRange.tscn` 沒有 Arena 節點、也沒有牆，但投射物
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
	MagicFX.spawn_burst(get_parent(), global_position, trail_color, 8, 120.0)

func _on_body_entered(body: Node) -> void:
	if _resolved:
		return
	_resolve(body)

func _resolve(body: Node) -> void:
	if impact.resolve(self, body):
		_resolved = true
		queue_free()
