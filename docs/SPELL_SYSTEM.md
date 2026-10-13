# 法術系統架構

> **2026-10-13 Phase 3 重新設計**：原本「`Spell`（設定值）+`SpellDelivery`（怎麼飛）+`SpellEffect`（命中後做什麼）」三層通用組合，是為了「任何法術都能被超魔專長動態插效果」設計的——法術圖譜的節點本來就是寫死、獨一無二的單一招式，不需要這種通用可組合性，使用者 review Phase 3 規劃時提出這個質疑，拍板改成：`Spell` 瘦身成純設定值 + 一個虛函式 `cast(caster, aim_dir)`，每種法術類型自己的子類別（`ProjectileSpell`/`ZoneSpell`）實作自己的效果，不再經過 `SpellDelivery`/`SpellEffect` 這層通用中介。**`SpellDelivery`/`SpellEffect` 及其所有子類別（含 `ProjectileDelivery`——不是只有先前就標注「目前沒有法術資源使用」的 `AoETargetingDelivery`/`HomingMissileDelivery`）現在整組變成孤兒，沒有任何新節點引用**，但不刪（`CLAUDE.md`「功能類的東西可以先留下」），見 §3/§4 開頭的孤兒標註。`ProjectileImpact`（§5）跟它的子類別（`ExplosiveImpact`/`PiercingImpact`/`SingleHitImpact`）不受影響，繼續被新的 `ProjectileSpell` 直接呼叫，是真正的飛行/碰撞基礎設施，不是這次拆掉的通用效果組合。
>
> 2026-10-13 跟著舊戰鬥系統一起刪除的（更早的轉型）：「一把法術一份 `.tres`、玩家裝備6把」的資料模型（`GameState.gd`／大廳裝備流程）、超魔專長數值縮放機制（`_apply_scaling_feats()` 那一整套）、§9 的 capability 相容性草案。

---

## 1. 核心原則：每種法術類型自己實作自己的效果

| 關注點 | 是什麼 | 存在哪裡 |
|---|---|---|
| **法術定義＋效果** | 純設定值 + `cast()` 怎麼產生效果 | `Spell` 子類別（Resource，`.tres`），見 §2 |
| **飛行/碰撞基礎設施** | 投射物怎麼飛、怎麼判定命中（真正可重用的機制，不是效果組合） | `SpellProjectile.gd`/`ProjectileImpact`，見 §5 |
| **執行時狀態** | CD 倒數、蓄力進度、生效中的 buff | 角色節點本身，絕不放在 Resource 上 |

**`Spell` 子類別這些 Resource 永遠只放設定值，絕不放會變動的運行時狀態**：Godot 的 Resource 預設是共享引用，不是值型別，兩個節點指到同一份 `.tres` 時，若運行時狀態（例如倒數計時器）存在 Resource 上，會互相污染。倒數狀態（例如 `DamageZone` 的 `_tick_timer`/`_life_timer`）存在生成出來的場景節點上，不是存在 `Spell` Resource 上——這條規則也記錄在 `CLAUDE.md` 架構規則1。

新增一個跟既有類型（投射物/範圍持續傷害）同形狀、只是數值不同的法術：建一個新的 `.tres`，不碰程式碼。新增真正全新的效果形狀（不是投射物也不是範圍 tick）才需要寫新的 `Spell` 子類別。

---

## 2. `Spell`（`scripts/spells/Spell.gd`）與子類別

基底類別只剩身份/說明文字 + 一個虛函式，**不放任何數值類欄位**：

```gdscript
@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export_multiline var description: String   # 手寫說明文字，不是自動組出來的

func cast(caster: Node2D, aim_dir: Vector2) -> void   # 基底不實作，子類別各自決定怎麼產生效果
```

`SpellGraphNode.spell` 欄位實際放的永遠是下面某個具體子類別的實例，不會是裸的 `Spell`（除非故意當佔位，`get_class() == "Spell"` 時 `cast()` 只會 `push_error`）。

**2026-10-13 第三次重新設計：連「同類法術共用一個設定值類別」都進一步拆開了**——使用者指出 `ProjectileSpell` 原本放的 `damage`/`explosion_radius` 不該在那裡：不是每個「會飛的投射物」都保證造成傷害（以後可能有純位移/純效果的投射物），`explosion_radius` 更是只有火球術這種會爆炸的才需要。原本借用基底 `Spell.max_range` 的欄位也有同樣問題——`ProjectileSpell`（飛行距離）跟 `ZoneSpell`（生成位置離施法者多遠）共用同一個欄位名字，意義卻完全不同。拆法：

