# 法術系統架構提案（PoC 之後）

> 範圍聲明：這份文件**只討論法術本身的架構**（定義、發射、效果套用），不涉及符紋系統怎麼生成/疊加強化效果——那是下一份要單獨討論的文件，這裡只確保法術架構留了一個乾淨的掛鉤點給符紋用。

> **狀態：§6 的 v1 範圍已實作完成，後續又經過幾輪修正。** `Spell`/`SpellDelivery`(`ProjectileDelivery`)/`SpellEffect`(`DamageEffect`) 跟 `ProjectileImpact`(`SingleHitImpact`/`ExplosiveImpact`) 都已落地在 `scripts/spells/`，現有的投射物法術與右鍵瞬發已遷移過去。`PierceEffect`/`PiercingImpact`（穿透）跟 `ProjectileSpeedEffect`（彈速）後來都確認用不到或不該存在而移除，細節見「§8 實作後補充」跟「§9 符紋與法術能力的相容性設計」。

---

## 0. 問題陳述：如果什麼都不做，會怎麼爛掉

現在 PoC 的 `Player.gd` 只有一個法術（固定投射物），符紋效果用 `Dictionary` 塞 `damage_mult`/`pierce`/`speed_mult` 字串鍵，在 `_fire_spell()` 裡用迴圈硬加總。這在「只有一個法術」的規模下完全合理，不是錯誤設計。

但依照最初的設計構想（多職業、裝備掉落、符紋解放、不同發射方式的法術），法術數量會持續增加。如果現在不先定架構，大概率會走向兩種已知的爛結局：

1. **巨大的 if/elif/match**：依照 `spell_id` 判斷要跑哪段邏輯，每加一個法術就要在好幾個地方插一個分支——這正是你一開始想避免的 spaghetti。
2. **一個法術一個子類別**：`FireballSpell`、`IceBoltSpell`、`HealSpell`... 相同的發射邏輯被複製貼上十幾次，改一個共通 bug 要改十個檔案，這也是 spaghetti，只是換了個外殼讓人誤以為是「物件導向」。

這份提案的目標：讓**新增一個「普通」法術**（跟既有法術發射方式相同、只是數值不同）**不需要寫新程式碼**，只有「發射機制」或「效果種類」本質上不存在時才需要寫新程式碼——而且寫一次之後，之後所有同類型法術都能重複用。

---

## 1. 核心原則：三個關注點分離，用組合不用繼承

把「法術」拆成三個獨立的東西，各自只做一件事：

| 關注點 | 是什麼 | 存在哪裡 | 範例 |
|---|---|---|---|
| **法術定義** | 純資料：這個法術的數值設定 | `Spell`（Resource，`.tres` 檔） | 傷害10、吟唱2秒、圖示 |
| **發射方式** | 「怎麼離開施法者、怎麼判定命中」的共用邏輯 | `SpellDelivery`（Resource，少量可重用策略） | 直線投射物、光束、範圍 |
| **命中效果** | 「命中後發生什麼事」的共用邏輯，可疊加 | `SpellEffect`（Resource，少量可重用策略） | +傷害、+穿透、+彈速 |
| **執行時狀態** | CD 倒數、本次吟唱已疊加的符紋 | **角色節點身上**（絕對不是 Resource） | `rightclick_cd_timer` |

最後一行是最容易踩的坑，必須畫重點：**`Spell`/`Delivery`/`Effect` 這些 Resource 永遠只放設定值，絕不放會變動的運行時狀態**。Godot 的 Resource 預設是共享引用，不是每個角色各自複製一份——如果兩個角色裝備同一個 `Fireball.tres`，CD 計時器要是存在資源上，兩個角色會共享同一個計時器，狀態互相污染。這點之前討論風險時提過，這裡正式寫進架構規則。

這套「資料+少量可組合行為模組」而非「每個技能一個類別」的做法，是 ARPG/技能系統類遊戲（包括你最初提到想參考的 PoE 輔助寶石概念）背後普遍採用的模式，原因就是上面第0節講的那兩種爛結局。

---

## 2. 具體架構

```
Spell (Resource)
├── id, display_name, icon, cast_time, mana_cost...
├── max_range: float                  (這個法術的有效距離，意義由 delivery 決定如何套用)
├── delivery: SpellDelivery          (多型，決定怎麼發出去/判定命中)
└── base_effects: Array[SpellEffect]  (多型，決定命中後發生什麼，可疊加多個)

SpellDelivery (Resource，基底)
├── ProjectileDelivery   —— 對應現有 PoC 的直線投射物邏輯
├── (未來) BeamDelivery
├── (未來) AoEDelivery   —— 對應原始設計裡「俯視選圈」的範圍法術
└── (未來) ChainDelivery —— 在多個目標間彈跳

SpellEffect (Resource，基底)
├── apply_mode: enum { INSTANT, DURATION }   (瞬發 或 持續性 buff/debuff)
├── duration: float                           (僅 apply_mode == DURATION 時有意義)
├── DamageEffect(amount)              — INSTANT
├── PierceEffect(count)               — INSTANT
├── ProjectileSpeedEffect(mult)        — INSTANT
├── (未來) HealEffect                  — INSTANT
└── (未來) SlowEffect / BurnEffect...  — DURATION
```

**施放流程**：法術觸發時，把 `base_effects` 跟（之後符紋系統會動態追加的）額外 effects 彙整成一包 `stats`，交給 `delivery.fire(caster, direction, stats)`。`delivery` 只負責「怎麼發出去、怎麼判定命中」，不需要知道傷害是多少；命中時把 `stats` 傳給被命中的對象，每個 effect 各自負責套用自己的部分（扣血、加穿透次數...）。

**新增一個「正常」法術**：建一個新的 `Spell.tres`，選既有的 `delivery` 跟 `effects`，填不同數值——不碰程式碼。

**新增一個真正全新的發射機制**（例如連鎖閃電，目標間彈跳）：寫一個新的 `ChainDelivery` 子類別，一次性投資，之後任何法術都能選用它，不用重寫。

**新增一個全新的效果種類**（例如燃燒持續傷害）：寫一個新的 `BurnEffect` 子類別，同理。

### 2.1 `max_range`：同一個欄位，不同 delivery 詮釋方式不同

