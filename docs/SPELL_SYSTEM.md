# 法術系統架構

> **這份文件描述的技術架構目前仍然有效、持續在用**——`Spell`/`SpellDelivery`/`SpellEffect`/`ProjectileImpact` 的三層分離設計是 `docs/DEMO_PLAN.md` 規劃的火系法術圖譜節點的實作基礎（見該文件 §4）。2026-10-13 跟著舊戰鬥系統一起刪除的只有：「一把法術一份 `.tres`、玩家裝備6把」的資料模型（`GameState.gd`／大廳裝備流程）、超魔專長數值縮放機制（`_apply_scaling_feats()` 那一整套）、§9 的 capability 相容性草案（概念上被新的圖譜 `transitions` 表取代，不會再做）。這份文件已經把那些刪掉的部分移除，只留下還在用、會繼續用的架構說明。

---

## 1. 核心原則：三層關注點分離

| 關注點 | 是什麼 | 存在哪裡 |
|---|---|---|
| **法術定義** | 純資料：數值設定 | `Spell`（Resource，`.tres`） |
| **發射方式** | 怎麼離開施法者、怎麼判定命中 | `SpellDelivery`（Resource，少量可重用策略） |
| **命中效果** | 命中後發生什麼事，可疊加 | `SpellEffect`（Resource，少量可重用策略） |
| **執行時狀態** | CD 倒數、吟唱進度、生效中的 buff | 角色節點本身，絕不放在 Resource 上 |

**`Spell`/`Delivery`/`Effect` 這些 Resource 永遠只放設定值，絕不放會變動的運行時狀態**：Godot 的 Resource 預設是共享引用，不是值型別，兩個角色裝備同一份 `.tres` 時，若運行時狀態（例如倒數計時器）存在 Resource 上，會互相污染。這條規則也記錄在 `CLAUDE.md` 架構規則1。

新增一把「正常」法術（沿用既有 delivery/effect、只是數值不同）：建一個新的 `Spell.tres`，不碰程式碼。新增真正全新的發射機制或效果種類才需要寫新的 `SpellDelivery`/`SpellEffect` 子類別，寫一次之後任何法術都能選用。**子類別只對應「發射機制」或「效果種類」的本質差異，純數值不同不開新子類別。**

---

## 2. `Spell`（`scripts/spells/Spell.gd`）

```gdscript
@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export_multiline var description: String   # 手寫說明文字，不是自動組出來的
@export var cast_time: float = 2.0          # 舊系統的固定讀條時長，新圖譜節點目前用不到這個欄位（不需要填）
@export var max_range: float = 650.0        # 意義由 delivery 決定如何詮釋，見下方各 delivery 說明
@export var slot_cost: int = 1              # 舊的6格裝備系統用，已刪除，新資源不用填
@export var delivery: SpellDelivery
@export var base_effects: Array[SpellEffect] = []
```

`max_range` 是同一個欄位、不同 delivery 各自詮釋：`ProjectileDelivery` 當飛行距離上限，`AoETargetingDelivery` 當選點距離上限。

**自身中心類 delivery（`SelfDelivery`/`SelfBuffDelivery`，施放不需要瞄準/選點，效果永遠發生在施法者自己身上或周圍）的 `max_range` 一律是 `0.0`**——這類法術沒有「打多遠」的概念，只有「影響範圍多大」（`SelfDelivery.radius`）。**新增自身中心類法術時，`.tres` 的 `max_range` 要記得設 `0.0`，不要照抄其他欄位的數值或留著預設值不管**——這條踩過一次坑（舊的 `ForceWave.tres` 一度誤設成跟 `radius` 同值）。

`.tres` 法術資源放在 `resources/spells/`。

---

## 3. `SpellDelivery`（`scripts/spells/SpellDelivery.gd`）

介面：

```gdscript
func fire(caster: Node2D, direction: Vector2, stats: Dictionary, max_range: float, effects: Array = [], echo: bool = false) -> void
```

`stats` 是呼叫端算好的最終數值（目前只有 `damage` 鍵）。`effects` 是 `Spell.base_effects` 的原始陣列（不是攤平後的 `stats`），只有 `SelfBuffDelivery` 會用到。**`echo` 參數目前是功能完整、但呼叫端（`Player.gd`）已經不會傳 `true` 進來的狀態**——舊的「法術迴響」超魔專長會把這個參數設成 `true`，那個專長已經刪除，但每個 delivery 內部處理 echo 的邏輯本身沒有動（§3.3 的 `AoETargetingDelivery` 範例還留著），之後如果新系統需要「重複施放一次」這種節點行為，直接傳 `echo=true` 就能用，不用重寫。

