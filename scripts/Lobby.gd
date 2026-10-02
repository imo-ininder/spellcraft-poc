extends Node2D

## 大廳：玩家在固定 GameState.TOTAL_SLOTS 格預算內勾選要帶上戰場的法術（DEMO_GOALS.md §2.5、§7.2）。
## 超過預算時不是「允許但不能出發」，是直接不給勾——按下的瞬間立刻反紅閃一下再彈回未勾選狀態。

@onready var slot_label: Label = $UI/SlotLabel
@onready var spell_list: VBoxContainer = $UI/SpellList
@onready var depart_button: Button = $UI/DepartButton

var selected: Array[Spell] = []
var buttons_by_spell: Dictionary = {}

func _ready() -> void:
	# 重新進大廳時沿用上次配置，而不是每次都清空重選
	selected = GameState.equipped_spells.duplicate()
	for spell in GameState.get_catalog():
		_add_spell_row(spell)
	depart_button.pressed.connect(_on_depart_pressed)
	_update_slot_label()

func _used_slots() -> int:
	var total := 0
	for spell in selected:
		total += spell.slot_cost
	return total

func _add_spell_row(spell: Spell) -> void:
	var button := CheckButton.new()
	button.text = "%s（%d格）" % [spell.display_name, spell.slot_cost]
	button.button_pressed = spell in selected
	button.toggled.connect(_on_spell_toggled.bind(spell, button))
	spell_list.add_child(button)
	buttons_by_spell[spell] = button

func _on_spell_toggled(pressed: bool, spell: Spell, button: CheckButton) -> void:
	if pressed:
		if _used_slots() + spell.slot_cost > GameState.TOTAL_SLOTS:
			# 格數不夠：拒絕這次勾選，反紅閃一下再彈回未勾選
			button.set_pressed_no_signal(false)
			_flash_reject(button)
			return
		selected.append(spell)
	else:
		selected.erase(spell)
	_update_slot_label()

func _flash_reject(button: CheckButton) -> void:
	var base_color := button.modulate
	button.modulate = Color(1.0, 0.35, 0.35)
	var tween := create_tween()
	tween.tween_property(button, "modulate", base_color, 0.35)

func _update_slot_label() -> void:
	var used := _used_slots()
	slot_label.text = "已用 %d / %d 格" % [used, GameState.TOTAL_SLOTS]
	slot_label.modulate = Color(1, 0.4, 0.4) if used > GameState.TOTAL_SLOTS else Color(1, 1, 1)

func _on_depart_pressed() -> void:
	GameState.equipped_spells = selected.duplicate()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
