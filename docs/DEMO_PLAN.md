# Demo Plan — 符文法術圖譜 Prototype

> **這份文件取代 `docs/DEMO_GOALS.md`**，是目前專案實際要照著做、照著追蹤進度的開發計畫。`docs/GDD.md` 是抽象的整體方向，`docs/FIRE_PROTOTYPE.md` 是使用者給的具體原型規格（符文語意、法術圖譜、每個節點的設計意圖），這份文件把 Fire Prototype §13 的 Phase 切法對應到**這個專案實際的檔案/系統**，每個 phase 補上驗收標準、明確排除範圍，以及目前進度。三份文件分工：GDD＝為什麼，Fire Prototype＝做什麼，這份＝怎麼做、做到哪了。

---

## 0. 目前進度

| Phase | 內容 | 狀態 |
|---|---|---|
| 0 | 舊系統清理（場景/法術/超魔） | ✅ 完成（2026-10-13） |
| 1 | 核心操作骨架（移動/近戰三連段/蓄力火球/專注進出殼） | ✅ 完成（2026-10-13） |
| 2 | 符文輸入系統 + 法術圖譜資料結構 + 基本 UI | ⬜ 未開始 |
| 3 | 火系法術：4 個核心節點 | ⬜ 未開始 |
| 4 | 專注值資源 + 子彈時間數值化 | ⬜ 未開始 |
| 5 | 測試敵人升級 | ⬜ 未開始 |
| 6 | 補完剩餘圖譜節點 | ⬜ 未開始 |

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

## 7. Phase 3 — 火系法術：4 個核心節點

**目標**：Basic 火球術／火焰箭／火焰地面／火雨術 各自有真正、可辨識的行為差異（Fire Prototype §6.1/6.5/6.6/6.2）。對應 Fire Prototype §13 Phase3 的前半。

**新增**：
- `resources/spells/fire/basic.tres`：`ProjectileDelivery`+`ExplosiveImpact`，數值可以參考舊 `Fireball.tres`（已刪除，但 `docs/SPELL_SYSTEM.md` 記錄過參考數值）當起點。
- `resources/spells/fire/fire_arrow.tres`：`ProjectileDelivery`+`PiercingImpact`，比 Basic 快、傷害低一點、穿透多個敵人——跟 Basic 的差異要「打起來有感」，不是數字上差一點點。
- `resources/spells/fire/fire_ground.tres`：`SelfDelivery`（先簡化成「固定以施法者為中心」，不做「跟著滑鼠往前推一段距離」那麼複雜，這是這個 phase 的簡化，用註解標記不是定案）+ DOT 效果，持續時間內多次造成傷害。
- `resources/spells/fire/fire_rain.tres`：範圍持續攻擊，用法跟 `fire_ground` 類似（`SelfDelivery`+DOT），差異在於演出/數值曲線要讓玩家感覺是不同招式。
- `fire_graph.tres` 的這 4 個節點接上真正資源，剩下 3 個（火焰護盾/火焰撤離/火牆術）繼續用 Phase 2 的佔位，Phase 6 再換。

**驗收標準**：
- 4 個節點各自打到 TestDummy 時，傷害/範圍/持續時間/命中方式要讓人「看得出不一樣」（不要求平衡）。
- `docs/FIRE_PROTOTYPE.md` §11 的「不同法術節點具有可辨識的行為差異」在這 4 個節點上成立。

**明確不做**：火焰護盾/火焰撤離/火牆術（Phase 6）、任何數值平衡調整。

## 8. Phase 4 — 專注值資源 + 子彈時間數值化

**目標**：專注狀態從 Phase 1 的「無限殼」變成真正有資源限制的機制（Fire Prototype §7）。對應 Fire Prototype §13 Phase4。

**新增**：
- `Player.gd`：`focus_value`/`FOCUS_MAX`/`FOCUS_DRAIN_PER_SEC`/`FOCUS_REGEN_PER_SEC`（全部佔位值）。進入專注持續消耗（用未縮放的真實 delta，讓「能撐幾秒」用真實時間量測，不受子彈時間倍率牽動——這點 Fire Prototype 文件沒明講，是這次補的設計選擇，之後覺得不對可以改用縮放 delta）。離開專注（不管手動退出還是耗盡）停止消耗，隨時間回滿。
- 耗盡時自動施放目前節點（Fire Prototype §3/§7.1 明講的暫定規則）。
- FocusHUD 補上專注值條顯示（平常隱藏/淡出，進入專注才出現）。

