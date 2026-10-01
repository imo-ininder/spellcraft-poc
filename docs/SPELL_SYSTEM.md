# 法術系統架構提案（PoC 之後）

> 範圍聲明：這份文件**只討論法術本身的架構**（定義、發射、效果套用），不涉及符紋系統怎麼生成/疊加強化效果——那是下一份要單獨討論的文件，這裡只確保法術架構留了一個乾淨的掛鉤點給符紋用。

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

## 7. 需要你決定的三件事

1. 這個「Spell = 資料，Delivery/Effect = 少量可組合策略」的方向，你同意嗎？還是有想調整的地方？
2. 第6節的 v1 範圍（只做等價遷移，不新增能力）同意嗎？
3. 要現在就動手把 PoC 現有程式碼遷移過去，還是先維持現狀繼續驗證符紋手感，等確定要擴充法術數量時才動工？
