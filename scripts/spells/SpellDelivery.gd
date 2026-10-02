class_name SpellDelivery
extends Resource

## stats 至少包含 damage（由 Spell.base_effects + 符紋 effects 疊加產生）。
## 右鍵瞬發跳過的是吟唱/符紋累積階段（在 Player.gd 處理），不是 delivery 自己的解算流程——
## 需要暫停選點的 delivery（AoETargetingDelivery），瞬發一樣要暫停，不能因為是瞬發就跳過（見 SPELL_SYSTEM.md §8.14）。
func fire(_caster: Node2D, _direction: Vector2, _stats: Dictionary, _max_range: float) -> void:
	push_error("SpellDelivery.fire() not implemented on " + get_class())
