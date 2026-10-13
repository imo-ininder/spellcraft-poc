# 專案說明（給 AI agent）

Spellcraft PoC：法師版「魔物獵人」，純 PVE。Godot 4.6.2，GDScript。

## 先讀這些

**2026-10-13：專案核心戰鬥方向正在轉型，先讀 `docs/DEMO_PLAN.md`**——這是目前實際要照著做、照著追蹤進度的開發計畫（分 Phase 0-6，Phase 0 已完成）。`docs/GDD.md`（整體方向：符文驅動的法術演化圖譜＋右鍵子彈時間／專注值）跟 `docs/FIRE_PROTOTYPE.md`（使用者提供的具體原型規格：符文語意、火系法術圖譜、每個節點設計意圖）是 `DEMO_PLAN.md` 的依據，三份分工是「為什麼／做什麼／怎麼做＋進度」。`docs/GDD.md` 文末附註記錄了現有程式碼哪些部分預期能沿用、哪些要重新設計，動手前先看那段。下面列的其他文件描述的是**舊系統**（已經被取代，相關場景/腳本/資源多數已經刪除，見「目前進度」），各自開頭都補了取代說明：

- `docs/DEMO_PLAN.md` — **目前實際的開發計畫**，分 Phase 定義範圍/驗收標準/進度，動手前先讀這份
- `docs/GDD.md` — 整體方向設計文件
- `docs/FIRE_PROTOTYPE.md` — 第一個原型的具體規格（符文/圖譜/數值）
- `docs/SPELL_SYSTEM.md` — 法術系統架構，`Spell`/`SpellDelivery`/`SpellEffect`/`ProjectileImpact` 的三層分離設計**仍在使用**（當作新圖譜節點的實作基礎，見 `docs/DEMO_PLAN.md` §4）
- `docs/SYSTEMS.md` — 跟戰鬥核心轉型無關、持續運作中的系統技術參考（Dash、HP/死亡、視覺風格/GroundProjection、專案結構、Input Map）
- `docs/ROADMAP.md` — 美術資源遷移路徑（§1/§2 仍適用，玩家角色已經是第一個落地案例）、舊玩法擴充清單（§3 已被取代）
- `docs/DESIGN.md`／`docs/DEMO_GOALS.md`／`docs/BOSS_DESIGN.md` **2026-10-13 已刪除**——內容已經拆解整理進上面幾份文件（哪部分進了哪份見 `docs/SYSTEMS.md`/`docs/SPELL_SYSTEM.md` 開頭的說明），不要再找這三份檔案

## 目前進度

**2026-10-13：Phase 0（舊系統清理）、Phase 1（核心操作骨架）、Phase 2（符文輸入+法術圖譜+基本UI）都已完成**，細節/實作記錄見 `docs/DEMO_PLAN.md` §0/§5/§6。目前場景仍然只有 `scenes/SpellTestRange.tscn`（`run/main_scene`）。

已經能動的東西：移動、近戰三連段、蓄力火球、右鍵進出專注狀態（子彈時間）、專注狀態下用 WASD 打符文（`UU`/`DD`/`LL`/`RR`）沿 `resources/spells/fire/fire_graph.tres` 這張圖切換 `Player.current_node_id`，左鍵在專注狀態下施放目前節點並退出。`scripts/ui/FocusHUD.gd`／`scenes/ui/FocusHUD.tscn` 顯示目前節點名稱＋符文成功/失敗回饋。**圖譜 7 個節點目前全部共用同一個佔位 `Spell`**（`resources/spells/fire/placeholder_basic.tres`，`ProjectileDelivery`+`ExplosiveImpact`）——這個 phase 驗證的是圖譜拓撲/符文判定，不是法術效果本身，7 把法術各自的真正差異化效果是 Phase 3/6 的事。

Phase 2 落地時順手清掉了舊「超魔專長數值縮放」系統的殘留介面（`scale_potency`/`scale_radius`/`scale_count`/`maximize`/`has_scalable_*`/`get_radius`/`get_count`/`describe_potency`、`fire()` 的 `echo` 參數），這些掛在 `SpellDelivery`/`SpellEffect`/`ProjectileImpact` 上但零呼叫端，新圖譜設計不會用到，使用者 review 時明確授權一併移除——如果看到舊文件還提到這些方法，那是沒跟著更新的歷史殘留，不是還在用。

**跟戰鬥系統設計無關、完全不受這次轉型影響的部分**：基礎 Dash、HP/死亡系統（`Player.gd` 的 `hp`/`MAX_HP`/`take_damage()`；左下角液體填充圓球 UI `scripts/ui/HealthOrb.gd`；死亡畫面 `scripts/ui/DeathScreen.gd`）、玩家角色美術（AI 生成 sprite sheet，`scripts/entities/PlayerSpriteAnimator.gd`，細節見 `docs/ROADMAP.md` §2.1a）、`GroundProjection`/`MagicFX` 等視覺工具。**接下來要做**：照 `docs/DEMO_PLAN.md` 的 Phase 3 開始（火系法術4個核心節點真正有差異化效果），不要跳著做後面的 phase。

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