你提到「投射物有最遠飛行距離、範圍法術有最遠施放點距離」——這兩個概念本質上都是「這個法術的有效距離上限」，所以設計成 `Spell` 身上**同一個** `max_range` 欄位，而不是幫每種 delivery 各開一個獨立命名的距離欄位（例如 `projectile_max_distance`、`aoe_max_cast_range` 分開存）。原因：

- **語意統一，方便裝備/被動效果加成**：原始設計裡裝備能提供「+施放距離」之類的被動效果。如果每種 delivery 的距離欄位命名都不同，被動效果的加成邏輯就要知道「這個法術是哪種 delivery、該加到哪個欄位」，等於又把 delivery 類型的分支判斷拉回法術外層，違背了這份文件一開始想避免的事。统一成一個 `max_range`，被動效果只要說「這個法術的 max_range +50」，不需要關心底下是哪種 delivery。
- **實際套用方式交給各個 `SpellDelivery` 自己決定**，法術本身不管：
  - `ProjectileDelivery`：`max_range` 代表飛行距離上限，投射物飛超過這個距離就自動消失/到頂判定失效。
  - `AoEDelivery`（範圍選圈，對應原始設計裡吟唱完切換俯視視角選圈的法術）：`max_range` 代表「游標離施法者多遠還能選取施放點」，超出範圍的話選圈 UI 應該要有視覺提示（例如圈變灰/鎖在最大距離邊緣），不能選取。
  - 其餘未來的 delivery（`BeamDelivery`/`ChainDelivery`）各自決定 `max_range` 對自己的意義（光束長度上限、連鎖彈跳的最大彈跳距離等），但欄位名稱保持一致。

**規則**：往後任何新 delivery，如果牽涉到「這個法術能做用到多遠」的概念，一律沿用 `max_range` 這個欄位解讀，不另開新欄位名稱。如果某種 delivery 真的沒有「距離」這個概念（理論上不太會發生，但保留彈性），`max_range` 可以忽略不用，不強制每種 delivery 都要處理它。

### 2.2 `duration`：為什麼放在 `SpellEffect` 身上，不是 `Spell` 身上

你提到有些法術是 buff/debuff，會有持續時間。這裡要先分辨一個容易混淆的點：**「有沒有 duration」是每個 effect 各自的屬性，不是整個法術共通的屬性**，原因是同一個法術的 `base_effects` 陣列裡，完全可能同時混著瞬發效果跟持續效果——例如一個法術「造成瞬間傷害，同時使目標減速3秒」，傷害是瞬發（`DamageEffect`，`apply_mode = INSTANT`），減速是持續性（`SlowEffect`，`apply_mode = DURATION`，`duration = 3.0`）。如果把 `duration` 放在 `Spell` 身上，就沒辦法表達「同一個法術裡，有些效果瞬發、有些效果持續」這種常見組合，所以 `duration` 跟著 `apply_mode` 一起放在 `SpellEffect` 基底上，由每個 effect 實例各自決定自己要不要用。

**真正的風險不是欄位放哪裡，是持續性效果的「運行時倒數狀態」要存在哪裡。** 這跟第1節畫的紅線是同一個問題：`SlowEffect` 這個 Resource 本身只能放「減速3秒、減速40%」這種固定設定值，**不能**在 Resource 身上存一個「這次還剩多少秒」的倒數計時器——否則多個目標同時被同一個法術的同一份 `SlowEffect` 資源命中時，会共享同一個倒數，命中時間不同的目標會互相干擾彼此的剩餘時間，這正是第1節講的 Resource 共享引用問題，只是換成了 duration 這個新場景再踩一次。

**正確做法**：持續性效果命中目標時，`SpellEffect.apply()` 不應該自己倒數計時，而是在被命中的角色身上**建立一個新的運行時物件**（例如一個 `ActiveStatusEffect` 的小物件或者乾脆是一個暫時的子節點），記錄「這個狀態還剩多少秒、每幀/每秒要做什麼」，計時器狀態存在這個運行時物件上，不是存在 `SlowEffect` 這個共享的 Resource 上。`SlowEffect` 資源只負責告訴系統「生成一個這樣設定的運行時狀態」，之後資源本身不再被動態修改。

這部分（角色身上要怎麼管理「目前身上有哪些持續性狀態」的清單、同種狀態疊加/覆蓋規則）屬於「狀態效果系統」的範疇，目前先在這裡點出設計方向與風險，不展開完整設計——等實際要做第一個 DURATION 類型的效果（例如減速或燃燒）時，再回來把這部分補完整。

---

## 3. 跟現有 PoC 程式碼的關係：這是演化，不是重寫

`Player.gd` 目前 `_fire_spell()` 裡的

```gdscript
damage += damage * float(r.get("damage_mult", 0.0))
pierce += int(r.get("pierce", 0))
speed_mult += float(r.get("speed_mult", 0.0))
```

這段邏輯本質上就是 `SpellEffect.apply()` 的雛形，只是現在用 Dictionary 字串鍵手寫，而不是用型別化的 class。`RUNE_COMBOS` 裡的 `damage_mult`/`pierce`/`speed_mult` 鍵名，之後可以直接對應成 `DamageEffect`/`PierceEffect`/`ProjectileSpeedEffect` 這幾個具體子類別。

`_spawn_projectile()` 現有的邏輯基本上就是 `ProjectileDelivery` 要做的事（算方向、`instantiate()` 投射物場景、設定速度）。

**遷移風險低，因為沒有要丟掉任何現有邏輯，只是把混在一起的程式碼拆成三個有清楚邊界的角色。**

**但 `max_range` 是一個新能力，現有 PoC 沒有**：`SpellProjectile.gd` 目前用 `LIFETIME`（固定3秒存活時間）讓投射物消失，這是「用時間模擬距離」的簡化做法，不是真的距離判定——如果中途改變飛行速度（例如符紋加了彈速），3秒內實際飛行距離也會跟著變，等於距離上限其實是浮動的，不是固定值。遷移到 `ProjectileDelivery` 時，應該改成真正累計飛行距離並跟 `max_range` 比較，到達距離上限才消失，不再用時間代替距離。這點記錄下來，避免遷移時以為只是換個檔案位置、照抄行為。