- **`Spell`**（基底）：不放任何數值欄位，純粹是身份識別 + `cast()` 介面。
- **`ProjectileSpell extends Spell`**（中繼層，一樣不會被直接生成）：只放「這是一個會飛的東西」本身一定會有、不管哪種投射物都通用的 4 個欄位——`travel_range`（取代舊的 `max_range`，改名是因為飛行路徑不保證是直線，這是「總路徑長度」不是「終點距離施法者多遠」）、`speed`、`size`（投射物大小/寬度，影響碰撞判定半徑跟長相比例尺）、`piercing`（命中後要不要消失，目前主要是描述性欄位，給以後 UI 顯示/篩選用——`FireballSpell`/`FireArrowSpell` 的 `cast()` 已經各自直接知道要生成哪種 Impact/投射物類別，不會真的讀這個值做分支）。`cast()` 依然是虛函式，不實作。
- **`FireballSpell extends ProjectileSpell`**：火球術自己的 `damage`/`explosion_radius`，`cast()` 完整實作——生成 `ExplosiveImpact`+`FireballProjectile`。
- **`FireArrowSpell extends ProjectileSpell`**：火焰箭自己的 `damage`（沒有 `explosion_radius`，用不到），`cast()` 完整實作——生成 `PiercingImpact`+`FireArrowProjectile`。

```gdscript
# ProjectileSpell.gd（中繼層）
@export var travel_range: float = 650.0
@export var speed: float = 600.0
@export var size: float = 8.0
@export var piercing: bool = false

# FireballSpell.gd
@export var damage: float = 12.0
@export var explosion_radius: float = 90.0

# FireArrowSpell.gd
@export var damage: float = 7.0
```

判斷一個數值欄位該放在哪一層的準則：**不保證每個同類子類別都需要的欄位，不要放在共用的中繼層**，哪怕現在剛好兩個都有（`damage` 現在剛好火球術跟火焰箭都有，但因為「不保證」，所以還是各自宣告一份，不借用繼承）。

### 2.1 `ProjectileSpell` 中繼層跟 `SpellProjectile` 節點骨架的拆分（長相/收尾手感）

`cast()` 不經過 `SpellDelivery`，直接 `.new()` 自己的投射物類別、呼叫 `setup(aim_dir, damage, travel_range, speed, impact)`——跟 `Player._fire_charged_fireball()`（Phase 1 就繞過 `Spell` Resource 直接這麼做，Phase 3 之後都指向同一組投射物類別）是同一手法，這次只是把它收進 `Spell` 子類別裡，讓圖譜節點也能用同一套。

**節點（場景）層也是同樣的拆分邏輯，而且命名直接按法術本身取，不是按視覺分類取**——使用者先指出飛行物理（直線飛行的位置積分、撞牆反彈）沒有「法術差異化」的意義，是純粹的物理計算，應該共用；長相/收尾手感才是玩家會感受到差異的地方，應該各自獨立。接著使用者又指出第一輪拆完的檔名（`ExplosiveOrbProjectile`/`PiercingBoltProjectile`）還是「按長相分類」取名，本質上仍是一種共用抽象的思維，要找火焰箭的程式碼還得先知道它屬於哪個「視覺類型」——改成直接按法術名字取檔名，拆成：

- **`SpellProjectile.gd`**（`class_name SpellProjectile extends Area2D`）：只剩共用的直線飛行骨架——`velocity`/`distance_traveled`/`max_range`（節點自己的飛行距離狀態，由 `setup()` 的 `range_limit` 參數帶進來，跟 Resource 層的 `travel_range` 是兩個獨立欄位，只是數值相同）判斷、撞牆反彈（`_bounce_off_arena_bounds()`）、命中轉呼叫 `impact.resolve()`。還有一個 `size` 欄位，純粹代為保存 `ProjectileSpell.size`，子類別自己決定怎麼用。開放一個虛函式 `_on_max_range_reached()`（預設 `_resolve(null)`，直接消失）給子類別覆寫。**這個類別本身不會被直接生成**。
- **`FireballProjectile.gd`**：火球術的長相——旋轉光球+火花拖尾，三個同心圓/環繞光點的半徑都按 `size` 等比縮放，`_draw()`/`spin` 全部自己管，不覆寫 `_on_max_range_reached()`（用基底預設，飛到底直接消失）。
- **`FireArrowProjectile.gd`**：火焰箭的長相——有寬度（`size` 就是射線寬度）的紅色射線，`retracting`/`tail_distance`/`RETRACT_DELAY`/`RETRACT_SPEED_MULT` 這些收尾狀態全部收在這支檔案裡，覆寫 `_on_max_range_reached()` 進入收尾階段（延遲 `RETRACT_DELAY` 秒才讓尾巴開始追頭，見該檔案的 `_draw()` 註解）。

