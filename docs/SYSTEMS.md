# 現有系統技術參考

> 這份文件收錄**跟這次戰鬥核心轉型（`docs/GDD.md`）無關、現在仍然持續運作的系統**的技術細節——原本分散在 `docs/DESIGN.md`（2026-10-13 已刪除）裡，那份文件混雜了已經刪除的舊戰鬥系統（超魔專長序列輸入、法術格大廳、輪盤）跟這些還活著的部分，容易讓人誤判哪些還有效。這裡只留下確認還在用的。法術系統架構（`Spell`/`SpellDelivery`/`SpellEffect`）另外記錄在 `docs/SPELL_SYSTEM.md`，開發計畫見 `docs/DEMO_PLAN.md`。

---

## 1. 基礎 Dash（`Player.gd`）

空白鍵觸發，不走 `Spell`/`SpellDelivery` 架構、不佔用法術欄位、沒有冷卻。方向取按下當下的 WASD（跟滑鼠瞄準方向無關），站著不動時用 `last_move_direction`（上一次有實際移動輸入的方向）。`DASH_DURATION`（0.12秒）內用 `DASH_SPEED` 持續呼叫 `move_and_slide()`，會自然貼牆滑行、碰到牆就停下，不是瞬移。`DASH_SPEED` 直接用 `50.0 / DASH_DURATION` 算（衝刺距離是 50px），數值本身就是「50px」這個意圖，不是另外存一個容易跟 `DASH_DURATION` 脫鉤的獨立常數。吟唱中、衝刺進行中都不會觸發/疊加。

目前只有這個基礎分支——裝備位移類法術時改走 `AoETargetingDelivery` 選點移動施法者座標的分支，從來沒有對應法術驗證過，新系統（`docs/FIRE_PROTOTYPE.md` 的「火焰撤離」節點）如果要做位移類效果，這個分支可以參考，但目前還是空的。

---

## 2. 玩家 HP／死亡（`Player.gd`／`scripts/ui/HealthOrb.gd`／`scripts/ui/DeathScreen.gd`）

- `Player.gd`：`const MAX_HP := 100.0`／`var hp`／`var is_dead`。`take_damage(amount)` 直接扣血、clamp 在 0、`hp_changed(ratio)` 訊號給 UI。血量歸零呼叫 `_die()`：設 `is_dead = true`、停止吟唱/衝刺/移動、emit `died` 訊號。`_physics_process()`/`_input()` 開頭都加了 `if is_dead: return`，死亡後整個不再回應任何輸入。
- `scripts/ui/HealthOrb.gd`＋`scenes/ui/HealthOrb.tscn`：PoE/暗黑風格「液體填充圓球」，用 `TextureProgressBar`（`fill_mode = FILL_BOTTOM_TO_TOP`、`nine_patch_stretch = true` 讓材質自動縮放填滿容器）取代手刻多邊形，液體從下往上淹沒的效果完全靠裁切材質本身做出來。液面只在 `hp_changed` 訊號真的觸發時才會變化，平常不會有任何浮動/呼吸動畫（故意的，避免讓人誤以為血量在變動）。`texture_under`／`texture_progress` 共用同一張圖（`art/ui/health_orb_fill.png`，目前是一張純紅色實心圓形 PNG，測試材質管線用，之後要換真的美術素材只要換掉這張圖，不用動程式碼）。只做血量這一顆，沒有對稱的第二顆資源球。跟 `CastBar.gd` 同一個「呼叫端 `bind(player)` 一次、自動訂閱訊號」的共用元件模式。
- `scripts/ui/DeathScreen.gd`＋`scenes/ui/DeathScreen.tscn`：監聽 `player.died`，顯示半透明黑底＋按鈕，同時 `get_tree().paused = true`。沒有「你死了」文字，只有按鈕。**2026-10-13 更新**：按鈕原本切回大廳（`Lobby.tscn`），大廳刪除後改成重開目前場景（`scenes/SpellTestRange.tscn`），`RESPAWN_SCENE` 常數（原名 `LOBBY_SCENE`，節點名稱 `LobbyButton` 還沒跟著改）。這個節點＋按鈕都要 `process_mode = PROCESS_MODE_ALWAYS` 才能在暫停時仍然接收點擊。

