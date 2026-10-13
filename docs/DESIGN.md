# Spellcraft PoC 設計文件

> 法師版「魔物獵人」，純 PVE。核心機制：吟唱法術時，在吟唱時間內用方向鍵打出超魔專長指令序列，即時決定本次法術的強化效果。打快可以多塞幾個專長但有打斷/打錯風險，打慢求穩但強化數量受限。

---

## 1. 核心機制：超魔專長序列輸入系統

### 1.1 吟唱流程
1. 玩家按住滑鼠左鍵（`cast_spell`）→ 進入吟唱狀態，開始倒數裝備中法術的 `cast_time`，角色鎖定移動。
2. 吟唱期間 WASD 不再移動角色，改為輸入方向鍵：上(U)/下(D)/左(L)/右(R)。
3. 每個按鍵接到緩衝字串 `combo_buffer` 後面，比對 `GameState.ARCANE_FEATS` 組合表。
4. 命中完整組合 → 觸發對應效果，疊加進 `accumulated_feats`。
5. 法術只在吟唱時間自然倒數結束時發動（`_finish_casting`），用目前累積的所有專長效果計算最終數值後發射。
6. 吟唱時間結束前鬆開左鍵＝取消整個吟唱（`_cancel_casting`）：不會發射法術，已累積專長全部作廢。

### 1.2 序列比對邏輯：前綴匹配 + Pending 機制
支援短序列與長序列共享前綴（例如 `UU` 和 `UULR`），讓玩家能在輸入過程中自然決定要不要賭更強效果。每次新按鍵組成 `attempt = combo_buffer + key` 後分四種情況處理（`Player.gd:_handle_combo_key`）：

| 情況 | 判定 | 行為 |
|---|---|---|
| `attempt` 是完整序列，且不是任何更長序列的前綴 | 單純完整命中 | 立即 `_commit_combo`：套用效果、噴特效、清空緩衝 |
| `attempt` 是完整序列，同時也是更長序列的前綴 | 曖昧狀態 | 存成 `pending_combo`，不立即觸發，繼續等待下一鍵 |
| `attempt` 不是完整序列，但是某個更長序列的前綴 | 半成品 | 更新 `combo_buffer = attempt`，清空 `pending_combo`，繼續等待 |
| `attempt` 既非完整序列，也不是任何前綴 | 無效延伸 | `_fail_combo()`：清空緩衝，灰色失敗特效 |

每個 frame 在 `_process_casting` 中檢查「距離上次按鍵過了多久」：
- 有 `pending_combo` 且等待超過 `COMBO_MAX_GAP` → 確認觸發 pending 序列（不算失敗）。
- 沒有 `pending_combo`、只是半成品前綴，等待超過 `COMBO_MAX_GAP` → 判定失敗。

### 1.3 時間窗口
唯一的時間常數：`COMBO_MAX_GAP = 0.15`（`Player.gd`）。按鍵可以盡量快，只要在 0.15 秒內接上下一鍵就能持續延伸序列；超過 0.15 秒沒接鍵，才會判定「停在這裡確認拿到」或「失敗」。沒有下限限制——系統不懲罰玩家手速快，只懲罰拖太久不接下一鍵。

### 1.4 失敗判定
只有以下兩種情況算失敗（`_fail_combo`）：
1. 按下的鍵使緩衝區變成一個既非完整序列、也不是任何序列前綴的字串。
2. 緩衝區是一個尚未完整的前綴（沒有 pending），且超過 0.15 秒沒有輸入下一鍵。

反之，緩衝區已經是完整序列（進入 pending）時超時，代表「確認拿到」，不算失敗。

### 1.5 目前的超魔專長表
定義於 `GameState.gd:ARCANE_FEATS`：

| 按鍵序列 | 效果 | 數值 |
|---|---|---|
| `UU`（上上） | +傷害 | damage_mult +0.5 |
| `UDU`（上下上） | +強力傷害 | damage_mult +1.2 |
| `UULR`（上上左右） | +終極爆發 | damage_mult +1.8（與 `UU` 共享前綴） |
| `RR`（右右） | +吟唱速度 | cast_speed_bonus +0.5 |
| `LL`（左左） | -吟唱速度 | cast_speed_bonus -0.5 |

角色永久天生會全部，不綁定特定法術，吟唱任何法術時都能打出同一組序列；有沒有實際作用取決於目前裝備的法術吃不吃得到該效果類型。Demo 階段固定全部解鎖，不做學習/解鎖/強化介面。

