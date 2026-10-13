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

**自身中心類 delivery（`SelfDelivery`/`SelfBuffDelivery`，施放不需要瞄準/選點，效果永遠發生在施法者自己身上或周圍）的 `max_range` 一律是 `0.0`**——這類法術沒有「打多遠」的概念，只有「影響範圍多大」（`SelfDelivery.radius`，法術擴展的縮放目標），兩者不是同一個東西。`SelfBuffDelivery` 用的兩把法術（`Invisibility.tres`/`SpeedBoost.tres`）從一開始就是 `0.0`；`ForceWave.tres`（`SelfDelivery`）2026-10-12 之前誤設成跟 `radius` 同值（`140.0`），導致法術增遠（`range_mult`）的相容性判斷（`spell.max_range > 0.0`）誤判成「適用」，使用者實測發現可以縮放一個根本不存在意義的「距離」數值，已修正成 `0.0`。**新增自身中心類法術時，`.tres` 的 `max_range` 要記得設 `0.0`，不要照抄其他欄位的數值或留著預設值不管。**

`.tres` 法術資源放在 `resources/spells/`。

---

## 3. `SpellDelivery`（`scripts/spells/SpellDelivery.gd`）

介面：

```gdscript
func fire(caster: Node2D, direction: Vector2, stats: Dictionary, max_range: float, effects: Array = []) -> void
```

`stats` 是呼叫端（`Player.gd`）先套用完 `base_effects` 跟超魔專長效果算好的最終數值（目前只有 `damage` 鍵）。`effects` 是 `Spell.base_effects` 的原始陣列（不是攤平後的 `stats`），只有 `SelfBuffDelivery` 會用到，其餘 delivery 忽略這個參數。

### 3.1 `ProjectileDelivery`
直線投射物，固定方向飛行。`@export var projectile_scene: PackedScene`、`impact: ProjectileImpact`（命中/飛行耗盡後行為，見第5節）、`travel_time: float = 0.1`（法術固定要在這麼多秒內飛完 `max_range`，速度反推出來）、`fixed_speed: float = 0.0`（>0 時優先於 `travel_time`，直接當固定飛行速度，不受 `max_range` 影響——給會反彈、`max_range` 代表總路徑長度而非終點距離的法術用）、`bounces_off_walls: bool = false`（碰到場地邊界是否反彈）、`count: int = 1`／`launch_interval: float = 0.08`（2026-10-12 新增：法術強效縮放量詞用，`count > 1` 時朝同一方向依序射出，見 §4.4）。

**`bounces_off_walls=true` 的反彈判定（`SpellProjectile._bounce_off_arena_bounds()`）讀的是 `Arena.ARENA_CENTER`/`Arena.PLAYER_ZONE_RADIUS` 這兩個寫死在 `Arena.gd`（`Main.tscn` 戰鬥場地專用）腳本類別上的 `const`**——這兩個是類別層級的常數，不需要場景裡真的有 `Arena` 節點就讀得到，2026-10-12 之前因此在 `scenes/SpellTestRange.tscn`（沒有 `Arena` 節點、也沒有牆、玩家出生點離 `Arena.ARENA_CENTER` 本來就超出 `PLAYER_ZONE_RADIUS`）出現「雷電箭看起來沒有從角色位置發射」＋「沒有牆的地方也會反彈」兩個症狀——其實是同一個根因：投射物一出生，第一個 `_physics_process()` tick 就因為「距離 `Main.tscn` 的場地中心已經超出 `Main.tscn` 的場地半徑」而被夾限彈飛，彈去的位置當然跟玩家實際站的地方對不上。已修正成先判斷 `get_tree().current_scene.has_node("Arena")`，沒有 `Arena` 節點的場景（例如 `SpellTestRange.tscn`）直接跳過整段反彈判定，投射物單純飛到 `max_range` 自然消失。**之後任何會被 `SpellTestRange.tscn` 這種非 `Main.tscn` 場景使用到的共用法術元件，碰到需要「場地邊界」這類只在特定場景才有意義的概念時，都要留意是不是又在用這種「讀類別常數、不檢查節點是否存在」的方式取資料，會在缺少對應場景結構的地方產生同一類幽靈邊界。**

