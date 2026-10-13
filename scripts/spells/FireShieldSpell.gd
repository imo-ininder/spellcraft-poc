class_name FireShieldSpell
extends Spell

## 火焰護盾（docs/FIRE_PROTOTYPE.md §6.3）：施放後一段時間內受到的傷害打折。狀態存在
## Player.gd 自己的 shield_timer/shield_damage_mult 兩個欄位上（CLAUDE.md 架構規則1——
## 運行時狀態不放在 Resource 上），不透過 active_buffs/SpellEffect 那套（那是給「同一時間
## 可能疊加多種不同 buff」設計的通用機制，火焰護盾目前是唯一一個自身防護類法術，不需要那層
## 通用性，直接寫兩個專屬欄位更直接）。
##
## 2026-10-13：類別名稱從 ShieldSpell 改成 FireShieldSpell——使用者指出「Shield」這種按
## 「效果類型」取的名字，會暗示「所有護盾類法術都共用這套邏輯」，但實際上這支檔案裡的每一行
## 都只跟火焰護盾這把法術有關，之後如果有別的元素也有護盾類法術，不保證邏輯會一樣，不該被
## 這個名字綁住預期。跟 FireballSpell/FireArrowSpell 同一個命名慣例：類別名稱綁定「這把
## 法術」，不是「這種機制」。
##
## 「對攻擊自己的敵人造成火焰傷害」（原文提到的反傷效果）這次沒做：take_damage() 目前不知道
## 攻擊者是誰，要做反傷得幫近戰/投射物/範圍法術全部的傷害呼叫點加上攻擊者參數，範圍超出這次，
## 使用者 review 規劃時同意先跳過，只做減傷，見 Player.gd 的 shield_timer 欄位宣告處註解。

@export var duration: float = 3.0
@export var damage_mult: float = 0.4 ## 受到傷害只剩 40%（佔位值）

func cast(caster: Node2D, _aim_dir: Vector2) -> void:
	caster.start_shield(duration, damage_mult)
