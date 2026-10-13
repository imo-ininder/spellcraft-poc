# Demo Plan — 符文法術圖譜 Prototype

> **這份文件取代 `docs/DEMO_GOALS.md`**，是目前專案實際要照著做、照著追蹤進度的開發計畫。`docs/GDD.md` 是抽象的整體方向，`docs/FIRE_PROTOTYPE.md` 是使用者給的具體原型規格（符文語意、法術圖譜、每個節點的設計意圖），這份文件把 Fire Prototype §13 的 Phase 切法對應到**這個專案實際的檔案/系統**，每個 phase 補上驗收標準、明確排除範圍，以及目前進度。三份文件分工：GDD＝為什麼，Fire Prototype＝做什麼，這份＝怎麼做、做到哪了。

---

## 0. 目前進度

| Phase | 內容 | 狀態 |
|---|---|---|
| 0 | 舊系統清理（場景/法術/超魔） | ✅ 完成（2026-10-13） |
| 1 | 核心操作骨架（移動/近戰三連段/蓄力火球/專注進出殼） | ✅ 完成（2026-10-13） |
| 2 | 符文輸入系統 + 法術圖譜資料結構 + 基本 UI | ✅ 完成（2026-10-13） |
| 3 | 火系法術：4 個核心節點 | ✅ 完成（2026-10-13） |
| 4 | 專注值資源 + 子彈時間數值化 | ✅ 完成（2026-10-13） |
| 5 | 測試敵人升級 | ⬜ 未開始 |
| 6 | 補完剩餘圖譜節點 | ✅ 完成（2026-10-13，使用者要求先做完全部法術效果再做 Phase 5，順序對調） |

---

## 1. 這次 Demo 要驗證的問題

直接繼承 `docs/FIRE_PROTOTYPE.md` §1／§11：玩家能否直覺地用符文改變法術、不同節點是否帶來真正不同的戰術選擇、右鍵專注+左鍵施放的操作是否自然、專注值的資源取捨是否有意義、玩家會不會依敵人行為選擇不同演化路徑。**驗證重點是手感跟機制成不成立，不是數值平衡或內容量**，每個 phase 的數值全部是佔位值，比照 `CLAUDE.md`「超魔專長/法術數值目前仍是 Demo 階段的示範值」的既有慣例。

## 2. 範圍邊界

直接繼承 `docs/FIRE_PROTOTYPE.md` §12：這次只做火元素，冰/雷/混沌等其他元素不在範圍內；9 種符文只用其中 4 種（上上/下下/左左/右右，見 Fire Prototype §4.1）；沒有裝備/掉落/Build/養成系統；沒有多個 Boss/大型關卡；沒有故事/任務系統。

## 3. 現況基礎（Phase 0 完成後，Phase 1 開工前讀這段）

- **唯一場景**：`scenes/SpellTestRange.tscn`（也是 `project.godot` 的 `run/main_scene`），裡面有 `Floor`（同心圓參考線）、`TestDummy`（純吃傷害的靶子）、`Player`、`UI/CastBar`+F3 除錯面板骨架。
- **`Player.gd` 現況**：HP/死亡、移動、Dash、knockback、8方向 sprite 動畫切換（`PlayerSpriteAnimator`）全部正常運作，不受這次轉型影響。吟唱相關欄位（`is_casting`/`combo_buffer`/`pending_combo`/`_handle_combo_key()` 的前綴比對邏輯）保留著骨架，但 `equipped_spell` 恆為 `null`，左鍵/右鍵目前什麼都不會發生——Phase 1 開始要拆掉/取代這部分，不是繼續沿用舊的「固定讀條吟唱」語意（那是舊系統，符文現在不是拿來疊修飾符，是拿來切換法術節點，見 `docs/GDD.md` 文末附註）。
- **保留可用的技術架構**（`docs/GDD.md` 文末附註已列過，這裡重申對這次 Demo 的意義）：`Spell`/`SpellDelivery`/`SpellEffect`/`ProjectileImpact` 三層分離架構（`scripts/spells/`）直接拿來實作圖譜節點的具體行為；`GroundProjection`/`MagicFX` 等視覺工具；`AoETargetingReticle`/`AoETargetingTrail`/`CastPreview`/`CastBar`——這些都還在，但這次 7 個火系節點目前的設計都不需要「暫停點選」這種互動（都是直接朝滑鼠方向施放），**預期這次 Demo 用不到它們**，先不刪，之後如果真的確定用不到再清。

## 4. 資料結構設計：法術圖譜（Phase 2 開始需要，先在這裡定義一次）

兩個新的 Resource 類別，放 `scripts/spells/`，跟 `Spell.gd` 同一層：

- **`SpellGraphNode`**：`id: String`、`spell: Spell`（直接複用既有 `Spell.gd`，`delivery`/`base_effects`/`max_range` 照舊，`cast_time`/`slot_cost` 這兩個舊系統專用欄位這次不用管）、`transitions: Dictionary[String, String]`（符文 id → 下一個節點的 id，查不到代表沒有合法轉換）。
- **`SpellGraph`**：`start_node_id: String`、`nodes: Array[SpellGraphNode]`，一個 `get_node_by_id(id) -> SpellGraphNode` 的查詢方法。

### 4.1 符文輸入判定：直接複用舊的前綴比對演算法

