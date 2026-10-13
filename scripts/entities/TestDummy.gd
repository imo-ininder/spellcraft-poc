extends StaticBody2D

## 法術測試場（scripts/SpellTestRange.gd）用的假敵人，純粹是個會吃傷害、會跳一下、會跳
## 傷害數字的靶子，沒有 AI／攻擊／分身——刻意不跟 Boss.gd 共用畫法（使用者明確要求不要
## 長得像 boss，單純一根站在原地的棍子就好，降低這個測試工具跟正式戰鬥場景的視覺混淆）。

const MAX_HP := 200.0

var hp := MAX_HP
var flash_timer := 0.0
var squash := 1.0

func _ready() -> void:
	add_to_group("enemies")

func take_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	flash_timer = 0.15
	_spawn_damage_label(amount, false)
	_bounce()
	queue_redraw()
	if hp <= 0.0:
		hp = MAX_HP

## 安靜扣血（DamageZone.gd 的 DOT 模式用，見 docs/SPELL_SYSTEM.md）：只扣血＋跳一個比較
## 不顯眼的傷害數字，不閃白／不彈一下／不擊退——站在燃燒地面上應該是持續流血的感覺，不是
## 每個 tick 都像被揍一次。跟 take_damage() 共用扣血夾限/死亡重置邏輯，不要各自維護一份。
func take_dot_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	_spawn_damage_label(amount, true)
	if hp <= 0.0:
		hp = MAX_HP

## 刻意不實作真正的擊退位移——假敵人要固定站在場地正中央，才能跟 TestRangeFloor.gd 畫的
## 同心圓參考線對得上，不然挨幾次擊退就飄離圓心，量測距離就沒意義了。
func apply_knockback(_force: Vector2) -> void:
	pass

func _bounce() -> void:
	squash = 1.35
	var tween := create_tween()
	tween.tween_property(self, "squash", 1.0, 0.25).set_trans(Tween.TRANS_ELASTIC)

func _spawn_damage_label(amount: float, is_dot: bool = false) -> void:
	var label := Label.new()
	label.text = str(int(amount))
	label.position = Vector2(randf_range(-10, 10), -50)
	label.modulate = Color(1, 0.5, 0.2, 0.6) if is_dot else Color(1, 0.8, 0.2)
	if is_dot:
		label.add_theme_font_size_override("font_size", 12)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
	queue_redraw()

## 單純一根打擊棍：地面貼一個壓扁橢圓陰影（GroundProjection.squash，集中管理），棍身被打中時
## 閃白、squash 擠壓一下（這個 squash 是下面被打擠壓動畫用的變數，跟地面壓扁係數是兩回事，
## 剛好同名要注意別搞混），沒有其他裝飾——這個測試工具不需要角色感，只要「看得出打中了」就夠。

func _draw() -> void:
	draw_set_transform(Vector2(0, 30), 0.0, Vector2(1.0, GroundProjection.squash))
	draw_circle(Vector2.ZERO, 18, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var body_color := Color(0.6, 0.45, 0.32)
	if flash_timer > 0.0:
		body_color = body_color.lerp(Color(1, 1, 1), flash_timer / 0.15)
	var half_w: float = 7.0 * squash
	var height: float = 90.0 / squash
	draw_rect(Rect2(-half_w, -height, half_w * 2.0, height), body_color)
	draw_circle(Vector2(0, -height), 10.0 * squash, body_color.lightened(0.25))
