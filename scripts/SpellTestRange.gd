extends Node2D

## 法術測試場（test arena）。這個場景現在是 Floor/TestDummy/Player 的骨架＋FocusHUD＋F3 除錯面板。
##
## 2026-10-13（Phase 1）：拔掉 CastBar 的綁定——CastBar.gd 顯示的是「固定時長吟唱讀條」，
## 新戰鬥系統沒有這個概念了（一般狀態的近戰/蓄力火球是瞬間判定，專注狀態的符文施法是按下
## 就立即觸發，都沒有「吟唱中」這段期間可以顯示進度）。CastBar.gd／CastBar.tscn 檔案本身
## 沒有刪，只是這個場景不再掛它；UI/CastBar 節點還留在 .tscn 裡（沒人綁定，永遠不可見，
## 無害）。
##
## Phase 2：新增 FocusHUD 綁定，跟 bind(player) 既有慣例一致。
## Phase 4：新增 StatusBars 綁定——血量＋專注值，畫面左上角永遠顯示，同一個 bind(player) 慣例。

@onready var player: CharacterBody2D = $Player
@onready var test_dummy: StaticBody2D = $TestDummy
@onready var focus_hud: FocusHUD = $UI/FocusHUD
@onready var status_bars: StatusBars = $UI/StatusBars
@onready var debug_bg: ColorRect = $UI/DebugBg
@onready var debug_label: Label = $UI/DebugLabel

## F3 除錯面板：故意不走 Input Map，直接用 is_physical_key_pressed()，原因見
## SPELL_SYSTEM.md §8.11。
var debug_visible := false
var _f3_was_pressed := false

func _ready() -> void:
	focus_hud.bind(player)
	status_bars.bind(player)
	debug_bg.visible = false
	debug_label.visible = false

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

	lines.append("--- 測試狀態（docs/DEMO_PLAN.md Phase 1/2/4）---")
	lines.append("is_focused: %s" % player.is_focused)
	lines.append("current_node_id: %s" % player.current_node_id)
	lines.append("combo_buffer: '%s'" % player.combo_buffer)
	lines.append("is_charging: %s" % player.is_charging)
	if player.is_charging:
		lines.append("charge_timer: %.2fs" % player.charge_timer)
	lines.append("focus_value: %.2f / %.2f" % [player.focus_value, player.FOCUS_MAX])
	lines.append("combo_stage: %d" % player.combo_stage)
	lines.append("Engine.time_scale: %.2f" % Engine.time_scale)
	if is_instance_valid(test_dummy):
		lines.append("dummy_hp: %.0f / %.0f" % [test_dummy.hp, test_dummy.MAX_HP])

	lines.append("")
	lines.append("--- Player buff ---")
	lines.append("is_invisible: %s" % player.is_invisible)
	lines.append("speed_boost_mult: %.2f" % player.speed_boost_mult)
	if player.active_buffs.is_empty():
		lines.append("active_buffs: (無)")
	else:
		lines.append("active_buffs:")
		for entry in player.active_buffs:
			lines.append("  %s: 剩 %.1fs" % [entry.effect.buff_id, entry.timer])

	return "\n".join(lines)