`Player.gd` 保留的 `_handle_combo_key()` 骨架（`docs/DESIGN.md` 原本記錄過這套邏輯，該文件已刪除，完整判定表搬來這裡）就是符文輸入要用的演算法，只是查表對象要換——舊系統查全域的 `GameState.ARCANE_FEATS`，新系統要查**目前節點的 `transitions`**。核心概念：支援短序列與長序列共享前綴（例如符文表裡 `UU` 是完整符文，但如果之後某個節點同時有 `UU` 跟 `UURDL` 兩條路徑，玩家能在輸入過程中自然決定要不要賭更長的）。每次新按鍵組成 `attempt = combo_buffer + key` 後分四種情況：

| 情況 | 判定 | 行為 |
|---|---|---|
| `attempt` 是完整符文，且不是任何更長符文的前綴 | 單純完整命中 | 立即查 `transitions[attempt]`，查到就換節點；清空緩衝 |
| `attempt` 是完整符文，同時也是更長符文的前綴 | 曖昧狀態 | 存成 `pending_combo`，不立即觸發，繼續等待下一鍵 |
| `attempt` 不是完整符文，但是某個更長符文的前綴 | 半成品 | 更新 `combo_buffer = attempt`，清空 `pending_combo`，繼續等待 |
| `attempt` 既非完整符文，也不是任何前綴 | 無效延伸 | 輸入失敗：清空緩衝，失敗回饋 |

每個 frame 檢查「距離上次按鍵過了多久」：有 `pending_combo` 且等待超過 `COMBO_MAX_GAP`（舊系統是 0.15 秒，這個數值是佔位值，符文手感可能需要重新調校，不要假設還適用）→ 確認觸發 pending 符文；沒有 `pending_combo`、只是半成品前綴，等待超過 `COMBO_MAX_GAP` → 判定失敗。

這次用得到的 4 種符文（`UU`/`DD`/`LL`/`RR`）彼此之間沒有前綴重疊問題（見 `docs/FIRE_PROTOTYPE.md` §4.1，都是 2 鍵、字母不同），Phase 2 不會真的用到「曖昧狀態」那一格，但保留完整判定表是因為之後可能會用到 `R9`（`上右下左`，4 鍵序列，跟 `R1`/`R2` 等 2 鍵符文有前綴關係），到時候不用重新設計判定邏輯。

`resources/spells/fire/` 底下建 `fire_graph.tres`（`SpellGraph`）+ 每個節點一個獨立 `.tres`（`SpellGraphNode`），方便在 Inspector 裡個別調整。9 種符文裡這次只用得到的 4 種（`UU`/`DD`/`LL`/`RR`）在 `Player.gd` 用一個固定常數表標成 `R1`/`R4`/`R3`/`R2`（對應 Fire Prototype §4.1 的語意：提升強化/穩定/自身後退/前進），符文輸入判定複用既有 `_handle_combo_key()` 的前綴比對骨架（見 §3 現況說明），只是查表對象從舊的 `GameState.ARCANE_FEATS` 換成「目前節點的 `transitions`」。

## 5. Phase 1 — 核心操作骨架

**目標**：玩家能動、能打、能進出專注模式（先是「殼」，時間會變慢，但符文/法術圖譜還不存在）。對應 Fire Prototype §13 Phase1 + §3 Controls + §8 Basic Combat。

**新增/修改**：
- `Player.gd` 新增近戰三連段：`combo_stage`（0→1→2→0 循環）、`MELEE_RANGE`/`MELEE_HALF_ANGLE`（距離+朝向夾角判定，複用舊 boss 吸引懲罰用過的「不靠物理形狀、純數值距離+角度」手法，對 `enemies` group 成員判定）、`MELEE_DAMAGE`/`MELEE_COOLDOWN` 佔位值。
- 蓄力火球：`cast_spell` action 的 tap（快按快放）判成近戰一下，hold 超過門檻（`CHARGE_THRESHOLD` 佔位值）再放開才發射火球——先直接用 `SpellProjectile.tscn`+`ProjectileDelivery` 兜一顆最簡單的投射物即可，不用等 Phase 2 的圖譜資料結構。
- 專注模式進出：`instant_cast` action（原本是右鍵瞬發，這次改語意）`just_pressed` 切換 `is_focused`，`Engine.time_scale` 跟著變（沿用舊輪盤用過的 `0.25`）。這個 phase 先不用真的能切換/施放法術節點，重點是「能不能順暢進出、時間縮放手感如何」。

**驗收標準**：
- 左鍵快點對 TestDummy 造成傷害，可以看到三段循環（即使三段數值一樣也沒關係，這個 phase 不要求演出差異）。
- 左鍵長按超過門檻放開會發射一顆火球，命中 TestDummy 有傷害。
- 右鍵進入專注：畫面/敵人動作明顯變慢；再按一次右鍵退出，恢復正常速度。
- 專注狀態下 WASD 不應該移動角色（先確認「輸入被攔截」這個行為成立，即使這個 phase 還不處理符文語意）。

**明確不做**：符文輸入判定、法術圖譜資料結構、專注值數值化（這個 phase 的「專注」只是時間縮放開關，不扣任何資源，之後 Phase 4 才補資源限制）、近戰三段的差異化演出。

