# 專案說明（給 AI agent）

Spellcraft PoC：法師版「魔物獵人」，純 PVE。Godot 4.6.2，GDScript。

## 先讀這些

動手改程式碼前，先讀 `docs/DESIGN.md` 第3節（符紋序列輸入系統）——這是整個專案最核心、最容易被誤改的邏輯，裡面記錄了時間窗口數值的演進歷史與為什麼現在這樣設計。不要只看程式碼就假設行為合理，`DESIGN.md` 裡記錄了好幾個「表面上像 bug 但其實是設計決定」的案例。

- `docs/DESIGN.md` — 已拍板的核心機制、決策歷史、已知行為邊界
- `docs/SPELL_SYSTEM.md` — 法術系統架構提案（尚未實作，只有 PoC 現有的 Dictionary 寫法）
- `docs/DEMO_GOALS.md` — 目前這一階段要做的 Demo 範圍與驗收標準，這是當前最新的工作目標
- `docs/ROADMAP.md` — 美術資源遷移路徑、玩法擴充清單

## 架構規則

1. **Resource 只放設定值，不放運行時狀態**（CD、吟唱進度、buff 剩餘時間一律存在角色節點身上）。這條規則在 `SPELL_SYSTEM.md` 裡反覆強調，因為 Godot 的 Resource 是共享引用，不是值型別。
2. **目錄依領域分類**：`entities/`（角色、怪物）、`spells/`（法術相關）、`core/`（場地/環境）、`fx/`（共用特效）。新增檔案時歸到對應資料夾，不要全部塞進同一層。
3. **符紋/法術數值目前仍是 PoC 階段的示範值**（`Player.gd` 的 `RUNE_COMBOS`），不是最終平衡數字，調整前先確認是否有文件記錄原因。

## 已知環境雷

- 新增帶 `class_name` 的腳本後，需要先跑一次 `Godot --headless --import --path .` 讓全域類別註冊，否則會出現 `Identifier "X" not declared` 的假錯誤。
- `Godot --headless --check-only` 在這個環境裡會卡住不退出，改用 `Godot --headless --quit-after N --path .` 跑幾個 frame 來驗證腳本語法/runtime 錯誤。
- 無頭模式無法模擬滑鼠/鍵盤輸入，符紋輸入手感、視覺效果務必在 editor 裡實際跑一次確認，不能只靠 headless 檢查判斷「做完了」。

## 工作方式

- 這個專案目前由單人（配 AI agent 協作）開發，PoC/Demo 階段優先驗證手感與架構方向，不要在數值還沒定案前過度打磨。
- 改動核心機制（符紋判定、法術架構）後，若有新的設計決策或踩到的坑，補回對應的 `docs/*.md`，不要只改程式碼不留記錄——這幾份文件就是給未來的你/其他 agent 看的「為什麼長這樣」的真相來源。
