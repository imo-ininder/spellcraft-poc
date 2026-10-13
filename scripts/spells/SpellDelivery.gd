class_name SpellDelivery
extends Resource

## stats 至少包含 damage（由 Spell.base_effects + 符紋 effects 疊加產生）。
## 右鍵瞬發跳過的是吟唱/符紋累積階段（在 Player.gd 處理），不是 delivery 自己的解算流程——
## 需要暫停選點的 delivery（AoETargetingDelivery），瞬發一樣要暫停，不能因為是瞬發就跳過（見 SPELL_SYSTEM.md §8.14）。
## effects：Spell.base_effects 原始陣列（不是攤平後的 stats）——只有 SelfBuffDelivery 這種需要
## 處理 DURATION 類效果（在目標身上安裝 buff，不是疊加進 stats 數值）的 delivery 才需要用到，
## 其餘 delivery 忽略這個參數，照舊只讀 stats 就好。預設空陣列，舊的呼叫端不補這個參數也不會壞。
## echo：法術迴響超魔專長用（2026-10-12），「這次施放要不要額外重複一次效果」——故意交給每個
## delivery 自己決定「重複」具體指什麼，不是在 Player.gd 集中處理，因為「重複」對不同 delivery
## 意義不一樣：AoETargetingDelivery 選點介面只開一次（使用者明確要求不要選兩次），重複的是
## 「已經選好的每個點再爆炸一次」；ProjectileDelivery/HomingMissileDelivery 沒有選點互動，
## 重複的是「整串發射再射一次」。兩次效果之間固定間隔 ECHO_DELAY 秒。
func fire(_caster: Node2D, _direction: Vector2, _stats: Dictionary, _max_range: float, _effects: Array = [], _echo: bool = false) -> void:
	push_error("SpellDelivery.fire() not implemented on " + get_class())

## 法術迴響兩次效果之間的間隔，所有 delivery 共用同一個數值（繼承自這個基底類別，不用各自
## 宣告一份），2026-10-12 使用者指定。
const ECHO_DELAY := 0.15

## 給「法術擴展」用：半徑可能長在 delivery 自己身上（SelfDelivery/AoETargetingDelivery），
## 也可能要往下委派給 ProjectileDelivery 底下的 impact（見 ProjectileImpact.gd 同名方法）。
## 預設什麼都不做：沒有半徑概念的 delivery（HomingMissileDelivery/SelfBuffDelivery）維持
## 空實作，代表「這個專長對它沒有作用」。
func scale_radius(_mult: float) -> void:
	pass

## 配套查詢用：這個 delivery 的 scale_radius() 實際上會不會做任何事——施法測試場的超魔專長
## 相容性篩選（灰掉用不到的勾選框）要用這個判斷，不用自己重新判斷型別一次。預設 false。
func has_scalable_radius() -> bool:
	return false

## 給除錯顯示用，見 SpellEffect.describe_potency() 同樣的用途。-1.0 代表「沒有半徑可顯示」，
## 用負數而不是 0.0 是因為 0.0 本身可能是一個合法但怪異的半徑值，不該跟「沒有這個概念」混淆。
func get_radius() -> float:
	return -1.0

## 給「法術強效」用：量詞類數值（例如 HomingMissileDelivery.missile_count「這次射出幾發」）
## 跟傷害區間/buff強度同屬於「效果本身的強度」，不是「影響多遠/多大範圍」的 metadata（那是
## 法術增遠/法術擴展的範圍），2026-10-12 確認跟 SpellEffect.scale_potency() 吃同一個倍率，
## 不另外開一個專長。預設什麼都不做：沒有量詞概念的 delivery（ProjectileDelivery/SelfDelivery/
## AoETargetingDelivery/SelfBuffDelivery，目前都是「每次施放固定命中/發射一次」）維持空實作，
## 代表「法術強效對它的數量沒有作用」，只影響它們各自效果的傷害/強度數值。
func scale_count(_mult: float) -> void:
	pass

## 配套查詢用，同 has_scalable_radius() 的用途。預設 false。
func has_scalable_count() -> bool:
	return false

## 給除錯顯示用，同 get_radius() 的用途。-1 代表「沒有量詞概念可顯示」。
func get_count() -> int:
	return -1

## 給「吟唱中預覽作用範圍」用（scenes/SpellTestRange.tscn 的 CastPreview.gd）：這把法術的
## 範圍圈大概會畫在哪裡。預設是施法者自己的位置（大多數 delivery 都是以施法者為中心命中，
## 例如 SelfDelivery）；AoETargetingDelivery 覆寫成跟著滑鼠走（同一套夾限邏輯，跟真正選點
## 階段的 AoETargetingReticle.gd 共用 GroundProjection.clamp_to_radius()，不要各自複製
## 一份，不然吟唱中的預覽跟選點時的實際夾限位置會兜不起來）。
func get_preview_center(caster: Node2D, _max_range: float) -> Vector2:
	return caster.global_position
