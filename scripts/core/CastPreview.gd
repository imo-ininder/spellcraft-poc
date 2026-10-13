extends Node2D

## 掛在 scenes/entities/Player.tscn 底下（不是掛在 Main.tscn／SpellTestRange.tscn 場景根層級），
## 原因：任何用到 Player.tscn 的場景都會自動帶有這個功能，不需要每次新增/修改場景時都手動記得
## 補一個節點＋一行 bind()——之前就是因為掛在場景根層級、各自手動接，導致只接了 SpellTestRange
## 沒接 Main，正式戰鬥完全沒有預覽圈，見 docs/DESIGN.md 同一輪記錄。吟唱過程中（還沒真的施放）
## 就先畫出這把法術的作用範圍，不用等到施放成功、進入選點/命中階段才看得到範圍大概多大/多遠。
## 兩種預覽同時畫、互不取代：
## 1. 「最遠能打到哪」：以施法者為中心、半徑 = spell.max_range 的邊界圈，顏色/粗細刻意跟
##    AoETargetingReticle.gd 選點確認階段畫的外圈一致（Color(1,1,1,0.25)，寬度2.0）——這樣
##    吟唱中看到的預覽跟選點確認階段視覺上無縫銜接，不會進入選點階段後顏色突然變。
## 2. 「命中半徑」：跟著滑鼠走的那個圈（AoETargetingDelivery.get_preview_center() 算出來的
##    位置），沒有半徑概念的法術（get_radius() < 0）不畫這個。
##
## 畫在哪裡／半徑多大完全問 delivery 自己（Spell.delivery.get_preview_center()／get_radius()，
## 見 SpellDelivery.gd），這裡不判斷法術是哪種型別——AoETargetingDelivery 會自己覆寫
## get_preview_center() 跟著滑鼠走（夾限邏輯跟真正選點時的 AoETargetingReticle.gd 共用
## GroundProjection.clamp_to_radius()，兩邊夾限位置保證一致）；SelfDelivery 之類沒覆寫的
## 就維持預設（以施法者為中心）。
##
## 命中半徑那圈顏色統一不分「滑鼠有沒有超出 max_range」——超出會被夾限但施放依然會成功命中
## 在夾限後的位置，不是失敗狀態，用單一顏色避免看起來像「這樣不行」，跟 AoETargetingReticle.gd
## 的同一個修正理由。
##
## 畫的不是 player.equipped_spell 原始數值，是套用「這次吟唱目前已經觸發的超魔專長」之後的
## 版本——法術增遠/法術擴展中途觸發時，預覽圈要跟著變大，不能還停在吟唱開始當下的舊數值。
## 重用 Player.debug_preview_scaled_spell()（跟 F4 數值 before/after 視窗、跟正式施放流程
## 共用同一個 _apply_scaling_feats()，不是另外算一套），每幀都用 player.accumulated_feats
## 目前的內容重算一次，純函式沒有副作用。

var player: CharacterBody2D

const PREVIEW_COLOR := Color(0.4, 1.0, 0.5, 0.6)
const MAX_RANGE_COLOR := Color(1, 1, 1, 0.25)

## 吟唱結束的瞬間，AoETargetingDelivery.fire() 可能在同一次呼叫裡就把 caster.get_tree().paused
## 設成 true（進入選點確認階段）——沒有這行的話，一旦進入暫停，_process() 整個不會再被呼叫，
## 代表 queue_redraw() 停擺，_draw() 永遠不會再跑到「is_casting 已經是 false、什麼都不畫」
## 那個分支，螢幕上會卡著吟唱結束前最後一幀的預覽圈，跟 AoETargetingReticle.gd 同樣理由
## 要設 ALWAYS。
##
## player 直接讀 get_parent()（這個節點在 Player.tscn 裡固定是 Player 的直屬子節點），不用
## 再靠外部場景腳本呼叫 bind() 手動注入——少一道「場景腳本記得呼叫」的環節，就少一種忘記接的
## 方式。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_parent()

func _process(_delta: float) -> void:
	queue_redraw()

## 這個節點現在是 Player 的子節點，_draw() 收到的座標要轉成相對自己原點的 local 座標（to_local()），
## 不能再像以前（掛在場景根層級、原點跟世界座標原點重合）那樣直接拿 global_position 當畫圖座標，
## 不然畫出來的位置會把 Player 當前位置多疊加一次。
func _draw() -> void:
	if not is_instance_valid(player) or not player.is_casting:
		return
	var spell: Spell = player.debug_preview_scaled_spell(player.accumulated_feats)
	if spell == null or spell.delivery == null:
		return

	if spell.max_range > 0.0:
		draw_polyline(GroundProjection.ellipse_points(to_local(player.global_position), spell.max_range), MAX_RANGE_COLOR, 2.0, true)

	var radius := spell.delivery.get_radius()
	if radius >= 0.0:
		var center := spell.delivery.get_preview_center(player, spell.max_range)
		draw_polyline(GroundProjection.ellipse_points(to_local(center), radius), PREVIEW_COLOR, 2.5, true)