---

## 4. 這份文件刻意不處理的事

符紋在運行時要怎麼「生成」臨時的 `SpellEffect` 並動態塞進 `base_effects`，是符紋系統自己的設計範疇（之前說好分開討論）。這份文件只確保架構上留了乾淨的掛鉤點——`Array[SpellEffect]` 可以在吟唱結束時被追加——實際怎麼從按鍵序列生成對應的 effect 實例，留給下一份文件處理。

---

## 5. 誠實的代價與風險（這不是免費午餐）

1. **GDScript 沒有真正的 interface/abstract class 強制力。** `SpellDelivery`/`SpellEffect` 的「基底方法」只能靠約定或執行時 `has_method()` 檢查，忘記覆寫某個方法不會在編輯期被抓到，只會在執行期才爆炸或默默無效。這是 Godot/GDScript 的先天限制，不是設計疏漏，但要有心理準備，不能假設型別系統會幫你擋錯。
2. **這是「規模夠大才值回票價」的投資。** 如果這個遊戲最終只打算做10個法術，這套架構是過度工程，直接用 Dictionary 資料表加簡單判斷就夠。但依照最初設計構想（多職業、裝備掉落、符紋解放系統持續擴充），法術數量會隨開發期拉長持續增加，現在投資這個架構才合理——這是你自己說的「希望新增法術有很好的擴充性」的直接代價，不是我加碼的東西。
3. **新的 Delivery/Effect 種類仍然要寫程式碼。** 這套架構省的是「新增同類型法術的重複勞動」，不是讓你完全不用寫程式。你剛才的提醒是對的，這裡再次確認：**只有新類型（新發射機制/新效果種類）才碰程式碼，純數值變化不碰**。
4. **繼承深度的誘惑依然存在。** 做了兩三個 Delivery/Effect 後，很容易每個新法術都覺得「這個也有點特殊」，最後退化回每個法術一個子類別。必須畫一條硬規則並讓後續所有人（包括未來的你）遵守：**子類別只能對應「發射機制」或「效果種類」的本質差異，純數值不同絕對不開新子類別**。這條線一旦鬆動，架構就白做了。
5. **`.tres` 資源欄位一旦定型要謹慎改動。** `Spell`/`Delivery`/`Effect` 都是 Resource，之後如果幫某個子類別加/刪/改欄位名稱，所有已存在的、用舊欄位結構存的 `.tres` 檔案重新載入時可能丟值或跳警告，Godot 不會自動幫你搬資料。欄位設計要在動手大量產出法術資源檔之前先想清楚。

---

## 6. 建議的 v1 範圍（需要你拍板）

**先做（對應現有 PoC 能力的等價遷移，不新增任何新能力）：**
- `Spell`（基底）
- `SpellDelivery`（基底）＋ `ProjectileDelivery`（唯一具體實作）
- `SpellEffect`（基底）＋ `DamageEffect` / `PierceEffect` / `ProjectileSpeedEffect`
- 一個簡單的法術清單/選用機制（先用手動清單或資料夾掃描都行，不急著做法術圓盤 UI）

**先不做：**
- `BeamDelivery` / `AoEDelivery` / `ChainDelivery` 等其他發射方式
- 符紋動態生成 effect 並塞進 `base_effects` 的實際串接邏輯
- 法術切換圓盤 UI

---

## 7. 需要你決定的三件事（已拍板，見 §8）

1. 這個「Spell = 資料，Delivery/Effect = 少量可組合策略」的方向，你同意嗎？還是有想調整的地方？
2. 第6節的 v1 範圍（只做等價遷移，不新增能力）同意嗎？
3. 要現在就動手把 PoC 現有程式碼遷移過去，還是先維持現狀繼續驗證符紋手感，等確定要擴充法術數量時才動工？

---

## 8. 實作後補充（v1 落地時的具體決定）

v1 範圍已實作（對應 Demo 開發的 Phase 1）。以下記錄實作時做的具體決定，跟當初 §4「這份文件刻意不處理的事」有關，補回來避免後人以為那件事還完全沒碰：

### 8.1 `DamageEffect` 同時承載「基礎傷害」與「符紋百分比加成」

§4 原本把「符紋怎麼變成 SpellEffect」整個留給未來文件。實作時發現至少**這三個數值型效果**（傷害/穿透/彈速）沒有必要等到完整的符紋動態系統設計好才能處理，所以先解決了這一小塊：

- `DamageEffect` 有三個欄位：`min_amount`/`max_amount`（法術的基礎傷害區間，放在 `Spell.base_effects` 裡，每次施放時 `randf_range(min_amount, max_amount)` 抽一個值——參考 PoE 技能寶石「傷害顯示為區間、每次命中各自抽」的設計，見 8.6）、`damage_mult`（符紋的百分比加成，對抽到的值疊加固定百分比，由吟唱時打出的符紋動態 `new` 出來，不存在 `base_effects` 裡）。
- `apply(stats)`：`stats.damage += randf_range(min_amount, max_amount) + stats.damage * damage_mult`。百分比加成的語意保留 `DESIGN.md` 3.6 記錄的規則——符紋加成是「對目前已累加的傷害值疊加百分比」，不是對最終值相乘，疊加順序就是打出符紋的順序；隨機的只有基礎傷害那一捲，符紋百分比本身不是隨機值（同樣是 PoE 的規則：基礎傷害是區間，「+X% 增傷」類修飾符是固定百分比）。
- `PierceEffect(count)`／`ProjectileSpeedEffect(mult)` 沒有這個雙重身份問題，直接對應 `stats.pierce`／`stats.speed_mult` 累加。
- **符紋表 `RUNE_COMBOS` 本身完全沒動**，轉換成 `SpellEffect` 實例這一步是在 `Player.gd._rune_to_effects()` 做的，屬於「膠水邏輯」，不是正式的「符紋系統架構」——如果之後符紋池要變成大廳可配置（`DEMO_GOALS.md` §4），這一步會被取代，不代表符紋系統的完整設計已經在這裡解決了。

### 8.2 `ProjectileDelivery` 改用真實飛行距離判斷 `max_range`

