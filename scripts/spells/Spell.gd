class_name Spell
extends Resource

@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var cast_time: float = 2.0
@export var max_range: float = 650.0
## 大廳法術格系統用：角色固定 6 格，裝備這把法術要佔用幾格（DEMO_GOALS.md §2.5）
@export var slot_cost: int = 1
@export var delivery: SpellDelivery
@export var base_effects: Array[SpellEffect] = []
