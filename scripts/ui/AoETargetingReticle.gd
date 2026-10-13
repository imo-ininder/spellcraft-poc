class_name AoETargetingReticle
extends Node2D

## 世界座標的選點介面（跟 SpellWheel 不一樣，SpellWheel 是純螢幕座標 UI）。
## 暫停時要繼續運作，所以 process_mode 設 ALWAYS，不受 SceneTree.paused 影響。
##
## 掛在 scenes/entities/Player.tscn 底下（不是掛在 Main.tscn／SpellTestRange.tscn 場景根層級），
## 跟 CastPreview.gd 同一個理由：任何用到 Player.tscn 的場景自動帶有這個功能，不用每個場景
## 各自手動補節點。AoETargetingDelivery.fire() 透過 caster.get_node("AoETargetingReticle")
## 取得這個節點（caster 就是施法的 Player，這個節點是它的直屬子節點）。
##
## 2026-10-12：支援一次吟唱選多個點（count>1，法術強效把火球術的「量詞」縮放到2以上時）——
## 依序選、依序標示，整段期間都在這個節點內部處理，呼叫端（AoETargetingDelivery.fire()）只要
## start() 一次、await finished 一次就好，不用自己寫迴圈：
## - 左鍵（cast_spell）＝確認目前瞄準的點。確認滿 total_count 個就結束，emit 所有確認過的點。
## - 右鍵（instant_cast）＝撤銷上一個已確認的點（還留在選取模式，繼續選剛撤銷掉的那個位置）。
##   如果還沒確認過任何點（confirmed_points 是空的），右鍵就是舊行為：整個取消，不施放。
## - ESC＝無論目前選到第幾個，直接整個取消（已經確認的點也一起作廢）——這是跟右鍵語意不同的
##   「大取消」，右鍵是一步步撤銷，ESC 是整組作廢。
## finished 訊號固定 emit 一個 Array（可能是空陣列，代表整個取消、什麼都不施放），呼叫端直接
## for point in points 處理就好，不用再判斷 null。

signal finished(points: Array)

var active := false
var caster: Node2D
var max_range := 0.0
var preview_radius := 0.0
var target_point := Vector2.ZERO
var total_count := 1
var confirmed_points: Array[Vector2] = []

@onready var trail: Node2D = $TrailLayer/TrailMarkers

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start(caster_node: Node2D, range_limit: float, radius: float, pick_count: int = 1) -> void:
	caster = caster_node
	max_range = range_limit
	preview_radius = radius
	total_count = pick_count
	confirmed_points.clear()
	target_point = caster.global_position
	active = true
	_refresh_trail()
	queue_redraw()

func _process(_delta: float) -> void:
	if not active:
		return
	target_point = GroundProjection.clamp_to_radius(caster.global_position, caster.get_global_mouse_position(), max_range)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("cast_spell"):
		confirmed_points.append(target_point)
		if confirmed_points.size() >= total_count:
			_finish()
		else:
			_refresh_trail()
			queue_redraw()
	elif event.is_action_pressed("instant_cast"):
		if not confirmed_points.is_empty():
			confirmed_points.pop_back()
			_refresh_trail()
			queue_redraw()
		else:
			_finish()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		confirmed_points.clear()
		_finish()

func _finish() -> void:
	active = false
	var result := confirmed_points.duplicate()
	confirmed_points.clear()
	_refresh_trail()
	queue_redraw()
	finished.emit(result)

func _refresh_trail() -> void:
	trail.points = confirmed_points
	trail.radius = preview_radius
	trail.queue_redraw()

## 3/4視角風格：圓形選取範圍要畫成貼地的橢圓，不是正圓——跟角色腳下陰影/爆炸特效同一套視覺
## 語言，橢圓頂點／壓扁係數統一呼叫 GroundProjection.ellipse_points()（集中管理，不要各自
## 複製一份橢圓迴圈）。這裡是用 caster.global_position/target_point 這種世界座標當圓心畫，
## 不是 CanvasItem 自己的座標系內置中，所以手動建橢圓多邊形而不是呼叫 draw_arc/draw_circle。
##
## 目標點被夾限到 max_range 邊界（滑鼠伸太遠）時顏色不變灰——夾限後的點一樣會成功施放，
## 不是失敗/無效狀態，灰色容易讓人誤會「這樣不能選」，統一用同一個綠色。
const RING_COLOR := Color(0.4, 1.0, 0.5, 0.9)

## 這裡只畫「目前還在瞄準、還沒確認」的那一個圈（跟著滑鼠走）＋最遠距離邊界——已經確認過的點
## 不在這裡畫，是另外用 TrailLayer（CanvasGroup）畫，見該節點腳本註解（避免多個確認點重疊時
## alpha 疊加變亮）。
##
## 這個節點現在是 Player 的子節點，畫圖座標要先 to_local() 轉成相對自己原點的 local 座標
## （理由跟 CastPreview.gd 同一行註解一樣：掛在場景根層級時原點等於世界座標原點可以直接用
## global 座標畫，現在原點跟著 Player 移動，不轉會把 Player 當前位置多疊加一次）。
func _draw() -> void:
	if not active:
		return
	draw_polyline(GroundProjection.ellipse_points(to_local(caster.global_position), max_range), Color(1, 1, 1, 0.25), 2.0, true)
	draw_polyline(GroundProjection.ellipse_points(to_local(target_point), preview_radius), RING_COLOR, 3.0, true)
