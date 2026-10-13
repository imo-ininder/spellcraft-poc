class_name SelfBuffDelivery
extends SpellDelivery

## 效果直接套用在施法者自己身上，無命中判定——對應 DEMO_GOALS.md §2.2 的 buff 類法術定義。
## 別跟 SelfDelivery 搞混，見該檔案開頭註解：SelfDelivery 命中的是周圍敵人，這個命中的是施法者自己。
##
## 只處理 DURATION 類效果（呼叫 caster.add_buff()，在施法者身上安裝有倒數時間的 buff）；
## 如果 base_effects 裡混了 INSTANT 類效果，照樣呼叫 apply(stats)，但目前兩把 buff 法術
## （隱形術/速度提升）都只有單一 DURATION 效果，INSTANT 分支純粹是介面完整性，不是已驗證的用例。
## 法術迴響（echo）：等 ECHO_DELAY 秒後再安裝一次同樣的 buff——DURATION 類效果再次命中時
## 是「刷新剩餘時間」不是疊加兩份倒數（見 Player.add_buff()），所以迴響在這裡的實際效果等同
## 延後 ECHO_DELAY 秒把倒數重新刷滿，不是讓 buff 強度變兩倍。
func fire(caster: Node2D, _direction: Vector2, stats: Dictionary, _max_range: float, effects: Array = [], echo: bool = false) -> void:
	_resolve(caster, stats, effects)
	if echo:
		await caster.get_tree().create_timer(ECHO_DELAY).timeout
		_resolve(caster, stats, effects)

func _resolve(caster: Node2D, stats: Dictionary, effects: Array) -> void:
	for effect in effects:
		if effect.apply_mode == SpellEffect.ApplyMode.DURATION:
			caster.add_buff(effect)
		else:
			effect.apply(stats)
