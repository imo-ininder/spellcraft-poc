extends Node2D

## 大廳：左半邊角色形象＋狀態（文字列出目前裝備的法術），右半邊是分頁清單（DEMO_GOALS.md §7.2）。
## 「法術配置」分頁不是把右側清單整個換掉，而是把全畫面蓋上一層半透明暗層、在上面疊一個浮動面板
## （SpellConfigPanel）——角色/分頁清單在暗層底下依然看得到，只是變暗，不是被取代掉。
##
## 大廳左側（角色形象/「裝備中」文字）只在關閉面板（Esc）時 flush 一次，見 _flush_lobby_display()。
##
## 法術配置開啟後是一個 100% 全螢幕覆蓋層（SpellConfigPanel，透明背景疊在 DimOverlay 上，
## 大廳本身在底下還看得到），裡面是兩個有實體邊框的浮動視窗（Panel，比用看不見的 margin
## 疊 margin 直覺）：左邊 GridWindow 放格數視覺化，刻意不填滿整個視窗，留白給未來要顯示的東西；
## 右邊 SpellWindow 放可捲動的法術清單（ScrollContainer，之後法術變多可以往下捲）。兩個視窗之間
## 本來就是空白（沒有第三個節點去填滿中間），直接透出 DimOverlay 的暗色背景。
## 格子跟清單、綠勾一樣是面板裡的即時回饋，每次勾選/取消都要立刻更新，不是只在關閉時才 flush。
##
## Tab1「超魔專長」分頁是唯讀說明，不是配置——超魔專長角色天生就會全部、不綁定法術（DESIGN.md §4.7），
## 大廳沒有東西可以選。版面沿用 Tab0 的兩視窗結構（FeatInfoPanel 疊在同一個 DimOverlay 上，兩個
## Panel anchor 位置跟 SpellConfigPanel 的 GridWindow/SpellWindow 完全一樣，切分頁時視窗不會跳動），
## 右側是可以用方向鍵上下選取的清單（跟 Tab 清單一樣，focus 內建的上下導覽），左側是單一說明欄位，
## 跟著右側目前選中的那一個即時更新——不是兩邊各列一次全部，是 master-detail 的關係。
##
## Tab0 的 GridWindow 下半部（原本固定顯示 LoadoutWheelPreview 輪盤）現在是兩個互斥顯示的東西：
## 預設顯示 SpellDetailLabel（法術說明，跟右側清單 hover/focus 的那一行連動，跟 Tab1 同一套
## master-detail 寫法），按住 Ctrl 才切換成輪盤（拖曳調整順序，邏輯完全沒變）。放開 Ctrl 時如果
## 剛好拖到一半，直接取消這次拖拽（LoadoutWheelPreview.cancel_drag()），不強制套用，見 _process()。

@onready var equipped_label: Label = $UI/LeftPanel/StatePanel/EquippedLabel
@onready var tab_list: VBoxContainer = $UI/RightPanel/TabMargin/TabList
@onready var depart_button: Button = $UI/RightPanel/DepartButton
@onready var dim_overlay: ColorRect = $UI/DimOverlay
@onready var spell_config_panel: Control = $UI/SpellConfigPanel
@onready var slot_grid: SlotGrid = $UI/SpellConfigPanel/GridWindow/GridMargin/GridArea/SlotGrid
@onready var slot_label: Label = $UI/SpellConfigPanel/GridWindow/GridMargin/GridArea/SlotLabel
@onready var spell_list: VBoxContainer = $UI/SpellConfigPanel/SpellWindow/SpellMargin/SpellArea/SpellScroll/SpellList
@onready var loadout_wheel_preview: LoadoutWheelPreview = $UI/SpellConfigPanel/GridWindow/GridMargin/GridArea/LoadoutWheelPreview
@onready var wheel_hint_label: Label = $UI/SpellConfigPanel/GridWindow/GridMargin/GridArea/WheelHintLabel
@onready var spell_detail_label: Label = $UI/SpellConfigPanel/GridWindow/GridMargin/GridArea/SpellDetailScroll/SpellDetailLabel
@onready var feat_info_panel: Control = $UI/FeatInfoPanel
@onready var feat_detail_label: Label = $UI/FeatInfoPanel/FeatDetailWindow/FeatDetailMargin/FeatDetailArea/FeatDetailScroll/FeatDetailLabel
@onready var feat_list_list: VBoxContainer = $UI/FeatInfoPanel/FeatListWindow/FeatListMargin/FeatListArea/FeatListScroll/FeatListList

