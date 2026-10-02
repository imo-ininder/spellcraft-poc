# 專案說明（給 AI agent）

Spellcraft PoC：法師版「魔物獵人」，純 PVE。Godot 4.6.2，GDScript。

## 先讀這些

動手改程式碼前，先讀 `docs/DESIGN.md` 第3節（超魔專長序列輸入系統，文件裡仍沿用舊名「符紋」描述判定邏輯本身，§4.7 說明了這只是用詞歷史，概念完全一致）——這是整個專案最核心、最容易被誤改的邏輯，裡面記錄了時間窗口數值的演進歷史與為什麼現在這樣設計。不要只看程式碼就假設行為合理，`DESIGN.md` 裡記錄了好幾個「表面上像 bug 但其實是設計決定」的案例。

- `docs/DESIGN.md` — 已拍板的核心機制、決策歷史、已知行為邊界，§4.7 記錄了法術格系統/大廳/GameState 的落地細節
- `docs/SPELL_SYSTEM.md` — 法術系統架構，`Spell`/`SpellDelivery`/`SpellEffect`/`ProjectileImpact` 已實作落地（§8 補充記錄實作時的具體決定），§9 的 capability 相容性機制規劃中但刻意尚未實作
- `docs/DEMO_GOALS.md` — 目前這一階段要做的 Demo 範圍與驗收標準，這是當前最新的工作目標，§2.5/§4 記錄了法術格系統取代原本「每把法術各自配符紋」設計的範圍調整
- `docs/ROADMAP.md` — 美術資源遷移路徑、玩法擴充清單

## 目前進度（流程：Lobby → Main）

啟動場景是 `scenes/Lobby.tscn`（大廳，配置法術格），按「出發」後切換到 `scenes/Main.tscn`（戰鬥）。已實作：超魔專長吟唱判定、三把法術（火球術/力場波/雷電箭，各自不同 `SpellDelivery`）、法術切換輪盤（支援任意把數）、基礎 Dash、右鍵瞬發、怪物簡易AI、法術格系統（固定6格，`GameState` autoload 跨場景傳遞）。**還沒做**：真實HP/死亡/結算畫面（玩家被打只閃光不扣血，怪物死亡會重置滿血）、buff類法術的duration機制、位移類法術（目前只有基礎Dash）、美術/音樂（全部仍是`_draw()`程式繪圖）。

## 架構規則

1. **Resource 只放設定值，不放運行時狀態**（CD、吟唱進度、buff 剩餘時間一律存在角色節點身上）。這條規則在 `SPELL_SYSTEM.md` 裡反覆強調，因為 Godot 的 Resource 是共享引用，不是值型別。
2. **目錄依領域分類**：`entities/`（角色、怪物）、`spells/`（法術相關）、`core/`（場地/環境）、`fx/`（共用特效）、`ui/`（輪盤、選點介面）、`state/`（GameState autoload）。新增檔案時歸到對應資料夾，不要全部塞進同一層。
3. **新增法術必須加進 `GameState.gd:CATALOG`**，否則大廳跟輪盤都不會出現這把法術——這是目前唯一的法術總表來源。
4. **超魔專長是角色永久天生會的被動，不是裝備/配置給特定法術的東西**（`Player.gd:ARCANE_FEATS`）。大廳要配置的是法術（`Spell.slot_cost` 佔用固定6格），不是專長。別把這兩個搞混，之前有過一輪方向調整才確定下來。
5. **超魔專長/法術數值目前仍是 Demo 階段的示範值**，不是最終平衡數字，調整前先確認 `docs/DESIGN.md` §3.6、§4.7 是否已記錄原因。

## 已知環境雷

- 新增帶 `class_name` 的腳本後，需要先跑一次 `Godot --headless --import --path .` 讓全域類別註冊，否則會出現 `Identifier "X" not declared` 的假錯誤。
- `Godot --headless --check-only` 在這個環境裡會卡住不退出，改用 `Godot --headless --quit-after N --path .` 跑幾個 frame 來驗證腳本語法/runtime 錯誤。
- `project.godot` 的 `run/main_scene` 是 `Lobby.tscn`，headless 預設跑的是大廳；要驗證戰鬥場景本身要另外指定 `Godot --headless --quit-after N scenes/Main.tscn`。
- 無頭模式無法模擬滑鼠/鍵盤輸入，超魔專長輸入手感、輪盤視覺效果務必在 editor 裡實際跑一次確認，不能只靠 headless 檢查判斷「做完了」。角度類邏輯（輪盤選取判定）可以寫一次性驗證腳本用 `Godot --headless --script path.gd` 跑數學驗證，但跑完記得清掉，不要留在專案裡常駐。

## 工作方式

- 這個專案目前由單人（配 AI agent 協作）開發，PoC/Demo 階段優先驗證手感與架構方向，不要在數值還沒定案前過度打磨。
- 改動核心機制（超魔專長判定、法術架構、法術格系統）後，若有新的設計決策或踩到的坑，補回對應的 `docs/*.md`，不要只改程式碼不留記錄——這幾份文件就是給未來的你/其他 agent 看的「為什麼長這樣」的真相來源。
- 動手前若發現使用者的描述跟現有文件/程式碼有衝突（例如把「符紋」講成「超魔專長」、把「每把法術配符紋」講成「配置法術格」），先確認是不是範圍/設計已經調整過，不要假設是自己記錯，也不要默默照舊邏輯做——先問清楚再動工。
