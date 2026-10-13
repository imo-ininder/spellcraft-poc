# 專案說明（給 AI agent）

Spellcraft PoC：法師版「魔物獵人」，純 PVE。Godot 4.6.2，GDScript。

## 先讀這些

**2026-10-13：專案核心戰鬥方向正在轉型，先讀 `docs/DEMO_PLAN.md`**——這是目前實際要照著做、照著追蹤進度的開發計畫（分 Phase 0-6，Phase 0 已完成）。`docs/GDD.md`（整體方向：符文驅動的法術演化圖譜＋右鍵子彈時間／專注值）跟 `docs/FIRE_PROTOTYPE.md`（使用者提供的具體原型規格：符文語意、火系法術圖譜、每個節點設計意圖）是 `DEMO_PLAN.md` 的依據，三份分工是「為什麼／做什麼／怎麼做＋進度」。`docs/GDD.md` 文末附註記錄了現有程式碼哪些部分預期能沿用、哪些要重新設計，動手前先看那段。下面列的其他文件描述的是**舊系統**（已經被取代，相關場景/腳本/資源多數已經刪除，見「目前進度」），各自開頭都補了取代說明：

- `docs/DEMO_PLAN.md` — **目前實際的開發計畫**，分 Phase 定義範圍/驗收標準/進度，動手前先讀這份
- `docs/GDD.md` — 整體方向設計文件
- `docs/FIRE_PROTOTYPE.md` — 第一個原型的具體規格（符文/圖譜/數值）
- `docs/SPELL_SYSTEM.md` — 法術系統架構。2026-10-13 Phase 3 起：`SpellDelivery`/`SpellEffect` 那套通用組合**整組變成孤兒**，每個法術圖譜節點改成自己的 `Spell` 子類別（`FireballSpell`/`FireArrowSpell`/`FireGroundSpell`/`FireRainSpell`/`FireShieldSpell`/`FireRetreatSpell`/`FireWallSpell`）實作 `cast()`，只有真正不保證每種同類法術都需要的屬性才放共用中繼層（`ProjectileSpell`/`ZoneSpell`），`ProjectileImpact`（`ExplosiveImpact`/`PiercingImpact`）仍是真正在用的基礎設施
- `docs/SYSTEMS.md` — 跟戰鬥核心轉型無關、持續運作中的系統技術參考（Dash、HP/死亡、視覺風格/GroundProjection、專案結構、Input Map）
- `docs/ROADMAP.md` — 美術資源遷移路徑（§1/§2 仍適用，玩家角色已經是第一個落地案例）、舊玩法擴充清單（§3 已被取代）
- `docs/DESIGN.md`／`docs/DEMO_GOALS.md`／`docs/BOSS_DESIGN.md` **2026-10-13 已刪除**——內容已經拆解整理進上面幾份文件（哪部分進了哪份見 `docs/SYSTEMS.md`/`docs/SPELL_SYSTEM.md` 開頭的說明），不要再找這三份檔案

## 目前進度

**2026-10-13：Phase 0-4、6 都已完成，Phase 5 還沒開始**（使用者要求先把全部法術效果做完再做測試敵人升級，順序對調），細節/實作記錄見 `docs/DEMO_PLAN.md` §0/§5/§6/§7/§8/§10。目前場景仍然只有 `scenes/SpellTestRange.tscn`（`run/main_scene`）。

已經能動的東西：移動、近戰三連段、蓄力火球、右鍵進出專注狀態（子彈時間，**開關式**——左鍵蓄力到 `CHARGE_THRESHOLD` 之後按右鍵進入，專注中再按一次右鍵＝取消不施放，**出招的唯一觸發點是左鍵放開**（左鍵要從蓄力階段全程按住，右鍵只負責開關子彈時間，不負責出招），沒蓄力到位按右鍵完全沒反應，防止空手連點右鍵免成本連續出招——這個語意改過四輪，完整過程見 `docs/DEMO_PLAN.md` §6 的「事後修正」）、專注狀態下用 WASD 打符文（`UU`/`DD`/`LL`/`RR`）沿 `resources/spells/fire/fire_graph.tres` 這張圖切換 `Player.current_node_id`。`scripts/ui/FocusHUD.gd`／`scenes/ui/FocusHUD.tscn` 顯示目前節點名稱＋符文成功/失敗回饋（只在專注中出現，情境資訊）。**專注狀態現在有真正的資源限制了**（Phase 4）：`Player.focus_value`（`FOCUS_MAX=5.0`）進專注後用真實（未被子彈時間縮放）的秒數持續消耗，耗盡會強制施放目前節點並退出（跟左鍵放開同一個出口），退出後隨時間回滿；進專注除了左鍵蓄力門票，現在還多一條 `focus_value > 0.0` 才能進。