**實作記錄（2026-10-13，✅ 完成）**：規劃之外、實作時發現必須一併處理的連動——`cast_spell`（左鍵）的新語意（一般狀態＝近戰/蓄力，專注狀態＝未來的符文施放）跟舊的「按住固定時長吟唱」系統完全衝突，`is_casting`/`cast_timer`/`cast_speed_bonus`/`_start_casting()`/`_cancel_casting()`/`_finish_casting()`/`_fire_spell()`/`_fire_instant_spell()` 連同 `cast_started`/`cast_progress`/`cast_ended` 訊號整組移除（新系統不管哪個狀態都沒有「按住累積一段固定時間」這個概念，Phase 2 的符文施放也是按下就立即觸發，不是channel）。連動影響兩個「功能類保留」的檔案：
- `scripts/core/CastPreview.gd`：`_draw()` 依賴 `player.is_casting`/`player.accumulated_feats`/`player.debug_preview_scaled_spell()`，三個都被刪除的對象——整個 `_draw()` 改成直接 `return`（停用，不刪檔案），等之後有「目前鎖定節點」這種可預覽的狀態再重新設計。
- `scripts/ui/CastBar.gd`：顯示的是「吟唱進度」，新系統沒有這個概念（瞬間判定/瞬間施放都沒有進度可顯示）——`scripts/SpellTestRange.gd` 拔掉 `cast_bar.bind(player)` 這一行，`CastBar.gd`/`CastBar.tscn` 檔案本身沒刪，`.tscn` 裡的 `UI/CastBar` 節點也還在（沒人綁定，永遠不可見，無害）。

舊的 `instant_cast`（右鍵瞬發，含 `RIGHTCLICK_CD`/`INSTANT_CAST_DAMAGE_MULT`/`rightclick_cd_timer`/`rightclick_cd_updated` 訊號）語意被右鍵專注開關完全取代，一併移除——Fire Prototype 的右鍵沒有冷卻限制。`combo_buffer`/`pending_combo`/`_handle_combo_key()`/`_commit_combo()`/`_fail_combo()`/`debug_force_feat()` 維持原樣保留（孤兒狀態，沒有任何呼叫點），等 Phase 2 從 `_process_focused()` 接上。

## 6. Phase 2 — 符文輸入系統 + 法術圖譜資料結構 + 基本 UI

**目標**：專注狀態下能用方向鍵序列切換「目前法術節點」，畫面上看得到切到哪個節點，左鍵能把目前節點的法術真的射出去。對應 Fire Prototype §13 Phase2。

**新增**：
- `scripts/spells/SpellGraphNode.gd`、`scripts/spells/SpellGraph.gd`（見 §4）。
- `Player.gd`：9 種符文裡用得到的 4 種的識別表、`_handle_rune_key()`（複用 `_handle_combo_key()` 骨架，查表對象換成目前節點的 `transitions`）、`current_node_id`、左鍵在專注狀態下＝立即施放目前節點法術並退出專注。
- `resources/spells/fire/fire_graph.tres`：先建「骨架圖譜」，7 個節點全部先指向同一個佔位 `Spell`（例如都複用 Basic 火球術），這個 phase 只驗證圖譜拓撲/切換邏輯對不對，不要求這時候就有 7 種不同效果。
- `scripts/ui/FocusHUD.gd` + `scenes/ui/FocusHUD.tscn`（比照 `HealthOrb.gd`/`CastBar.gd` 的 `bind(player)` 慣例）：顯示目前節點名稱、符文輸入成功/失敗的短暫回饋（複用既有 `fail_flash_timer`/`success_flash_timer` 那套「設個倒數計時器、process 遞減、>0 時顯示顏色」手法）。

**驗收標準**：
- 專注狀態下打 `UU`/`DD`/`RR`/`LL` 能從起始節點（Basic 火球術）切到對應節點，FocusHUD 文字跟著變。
- 打一個圖譜裡不存在的序列（例如在 `fire_arrow` 節點打 `UU`）要有清楚的「輸入失敗」回饋，不會莫名切到別的節點。
- 在非起始節點按左鍵：確認施放的是「目前所在節點」對應的效果（即使這個 phase 全部節點效果都一樣，至少要證明「讀對了目前是哪個節點」）。

**明確不做**：7 種法術的真正差異化效果（圖譜先用佔位 Spell 接線，Phase 3/6 才換成真的）、專注值數值化。

**實作記錄（2026-10-13，✅ 完成）**：

