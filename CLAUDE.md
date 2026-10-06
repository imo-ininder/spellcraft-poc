# 專案說明（給 AI agent）

Spellcraft PoC：法師版「魔物獵人」，純 PVE。Godot 4.6.2，GDScript。

## 先讀這些

動手改程式碼前，先讀 `docs/DESIGN.md` 第3節（超魔專長序列輸入系統，文件裡仍沿用舊名「符紋」描述判定邏輯本身，§4.7 說明了這只是用詞歷史，概念完全一致）——這是整個專案最核心、最容易被誤改的邏輯，裡面記錄了時間窗口數值的演進歷史與為什麼現在這樣設計。不要只看程式碼就假設行為合理，`DESIGN.md` 裡記錄了好幾個「表面上像 bug 但其實是設計決定」的案例。

- `docs/DESIGN.md` — 已拍板的核心機制、決策歷史、已知行為邊界，§4.7 記錄了法術格系統/大廳/GameState 的落地細節
- `docs/SPELL_SYSTEM.md` — 法術系統架構，`Spell`/`SpellDelivery`/`SpellEffect`/`ProjectileImpact` 已實作落地（§8 補充記錄實作時的具體決定），§9 的 capability 相容性機制規劃中但刻意尚未實作
- `docs/DEMO_GOALS.md` — 目前這一階段要做的 Demo 範圍與驗收標準，這是當前最新的工作目標，§2.5/§4 記錄了法術格系統取代原本「每把法術各自配符紋」設計的範圍調整
- `docs/ROADMAP.md` — 美術資源遷移路徑、玩法擴充清單
- `docs/BOSS_DESIGN.md` — Demo boss（墮落法師）的完整行動機制設計：分身誤導、火球雨、吸引扇形、走位 AI，含數值表與設計意圖，動 `scripts/entities/boss/` 下任何檔案前先讀這份

## 目前進度（流程：Lobby → Main）

啟動場景是 `scenes/Lobby.tscn`（大廳，配置法術格），按「出發」後切換到 `scenes/Main.tscn`（戰鬥）。已實作：超魔專長吟唱判定、五把法術（火球術/力場波/雷電箭/隱形術/速度提升，涵蓋 `ProjectileDelivery`/`SelfDelivery`/`AoETargetingDelivery`/`SelfBuffDelivery` 四種 delivery，buff 類法術的 DURATION 效果機制已落地，見 `docs/SPELL_SYSTEM.md` §8.15）、法術切換輪盤（支援任意把數）、基礎 Dash、右鍵瞬發、競技場（內圈玩家場地＋外圈 boss 環道，中間隔一圈不能互通的縫隙，見 `docs/BOSS_DESIGN.md` §2.5）、Demo boss（`scripts/entities/boss/`：遠程型法師，固定沿外圈軌道巡邏（不追玩家，物理上也碰不到玩家），分身誤導機制（逐批累加、分身+本體總共上限5個）＋火球雨/光球連擊兩個遠程週期招式隔空打進內圈，吸引懲罰目前停用，見 `docs/BOSS_DESIGN.md`）、法術格系統（固定6格，`GameState` autoload 跨場景傳遞）、開發用除錯面板（F3 切換，顯示玩家 buff 狀態/boss AI 狀態機，見 `Main.gd`）。**還沒做**：真實HP/死亡/結算畫面（玩家被打只閃光不扣血，boss 本體血量歸零會重置滿血——分身的3HP是例外，是真的會消失，這次刻意只做這一塊）、位移類法術（目前只有基礎Dash，`AoETargetingDelivery` 移動施法者那條收尾路徑還沒驗證過）、美術/音樂（全部仍是`_draw()`程式繪圖）。

## 架構規則