照 §3 風險段落講的做法，`SpellProjectile.gd` 不再用 `LIFETIME`（固定3秒）模擬距離上限，改成每個 frame 累計實際飛行距離，達到 `max_range` 才消失。這代表彈速符紋（`speed_mult`）不會再讓投射物的有效飛行距離跟著變動——這不是新增玩法能力，是把本文件已經點名的「正確做法」補上。初版把 `max_range` 設成 1400，但 Arena 只有 1200×700（對角線約 1389），且 `SpellProjectile` 是 `Area2D` 不會被牆體擋住，實測等於「永遠飛出畫面外才消失」，玩家完全感受不到距離上限——已調整為 650（見 8.6），確保在場地內就能觀察到效果。

### 8.3 `SpellDelivery.fire()` 介面

`fire(caster: Node2D, direction: Vector2, stats: Dictionary, max_range: float) -> void`。`stats` 是呼叫端（目前是 `Player.gd`）先套用完 `base_effects` 跟符紋 effects 算好的最終數值（`damage`/`pierce`/`speed_mult`），`delivery` 只管怎麼發射、怎麼判定命中，不需要知道數值怎麼來的，符合 §1 的分工原則。

### 8.4 資源檔位置

`.tres` 法術資源放在新開的 `resources/spells/`（比照 `scripts/`/`scenes/` 的領域分類慣例），目前只有 `Fireball.tres` 一份，對應 PoC 原本唯一的投射物法術。右鍵瞬發沒有另外做一個 `Spell.tres`——它沿用裝備中法術的 `base_effects` 算出基礎傷害，再乘上 `Player.gd` 的 `INSTANT_CAST_DAMAGE_MULT`（0.8，沿用原本數值），呼叫同一個 `delivery.fire()`，沒有重複一套投射物生成邏輯。

### 8.5 還沒做的事（維持 §6「先不做」清單）

大廳配置、符紋池選配、`BeamDelivery`/`AoEDelivery`/`ChainDelivery`、buff 的 duration 機制，都還沒碰，跟 §6 說的一樣留給後續 phase。

### 8.6 v1 落地後第一輪回饋（三個修正）

v1 實作完、headless 驗證過之後，收到三點回饋，都已修正：

1. **`max_range` 在目前場地尺寸下感受不到效果**：如 8.2 所述，1400 幾乎等於 Arena 對角線長度，且投射物不會被牆擋，等於永遠飛出畫面外才消失。改成 `max_range = 650`（`Fireball.tres` 與 `Spell.gd` 的 `@export` 預設值都改了），在 1200×700 的場地內朝空地發射就能明顯看到投射物中途消失。
2. **穿透不該是 `ProjectileDelivery` 內建的欄位，應該是「命中後要幹嘛」這件事的其中一種變體**（第一輪改法把這點做錯了，這裡是修正後的版本）：
   - 新增 `ProjectileImpact`（Resource 基底），定義 `resolve(projectile, body) -> bool`——投射物命中東西、或飛行距離耗盡時呼叫（耗盡時 `body` 為 `null`），回傳是否該消失。
   - `SingleHitImpact`：命中第一個東西就扣血、消失，飛行到頭什麼都不做直接消失。最陽春的預設變體。
   - `PiercingImpact`：有 `pierce_count` 欄位，命中後扣血但不一定消失，次數用完才消失。剩餘次數存在 `projectile.impact_state`（投射物節點身上），不存在 `PiercingImpact` 這個 Resource 上——同一份 `.tres` 可能同時被好幾顆飛行中的投射物共用，運行時狀態不能放在共享的 Resource 上（跟 §1/§2.2 講的紅線是同一件事）。
   - `ExplosiveImpact`：命中東西「或」飛行到頭時都會爆炸，對爆炸點 `radius` 範圍內所有 `enemies` 群組（新加的，`TargetDummy.gd` 已加入）成員造成傷害，不穿透。**火球術現在用的是這個**，不是穿透。
   - `ProjectileDelivery` 新增 `@export var impact: ProjectileImpact` 欄位（取代第一輪加的 `base_pierce`，那個寫法已經移除），法術資料直接在 `.tres` 裡選一個變體塞進去。
   - 目前唯一還會動態疊加的是 `stats.pierce`（符紋 `DD`/`UULR` 產生的 `PierceEffect`），會原封不動傳進投射物的 `pierce_bonus` 欄位，但**只有用 `PiercingImpact` 的法術會讀這個值**——火球用 `ExplosiveImpact`，不消費 `pierce_bonus`，所以現在打 `DD` 符紋對火球術沒有額外效果。這不只是「之後想到再修」的小事，而是指向一個更根本的設計問題——見 §9，已經有規劃好的解法，只是刻意延後到大廳/符紋池 phase 才落地，不是忘記處理。
3. **傷害不該是寫死的單一數字**：見 8.1，`DamageEffect` 改成 `min_amount`/`max_amount` 區間，每次施放時抽一個基礎傷害值，`Fireball.tres` 設成 `8.0~12.0`（平均值維持原本的 10，不改動整體平衡，只是讓它變成區間）。符紋的百分比加成不受影響，一樣是固定 % 疊加在抽到的值上。

### 8.7 穿透整個機制移除（確認用不到，不是還沒做）

8.6 第2點做完、§9 的相容性設計也才剛寫完沒多久，遊戲範圍就定調為「純 PVE、一次只打一隻王」——穿透（打穿一個目標、命中後面還有目標）在這個範圍下完全沒有使用情境。所以沒有照 §9 的方向去「修正」穿透的相容性問題，而是直接把整條穿透路徑拿掉：

- 刪除 `PiercingImpact.gd`、`PierceEffect.gd`。
- `RUNE_COMBOS` 移除 `DD`（+穿透），`UULR` 移除 `pierce +2`（保留 `damage_mult +1.8`）。
- `stats` Dictionary 移除 `pierce` 鍵，`SpellProjectile.setup()` 移除 `pierce_bonus` 參數與欄位，`impact_state`（原本只給 `PiercingImpact` 存剩餘命中次數用）也一併移除——沒有任何東西在用了。
- `ProjectileImpact` 基底、`SingleHitImpact`、`ExplosiveImpact` 保留，這套「命中/飛行耗盡後要幹嘛」的變體架構本身是對的，只是穿透不會是其中一個變體了。

