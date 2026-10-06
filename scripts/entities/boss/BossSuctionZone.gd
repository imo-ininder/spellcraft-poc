extends Node2D

## 吸引懲罰（見 Boss.gd「太近懲罰」區塊）的單一扇形範圍——永遠只有一個施法者（不像舊版
## 是本體+所有分身一起放），由 Boss._start_suction_punish() 建立並全程監控。
## TELEGRAPH 階段只畫外框、不拉扯，給玩家一瞬間反應時間；過了 telegraph_delay 才進 ACTIVE，
## 開始真正拉扯。方向在 setup() 當下就定住（朝當時玩家的方向），不會持續轉向。
## is_player_inside() 是即時判定（不是曾經命中過就恆真的 sticky flag），Boss 每幀持續讀這個值
## 跟 is_active() 來判斷要不要提前取消、要不要觸發「拉近後重擊」。

enum Phase { TELEGRAPH, ACTIVE }

var caster: Node2D
var range := 320.0
var half_angle := 0.35
var duration := 3.0
var pull_speed := 100.0
var telegraph_delay := 0.4
var phase: Phase = Phase.TELEGRAPH

func setup(c: Node2D, r: float, ha: float, dur: float, ps: float = 100.0, delay: float = 0.4) -> void:
	caster = c
	range = r
	half_angle = ha
	duration = dur
	pull_speed = ps
	telegraph_delay = delay
	global_position = caster.global_position
	var player := _find_player()
	var axis_dir := (player.global_position - global_position).normalized() if player else Vector2.RIGHT
	rotation = axis_dir.angle()

func is_active() -> bool:
	return phase == Phase.ACTIVE

func _process(delta: float) -> void:
	if not is_instance_valid(caster):
		queue_free()
		return
	global_position = caster.global_position
	match phase:
		Phase.TELEGRAPH:
			telegraph_delay -= delta
			if telegraph_delay <= 0.0:
				phase = Phase.ACTIVE
		Phase.ACTIVE:
			duration -= delta
			if duration <= 0.0:
				queue_free()
				return
			var player := _find_player()
			if player and is_player_inside():
				var to_caster: Vector2 = global_position - player.global_position
				if to_caster.length() > 1.0:
					player.global_position += to_caster.normalized() * pull_speed * delta
	queue_redraw()

func is_player_inside() -> bool:
	var player := _find_player()
	if player == null:
		return false
	var offset: Vector2 = player.global_position - global_position
	if offset.length() > range:
		return false
	var angle_diff: float = abs(wrapf(offset.angle() - rotation, -PI, PI))
	return angle_diff <= half_angle

## 玩家隱形時回傳 null，跟 Boss.gd 同一份邏輯（各自複製一份，見專案慣例）——目前這招整個
## 停用中（SUCTION_ENABLED=false），這裡補上純粹是跟其餘三份 _find_player() 保持一致，之後
## 如果重新啟用，不用再回頭補這一塊。
func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty() or players[0].is_invisible:
		return null
	return players[0]

func _draw() -> void:
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	const STEPS := 24
	for s in range(STEPS + 1):
		var a: float = lerp(-half_angle, half_angle, float(s) / float(STEPS))
		points.append(Vector2(cos(a), sin(a)) * range)
	if phase == Phase.TELEGRAPH:
		# 預警：只畫外框不填色、不能拉扯，純粹提示「這個方向要出招了」。
		draw_polyline(points, Color(1, 0.4, 0.9, 0.85), 2.5, true)
	else:
		draw_colored_polygon(points, Color(0.6, 0.1, 0.7, 0.25))
		draw_polyline(points, Color(0.8, 0.3, 0.9, 0.6), 2.0, true)