**這兩個子類別都沒有對應的 `.tscn`**：碰撞形狀就一個半徑 = `size` 的 `CircleShape2D`，各自在自己的 `_ready()` 用 `CollisionShape2D.new()`/`CircleShape2D.new()` 建立，不需要為了掛一個子節點多開一個場景檔案——`FireballSpell.cast()`/`FireArrowSpell.cast()` 直接 `FireballProjectile.new()`/`FireArrowProjectile.new()`，不經過 `PackedScene`。**`size` 要在呼叫 `add_child()` 之前設定好**（`projectile.size = size` 要寫在 `add_child()` 前面），因為碰撞形狀是在 `_ready()`（進入場景樹時觸發）建的，太晚設定會建出預設尺寸的碰撞形狀。

兩支子類別檔案彼此不 import、不互相呼叫，改任何一把法術的數值/畫法都不會動到另一把。**之後如果某把法術的移動方式根本不是直線飛行（例如射出型火牆、位移類），不需要繼承 `SpellProjectile`，直接寫自己的場景/腳本即可**——共用的範圍刻意縮到最小、最沒有「選擇意義」的那一塊（純直線飛行的數學），不是要求以後的法術都套進這個繼承體系；真正會因為法術不同而不同的東西（長相、收尾、特殊機制、數值），一律各自獨立一支檔案。

**踩過的坑：`speed` 調到極端值（測試時曾經設到 12000）會讓投射物在物理 tick 之間直接「跳過」目標，完全不會命中**——Godot 的 `Area2D` 重疊偵測是逐 frame 離散採樣，不是連續碰撞偵測（CCD），每幀移動距離一旦遠大於目標的碰撞形狀大小，兩幀之間可能根本沒有任何一刻真的「重疊」過，命中判定就直接漏掉。調投射物速度時如果發現「明明瞄準了卻完全沒有傷害」，先懷疑是不是這個，不是命中判定邏輯本身壞了。

### 2.2 `ZoneSpell` 中繼層跟 `DamageZone` 節點骨架的拆分（火焰地面/火雨術）

跟 `ProjectileSpell` 同一個分層邏輯（§2.1）：`ZoneSpell`（中繼層，不會被直接生成）只放「這是一個會持續造成範圍傷害的東西」一定會有的屬性，不保證每把法術都需要、或已經有獨立長相需求的東西拆到各自的子類別：

```gdscript
# ZoneSpell.gd（中繼層）
enum DamageMode { HIT, DOT }

@export var damage_per_tick: float = 5.0
@export var tick_interval: float = 0.5
@export var duration: float = 3.0
@export var radius: float = 80.0
@export var damage_mode: DamageMode = DamageMode.DOT

# FireGroundSpell.gd
@export var spawn_distance: float = 60.0   # 施法者面前固定距離

# FireRainSpell.gd
@export var placement_range: float = 450.0 # 滑鼠瞄準位置夾限距離，自己專屬的欄位，不跟 ProjectileSpell.travel_range 共用
@export var rain_spawn_interval: float = 0.12 # 掉落物特效的生成頻率，只有這把法術在用
```

**`damage_mode` 決定的不只是數值，是傷害的「感覺」**：火焰地面（`DOT`）站在裡面要安靜持續流血，不該每個 tick 都像被打一次；火雨術（`HIT`）每個 tick 是真正的擊中，要有閃白/彈一下等一般受擊反應。兩者因此走不同的傷害入口（見 §2.3），不是同一個 `take_damage()` 配不同數值。

**節點（場景）層也跟著拆**：
- **`DamageZone.gd`**（`class_name DamageZone extends Node2D`）：只剩共用的圓形持續範圍骨架——tick 判定（純距離計算，不是 `Area2D` 物理重疊，跟 `ExplosiveImpact`/近戰判定同一套手法，這樣目標在兩次 tick 之間移動進出範圍也能正確抓到）、存活計時、畫圓形範圍。`duration` 到期自動 `queue_free()`。**沒有對應的 `.tscn`**（這個節點沒有子節點/碰撞形狀需要組合，直接 `.new()`）。`FireGroundSpell.cast()`、`FireWallSpell.cast()`（§2.4，火柱）都直接生成這個類別，不需要額外長相。
- **`FireRainZone`**（`class_name FireRainZone extends DamageZone`）：只加火雨術專屬的東西——範圍內隨機冒出的掉落物特效（`_spawn_rain_drop()`，`sqrt(randf())` 讓隨機點在圓形面積內均勻分布，不是角度均勻、不然中心會比邊緣密，`GroundProjection.ellipse_point()` 貼合壓扁橢圓視覺範圍，重用 `MagicFX.spawn_burst()`）。`rain_spawn_interval` 是真正的 `@export` 欄位（`FireRainSpell` 直接設定），不是寫死的常數。

