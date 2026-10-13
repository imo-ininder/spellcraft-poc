class_name DeathScreen
extends Control

## 玩家血量歸零時顯示的暗化遮罩＋按鈕。2026-10-13：原本的大廳（scenes/Lobby.tscn）跟著舊
## 戰鬥系統一起刪除了（見 docs/GDD.md），按鈕改成重開目前場景（test arena），不是切去大廳——
## 沒有大廳可以回了，這是過渡期的刻意狀態，之後新系統/場景定案了再決定死亡後該去哪。
##
## 顯示的同時暫停遊戲（get_tree().paused = true），這個節點自己跟按鈕都要
## process_mode = ALWAYS 才能在暫停時仍然接收點擊，見 AoETargetingReticle.gd 同樣理由的註解。

const RESPAWN_SCENE := "res://scenes/SpellTestRange.tscn"

## 節點名稱還叫 LobbyButton（.tscn 沒跟著改名，只是個節點路徑字串，不影響行為）——
## 之後新系統/場景定案了再一起整理，這次只修復「按下去要切去哪」這個會壞掉的部分。
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
	get_tree().change_scene_to_file(RESPAWN_SCENE)
