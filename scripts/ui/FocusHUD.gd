class_name FocusHUD
extends Control

## 專注狀態 HUD：顯示目前法術圖譜節點名稱＋符文輸入成功/失敗的短暫回饋（docs/DEMO_PLAN.md
## §6）。跟 CastBar.gd／StatusBars.gd 同一個 bind(player) 慣例。
##
## 只在專注狀態下顯示，用 _process() 輪詢 player.is_focused 做可見度切換——這是單純的
## 布林開關，不像 CastBar 需要逐幀同步一個連續進度值，不需要為此新增訊號。
## 節點名稱／成功/失敗閃色用訊號驅動（node_changed／combo_failed），不是每幀重新查一次
## 目前節點（圖譜查詢沒有快取，見 SpellGraph.get_node_by_id()，沒必要每幀白跑一次）。
##
## 2026-10-13：專注值條原本掛在這裡，後來搬到 StatusBars.gd（畫面左上角，跟血量放一起，
## 永遠顯示）——專注值是「資源存量」，不是「專注狀態才需要知道」的資訊，使用者明確要求比照
## 血量處理，跟 FocusHUD 這種「只在專注中才有意義」的情境資訊（目前在哪個符文節點）分開。

@onready var node_label: Label = $NodeLabel

var player: CharacterBody2D
var flash_timer := 0.0
var flash_color := Color.WHITE

func _ready() -> void:
	visible = false

func bind(target_player: CharacterBody2D) -> void:
	player = target_player
	player.node_changed.connect(_on_node_changed)
	player.combo_failed.connect(_on_combo_failed)
	_refresh_label()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	visible = player.is_focused
	if flash_timer > 0.0:
		flash_timer -= delta
	node_label.modulate = flash_color if flash_timer > 0.0 else Color.WHITE

func _refresh_label() -> void:
	var node: SpellGraphNode = player.current_graph.get_node_by_id(player.current_node_id)
	node_label.text = node.spell.display_name if node != null else "?"

func _on_node_changed(_node_id: String) -> void:
	flash_timer = 0.2
	flash_color = Color(0.4, 1.0, 0.55)
	_refresh_label()

func _on_combo_failed() -> void:
	flash_timer = 0.3
	flash_color = Color(1.0, 0.35, 0.35)