§9 的能力宣告（capability）設計仍然成立，只是範例裡的 `"projectile_pierce"`/`PierceEffect` 已經不存在。

### 8.8 彈速整個維度也移除，改成「固定時間內飛到最大距離」

拿掉穿透沒多久，又決定拿掉「彈速」這個維度——理由跟穿透不一樣：不是用不到，是**速度本來就不該是一個獨立數值**。改成「法術固定要在 `travel_time` 秒內飛完 `max_range`」，速度 = `max_range / travel_time`，是反推出來的結果，不是另一個可以單獨疊加的 stat。`max_range` 越大，飛行速度自然越快，這點直接對應玩家原本的直覺（有效距離越遠的法術，看起來飛得越快），不需要再靠符紋額外疊加「彈速」。

- `ProjectileDelivery` 新增 `@export var travel_time: float = 0.1`（`Fireball.tres` 設成 0.1，火球幾乎是瞬間飛到頭）。
- `SpellProjectile.setup()` 拿掉 `speed_mult` 參數，改用 `range_limit / travel_time` 算 `velocity`；拿掉 `BASE_SPEED` 常數（不再需要「基礎速度乘上倍率」這個模型）。
- 刪除 `ProjectileSpeedEffect.gd`；`RUNE_COMBOS` 移除 `LR`/`RL`（+彈速）；`stats` Dictionary 不再有 `speed_mult` 鍵，現在只剩 `damage`。
- 投射物的「高速=綠」顏色提示也拿掉了，因為速度不再是玩家能透過符紋影響的東西，不需要視覺回饋去標示「這次比較快」。
- 符紋現在只剩「傷害」這一個可疊加的維度（`UU`/`UDU`/`UULR`）。§9 的能力宣告設計要再簡化一次：`ProjectileDelivery` 不再自帶 `"projectile_speed"` 能力（因為沒有任何效果會去讀它），真正會用到的能力集合目前只剩 `"area_radius"`（`ExplosiveImpact` 專屬）。

### 8.9 新增 `RR`/`LL`：第一個不經過 `stats`／發射數值的符紋類別

新增 `RR`（+吟唱速度）跟 `LL`（-吟唱速度），對應 `>>`/`<<` 的直覺（右右＝加速、左左＝減速）。跟 `UU`/`UDU`/`UULR` 不一樣的地方：這兩個符紋**不會**進到 `_fire_spell()` 的 `stats` 累加流程，而是在 `_commit_combo()` 當下直接修改 `Player.gd:cast_speed_bonus`，立即影響 `_process_casting()` 裡的讀條消耗速度——打完馬上看到讀條變快/變慢，不是等吟唱結束才生效。

**數值公式比照 ARPG 常見的「增減速％」慣例，不是線性砍時長**：`cast_speed_bonus` 是調整值的總和（0.0＝正常），實際吟唱時長 ＝ `base_cast_time / (1 + cast_speed_bonus)`——`cast_speed_bonus = 1.0`（+100%）時長就會變成一半，已經用 headless 腳本實測驗證過（2 秒的吟唱在 `cast_speed_bonus=1.0` 時剛好 1 秒讀完）。因為要逐 frame 消耗 `cast_timer`，程式碼寫成 `cast_timer -= delta * (1 + cast_speed_bonus)`（消耗速率，跟「時長」互為倒數，數學上是同一件事）。`cast_speed_bonus` 下限 clamp 在 -0.9，不是對最終倍率隨意設一個下限——線性直接砍一個「倍率」變數容易在疊加多個減速效果時讓倍率變成 0 或負數，倒數公式本身就有自然的漸退特性，clamp 只是為了避免 `(1+cast_speed_bonus)` 真的碰到 0。細節見 `docs/DESIGN.md` §3.6。

這代表符紋系統裡其實有兩條完全不同的套用路徑：
1. **影響發射數值**（傷害、之後的範圍半徑...）：吟唱結束時才統一套用，走 `stats` Dictionary，這條路徑才是 §9 capability 設計要管的範圍。
2. **影響吟唱過程本身**（讀條速度，之後可能還有「吟唱中斷判定」之類）：觸發當下立即生效，不經過 `stats`，`required_capability` 這套機制對這類符紋沒有意義（沒有 delivery/impact 需要讀取它們）。

§9 落地時如果要幫符紋池做相容性過濾，需要先分清楚符紋屬於哪一類——`RR`/`LL` 這類「即時生效」的符紋理論上對任何法術都通用（任何法術都有吟唱讀條），不需要 capability 檢查；只有第1類才需要。

### 8.10 新增兩把法術：`ForceWave`、`LightningBolt`，架構撑開到第二種 delivery

v1 到現在只有一把法術驗證過（火球），這次新增兩把，把架構沒驗證過的部分真正跑起來：