### 3.2 `SelfDelivery`
以施法者為中心，對 `radius` 範圍內的 `"enemies"` 群組成員造成 `stats.damage` 並呼叫 `target.apply_knockback(...)`。沒有飛行階段，命中判定跟傷害/擊退在 `fire()` 裡一次做完。對應近身範圍攻擊類法術（`ForceWave` 使用）。

**不要跟 `SelfBuffDelivery` 搞混**：`SelfDelivery` 命中的是「周圍的敵人」，`SelfBuffDelivery` 命中的是「施法者自己」，兩者雖然都沒有飛行階段、名字也相近，但命中對象完全不同。

### 3.3 `AoETargetingDelivery`
鎖定選點的範圍法術。`fire()` 是非同步的：暫停遊戲（`get_tree().paused = true`，真正的暫停，不是子彈時間）、顯示跟隨滑鼠的選點介面（`AoETargetingReticle.gd`，`process_mode = PROCESS_MODE_ALWAYS` 才能在暫停時繼續運作）、`await` 等玩家確認/取消、恢復遊戲後對選定點 `radius` 範圍內所有 `"enemies"` 群組成員造成傷害。`max_range` 詮釋成「鎖定距離上限」，超出範圍時指示圈鎖在邊界但顏色不變灰（夾限後一樣會成功命中，不是失敗狀態）。右鍵瞬發一樣會走這整條暫停選點流程，只是不經過吟唱、傷害用固定倍率——瞬發省略的是吟唱/超魔專長累積階段，不是 delivery 本身的運作方式。

`AoETargetingReticle.gd` 2026-10-12 起掛在 `scenes/entities/Player.tscn` 底下（不是場景根層級），`fire()` 用 `caster.get_node("AoETargetingReticle")` 取得它（`caster` 就是施法的 Player，這個節點是它的直屬子節點）——理由跟下面 §4.4 旁邊、`docs/DESIGN.md` §1.6 記錄的 `CastPreview.gd` 同一輪改動一樣：避免每個場景各自手動補節點、各寫一份綁定邏輯導致忘記接的問題。

`@export var count: int = 1`（2026-10-12 新增，法術強效縮放量詞用，見 §4.4）：`count > 1` 時可以依序選多個點，玩家每次可以點不同位置，全部選完（或中途整個取消）才統一恢復遊戲、依序解算收集到的所有點。

**多點選取的互動邏輯整個收在 `AoETargetingReticle.gd` 內部（2026-10-12 重新設計，使用者實測後要求的互動語意）**，`AoETargetingDelivery.fire()` 只要 `reticle.start(caster, max_range, radius, count)` 一次、`await reticle.finished` 一次，拿到的是一個 `Array[Vector2]`（已確認的所有點，可能是空陣列）：
- **左鍵（`cast_spell`）＝確認**：把目前瞄準的點加進 `confirmed_points`。確認滿 `count` 個就結束（emit 全部點）；不夠的話留在選取模式，继续選下一個。
- **右鍵（`instant_cast`）＝撤銷上一步**：`confirmed_points` 非空時，把最後一個已確認的點丟掉，退回去重選那個位置（不是整個取消）。`confirmed_points` 是空的（還沒確認過任何點）時，右鍵退化成舊行為：整個取消，不施放。
- **ESC＝整個取消**：不管選到第幾個，已經確認的點全部作廢，emit 空陣列——這是跟右鍵語意不同的「大取消」，右鍵是一步步撤銷，ESC 是整組放棄。
- 已確認的點會畫出痕跡（跟著一路保留到選完/取消），跟著滑鼠走的「目前瞄準、還沒確認」那一圈是分開畫的。

**痕跡圈重疊不會疊加變亮（2026-10-12，使用者明確要求）**：如果直接在 `AoETargetingReticle._draw()` 裡疊加畫多個半透明圈，彼此重疊的區域會因為 alpha 合成疊加而比單一個圈更亮/更飽和。解法是 `scenes/entities/Player.tscn` 的 `AoETargetingReticle/TrailLayer`（`CanvasGroup` 節點，`self_modulate` 設成 `Color(1,1,1,0.9)`）底下掛 `TrailMarkers`（`scripts/ui/AoETargetingTrail.gd`，畫已確認的點，用的是 `alpha=1.0` 不透明色）——`CanvasGroup` 會先把底下所有子節點畫進同一塊緩衝區（緩衝區內部用不透明色畫，彼此重疊只是互相覆蓋，不會疊加變亮），再把整塊緩衝區當成一個單位，用 `CanvasGroup` 自己的 `self_modulate` 透明度跟背景合成一次——不管疊幾個痕跡圈在同一塊區域，最終看起來永遠跟畫一個圈一樣亮。已截圖驗證過：兩個刻意重疊的痕跡圈，交叉處維持原本亮度，沒有變亮。

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

