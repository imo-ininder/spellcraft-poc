class_name Spell
extends Resource

@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var cast_time: float = 2.0
@export var max_range: float = 650.0
@export var delivery: SpellDelivery
@export var base_effects: Array[SpellEffect] = []
