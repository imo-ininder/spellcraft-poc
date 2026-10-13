class_name Spell
extends Resource

@export var id: String
@export var display_name: String
@export var icon: Texture2D
## 手寫說明文字：描述這把法術實際做什麼，包含具體數值（範圍/傷害區間...）——是手寫的
## flavor text，不是從 delivery/effects 自動組出來的，改動 delivery/effect 的數值時記得
## 手動回來同步這段文字，不會自動對上。
@export_multiline var description: String = ""
## 舊系統的固定讀條時長，見 docs/SPELL_SYSTEM.md §2——符文圖譜節點目前不需要填這個欄位。
@export var cast_time: float = 2.0
@export var max_range: float = 650.0
## 舊的大廳6格裝備系統用，已刪除（見 docs/SYSTEMS.md），新的法術圖譜節點不需要填這個欄位。
@export var slot_cost: int = 1
@export var delivery: SpellDelivery
@export var base_effects: Array[SpellEffect] = []