傷害類專長（`damage_mult`）疊加方式：對「目前已累加的傷害值」疊加百分比，不是對最終值相乘，疊加順序就是打出專長的順序。

### 1.6 吟唱速度調整公式
`RR`/`LL` 不經過發射數值（`stats`），而是在 `_commit_combo` 當下直接修改 `Player.gd:cast_speed_bonus`，立即影響讀條消耗速度。`cast_speed_bonus` 是調整值總和（0.0＝正常），實際吟唱時長：

```
實際吟唱時長 = base_cast_time / (1 + cast_speed_bonus)
```

`cast_speed_bonus = 1.0`（+100%）時長變成一半。逐 frame 消耗寫成 `cast_timer -= delta * (1 + cast_speed_bonus)`（消耗速率跟時長互為倒數）。`cast_speed_bonus` 下限 clamp 在 `-0.9`，避免疊加多個減速效果讓 `(1+cast_speed_bonus)` 碰到 0 或負數。

**2026-10-11：讀條元件抽成 `scenes/ui/CastBar.tscn`＋`scripts/ui/CastBar.gd`（`class_name CastBar`）**——進度條＋倒數秒數文字（`"%.2fs"`，顯示的是「照目前施法速度實際還剩幾秒」：`(1-ratio)*cast_time / (1+cast_speed_bonus)`，不是法術固定的基礎秒數，`RR`/`LL` 中途觸發時數字會直接跳到新速度算出來的值）。`Main.tscn`（正式戰鬥）／`scenes/SpellTestRange.tscn`（法術測試場）都用 `instance=` 掛同一個場景，呼叫端只要在 `_ready()` 呼叫一次 `cast_bar.bind(player)`。這個元件**刻意不**套用專案裡「行為共用、程式碼各自複製」的慣例（那套慣例是給 `_find_player()` 這種極小、極穩定、幾乎不會再改的工具函式用的）——讀條的呈現邏輯會持續被調整，一開始各自複製了一份，兩邊很快就對不上，所以改成共用場景。之後要調整讀條的呈現方式，只要改 `CastBar.gd` 這一個檔案。

**2026-10-12：`CastPreview.gd`（吟唱中的範圍預覽）／`AoETargetingReticle.gd`（選點確認介面）改掛在 `scenes/entities/Player.tscn` 底下，不再掛在 `Main.tscn`／`SpellTestRange.tscn` 場景根層級**——背景：`CastPreview.gd` 最初只接進 `SpellTestRange.tscn`，忘了同步接進 `Main.tscn`，導致正式戰鬥完全沒有這個功能，被使用者抓到；當下的補救是在 `Main.tscn` 也手動加一份節點＋`bind()`，但使用者追問「每開一個 tscn 就要重新檢查一次？」，指出這只是治標（靠人記得檢查），沒解決「這兩個場景各自維護一份幾乎一樣的節點配置＋綁定程式碼」這個根本的復用性問題。

既然 `Player.tscn` 本身就已經是兩個場景共用的可重用場景（`instance=ExtResource(...)`），`CastPreview`/`AoETargetingReticle` 這類「純粹跟著施法者本人走、不依賴場景其他結構」的節點，改成直接掛在 `Player.tscn` 底下，任何用到 `Player.tscn` 的場景自動帶有這個功能，不需要每個場景各自手動補節點／各寫一行 `bind()`——少一個環節，就少一種「忘記接」的方式，不是靠記憶體/checklist 去防止忘記。具體改動：
- 兩個腳本都拿掉外部 `bind(player)` API，改成 `_ready()` 裡 `player = get_parent()`／`caster` 直接是自己的父節點。
- `_draw()` 原本直接拿 `global_position` 當畫圖座標（因為以前掛在場景根層級、原點跟世界座標原點重合），現在原點跟著 Player 移動，所有畫圖座標要先 `to_local()` 轉換。
- `AoETargetingDelivery.fire()` 原本用 `caster.get_tree().current_scene.get_node("AoETargetingReticle")` 這種寫死節點名稱＋假設場景結構的方式找選點介面，改成 `caster.get_node("AoETargetingReticle")`（`caster` 就是施法的 Player，這個節點現在是它的直屬子節點）——連「場景根層級必須剛好有一個這個名字的節點」這個隱性假設也一併拿掉。