### 3.1 `ProjectileDelivery`
直線投射物，固定方向飛行。`@export var projectile_scene: PackedScene`、`impact: ProjectileImpact`（命中/飛行耗盡後行為，見第5節）、`travel_time: float = 0.1`（法術固定要在這麼多秒內飛完 `max_range`，速度反推出來）、`fixed_speed: float = 0.0`（>0 時優先於 `travel_time`，直接當固定飛行速度，不受 `max_range` 影響——給會反彈、`max_range` 代表總路徑長度而非終點距離的法術用）、`bounces_off_walls: bool = false`（碰到場地邊界是否反彈）、`count: int = 1`／`launch_interval: float = 0.08`（`count > 1` 時朝同一方向依序射出）。

**`bounces_off_walls=true` 的反彈判定（`SpellProjectile._bounce_off_arena_bounds()`）讀的是 `Arena.ARENA_CENTER`/`Arena.PLAYER_ZONE_RADIUS` 這兩個寫死在 `Arena.gd` 腳本類別上的 `const`，用 `get_tree().current_scene.has_node("Arena")` 判斷目前場景有沒有真的放一個 `Arena` 節點**——2026-10-13 更新：`Arena.gd` 掛載的場景（`Main.tscn`）已經刪除，**目前沒有任何場景有 `Arena` 節點，這個 guard 會永遠為 false，牆壁反彈這條路徑目前整個是死路（不會執行到）**，但程式碼跟 `Arena.gd` 本身都還在（`Arena.gd` 現在是孤兒腳本，沒有掛在任何場景上）。之後如果新系統需要場地邊界反彈，要嘛重新設計場地結構、要嘛修改這個判斷式讀新的邊界來源。

### 3.2 `SelfDelivery`
以施法者為中心，對 `radius` 範圍內的 `"enemies"` 群組成員造成 `stats.damage` 並呼叫 `target.apply_knockback(...)`。沒有飛行階段，命中判定跟傷害/擊退在 `fire()` 裡一次做完。`docs/DEMO_PLAN.md` 規劃的「火焰地面」「火雨術」這類以施法者為中心的範圍法術，第一版可以直接沿用這個 delivery。

**不要跟 `SelfBuffDelivery` 搞混**：`SelfDelivery` 命中的是「周圍的敵人」，`SelfBuffDelivery` 命中的是「施法者自己」。

### 3.3 `AoETargetingDelivery`
鎖定選點的範圍法術。`fire()` 是非同步的：暫停遊戲（`get_tree().paused = true`，真正的暫停，不是子彈時間）、顯示跟隨滑鼠的選點介面（`AoETargetingReticle.gd`，`process_mode = PROCESS_MODE_ALWAYS` 才能在暫停時繼續運作）、`await` 等玩家確認/取消、恢復遊戲後對選定點 `radius` 範圍內所有 `"enemies"` 群組成員造成傷害。

**2026-10-13 現況：目前沒有任何法術資源使用這個 delivery**（舊的火球術 `.tres` 已刪除），`AoETargetingReticle.gd`/`AoETargetingTrail.gd`（跟隨滑鼠的選點介面、多點選取、痕跡圈不疊加變亮的 `CanvasGroup` 處理）整套互動邏輯都完整保留在 `scenes/entities/Player.tscn` 底下，處於「功能完整但沒有東西在用」的狀態——`docs/DEMO_PLAN.md` 規劃的 7 個火系節點目前都是直接朝滑鼠方向施放，沒有一個需要暫停點選。如果之後某個節點需要「選一個/多個地面座標」這種互動（例如更進階的範圍控制型法術），這套機制可以直接拿來用，不用重寫。

`@export var count: int = 1`：`count > 1` 時可以依序選多個點（左鍵確認/右鍵撤銷上一步/ESC整個取消的互動邏輯收在 `AoETargetingReticle.gd` 內部）。`@export var radius: float = 90.0`。

### 3.4 `SelfBuffDelivery`
效果直接套用在施法者自己身上，無命中判定：

```gdscript
func fire(caster, _direction, stats, _max_range, effects := [], _echo := false) -> void:
	for effect in effects:
		if effect.apply_mode == SpellEffect.ApplyMode.DURATION:
			caster.add_buff(effect)
		else:
			effect.apply(stats)
```

`docs/FIRE_PROTOTYPE.md` §6.3 的「火焰護盾」（自身防護類 DURATION buff）規劃用這個 delivery，細節見第6節。

