class_name SpellDelivery
extends Resource

## stats 至少包含 damage（由 Spell.base_effects + 符文效果疊加產生）。
## 右鍵瞬發跳過的是吟唱/符文累積階段（在 Player.gd 處理），不是 delivery 自己的解算流程——
## 需要暫停選點的 delivery（AoETargetingDelivery），瞬發一樣要暫停，不能因為是瞬發就跳過（見 SPELL_SYSTEM.md §8.14）。
## effects：Spell.base_effects 原始陣列（不是攤平後的 stats）——只有 SelfBuffDelivery 這種需要
## 處理 DURATION 類效果（在目標身上安裝 buff，不是疊加進 stats 數值）的 delivery 才需要用到，
## 其餘 delivery 忽略這個參數，照舊只讀 stats 就好。預設空陣列，舊的呼叫端不補這個參數也不會壞。
func fire(_caster: Node2D, _direction: Vector2, _stats: Dictionary, _max_range: float, _effects: Array = []) -> void:
	push_error("SpellDelivery.fire() not implemented on " + get_class())

## 給「吟唱中預覽作用範圍」用（scenes/SpellTestRange.tscn 的 CastPreview.gd，目前整個停用，
## 見該檔案開頭註解）：這把法術的範圍圈大概會畫在哪裡。預設是施法者自己的位置（大多數 delivery
## 都是以施法者為中心命中，例如 SelfDelivery）；AoETargetingDelivery 覆寫成跟著滑鼠走。
func get_preview_center(caster: Node2D, _max_range: float) -> Vector2:
	return caster.global_position