**血量＋專注值永遠顯示在畫面左上角**（`scripts/ui/StatusBars.gd`／`scenes/ui/StatusBars.tscn`，紅血量條/紫專注值條，使用者明確要求比照血量處理，不像 FocusHUD 只在專注中才出現——事後修正，過程見 `docs/DEMO_PLAN.md` §8）。順便發現 `HealthOrb.gd`/`HealthOrb.tscn`（液體圓球血量 UI）其實從沒被放進任何場景，`SpellTestRange.tscn` 一直沒有血量顯示，`StatusBars` 是第一個真的接上畫面的；`HealthOrb` 保留不刪，繼續孤兒。另外修了一個從 Phase 2 就存在、沒人發現的 bug：`FocusHUD` 節點的 `anchors_preset` 是 `0`（零尺寸），底下置中排版的子節點全部被擠到螢幕左邊緣外看不到，已改成滿版錨點。

**圖譜 7 個節點裡 4 個（`basic`/`fire_arrow`/`fire_ground`/`fire_rain`）已經有真正差異化效果**（Phase 3）：架構上**整個不走 `SpellDelivery`/`SpellEffect` 那套通用組合了**——每個法術圖譜節點本來就是寫死的單一招式，不需要「任何法術都能插任何效果」的通用可組合性，使用者 review 時提出這個質疑並拍板改掉，而且不只法術效果，連「同類法術共用一個設定值類別」都拆到不能再拆：`Spell.gd` 瘦身成純身份欄位（不放數值）+ 虛函式 `cast(caster, aim_dir)`，中繼層 `ProjectileSpell`（只放 `travel_range`/`speed`/`size`/`piercing` 這種不管哪種投射物都通用的屬性）底下是各自的 `FireballSpell`/`FireArrowSpell`（各自的 `damage`，`FireballSpell` 多一個 `explosion_radius`，兩者都完整實作 `cast()`，各自 `.new()` 自己專屬的投射物節點類別 `FireballProjectile`/`FireArrowProjectile`，兩個都沒有對應的 `.tscn`——碰撞形狀用程式碼建）；`ZoneSpell`（中繼層，只放 tick 傷害/間隔/持續時間/半徑/`damage_mode` 這種任何持續範圍都通用的屬性）底下是 `FireGroundSpell`/`FireRainSpell`——這兩個節點同一天又被拆過一次：火雨術的「掉落物特效」原本直接寫進共用的 `DamageZone.gd`（用 `damage_mode==HIT` 當開關、頻率是寫死的 const），使用者指出這樣等於在共用類別裡 expose 了「只有火雨術在用、還調不到」的東西，改成 `FireRainZone extends DamageZone` 專屬子類別，`rain_spawn_interval` 變成真正的 `@export` 欄位。`DamageZone`（`class_name`，不是場景，`.new()` 直接生成，沒有 `.tscn`）也被 `FireGroundSpell`/`FireWallSpell`（火柱）直接重用。**火焰地面是安靜的 DOT，火雨術是會觸發正常受擊反應的「擊中」**——這是兩種不同的傷害入口（`take_dot_damage()` vs `take_damage()`，見 `docs/SPELL_SYSTEM.md` §2.3），不是同一種機制換數值。**剩下 3 個節點（Phase 6）現在也都有真正效果了**：`fire_shield`（`FireShieldSpell`，受傷打折，寫 `Player.shield_timer`/`shield_damage_mult` 兩個專屬欄位，不經過 `active_buffs`；反傷效果沒做，`take_damage()` 不知道攻擊者是誰）、`fire_retreat`（`FireRetreatSpell`，完全獨立一套位移——使用者明確要求不重用 `apply_knockback()`/Dash，見 `Player.start_retreat()`/`_process_retreat()`——留下矩形 DOT 軌跡 `FireRetreatTrailZone.gd`，明確要求不跟 `DamageZone` 共用）、`fire_wall`（`FireWallSpell`，不是投射物，在前方固定距離一次生成一排重疊的火柱，直接重用 `DamageZone`，用 `await` 做依序點燃的 cascade 效果）。7 個節點全部有真資源後，`placeholder_basic.tres` 變成零呼叫端直接刪除了，不是繼續留著的孤兒。拆分的完整理由跟判斷準則見 `docs/SPELL_SYSTEM.md` §2/§2.1/§2.2，Phase 6 細節見 `docs/DEMO_PLAN.md` §10。

