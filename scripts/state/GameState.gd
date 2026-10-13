extends Node

## 跨場景（大廳／戰鬥）共用的角色裝備狀態。Autoload 單例，見 project.godot [autoload]。

## 角色固定法術格總數（DEMO_GOALS.md §2.5）。Demo 階段固定值，不受裝備/升級影響。
const TOTAL_SLOTS := 6

## 法術總表：目前有哪些法術存在。新增法術時只需要改這裡，大廳/輪盤都會自動反映。
const CATALOG: Array[String] = [
	"res://resources/spells/Fireball.tres",
	"res://resources/spells/ForceWave.tres",
	"res://resources/spells/LightningBolt.tres",
	"res://resources/spells/Invisibility.tres",
	"res://resources/spells/SpeedBoost.tres",
	"res://resources/spells/MagicMissile.tres",
]

## 玩家在大廳選好、要帶上戰場的法術。戰鬥場景（Player.gd）讀這份清單；大廳（Lobby.gd）負責寫入。
## 空陣列代表「還沒經過大廳配置」——Player.gd 會 fallback 成 default_loadout()，
## 讓直接在 editor 開 Main.tscn 測試的工作流程不會因為跳過大廳而壞掉。
var equipped_spells: Array[Spell] = []

## 超魔專長組合表：按鍵序列 -> 效果。序列越長/越難打，效果越強。角色天生就會全部，Demo 階段固定不解鎖。
## 放在 GameState 而不是 Player.gd：大廳的超魔專長一覽分頁（唯讀說明）需要讀這份表，但大廳沒有
## Player 實例，不該伸手進另一個場景的腳本內部常數——跟 CATALOG 一樣是跨場景共用資料。
const ARCANE_FEATS := {
	"UU": {"label": "+傷害", "color": Color(1, 0.3, 0.3), "damage_mult": 0.5},
	"UDU": {"label": "+強力傷害", "color": Color(1, 0.1, 0.6), "damage_mult": 1.2},
	"UULR": {"label": "+終極爆發", "color": Color(1, 0.8, 0.1), "damage_mult": 1.8},
	"RR": {"label": "+吟唱速度", "color": Color(0.2, 0.9, 1.0), "cast_speed_bonus": 0.5},
	"LL": {"label": "-吟唱速度", "color": Color(0.5, 0.4, 0.8), "cast_speed_bonus": -0.5},
	## 以下 4 個是數值縮放類超魔專長（2026-10-11 新增）：按鍵序列是佔位用的，使用者明確說這次
	## 先不決定最終按鍵——選不會跟上面既有序列前綴衝突的 D 開頭序列（現有序列沒有任何一個以
	## D 開頭），之後要改最終按鍵只改這裡的 key 字串即可。不給 color，_commit_combo() 有
	## feat.get("color", Color.WHITE) 的 fallback。縮放邏輯見 Player.gd:_apply_scaling_feats()。
	"DD": {"label": "法術強效", "potency_mult": 1.5}, # 效果文數值（傷害區間/buff強度）×1.5後floor
	"DL": {"label": "法術增遠", "range_mult": 1.5}, # max_range ×1.5
	"DR": {"label": "法術擴展", "radius_mult": 1.5}, # 半徑 ×1.5
	"DU": {"label": "法術極效", "maximize": true}, # 隨機區間一律取最大值
	## 2026-10-12 新增：共用上面同一套「原地放大這次施放的法術數值」慣例，按鍵序列一樣是佔位
	## （DD開頭，跟法術強效共用前綴，比照 UU/UULR 既有的前綴共用模式）。
	"DDL": {"label": "法術延時", "duration_mult": 2.0}, # 持續時間（buff類效果的 duration）×2
	"DDR": {"label": "法術迴響", "echo": true}, # 整把法術完整重放一次，見 Player.gd:_fire_spell()
}

func get_catalog() -> Array[Spell]:
	var spells: Array[Spell] = []
	for path in CATALOG:
		spells.append(load(path))
	return spells

## equipped_spells 為空時的 fallback：依 CATALOG 順序貪婪塞滿 6 格，塞不下的法術跳過。
## 原本（只有3把法術、恰好吃滿6格）直接回傳全部，但新增法術後 CATALOG 的 slot_cost 總和
## 會超過 TOTAL_SLOTS——這個 fallback 本來就只是方便「不經大廳直接開 Main.tscn 測試」，
## 不是正式裝備流程（正式流程一律經過 Lobby.gd 的勾選/格數檢查），貪婪塞滿即可，不需要
## 更聰明的選擇策略。
func default_loadout() -> Array[Spell]:
	var loadout: Array[Spell] = []
	var used := 0
	for spell in get_catalog():
		if used + spell.slot_cost > TOTAL_SLOTS:
			continue
		loadout.append(spell)
		used += spell.slot_cost
	return loadout

func get_equipped_or_default() -> Array[Spell]:
	return equipped_spells if not equipped_spells.is_empty() else default_loadout()