## 按鍵字母 -> 中文方向，純顯示用（跟 Player.gd:DIR_KEYS 的 action->字母 方向相反）。
const DIR_LABELS := {"U": "上", "D": "下", "L": "左", "R": "右"}

var selected: Array[Spell] = []
var check_labels_by_spell: Dictionary = {}
var first_feat_button: Button
var first_spell_button: Button

## 滑鼠停在哪一行/鍵盤focus在哪一行（兩者都會觸發），法術說明欄位跟著這個即時更新——
## 跟 Tab1 的 FeatDetailLabel 是同一種 master-detail 關係，見下方 _on_spell_row_hovered()。
var hovered_spell: Spell = null

## 法術格視窗（GridWindow）下半部現在是兩個互斥顯示的東西：預設顯示法術說明
## （SpellDetailLabel，跟右側清單目前 hover/focus 的那一行連動），按住 Ctrl 時換成原本的
## 輪盤排序工具（LoadoutWheelPreview，拖曳調整順序，邏輯完全沒變，只是多了顯示/隱藏開關）。
## 用 _process() 輪詢 Ctrl 狀態而不是事件——跟 Player.gd 的輪盤開關、SPELL_SYSTEM.md §8.11
## 同樣理由：這個鍵只是「按住期間」的狀態查詢，不是一次性觸發，用 is_key_pressed() 符合直覺。
var wheel_shown := false

func _ready() -> void:
	# 重新進大廳時沿用上次配置，而不是每次都清空重選
	selected = GameState.equipped_spells.duplicate()
	for spell in GameState.get_catalog():
		_add_spell_row(spell)
	depart_button.pressed.connect(_on_depart_pressed)
	loadout_wheel_preview.order_changed.connect(_on_wheel_order_changed)

	var spell_config_tab: Button = tab_list.get_child(0)
	spell_config_tab.pressed.connect(_enter_spell_config_tab)
	spell_config_tab.grab_focus()

	var feat_tab: Button = tab_list.get_child(1)
	feat_tab.pressed.connect(_enter_feat_tab)
	for key_string in GameState.ARCANE_FEATS:
		_add_feat_row(key_string, GameState.ARCANE_FEATS[key_string])

	_refresh_panel_display()
	_flush_lobby_display()

func _unhandled_input(event: InputEvent) -> void:
	if (spell_config_panel.visible or feat_info_panel.visible) and event.is_action_pressed("ui_cancel"):
		_return_to_tabs()

## 只在法術配置分頁開啟時輪詢——其他分頁 Ctrl 沒有意義，也不該讓已經藏起來的輪盤或說明欄位
## 繼續被這段邏輯動到。
func _process(_delta: float) -> void:
	if not spell_config_panel.visible:
		return
	var ctrl_held := Input.is_key_pressed(KEY_CTRL)
	if ctrl_held == wheel_shown:
		return
	wheel_shown = ctrl_held
	if not wheel_shown:
		loadout_wheel_preview.cancel_drag()
	loadout_wheel_preview.visible = wheel_shown
	spell_detail_label.get_parent().visible = not wheel_shown
	wheel_hint_label.text = "放開 Ctrl 查看法術說明" if wheel_shown else "按住 Ctrl 拖曳調整輪盤順序"

## 兩個面板互斥：DimOverlay 開著時滑鼠點擊會被它的 mouse_filter=STOP 擋住，正常滑鼠操作碰不到
## 底下被蓋住的分頁按鈕，但鍵盤 Tab 鍵的 focus 循環不受視覺遮擋限制，理論上還是能切到另一個
## 分頁按鈕並觸發 pressed——沒有這個互斥的話兩個面板會同時 visible、疊在畫面上。
func _enter_spell_config_tab() -> void:
	dim_overlay.visible = true
	feat_info_panel.visible = false
	spell_config_panel.visible = true
	if first_spell_button:
		first_spell_button.grab_focus()

func _enter_feat_tab() -> void:
	dim_overlay.visible = true
	spell_config_panel.visible = false
	feat_info_panel.visible = true
	if first_feat_button:
		first_feat_button.grab_focus()