- **`SelfDelivery`（`scripts/spells/SelfDelivery.gd`，新落地 §2.2 原始提案）**：以施法者為中心，對 `radius` 範圍內的 `"enemies"` 群組成員造成 `stats.damage` 並呼叫 `target.apply_knockback(...)`。跟 `ProjectileDelivery` 不一樣的地方：沒有飛行階段，命中判定跟傷害/擊退直接在 `fire()` 裡一次做完，不需要 `ProjectileImpact` 這層（那是給「有命中事件」的 delivery 用的，`SelfDelivery` 的命中是即時全部判定完，沒有「之後會不會命中」這個問題）。重用了 `ExplosiveImpact` 已經在用的 `MagicFX.spawn_burst()`／`spawn_explosion_ring()`，沒有新寫一套特效。`ForceWave.tres` 用這個 delivery，`radius=140`、`knockback_force=500`。
- **擊退（`TargetDummy.gd:apply_knockback()`）**：新增一個獨立於 AI 狀態機的位移層（`knockback_velocity`，`_process()` 裡在 `_process_ai(delta)` 之後疊加、用摩擦力衰減、clamp 在場地範圍內），不碰 AI 邏輯本身。這是目前唯一會主動移動 `TargetDummy` 位置的機制，除了 AI 自己的跳躍動畫。
- **`PiercingImpact` 重新加回來（語意跟之前刪掉的不一樣）**：之前刪掉的版本是「符紋疊加的有限次數穿透」（§8.7），這次是「法術天生的無限穿透」——`LightningBolt` 用這個，命中什麼都不會消失，只有飛行距離耗盡（`body == null`）才真正結束。不要把這兩個搞混：如果之後真的要做「符紋疊加穿透次數」，那是另一個獨立的設計問題，不是把這個 `PiercingImpact` 改回有次數限制。
- **牆壁反彈（`ProjectileDelivery.bounces_off_walls` + `SpellProjectile._bounce_off_arena_bounds()`）**：故意**不**用物理碰撞做——`SpellProjectile` 的 `collision_mask` 從一開始就沒有偵測牆壁所在的 layer（確認過，牆壁 layer 4／`SpellProjectile` mask 只認 layer 3），這是為了不影響 Fireball 現有的「直接飛出場地外才消失」手感。改成直接比較 `position` 跟 `Arena.ARENA_WIDTH`/`ARENA_HEIGHT`（新增 `class_name Arena` 讓這兩個常數能全域存取），超出範圍就 clamp 位置、反轉對應軸向的 `velocity`。只有 `bounces_off_walls=true` 的 delivery（目前只有 `LightningBolt`）會觸發這段，其他法術完全不受影響。`distance_traveled` 的累計方式不受反彈影響（撞牆改變方向不會讓它提前或延後消失，純粹看總飛行路徑長度）。
- **暫時性的裝備切換（`Player.gd:_input()`，已被 §8.11 的正式輪盤取代）**：原本還沒有大廳/裝備系統，先用數字鍵 1/2/3 直接切換 `equipped_spell` 方便測試。這段程式碼已經整個刪除，不是保留著——§8.11 的 Ctrl 輪盤就是當時說好要取代它的正式機制，等真正的大廳裝備系統（`DEMO_GOALS.md` §2.5/§7.2）上線後，輪盤本身會留著（它是戰鬥中切換「目前使用中法術」的機制），但輪盤顯示的清單來源會從 `equipped_spells` 固定陣列換成大廳配置的結果。

**§9 的影響**：現在確定有法術種類變多的壓力了（3把法術，2種 delivery），§9 提的「符紋有沒有用完全是意外」這個問題不再是假設性的——`ForceWave` 用 `SelfDelivery`，完全沒有 `ProjectileDelivery` 相關的任何概念，如果之後有人幫火球加了彈速/穿透符紋，套用到 ForceWave 身上也不會出錯，只是安靜地沒有效果，跟 §9.1 描述的問題一模一樣。`SelfDelivery.get_capabilities()` 如果要補上，應該回傳 `[]`（它沒有 `ProjectileDelivery` 那條「會飛」的概念，`radius`/`knockback_force` 目前都是固定配置，不是符紋能疊加的 stat）。

### 8.11 法術切換輪盤（`DEMO_GOALS.md` §3、§7.4 落地）

數字鍵切換（§8.10）被整個取代，改成正式的 Ctrl 輪盤。架構上這跟「法術本身」的設計關係不大，純粹是 UI/輸入層，但記錄在這裡方便跟 `equipped_spells` 的概念對照：

- `Player.gd` 新增 `equipped_spells: Array[Spell]`（固定 3 把）跟 `equipped_spell`（目前使用中的，輪盤選的就是從這份清單裡挑一個指派過去）。選取判定（角度計算、開關狀態機、`Engine.time_scale` 控制）都在 `Player.gd`，因為它本來就是唯一同時持有「輸入狀態」跟「法術裝備狀態」的地方。
- `scripts/ui/SpellWheel.gd` 刻意只管畫面：給它看什麼就畫什麼（`open()`/`update_hover()`/`close()`），不自己判斷滑鼠角度、不自己讀 `Input`。這跟 `Spell`/`Delivery`/`Effect` 的分工哲學是同一個原則的延伸——判定邏輯跟呈現邏輯分開，之後要幫輪盤換美術（圖示貼圖取代 `_draw()` 畫的圓圈文字，見 `ROADMAP.md` 美術遷移計畫）只需要改 `SpellWheel.gd`，不會動到 `Player.gd` 的選取邏輯。
- 角度公式 `fposmod(offset.angle() + PI/2.0, TAU)` 再除以每格角度、四捨五入取 index，`SpellWheel.gd` 畫圖用完全對稱的 `-PI/2 + slice*i` 算每格位置——兩邊手動對齊，用 headless 腳本把「畫在哪個角度」反推回「會選到哪個 index」逐格驗證過，三格都對得上。這是這次唯一有機會做錯又不會噴錯誤訊息的地方（角度基準不一致只會表現成「滑鼠移到看起來對的格子卻選到別的」，headless 驗證能抓到這種邏輯錯誤，純粹靠人眼看畫面反而不容易發現）。
- Ctrl 偵測刻意不走 `project.godot` 的 Input Map——手刻 `InputEventKey` 的 `physical_keycode` 數值風險跟手寫 `.tres` 的 `Array[Resource]` 語法類似，但更糟的是**寫錯了 Godot 不會報錯，只是永遠不觸發**，headless 驗證完全抓不到這種錯誤。直接在程式碼用 `Input.is_key_pressed(KEY_CTRL)` 符號常數，風險低很多。
- 開輪盤時如果正在吟唱，直接取消吟唱（不是暫停吟唱等輪盤關閉後繼續）——跟 `DEMO_GOALS.md` §3「不會同時吟唱」的描述一致，也避免「輪盤開著、吟唱計時器在背景用子彈時間的 `delta` 偷跑」這種容易忽略的邊界情況。

### 8.12 兩個小修正：輪盤改成真正的圓盤分割、投射物加 `fixed_speed`