### 3.5 `HomingMissileDelivery`
自動鎖定目標的追蹤飛彈，發射機制跟 `ProjectileDelivery` 本質不同（不是加參數能表達的數值差異），獨立成子類別：

- 不吃瞄準方向——`fire()` 忽略傳入的 `direction` 參數，施放當下自動從 `max_range` 範圍內挑**最近**的一個 `"enemies"` 群組成員鎖定；範圍內沒有目標就直接不發射（不會對著空氣射）。
- `missile_count`（預設3）發飛彈**依序**發射（`launch_interval` 間隔，預設0.12秒），不是同時射出，`fire()` 是非同步的（`await` 發射間隔）。發射方向直接對準目標，不額外加起手偏移角——彎曲不規則的弧線效果全部交給 `HomingMissile.gd` 全程持續的隨機漂移處理（見下）。
- `@export var missile_scene: PackedScene`（`HomingMissile.tscn`）、`impact: ProjectileImpact`、`missile_count: int = 3`、`missile_speed: float = 850.0`、`turn_rate: float = 5.0`（徑度/秒，飛彈最大轉向速率）、`launch_interval: float = 0.12`。

對應 `MagicMissile` 使用。投射物視覺（`HomingMissile.gd:_draw()`）是帶尖端方向的小飛鏢造型，跟 `SpellProjectile.gd` 的圓形光點刻意畫成不同樣子，一眼能分辨是會轉向的飛彈。

**`HomingMissile.gd` 的飛行邏輯（三發飛彈共用同一支腳本，各自獨立運作）**：

- **基準方向 + 隨機漂移兩層疊加**：每幀先算出「這一幀當下朝向目標」的基準方向（沒有目標時維持目前飛行方向），再疊加一個連續漂移的隨機角度偏移（漂移角速度本身也是隨機游走、有阻尼拉回0，不是每幀直接 `randf()` 亂跳），兩者相加成最終想要朝向的角度，再用 `rotate_toward()` 把目前速度方向往那個角度轉一點（受 `turn_rate` 限制轉多快）——這就是「先算出直線路徑，再 random 成曲線路徑前進」的實作方式，漂移貫穿整段飛行過程，不是只有起步那一下歪一次。
- **目標死亡後自動在範圍內找下一個目標**：每幀只要鎖定的目標失效（死亡/消失）就立刻重新掃一次 `"enemies"` 群組，找飛彈目前位置 `max_range` 範圍內最近的下一個，找不到才真的退化成「維持目前飛行方向」的直線彈——三發飛彈鎖定同一個初始目標，但目標死亡不代表還在飛的其他發就沒事做，會自動轉去打範圍內其他敵人。
- **`max_range` 只在「目前沒有目標可追」時才當飛行距離上限**：只要還在追蹤（不管是原本的目標還是中途換的新目標），不會因為飛行距離超過 `max_range` 就放棄——目標會移動（含 boss 的瞬間跳位巡邏），飛彈持續修正路線本來就會比直線距離繞得遠。追蹤中的保底安全網是 `HomingMissile.MAX_LIFETIME`（6秒，時間制不是距離制），純粹防止極端情況下變成永遠不消失的孤兒節點，不是用來限制「有沒有機會追到」。

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

### 4.4 數值縮放類超魔專長（2026-10-11 新增：法術強效/法術增遠/法術擴展/法術極效；2026-10-12 補上法術延時）

這 5 個超魔專長是「原地放大/最大化這次施放的法術數值」，跟 `UU`/`UDU`/`UULR`（`damage_mult`，疊加獨立加成）性質不同——不能直接改 `equipped_spell`/`delivery`/`base_effects` 任何欄位（Resource 是共享引用，見第1節），一定要 `duplicate(true)` 深層複製一份再改，原本的 `.tres` 完全不動。`Player._apply_scaling_feats(spell, feats)` 負責這件事，`_fire_spell()` 一律改用它回傳的複製品。

