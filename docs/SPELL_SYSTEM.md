# 法術系統架構

> 法術系統的技術規格：`Spell`/`SpellDelivery`/`SpellEffect`/`ProjectileImpact` 的資料結構與現存子類別。核心吟唱機制（超魔專長序列輸入）見 `DESIGN.md`，Demo 範圍/驗收標準見 `DEMO_GOALS.md`，Boss 招式（不走這套架構）見 `BOSS_DESIGN.md`。

---

## 1. 核心原則：三層關注點分離

| 關注點 | 是什麼 | 存在哪裡 |
|---|---|---|
| **法術定義** | 純資料：數值設定 | `Spell`（Resource，`.tres`） |
| **發射方式** | 怎麼離開施法者、怎麼判定命中 | `SpellDelivery`（Resource，少量可重用策略） |
| **命中效果** | 命中後發生什麼事，可疊加 | `SpellEffect`（Resource，少量可重用策略） |
| **執行時狀態** | CD 倒數、吟唱進度、生效中的 buff | 角色節點本身，絕不放在 Resource 上 |

**`Spell`/`Delivery`/`Effect` 這些 Resource 永遠只放設定值，絕不放會變動的運行時狀態**：Godot 的 Resource 預設是共享引用，不是值型別，兩個角色裝備同一份 `.tres` 時，若運行時狀態（例如倒數計時器）存在 Resource 上，會互相污染。

新增一把「正常」法術（沿用既有 delivery/effect、只是數值不同）：建一個新的 `Spell.tres`，不碰程式碼。新增真正全新的發射機制或效果種類才需要寫新的 `SpellDelivery`/`SpellEffect` 子類別，寫一次之後任何法術都能選用。**子類別只對應「發射機制」或「效果種類」的本質差異，純數值不同不開新子類別。**

---

## 2. `Spell`（`scripts/spells/Spell.gd`）

```gdscript
@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export_multiline var description: String   # 大廳法術配置頁顯示的手寫說明文字，不是自動組出來的
@export var cast_time: float = 2.0
@export var max_range: float = 650.0        # 意義由 delivery 決定如何詮釋，見下方各 delivery 說明
@export var slot_cost: int = 1              # 大廳法術格系統用，角色固定 6 格
@export var delivery: SpellDelivery
@export var base_effects: Array[SpellEffect] = []
```

`max_range` 是同一個欄位、不同 delivery 各自詮釋：`ProjectileDelivery` 當飛行距離上限，`AoETargetingDelivery` 當選點距離上限。這樣被動效果（例如「+施放距離」裝備）之後只需要調整 `max_range`，不需要知道底下是哪種 delivery。

`.tres` 法術資源放在 `resources/spells/`。

---

## 3. `SpellDelivery`（`scripts/spells/SpellDelivery.gd`）

介面：

```gdscript
func fire(caster: Node2D, direction: Vector2, stats: Dictionary, max_range: float, effects: Array = []) -> void
```

`stats` 是呼叫端（`Player.gd`）先套用完 `base_effects` 跟超魔專長效果算好的最終數值（目前只有 `damage` 鍵）。`effects` 是 `Spell.base_effects` 的原始陣列（不是攤平後的 `stats`），只有 `SelfBuffDelivery` 會用到，其餘 delivery 忽略這個參數。

### 3.1 `ProjectileDelivery`
直線投射物。`@export var projectile_scene: PackedScene`、`impact: ProjectileImpact`（命中/飛行耗盡後行為，見第5節）、`travel_time: float = 0.1`（法術固定要在這麼多秒內飛完 `max_range`，速度反推出來）、`fixed_speed: float = 0.0`（>0 時優先於 `travel_time`，直接當固定飛行速度，不受 `max_range` 影響——給會反彈、`max_range` 代表總路徑長度而非終點距離的法術用）、`bounces_off_walls: bool = false`（碰到場地邊界是否反彈）。

### 3.2 `SelfDelivery`
以施法者為中心，對 `radius` 範圍內的 `"enemies"` 群組成員造成 `stats.damage` 並呼叫 `target.apply_knockback(...)`。沒有飛行階段，命中判定跟傷害/擊退在 `fire()` 裡一次做完。對應近身範圍攻擊類法術（`ForceWave` 使用）。

**不要跟 `SelfBuffDelivery` 搞混**：`SelfDelivery` 命中的是「周圍的敵人」，`SelfBuffDelivery` 命中的是「施法者自己」，兩者雖然都沒有飛行階段、名字也相近，但命中對象完全不同。

