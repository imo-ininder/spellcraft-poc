class_name ProjectileImpact
extends Resource

## 投射物命中東西、或飛行距離耗盡時呼叫（耗盡時 body 為 null）。
## 回傳 true 代表這次之後投射物應該消失，false 代表可以繼續飛行。
func resolve(_projectile: Node, _body: Node) -> bool:
	push_error("ProjectileImpact.resolve() not implemented on " + get_class())
	return true
