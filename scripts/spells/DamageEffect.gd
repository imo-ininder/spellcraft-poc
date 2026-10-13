class_name DamageEffect
extends SpellEffect

## 基礎傷害用（例如法術的 base_effects）：每次施放在 [min_amount, max_amount] 間隨機抽一個值，
## 參考 PoE 技能寶石「傷害顯示為區間」的設計，不是寫死單一數字。
@export var min_amount: float = 0.0
@export var max_amount: float = 0.0
## 舊超魔專長系統的百分比加成欄位（已刪除，見 docs/SPELL_SYSTEM.md），新系統目前用不到、留 0.0
## 即可。語意是對「目前已累加的傷害值」疊加百分比，不是對最終值相乘——這個語意是刻意的，
## 之後如果真的要重新接上類似機制，別改成相乘。
@export var damage_mult: float = 0.0

func _init(min_amt: float = 0.0, max_amt: float = 0.0, mult: float = 0.0) -> void:
	min_amount = min_amt
	max_amount = max_amt
	damage_mult = mult

func apply(stats: Dictionary) -> void:
	var rolled := randf_range(min_amount, max_amount)
	stats.damage += rolled + stats.damage * damage_mult

## 「法術強效」用：傷害區間是整數點數，floor（無條件捨去）。damage_mult 不是「效果文數值」
## （那是超魔專長自己疊加的加成，不是法術本身的數值），不縮放。
func scale_potency(mult: float) -> void:
	min_amount = floor(min_amount * mult)
	max_amount = floor(max_amount * mult)

## 「法術極效」用：把 min_amount 設成 max_amount，這樣 apply() 的 randf_range(max,max)
## 必定回傳 max，不用改 apply() 本身的邏輯。
func maximize() -> void:
	min_amount = max_amount

func has_scalable_potency() -> bool:
	return true

func has_scalable_maximize() -> bool:
	return true

func describe_potency() -> String:
	return "傷害 %d~%d" % [int(min_amount), int(max_amount)]
