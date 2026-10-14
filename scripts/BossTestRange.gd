extends Node2D

## Boss 互動測試場——Floor + FurnaceGuardian + 玩家角色，用來驗證設計文件（使用者提供的
## 「熔爐守衛 Prototype Boss Design v0.1」）描述的玩家/Boss 互動：讀招、走位閃避、利用
## 硬直視窗反擊、專注狀態演化法術。
##
## 2026-10-13：玩家角色接進來了——一開始（docs/BOSS_PROTOTYPE.md 記錄的第一輪）這個場景
## 刻意只有 Boss，先確認狀態機/前搖/判定形狀本身對不對，現在補上玩家跟對應的 UI
## （FocusHUD／StatusBars，bind(player) 跟 SpellTestRange.gd 同一個既有慣例）。
##
## Floor 重用 scripts/core/TestRangeFloor.gd（跟 SpellTestRange.gd 共用同一份——這是純視覺
## 的同心圓參考線工具，不是法術或 Boss 的專屬行為，符合「穩定的純工具可以共用」的既有原則），
## Boss 擺在跟 Floor 同一個圓心，方便直接拿 100px 一圈的參考線量 SWEEP_RANGE/SLAM_RADIUS
## 畫出來的範圍對不對。玩家出生在 Boss 正南方 300px，進場就在 ENGAGE_RANGE（170px）外，
## 看得到 Boss 從 Observe 開始主動靠近的過程，不是一開場就已經貼臉。

@onready var boss: FurnaceGuardian = $Entities/FurnaceGuardian
@onready var player: CharacterBody2D = $Entities/Player
@onready var focus_hud: FocusHUD = $UI/FocusHUD
@onready var status_bars: StatusBars = $UI/StatusBars
@onready var boss_health_bar: BossHealthBar = $UI/BossHealthBar
@onready var debug_bg: ColorRect = $UI/DebugBg
@onready var debug_label: Label = $UI/DebugLabel

## 預設開著——這個場景本來就是為了盯著狀態機看，不用再按一次 F3 才看得到。
var debug_visible := true
var _f3_was_pressed := false

func _ready() -> void:
	focus_hud.bind(player)
	status_bars.bind(player)
	boss_health_bar.bind(boss)
	debug_bg.visible = debug_visible
	debug_label.visible = debug_visible
	## 2026-10-14 使用者要求：血量歸零在初始位置重生——見 Player.respawn()/
	## FurnaceGuardian.respawn() 宣告處的註解，這是測試場景專屬接線，不寫進角色腳本本體。
	boss.died.connect(boss.respawn)
	player.died.connect(player.respawn)

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
	var lines: Array[String] = ["[F3] 除錯面板 — 熔爐守衛互動測試場", ""]

	lines.append("--- Boss ---")
	lines.append("state: %s" % boss.debug_state_text())
	lines.append("hp: %.0f / %.0f" % [boss.hp, boss.MAX_HP])
	lines.append("facing_dir: (%.2f, %.2f)" % [boss.facing_dir.x, boss.facing_dir.y])
	lines.append("distance_to_player: %.0f" % GroundProjection.projected_distance(boss.global_position, player.global_position))
	lines.append("Engine.time_scale: %.2f" % Engine.time_scale)

	lines.append("")
	lines.append("--- Player（docs/DEMO_PLAN.md Phase 1/2/4）---")
	lines.append("hp: %.0f / %.0f" % [player.hp, player.MAX_HP])
	lines.append("is_focused: %s" % player.is_focused)
	lines.append("current_node_id: %s" % player.current_node_id)
	lines.append("focus_value: %.2f / %.2f" % [player.focus_value, player.FOCUS_MAX])
	lines.append("shield_timer: %.2fs" % player.shield_timer)

	lines.append("")
	lines.append("--- 手動測試（只在 Boss 的 Observe 狀態生效，不走 Input Map，原因見")
	lines.append("    docs/SPELL_SYSTEM.md §8.11 同一類考量）---")
	lines.append("[1] 強制下一招＝橫掃")
	lines.append("[2] 強制下一招＝熔岩重擊")
	lines.append("[3] 強制下一招＝熔爐衝鋒")
	return "\n".join(lines)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_1:
			boss.debug_force_attack("sweep")
		elif event.physical_keycode == KEY_2:
			boss.debug_force_attack("slam")
		elif event.physical_keycode == KEY_3:
			boss.debug_force_attack("charge")