**判斷準則**：一個支援性節點該掛在 `Player.tscn` 底下、還是掛在場景根層級，看它是「跟著某個特定施法者走的個體行為/視覺」還是「跟場景佈局相關的 HUD」。`CastPreview`/`AoETargetingReticle` 是前者（純世界座標、只服務這一個 Player）；`CastBar` 是後者（`CanvasLayer` 底下的 UI 元件，位置/排版兩個場景目前故意不同，見上一條記錄），所以 `CastBar` 維持場景各自 `instance=` 掛一份、不跟著搬進 `Player.tscn`，不是這次漏掉。

---

## 2. 法術格系統與大廳

### 2.1 法術格
角色固定 6 格法術欄位（`GameState.TOTAL_SLOTS`），每把法術依 `Spell.slot_cost` 佔用不同格數。配置的單位是法術，不是超魔專長——超魔專長天生全部解鎖、不需配置。玩家在大廳場景（`scenes/Lobby.tscn`）勾選要帶上戰場的法術，超過格數預算時直接拒絕這次勾選並反紅閃一下。

### 2.2 GameState（autoload 單例，`scripts/state/GameState.gd`）
- `TOTAL_SLOTS = 6`。
- `CATALOG`：法術 `.tres` 路徑總表，新增法術只需要改這裡，大廳跟輪盤都會自動反映。
- `ARCANE_FEATS`：超魔專長組合表，`Player.gd` 跟大廳的超魔專長一覽分頁都讀這份表。
- `equipped_spells`：大廳勾選結果，`Lobby.gd` 按「出發」時寫入，`Player.gd:_ready()` 讀取。
- `default_loadout()`：`equipped_spells` 為空時的 fallback，依 `CATALOG` 順序貪婪塞滿 6 格、塞不下的法術跳過——讓不經大廳直接開 `Main.tscn` 測試的工作流程不受影響。

`project.godot` 的 `run/main_scene` 是 `Lobby.tscn`；`Main.tscn` 是戰鬥場景，透過 `Lobby.gd:_on_depart_pressed()` 的 `change_scene_to_file()` 切換過去。

### 2.3 大廳 UI
左半邊是角色形象（`CharacterPortrait.gd`）＋目前裝備法術文字列表；右半邊是分頁清單（法術配置／超魔專長／三個「敬請期待」佔位）。選分頁會疊一層 `DimOverlay`（78%不透明黑）+ 對應的浮動面板，兩個面板互斥（開一個會先關閉另一個，避免鍵盤 Tab 焦點繞過視覺遮擋同時開啟兩個面板）。

**法術配置分頁**（`SpellConfigPanel`）：左側 `GridWindow` 顯示法術格視覺化（`SlotGrid.gd`，已用/總格數）；下半部平時顯示目前選中法術的詳細說明（名稱、佔用格數、施放時間、`Spell.description` 手寫說明文字），按住 Ctrl 時切換成法術輪盤排序預覽（`LoadoutWheelPreview.gd`，拖拽交換法術在戰鬥輪盤上的順序，角度基準與戰鬥輪盤一致：正上方為第0格、`TAU/n` 等分、順時針）。右側 `SpellWindow` 是可捲動的法術清單（`ScrollContainer`），滑鼠 hover 或鍵盤 focus 到哪一行就更新左側說明。

**超魔專長分頁**（`FeatInfoPanel`）：唯讀，不能配置。右側清單同樣是 master-detail 關係，focus/hover 到哪一條就在左側顯示按法與效果說明。

兩個分頁清單內的按鈕都套用自訂的 `focus` 樣式（`expand_margin` 設為 0，框線貼齊按鈕邊界而非往外凸出），避免按鈕邊緣貼齊 `ScrollContainer` 裁切邊界時框線被裁掉。

---

## 3. 戰鬥系統

### 3.1 右鍵瞬發
`instant_cast`（滑鼠右鍵）：固定傷害＝裝備中法術的基礎傷害乘上 `INSTANT_CAST_DAMAGE_MULT`（0.8），不經過吟唱/超魔專長強化。CD 固定 `RIGHTCLICK_CD = 3.0` 秒，UI 顯示冷卻進度條。瞬發跳過的只是吟唱/專長累積階段，不影響 delivery 本身的運作方式——如果裝備中法術是鎖定選點類型，右鍵瞬發一樣會暫停遊戲等待選位置。