### 3.5 `HomingMissileDelivery`
自動鎖定目標的追蹤飛彈，發射機制跟 `ProjectileDelivery` 本質不同（不是加參數能表達的數值差異），獨立成子類別：

- 不吃瞄準方向——`fire()` 忽略傳入的 `direction` 參數，施放當下自動從 `max_range` 範圍內挑**最近**的一個 `"enemies"` 群組成員鎖定；範圍內沒有目標就直接不發射（不會對著空氣射）。
- `missile_count`（預設3）發飛彈**依序**發射（`launch_interval` 間隔，預設0.12秒），不是同時射出。發射方向直接對準目標，不額外加起手偏移角——彎曲不規則的弧線效果全部交給 `HomingMissile.gd` 全程持續的隨機漂移處理。
- `@export var missile_scene: PackedScene`（`HomingMissile.tscn`）、`impact: ProjectileImpact`、`missile_count: int = 3`、`missile_speed: float = 850.0`、`turn_rate: float = 5.0`（徑度/秒）、`launch_interval: float = 0.12`。

**2026-10-13 現況：目前沒有任何法術資源使用這個 delivery**（舊的魔法飛彈 `.tres` 已刪除），`docs/FIRE_PROTOTYPE.md` 的 7 個火系節點目前沒有一個是導引彈，保留這份架構等之後真的需要「自動追蹤」類型的法術時再接上。

**`HomingMissile.gd` 的飛行邏輯（三發飛彈共用同一支腳本，各自獨立運作）**：基準方向 + 隨機漂移兩層疊加（每幀算出「朝向目標」的基準方向，疊加一個連續漂移的隨機角度偏移，兩者相加後用 `rotate_toward()` 轉向）；目標死亡後自動在範圍內找下一個目標；`max_range` 只在「目前沒有目標可追」時才當飛行距離上限，追蹤中的保底安全網是 `HomingMissile.MAX_LIFETIME`（6秒，時間制）。

---

## 4. `SpellEffect`（`scripts/spells/SpellEffect.gd`）

```gdscript
enum ApplyMode { INSTANT, DURATION }

@export var apply_mode: ApplyMode = ApplyMode.INSTANT
@export var duration: float = 0.0   # 只有 apply_mode == DURATION 時才有意義
@export var buff_id: String = ""    # 只有 DURATION 類效果需要，用來判斷「是不是同一種 buff」

func apply(_stats: Dictionary) -> void       # INSTANT 類覆寫：套用一次性數值（例如傷害）
func on_start(_target: Node) -> void          # DURATION 類覆寫：buff 剛安裝時要做的事
func on_expire(_target: Node) -> void         # DURATION 類覆寫：buff 到期要復原的事，必須能完整抵銷 on_start()
```

`Player._base_stats()` 只對 `apply_mode == INSTANT` 的效果呼叫 `apply(stats)`；DURATION 類效果由 `SelfBuffDelivery` 直接拿 `Spell.base_effects` 原始陣列呼叫 `caster.add_buff(effect)`，不經過 `stats`。

### 4.1 `DamageEffect`（INSTANT）
```gdscript
@export var min_amount: float = 0.0
@export var max_amount: float = 0.0   # 基礎傷害區間，每次施放 randf_range() 抽一個值
@export var damage_mult: float = 0.0  # 舊超魔專長的百分比加成欄位，新系統目前用不到，留 0.0 即可
```
`apply(stats)`：`stats.damage += randf_range(min_amount, max_amount) + stats.damage * damage_mult`。

### 4.2 `InvisibilityEffect`（DURATION，`buff_id = "invisibility"`）
`on_start()`：`target.is_invisible = true`。`on_expire()`：`target.is_invisible = false`。**2026-10-13 現況：目前沒有法術資源使用這個效果**（舊的隱形術 `.tres` 已刪除），腳本本身保留（功能類），`Player.gd` 的 `is_invisible` 欄位還在，`_break_invisibility_on_cast()` 中斷邏輯也還在。

### 4.3 `SpeedBuffEffect`（DURATION，`buff_id = "speed_boost"`）
`@export var mult: float = 0.1`（+10%）。`on_start()`：`target.speed_boost_mult = mult`。`on_expire()`：`target.speed_boost_mult = 0.0`。**2026-10-13 現況：目前沒有法術資源使用這個效果**（舊的速度提升 `.tres` 已刪除），腳本本身保留，`Player.gd` 的 `speed_boost_mult` 欄位還在（跟 Boss 吸引懲罰用的 `speed_multiplier` 分開存，兩者在 `_process_movement()` 相乘生效，避免同一欄位被多個來源互相覆蓋——Boss 已刪除，這條設計考量本身的教訓仍然值得記住：同一效果如果以後有多個獨立來源，記得分開存）。