縮放邏輯**不**集中寫在 `Player.gd` 用型別判斷，而是比照 `apply()`/`on_start()`/`on_expire()` 的虛擬方法模式：
- `SpellEffect.gd` 新增 `scale_potency(mult)`／`maximize()`（預設空實作）：`DamageEffect` 覆寫兩者（`min_amount`/`max_amount` 乘 `mult` 後 floor；`maximize()` 把 `min_amount` 設成 `max_amount`，讓 `randf_range` 必定回傳上限）；`SpeedBuffEffect` 只覆寫 `scale_potency()`（`mult` 是 0.1 這種比例，floor 浮點數本身會變成 0，要先換算成整數百分點再 floor）；`InvisibilityEffect` 兩個都不覆寫（只有 `duration`，算 metadata，不是「效果文數值」）。
- `SpellDelivery.gd`／`ProjectileImpact.gd` 各新增 `scale_radius(mult)`（預設空實作）：`SelfDelivery`/`AoETargetingDelivery`/`ExplosiveImpact` 覆寫成 `radius *= mult`；`ProjectileDelivery` 覆寫成委派給自己的 `impact`。
- `SpellDelivery.gd` 新增 `scale_count(mult)`（預設空實作，2026-10-12 補上）：量詞（「這次打幾下/射幾發/丟幾顆」）使用者確認跟效果強度同屬「法術強效」範圍，吃 `potency_mult` 這同一個倍率，不是另外開新專長。`Player._apply_scaling_feats()` 裡 `scaled.delivery.scale_count(potency_mult)` 跟 effects 的 `scale_potency()` 並列呼叫，不是獨立的分支。三個 delivery 都覆寫成 `count = maxi(1, int(floor(count * mult)))`（floor 捨去、下限夾1，跟 `DamageEffect.scale_potency()` 同一條規則）：
  - `HomingMissileDelivery.missile_count`（2026-10-12 第一版就有，原本就靠 `launch_interval` 依序發射）。
  - `ProjectileDelivery`（2026-10-12 補上 `count`／`launch_interval` 兩個新欄位）：`count > 1` 時朝同一個瞄準方向依序射出 N 發（跟 `HomingMissileDelivery` 同一套依序發射模式），不是同時射出。
  - `AoETargetingDelivery`（2026-10-12 補上 `count` 欄位）：`count > 1` 時**依序選多個點**——`fire()` 內的迴圈重複呼叫 `reticle.start()`/`await reticle.finished` `count` 次，每次可以點不同位置，不是同一個點疊加好幾次爆炸（使用者確認的手感：像連續丟 N 顆火球，不是單點多重爆炸）。整段選點期間遊戲持續維持暫停（不會選一個點就恢復一次又重新暫停，避免畫面閃爍），中途取消（ESC/右鍵）不會讓整個施放作廢，已經選好的點照樣生效，只是少選到的不會爆炸；全部選完或提前取消後才統一恢復遊戲、依序解算所有收集到的點。`count=1`（預設值，或縮放後 floor 下來還是1）時行為跟改動前完全一致。
  - `SelfDelivery`/`SelfBuffDelivery` 沒有量詞概念（「打周圍所有敵人一次」/「buff自己一次」本來就沒有「打幾次」的意義），維持 `SpellDelivery` 的空實作。
- `SpellEffect.gd` 新增 `scale_duration(mult)`（2026-10-12 補上，法術延時用）：跟 `scale_potency()`/`maximize()` 不一樣，這裡**不用**讓每個子類別各自覆寫——`duration` 本來就宣告在 `SpellEffect` 基底類別身上（不是子類別各自擁有的欄位），基底類別直接 `duration *= mult` 就對所有子類別生效。配套的 `has_scalable_duration()` 也不是看子類別有沒有覆寫，直接問 `apply_mode == ApplyMode.DURATION`（只有 DURATION 類效果的 duration 才有意義，邏輯本來就跟具體子類型無關）。
- 每個方法都配一個 `has_scalable_potency()`/`has_scalable_maximize()`/`has_scalable_radius()`/`has_scalable_count()`/`has_scalable_duration()` 查詢版本，給 `scenes/SpellTestRange.tscn` 的超魔專長相容性灰階用，不用在呼叫端重新判斷型別一次（`_spell_has_scalable_potency()` 同時看 effects 跟 `delivery.has_scalable_count()` 兩邊，只要有一邊成立就不灰掉）。

