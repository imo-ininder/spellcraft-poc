extends Node2D

## 法術/超魔專長測試場：左側兩個折疊清單（法術單選、超魔專長多選），打勾後按正常的施放鍵
## （cast_spell，左鍵）觸發，吟唱一開始就把勾選的超魔專長直接視同已觸發（Player.debug_force_feat()，
## 見該函式註解），不需要在吟唱過程中真的手動打方向鍵組合——這是開發用的捷徑，跳過的只是
## 「輸入方式」，吟唱時長／cast_speed_bonus／傷害倍率全部還是走正式邏輯，不是另外模擬一套。
##
## 超魔專長清單會依目前選到的法術做相容性篩選：傷害類超魔專長（UU/UDU/UULR，影響 damage_mult）
## 套在沒有基礎傷害的法術上（例如隱形術、速度提升這類 buff 法術）數值算出來就是乘以0，灰掉不能
## 勾比讓使用者自己發現「勾了沒反應」更清楚——判斷依據是 base_effects 裡有沒有 DamageEffect
## 且 max_amount > 0，不是看 delivery 類型（技術上更準確，不會漏判未來新增的法術類型）。
## 吟唱速度類超魔專長（RR/LL）不受此限制，任何法術都能套用。

@onready var player: CharacterBody2D = $Player
@onready var test_dummy: StaticBody2D = $TestDummy
@onready var spell_list: VBoxContainer = $UI/LeftPanel/VBox/SpellList
@onready var feat_list: VBoxContainer = $UI/LeftPanel/VBox/FeatList
@onready var spell_fold_header: Button = $UI/LeftPanel/VBox/SpellFoldHeader
@onready var feat_fold_header: Button = $UI/LeftPanel/VBox/FeatFoldHeader
@onready var cast_bar: CastBar = $UI/CastBar
@onready var triggered_label: Label = $UI/LeftPanel/VBox/TriggeredLabel
@onready var debug_bg: ColorRect = $UI/DebugBg
@onready var debug_label: Label = $UI/DebugLabel
@onready var spell_state_bg: ColorRect = $UI/SpellStateBg
@onready var spell_state_label: Label = $UI/SpellStateLabel

var spells: Array[Spell] = []
var feat_keys: Array[String] = []
var selected_spell_index := 0
var checked_feat_keys: Array[String] = []
var spell_checkboxes: Array[CheckBox] = []
var feat_checkboxes: Dictionary = {} # key_string -> CheckBox

## 跟 Main.gd 同一套 F3 除錯面板（獨立複製一份，不是共用——這份只跟這個測試場的狀態有關，
## 沒有 boss，顯示內容本來就不一樣）。一樣故意不走 Input Map，直接用 is_physical_key_pressed()，
## 原因見 SPELL_SYSTEM.md §8.11／Main.gd 同一行註解。
var debug_visible := false
var _f3_was_pressed := false

## 另一個獨立的除錯視窗（F4），跟 F3 那個分開——顯示「目前選的法術，原始數值 vs. 套用勾選中
## 超魔專長後的數值」，即時更新（不需要真的施放一次才看得到，勾選框一變就重算）。
var spell_state_visible := false
var _f4_was_pressed := false

func _ready() -> void:
	spells = GameState.get_catalog()
	feat_keys.assign(GameState.ARCANE_FEATS.keys())
	_build_spell_list()
	_build_feat_list()
	_select_spell(0)

	spell_fold_header.pressed.connect(func(): spell_list.visible = not spell_list.visible)
	feat_fold_header.pressed.connect(func(): feat_list.visible = not feat_list.visible)

	cast_bar.bind(player)
	player.cast_started.connect(_on_cast_started)
	player.feat_added.connect(_on_feat_added)
	triggered_label.text = ""
	debug_bg.visible = false
	debug_label.visible = false
	spell_state_bg.visible = false
	spell_state_label.visible = false

func _build_spell_list() -> void:
	for i in range(spells.size()):
		var spell := spells[i]
		var cb := CheckBox.new()
		cb.text = spell.display_name
		cb.toggled.connect(_on_spell_toggled.bind(i))
		spell_list.add_child(cb)
		spell_checkboxes.append(cb)

