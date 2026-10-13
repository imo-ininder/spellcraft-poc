class_name SpellEffect
extends Resource

## INSTANT：吟唱結束當下套用一次，走 apply(stats)（例如傷害）。
## DURATION：在目標身上安裝一個有倒數時間的 buff，走 on_start()/on_expire()，不走 apply()——
## 倒數計時狀態存在目標節點身上（Player.active_buffs），不存在這個 Resource 上（CLAUDE.md 架構規則1：
## Resource 是共享引用，裝備同一份 .tres 的多個角色不能共享同一個倒數）。
enum ApplyMode { INSTANT, DURATION }

@export var apply_mode: ApplyMode = ApplyMode.INSTANT
@export var duration: float = 0.0 # 只有 apply_mode == DURATION 時才有意義
## DURATION 類效果用：同類型 buff 再次命中時用這個判斷「是不是同一種」以刷新時間，
## 不是疊加兩份獨立倒數——見 Player.add_buff()。INSTANT 類效果不需要這個欄位。
@export var buff_id: String = ""

func apply(_stats: Dictionary) -> void:
	push_error("SpellEffect.apply() not implemented on " + get_class())

## DURATION 類效果覆寫：buff 剛安裝時要做的事（例如設定 target.is_invisible = true）。
func on_start(_target: Node) -> void:
	pass

## DURATION 類效果覆寫：buff 到期時要復原的事（跟 on_start() 成對，必須能完整抵銷）。
func on_expire(_target: Node) -> void:
	pass

## 給「法術強效」這類超魔專長用：把這個效果的「強度」數值（傷害區間、buff強度百分比）乘上
## mult 倍——不包含 duration/其他 metadata（那些由 Spell.max_range／delivery 的 radius
## 各自處理，不走這個方法，見 docs/SPELL_SYSTEM.md 相關章節）。預設什麼都不做：沒有可縮放
## 強度數值的效果（例如 InvisibilityEffect，只有 duration）不用覆寫，維持空實作就代表
## 「這個專長對它沒有作用」。呼叫端（Player.gd）只負責觸發，不需要知道底下有哪些子類型——
## 新增效果類型時要不要支援縮放，在該類別自己的檔案裡決定，不要在呼叫端集中判斷型別。
func scale_potency(_mult: float) -> void:
	pass

## 給「法術極效」用：讓這個效果的隨機區間一律取最大值。預設什麼都不做。
func maximize() -> void:
	pass

## 給「法術延時」用：持續時間（DURATION 類效果才有意義）乘上 mult 倍。跟 scale_potency()/
## maximize() 不同，這裡不用讓每個子類別各自覆寫——duration 本來就宣告在這個基底類別身上
## （不是子類別各自擁有的欄位），直接在這裡處理就對所有子類別都生效。INSTANT 類效果雖然也會
## 繼承到這個方法，但它們的 duration 欄位本來就沒被讀取，縮放了也不會有任何觀察得到的效果，
## 不需要特別關閉。
func scale_duration(mult: float) -> void:
	duration *= mult

## 配套查詢用：scale_potency()/maximize()/scale_duration() 實際上會不會做任何事——施法測試場
## 的超魔專長相容性篩選（灰掉用不到的勾選框）要用這幾個判斷，不用自己重新判斷型別一次。
## has_scalable_duration() 跟前兩個不一樣，不是看子類別有沒有覆寫，而是直接問 apply_mode——
## 只有 DURATION 類效果的 duration 才有意義，邏輯本來就跟型別無關，所以基底類別自己就能
## 回答，不用交給子類別各自判斷。
func has_scalable_potency() -> bool:
	return false

func has_scalable_maximize() -> bool:
	return false

func has_scalable_duration() -> bool:
	return apply_mode == ApplyMode.DURATION

## 給除錯顯示用（scenes/SpellTestRange.tscn 的數值 before/after 視窗）：把這個效果的強度
## 數值轉成一行好讀的字串，空字串代表「沒有強度數值可顯示」。預設空字串——不覆寫就代表
## has_scalable_potency() 也是 false 的那些效果，沒有東西好秀。
func describe_potency() -> String:
	return ""