**2026-10-13 事後修正：掉落物特效原本直接寫在共用的 `DamageZone.gd` 裡，用 `damage_mode == HIT` 當開關、頻率是寫死的 `const`**——使用者指出這樣等於在共用類別裡 expose 了「只有火雨術在用、還調不到」的東西：火焰地面/火牆術的火柱完全不需要這個效果，不該因為它們剛好也走 `DamageZone` 就被迫一起背負這段邏輯，而且想調火雨術的掉落頻率還得去改共用檔案裡的常數，不是乾淨的資料欄位。拆成上面的 `FireRainZone` 子類別 + `ZoneSpell` 也跟著 `ProjectileSpell` 的模式整個拆成 `FireGroundSpell`/`FireRainSpell` 兩個子類別（原本 `spawn_in_front` 這個 bool 開關也跟著拿掉，兩邊各自的 `cast()` 直接寫死自己的生成位置邏輯，不需要共用一個 if/else 分支）。

### 2.3 兩種傷害入口：`take_damage()` vs `take_dot_damage()`

`TestDummy.gd`/`Player.gd` 都有這兩個方法：

- `take_damage(amount)`：一般受擊——扣血＋閃白/彈一下（`TestDummy`）或 `hazard_flash_timer`/`MagicFX` 爆裂/`hurt` 動畫（`Player`）。投射物命中、近戰、`ZoneSpell.DamageMode.HIT` 的 tick 都走這個。
- `take_dot_damage(amount)`：安靜扣血——只扣血＋（`TestDummy`）跳一個比較不顯眼的傷害數字，沒有任何受擊反應。只有 `ZoneSpell.DamageMode.DOT` 的 tick 走這個。

兩者共用扣血夾限（`hp = max(0.0, hp - amount)`）/死亡判斷邏輯，不要各自維護一份。

### 2.4 Phase 6：火焰護盾／火焰撤離／火牆術——三個互不共用的獨立子類別

這三個節點使用者 2026-10-13 review 時明確要求「連長得像的機制也不要共用」，即使彼此之間、或跟既有的 `ProjectileSpell`/`ZoneSpell` 乍看架構類似，也刻意各自獨立一支檔案、不繼承、不互相呼叫。

**`FireShieldSpell`（火焰護盾）**：
```gdscript
@export var duration: float = 3.0
@export var damage_mult: float = 0.4
```
`cast()` 呼叫 `Player.start_shield(duration, damage_mult)`，寫兩個專屬欄位 `shield_timer`/`shield_damage_mult`——**不經過 `active_buffs`/`SpellEffect`**（§7 的 Buff 系統是為了「同時可能疊加多種不同 buff」設計的，火焰護盾目前是唯一一個自身防護類法術，不需要那層通用性，直接寫專屬欄位更直接）。`Player.take_damage()`/`take_dot_damage()` 都會套用 `shield_damage_mult`。**反傷效果沒做**：原文「對攻擊自己的敵人造成火焰傷害」需要知道攻擊者是誰，但 `take_damage()` 目前完全不接收攻擊者參數，要做反傷得幫近戰/兩種投射物/`DamageZone`/`FireRetreatTrailZone` 全部加這個參數，範圍超出這次，先只做減傷。

**`FireRetreatSpell`（火焰撤離）**：
```gdscript
@export var retreat_distance: float = 120.0
@export var trail_width: float = 50.0
@export var damage_per_tick: float = 3.0
@export var tick_interval: float = 0.5
@export var duration: float = 3.0
```
`cast()` 呼叫 `Player.start_retreat(-aim_dir, retreat_distance)`——**使用者明確要求不要重用 `apply_knockback()`（力道+摩擦力衰減）或 Dash**，即使「短暫位移+`move_and_slide()` 貼牆滑行」形狀很像。`Player.gd` 新增完全獨立的一組狀態：`is_retreating`/`retreat_timer`/`retreat_velocity`/`_process_retreat()`，固定速度位移、時間到準確停在目標距離（不是力道衰減到 0）。原地留下 `FireRetreatTrailZone.gd`（**使用者明確要求不要跟 `DamageZone.gd` 共用**——那是圓形範圍，撤離軌跡是矩形，覆蓋撤離前後整條路徑，用 `to_local()` 轉本地座標做矩形範圍判定，寫法接近 `FireArrowProjectile.gd` 的射線判定但固定不動、沒有頭尾伸縮）。

