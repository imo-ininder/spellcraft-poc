# Spellcraft PoC

法師版即時 PvE 魔法動作遊戲。核心玩法正在轉型中（2026-10-13）：右鍵進入專注狀態消耗連續資源換取 Bullet Time，用方向鍵符文沿預先設計的法術圖譜切換目前的法術節點，任意節點皆可施放；一般狀態下用普通攻擊三連段／蓄力火球維持戰鬥節奏。詳見 `docs/GDD.md`。

- 引擎：Godot 4.6.2
- 設計文件：見 `docs/`
  - `GDD.md` — 整體戰鬥方向設計文件（符文圖譜＋專注值/子彈時間）
  - `FIRE_PROTOTYPE.md` — 第一個原型的具體規格（符文語意、火系法術圖譜、數值）
  - `DEMO_PLAN.md` — **實際的開發計畫**，分 Phase 定義範圍/驗收標準/進度，動手前先讀這份
  - `SPELL_SYSTEM.md` — 法術系統架構（`Spell`/`SpellDelivery`/`SpellEffect`/`ProjectileImpact`），仍在使用
  - `SYSTEMS.md` — 跟戰鬥核心轉型無關、持續運作中的系統技術參考（Dash、HP/死亡、視覺風格、專案結構）
  - `ROADMAP.md` — 美術資源遷移路徑與玩法擴充清單
  - `BOSS_DESIGN.md`／`DESIGN.md`／`DEMO_GOALS.md` 已刪除（舊戰鬥系統的設計文件，內容已拆解整理進上面幾份文件）

## 執行

用 Godot 4.6 開啟專案根目錄即可，主場景為 `scenes/SpellTestRange.tscn`（目前專案唯一的場景）。

無頭檢查腳本語法（無法測試輸入手感，須用 editor 實際操作）：

```
Godot --headless --import --path .
Godot --headless --quit-after 240 --path .
```

## 目錄結構

```
docs/              設計文件
scenes/
  SpellTestRange.tscn   唯一場景（test arena），也是 run/main_scene
  entities/        角色、怪物場景（Player、TestDummy）
  spells/          投射物等法術相關場景
  ui/              CastBar／HealthOrb／DeathScreen／FocusHUD
scripts/
  SpellTestRange.gd
  core/            場地/環境邏輯（GroundProjection、TestRangeFloor；Arena.gd 目前是孤兒腳本，見 SYSTEMS.md）
  entities/        角色邏輯（Player、PlayerSpriteAnimator、TestDummy）
  spells/          Spell/SpellDelivery/SpellEffect/ProjectileImpact 架構 + SpellGraphNode/SpellGraph（法術圖譜），見 docs/SPELL_SYSTEM.md
  ui/              CastBar、HealthOrb、DeathScreen、FocusHUD、AoETargetingReticle（目前沒有法術在用）
  fx/              共用特效工具（MagicFX）

resources/spells/fire/   火系法術圖譜資源（fire_graph.tres + 7 個節點 .tres，目前共用一個佔位 Spell）
```