### 3.2 法術切換輪盤
按住 Ctrl（`Input.is_key_pressed(KEY_CTRL)`，不走 Input Map）彈出輪盤，`Engine.time_scale` 降到 0.25（子彈時間，怪物與場上一切持續運作只是變慢，不是暫停）。以 Ctrl 按下那一刻的滑鼠位置為輪盤中心，滑鼠相對中心的角度決定選中哪一格（正上方為第0格，順時針等分，離中心 12px 內不選取任何格）。放開 Ctrl 或點擊左鍵都會確認並收起輪盤。輪盤開啟時 `Player._physics_process()` 整段提前 return，唯一能做的操作是選法術；若此時正在吟唱會直接取消。支援任意把數（角度公式用 `TAU / float(n)`，不綁定固定數量）。`scripts/ui/SpellWheel.gd` 純畫面呈現，不做選取判定，判定邏輯在 `Player.gd`。

### 3.3 AoE 選點介面
`AoETargetingDelivery` 施放時觸發，畫在世界座標（施法者周圍的 `max_range` 邊界淡圈、落點範圍預覽圈），用 `get_tree().paused = true` 做真正的暫停（跟輪盤的子彈時間不同），節點本身 `process_mode = PROCESS_MODE_ALWAYS` 才能在暫停時繼續運作。左鍵確認、右鍵或 Esc 取消；滑鼠超出 `max_range` 時指示圈鎖在邊界並變灰。

### 3.4 基礎 Dash
空白鍵觸發，不走 `Spell`/`SpellDelivery` 架構、不佔用法術欄位、沒有冷卻。方向取按下當下的 WASD（跟滑鼠瞄準方向無關），站著不動時用 `last_move_direction`（上一次有實際移動輸入的方向）。`DASH_DURATION`（0.12秒）內用 `DASH_SPEED` 持續呼叫 `move_and_slide()`，會自然貼牆滑行、碰到牆就停下，不是瞬移。`DASH_SPEED` 直接用 `50.0 / DASH_DURATION` 算（2026-10-12 使用者要求衝刺距離改成 50px，原本約220px），數值本身就是「50px」這個意圖，不是另外存一個容易跟 `DASH_DURATION` 脫鉤的獨立常數。吟唱中、輪盤開啟、衝刺進行中都不會觸發/疊加。

目前只有這個基礎分支——裝備位移類法術時改走 `AoETargetingDelivery` 選點移動施法者座標的分支尚未有對應法術可驗證。

### 3.5 玩家 HP／死亡（2026-10-12 新增，2026-10-12 當天又修正一輪）

**範圍明確只包含玩家這一側**——使用者實測討論後確認：Boss 本體血量歸零維持原本「重置滿血」的佔位行為不動（分身的 3HP 是例外，本來就是真的會消失），這次不處理。

- `Player.gd`：`const MAX_HP := 100.0`／`var hp`／`var is_dead`，跟 `Boss.gd`/`TestDummy.gd` 同一套既有慣例（`take_damage(amount)` 直接扣血、clamp 在 0、`hp_changed(ratio)` 訊號給 UI）。`take_damage()` 血量歸零時呼叫 `_die()`：設 `is_dead = true`、停止吟唱/衝刺/移動、emit `died` 訊號——**不**比照 Boss 重置滿血，這是玩家真正的死亡。`_physics_process()`/`_input()` 開頭都加了 `if is_dead: return`，死亡後整個不再回應任何輸入（移動、吟唱、瞬發、Dash、輪盤全部停）。
- `scripts/ui/HealthOrb.gd`＋`scenes/ui/HealthOrb.tscn`：使用者明確要求 PoE/暗黑那種「液體填充圓球」視覺風格，不是進度條。**第一版用 `_draw()` 手刻圓弧弓形多邊形＋sine 波液面起伏，使用者實測後要求拿掉波動（血量沒變時不該有任何浮動效果，會讓人誤以為血量在變動），並且考慮到之後會換成美術素材，要求改用真的材質測試整條管線**——改版後用 `TextureProgressBar`（`fill_mode = FILL_BOTTOM_TO_TOP`、`nine_patch_stretch = true` 讓材質自動縮放填滿容器，不管以後真的美術素材尺寸是多少都不用改程式）取代手刻多邊形，液體從下往上淹沒的效果完全靠裁切材質本身做出來，不自己算幾何、不加任何動畫——液面只在 `hp_changed` 訊號真的觸發時才會變化。`texture_under`／`texture_progress` 共用同一張圖（`art/ui/health_orb_fill.png`，一張純紅色實心圓形 PNG，純粹拿來測試材質管線，之後要換真的美術素材只要換掉這張圖，不用動程式碼），只是 `tint_under` 調暗代表「空血」的底色。只做血量這一顆，使用者明確說「不用對稱，單邊就好了」——不加魔力/資源球，這個專案目前也沒有資源系統。跟 `CastBar.gd` 同一個「呼叫端 `bind(player)` 一次、自動訂閱訊號」的共用元件模式，`Main.tscn` 的 `UI` CanvasLayer 左下角掛一份。
- `scripts/ui/DeathScreen.gd`＋`scenes/ui/DeathScreen.tscn`：監聽 `player.died`，顯示半透明黑底＋按鈕，同時 `get_tree().paused = true`（玩家已經死了，背景不該讓 Boss 繼續出招）。**第一版有「你死了」大字＋「重試」按鈕（重試＝`reload_current_scene()` 原地重來）；使用者實測後要求拿掉文字、按鈕改成「回大廳」**——`_on_lobby_pressed()` 改用 `get_tree().change_scene_to_file("res://scenes/Lobby.tscn")`，死亡後直接回到裝備配置畫面重新出發，不是原地重來一場一樣的戰鬥。這個節點＋按鈕都要 `process_mode = PROCESS_MODE_ALWAYS` 才能在暫停時仍然接收點擊，跟 `AoETargetingReticle.gd` 同樣理由。已驗證過：死亡畫面正確顯示（無文字、只有按鈕）、按下後正確切回 Lobby。