---

## 5. `ProjectileImpact`（`scripts/spells/ProjectileImpact.gd`）

投射物命中東西、或飛行距離耗盡（`body == null`）時呼叫，回傳是否該消失：

```gdscript
func resolve(projectile: Node, body: Node) -> bool
```

- **`SingleHitImpact`**：命中第一個東西就扣血、消失；飛行到頭直接消失不做任何事。
- **`ExplosiveImpact`**：命中東西「或」飛行到頭都會爆炸，對爆炸點 `radius`（預設90）範圍內所有 `"enemies"` 群組成員造成傷害，不穿透。`docs/FIRE_PROTOTYPE.md` 的 Basic 火球術規劃直接用這個（「撞擊敵人或達到最大距離後爆開，造成小型範圍傷害」）。
- **`PiercingImpact`**：全距離無限穿透，命中任何東西都造成傷害但不消失，只有飛行距離耗盡才真正結束。「火焰箭」規劃用這個（「穿透路徑上所有敵人」）。

---

## 6. Buff 系統（`Player.gd`）

```gdscript
var active_buffs: Array = []   # [{effect: SpellEffect, timer: float}]

func add_buff(effect: SpellEffect) -> void   # 同 buff_id 再次命中時刷新 timer，不疊加兩份獨立倒數；否則新增一筆並呼叫 effect.on_start(self)
func has_buff(buff_id: String) -> bool
func _process_buffs(delta: float) -> void    # 每個 _physics_process() 呼叫：倒數各筆 timer，到期呼叫 effect.on_expire(self) 並移除
```

`is_invisible: bool`、`speed_boost_mult: float` 是兩個專用欄位，由對應的 `on_start()`/`on_expire()` 直接讀寫，不是通用化的效果數值介面——目前只有這兩種 buff，沒有做成完全統一的介面。

**隱形中斷**：中斷規則不寫在 `InvisibilityEffect` 身上，而是 `Player._fire_spell()`/`_fire_instant_spell()` 開頭統一呼叫 `_break_invisibility_on_cast()`——中斷的觸發點是「玩家施放了任意法術」這個主動行為，不是效果本身的倒數邏輯。**2026-10-13 現況**：目前沒有敵人會去讀 `is_invisible`（舊的 `_find_player()` 系列 boss 腳本已刪除），這個欄位目前對任何敵人行為都沒有影響，純粹是保留著的狀態容器，等 `docs/DEMO_PLAN.md` Phase 5 的測試敵人做出來、需要「找不到玩家」這個概念時再接上。

---

## 7. GDScript 語言限制

`_init()` 裡直接賦值**繼承自父類別**的 `@export` 欄位會編譯失敗（`Identifier not found`），必須加 `self.` 明確限定：

```gdscript
func _init() -> void:
	self.apply_mode = SpellEffect.ApplyMode.DURATION   # 正確：繼承來的欄位要加 self.
	self.buff_id = "invisibility"
```

欄位若是宣告在子類別自己身上（例如 `DamageEffect` 的 `min_amount`），則不需要 `self.` 也能在 `_init()` 裡直接賦值。只有「`_init()` 賦值繼承來的欄位」這個特定組合會出錯，`_ready()`、一般方法存取繼承欄位不受影響。

GDScript 沒有真正的 interface/abstract class 強制力：`SpellDelivery`/`SpellEffect` 的基底方法只能靠約定，忘記覆寫不會在編輯期被抓到，只會在執行期 `push_error` 或默默無效。

**`await` 協程暫停期間，`Resource` 複製品（`duplicate(true)` 產生的）如果沒有額外的強引用持有者，可能在暫停過程中被垃圾回收，導致協程永遠無法恢復。** 這條是踩過的真實坑（舊的超魔專長數值縮放機制會 `duplicate(true)` 產生縮放後的 `Spell` 複製品，如果只存在區域變數、沒有任何地方長期持有，搭配 `AoETargetingDelivery.fire()` 內部的 `await reticle.finished`，複製品會在等待玩家選點確認的過程中被回收，協程永遠無法恢復，遊戲卡在暫停狀態）。那套縮放機制已經刪除，但**這條 GDScript 行為本身的教訓是通用的**：以後任何「`duplicate(true)` 產生的臨時 Resource」只要會流進 `await`-based 的呼叫鏈（目前只有 `AoETargetingDelivery.fire()`），都要額外存一份強引用保活，不能只放區域變數。