`SpellDelivery`/`SpellEffect`（含 `ProjectileDelivery`，之前就標注孤兒的 `AoETargetingDelivery`/`HomingMissileDelivery` 也還是孤兒）整組變成沒有任何新節點引用的孤兒架構，連同更早 Phase 2 落地時順手清掉的舊「超魔專長數值縮放」殘留介面（`scale_potency`/`scale_radius`/`scale_count`/`maximize`/`has_scalable_*`/`get_radius`/`get_count`/`describe_potency`、`fire()` 的 `echo` 參數）——都不刪，比照「功能類的東西可以先留下」的既有慣例，但如果看到舊文件還提到這些方法當作「現在在用的架構」，那是沒跟著更新的歷史殘留。

**系統性修正（2026-10-13）**：使用者發現火牆術的火柱間距往水平方向射出會重疊、往垂直方向射出卻不會，根因是壓扁視角（`GroundProjection.squash`）下，任何用 `direction * distance` 算世界座標位移/位置的地方，都會出現「水平距離感正常、垂直距離感變短」的系統性問題——不是只有火牆有這個 bug，Dash/火焰撤離的位移距離、投射物的飛行距離判斷全部中招。新增 `GroundProjection.offset_towards(direction, distance)`（回傳「投影後長度等於 distance」的世界座標向量）統一解法，套用到 `Player.gd`（Dash 的 `dash_velocity`、`start_retreat()`）、`FireWallSpell`/`FireGroundSpell`/`FireRetreatSpell`（生成位置/間距/軌跡）、`SpellProjectile.gd`（拆出 `projected_distance_traveled` 專門給 `max_range` 判斷用，`distance_traveled` 原始距離保留給子類別長相用）——**每個法術仍然各自獨立實作，這個函式是純數學工具，不是行為共用**，詳細清單見 `docs/SYSTEMS.md` §3.1。另外把 `COMBO_MAX_GAP`（符文輸入確認視窗）從 0.15 拉長到 0.35，使用者實測覺得太短。

**跟戰鬥系統設計無關、完全不受這次轉型影響的部分**：基礎 Dash、HP/死亡系統（`Player.gd` 的 `hp`/`MAX_HP`/`take_damage()`；左下角液體填充圓球 UI `scripts/ui/HealthOrb.gd`；死亡畫面 `scripts/ui/DeathScreen.gd`）、玩家角色美術（AI 生成 sprite sheet，`scripts/entities/PlayerSpriteAnimator.gd`，細節見 `docs/ROADMAP.md` §2.1a）、`GroundProjection`/`MagicFX` 等視覺工具。**接下來要做**：照 `docs/DEMO_PLAN.md` 的 Phase 5 開始（測試敵人升級），不要跳著做後面的 phase。

## 架構規則

