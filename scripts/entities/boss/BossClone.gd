extends StaticBody2D

## 分身術召喚出來的分身：3 HP，死掉就消失，沒有自己的 AI——週期招式（丟火球/光球連擊）
## 由 Boss 統一觸發，這裡只被動提供 global_position 當施法原點。視覺上跟 Boss 用同一套
## 畫法（Boss._draw_boss_body()，static func），玩家分不出哪個是本體。

const MAX_HP := 3.0
const KNOCKBACK_FRICTION := 900.0

var hp := MAX_HP
var flash_timer := 0.0
var squash := 1.0
var idle_bob := 0.0
var knockback_velocity := Vector2.ZERO

## 沒有自己的狀態機，要不要移動純粹聽 Boss 指揮（Boss._set_wandering()）。角度也不是自己
## 決定——Boss._sync_clone_formation() 每幀持續寫入 track_angle，維持跟本體/其他分身之間
## 等分角度、沿外圈固定軌道巡邏的隊形，這裡只負責照目前的角度算出軌道上的座標。
var is_wandering := true
var track_angle := 0.0

## 本體讀氣召喚新分身時，這隻分身並不是真的在做任何事——只是視覺上「假裝」跟著一起施法
## （停下來、頭上也亮起讀氣光環），讓畫面看起來像一整群同步施法，不是只有本體在忙。
## Boss._start_clone_summon()/_set_pretend_channeling() 統一開關、Boss._process_ai() 每幀同步
## pretend_progress，這隻分身自己完全不會因為這個狀態觸發任何實際行為。
var is_pretend_channeling := false
var pretend_progress := 0.0

signal died

func _ready() -> void:
	add_to_group("enemies")

func take_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	flash_timer = 0.15
	_spawn_damage_label(amount)
	_bounce()
	queue_redraw()
	if hp <= 0.0:
		MagicFX.spawn_burst(get_tree().current_scene, global_position, Color(0.7, 0.4, 1.0), 20, 240.0)
		died.emit()
		queue_free()

func apply_knockback(force: Vector2) -> void:
	knockback_velocity += force

func _bounce() -> void:
	squash = 1.35
	var tween := create_tween()
	tween.tween_property(self, "squash", 1.0, 0.25).set_trans(Tween.TRANS_ELASTIC)

func _spawn_damage_label(amount: float) -> void:
	var label := Label.new()
	label.text = str(int(amount))
	label.position = Vector2(randf_range(-10, 10), -50)
	label.modulate = Color(1, 0.8, 0.2)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
	idle_bob += delta * 2.0
	if is_wandering:
		_process_patrol()
	if knockback_velocity.length() > 1.0:
		global_position += knockback_velocity * delta
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		knockback_velocity = Vector2.ZERO
	# 同 Boss.gd：不管巡邏還是被擊退，每幀都要夾回環道範圍內，不是只在擊退分支裡夾。
	_clamp_to_arena()
	queue_redraw()

func _clamp_to_arena() -> void:
	var offset: Vector2 = global_position - Arena.ARENA_CENTER
	var dist := offset.length()
	if dist > Arena.ARENA_RADIUS:
		global_position = Arena.ARENA_CENTER + offset.normalized() * Arena.ARENA_RADIUS
	elif dist < Arena.BOSS_RING_INNER_RADIUS and dist > 0.1:
		global_position = Arena.ARENA_CENTER + offset.normalized() * Arena.BOSS_RING_INNER_RADIUS

## 位置純粹是 track_angle 的函式（固定半徑 Arena.BOSS_TRACK_RADIUS），track_angle 本身不在這裡
## 自己累加——由 Boss._sync_clone_formation() 每幀寫入「本體角度+固定偏移」，本體角度持續增加，
## 這裡跟著平滑移動，不需要自己的計時/追趕邏輯。
func _process_patrol() -> void:
	global_position = Arena.ARENA_CENTER + Vector2(cos(track_angle), sin(track_angle)) * Arena.BOSS_TRACK_RADIUS

func _draw() -> void:
	Boss._draw_boss_body(self, hp, MAX_HP, flash_timer, squash, idle_bob)
	# 跟 Boss._draw() 的讀氣光環畫法完全一樣（同一段程式碼複製一份，不是呼叫共用函式，
	# 跟整個檔案「視覺共用、程式碼各自一份」的慣例一致）——差別只在這裡是「假裝」讀氣，
	# 不是真的在倒數 channel_timer。
	if is_pretend_channeling:
		draw_arc(Vector2.ZERO, 46, -PI / 2.0, -PI / 2.0 + pretend_progress * TAU, 32, Color(1, 0.3, 0.9, 0.9), 4.0, false)
		draw_arc(Vector2.ZERO, 46, 0, TAU, 32, Color(1, 0.3, 0.9, 0.25), 2.0, true)