**`FireWallSpell`（火牆術）**：
```gdscript
@export var pillar_count: int = 5
@export var spacing: float = 50.0
@export var distance_ahead: float = 90.0
@export var cascade_delay: float = 0.08
@export var pillar_radius: float = 40.0
@export var damage_per_tick: float = 4.0
@export var tick_interval: float = 0.4
@export var duration: float = 2.5
```
原文描述「射出型火牆」容易誤會成投射物，**使用者糾正：不是投射物，是在施法者前方固定距離「一次創造」一整排火柱**（使用者的說法：「很多根火柱的集合」），**直接重用現成的 `DamageZone`**（圓形 DOT 範圍，不需要為「火牆」另外設計形狀，`.new()` 直接生成，不經過 `.tscn`）。`cascade_delay` 用 `await scene_tree.create_timer(...).timeout` 依序間隔生成每根火柱（不是同時全部出現），所以 `cast()` 是一個**協程**——呼叫端（`Player._cast_current_node()`）沒有、也不需要 `await` 它，GDScript 允許這種「射後不理」，協程會在背景繼續跑完剩下的火柱。

**排列方向踩過一次坑**：第一版把火柱排成「瞄準方向的垂直線」（`aim_dir.rotated(PI/2.0)`，想成一面擋在前面的牆），使用者實測後糾正——要沿著瞄準方向本身一路往前排（`origin + aim_dir * spacing * i`），不是垂直線；距離也拉長了（`spacing` 50→90、`pillar_count` 5→6）。

`.tres` 法術資源放在 `resources/spells/`。

---

## 3. 〔孤兒〕`SpellDelivery`（`scripts/spells/SpellDelivery.gd`）

> **2026-10-13 現況：這整節描述的架構現在沒有任何法術資源引用**（見文件開頭的說明）——包括 `ProjectileDelivery`，Phase 3 之前它是 `basic.tres` 等節點實際在用的 delivery，現在也被 `ProjectileSpell.cast()` 直接繞過了。以下內容保留供參考（技術細節本身沒有錯，只是目前沒有呼叫端），`CLAUDE.md`「功能類的東西可以先留下」，萬一之後真的冒出「好幾個節點要共用同一種通用發射機制」再撿回來用。

介面：

```gdscript
func fire(caster: Node2D, direction: Vector2, stats: Dictionary, max_range: float, effects: Array = []) -> void
```

`stats` 是呼叫端算好的最終數值（目前只有 `damage` 鍵）。`effects` 是 `Spell.base_effects` 的原始陣列（不是攤平後的 `stats`），只有 `SelfBuffDelivery` 會用到。

**2026-10-13（Phase 2）：`echo` 參數跟整套 `scale_potency()`/`scale_radius()`/`scale_count()`/`maximize()`/`has_scalable_*()`/`get_radius()`/`get_count()`/`describe_potency()` 介面已經整個刪除**（原本掛在 `SpellDelivery`/`SpellEffect`/`ProjectileImpact` 跟各子類別上）——這些都是舊「超魔專長數值縮放」系統（`_apply_scaling_feats()`）的配套介面，`_apply_scaling_feats()` 本體已經在轉型時刪除，但這些方法原本沒有跟著清掉，一直是零呼叫端的殘留介面。新的符文圖譜設計（符文navigate 節點，不縮放數值）確認不會用到這套機制，Phase 2 落地時整個移除，不是繼續留著「以後可能用到」。`get_preview_center()` 不受影響，保留著（那是給 `CastPreview.gd` 的範圍預覽用，跟數值縮放是不同關注點，見 §3.3）。

### 3.1 `ProjectileDelivery`
直線投射物，固定方向飛行。`@export var projectile_scene: PackedScene`、`impact: ProjectileImpact`（命中/飛行耗盡後行為，見第5節）、`travel_time: float = 0.1`（法術固定要在這麼多秒內飛完 `max_range`，速度反推出來）、`fixed_speed: float = 0.0`（>0 時優先於 `travel_time`，直接當固定飛行速度，不受 `max_range` 影響——給會反彈、`max_range` 代表總路徑長度而非終點距離的法術用）、`bounces_off_walls: bool = false`（碰到場地邊界是否反彈）、`count: int = 1`／`launch_interval: float = 0.08`（`count > 1` 時朝同一方向依序射出）。

**`bounces_off_walls=true` 的反彈判定（`SpellProjectile._bounce_off_arena_bounds()`）讀的是 `Arena.ARENA_CENTER`/`Arena.PLAYER_ZONE_RADIUS` 這兩個寫死在 `Arena.gd` 腳本類別上的 `const`，用 `get_tree().current_scene.has_node("Arena")` 判斷目前場景有沒有真的放一個 `Arena` 節點**——2026-10-13 更新：`Arena.gd` 掛載的場景（`Main.tscn`）已經刪除，**目前沒有任何場景有 `Arena` 節點，這個 guard 會永遠為 false，牆壁反彈這條路徑目前整個是死路（不會執行到）**，但程式碼跟 `Arena.gd` 本身都還在（`Arena.gd` 現在是孤兒腳本，沒有掛在任何場景上）。之後如果新系統需要場地邊界反彈，要嘛重新設計場地結構、要嘛修改這個判斷式讀新的邊界來源。

