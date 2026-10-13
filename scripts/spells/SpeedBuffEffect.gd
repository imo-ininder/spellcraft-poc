class_name SpeedBuffEffect
extends SpellEffect

## 移動速度提升：寫進 Player.speed_boost_mult——這個欄位跟 Boss 吸引懲罰用的 speed_multiplier
## 是完全不同的欄位，兩者在 _process_movement() 相乘生效，不會互相覆蓋（SPELL_SYSTEM.md §2.2
## 原本點出的風險：同一個減速/加速來源共用一個欄位會互相蓋掉彼此，見 Player.gd 的欄位註解）。
@export var mult: float = 0.1 # +10%

func _init() -> void:
	self.apply_mode = SpellEffect.ApplyMode.DURATION
	self.buff_id = "speed_boost"

func on_start(target: Node) -> void:
	target.speed_boost_mult = mult
	MagicFX.spawn_burst(target.get_tree().current_scene, target.global_position, Color(0.6, 1.0, 0.4), 20, 200.0)

func on_expire(target: Node) -> void:
	target.speed_boost_mult = 0.0

## 「法術強效」用：mult 是像 0.1=10% 這種比例，直接對浮點數 floor 會整個變成0（無條件捨去
## 小於1的數字一律歸零），所以先換算成「整數個百分點」再 floor，不然 10%*1.5=15% 會被捨去
## 成 0%，整個 buff 效果消失——這是 floor 套在小數比例欄位上必須注意的陷阱。參數刻意不叫
## mult，避免跟這個類別自己的 mult 欄位撞名（撞名的話這裡會變成改到參數本身，不是真的欄位）。
func scale_potency(factor: float) -> void:
	mult = floor(mult * 100.0 * factor) / 100.0

func has_scalable_potency() -> bool:
	return true

func describe_potency() -> String:
	return "強度 +%.0f%%" % (mult * 100.0)