1. **Resource 只放設定值，不放運行時狀態**（CD、吟唱進度、buff 剩餘時間一律存在角色節點身上）。這條規則在 `SPELL_SYSTEM.md` 裡反覆強調，因為 Godot 的 Resource 是共享引用，不是值型別。
2. **目錄依領域分類**：`entities/`（角色、怪物）、`spells/`（法術相關）、`core/`（場地/環境）、`fx/`（共用特效）、`ui/`（輪盤、選點介面）。新增檔案時歸到對應資料夾，不要全部塞進同一層。`state/`（`GameState` autoload）2026-10-13 跟著舊裝備/超魔專長系統一起刪除了，這個分類目前沒有東西，之後如果新系統需要跨場景共用狀態再評估要不要重開。
3. **（舊規則，已失效）新增法術必須加進 `GameState.gd:CATALOG`**——`GameState.gd` 已刪除，這條規則目前沒有對應物。新系統的法術圖譜資料結構見 `docs/DEMO_PLAN.md` §4。
4. **（舊規則，已失效）超魔專長是角色永久天生會的被動**——超魔專長系統（`GameState.ARCANE_FEATS`）已刪除，`Player.gd` 保留了方向鍵序列前綴比對的骨架（`_handle_combo_key()`/`combo_buffer`），但查表對象/觸發後行為都還沒重新接上，見 `docs/DEMO_PLAN.md` §4/§6（Phase 2）。
5. **法術數值目前仍是 Demo 階段的示範值**，不是最終平衡數字，新系統的數值全部是佔位值，比照這條慣例，不需要先定案再動手。
6. **判斷「該不該共用程式碼」要看這段邏輯會不會被持續調整，不是只看程式碼像不像/場景獨不獨立**：極小、極穩定、幾乎不會再改的工具函式可以各自複製，共用反而徒增間接層。但任何涉及 UI 呈現、使用者會持續要求調整格式/數值/視覺的邏輯（讀條、計時器顯示、HUD 元件...），一開始就要抽成共用場景（`.tscn`＋`class_name` 腳本，暴露簡單 public API），跟 `Player.tscn`/`HomingMissile.tscn` 這種可重用場景同一個模式，不要先複製再說。踩過一次見 `scripts/ui/CastBar.gd`（`Main.gd`〔已刪除〕／`SpellTestRange.gd` 原本各自複製一份讀條邏輯，使用者只要求改一邊就對不上，2026-10-11 記錄，原始記錄在已刪除的 `docs/DESIGN.md` §1.6，教訓已經沒有獨立文件可查，寫在這裡就是完整記錄）——如果已經複製了，之後使用者對其中一份提出調整需求時，要主動意識到「另一份是不是也要跟著改」，不要只改明確點名的那一份就交差。

## 已知環境雷

- **`.mcp.json`（MCP server 設定，已加進 `.gitignore`，不進版控）如果 `command` 寫的是 `"cmd"`／`args` 第一個是 `"/c"`，那是 Windows 專用的呼叫方式，在 macOS 上會因為找不到 `cmd` 這個指令直接連線失敗（`ENOENT`）。這台機器要直接用 `"command": "npx"`，`args` 不要有 `/c`。改完設定檔後，當前連線不會自動套用，需要使用者手動重新連接一次 editor 的 MCP 才會生效。
- **MCP 連線跟 headless 流程會互相干擾**：editor 的 MCP 連線正常時，不要再跑 `Godot --headless --import`/`--quit-after` 這類會另外開一個 Godot 處理程序的指令——會跟 editor 那份 MCP registry/port 搶，導致連線變成 `AUTH_FAILED`（`registry entry has no token path`）甚至讓新開的 headless 處理程序卡死不退出。MCP 連線正常時，所有驗證（語法檢查、跑起來測行為、截圖）優先用 `script_check`/`game_start`/`execute_code`/`runtime_get_script_vars`/`runtime_screenshot` 這些 MCP 工具，不要繞回 headless script。
- `node_get_property`/`node_call_method`/`scene_get_tree` 讀的是 **editor 裡目前開啟的場景（設計時狀態）**，不是真正在跑的 runtime 實例——即使遊戲正在跑，這幾個工具看到的還是 `.tscn` 檔案本身的內容。要讀/改真正在跑的那份，要用 `execute_code`（`channel: "runtime"`，預設值）配 `get_node('/root/場景名/節點路徑')`，或 `runtime_get_script_vars`。