**驗收標準**：
- 專注值隨時間下降可以在 FocusHUD 看到。
- 不輸入、放著不管，等專注值耗盡：自動施放目前節點、退出專注、時間恢復正常。
- 手動按右鍵退出（專注值還沒耗盡）：**這個行為 Fire Prototype 文件本身列為待定項**（§3「尚未施放的法術如何處理，仍待確認」），開工前建議先跟使用者確認一次要不要施放，不要自己假設——這是 Phase 4 唯一需要在動手前額外確認的點，其餘數值全部是佔位、不需要先問。

**明確不做**：專注值視覺樣式打磨、恢復曲線調整、消耗速率跟演化深度掛鉤（Fire Prototype §12 Open Questions 提過這個可能性，這次先用固定速率）。

## 9. Phase 5 — 測試敵人升級

**目標**：把 `TestDummy` 從純吃傷害的靶子，升級成「有攻擊、有節奏」的簡單敵人，驗證不同法術節點在不同情境下有不同價值（Fire Prototype §9）。對應 Fire Prototype §13 Phase5。

**新增**：新的敵人腳本（取代或擴充 `scripts/entities/TestDummy.gd`），具備：一般移動/追擊、近距離攻擊、有明確前搖的強力攻擊、短暫攻擊間隙、能被範圍法術跟投射物命中。

**驗收標準**：能具體測試 Fire Prototype §9 列的 4 個情境——敵人遠距離移動時測投射物（Basic/火焰箭）、敵人即將進入某個區域時測地面系（火焰地面/火雨術）、敵人即將攻擊時測護盾（火焰護盾，如果 Phase 6 還沒做完，先用佔位版本測流程）、敵人停留原地時測範圍法術。

**明確不做**：真正的死亡/結算畫面（這隻敵人還是測試用途，不是正式關卡的一部分）、多階段 Boss、像舊 `Boss.gd` 那樣的分身/走位 AI。

## 10. Phase 6 — 補完剩餘圖譜節點

**目標**：火焰護盾／火焰撤離／火牆術 從 Phase 2 留的佔位換成真正行為（Fire Prototype §6.3/6.4/6.7）。對應 Fire Prototype §13 Phase6。

**新增**：
- `fire_shield.tres`：`SelfBuffDelivery` 安裝一個 DURATION buff（防禦力提升；「對攻擊自己的敵人造成火焰傷害」這個反傷效果看當時 `SelfBuffDelivery`/`SpellEffect` 架構支不支援，不支援的話先簡化成只有減傷，用註解標記）。
- `fire_retreat.tres`：向後位移一段距離（可以參考 `Player.gd` 既有 Dash 的 `move_and_slide()` 位移手法）+ 在地上留下火焰軌跡（可能需要一個新的持續區域效果，或簡化成跟 `fire_ground` 共用邏輯）。
- `fire_wall.tres`：射出型火牆，具體生成/飛行/命中判定——Fire Prototype 文件自己也說「仍需進一步定義」，這個 phase 開工時要先把這個節點的具體玩法定案，不是直接套用現成 delivery 湊數。

**驗收標準**：`docs/FIRE_PROTOTYPE.md` §11 全部驗收項目成立，7 個節點都有可辨識行為，§5.3 圖譜的每一條路徑都實測過一次（包含兩條路徑通到同一個節點的 `fire_wall`）。

---

## 11. 風險

直接繼承 `docs/FIRE_PROTOTYPE.md` §11.1 的 5 個風險（子彈時間過於安全、圖譜過於複雜、施法過於緩慢、基本攻擊失去定位、專注值缺乏取捨），這些是機制設計本身的風險，不是哪個 phase 能單獨解決的，每個 phase 做完都要回頭檢視一次這幾點有沒有發生。另外補一個這個專案特有的風險：**符文輸入判定複用的是舊超魔專長系統留下的前綴比對骨架**（見 §4），如果之後符文的時間窗口/輸入手感需要跟舊系統明顯不同的調校方式，可能要重新設計這塊，不能假設舊的 `COMBO_MAX_GAP` 數值還適用。