### 3.3 `AoETargetingDelivery`
鎖定選點的範圍法術。`fire()` 是非同步的：暫停遊戲（`get_tree().paused = true`，真正的暫停，不是子彈時間）、顯示跟隨滑鼠的選點介面（`AoETargetingReticle.gd`，`process_mode = PROCESS_MODE_ALWAYS` 才能在暫停時繼續運作）、`await` 等玩家確認/取消、恢復遊戲後對選定點 `radius` 範圍內所有 `"enemies"` 群組成員造成傷害。`max_range` 詮釋成「鎖定距離上限」，超出範圍時指示圈鎖在邊界並變灰。右鍵瞬發一樣會走這整條暫停選點流程，只是不經過吟唱、傷害用固定倍率——瞬發省略的是吟唱/超魔專長累積階段，不是 delivery 本身的運作方式。

`@export var radius: float = 90.0`。

### 3.4 `SelfBuffDelivery`
效果直接套用在施法者自己身上，無命中判定：

```gdscript
func fire(caster, _direction, stats, _max_range, effects := []) -> void:
	for effect in effects:
		if effect.apply_mode == SpellEffect.ApplyMode.DURATION:
			caster.add_buff(effect)
		else:
			effect.apply(stats)
```

對應 buff 類法術（`Invisibility`、`SpeedBoost` 使用），細節見第6節。

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
@export var damage_mult: float = 0.0  # 超魔專長的百分比加成
```
`apply(stats)`：`stats.damage += randf_range(min_amount, max_amount) + stats.damage * damage_mult`——百分比加成是對「目前已累加的傷害值」疊加，不是對最終值相乘，疊加順序即打出專長的順序。

### 4.2 `InvisibilityEffect`（DURATION，`buff_id = "invisibility"`）
`on_start()`：`target.is_invisible = true`。`on_expire()`：`target.is_invisible = false`。持續期間敵人完全找不到玩家位置（見第6節）。

### 4.3 `SpeedBuffEffect`（DURATION，`buff_id = "speed_boost"`）
`@export var mult: float = 0.1`（+10%）。`on_start()`：`target.speed_boost_mult = mult`。`on_expire()`：`target.speed_boost_mult = 0.0`。

---

## 5. `ProjectileImpact`（`scripts/spells/ProjectileImpact.gd`）

投射物命中東西、或飛行距離耗盡（`body == null`）時呼叫，回傳是否該消失：

```gdscript
func resolve(projectile: Node, body: Node) -> bool
```

- **`SingleHitImpact`**：命中第一個東西就扣血、消失；飛行到頭直接消失不做任何事。目前沒有法術使用。
- **`ExplosiveImpact`**：命中東西「或」飛行到頭都會爆炸，對爆炸點 `radius`（預設90）範圍內所有 `"enemies"` 群組成員造成傷害，不穿透。目前沒有法術使用。
- **`PiercingImpact`**：全距離無限穿透，命中任何東西都造成傷害但不消失，只有飛行距離耗盡才真正結束。`LightningBolt` 使用。

`SingleHitImpact`/`ExplosiveImpact` 是架構上保留的變體，暫時沒有法術採用，不代表沒用、該刪。

---

## 6. Buff 系統（`Player.gd`）

```gdscript
var active_buffs: Array = []   # [{effect: SpellEffect, timer: float}]