- 新增帶 `class_name` 的腳本後，需要先跑一次 `Godot --headless --import --path .` 讓全域類別註冊，否則會出現 `Identifier "X" not declared` 的假錯誤。
- `Godot --headless --check-only` 在這個環境裡會卡住不退出，改用 `Godot --headless --quit-after N --path .` 跑幾個 frame 來驗證腳本語法/runtime 錯誤。
- `project.godot` 的 `run/main_scene` 是 `scenes/SpellTestRange.tscn`（2026-10-13 大廳/正式戰鬥場景刪除後改的，目前專案唯一的場景），headless 預設跑的就是這個場景，不用再另外指定路徑。
- 無頭模式無法模擬滑鼠/鍵盤輸入，超魔專長輸入手感、輪盤視覺效果務必在 editor 裡實際跑一次確認，不能只靠 headless 檢查判斷「做完了」。角度類邏輯（輪盤選取判定）可以寫一次性驗證腳本用 `Godot --headless --script path.gd` 跑數學驗證，但跑完記得清掉，不要留在專案裡常駐。
- **`_init()` 裡直接寫繼承自父類別的 `@export` 欄位會編譯失敗**（`Identifier not found: <欄位名>`），即使欄位確實宣告在父類別上——必須加 `self.` 明確限定（`self.apply_mode = ...`），同一個欄位如果是宣告在「這個類別自己身上」則不需要 `self.` 也能在 `_init()` 裡直接賦值（`DamageEffect.gd` 的 `min_amount`/`max_amount` 就是這樣，照樣能用）。只在「`_init()` 賦值繼承來的欄位」這個特定組合才會炸，其餘地方（`_ready()`、一般方法）存取繼承欄位不受影響。踩過一次見 `scripts/spells/InvisibilityEffect.gd`/`SpeedBuffEffect.gd`。
- **這個環境裡 MCP 連線偶爾會卡在 `AUTH_FAILED`（`registry entry has no token path`）**，通常是在跑 `Godot --headless --import --path .`（重新註冊全域類別用）之後發生——那個指令會另外開一個 Godot 處理程序去註冊 MCP registry，可能把正在跑的 editor 那份 token 蓋掉。`script_check`／`game_start`／`game_stop` 不受影響還能用，但 `execute_code`／`runtime_screenshot`／`runtime_get_script_vars` 這類真正連進 runtime 的工具會持續失敗，agent 自己重試/重開 `game_start` 沒用，需要使用者手動重新連接 editor 的 MCP 才能恢復。
- **外部腳本（例如 Python/Bash）新增的圖片等二進位資源，Godot 編輯器不會自動偵測匯入**，執行期讀到的材質欄位會是 `null`——要呼叫 MCP 的 `editor_refresh` 且**不帶 `file_paths` 參數**（觸發全專案掃描，不是只傳路徑的 O(1) 單檔模式）才會真的產生對應的 `.import` 檔案；而且就算匯入完成，當下已經在跑的遊戲 session 讀到的仍然是匯入前的舊狀態，要 `game_stop`＋`game_start` 重開一次遊戲才讀得到剛匯入好的資源。跟新增 `class_name` 腳本要先匯入是同一類問題，只是觸發方式不同。

## 工作方式

- 這個專案目前由單人（配 AI agent 協作）開發，PoC/Demo 階段優先驗證手感與架構方向，不要在數值還沒定案前過度打磨。
- 改動核心機制（超魔專長判定、法術架構、法術格系統）後，若有新的設計決策或踩到的坑，補回對應的 `docs/*.md`，不要只改程式碼不留記錄——這幾份文件就是給未來的你/其他 agent 看的「為什麼長這樣」的真相來源。
- 動手前若發現使用者的描述跟現有文件/程式碼有衝突（例如把「符紋」講成「超魔專長」、把「每把法術配符紋」講成「配置法術格」），先確認是不是範圍/設計已經調整過，不要假設是自己記錯，也不要默默照舊邏輯做——先問清楚再動工。
