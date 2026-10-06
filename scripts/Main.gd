extends Node2D

@onready var player := $Player
@onready var boss := $Boss
@onready var cast_bar: ProgressBar = $UI/CastBar
@onready var feat_container: HBoxContainer = $UI/FeatContainer
@onready var combo_label: Label = $UI/ComboLabel
@onready var cd_bar: ProgressBar = $UI/CDBar
@onready var cd_label: Label = $UI/CDLabel
@onready var spell_wheel: SpellWheel = $UI/SpellWheel
@onready var debug_bg: ColorRect = $UI/DebugBg
@onready var debug_label: Label = $UI/DebugLabel

## 開發用除錯面板：按 F3 切換，預設關閉（不要讓一般遊玩畫面一直有一大塊文字）。這個鍵刻意
## 不走 Input Map，直接用 is_physical_key_pressed() 判斷——跟 Ctrl 輪盤同樣理由（見
## SPELL_SYSTEM.md §8.11）：手刻 InputEventKey 寫錯了 Godot 不會報錯、只是永遠不觸發，
## 符號常數風險低很多。顯示 boss 目前狀態機/CD、玩家目前生效中的 buff，純粹讓開發時能肉眼
## 確認「出招邏輯有沒有照預期跑」「buff 有沒有正確上/卸」，不是正式 HUD 的一部分。
var debug_visible := false
var _f3_was_pressed := false

## 跟 Boss.gd 的 enum BossState 順序手動對應（GDScript 沒有簡單的「enum 值轉名稱」反射），
## 改動 Boss.gd 的 enum 定義時記得同步更新這份清單，不然這裡顯示的名稱會對不上。
const BOSS_STATE_NAMES := ["IDLE", "CLONE_SUMMON_BUFFER", "CASTING_CLONE_SUMMON", "ATTACK_FIREBALL", "ATTACK_ORB_BARRAGE", "ATTACK_SUCTION"]
const BOSS_ATTACK_NAMES := ["FIREBALL", "ORB_BARRAGE"]

func _ready() -> void:
	player.cast_started.connect(_on_cast_started)
	player.cast_progress.connect(_on_cast_progress)
	player.cast_ended.connect(_on_cast_ended)
	player.feat_added.connect(_on_feat_added)
	player.combo_failed.connect(_on_combo_failed)
	player.rightclick_cd_updated.connect(_on_cd_updated)
	player.spell_wheel_opened.connect(_on_wheel_opened)
	player.spell_wheel_hover_changed.connect(_on_wheel_hover_changed)
	player.spell_wheel_closed.connect(_on_wheel_closed)
	cast_bar.visible = false
	combo_label.text = ""
	cd_label.text = "右鍵CD: 就緒"

func _on_wheel_opened(center: Vector2, current_index: int) -> void:
	spell_wheel.open(player.equipped_spells, center, current_index)

func _on_wheel_hover_changed(index: int) -> void:
	spell_wheel.update_hover(index)

func _on_wheel_closed(_selected_index: int) -> void:
	spell_wheel.close()

func _on_cast_started() -> void:
	cast_bar.visible = true
	cast_bar.value = 0
	for child in feat_container.get_children():
		child.queue_free()
	combo_label.text = "吟唱中... WASD 輸入超魔專長"
	combo_label.modulate = Color(1, 1, 1)

func _on_cast_progress(ratio: float) -> void:
	cast_bar.value = ratio * 100

func _on_cast_ended() -> void:
	cast_bar.visible = false
	combo_label.text = ""

func _on_feat_added(feat_data) -> void:
	var label := Label.new()
	label.text = feat_data.get("label", "?")
	label.modulate = feat_data.get("color", Color.WHITE)
	feat_container.add_child(label)
	combo_label.text = "超魔專長成功！"
	combo_label.modulate = Color(0.4, 1, 0.5)

func _on_combo_failed() -> void:
	combo_label.text = "超魔專長失敗，重新輸入"
	combo_label.modulate = Color(1, 0.3, 0.3)

func _on_cd_updated(ratio: float) -> void:
	cd_bar.value = ratio * 100
	if ratio >= 1.0:
		cd_label.text = "右鍵CD: 就緒"
	else:
		cd_label.text = "右鍵CD: %.1f s" % ((1.0 - ratio) * 3.0)

func _process(_delta: float) -> void:
	var f3_pressed := Input.is_physical_key_pressed(KEY_F3)
	if f3_pressed and not _f3_was_pressed:
		debug_visible = not debug_visible
		debug_bg.visible = debug_visible
		debug_label.visible = debug_visible
	_f3_was_pressed = f3_pressed
	if debug_visible:
		debug_label.text = _build_debug_text()

func _build_debug_text() -> String:
	var lines: Array[String] = ["[F3] 除錯面板", ""]

	lines.append("--- Player buff ---")
	lines.append("is_invisible: %s" % player.is_invisible)
	lines.append("speed_boost_mult: %.2f" % player.speed_boost_mult)
	if player.active_buffs.is_empty():
		lines.append("active_buffs: (無)")
	else:
		lines.append("active_buffs:")
		for entry in player.active_buffs:
			lines.append("  %s: 剩 %.1fs" % [entry.effect.buff_id, entry.timer])

	lines.append("")
	lines.append("--- Boss AI ---")
	if is_instance_valid(boss):
		var state_idx: int = boss.state
		var state_name: String = BOSS_STATE_NAMES[state_idx] if state_idx < BOSS_STATE_NAMES.size() else str(state_idx)
		var next_idx: int = boss.next_attack
		var next_name: String = BOSS_ATTACK_NAMES[next_idx] if next_idx < BOSS_ATTACK_NAMES.size() else str(next_idx)
		lines.append("state: %s" % state_name)
		lines.append("next_attack: %s" % next_name)
		lines.append("attack_cd_timer: %.1fs" % boss.attack_cd_timer)
		lines.append("clone_cd_timer: %.1fs" % boss.clone_cd_timer)
		lines.append("clones: %d" % boss.clones.size())
		lines.append("is_wandering: %s" % boss.is_wandering)
		lines.append("is_patrol_moving: %s" % boss.is_patrol_moving)
		lines.append("track_angle: %.2f" % boss.track_angle)
		if boss.state == Boss.BossState.CASTING_CLONE_SUMMON:
			lines.append("channel_timer: %.1fs (傷害已累積 %.0f)" % [boss.channel_timer, boss.channel_damage_taken])
	else:
		lines.append("(boss 不存在)")

	return "\n".join(lines)