1. **Resource 只放設定值，不放運行時狀態**（CD、吟唱進度、buff 剩餘時間一律存在角色節點身上）。這條規則在 `SPELL_SYSTEM.md` 裡反覆強調，因為 Godot 的 Resource 是共享引用，不是值型別。
2. **目錄依領域分類**：`entities/`（角色、怪物）、`spells/`（法術相關）、`core/`（場地/環境）、`fx/`（共用特效）、`ui/`（輪盤、選點介面）、`state/`（GameState autoload）。新增檔案時歸到對應資料夾，不要全部塞進同一層。
3. **新增法術必須加進 `GameState.gd:CATALOG`**，否則大廳跟輪盤都不會出現這把法術——這是目前唯一的法術總表來源。
4. **超魔專長是角色永久天生會的被動，不是裝備/配置給特定法術的東西**（組合表定義在 `GameState.gd:ARCANE_FEATS`，`Player.gd` 只引用它來做判定——大廳的超魔專長一覽分頁也要讀同一份表，所以資料放 GameState，判定邏輯仍在 Player.gd）。大廳要配置的是法術（`Spell.slot_cost` 佔用固定6格），不是專長。別把這兩個搞混，之前有過一輪方向調整才確定下來。
5. **超魔專長/法術數值目前仍是 Demo 階段的示範值**，不是最終平衡數字，調整前先確認 `docs/DESIGN.md` §3.6、§4.7 是否已記錄原因。

## 已知環境雷

- 新增帶 `class_name` 的腳本後，需要先跑一次 `Godot --headless --import --path .` 讓全域類別註冊，否則會出現 `Identifier "X" not declared` 的假錯誤。
- `Godot --headless --check-only` 在這個環境裡會卡住不退出，改用 `Godot --headless --quit-after N --path .` 跑幾個 frame 來驗證腳本語法/runtime 錯誤。
- `project.godot` 的 `run/main_scene` 是 `Lobby.tscn`，headless 預設跑的是大廳；要驗證戰鬥場景本身要另外指定 `Godot --headless --quit-after N scenes/Main.tscn`。
- 無頭模式無法模擬滑鼠/鍵盤輸入，超魔專長輸入手感、輪盤視覺效果務必在 editor 裡實際跑一次確認，不能只靠 headless 檢查判斷「做完了」。角度類邏輯（輪盤選取判定）可以寫一次性驗證腳本用 `Godot --headless --script path.gd` 跑數學驗證，但跑完記得清掉，不要留在專案裡常駐。
- **`_init()` 裡直接寫繼承自父類別的 `@export` 欄位會編譯失敗**（`Identifier not found: <欄位名>`），即使欄位確實宣告在父類別上——必須加 `self.` 明確限定（`self.apply_mode = ...`），同一個欄位如果是宣告在「這個類別自己身上」則不需要 `self.` 也能在 `_init()` 裡直接賦值（`DamageEffect.gd` 的 `min_amount`/`max_amount` 就是這樣，照樣能用）。只在「`_init()` 賦值繼承來的欄位」這個特定組合才會炸，其餘地方（`_ready()`、一般方法）存取繼承欄位不受影響。踩過一次見 `scripts/spells/InvisibilityEffect.gd`/`SpeedBuffEffect.gd`。
- **這個環境裡 MCP 連線偶爾會卡在 `AUTH_FAILED`（`registry entry has no token path`）**，通常是在跑 `Godot --headless --import --path .`（重新註冊全域類別用）之後發生——那個指令會另外開一個 Godot 處理程序去註冊 MCP registry，可能把正在跑的 editor 那份 token 蓋掉。`script_check`／`game_start`／`game_stop` 不受影響還能用，但 `execute_code`／`runtime_screenshot`／`runtime_get_script_vars` 這類真正連進 runtime 的工具會持續失敗，agent 自己重試/重開 `game_start` 沒用，需要使用者手動重新連接 editor 的 MCP 才能恢復。

## 工作方式

- 這個專案目前由單人（配 AI agent 協作）開發，PoC/Demo 階段優先驗證手感與架構方向，不要在數值還沒定案前過度打磨。
- 改動核心機制（超魔專長判定、法術架構、法術格系統）後，若有新的設計決策或踩到的坑，補回對應的 `docs/*.md`，不要只改程式碼不留記錄——這幾份文件就是給未來的你/其他 agent 看的「為什麼長這樣」的真相來源。
- 動手前若發現使用者的描述跟現有文件/程式碼有衝突（例如把「符紋」講成「超魔專長」、把「每把法術配符紋」講成「配置法術格」），先確認是不是範圍/設計已經調整過，不要假設是自己記錯，也不要默默照舊邏輯做——先問清楚再動工。