- **§4.1 判定表補上一個原本沒寫清楚的分支**：「打出完整合法符文，但目前節點沒有這條 transition」該怎麼辦，原始表格只寫了「查到就換節點」。拍板結果：**玩家停留在原節點，不是任何懲罰性狀態，也不影響當下能不能施放**——跟按錯鍵用同一套視覺回饋（`_fail_combo()`），因為對玩家來說兩者都是「這次輸入沒有造成改變」。細節跟理由見 `docs/SPELL_SYSTEM.md` §6.1。
- **前綴比對的查詢對象是全域符文語法表（`KNOWN_RUNES`），不是目前節點的 `transitions`**：這樣「要不要繼續等下一鍵」在所有節點手感一致，玩家可以打完整段想打的符文，才由系統判斷這條路通不通，不會因為某節點不接受某符文就提早打斷輸入（卡在半成品前綴就失敗）。
- **圖譜資料結構本質上是有向圖，不是樹**：`transitions: Dictionary[String, String]` 沒有任何機制禁止回頭路/環，`docs/GDD.md` §5.3 的反向路徑如果之後要加，直接在某節點補一條指回去的符文即可，不需要改資料結構或程式碼。這次 7 節點的火系圖譜本身沒有用到反向路徑（`docs/FIRE_PROTOTYPE.md` §5.3 的拓撲裡沒有這種邊），這個設計原則目前只有「架構上支援」，沒有被這張圖實測過。
- **`current_node_id` 每次進入專注狀態都重置回 `start_node_id`**，不沿用上次退出時停在哪個節點——跟 `combo_buffer`/`pending_combo` 進入時清空是同一個邏輯慣例，拍板依據見使用者確認「永遠都是從 starting node 開始衍生」。
- **副作用：順手清掉了舊「超魔專長數值縮放」系統的殘留介面**（`scale_potency()`/`scale_radius()`/`scale_count()`/`maximize()`/`has_scalable_*()`/`get_radius()`/`get_count()`/`describe_potency()`、`fire()` 的 `echo` 參數），這些方法原本的本體（`_apply_scaling_feats()`）已經在轉型時刪除，但掛在 `SpellDelivery`/`SpellEffect`/`ProjectileImpact` 跟各子類別上的配套介面沒有跟著清，是零呼叫端的殘留。新符文圖譜設計（符文 navigate 節點，不縮放數值）確認不會用到，這次順手一次清乾淨，不是這個 phase 原本規劃的範圍，但使用者在 review 時明確授權一併處理。細節見 `docs/SPELL_SYSTEM.md` §3。
- **用 MCP runtime 工具（`execute_code`/`runtime_get_script_vars`/`runtime_screenshot`）在真正跑起來的遊戲裡驗證**，不是只跑語法檢查：`debug_force_rune()` 這個既有的測試捷徑直接拿來驗證圖譜轉換（`basic→RR→fire_arrow`、`fire_arrow→DD→fire_wall`、`fire_arrow→UU` 停留原地、重新 `_enter_focus()` 重置回 `basic`、`basic→LL→fire_shield` 搭配 FocusHUD 文字即時更新），`_cast_current_node()` 施放後正確退出專注且 console 無錯誤。

**事後修正（2026-10-13，右鍵語意，共四輪）**：
1. Phase 2 完成後實測發現右鍵「按一下切換」手感不對——可以空手連點右鍵免成本連續出招。改成按住進入、放開施放，並加上「左鍵要先蓄力到 `CHARGE_THRESHOLD` 右鍵才有效」的門票限制。
2. 門票限制維持，但「放開右鍵＝施放」的部分又改回按右鍵放開才出招（而不是進專注立刻出招）。
3. 使用者實測「按住右鍵」這個手感本身覺得彆扭，要求改回開關式（press 進/press 出），但保留門票限制、且出招邏輯這次改成完全不同的觸發點：**左鍵全程按住不放、右鍵純粹開關子彈時間**。最終定案：
   - 左鍵蓄力到 `CHARGE_THRESHOLD`（門票）之後，按右鍵（press）進入專注，`is_charging`/`charge_timer` 被 `_enter_focus()` 清空（蓄力「已用掉」）。
   - 專注中再按一次右鍵（press）＝取消，不施放任何法術，直接 `_exit_focus()`。
   - 專注中左鍵「放開」（`is_action_just_released`，不依賴 `is_charging` 變數，引擎自己追蹤按鍵狀態）＝施放目前節點並退出專注，這是**唯一**的出招觸發點。
   - 右鍵全程不負責出招，左鍵在專注狀態裡原本的蓄力/近戰判定完全不會跑到（提早在 `is_focused` 分支被攔截）。

`_enter_focus()`/`_exit_focus()` 集中處理 `is_charging`/`charge_timer` 的清空，確保取消或施放之後都不會把蓄力殘留帶到下一次進專注、或退出後在一般狀態意外多觸發一次蓄力火球/近戰。專注值消耗（Fire Prototype §7）本身還沒實作，這個 phase 仍是時間縮放的「無限殼」，資源限制留給 Phase 4。

## 7. Phase 3 — 火系法術：4 個核心節點

**目標**：Basic 火球術／火焰箭／火焰地面／火雨術 各自有真正、可辨識的行為差異（Fire Prototype §6.1/6.5/6.6/6.2）。對應 Fire Prototype §13 Phase3 的前半。

