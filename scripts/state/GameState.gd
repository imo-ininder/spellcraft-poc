extends Node

## 跨場景（大廳／戰鬥）共用的角色裝備狀態。Autoload 單例，見 project.godot [autoload]。

## 角色固定法術格總數（DEMO_GOALS.md §2.5）。Demo 階段固定值，不受裝備/升級影響。
const TOTAL_SLOTS := 6

## 法術總表：目前有哪些法術存在。新增法術時只需要改這裡，大廳/輪盤都會自動反映。
const CATALOG: Array[String] = [
	"res://resources/spells/Fireball.tres",
	"res://resources/spells/ForceWave.tres",
	"res://resources/spells/LightningBolt.tres",
]

## 玩家在大廳選好、要帶上戰場的法術。戰鬥場景（Player.gd）讀這份清單；大廳（Lobby.gd）負責寫入。
## 空陣列代表「還沒經過大廳配置」——Player.gd 會 fallback 成 default_loadout()，
## 讓直接在 editor 開 Main.tscn 測試的工作流程不會因為跳過大廳而壞掉。
var equipped_spells: Array[Spell] = []

func get_catalog() -> Array[Spell]:
	var spells: Array[Spell] = []
	for path in CATALOG:
		spells.append(load(path))
	return spells

## equipped_spells 為空時的 fallback：帶上全部法術（目前 3 把恰好佔滿 6 格）。
func default_loadout() -> Array[Spell]:
	return get_catalog()

func get_equipped_or_default() -> Array[Spell]:
	return equipped_spells if not equipped_spells.is_empty() else default_loadout()