**範圍界線（2026-10-12 更新：量詞／count、持續時間／duration 都已經各自有對應的專長了）**：`max_range`/`radius`/`duration`/`cast_time` 都算「法術 metadata」，不算在「法術強效」（`potency_mult`）縮放的「效果文數值」範圍內——`max_range`/`radius`/`duration` 現在分別由法術增遠/法術擴展/法術延時各自處理，`cast_time` 目前仍然沒有對應專長處理。法術強效縮放的是效果的強度本身（傷害區間、buff 強度百分比）**以及**量詞（一次打幾下/射幾發/丟幾顆，`HomingMissileDelivery.missile_count`／`ProjectileDelivery.count`／`AoETargetingDelivery.count`）——量詞屬於「這個效果本身多猛」的一部分，不是「影響多遠/多大範圍」的 metadata，所以跟強度數值吃同一個倍率；`duration` 則跟 `max_range`/`radius` 同一類（「影響多久」的 metadata），所以法術延時獨立開一個專長處理，不是併進法術強效。`Fireball.tres`/`LightningBolt.tres` 的 `description` 欄位寫死「1顆」/「1道」，是 `count=1` 這個預設值的文字描述，縮放後不會動態改寫描述文字（跟傷害區間「8~12」這種敘述文字同樣不會動態改寫的既有慣例一致，實際數值變化要看 F4 除錯視窗）。

### 4.5 法術迴響（2026-10-12 新增，`echo: true`；2026-10-12 使用者實測後修正互動邏輯）

跟上面 5 個數值縮放類超魔專長性質不同——**不是**放大某個數值，是「這次施放的效果重複一次」，所以不經過 `_apply_scaling_feats()`／`duplicate(true)` 那套複製保護（它沒有要改任何 Resource 欄位，不需要複製）。

**`echo` 是傳給 `delivery.fire()` 的參數，不是在 `Player._fire_spell()` 自己呼叫 `fire()` 兩次**——第一版曾經這樣做過，但使用者實測後指出：火球術這類需要選點的法術，echo 不應該讓選點介面重新開一次，「點一次，效果變兩次」才對；如果 count>1（選了多個點），應該是「那些被點的地方都發生兩次效果」，不是「全部點位重選一輪」。因此「重複」具體要做什麼，改成交給每個 delivery 自己的 `fire()` 決定（`SpellDelivery.fire()` 的 `echo` 參數註解有完整說明）：
- `AoETargetingDelivery`：選點介面只開一次（`count` 個點，跟 echo 無關），選完**整批**解算一次；`echo` 生效的話，等 `ECHO_DELAY` 秒後**對同一批點**整批再解算一次——不會也不需要重新呼叫 `reticle.start()`。
- `ProjectileDelivery`／`HomingMissileDelivery`：沒有選點互動，「重複」就是整串（`count` 發／`missile_count` 發）依序發射完，等 `ECHO_DELAY` 秒後整串再射一次（`HomingMissileDelivery` 會重新 `_pick_target()`，不是沿用第一輪鎖定的目標，第一輪目標中途死亡的話迴響那輪可以retarget）。
- `SelfDelivery`／`SelfBuffDelivery`：範圍判定/buff安裝整個跑完一次，等 `ECHO_DELAY` 秒後整個再跑一次（`SelfBuffDelivery` 的 DURATION 類效果重複安裝是「刷新剩餘時間」，不是疊加兩份倒數，見 `Player.add_buff()`）。

兩次效果刻意共用同一份已經算好的 `stats`（不重新 roll 傷害區間），跟「量詞」類超魔專長的既有慣例一致（`count=3` 的魔法飛彈，3 發本來就共用同一個 `stats.damage`，不是各自獨立 roll）。