**架構決定（實作前跟使用者確認過，取代原本「繼續用 `SpellDelivery`+`SpellEffect`」的規劃）**：舊的 `Spell`（設定值）+`SpellDelivery`（決定怎麼飛）+`SpellEffect`（決定命中後做什麼）這套通用組合，是為了「任何法術都能被超魔專長動態插效果」設計的——法術圖譜的 7 個節點本來就是寫死、獨一無二的單一招式，不需要這種通用可組合性，硬套只會多一層間接。改成：`Spell.gd` 瘦身成純設定值（`id`/`display_name`/`icon`/`description`/`max_range`）+ 一個虛函式 `cast(caster, aim_dir)`，每個法術類型自己的子類別實作自己的效果：
- `ProjectileSpell`（火球術/火焰箭）：直接重用 `SpellProjectile.tscn`/`ProjectileImpact` 子類別（這兩個是真正的飛行/碰撞基礎設施，不是這次要拆的通用效果組合，跟 Phase 1 `_fire_charged_fireball()` 繞過 `Spell` Resource 直接呼叫是同一手法），`damage`/`speed`/`piercing`/`explosion_radius` 都是自己的 export 欄位。
- `ZoneSpell`（火焰地面/火雨術）：生成共用場景 `DamageZone.tscn`（純距離判定的計時器，不是物理碰撞），`damage_per_tick`/`tick_interval`/`duration`/`radius` 都是自己的欄位。
- 舊的 `SpellDelivery`/`SpellEffect`（及 `AoETargetingDelivery`/`HomingMissileDelivery`/`SelfDelivery`/`SelfBuffDelivery`/`DamageEffect`/`InvisibilityEffect`/`SpeedBuffEffect`）整組變成孤兒，不被任何新節點引用，但不刪（`CLAUDE.md`「功能類的東西可以先留下」），萬一之後真的冒出「好幾個節點要共用同一種通用效果」再撿回來用。

**兩個節點的機制修正**（使用者 review 規劃時糾正，跟 Fire Prototype 原文字面描述有落差）：
- **火焰地面不是以施法者為中心**（不是 `SelfDelivery` 的預設行為）：是在施法者**面前**固定距離處生成（`caster.global_position + aim_dir * spawn_distance`），對應 Fire Prototype §6.6「在身前創造一片...」的字面意思。
- **火雨術不是 DOT**：火焰地面是安靜的 DOT（站在裡面持續流血，不該每次 tick 都像被打一次），火雨術的每次 tick 是真正的「擊中」（要有閃白/彈一下等一般受擊反應，跟被投射物打到一樣）。兩者因此不能共用同一個傷害入口——`TestDummy.gd`/`Player.gd` 新增 `take_dot_damage(amount)`（只扣血，不閃白/不彈/不擊退/不觸發受傷動畫），跟原本的 `take_damage()`（觸發完整受擊反應）並存，`ZoneSpell.damage_mode`（`HIT`/`DOT` enum）決定 `DamageZone` 的 tick 呼叫哪一個。

**新增**：
- `scripts/spells/ProjectileSpell.gd`、`scripts/spells/ZoneSpell.gd`、`scripts/spells/DamageZone.gd`+`scenes/spells/DamageZone.tscn`。
- `resources/spells/fire/basic.tres`（`ProjectileSpell`，`piercing=false`）、`fire_arrow.tres`（`ProjectileSpell`，`piercing=true`，比 Basic 快、傷害低）、`fire_ground.tres`（`ZoneSpell`，`damage_mode=DOT`，`spawn_in_front=true`）、`fire_rain.tres`（`ZoneSpell`，`damage_mode=HIT`，`spawn_in_front=false`，生成位置用滑鼠瞄準點夾限在 `max_range` 內，沿用 `GroundProjection.clamp_to_radius()`，不需要額外的選點確認步驟）。
- `fire_graph.tres` 的這 4 個節點（`node_basic.tres`/`node_fire_arrow.tres`/`node_fire_ground.tres`/`node_fire_rain.tres`）改指向上面新資源，剩下 3 個（火焰護盾/火焰撤離/火牆術）繼續指向 `placeholder_basic.tres`（這份佔位也改型別成 `ProjectileSpell`，純粹為了讓舊 `Spell` 瘦身後這 3 個節點還能正常施放，不是 Phase 6 的提前設計），Phase 6 再換。
- `Player.gd`：`_cast_current_node()` 改呼叫 `node.spell.cast(self, dir)`，不再自己組 stats dict 餵給 delivery——`_base_stats()` 整個刪除（中間層不需要了）。

**驗收標準**：
- 4 個節點各自打到 TestDummy 時，傷害/範圍/持續時間/命中方式要讓人「看得出不一樣」（不要求平衡）。
- `docs/FIRE_PROTOTYPE.md` §11 的「不同法術節點具有可辨識的行為差異」在這 4 個節點上成立。
- 火焰地面的 tick 不觸發 `flash_timer`（安靜扣血），火雨術的 tick 會（真正擊中）。

**明確不做**：火焰護盾/火焰撤離/火牆術（Phase 6）、任何數值平衡調整。

**實作記錄（2026-10-13，✅ 完成）**：用 `execute_code` 直接呼叫各節點 `spell.cast(player, aim_dir)`（繞過右鍵/蓄力輸入，直接測機制本身）在真正跑起來的遊戲裡驗證：`basic` 命中造成 12 傷害（爆炸）、`fire_arrow` 穿透命中造成 7 傷害、`fire_ground` 在面前 60px 處生成區域並以 DOT 方式持續扣血（`flash_timer` 全程沒被觸發，確認走的是 `take_dot_damage()`）、`fire_rain` 在滑鼠瞄準點（手動算過 `clamp_to_radius()` 的夾限結果來定位 TestDummy）持續扣血且每次都觸發 `flash_timer`（確認走的是一般 `take_damage()`）。`DamageZone` 在 `duration` 到期後正確 `queue_free()`，場景節點數恢復原狀。`lsp_project_diagnostics` 37/37 乾淨。