- **輪盤視覺**：§8.11 第一版畫的是「3 個小圓圈繞著中心排列」，使用者要的是「真的一個圓盤，三分之一切分」。改成 `SpellWheel.gd:_draw()` 用 `_draw_pie_slice()` 畫實心扇形（手動建構 `center + 弧線上多個點` 的 polygon，`draw_colored_polygon` 填色——Godot 沒有內建的「畫扇形」函式），外層加一個完整圓的描邊讓它看起來真的是一個盤子。**選取判定（角度公式）完全沒變**，因為每一格原本就是以「格中心角度」為基準做最近鄰判定，扇形的角度範圍本來就跟判定邊界一致，只是畫法從「一個點」變成「一片扇形」。
- **`ProjectileDelivery.fixed_speed`**：雷電箭的 `max_range` 設到 1800（配合反彈，故意飛很久），如果繼續用 `travel_time` 反推速度（§8.8 的模型），`1800/0.1=18000 px/s`，快到幾乎看不見。`travel_time` 模型的前提是「法術要在固定時間內抵達終點」，這個假設只適合「飛向一個目標並命中/到頭」的直線法術，雷電箭會反彈、`max_range` 只是「總路徑長度上限」不是「终點距離」，兩者語意已經不一樣，所以不是調數值能解決的，是模型本身不適用。新增 `fixed_speed`（>0 時優先於 `travel_time`）讓法術可以選擇「固定飛行速度」而不是「固定抵達時間」，雷電箭設成 700。火球術當時還在用 `ProjectileDelivery` 時沒受影響（`fixed_speed=0`，照舊用 `travel_time` 反推），不過火球後來整個換了 delivery，見 §8.13。

### 8.13 火球術改成 `AoETargetingDelivery`：鎖定選點的範圍法術，不再是投射物

使用者想法改變：火球不該飛，應該是「鎖定然後決定位置」的範圍法術——對應 `DEMO_GOALS.md` §2.2 原本就提案過、v1 沒做的 `AoETargetingDelivery`。這次正式落地：

- **`fire()` 第一次變成非同步**：之前所有 delivery 的 `fire()` 都是同步、呼叫完立刻結束。`AoETargetingDelivery.fire()` 要「暫停遊戲 → 顯示選點介面 → 等玩家確認/取消 → 恢復 → 套用效果」，中間跨好幾個 frame，用 GDScript 的 `await` 等一個自訂訊號（`AoETargetingReticle.finished`）。`Player._fire_spell()` 呼叫這個 `fire()` 時沒有 `await`——函式跑到第一個 `await` 就把控制權還給呼叫端，`cast_ended.emit()` 照常立刻觸發、吟唱條照常消失。暫停/選點是接在吟唱結束後面的**獨立步驟**，不是吟唱本身的一部分，這點很重要：之後如果要查「為什麼吟唱條消失了但畫面還沒動」，答案就在這裡，不是 bug。
- **真正的暫停，不是輪盤的子彈時間**：`DEMO_GOALS.md` §3 最後一句明確提醒這是兩種不同機制——輪盤用 `Engine.time_scale`（一切照常運作只是變慢），這次用 `get_tree().paused = true`（怪物、投射物全部凍結）。負責畫選點介面/讀取滑鼠/處理確認鍵的 `AoETargetingReticle.gd` 在 `_ready()` 把自己的 `process_mode` 設成 `PROCESS_MODE_ALWAYS`，才能在暫停時繼續運作——這是 Godot 暫停機制的標準用法，忘記設這個的話，暫停之後選點介面本身也會跟著凍結，玩家會卡住。
- **右鍵瞬發原本用 `instant` 參數跳過暫停選點，這是設計錯誤，已經在 §8.14 整個拿掉**：瞬發跳過的應該只是吟唱/符紋累積那段，delivery 自己的解算流程（包含該不該暫停）不該被瞬發影響，細節見 §8.14，這裡只留一句指過去，避免看到舊版說法誤以為還是這樣設計。
- **傷害判定重用 `ExplosiveImpact` 已驗證過的模式**：`AoETargetingDelivery._resolve()` 跟 `ExplosiveImpact.resolve()` 的核心邏輯幾乎一樣（`enemies` 群組 + 距離比較 + `MagicFX` 特效），沒有重新發明。**`ExplosiveImpact.gd` 本身保留，沒有刪**——它是「投射物命中/飛行到頭時爆炸」的變體，跟「玩家主動選點放置範圍法術」是兩個不同的概念（一個是被動結果，一個是主動輸入），只是火球不再用它。目前沒有任何法術在用 `ExplosiveImpact`，跟 `SingleHitImpact` 一樣是「架構上存在、暫時沒人用」的狀態，不代表沒用、該刪。
- **`max_range` 的語意再一次印證 `SPELL_SYSTEM.md` §2.1 當初的設計**：`AoETargetingDelivery` 把 `max_range` 詮釋成「鎖定距離上限」，跟 `ProjectileDelivery` 詮釋成「飛行距離上限」是同一個欄位、不同 delivery 各自解讀——當初設計 `Spell.max_range` 時就是為了讓被動效果（之後的「+施放距離」裝備）不用管底下是哪種 delivery，這次是這個設計第一次真正被兩種不同語意的 delivery 用到。
- **鏡頭沒有額外處理**：`DEMO_GOALS.md` §3 提到選點時要「切換到可視範圍更大的選點視角」，但目前 Arena（1200×700）在現有 `Camera2D.zoom=1.0` 下本來就整個可見，這段需求等於已經被滿足，沒有另外寫鏡頭縮放邏輯。等場地變大、或鏡頭開始跟隨玩家捲動（目前鏡頭是 `Player` 的子節點，玩家不太移動時幾乎不會捲動）時，才需要真的處理這段。

### 8.14 修正：右鍵瞬發不該跳過暫停選點，`instant` 參數整個拿掉

§8.13 第一版把「右鍵瞬發」理解成「這個 delivery 呼叫不能暫停、不能等玩家輸入」，所以加了 `instant` 參數讓 `AoETargetingDelivery` 在瞬發時跳過暫停、直接在滑鼠當前位置解算。**這是對「瞬發」的誤解，使用者糾正了**：瞬發省略的是**吟唱/符紋累積那個階段**（不用打方向鍵組合、不用等讀條），不是「這把法術本身該有的運作方式」。如果一把法術本來就是「鎖定選點再發動」，瞬發也一樣要鎖定選點，只是不用先吟唱、傷害用固定倍率（`INSTANT_CAST_DAMAGE_MULT`）而不是疊符紋——這兩件事（怎麼觸發 vs 怎麼解算）是獨立的，不該混在一起判斷。