func _return_to_tabs() -> void:
	dim_overlay.visible = false
	spell_config_panel.visible = false
	feat_info_panel.visible = false
	tab_list.get_child(0).grab_focus()
	_flush_lobby_display()

func _used_slots() -> int:
	var total := 0
	for spell in selected:
		total += spell.slot_cost
	return total

## 大廳統一字體大小：標題 22、其他文字 16，跟 .tscn 裡其他 Label/Button 的 theme_override 對齊。
const BODY_FONT_SIZE := 16

## 法術/超魔專長清單的按鈕都裝在 ScrollContainer 裡（SpellScroll/FeatListScroll），引擎預設的
## focus 樣式框線用 expand_margin=2 往控制項外側凸出2px（用 execute_code 直接讀 Tab0 的
## get_theme_stylebox("focus") 實測確認過這個數字，不是用猜的）——按鈕邊緣剛好頂到
## ScrollContainer 的裁切邊界時，凸出去的那2px會被裁掉，裁切邊界在哪一側就決定框線少了哪一側：
## 目前捲動在最上面時，第一列的上緣頂到 ScrollContainer 的上邊界，上緣的2px被裁掉；
## 法術清單每行是 HBoxContainer（按鈕+勾選Label），按鈕右側有勾選Label當緩衝不會頂到容器右界，
## 只有左緣頂到容器左界，所以只有左側被裁；超魔專長清單是光禿禿的按鈕直接佔滿整行寬度，
## 左右兩側都頂到容器邊界，兩側都被裁——兩頁用的是同一套清單寫法，只是法術那邊多一個
## 勾選Label「意外」提供了右側緩衝，看起來才會像是不同的結果。
##
## 修法：把這兩份清單的按鈕 focus 框線改成 expand_margin=0，框線畫在控制項邊界「內側」，
## 永遠不會超出按鈕本身的範圍，自然不可能被外層的裁切邊界切掉——不管捲動位置、是不是第一/
## 最後一項、清單之後真的多到需要捲動，都不會再踩到同一個問題（不是只修「目前看得到」的個案）。
## 直接 duplicate() 引擎預設的 focus 樣式再改 expand_margin，確保除了這個修正之外，外觀（邊框
## 顏色/粗細/圓角）跟其他沒有這個問題的按鈕（Tab0-4、DepartButton）完全一致。
var _row_focus_style: StyleBoxFlat

func _flush_focus_style(button: Button) -> void:
	if _row_focus_style == null:
		var base := button.get_theme_stylebox("focus")
		_row_focus_style = base.duplicate() if base is StyleBoxFlat else StyleBoxFlat.new()
		_row_focus_style.expand_margin_left = 0
		_row_focus_style.expand_margin_top = 0
		_row_focus_style.expand_margin_right = 0
		_row_focus_style.expand_margin_bottom = 0
	button.add_theme_stylebox_override("focus", _row_focus_style)

## 每一行：法術名稱（可點擊切換）＋右側一個綠勾 Label，選中時顯示勾、沒選中時是空字串。
func _add_spell_row(spell: Spell) -> void:
	var row := HBoxContainer.new()
	var name_button := Button.new()
	name_button.flat = true
	name_button.text = spell.display_name
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	name_button.pressed.connect(_on_spell_row_pressed.bind(spell, name_button))
	name_button.mouse_entered.connect(_on_spell_row_hovered.bind(spell))
	name_button.focus_entered.connect(_on_spell_row_hovered.bind(spell))
	_flush_focus_style(name_button)
	if first_spell_button == null:
		first_spell_button = name_button
	var check_label := Label.new()
	check_label.custom_minimum_size = Vector2(28, 0)
	check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check_label.modulate = Color(0.3, 1.0, 0.4)
	check_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	row.add_child(name_button)
	row.add_child(check_label)
	spell_list.add_child(row)
	check_labels_by_spell[spell] = check_label

## 右側清單是可以用方向鍵上下選取的 Button（跟 Tab 清單一樣沿用內建的 focus 上下導覽，不用自己寫），
## 選到哪一個（focus_entered，涵蓋方向鍵移動跟滑鼠點擊兩種情況）就更新左側說明欄位，不上色。
func _add_feat_row(key_string: String, feat: Dictionary) -> void:
	var name_button := Button.new()
	name_button.flat = true
	name_button.text = feat.get("label", "?")
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	name_button.focus_entered.connect(_show_feat_detail.bind(key_string, feat))
	_flush_focus_style(name_button)
	feat_list_list.add_child(name_button)
	if first_feat_button == null:
		first_feat_button = name_button

