extends Node2D

## 光球連擊（見 Boss.gd 的 _start_orb_barrage()）單一顆光球：丟出瞬間鎖定玩家當時位置當方向，
## 之後直線飛行、持續加速，不會轉向追蹤（跟火球雨/雷電箭一樣的公平性設計：鎖定過去的狀態，
## 不持續跟著玩家跑）。撞到場地邊界直接消失，沒有反彈——跟雷電箭的 bounces_off_walls 是
## 不同行為，這招刻意設計成「打偏了就真的打空」，不會意外彈回來補一刀。

const START_SPEED := 220.0
const ACCELERATION := 500.0 # px/s^2，飛行中持續加速，不是固定速度
const RADIUS := 20.0 # 刻意畫大一點，跟火球(預告圈)/雷電箭(細長鋸齒)做出差異，就是顆扎實的大光球
const DAMAGE := 12.0
const HIT_RADIUS := 26.0

var direction := Vector2.ZERO
var speed := START_SPEED
var damage := DAMAGE
var _resolved := false

func setup(from_pos: Vector2, dir: Vector2, dmg: float = DAMAGE) -> void:
	global_position = from_pos
	direction = dir
	damage = dmg

func _process(delta: float) -> void:
	if _resolved:
		return
	speed += ACCELERATION * delta
	global_position += direction * speed * delta
	queue_redraw()

	var offset: Vector2 = global_position - Arena.ARENA_CENTER
	if offset.length() > Arena.ARENA_RADIUS:
		_resolved = true
		queue_free()
		return

	var player := _find_player()
	if player and player.global_position.distance_to(global_position) <= HIT_RADIUS:
		_resolved = true
		player.take_damage(damage)
		MagicFX.spawn_burst(get_parent(), global_position, Color(0.5, 0.85, 1.0), 14, 180.0)
		queue_free()

## 玩家隱形時回傳 null，跟 Boss.gd 同一份邏輯（各自複製一份，見專案慣例）。這個函式同時用在
## 丟出瞬間決定方向、以及飛行中每幀的命中判定（見上面 _process()）——後者代表如果光球已經飛出去
## 之後玩家才隱形，它也會立刻打空，不只是擋住新丟出的光球瞄不準，是「隱形當下就安全」。
func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty() or players[0].is_invisible:
		return null
	return players[0]

## 陰影固定畫在光球正下方一小段距離（不是跟著飛行角度轉），製造「飛在空中」的高度感，
## 跟角色腳下陰影/MagicFX爆炸特效同一套3/4視角語言：壓扁橢圓，不是正圓。
func _draw() -> void:
	var shadow_points := PackedVector2Array()
	for i in range(16):
		var a: float = TAU * float(i) / 16.0
		shadow_points.append(Vector2(0, 16) + Vector2(cos(a) * RADIUS * 0.9, sin(a) * RADIUS * 0.35))
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.3))
	draw_circle(Vector2.ZERO, RADIUS, Color(0.5, 0.85, 1.0, 0.9))
	draw_circle(Vector2.ZERO, RADIUS * 0.5, Color(0.85, 0.95, 1.0, 0.95))
