# Spellcraft PoC

法師版「魔物獵人」，純 PVE。核心玩法：吟唱法術時，在吟唱時間內用方向鍵打出符紋指令序列，即時決定本次法術的強化效果。

- 引擎：Godot 4.6.2
- 設計文件：見 `docs/`
  - `DESIGN.md` — 已拍板的核心機制與決策歷史（符紋輸入判定、時間窗口演進、已知行為邊界）
  - `SPELL_SYSTEM.md` — 法術系統架構提案（Spell / SpellDelivery / SpellEffect）
  - `DEMO_GOALS.md` — 目前開發目標的 Demo 範圍與驗收標準
  - `ROADMAP.md` — 美術資源遷移路徑與玩法擴充清單

## 執行

用 Godot 4.6 開啟專案根目錄即可，主場景為 `scenes/Main.tscn`。

無頭檢查腳本語法（無法測試輸入手感，須用 editor 實際操作）：

```
Godot --headless --import --path .
Godot --headless --quit-after 240 --path .
```

## 目錄結構

```
docs/              設計文件
scenes/
  Main.tscn        主場景
  entities/        角色、怪物場景
  spells/          投射物等法術相關場景
scripts/
  Main.gd
  core/            場地/環境邏輯（Arena）
  entities/        角色、怪物邏輯（Player、TargetDummy）
  spells/          法術發射邏輯（SpellProjectile，未來 Spell/Delivery/Effect 歸此）
  fx/              共用特效工具（MagicFX）
```
