class_name StatusBars
extends Control

## 血量＋專注值狀態列：畫面左上角，永遠顯示——跟 FocusHUD（只在專注狀態才出現，顯示的是
## 「正在做什麼」）不一樣，這兩個是隨時都該看得到的資源存量，使用者 2026-10-13 明確要求
## 放在一起、用簡單的條（不是 HealthOrb.gd 那套材質裁切液體效果），HP 紅色、專注值紫色。
## 2026-10-13 現況：`HealthOrb.gd`/`HealthOrb.tscn` 本來就沒有掛在任何場景裡（孤兒狀態，
## 血量目前完全沒有畫面顯示），這支檔案是第一個真的把 hp_changed 接到畫面上的 UI，不是在
## 取代一個原本有在用的東西。

@onready var hp_bar: ProgressBar = $HPBar
@onready var focus_bar: ProgressBar = $FocusBar

var player: CharacterBody2D

func bind(target_player: CharacterBody2D) -> void:
	player = target_player
	player.hp_changed.connect(_on_hp_changed)
	_on_hp_changed(player.hp / player.MAX_HP)

func _on_hp_changed(ratio: float) -> void:
	hp_bar.value = clamp(ratio, 0.0, 1.0) * 100.0

## focus_value 沒有對應的「數值變了」訊號可以掛——跟 FocusHUD.gd 的專注值條同一個理由，
## 消耗/回復是逐幀連續變動的，沒必要為此新增訊號，每幀直接讀。
func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	focus_bar.value = (player.focus_value / player.FOCUS_MAX) * 100.0
