class_name ProjectileImpact
extends Resource

## 投射物命中東西、或飛行距離耗盡時呼叫（耗盡時 body 為 null）。
## 回傳 true 代表這次之後投射物應該消失，false 代表可以繼續飛行。
func resolve(_projectile: Node, _body: Node) -> bool:
	push_error("ProjectileImpact.resolve() not implemented on " + get_class())
	return true

## 給「法術擴展」用，見 SpellDelivery.scale_radius() 同名方法的註解——這是另一個可能長
## 半徑欄位的地方（ExplosiveImpact）。預設什麼都不做。
func scale_radius(_mult: float) -> void:
	pass

## 配套查詢用，見 SpellDelivery.has_scalable_radius() 同名方法的註解。預設 false。
func has_scalable_radius() -> bool:
	return false

## 給除錯顯示用，見 SpellDelivery.get_radius() 同名方法的註解。
func get_radius() -> float:
	return -1.0
