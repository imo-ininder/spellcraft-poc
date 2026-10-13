class_name SpellGraphNode
extends Resource

## 法術圖譜的一個節點：一把完整可施放的法術，同時可能是其他節點的中繼站
## （docs/DEMO_PLAN.md §4、docs/GDD.md §5.1、docs/FIRE_PROTOTYPE.md §5.2）。
## 節點本身不需要獨立的顯示名稱欄位——UI 要顯示的名字直接讀 spell.display_name，
## 不重複一份容易跟 spell 本身的名字對不上的資料。

@export var id: String
@export var spell: Spell
## 符文（"UU"/"DD"/"LL"/"RR"...）-> 下一個節點的 id。查不到代表這個節點不接受那個
## 符文，不會任意生成新法術（docs/FIRE_PROTOTYPE.md §5.2「不存在有效轉換的輸入，
## 不應任意生成新的法術」）。
@export var transitions: Dictionary[String, String] = {}