### 3.2 `SelfDelivery`
以施法者為中心，對 `radius` 範圍內的 `"enemies"` 群組成員造成 `stats.damage` 並呼叫 `target.apply_knockback(...)`。沒有飛行階段，命中判定跟傷害/擊退在 `fire()` 裡一次做完。**2026-10-13 更新：「火焰地面」/「火雨術」最後沒有用這個**——使用者 review 時糾正，火焰地面是在施法者面前（不是以自身為中心），火雨術是在滑鼠瞄準位置，兩者都改成 `ZoneSpell`（見 §2.2）生成 `DamageZone`，不是這個 delivery。

**不要跟 `SelfBuffDelivery` 搞混**：`SelfDelivery` 命中的是「周圍的敵人」，`SelfBuffDelivery` 命中的是「施法者自己」。

### 3.3 `AoETargetingDelivery`
鎖定選點的範圍法術。`fire()` 是非同步的：暫停遊戲（`get_tree().paused = true`，真正的暫停，不是子彈時間）、顯示跟隨滑鼠的選點介面（`AoETargetingReticle.gd`，`process_mode = PROCESS_MODE_ALWAYS` 才能在暫停時繼續運作）、`await` 等玩家確認/取消、恢復遊戲後對選定點 `radius` 範圍內所有 `"enemies"` 群組成員造成傷害。

**2026-10-13 現況：目前沒有任何法術資源使用這個 delivery**（舊的火球術 `.tres` 已刪除），`AoETargetingReticle.gd`/`AoETargetingTrail.gd`（跟隨滑鼠的選點介面、多點選取、痕跡圈不疊加變亮的 `CanvasGroup` 處理）整套互動邏輯都完整保留在 `scenes/entities/Player.tscn` 底下，處於「功能完整但沒有東西在用」的狀態——`docs/DEMO_PLAN.md` 規劃的 7 個火系節點目前都是直接朝滑鼠方向施放，沒有一個需要暫停點選。如果之後某個節點需要「選一個/多個地面座標」這種互動（例如更進階的範圍控制型法術），這套機制可以直接拿來用，不用重寫。

`@export var count: int = 1`：`count > 1` 時可以依序選多個點（左鍵確認/右鍵撤銷上一步/ESC整個取消的互動邏輯收在 `AoETargetingReticle.gd` 內部）。`@export var radius: float = 90.0`。

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

`docs/FIRE_PROTOTYPE.md` §6.3 的「火焰護盾」（自身防護類 DURATION buff）規劃用這個 delivery，細節見第6節。

### 3.5 `HomingMissileDelivery`
自動鎖定目標的追蹤飛彈，發射機制跟 `ProjectileDelivery` 本質不同（不是加參數能表達的數值差異），獨立成子類別：

- 不吃瞄準方向——`fire()` 忽略傳入的 `direction` 參數，施放當下自動從 `max_range` 範圍內挑**最近**的一個 `"enemies"` 群組成員鎖定；範圍內沒有目標就直接不發射（不會對著空氣射）。
- `missile_count`（預設3）發飛彈**依序**發射（`launch_interval` 間隔，預設0.12秒），不是同時射出。發射方向直接對準目標，不額外加起手偏移角——彎曲不規則的弧線效果全部交給 `HomingMissile.gd` 全程持續的隨機漂移處理。
- `@export var missile_scene: PackedScene`（`HomingMissile.tscn`）、`impact: ProjectileImpact`、`missile_count: int = 3`、`missile_speed: float = 850.0`、`turn_rate: float = 5.0`（徑度/秒）、`launch_interval: float = 0.12`。

**2026-10-13 現況：目前沒有任何法術資源使用這個 delivery**（舊的魔法飛彈 `.tres` 已刪除），`docs/FIRE_PROTOTYPE.md` 的 7 個火系節點目前沒有一個是導引彈，保留這份架構等之後真的需要「自動追蹤」類型的法術時再接上。

**`HomingMissile.gd` 的飛行邏輯（三發飛彈共用同一支腳本，各自獨立運作）**：基準方向 + 隨機漂移兩層疊加（每幀算出「朝向目標」的基準方向，疊加一個連續漂移的隨機角度偏移，兩者相加後用 `rotate_toward()` 轉向）；目標死亡後自動在範圍內找下一個目標；`max_range` 只在「目前沒有目標可追」時才當飛行距離上限，追蹤中的保底安全網是 `HomingMissile.MAX_LIFETIME`（6秒，時間制）。

---

## 4. 〔孤兒〕`SpellEffect`（`scripts/spells/SpellEffect.gd`）