**踩到的環境雷：外部腳本新增的圖片資源，Godot 編輯器不會自動匯入，需要用 `editor_refresh` 不帶路徑參數（觸發全專案掃描，不是只傳 `file_paths` 的 O(1) 單檔模式）才會真的產生 `.import` 檔案；而且就算匯入完成，已經在跑的遊戲 session 讀到的還是舊的（`texture_progress` 等欄位是 `null`），要 `game_stop`+`game_start` 重開一次遊戲才會讀到剛匯入好的資源。**跟 `CLAUDE.md`「已知環境雷」記錄的「新增 `class_name` 腳本要先匯入」同一類問題，只是這次是圖片資源，觸發匯入的方式也不同（不是 `--headless --import`，是 `editor_refresh` 全掃描）。

---

## 4. 競技場

### 4.1 三環結構
場地是三個同心圓區域，圓心 `ARENA_CENTER = Vector2(600, 350)`：

| 區域 | 半徑範圍 | 說明 |
|---|---|---|
| 玩家場地 | 0 ~ `PLAYER_ZONE_RADIUS`(260) | 玩家唯一能站的地方，`Main.tscn` 的牆壁碰撞（`CollisionPolygon2D`）圍這一圈 |
| 縫隙 | 260 ~ 360（寬度 `GAP_WIDTH`=100） | 完全淨空，不鋪地磚，兩個場地物理上不連通 |
| boss 環道 | `BOSS_RING_INNER_RADIUS`(360) ~ `ARENA_RADIUS`(450) | boss 與分身唯一出現的地方，環道寬度90 |

boss 固定巡邏軌道半徑 `BOSS_TRACK_RADIUS = (BOSS_RING_INNER_RADIUS + ARENA_RADIUS) / 2.0`（算出來410，環道正中央）。牆體視覺厚度 `WALL_THICKNESS = 24`。

玩家與 boss 物理上永遠碰不到面，所有互動只能靠法術隔空進行。完整的 boss 走位/招式機制見 `BOSS_DESIGN.md`。

**2026-10-12：場地整個改成壓扁橢圓（套 `GroundProjection.squash`），不再是正圓**——之前（見 §5.1）場地圍牆/boss巡邏軌道刻意維持正圓，只有範圍判定/視覺指示套壓扁，使用者這次明確要求場地本身也要跟著壓扁，不要「正圓場地裡包一堆橢圓範圍指示」這種不協調的組合。所有半徑常數（`PLAYER_ZONE_RADIUS`/`BOSS_RING_INNER_RADIUS`/`ARENA_RADIUS`/`BOSS_TRACK_RADIUS`）數值本身不變，只是「半徑」的詮釋從正圓改成橢圓長軸——`GroundProjection.ellipse_point(center, radius, angle)` 給「角度→橢圓上座標」用（boss巡邏/分身出生位置），`GroundProjection.clamp_to_ring(from, to, min, max)` 給「環狀邊界夾限」用（boss被擊退飄出環道時夾回來）。

