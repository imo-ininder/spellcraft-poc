class_name Spell
extends Resource

@export var id: String
@export var display_name: String
@export var icon: Texture2D
## 大廳法術配置頁用的手寫說明文字（DESIGN.md §4.x／SPELL_SYSTEM.md §8.16）：描述這把法術實際
## 做什麼，包含具體數值（範圍/傷害區間...）——是手寫的 flavor text，不是從 delivery/effects
## 自動組出來的，改動 delivery/effect 的數值時記得手動回來同步這段文字，不會自動對上。
@export_multiline var description: String = ""
@export var cast_time: float = 2.0
@export var max_range: float = 650.0
## 大廳法術格系統用：角色固定 6 格，裝備這把法術要佔用幾格（DEMO_GOALS.md §2.5）
@export var slot_cost: int = 1
@export var delivery: SpellDelivery
@export var base_effects: Array[SpellEffect] = []