## 法術清單是單選（一次只能測一把），用 CheckBox 模擬單選行為：勾新的就把其他取消，
## 想取消目前勾選的那個會被擋下來（永遠保持剛好一個被選中，不然 player.equipped_spell 會是空的）。
func _on_spell_toggled(pressed: bool, index: int) -> void:
	if not pressed:
		spell_checkboxes[index].set_pressed_no_signal(true)
		return
	_select_spell(index)

func _select_spell(index: int) -> void:
	selected_spell_index = index
	player.equipped_spell = spells[index]
	for i in range(spell_checkboxes.size()):
		spell_checkboxes[i].set_pressed_no_signal(i == index)
	_refresh_feat_compatibility()

func _build_feat_list() -> void:
	for key in feat_keys:
		var feat: Dictionary = GameState.ARCANE_FEATS[key]
		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [feat.get("label", "?"), key]
		cb.toggled.connect(_on_feat_toggled.bind(key))
		feat_list.add_child(cb)
		feat_checkboxes[key] = cb

func _on_feat_toggled(pressed: bool, key: String) -> void:
	if pressed:
		if not checked_feat_keys.has(key):
			checked_feat_keys.append(key)
	else:
		checked_feat_keys.erase(key)

func _spell_has_damage(spell: Spell) -> bool:
	for effect in spell.base_effects:
		if effect is DamageEffect and effect.max_amount > 0.0:
			return true
	return false

## 每個 effect/delivery/impact 自己知道「縮放牠會不會有效果」（has_scalable_potency()/
## has_scalable_maximize()/has_scalable_radius()/has_scalable_count()，見 SpellEffect.gd/
## SpellDelivery.gd/ProjectileImpact.gd），這裡只負責問、不重新判斷型別——新增法術效果類型時，
## 該類別自己決定要不要支援這幾個新專長，這裡不用跟著改。
##
## 法術強效除了縮放效果的傷害/buff強度，2026-10-12 起也縮放 delivery 的量詞（例如
## HomingMissileDelivery.missile_count「這次射出幾發」）——所以這裡除了看 effects，也要看
## delivery.has_scalable_count()，兩者有一個成立就不該灰掉（只有量詞沒有傷害強度的 delivery
## 目前還不存在，但邏輯上不該漏判）。
func _spell_has_scalable_potency(spell: Spell) -> bool:
	for effect in spell.base_effects:
		if effect.has_scalable_potency():
			return true
	return spell.delivery.has_scalable_count()

func _spell_has_scalable_maximize(spell: Spell) -> bool:
	for effect in spell.base_effects:
		if effect.has_scalable_maximize():
			return true
	return false

## 法術延時用：只有 DURATION 類效果（buff類法術，目前是隱形術/速度提升）的 duration 才有意義，
## 跟 has_scalable_potency()/has_scalable_maximize() 同一個問法——問效果自己，不在這裡判斷型別。
func _spell_has_scalable_duration(spell: Spell) -> bool:
	for effect in spell.base_effects:
		if effect.has_scalable_duration():
			return true
	return false

func _feat_applies_to(feat: Dictionary, spell: Spell) -> bool:
	if feat.has("damage_mult"):
		return _spell_has_damage(spell)
	if feat.has("potency_mult"):
		return _spell_has_scalable_potency(spell)
	if feat.has("range_mult"):
		return spell.max_range > 0.0
	if feat.has("radius_mult"):
		return spell.delivery.has_scalable_radius()
	if feat.has("duration_mult"):
		return _spell_has_scalable_duration(spell)
	if feat.get("maximize", false):
		return _spell_has_scalable_maximize(spell)
	## echo（法術迴響）沒有不相容的法術——任何法術重放一次都有意義（多一次傷害/多一次範圍/
	## 多裝一次buff），落到這裡的預設 return true，不需要額外判斷式。
	return true

## 切換法術時重新檢查每個超魔專長的相容性——原本勾選、但換法術後變不相容的要自動取消勾選，
## 不留著一個「勾了但灰掉、數值其實沒套用」的曖昧狀態。
func _refresh_feat_compatibility() -> void:
	var spell := spells[selected_spell_index]
	for key in feat_keys:
		var feat: Dictionary = GameState.ARCANE_FEATS[key]
		var cb: CheckBox = feat_checkboxes[key]
		var applies := _feat_applies_to(feat, spell)
		cb.disabled = not applies
		if not applies and cb.button_pressed:
			cb.set_pressed_no_signal(false)
			checked_feat_keys.erase(key)