**`ECHO_DELAY := 0.15`（使用者指定，宣告在 `SpellDelivery.gd` 基底類別，所有 delivery 共用同一個數值）**：兩次效果之間固定間隔 0.15 秒，不是立即連續觸發——用 `caster.get_tree().create_timer(ECHO_DELAY).timeout` 等待，發生在解除暫停之後（不在暫停狀態下等待）。

已驗證過：法術迴響+需要選點的火球術，只會開一次選點介面，確認後 `paused` 直接變 `false`（不會重新暫停開第二次選點）；命中判定正確發生兩次（兩次傷害總和落在「單次傷害區間×2」範圍內，兩次數值相同，符合共用同一份 `stats` 的設計）。

沒有相容性限制（`scenes/SpellTestRange.tscn` 的 `_feat_applies_to()` 讓它落在預設 `return true`）——任何法術重放一次都有意義（多一次傷害/多一次範圍/多裝一次 buff），不像其他縮放類專長需要看法術有沒有對應的可縮放欄位。

按鍵序列（`DD`/`DL`/`DR`/`DU`/`DDL`/`DDR`，`GameState.ARCANE_FEATS`）是佔位用的，不是最終設計，之後要改按鍵只改那邊的 key 字串。`DDL`/`DDR` 刻意跟 `DD`（法術強效）共用前綴，比照 `UU`/`UULR` 既有的前綴共用模式（見 §1.2）。

---

## 5. `ProjectileImpact`（`scripts/spells/ProjectileImpact.gd`）

投射物命中東西、或飛行距離耗盡（`body == null`）時呼叫，回傳是否該消失：

```gdscript
func resolve(projectile: Node, body: Node) -> bool
```

- **`SingleHitImpact`**：命中第一個東西就扣血、消失；飛行到頭直接消失不做任何事。`MagicMissile` 使用。
- **`ExplosiveImpact`**：命中東西「或」飛行到頭都會爆炸，對爆炸點 `radius`（預設90）範圍內所有 `"enemies"` 群組成員造成傷害，不穿透。目前沒有法術使用。
- **`PiercingImpact`**：全距離無限穿透，命中任何東西都造成傷害但不消失，只有飛行距離耗盡才真正結束。`LightningBolt` 使用。

`ExplosiveImpact` 是架構上保留的變體，暫時沒有法術採用，不代表沒用、該刪。

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
| 魔法飛彈 MagicMissile | `HomingMissileDelivery` | `SingleHitImpact` + `DamageEffect` | 自動鎖定最近目標，依序3發、各自轉向修正命中，每發造成1~4傷害 | 1 |

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

**2026-10-12 踩到的坑：`await` 協程暫停期間，`Resource` 複製品如果沒有額外的強引用持有者，可能在暫停過程中被回收，導致協程永遠無法恢復。** 具體案例：`Player._apply_scaling_feats()`（§4.4）用 `duplicate(true)` 產生縮放後的 `Spell` 複製品，`_fire_spell()` 原本只把它存在區域變數 `spell` 裡，呼叫 `spell.delivery.fire(...)`（`AoETargetingDelivery.fire()` 內部有 `await reticle.finished`）之後函式就返回，複製品沒有任何地方長期持有——結果是：同時勾選範圍類超魔專長（法術增遠/法術擴展，會觸發 `duplicate(true)`）＋火球術這種 `AoETargetingDelivery` 法術時，選點確認後遊戲永遠卡在暫停狀態（`get_tree().paused` 回不去 `false`），玩家體感是「放完法術卡死」；不勾縮放專長（直接用 `equipped_spell.delivery`，被 `Player.equipped_spell` 長期持有，不會被回收）或用不含 `await` 的 delivery（`ProjectileDelivery`/`SelfDelivery` 等）都不會觸發，這正是一開始難以定位的原因。修法：`Player.gd` 新增 `_active_cast_spell: Spell` 欄位，`_fire_spell()` 把縮放後的複製品額外存一份進去，讓它在整段非同步流程期間都有一個不會消失的強引用持有者（欄位本身不被讀取，純粹是保活用）。**以後任何「`duplicate(true)` 產生的臨時 Resource」只要會流進 `await`-based 的呼叫鏈（目前只有 `AoETargetingDelivery.fire()`），都要比照辦理，不能只放區域變數。**

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