**踩到的環境雷**：外部腳本新增的圖片資源，Godot 編輯器不會自動匯入，需要用 MCP 的 `editor_refresh` **不帶路徑參數**（觸發全專案掃描，不是只傳 `file_paths` 的 O(1) 單檔模式）才會真的產生 `.import` 檔案；而且就算匯入完成，已經在跑的遊戲 session 讀到的還是舊的，要 `game_stop`+`game_start` 重開一次遊戲才會讀到剛匯入好的資源。跟 `CLAUDE.md`「已知環境雷」記錄的「新增 `class_name` 腳本要先匯入」同一類問題，只是觸發方式不同。

---

## 3. 視覺風格

Magicka 調性：Q 版、鮮豔、誇張特效的奇幻風格。地板/場地用 Godot `_draw()` 程式繪圖，角色改用 AI 生成的 sprite 動畫（見 `docs/ROADMAP.md` §2.1a），特效用 `CPUParticles2D` 動態生成。

### 3.1 3/4 俯視角慣例
地板維持純俯視方格座標系（不是真等角投影），角色/怪物/地面特效走「有正面、帶高度感」的畫法：
- **腳下陰影**：壓扁橢圓（多邊形近似），讓角色站在地上而不是貼平的貼紙。
- **身體左右分色**（程式繪圖角色才需要，例如 `TestDummy.gd`）：同一塊造型左右兩片不同明暗（暗側 `darkened(0.25)`），模擬最簡單的立體感。

地板磚塊、爆炸特效、範圍選取圈延伸同一套「有高度感」語言但不做真投影：爆炸/範圍特效壓扁成橢圓，壓扁係數跟判定邏輯統一讀 `scripts/core/GroundProjection.gd`（`class_name GroundProjection`），不是各檔案各放一份 `GROUND_SQUASH` 常數。

**`GroundProjection` 身兼兩個角色：(1) 視覺壓扁的幾何工具，(2) 範圍判定的距離公式**——`squash`（目前0.5）是唯一的壓扁係數來源。`projected_distance(a, b)`（Y方向差距除以 squash 再算距離，取代 `distance_to()`/`.length()`）確保「視覺上畫的橢圓範圍」跟「程式判定的命中範圍」是同一個形狀，不會出現視覺壓扁了但判定還是用正圓的落差（這是 2026-10-11 修過的真實 bug）。`projected_velocity(direction, speed)`：上下方向移動的世界座標速度乘上 `squash`（變慢）——因為 `projected_distance()` 讓上下方向判定範圍天生比左右方向更容易進入（Y差距影響力被放大），移動速度對應變慢才能讓「走進某個範圍要花多久」不管從哪個方向接近都一致，`Player._process_movement()` 已經套用。`ellipse_point(center, radius, angle)`／`ellipse_points(center, radius, segments)`／`clamp_to_radius()`／`clamp_to_ring()`／`ellipse_normal()`：給橢圓邊界的座標/夾限/反彈法線用（**不能**用「圓心→該點」方向算法線，那是正圓公式，橢圓上任一點的法線方向跟半徑方向不同）。

**刻意不套這套壓扁系統的東西**：角色/投射物的實際碰撞形狀（`CircleShape2D` 全部維持圓形——範圍判定是程式碼手動算距離，碰撞是 Godot 物理引擎的實際形狀重疊，兩者是不同機制，碰撞形狀都很小，沒必要冒多邊形橢圓近似的複雜度/效能風險）；Dash/Knockback（瞬間物理反饋，不套這個系統）；`MagicFX.make_sparkle_trail()` 的拖尾粒子（軌跡在空中飛，不需要壓扁）。

**2026-10-13 現況**：`scripts/core/Arena.gd`（原本的三環場地結構：玩家場地/縫隙/boss環道，整個套了壓扁橢圓）沒有被任何場景使用了（`Main.tscn` 已刪除），是孤兒腳本——裡面定義的 `ARENA_CENTER`/`PLAYER_ZONE_RADIUS`/`BOSS_RING_INNER_RADIUS`/`ARENA_RADIUS`/`BOSS_TRACK_RADIUS` 這些 `const` 還被 `SpellProjectile.gd` 的牆壁反彈判斷讀取（見 `docs/SPELL_SYSTEM.md` §3.1），但因為沒有場景有 `Arena` 節點，那條判斷式永遠走不到。腳本本身沒刪（可能之後新戰鬥場地會重新設計/沿用部分邏輯），只是目前完全不在運作。`scenes/SpellTestRange.tscn` 目前用的地板是 `scripts/core/TestRangeFloor.gd`（簡化版圓形地板+同心圓參考線，跟 `Arena.gd` 無關，不分玩家/怪物場地）。

