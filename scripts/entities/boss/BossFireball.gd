extends Node2D

## Boss 週期招式之一：頭上出現火球預告，delay 秒後鎖定玩家當時所在的地板座標丟出去——丟出
## 瞬間就定住目標點，不會持續追蹤玩家，飛行過程中不造成任何傷害。一丟出去，爆炸範圍預告圈就
## 已經畫在目標落點上（FLYING 階段也畫，不是等落地才畫），玩家從火球起飛那一刻就看得到完整的
## 危險範圍；飛到定住的目標點就直接爆炸，落地不等延遲（使用者要求拿掉落地後的額外延遲——
## 預告已經在飛行全程顯示過了，落地再緩一拍沒意義）。不走 Spell/SpellDelivery 架構，獨立的
## 小腳本，由 Boss._spawn_fireball() 在 get_tree().current_scene 下建立。
##
## exploded signal：有分身在場時，Boss 要等上一顆火球真正爆炸完才讓下一個施法者開始丟
## （見 Boss._start_fireball_attack() 的 await fireball.exploded），不是固定錯開時間並行丟。

const FLY_SPEED := 420.0
const HEAD_OFFSET := Vector2(0, -50)
const IMPACT_RADIUS := 95.0
## 3/4視角風格：落點預告是貼在地上的範圍，要跟角色陰影/MagicFX爆炸特效同一套「壓扁成橢圓」
## 視覺語言，不是正圓——跟 AoETargetingReticle.gd 的 GROUND_SQUASH 保持一致的壓扁比例。
const GROUND_SQUASH := 0.5

enum Phase { TELEGRAPH, FLYING }

var delay := 0.3
var damage := 10.0
var velocity := Vector2.ZERO
var phase: Phase = Phase.TELEGRAPH
var target_pos := Vector2.ZERO
var target_distance := 0.0
var distance_traveled := 0.0
## queue_free() 延遲到這一幀結束才真的生效，呼叫後節點短暫還是「活著」的，這個旗標避免
## 爆炸判定被重複觸發（跟 SpellProjectile.gd 的 _resolved 是同一個坑）。
var _resolved := false

signal exploded

func setup(from_pos: Vector2, cast_delay: float, dmg: float) -> void:
	global_position = from_pos + HEAD_OFFSET
	delay = cast_delay
	damage = dmg

func _process(delta: float) -> void:
	if _resolved:
		return
	match phase:
		Phase.TELEGRAPH:
			delay -= delta
			queue_redraw()
			if delay <= 0.0:
				_throw()
		Phase.FLYING:
			var step := velocity * delta
			global_position += step
			distance_traveled += step.length()
			queue_redraw()
			if distance_traveled >= target_distance:
				_explode()

## 丟出瞬間鎖定玩家當時所在的地板座標（target_pos），之後飛行方向/終點都不再變動，不是持續追蹤。
func _throw() -> void:
	phase = Phase.FLYING
	var player := _find_player()
	target_pos = player.global_position if player else global_position + Vector2.DOWN * 200.0
	target_distance = global_position.distance_to(target_pos)
	velocity = (target_pos - global_position).normalized() * FLY_SPEED if target_distance > 1.0 else Vector2.ZERO
	MagicFX.spawn_burst(get_parent(), global_position, Color(1, 0.5, 0.1), 10, 150.0)

## 飛到鎖定的地板座標就直接爆炸，沒有落地延遲。
func _explode() -> void:
	_resolved = true
	global_position = target_pos
	var player := _find_player()
	if player and _is_inside_impact_ellipse(player.global_position):
		player.take_damage(damage)
	MagicFX.spawn_burst(get_parent(), target_pos, Color(1, 0.5, 0.1), 24, 260.0)
	MagicFX.spawn_explosion_ring(get_parent(), target_pos, IMPACT_RADIUS, Color(1, 0.35, 0.1))
	exploded.emit()
	queue_free()

## 玩家隱形時回傳 null，跟 Boss.gd 同一份邏輯（各自複製一份，見專案慣例），讓火球雨丟出瞬間
## 鎖不到玩家位置、落在目標消失時的 fallback 落點（caster 下方），不是真的打中隱形中的玩家。
func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty() or players[0].is_invisible:
		return null
	return players[0]

## 傷害判定要跟畫出來的範圍預告一致——預告是壓扁成橢圓畫的（GROUND_SQUASH），但命中判定
## 之前還是用 distance_to() <= IMPACT_RADIUS 這種正圓算法，兩者對不上：玩家站在橢圓外面但
## 正圓範圍內的地方（例如落點正上方/正下方，y方向因為壓扁比x方向窄很多）照理說不該中，
## 卻因為判定還是正圓而被打到。用跟繪圖同一個比例去正規化座標再檢查距離，確保「畫出來的範圍」
## 跟「真的會受傷的範圍」是同一塊。
func _is_inside_impact_ellipse(point: Vector2) -> bool:
	var offset: Vector2 = point - target_pos
	var nx: float = offset.x / IMPACT_RADIUS
	var ny: float = offset.y / (IMPACT_RADIUS * GROUND_SQUASH)
	return nx * nx + ny * ny <= 1.0

## 貼地範圍預告用的橢圓（填色多邊形版），跟 AoETargetingReticle._draw_ground_ellipse() 同一種
## 「cos/sin 乘不同半徑湊橢圓」手法，這裡額外需要填色（不只是描邊），所以用 draw_colored_polygon。
func _draw_ground_ellipse_fill(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32):
		var a: float = TAU * float(i) / 32.0
		points.append(center + Vector2(cos(a) * radius, sin(a) * radius * GROUND_SQUASH))
	draw_colored_polygon(points, color)

func _draw_ground_ellipse_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(65):
		var a: float = TAU * float(i) / 64.0
		points.append(center + Vector2(cos(a) * radius, sin(a) * radius * GROUND_SQUASH))
	draw_polyline(points, color, width, true)

func _draw() -> void:
	match phase:
		Phase.TELEGRAPH:
			var pulse := 6.0 + sin(delay * 10.0) * 2.0
			draw_circle(Vector2.ZERO, pulse, Color(1, 0.5, 0.1, 0.8))
			draw_arc(Vector2.ZERO, pulse + 3, 0, TAU, 16, Color(1, 0.8, 0.3, 0.6), 2.0, true)
		Phase.FLYING:
			# 爆炸範圍預告：一丟出去就先畫在落點上（target_pos 換算成相對這顆火球目前位置的 local 座標），
			# 不用等落地——玩家從起飛那一刻就能看到完整危險範圍，提早決定要不要躲。壓成橢圓而不是正圓，
			# 跟地面其他範圍指示（陰影/爆炸特效/AoE選取圈）保持同一套3/4視角語言。
			var local_target := to_local(target_pos)
			_draw_ground_ellipse_fill(local_target, IMPACT_RADIUS, Color(1, 0.3, 0.1, 0.12))
			_draw_ground_ellipse_outline(local_target, IMPACT_RADIUS, Color(1, 0.5, 0.2, 0.35), 2.0)
			draw_circle(Vector2.ZERO, 10, Color(1, 0.5, 0.1))
			draw_circle(Vector2.ZERO, 5, Color(1, 0.85, 0.3))