**事後修正（2026-10-13，架構再拆兩次）**：完成之後使用者又追問/糾正了兩輪，`ProjectileSpell` 架構最終定案細節跟上面「架構決定」寫的不完全一樣，見 `docs/SPELL_SYSTEM.md` §2/§2.1 的完整記錄，摘要：
1. **長相/收尾手感跟飛行物理分屬不同檔案**：`SpellProjectile.gd` 瘦成只剩純直線飛行骨架，火球術/火焰箭的長相+收尾各自獨立一支檔案（`FireballProjectile.gd`/`FireArrowProjectile.gd`，按法術名字命名，不是按「爆炸系/穿透系」這種視覺分類命名），兩者都沒有對應的 `.tscn`（碰撞形狀用程式碼建，不需要場景檔案）。
2. **`ProjectileSpell`（Resource 設定值層）不該放 `damage`/`explosion_radius`**：不保證每個投射物都造成傷害，`explosion_radius` 更是火球術專屬——拆成 `ProjectileSpell`（中繼層，只放 `travel_range`/`speed`/`size`/`piercing` 這 4 個「會飛的東西」通用屬性）+ `FireballSpell`/`FireArrowSpell`（各自的 `damage`，`FireballSpell` 多一個 `explosion_radius`）。基底 `Spell` 的 `max_range` 也跟著拿掉（`ZoneSpell` 原本借用同一個欄位名字但意義不同，改成自己專屬的 `placement_range`）。

`basic.tres`/`placeholder_basic.tres` 的 `script_class` 改成 `FireballSpell`，`fire_arrow.tres` 改成 `FireArrowSpell`，欄位名稱同步更新（`max_range`→`travel_range`，新增 `size`）。三個呼叫點（圖譜節點 `basic`/`fire_arrow`、`Player._fire_charged_fireball()`）都重新測過，`lsp_project_diagnostics` 41/41 乾淨。

## 8. Phase 4 — 專注值資源 + 子彈時間數值化

**目標**：專注狀態從 Phase 1 的「無限殼」變成真正有資源限制的機制（Fire Prototype §7）。對應 Fire Prototype §13 Phase4。

**新增**：
- `Player.gd`：`focus_value`/`FOCUS_MAX`/`FOCUS_DRAIN_PER_SEC`/`FOCUS_REGEN_PER_SEC`（全部佔位值）。進入專注持續消耗（用未縮放的真實 delta，讓「能撐幾秒」用真實時間量測，不受子彈時間倍率牽動——這點 Fire Prototype 文件沒明講，是這次補的設計選擇，之後覺得不對可以改用縮放 delta）。離開專注（不管手動退出還是耗盡）停止消耗，隨時間回滿。
- 耗盡時自動施放目前節點（Fire Prototype §3/§7.1 明講的暫定規則）。
- FocusHUD 補上專注值條顯示（平常隱藏/淡出，進入專注才出現）——**事後修正**：使用者指出專注值是「資源存量」，跟血量一樣該隨時看得到，不該只在專注中才出現，見下方實作記錄。

**驗收標準**：
- 專注值隨時間下降可以在 FocusHUD 看到。
- 不輸入、放著不管，等專注值耗盡：自動施放目前節點、退出專注、時間恢復正常。
- 手動取消（專注值還沒耗盡）：不施放任何法術——**這個原本列為待定的問題已經被使用者在右鍵語意第四輪修正時提前回答了**（見 §6 的「事後修正」），開工前不需要再問一次。

**明確不做**：專注值視覺樣式打磨、恢復曲線調整、消耗速率跟演化深度掛鉤（Fire Prototype §12 Open Questions 提過這個可能性，這次先用固定速率）。

**實作記錄（2026-10-13，✅ 完成）**：
- `Player.gd` 新增 `focus_value`/`FOCUS_MAX=5.0`/`FOCUS_DRAIN_PER_SEC=1.0`/`FOCUS_REGEN_PER_SEC=1.5`（全部佔位值）。`_process_focus_drain()` 在專注狀態每幀呼叫，把 `_physics_process()` 收到的（已被 `Engine.time_scale` 縮放過的）`delta` 除回 `Engine.time_scale` 還原成真實秒數再扣血，確保「能撐幾秒」不受子彈時間倍率影響。耗盡時直接呼叫 `_cast_current_node()`（跟左鍵放開同一個出口），強制施放+退出。
- **進專注的門票多了一條**：原本只要左鍵蓄力到 `CHARGE_THRESHOLD`，這次加上 `focus_value > 0.0`——避免耗盡後立刻又能進、進去又立刻被耗盡判定踢出的空轉迴圈，這是這次補上的設計選擇，Fire Prototype 文件沒有明講。
- `FocusHUD.gd`/`FocusHUD.tscn` 第一版新增 `FocusBar`（`ProgressBar`，跟 `CastBar.gd` 同一個「用 Godot 內建元件，不自己刻進度條」慣例），`_process()` 每幀讀 `player.focus_value / player.FOCUS_MAX` 設定 `bar.value`。
- **順手修掉一個無關的既有 bug**：`scenes/SpellTestRange.tscn` 裡 `FocusHUD` 節點的 `anchors_preset` 原本是 `0`（左上角、零尺寸），導致它底下用 `anchor_left/right=0.5` 做「置中」的子節點全部相對一個零尺寸的父層計算位置，實際畫面上整組 UI 被擠在螢幕左邊緣外、看不清楚——這個 bug 從 Phase 2 落地 FocusHUD 時就存在，當時只用 `execute_code` 驗證邏輯狀態，沒有實際截圖看畫面才沒發現。改成 `anchors_preset = 15`（滿版），這次用 `runtime_screenshot` 實際看畫面確認。