### 3.2 共用特效（`MagicFX.gd`）
`class_name MagicFX`，三個 static 工具方法：`spawn_burst()`（爆發粒子）、`make_sparkle_trail()`（拖尾粒子，不套壓扁）、`spawn_explosion_ring()`（範圍特效用的擴張淡出圈）。壓扁係數讀 `GroundProjection.squash`。

### 3.3 解析度
`project.godot`：`viewport_width/height = 1280x720`（設計基準解析度），`stretch/mode = "canvas_items"`，`stretch/aspect = "keep"`。

---

## 4. 專案結構（2026-10-13 現況）

```
spellcraft-poc/
├── project.godot                       # Godot 4.6 專案設定，input map，啟動場景＝SpellTestRange.tscn
├── scenes/
│   ├── SpellTestRange.tscn             # 目前唯一的場景（test arena），也是 run/main_scene
│   ├── entities/
│   │   ├── Player.tscn                 # CharacterBody2D + CollisionShape2D + Camera2D + SpriteAnimator + CastPreview + AoETargetingReticle
│   │   └── TestDummy.tscn              # 測試用假敵人（純吃傷害的靶子）
│   ├── spells/
│   │   ├── SpellProjectile.tscn        # 直線投射物共用場景
│   │   └── HomingMissile.tscn          # 追蹤飛彈共用場景（目前沒有法術使用）
│   └── ui/
│       ├── CastBar.tscn／HealthOrb.tscn／DeathScreen.tscn
├── scripts/
│   ├── SpellTestRange.gd               # test arena 的場景邏輯：F3 除錯面板骨架
│   ├── core/
│   │   ├── Arena.gd                    # 孤兒腳本（舊三環場地結構，沒有場景在用，見 §3.1）
│   │   ├── TestRangeFloor.gd           # test arena 目前實際用的地板
│   │   ├── GroundProjection.gd         # 橢圓壓扁系統（視覺+判定共用）
│   │   └── CastPreview.gd              # 吟唱範圍預覽（掛在 Player.tscn 底下，目前因為沒有法術在吟唱狀態不會真的畫出東西）
│   ├── entities/
│   │   ├── Player.gd                   # 移動、HP/死亡、Dash、sprite動畫切換、（過渡期）吟唱狀態機骨架
│   │   ├── PlayerSpriteAnimator.gd     # AnimatedSprite2D 動畫切換，見 docs/ROADMAP.md §2.1a
│   │   └── TestDummy.gd
│   ├── fx/
│   │   └── MagicFX.gd
│   ├── ui/
│   │   ├── CastBar.gd／HealthOrb.gd／DeathScreen.gd
│   │   └── AoETargetingReticle.gd／AoETargetingTrail.gd  # 選點介面，目前沒有法術在用（見 SPELL_SYSTEM.md §3.3）
│   └── spells/                         # 見 docs/SPELL_SYSTEM.md 完整說明
└── （resources/spells/ 目前是空的——舊的6把法術 .tres 已刪除，新的火系法術圖譜資源見 docs/DEMO_PLAN.md §4，還沒建立）
```

### 4.1 Input Map（`project.godot`）
| Action | 綁定 | 現況 |
|---|---|---|
| `move_up/down/left/right` | W/A/S/D（實體鍵碼） | 現役 |
| `cast_spell` | 滑鼠左鍵 | 現役，但語意正在改——`docs/DEMO_PLAN.md` Phase 1 之後會變成「一般狀態＝近戰/蓄力火球，專注狀態＝施放目前節點」，不是舊的「按住吟唱」 |
| `instant_cast` | 滑鼠右鍵 | 現役，但語意正在改——原本是法術瞬發，`docs/DEMO_PLAN.md` Phase 1 之後會變成「進入/退出專注狀態」 |

F3（除錯面板）、空白鍵（Dash）都不走 Input Map，直接在腳本用符號常數判斷（`Input.is_physical_key_pressed()`/`event.physical_keycode`），避免手刻 `InputEventKey` 設錯 keycode 卻不會報錯的風險。

### 4.2 執行環境
Godot 4.6.2.stable，渲染後端 `gl_compatibility`。其餘環境雷（headless 限制、`class_name` 腳本要先匯入等）記錄在 `CLAUDE.md`「已知環境雷」，不重複寫在這裡。