## 讀條本身（進度/倒數秒數）由 cast_bar.bind(player) 自己處理，見 scripts/ui/CastBar.gd——
## 這裡只負責跟讀條無關的部分：清掉上一次顯示的觸發紀錄、把勾選的超魔專長視同已觸發。
func _on_cast_started() -> void:
	triggered_label.text = ""
	for key in checked_feat_keys:
		player.debug_force_feat(key)

func _on_feat_added(feat_data) -> void:
	var label: String = feat_data.get("label", "?")
	triggered_label.text += ("" if triggered_label.text == "" else " / ") + label

func _process(_delta: float) -> void:
	var f3_pressed := Input.is_physical_key_pressed(KEY_F3)
	if f3_pressed and not _f3_was_pressed:
		debug_visible = not debug_visible
		debug_bg.visible = debug_visible
		debug_label.visible = debug_visible
	_f3_was_pressed = f3_pressed
	if debug_visible:
		debug_label.text = _build_debug_text()

	var f4_pressed := Input.is_physical_key_pressed(KEY_F4)
	if f4_pressed and not _f4_was_pressed:
		spell_state_visible = not spell_state_visible
		spell_state_bg.visible = spell_state_visible
		spell_state_label.visible = spell_state_visible
	_f4_was_pressed = f4_pressed
	if spell_state_visible:
		spell_state_label.text = _build_spell_state_text()

## 不是等真的施放一次才看得到結果——直接呼叫 Player.debug_preview_scaled_spell()（純函式，
## 內部跟正式施放流程共用同一個 _apply_scaling_feats()，不是另外算一套），拿目前勾選中的
## 超魔專長去跑一次縮放，比對原始法術跟縮放後複製品的每個數值。只列出「有東西可以顯示」的
## 欄位（傷害/buff強度用 describe_potency()，半徑用 get_radius()，兩者都是 -1.0/空字串
## 代表「這個法術沒有這個概念」，不是集中判斷型別，而是問法術自己），沒有勾任何相關專長時
## 原始值跟縮放後值自然會一樣，直接看得出「這個法術現在沒被任何東西動到」。
func _build_spell_state_text() -> String:
	var lines: Array[String] = ["[F4] 法術數值：原始 → 套用勾選中的超魔專長後", ""]

	var original: Spell = spells[selected_spell_index]
	var feats: Array = []
	for key in checked_feat_keys:
		feats.append(GameState.ARCANE_FEATS[key])
	var scaled: Spell = player.debug_preview_scaled_spell(feats)

	lines.append(original.display_name)
	lines.append("")
	lines.append("max_range: %.0f → %.0f" % [original.max_range, scaled.max_range])

	var orig_radius := original.delivery.get_radius()
	if orig_radius >= 0.0:
		lines.append("radius: %.0f → %.0f" % [orig_radius, scaled.delivery.get_radius()])

	var orig_count := original.delivery.get_count()
	if orig_count >= 0:
		lines.append("count: %d → %d" % [orig_count, scaled.delivery.get_count()])

	for i in range(original.base_effects.size()):
		var orig_desc: String = original.base_effects[i].describe_potency()
		if orig_desc == "":
			continue
		var scaled_desc: String = scaled.base_effects[i].describe_potency()
		lines.append("%s → %s" % [orig_desc, scaled_desc])

	for i in range(original.base_effects.size()):
		if not original.base_effects[i].has_scalable_duration():
			continue
		lines.append("duration: %.1fs → %.1fs" % [original.base_effects[i].duration, scaled.base_effects[i].duration])

	for f in feats:
		if f.get("echo", false):
			lines.append("")
			lines.append("（法術迴響生效中：會完整重放一次，F4 這裡顯示的數值兩次施放相同）")

	return "\n".join(lines)

func _build_debug_text() -> String:
	var lines: Array[String] = ["[F3] 除錯面板", ""]

	lines.append("--- 測試狀態 ---")
	lines.append("equipped_spell: %s" % equipped_spell_label())
	lines.append("checked_feats: %s" % (", ".join(checked_feat_keys) if not checked_feat_keys.is_empty() else "(無)"))
	lines.append("is_casting: %s" % player.is_casting)
	if player.is_casting:
		lines.append("cast_timer: %.2fs" % player.cast_timer)
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

func equipped_spell_label() -> String:
	return player.equipped_spell.display_name if player.equipped_spell else "(無)"