**事後修正（2026-10-13，專注值條搬家）**：使用者 review 時指出專注值不該只在專注狀態才看得到——這是跟血量同一類「資源存量」，應該隨時顯示，不是「正在做什麼」這種情境資訊（後者才適合只在相關狀態出現）。改成：
- 新增 `scripts/ui/StatusBars.gd`/`scenes/ui/StatusBars.tscn`：畫面左上角永遠顯示的血量（紅）＋專注值（紫）兩條 `ProgressBar`，顏色用 `theme_override_styles/fill` 塞 `StyleBoxFlat` 指定，不是 `modulate`（`modulate` 會連背景軌道一起染色）。血量接 `player.hp_changed` 訊號（跟 `HealthOrb.gd` 同一個事件型），專注值沒有對應訊號、每幀直接讀（跟 `FocusHUD` 原本那條一樣的理由）。
- `FocusHUD.gd`/`FocusHUD.tscn` 的 `FocusBar` 移除，只留節點名稱＋符文成功/失敗回饋（這些才是「專注中才有意義」的情境資訊）。
- 附帶發現：`scenes/ui/HealthOrb.tscn`（液體圓球血量 UI）其實從來沒有被放進任何場景——`SpellTestRange.tscn` 一直沒有顯示血量，`StatusBars` 是第一個真的把 `hp_changed` 接上畫面的元件，不是取代一個原本在用的東西。`HealthOrb.gd`/`.tscn` 保留著不刪（功能類），只是繼續孤兒。
- 驗證：`runtime_screenshot` 確認左上角兩條互不干擾、正確顯示；`take_damage(60)` 後血量條掉到約 40%、手動設定 `focus_value=2.0` 專注值條同步顯示 40%，兩者在非專注狀態下也正常可見。`lsp_project_diagnostics` 42/42 乾淨。
- 驗證：`execute_code` 直接操控 `focus_value`/呼叫 `_enter_focus()`，確認專注中會用真實時間扣血、歸零時自動施放並正確退出（`Engine.time_scale` 恢復、`is_focused=false`）、退出後開始回復；`focus_value=0` 時按右鍵確認完全進不去專注狀態。`lsp_project_diagnostics` 41/41 乾淨。

## 9. Phase 5 — 測試敵人升級

**目標**：把 `TestDummy` 從純吃傷害的靶子，升級成「有攻擊、有節奏」的簡單敵人，驗證不同法術節點在不同情境下有不同價值（Fire Prototype §9）。對應 Fire Prototype §13 Phase5。

**新增**：新的敵人腳本（取代或擴充 `scripts/entities/TestDummy.gd`），具備：一般移動/追擊、近距離攻擊、有明確前搖的強力攻擊、短暫攻擊間隙、能被範圍法術跟投射物命中。

**驗收標準**：能具體測試 Fire Prototype §9 列的 4 個情境——敵人遠距離移動時測投射物（Basic/火焰箭）、敵人即將進入某個區域時測地面系（火焰地面/火雨術）、敵人即將攻擊時測護盾（火焰護盾，如果 Phase 6 還沒做完，先用佔位版本測流程）、敵人停留原地時測範圍法術。

**明確不做**：真正的死亡/結算畫面（這隻敵人還是測試用途，不是正式關卡的一部分）、多階段 Boss、像舊 `Boss.gd` 那樣的分身/走位 AI。

## 10. Phase 6 — 補完剩餘圖譜節點

**目標**：火焰護盾／火焰撤離／火牆術 從 Phase 2 留的佔位換成真正行為（Fire Prototype §6.3/6.4/6.7）。對應 Fire Prototype §13 Phase6。

**新增（原始規劃，已被下方實作記錄取代）**：原本規劃用 `SelfBuffDelivery`/重用 Dash/跟 `fire_ground` 共用邏輯，Phase 3 把 `SelfBuffDelivery` 那套通用組合拆掉之後這些規劃已經不適用，實際做法見下方實作記錄。

**驗收標準**：`docs/FIRE_PROTOTYPE.md` §11 全部驗收項目成立，7 個節點都有可辨識行為，§5.3 圖譜的每一條路徑都實測過一次（包含兩條路徑通到同一個節點的 `fire_wall`）。

**實作記錄（2026-10-13，✅ 完成）**：使用者要求先把 Phase 6 做完（全部法術效果）再做 Phase 5，順序對調。三個節點都延續 Phase 3 的模式（`Spell` 子類別各自實作 `cast()`），但這次使用者進一步要求「連長得像的機制也不要共用」，三個節點彼此之間、跟既有的 `ZoneSpell`/`DamageZone` 都刻意保持獨立：

