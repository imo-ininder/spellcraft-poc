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