### 4.2 碰撞與反彈
牆壁碰撞只圍 `PLAYER_ZONE_RADIUS`：`CollisionPolygon2D`（`scripts/core/PlayerZoneWall.gd`，2026-10-12 起在 `_ready()` 用 `GroundProjection.ellipse_points()` 動態產生橢圓頂點，取代原本寫死在 `.tscn` 裡的 48 點正圓座標——這樣以後調整 `PLAYER_ZONE_RADIUS` 或 `squash` 係數，牆壁碰撞形狀會自動跟著變）。boss/分身不走物理碰撞（手動控制 `global_position`，`collision_mask=0`），靠自身巡邏公式與邊界夾限維持在環道內。

`SpellProjectile.gd` 的牆壁反彈（`bounces_off_walls=true` 的 delivery，目前只有雷電箭）不用物理碰撞：比較投射物到 `ARENA_CENTER` 的壓扁距離（`GroundProjection.projected_distance()`）跟 `PLAYER_ZONE_RADIUS`，超出範圍時用 `GroundProjection.clamp_to_radius()` 夾回橢圓邊界上，反彈法線改用 `GroundProjection.ellipse_normal()` 算真正的橢圓法線（**不能**用「圓心→該點」方向，那是正圓公式，橢圓上任一點的法線方向跟半徑方向不同，用正圓公式會讓反彈角度肉眼可見地不對）。

---

## 5. 視覺風格

Magicka 調性：Q 版、鮮豔、誇張特效的奇幻風格。全部用 Godot `_draw()` 程式繪圖 + `CPUParticles2D` 動態生成，無外部美術資源。

### 5.1 3/4 俯視角慣例
地板維持純俯視方格座標系不變（不是真等角投影），角色/怪物造型改用「有正面、帶高度感」的畫法：
- **腳下陰影**：壓扁橢圓（多邊形近似），讓角色站在地上而不是貼平的貼紙。
- **身體左右分色**：同一塊造型左右兩片不同明暗（暗側 `darkened(0.25)`），模擬最簡單的立體感。
- **臉部正面化**：頭部圓形疊在身體肩線之上，帶兩個眼睛點，不是俯視頭頂。

角色不用 `look_at()` 連續旋轉，只用 `facing_right`（滑鼠在角色左/右的布林值）決定法杖畫在哪一側（x 座標鏡射），角色本身固定朝下。

地板磚塊、爆炸特效、範圍選取圈也延伸同一套「有高度感」語言但不做真投影：磚塊加「左上亮、右下暗」浮雕邊線模擬厚度；爆炸/範圍特效壓扁成橢圓，壓扁係數跟判定邏輯統一讀 `scripts/core/GroundProjection.gd`（`class_name GroundProjection`，見下方說明），不再各檔案各放一份 `GROUND_SQUASH` 常數。

**2026-10-11：補上「視覺壓扁」跟「判定範圍」對不上的修正，新增 `GroundProjection`**——`scenes/SpellTestRange.tscn` 這個測試場（同心圓參考線）上線後，發現範圍判定邏輯全部還是用沒壓縮的正圓（`AoETargetingReticle.gd` 的滑鼠選點夾限、`AoETargetingDelivery.gd`/`ExplosiveImpact.gd`/`SelfDelivery.gd` 的命中判定、`HomingMissile.gd`/`HomingMissileDelivery.gd` 的鎖定範圍、`Boss.gd` 吸引扇形觸發/脫離距離、`BossOrb.gd` 命中半徑、`BossSuctionZone.gd` 扇形距離分量），視覺畫的是橢圓、判定卻是正圓。已修：
- 新增 `GroundProjection.squash`（集中管理壓扁係數，取代各檔案各自的 `GROUND_SQUASH`）、`GroundProjection.projected_distance()`（Y方向差距除以 squash 再算距離，取代上述所有範圍判定的 `distance_to()`/`.length()`）。
- `Player.gd` 的 `_process_movement()` 改用 `GroundProjection.projected_velocity()`：上下方向移動的世界座標速度乘上 `squash`（變慢）——因為 `projected_distance()` 讓上下方向判定範圍天生比左右方向更容易進入（Y差距影響力被放大），移動速度對應變慢才能讓「走進某個範圍要花多久」不管從哪個方向接近都一致。
- **刻意不動**：碰撞形狀（`CircleShape2D` 全部維持圓形，範圍判定是程式碼手動算距離、碰撞是 Godot 物理引擎的實際形狀重疊，兩者是不同機制，碰撞形狀這些都很小、沒必要冒多邊形橢圓近似的複雜度/效能風險）；Dash/Knockback（瞬間物理反饋，不套這個系統）。
- **場地圓形圍牆／boss固定巡邏半徑／`SpellProjectile` 牆壁反彈這三項，當時刻意維持正圓（跟實際碰撞形狀一致），2026-10-12 已經依使用者要求補做（場地整個改成壓扁橢圓），見 §4.1／§4.2。