修正後：
- `AoETargetingDelivery.fire()` 不再分 `instant` 兩條路，永遠暫停遊戲、顯示選點介面、等玩家確認——右鍵瞬發火球現在也會真的暫停等你點位置，跟正常吟唱完全同一套流程，差別只在傷害數值跟少了符紋。
- `instant` 參數從 `SpellDelivery.fire()` 的共用介面整個拿掉（`ProjectileDelivery`/`SelfDelivery` 本來就不理會它，`AoETargetingDelivery` 現在也不需要了），`Player._fire_instant_spell()` 呼叫 `delivery.fire()` 時不再多傳一個 `true`——跟 `_fire_spell()`（正常吟唱流程）呼叫的參數完全一樣，兩者唯一的差異在呼叫前算 `stats` 的方式（瞬發用固定倍率、正常流程疊符紋效果），不是 delivery 怎麼解算。
- `_clamp_point()`（原本給瞬發路徑用來把滑鼠位置 clamp 進 `max_range` 的 helper）也一併刪除——`AoETargetingReticle` 自己在 `_process()` 裡已經會做範圍 clamp（超出範圍鎖在邊界、變灰），不需要在 `AoETargetingDelivery` 裡重複一份。
- 用 headless 腳本驗證過：呼叫 `player._fire_instant_spell()` 後 `get_tree().paused` 立刻變成 `true`、選點介面 `active=true`，模擬確認後傷害正常套用、暫停正確恢復——瞬發火球現在跟正常吟唱走的是同一條暫停選點路徑。

---

## 9. 符紋與法術能力的相容性設計（規劃中，刻意尚未實作）

### 9.1 問題：法術可能同時具備多種性質，現有符紋系統無法正確表達

火球術的 `impact` 是 `ExplosiveImpact`（命中/到達距離上限時爆炸，有爆炸半徑這個維度），理應能吃到「影響範圍」的符紋（例如爆炸半徑），但現在完全吃不到，因為 `RUNE_COMBOS` 跟 `Player.gd:_rune_to_effects()` 只認識 `damage_mult` 一把寫死的鑰匙，`stats` Dictionary 也只有 `damage` 這個鍵，沒有「爆炸半徑」這個維度可以疊加。

更根本的問題：一個符紋「有沒有用」目前完全取決於剛好有沒有東西去讀 `stats` 裡對應的那把鑰匙，是意外，不是設計——這在只有一個法術時不構成問題，但之後法術種類變多（Beam／AoE選點／buff），每多一種 delivery/impact 組合就要回頭改 `_rune_to_effects()` 加新的 if 分支，而且沒有任何機制能說明「這個符紋對這把法術到底有沒有用」，玩家也無從得知。（穿透、彈速都曾經是這個問題的具體例子——`PierceEffect`/`ProjectileSpeedEffect` 會套用到任何法術，但只有特定 impact 才會讀它們——後來發現兩個都用不到／不該是獨立數值就直接刪了，見 §8.7、§8.8，不代表這個根本問題消失了，只是少了例子。）

### 9.2 提案：能力宣告（capability）機制，比照 PoE 技能寶石的 tag 相容性

參考 PoE 輔助寶石的設計——輔助寶石只對有對應 tag 的主動技能生效（例如「集中效應」只對 Area tag 的技能生效），把同一套概念套在 `Spell`/`Delivery`/`Impact`/`SpellEffect` 上：

- `SpellDelivery`／`ProjectileImpact` 各自加一個 `get_capabilities() -> Array[String]`：
  - `ProjectileDelivery` 本身不帶任何能力（飛行速度已經不是可疊加的 stat，見 §8.8），完全由自己 `impact` 回報的能力決定。
  - `SingleHitImpact.get_capabilities()` → `[]`（不補充任何額外能力）。
  - `ExplosiveImpact.get_capabilities()` → `["area_radius"]`。
  - `Spell.get_capabilities()` = `delivery.get_capabilities()`（組合起來的結果）。以火球為例，最終能力集合是 `{"area_radius"}`。
- `SpellEffect` 加一個 `required_capability: String`（預設空字串＝通用，任何法術都吃得到）：
  - `DamageEffect.required_capability = ""`（傷害是通用的）。
  - 新增一個 `AoERadiusEffect`（`mult` 欄位，疊加進 `stats.aoe_radius_mult`），`required_capability = "area_radius"`，給 `ExplosiveImpact.resolve()` 在算實際爆炸半徑時乘上去（`radius * (1.0 + stats.aoe_radius_mult)`）。
- 套用符紋效果的迴圈（目前在 `Player.gd:_fire_spell`）改成：`if effect.required_capability == "" or effect.required_capability in equipped_spell.get_capabilities(): effect.apply(stats)`，否則跳過。跳過不等於失敗，應該給玩家一個不同於「符紋失敗」的視覺回饋（例如符紋圖示變灰／顯示「對目前法術無效」），不要讓玩家誤以為自己打錯鍵。

### 9.3 為什麼現在不做，留到哪個 phase

目前只有一把法術（`Fireball.tres`），一種 delivery、三種 impact 變體裡只有一種真的被用到，capability 機制現在做下去沒有實際測試壓力，很容易為了「看起來完整」而過度設計。真正需要這套機制的時機是 `DEMO_GOALS.md` §4 做大廳符紋池配置的時候——那時候玩家會為每個裝備法術各自選配符紋，大廳 UI 本來就需要知道「這把法術能吃哪些符紋」才能正確地把不相容的符紋從可選清單裡濾掉，`get_capabilities()`／`required_capability` 這套機制到時候是直接拿來用的，不是重做。

**落地時需要一起做的事**：
1. 上述 `get_capabilities()`／`required_capability` 兩邊的宣告。
2. `_fire_spell` 的套用迴圈加相容性檢查。
3. 新增 `AoERadiusEffect`，並在符紋池/組合表裡至少安排一個會產生它的符紋，讓火球真的能吃到「影響範圍」的符紋，驗證這個設計真的有解決問題，不是紙上談兵。
4. 符紋不相容時的 UI 回饋（跟「符紋失敗」要做出視覺區別）。
5. 大廳的符紋池清單用 `spell.get_capabilities()` 做可選符紋的過濾。