func add_buff(effect: SpellEffect) -> void   # 同 buff_id 再次命中時刷新 timer，不疊加兩份獨立倒數；否則新增一筆並呼叫 effect.on_start(self)
func has_buff(buff_id: String) -> bool
func _process_buffs(delta: float) -> void    # 每個 _physics_process() 呼叫：倒數各筆 timer，到期呼叫 effect.on_expire(self) 並移除
```

`is_invisible: bool`、`speed_boost_mult: float` 是兩個專用欄位，由對應的 `on_start()`/`on_expire()` 直接讀寫，不是通用化的效果數值介面——目前只有這兩種 buff，效果本質不同（一個是 bool 旗標、一個是數值疊加），沒有做成完全統一的介面。

`speed_boost_mult` 跟 Boss 吸引懲罰用的 `speed_multiplier` 是兩個分開的欄位：`_process_movement()` 兩者相乘生效（`SPEED * speed_multiplier * (1.0 + speed_boost_mult)`），避免同一個欄位被多個獨立來源覆蓋。

**隱形對 boss 的影響**：`Boss.gd`/`BossFireball.gd`/`BossOrb.gd`/`BossSuctionZone.gd` 各自有一份 `_find_player()`，玩家 `is_invisible` 為真時統一回傳 `null`——這是本體/分身鎖定玩家位置的唯一入口，單點擋住就讓所有依賴它的攻擊同時失去目標。已鎖定飛行中的攻擊不受影響（隱形防的是新的鎖定）。

**隱形中斷**：中斷規則不寫在 `InvisibilityEffect` 身上，而是 `Player._fire_spell()`/`_fire_instant_spell()` 開頭統一呼叫 `_break_invisibility_on_cast()`——中斷的觸發點是「玩家施放了任意法術」這個主動行為，不是效果本身的倒數邏輯。重新施放隱形術本身也會先被中斷一次，再被這次施放重新安裝，等於無縫刷新。

---

## 7. 現行法術總表（`GameState.CATALOG`）

| 法術 | Delivery | Impact/Effect | 數值 | `slot_cost` |
|---|---|---|---|---|
| 火球術 Fireball | `AoETargetingDelivery` | `DamageEffect` | radius=90，傷害8~12 | 3 |
| 力場波 ForceWave | `SelfDelivery` | `DamageEffect` | radius=140，knockback=500，傷害12~18 | 2 |
| 雷電箭 LightningBolt | `ProjectileDelivery` | `PiercingImpact` + `DamageEffect` | 反彈、`fixed_speed`=700，傷害6~10 | 1 |
| 隱形術 Invisibility | `SelfBuffDelivery` | `InvisibilityEffect` | 持續5秒 | 2 |
| 速度提升 SpeedBoost | `SelfBuffDelivery` | `SpeedBuffEffect` | +10%移動速度，持續10秒 | 1 |

---

## 8. GDScript 語言限制

`_init()` 裡直接賦值**繼承自父類別**的 `@export` 欄位會編譯失敗（`Identifier not found`），必須加 `self.` 明確限定：

```gdscript
func _init() -> void:
	self.apply_mode = SpellEffect.ApplyMode.DURATION   # 正確：繼承來的欄位要加 self.
	self.buff_id = "invisibility"
```

欄位若是宣告在子類別自己身上（例如 `DamageEffect` 的 `min_amount`），則不需要 `self.` 也能在 `_init()` 裡直接賦值。只有「`_init()` 賦值繼承來的欄位」這個特定組合會出錯，`_ready()`、一般方法存取繼承欄位不受影響。

GDScript 沒有真正的 interface/abstract class 強制力：`SpellDelivery`/`SpellEffect` 的基底方法只能靠約定，忘記覆寫不會在編輯期被抓到，只會在執行期 `push_error` 或默默無效。

---

## 9. 符紋與法術能力的相容性設計（規劃中，尚未實作）

### 9.1 問題
一把法術的 `impact`/`delivery` 可能具備多種性質（例如 `ExplosiveImpact` 有爆炸半徑這個維度），理應能吃到對應維度的超魔專長強化，但目前的套用迴圈（`Player._fire_spell`）沒有機制表達「這個專長對這把法術到底有沒有用」——效果有沒有實際作用，完全取決於有沒有東西去讀 `stats` 裡對應的鍵，是意外不是設計。法術種類越多，這個問題越明顯。

### 9.2 設計草案：能力宣告（capability）機制
比照 PoE 輔助寶石的 tag 相容性：

- `SpellDelivery`／`ProjectileImpact` 各自加一個 `get_capabilities() -> Array[String]`，`Spell.get_capabilities() = delivery.get_capabilities()`。例如 `ExplosiveImpact.get_capabilities()` → `["area_radius"]`。
- `SpellEffect` 加一個 `required_capability: String`（預設空字串＝通用，任何法術都吃得到）。
- 套用效果的迴圈改成：`if effect.required_capability == "" or effect.required_capability in equipped_spell.get_capabilities(): effect.apply(stats)`，否則跳過並給玩家視覺回饋（跟「專長失敗」要有區別，不要讓玩家誤以為打錯鍵）。

### 9.3 現況
尚未實作。目前所有可疊加的超魔專長效果（傷害加成、吟唱速度）都是通用效果，沒有需要過濾的實例，落地時機是大廳做法術個別配置超魔專長池的時候——那時候需要知道「這把法術能吃哪些專長」才能在 UI 正確過濾不相容的選項。