### 5.2 共用特效（`MagicFX.gd`）
`class_name MagicFX`，提供三個 static 工具方法：`spawn_burst()`（爆發粒子）、`make_sparkle_trail()`（拖尾粒子，不套壓扁，軌跡在空中飛不需要壓扁）、`spawn_explosion_ring()`（範圍特效用的擴張淡出圈）。壓扁係數讀 `GroundProjection.squash`（見 §5.1）。

### 5.3 解析度
`project.godot`：`viewport_width/height = 1280x720`（設計基準解析度），`stretch/mode = "canvas_items"`，`stretch/aspect = "keep"`。FHD(1920x1080)／2K(2560x1440)／4K(3840x2160) 都是同樣 16:9，畫面等比例縮放貼合視窗。

---

## 6. 專案結構

```
spellcraft-poc/
├── project.godot                       # Godot 4.6 專案設定，input map、[autoload] GameState、啟動場景＝Lobby.tscn
├── scenes/
│   ├── Lobby.tscn                      # 大廳：法術格配置畫面，啟動場景
│   ├── Main.tscn                       # 戰鬥場景：Arena、Player、Boss、選點介面、UI（吟唱條/專長列/CD條/輪盤/除錯面板）
│   ├── entities/
│   │   ├── Player.tscn                 # CharacterBody2D + CollisionShape2D + Camera2D + CastPreview + AoETargetingReticle（後兩者掛在這裡，不是掛在 Main.tscn/SpellTestRange.tscn 根層級，任何用到這個場景的地方自動帶有吟唱預覽/AoE選點功能，見 §1.7）
│   │   └── boss/                       # Boss.tscn／BossClone.tscn／BossFireball.tscn／BossOrb.tscn／BossSuctionZone.tscn（見 BOSS_DESIGN.md）
│   └── spells/
│       ├── SpellProjectile.tscn        # 直線投射物共用場景
│       └── HomingMissile.tscn          # 追蹤飛彈共用場景（魔法飛彈用）
├── scripts/
│   ├── Main.gd                         # UI 綁定 + 開發用除錯面板（F3）
│   ├── Lobby.gd                        # 大廳邏輯：格數預算檢查、分頁切換、法術說明顯示、輪盤排序
│   ├── state/
│   │   └── GameState.gd                # Autoload 單例：法術總表、超魔專長表、equipped_spells 跨場景傳遞
│   ├── core/
│   │   └── Arena.gd                    # 競技場地板/牆體程式繪圖（三環結構）
│   ├── entities/
│   │   ├── Player.gd                   # 移動、吟唱狀態機、超魔專長判定、buff系統、發射邏輯、輪盤選取、角色繪製
│   │   └── boss/                       # Boss.gd/BossClone.gd/BossFireball.gd/BossOrb.gd/BossSuctionZone.gd（見 BOSS_DESIGN.md）
│   ├── fx/
│   │   └── MagicFX.gd                  # 共用特效工具
│   ├── ui/
│   │   ├── SpellWheel.gd               # 戰鬥法術輪盤畫面呈現
│   │   ├── AoETargetingReticle.gd      # AoE 選點介面
│   │   ├── CharacterPortrait.gd        # 大廳角色形象
│   │   ├── SlotGrid.gd                 # 大廳法術格視覺化
│   │   └── LoadoutWheelPreview.gd      # 大廳輪盤排序預覽（拖拽交換）
│   └── spells/
│       ├── Spell.gd                    # 法術定義（Resource）
│       ├── SpellDelivery.gd            # 發射方式基底
│       ├── ProjectileDelivery.gd       # 直線投射物
│       ├── SelfDelivery.gd             # 以施法者為中心對周圍敵人造成範圍傷害
│       ├── SelfBuffDelivery.gd         # 效果套用在施法者自己身上（buff類法術）
│       ├── AoETargetingDelivery.gd     # 鎖定選點的範圍傷害
│       ├── HomingMissileDelivery.gd    # 自動鎖定目標、依序發射的追蹤飛彈
│       ├── ProjectileImpact.gd         # 投射物命中/飛行耗盡後行為變體基底
│       ├── SingleHitImpact.gd / ExplosiveImpact.gd / PiercingImpact.gd
│       ├── SpellEffect.gd              # 命中/疊加效果基底（INSTANT/DURATION）
│       ├── DamageEffect.gd / InvisibilityEffect.gd / SpeedBuffEffect.gd
│       ├── SpellProjectile.gd          # 直線投射物飛行、碰撞傷害、拖尾特效
│       └── HomingMissile.gd            # 追蹤飛彈：恆速轉向導引、碰撞傷害、拖尾特效
└── resources/
    └── spells/
        ├── Fireball.tres               # AoETargetingDelivery，slot_cost=3
        ├── ForceWave.tres              # SelfDelivery，slot_cost=2
        ├── LightningBolt.tres          # ProjectileDelivery + PiercingImpact + 牆壁反彈，slot_cost=1
        ├── Invisibility.tres           # SelfBuffDelivery + InvisibilityEffect，slot_cost=2
        ├── SpeedBoost.tres             # SelfBuffDelivery + SpeedBuffEffect，slot_cost=1
        └── MagicMissile.tres           # HomingMissileDelivery + SingleHitImpact，slot_cost=1
```

