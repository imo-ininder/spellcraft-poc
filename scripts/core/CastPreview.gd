extends Node2D

## 掛在 scenes/entities/Player.tscn 底下（不是掛在場景根層級），原因：任何用到 Player.tscn 的
## 場景都會自動帶有這個功能，不需要每次新增/修改場景時都手動記得補一個節點＋一行 bind()——
## 之前就是因為掛在場景根層級、各自手動接，導致只接了 SpellTestRange 沒接 Main.tscn（已刪除），
## 正式戰鬥完全沒有預覽圈。吟唱過程中（還沒真的施放）就先畫出這把法術的作用範圍，不用等到
## 施放成功、進入選點/命中階段才看得到範圍大概多大/多遠。2026-10-13 現況：舊戰鬥系統刪除後
## 沒有法術會進入吟唱狀態（is_casting 恆為 false），這個節點目前不會真的畫出任何東西，但
## 掛載方式/畫法架構保留著，等新系統的「施放中預覽」需求明確了再接上。
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

## 2026-10-13：舊的「吟唱中範圍預覽」整套依賴 player.is_casting／player.accumulated_feats／
## player.debug_preview_scaled_spell()，這三個全部跟著舊的固定時長吟唱系統一起刪除了（見
## docs/DEMO_PLAN.md Phase 1）。新系統沒有「準備中法術」這個持續性狀態可以預覽——Phase 1
## 的蓄力火球/近戰是瞬間判定，Phase 2 的符文施法是按下就立即觸發，都沒有「吟唱中」這段
## 期間。整個停用（維持 return，不畫任何東西），掛載方式/畫法架構（to_local()/
## GroundProjection.ellipse_points() 這套）保留著，等之後真的有「目前鎖定節點」這種可以
## 預覽的狀態時再重新設計要畫什麼、問誰拿數值。
func _draw() -> void:
	return