> **2026-10-13 現況：這整節描述的架構現在沒有任何法術資源引用**（見文件開頭的說明）——`placeholder_basic.tres` 原本透過 `base_effects` 用 `DamageEffect`，Phase 3 之後改成 `ProjectileSpell.damage` 直接一個數值欄位，不再經過 `SpellEffect`。保留供參考，理由同 §3 開頭。`InvisibilityEffect`/`SpeedBuffEffect` 另外還有 §7 Buff 系統這條活路（`Player.active_buffs`/`add_buff()` 不依賴 `SpellDelivery`，是獨立運作的），不是完全沒有存在意義，只是目前沒有任何法術資源會觸發它們。

```gdscript
enum ApplyMode { INSTANT, DURATION }

@export var apply_mode: ApplyMode = ApplyMode.INSTANT
@export var duration: float = 0.0   # 只有 apply_mode == DURATION 時才有意義
@export var buff_id: String = ""    # 只有 DURATION 類效果需要，用來判斷「是不是同一種 buff」

func apply(_stats: Dictionary) -> void       # INSTANT 類覆寫：套用一次性數值（例如傷害）
func on_start(_target: Node) -> void          # DURATION 類覆寫：buff 剛安裝時要做的事
func on_expire(_target: Node) -> void         # DURATION 類覆寫：buff 到期要復原的事，必須能完整抵銷 on_start()
```

舊的呼叫方式（已孤兒）：`Player._base_stats()` 只對 `apply_mode == INSTANT` 的效果呼叫 `apply(stats)`——這個函式連同它組出來的 stats dict 中間層，在 Phase 3 拆掉 `SpellDelivery`/`SpellEffect` 時一併從 `Player.gd` 刪除了（`ProjectileSpell.damage` 直接是一個數值欄位，不用再組 dict）。DURATION 類效果當時是由 `SelfBuffDelivery` 直接拿 `Spell.base_effects` 原始陣列呼叫 `caster.add_buff(effect)`，不經過 `stats`——這條路徑本身沒被刪（§7 Buff 系統現在仍可以被直接呼叫 `add_buff()` 觸發），只是沒有任何法術資源會經過 `SelfBuffDelivery` 走到這裡了。

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

## 5. `ProjectileImpact`（`scripts/spells/ProjectileImpact.gd`）——真正在用的基礎設施

**跟 §3/§4 不一樣，這一節沒有孤兒**：`ProjectileSpell.cast()`（§2.1）直接 `new()` 一個這裡的子類別塞給 `SpellProjectile.setup()`，不經過任何 Delivery 中介。

投射物命中東西、或飛行距離耗盡（`body == null`）時呼叫，回傳是否該消失：

```gdscript
func resolve(projectile: Node, body: Node) -> bool
```

- **`SingleHitImpact`**：命中第一個東西就扣血、消失；飛行到頭直接消失不做任何事。目前沒有任何 `ProjectileSpell` 用這個（只有 `piercing=true/false` 兩個選項對應 `PiercingImpact`/`ExplosiveImpact`），保留著給之後真的需要「單純命中一次就消失、不爆炸」的法術用。
- **`ExplosiveImpact`**：命中東西「或」飛行到頭都會爆炸，對爆炸點 `radius`（`ProjectileSpell.explosion_radius`）範圍內所有 `"enemies"` 群組成員造成傷害，不穿透。火球術（`basic.tres`，`piercing=false`）用這個。
- **`PiercingImpact`**：全距離無限穿透，命中任何東西都造成傷害但不消失，只有飛行距離耗盡才真正結束。火焰箭（`fire_arrow.tres`，`piercing=true`）用這個。

---

## 6. 法術圖譜（`SpellGraphNode`/`SpellGraph`，2026-10-13 Phase 2 落地）

`docs/DEMO_PLAN.md` §4 規劃的資料結構，`scripts/spells/` 底下跟 `Spell.gd` 同一層：

```gdscript
# SpellGraphNode.gd
@export var id: String
@export var spell: Spell
@export var transitions: Dictionary[String, String] = {}   # 符文 -> 下一個節點的 id

# SpellGraph.gd
@export var start_node_id: String
@export var nodes: Array[SpellGraphNode] = []
func get_node_by_id(id: String) -> SpellGraphNode   # 線性搜尋，節點數量不多，不需要優化成查表
```