法術系統架構的完整欄位/類別說明記錄在 `SPELL_SYSTEM.md`，不重複寫在這裡。

### 6.1 Input Map（`project.godot`）
| Action | 綁定 |
|---|---|
| `move_up/down/left/right` | W/A/S/D（實體鍵碼） |
| `cast_spell` | 滑鼠左鍵 |
| `instant_cast` | 滑鼠右鍵 |

Ctrl（法術輪盤）、空白鍵（Dash）、F3（除錯面板）都不走 Input Map，直接在腳本用符號常數判斷（`Input.is_key_pressed(KEY_CTRL)` 等），避免手刻 `InputEventKey` 設錯 keycode 卻不會報錯的風險。

### 6.2 執行環境
- Godot 4.6.2.stable，渲染後端 `gl_compatibility`。
- 無頭測試：`Godot --headless --quit-after N --path .` 可快速檢查腳本語法錯誤，無法測試實際輸入手感。
- 新增/修改帶 `class_name` 的腳本後，需要跑一次 `Godot --headless --import --path .` 讓全域類別註冊，否則可能出現假的 `Identifier "X" not declared` 錯誤。

---

## 7. 已知限制與開放問題

- **`COMBO_MAX_GAP = 0.15` 是示範值**，不同序列長度（2鍵 vs 4鍵）是否該用不同窗口尚未測試。
- **吟唱被怪物打斷的處理尚未設計**：目前怪物攻擊不會打斷玩家吟唱。
- **位移類法術**：`AoETargetingDelivery` 移動施法者座標的收尾路徑尚未有對應法術驗證過。
- **Mana／施放頻率限制**：尚未決定是否加入。
- **超魔專長組合表的平衡性**：目前 5 組為示範數值，未做最終平衡；專長本身還沒有解鎖/強化機制。
- **真實 HP／死亡／結算畫面**：玩家被打只閃光不扣血；boss 血量歸零會重置滿血，不是真正死亡（分身的 3HP 是例外，會真的消失）。
- **大廳狀態不持久化**：`GameState` 不會存到磁碟，重啟遊戲會回到空清單走 fallback；若需要存檔功能，`GameState` 是最直接的掛鉤點。

---

## 8. 建議閱讀順序
1. 先讀本文件第1節（超魔專長序列輸入系統），這是整個專案的核心機制。
2. 打開 Godot editor 跑一次，流程是 `Lobby.tscn`（大廳配置法術）→「出發」→ `Main.tscn`（戰鬥），建立操作直覺。
3. 讀 `Player.gd` 全文，這是最核心的邏輯檔案。
4. 讀 `SPELL_SYSTEM.md` 理解法術架構，讀 `BOSS_DESIGN.md` 理解 boss 行為。
5. 新增法術記得在 `GameState.gd:CATALOG` 加上資源路徑，否則大廳跟輪盤都不會出現這把法術。