- **`fire_shield` → `FireShieldSpell.gd`**：`cast()` 呼叫新的 `Player.start_shield(duration, damage_mult)`，寫兩個專屬欄位（`shield_timer`/`shield_damage_mult`，不透過 `active_buffs`/`SpellEffect`——那套是給同時可能疊加多種 buff 設計的通用機制，火焰護盾目前是唯一一個自身防護法術不需要）。`take_damage()`/`take_dot_damage()` 都套用這個乘數。**反傷效果這次沒做**：`take_damage()` 不知道攻擊者是誰，要做反傷得幫近戰/兩種投射物/`DamageZone` 全部加攻擊者參數，範圍超出這次，先只做減傷。
- **`fire_retreat` → `FireRetreatSpell.gd`**：使用者明確要求不要重用 `apply_knockback()`（原本的提案）或 Dash，即使形狀很像——新增完全獨立的一組狀態（`Player.is_retreating`/`retreat_timer`/`retreat_velocity`/`start_retreat()`/`_process_retreat()`），固定速度位移（不是力道衰減）。原地留下 `FireRetreatTrailZone.gd`（新檔案，矩形 DOT 區域，使用者明確要求不要跟 `DamageZone.gd`〔圓形〕共用，用 `to_local()` 轉本地座標做矩形範圍判定，寫法上接近 `FireArrowProjectile.gd` 的射線判定但是固定不動）。
- **`fire_wall` → `FireWallSpell.gd`**：使用者糾正了原本「移動的長方形火牆」提案——不是投射物，是在施法者前方固定距離「一次創造」一排火柱（使用者的說法：「很多根火柱的集合」），直接重用現成的 `DamageZone.tscn`（不需要為火牆另外設計形狀），用 `await` 做 cascade（依序間隔點燃，不是同時出現）。`cast()` 因此是一個協程，呼叫端沒有、也不需要 `await` 它。**排列方向事後又修正一次**：第一版排成瞄準方向的垂直線（想成一面擋在前面的牆），使用者實測後糾正要沿瞄準方向本身一路往前排，距離也拉長（`spacing` 50→90、`pillar_count` 5→6），見 `docs/SPELL_SYSTEM.md` §2.4。

驗證：5 種符文路徑都實測過（`basic→LL→fire_shield`、`basic→DD→fire_ground→LL→fire_retreat`、`basic→RR→fire_arrow→DD→fire_wall`、`basic→DD→fire_ground→RR→fire_wall` 兩條路徑都真的走過、確認落在同一個 `fire_wall` 節點），護盾減傷數字正確（50 傷害打折成 20）、撤離位移距離跟方向正確（反方向 120px）、撤離軌跡/火牆火柱都正確造成 DOT（`flash_timer` 全程沒觸發）且計時結束後 `queue_free()` 乾淨無殘留。順手清掉了全部 7 個節點共用的 `placeholder_basic.tres`（最後一個引用它的節點換成真資源後變成零呼叫端，直接刪除，不是「功能類先留著」的情況——這份佔位本來就只為了「讓 Phase 2/3 沒做完的節點不會壞掉」而存在，現在 7 個節點全部有真資源，它沒有任何保留價值）。`lsp_project_diagnostics` 46/46 乾淨。

**事後修正（2026-10-13，火雨術掉落物特效 + ZoneSpell 比照 ProjectileSpell 整個拆開）**：使用者要求幫火雨術加掉落物特效，第一版直接寫進共用的 `DamageZone.gd`（用 `damage_mode==HIT` 當開關、頻率是寫死的 const）——使用者指出這樣等於在共用類別裡 expose 了「只有火雨術在用、還調不到」的東西，而且是同一個「不要把專屬邏輯塞進共用檔案」的問題又犯一次。改法比照 `ProjectileSpell` 拆 `FireballSpell`/`FireArrowSpell` 的模式：
- `ZoneSpell` 瘦成中繼層，只放 tick 傷害/間隔/持續時間/半徑/`damage_mode`（任何持續範圍都通用的屬性）。
- `FireGroundSpell extends ZoneSpell`：自己的 `spawn_distance`，`cast()` 生成純 `DamageZone`。
- `FireRainSpell extends ZoneSpell`：自己的 `placement_range`/`rain_spawn_interval`（真正的 `@export` 欄位，不是寫死的 const），`cast()` 生成 `FireRainZone`（新檔案，`extends DamageZone`，只加掉落物特效）。
- `DamageZone.gd` 補 `class_name`、拿掉 `.tscn`（沒有子節點/碰撞形狀需要組合，`.new()` 直接生成，跟 `FireballProjectile`/`FireArrowProjectile` 同一個理由），`FireWallSpell`（火柱）也跟著改用 `DamageZone.new()`。

驗證：三個都重測過——`fire_rain` 範圍內正確冒出橘色隨機火花、`fire_ground`/`fire_wall` 都正常造成 DOT 傷害且沒有掉落特效（確認 gating 正確），`lsp_project_diagnostics` 49/49 乾淨。

---

## 11. 風險

直接繼承 `docs/FIRE_PROTOTYPE.md` §11.1 的 5 個風險（子彈時間過於安全、圖譜過於複雜、施法過於緩慢、基本攻擊失去定位、專注值缺乏取捨），這些是機制設計本身的風險，不是哪個 phase 能單獨解決的，每個 phase 做完都要回頭檢視一次這幾點有沒有發生。另外補一個這個專案特有的風險：**符文輸入判定複用的是舊超魔專長系統留下的前綴比對骨架**（見 §4），如果之後符文的時間窗口/輸入手感需要跟舊系統明顯不同的調校方式，可能要重新設計這塊，不能假設舊的 `COMBO_MAX_GAP` 數值還適用。