func _show_feat_detail(key_string: String, feat: Dictionary) -> void:
	# 效果說明之後可能會補充更多細節，先放基本的按鍵序列＋效果數值，格式之後再擴充不影響這個欄位的結構。
	feat_detail_label.text = "按法：%s\n效果：%s（%s）" % [_describe_key_sequence(key_string), feat.get("label", "?"), _describe_feat_effect(feat)]

func _describe_key_sequence(key_string: String) -> String:
	var parts: Array = []
	for letter in key_string:
		parts.append(DIR_LABELS.get(letter, letter))
	return "".join(parts)

func _describe_feat_effect(feat: Dictionary) -> String:
	if feat.has("damage_mult"):
		return "傷害 +%d%%" % int(round(float(feat["damage_mult"]) * 100))
	if feat.has("cast_speed_bonus"):
		var bonus: float = feat["cast_speed_bonus"]
		return "吟唱速度 %s%d%%" % ["+" if bonus >= 0.0 else "", int(round(bonus * 100))]
	return ""

## 滑鼠移過去或鍵盤 focus 移過去（兩種情境共用同一個 callback），不分左側格子視窗目前顯示的是
## 說明還是輪盤——反正看不到的那一面更新了也不會有人注意到，不需要額外判斷。
func _on_spell_row_hovered(spell: Spell) -> void:
	hovered_spell = spell
	_update_spell_detail()

func _update_spell_detail() -> void:
	if hovered_spell == null:
		spell_detail_label.text = ""
		return
	spell_detail_label.text = "%s\n佔用法術格數：%d，施放時間：%.1f 秒\n\n法術效果：\n%s" % [
		hovered_spell.display_name, hovered_spell.slot_cost, hovered_spell.cast_time, hovered_spell.description
	]

func _on_spell_row_pressed(spell: Spell, name_button: Button) -> void:
	if spell in selected:
		selected.erase(spell)
	else:
		if _used_slots() + spell.slot_cost > GameState.TOTAL_SLOTS:
			# 格數不夠：拒絕這次選取，該行名稱反紅閃一下
			_flash_reject(name_button)
			return
		selected.append(spell)
	_refresh_panel_display()

func _flash_reject(control: Control) -> void:
	var base_color := control.modulate
	control.modulate = Color(1.0, 0.35, 0.35)
	var tween := create_tween()
	tween.tween_property(control, "modulate", base_color, 0.35)

## 法術配置面板內部的即時回饋（綠勾、格子、「已用X/6格」數字）——每次勾選/取消都要立刻更新。
func _refresh_panel_display() -> void:
	for spell in check_labels_by_spell:
		check_labels_by_spell[spell].text = "✓" if spell in selected else ""

	var used := _used_slots()
	slot_label.text = "已用 %d / %d 格" % [used, GameState.TOTAL_SLOTS]
	slot_label.modulate = Color(1, 0.4, 0.4) if used > GameState.TOTAL_SLOTS else Color(1, 1, 1)
	slot_grid.update_slots(used, GameState.TOTAL_SLOTS)
	loadout_wheel_preview.update_spells(selected)

## 輪盤預覽拖拽交換完成後回傳的新順序——在這裡才真的寫回 selected（輪盤預覽內部存的是複本，
## 不會反過來自動連動 selected，見 LoadoutWheelPreview.gd 開頭註解／DESIGN.md §4.9）。
func _on_wheel_order_changed(new_order: Array) -> void:
	selected = new_order.duplicate()

## 大廳左側「裝備中」文字只在關閉法術配置面板（Esc）時才更新一次，配置過程中頻繁勾選/取消
## 不需要同步更新大廳畫面——那個位置是「目前帶上戰場的法術」總覽，不是即時編輯回饋。
func _flush_lobby_display() -> void:
	if selected.is_empty():
		equipped_label.text = "尚未裝備法術"
	else:
		var names: Array = []
		for spell in selected:
			names.append(spell.display_name)
		equipped_label.text = "裝備中：\n" + "\n".join(names)

func _on_depart_pressed() -> void:
	GameState.equipped_spells = selected.duplicate()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
