class_name DamageEffect
extends SpellEffect

## 基礎傷害用（例如法術的 base_effects）：每次施放在 [min_amount, max_amount] 間隨機抽一個值，
## 參考 PoE 技能寶石「傷害顯示為區間」的設計，不是寫死單一數字。
@export var min_amount: float = 0.0
@export var max_amount: float = 0.0
## 符紋百分比加成用：對「目前已累加的傷害值」疊加百分比，不是對最終值相乘
## （見 docs/DESIGN.md 3.6，這個語意是刻意的，別改成相乘）
@export var damage_mult: float = 0.0

func _init(min_amt: float = 0.0, max_amt: float = 0.0, mult: float = 0.0) -> void:
	min_amount = min_amt
	max_amount = max_amt
	damage_mult = mult

func apply(stats: Dictionary) -> void:
	var rolled := randf_range(min_amount, max_amount)
	stats.damage += rolled + stats.damage * damage_mult