一個節點就是一把完整可施放的法術（`spell` 放 `Spell` 子類別的實例，見 §2），同時可能是其他節點的轉換起點。`transitions` 本質是有向圖的邊，**沒有任何機制禁止同一張圖出現環或回頭路**——`docs/GDD.md` §5.3 提到的「反向路徑」如果之後要加，直接在某個節點的 `transitions` 裡補一條指回之前節點 id 的符文即可，資料結構層級已經支援，不需要改程式碼。目前唯一一張圖（`resources/spells/fire/fire_graph.tres`）照 `docs/FIRE_PROTOTYPE.md` §5.3 的拓撲建：`basic`/`fire_arrow`/`fire_ground`/`fire_rain` 這 4 個節點（Phase 3 完成）各自接自己的 `ProjectileSpell`/`ZoneSpell`，`fire_shield`/`fire_retreat`/`fire_wall` 這 3 個還沒做（Phase 6）繼續共用佔位 `placeholder_basic.tres`（`ProjectileSpell`）。

### 6.1 符文判定：查表對象是全域語法表，不是目前節點

`Player.gd` 的 `_handle_rune_key()`（複用舊符文系統 `_handle_combo_key()` 的前綴比對骨架）判斷「要不要繼續等下一鍵」時，查的是全域常數 `KNOWN_RUNES`（目前 `["UU","DD","LL","RR"]`），跟目前節點完全無關——這樣玩家在任何節點打符文的「等待手感」都一致，不會因為某節點不接受某符文就提早中斷輸入。只有打出一個完整合法的符文之後，才在 `_commit_rune()` 裡去查目前節點的 `transitions` 有沒有這條路。

**查不到的話，玩家停留在原節點，不是任何懲罰性狀態，也不影響當下能不能施放**——這是 `docs/DEMO_PLAN.md` §4.1 原始判定表沒寫清楚的分支（只寫了「查到就換節點」，沒寫「查不到」），Phase 2 落地時補上的釐清。視覺回饋跟「按錯鍵」共用同一套（`_fail_combo()`），因為對玩家來說兩者都是「這次輸入沒有造成任何改變」，不需要刻意區分。

`current_node_id` 每次進入專注狀態（`_enter_focus()`）都重置回 `current_graph.start_node_id`，不會沿用上次退出時停在哪個節點——跟 `combo_buffer`/`pending_combo` 進入時清空是同一個邏輯慣例。

---

## 7. Buff 系統（`Player.gd`）

```gdscript
var active_buffs: Array = []   # [{effect: SpellEffect, timer: float}]

func add_buff(effect: SpellEffect) -> void   # 同 buff_id 再次命中時刷新 timer，不疊加兩份獨立倒數；否則新增一筆並呼叫 effect.on_start(self)
func has_buff(buff_id: String) -> bool
func _process_buffs(delta: float) -> void    # 每個 _physics_process() 呼叫：倒數各筆 timer，到期呼叫 effect.on_expire(self) 並移除
```

`is_invisible: bool`、`speed_boost_mult: float` 是兩個專用欄位，由對應的 `on_start()`/`on_expire()` 直接讀寫，不是通用化的效果數值介面——目前只有這兩種 buff，沒有做成完全統一的介面。

**隱形中斷**：中斷規則本來不寫在 `InvisibilityEffect` 身上，是靠 `Player.gd` 裡一個統一呼叫點 `_break_invisibility_on_cast()`（觸發點是「玩家施放了任意法術」這個主動行為，不是效果本身的倒數邏輯）——**2026-10-13 現況：原本呼叫它的 `_fire_spell()`/`_fire_instant_spell()` 已經在 Phase 1 轉型時整個刪除，`_break_invisibility_on_cast()` 目前零呼叫端，是孤兒函式**，連同 `is_invisible` 欄位本身一起保留（`Player.gd` 該函式上方有對應註解）。目前也沒有敵人會去讀 `is_invisible`（舊的 `_find_player()` 系列 boss 腳本已刪除），等 `docs/DEMO_PLAN.md` Phase 5 的測試敵人做出來、需要「找不到玩家」這個概念時，兩邊（中斷觸發點＋敵人讀取端）都要重新接上。

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

**`await` 協程暫停期間，`Resource` 複製品（`duplicate(true)` 產生的）如果沒有額外的強引用持有者，可能在暫停過程中被垃圾回收，導致協程永遠無法恢復。** 這條是踩過的真實坑（舊的超魔專長數值縮放機制會 `duplicate(true)` 產生縮放後的 `Spell` 複製品，如果只存在區域變數、沒有任何地方長期持有，搭配 `AoETargetingDelivery.fire()` 內部的 `await reticle.finished`，複製品會在等待玩家選點確認的過程中被回收，協程永遠無法恢復，遊戲卡在暫停狀態）。那套縮放機制已經刪除，但**這條 GDScript 行為本身的教訓是通用的**：以後任何「`duplicate(true)` 產生的臨時 Resource」只要會流進 `await`-based 的呼叫鏈（目前只有 `AoETargetingDelivery.fire()`），都要額外存一份強引用保活，不能只放區域變數。
