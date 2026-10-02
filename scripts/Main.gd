extends Node2D

@onready var player := $Player
@onready var cast_bar: ProgressBar = $UI/CastBar
@onready var feat_container: HBoxContainer = $UI/FeatContainer
@onready var combo_label: Label = $UI/ComboLabel
@onready var cd_bar: ProgressBar = $UI/CDBar
@onready var cd_label: Label = $UI/CDLabel
@onready var spell_wheel: SpellWheel = $UI/SpellWheel

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
