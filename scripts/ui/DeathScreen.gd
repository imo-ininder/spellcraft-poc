class_name DeathScreen
extends Control

## 玩家血量歸零時顯示的暗化遮罩＋按鈕（2026-10-12 使用者要求拿掉「你死了」文字，按鈕改成
## 回大廳，不是重試）。回大廳＝切回 scenes/Lobby.tscn，不是重新載入 Main.tscn——玩家死亡後
## 應該回到裝備配置畫面重新出發，不是原地重來一場一模一樣的戰鬥。
##
## 顯示的同時暫停遊戲（get_tree().paused = true）——玩家已經死了，背景不應該讓 Boss 繼續巡邏/
## 出招，這個節點自己跟按鈕都要 process_mode = ALWAYS 才能在暫停時仍然接收點擊，見
## AoETargetingReticle.gd 同樣理由的註解。

const LOBBY_SCENE := "res://scenes/Lobby.tscn"

@onready var lobby_button: Button = $CenterContainer/VBoxContainer/LobbyButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	lobby_button.pressed.connect(_on_lobby_pressed)

func bind(player: CharacterBody2D) -> void:
	player.died.connect(_on_player_died)

func _on_player_died() -> void:
	visible = true
	get_tree().paused = true

func _on_lobby_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(LOBBY_SCENE)
