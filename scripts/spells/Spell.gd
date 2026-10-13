class_name Spell
extends Resource

## 2026-10-13 Phase 3 重新設計：法術圖譜的每個節點本來就是寫死、獨一無二的單一招式，不是
## 玩家自由裝備、能被超魔專長動態加效果的可拆換法術——舊系統「Spell 設定值 + SpellDelivery
## 決定怎麼飛 + SpellEffect 陣列決定命中後做什麼」這套通用組合是為了「任何法術都能插任何
## 效果」而設計的，現在這個需求不存在了，硬套只會多一層間接、沒拿到當初這層設計換來的好處
## （使用者提出的質疑，討論記錄見 docs/SPELL_SYSTEM.md）。`SpellDelivery`/`SpellEffect`
## （及其子類別）整組變成孤兒，不被任何新節點引用，但先不刪（CLAUDE.md「功能類的東西可以
## 先留下」的既有慣例），萬一之後真的冒出「好幾個節點要共用同一種通用效果」的情境再撿回來用。
##
## 改成每個節點自己用 cast() 實作自己的效果，而且不只效果本身，連「同類法術共用一個設定值
## 類別」都拆到不能再拆——判斷準則是「不保證每個同類子類別都需要的欄位/邏輯，不要放在共用的
## 中繼層，哪怕名字聽起來像同一種機制」。目前的分層：
## - `ProjectileSpell`（中繼層，只放投射物都通用的 travel_range/speed/size/piercing）
##   → `FireballSpell`/`FireArrowSpell` 各自的 cast()，各自 `.new()` 專屬的投射物節點類別。
## - `ZoneSpell`（中繼層，只放持續範圍都通用的 tick 傷害/間隔/持續時間/半徑/damage_mode）
##   → `FireGroundSpell`/`FireRainSpell` 各自的 cast()。火雨術的掉落物特效是它自己專屬的
##   長相（`FireRainZone extends DamageZone`），沒有被迫塞進火焰地面也會用到的共用
##   `DamageZone` 裡。
## - `FireShieldSpell`/`FireRetreatSpell`/`FireWallSpell` 彼此之間、跟上面兩條分支，完全
##   獨立、互不繼承、互不共用——這三個刻意連「長得像的機制」也不共用（例如火焰撤離的位移
##   不重用既有的擊退/Dash 系統）。
## 完整理由跟每一輪的修正記錄見 docs/SPELL_SYSTEM.md §2。

@export var id: String
@export var display_name: String
@export var icon: Texture2D
## 手寫說明文字：描述這把法術實際做什麼，包含具體數值（範圍/傷害區間...）——是手寫的
## flavor text，不是自動組出來的，改動下面子類別的數值欄位時記得手動回來同步這段文字，
## 不會自動對上。
@export_multiline var description: String = ""

## 2026-10-13：原本這裡有一個共用的 max_range，`ProjectileSpell`（飛行距離）跟 `ZoneSpell`
## （生成位置離施法者多遠）兩種子類別借用同一個欄位名字，但意義完全不同——使用者指出這種
## 「不保證每種法術都需要、名字還一樣」的共用欄位正是該拆開的那種，已經移除。`ProjectileSpell`
## 改用自己的 `travel_range`，`ZoneSpell` 改用自己的 `placement_range`，基底 `Spell` 現在
## 純粹只剩身份/說明文字，不放任何數值類欄位。

## 虛函式：施放這把法術的實際效果。caster 是 Player（也可能是之後的敵人，不限定型別方便
## 重用），aim_dir 是已正規化的瞄準方向（通常是「施法者→滑鼠」，由呼叫端算好傳進來，這裡
## 不重算一次）。基底類別故意不實作——每個子類別自己決定要不要用這個方向、要不要生成東西。
func cast(_caster: Node2D, _aim_dir: Vector2) -> void:
	push_error("Spell.cast() not implemented on " + get_class())
