class_name FireRetreatSpell
extends Spell

## 火焰撤離（docs/FIRE_PROTOTYPE.md §6.4）：向瞄準方向的反方向位移一段距離（重用
## Player.start_retreat()，使用者明確要求不跟 apply_knockback()/Dash 共用，見該函式宣告處
## 註解），原地留下一塊長方形 DOT 區域（FireRetreatTrailZone，使用者明確要求不跟 DamageZone
## 共用——兩者形狀不同：這個是矩形，覆蓋撤離前後的路徑）。
##
## 2026-10-13：類別名稱從 RetreatSpell 改成 FireRetreatSpell——「Retreat」是按「位移類型」
## 取的名字，暗示「所有撤離類法術都長這樣」，但這支檔案的位移距離/軌跡形狀都是這把法術自己
## 的設計，不是通用規格。跟 FireballSpell/FireArrowSpell 同一個命名慣例。

## retreat_distance 是「投影後／視覺上看起來的距離」，不是世界座標位移量——跟
## Player.start_retreat() 同一套校正（見該函式宣告處註解），這裡用 GroundProjection.
## offset_towards() 重算一次實際的世界座標位移向量，確保軌跡（矩形）的長度/位置跟玩家
## 實際移動的距離/方向完全對齊（兩邊是各自呼叫同一個純函式，結果保證一致，不是共用一份
## 算好的狀態）。
@export var retreat_distance: float = 120.0
@export var trail_width: float = 50.0
@export var damage_per_tick: float = 3.0
@export var tick_interval: float = 0.5
@export var duration: float = 3.0

func cast(caster: Node2D, aim_dir: Vector2) -> void:
	var retreat_dir := -aim_dir
	var start_pos: Vector2 = caster.global_position
	caster.start_retreat(retreat_dir, retreat_distance)

	var raw_offset := GroundProjection.offset_towards(retreat_dir, retreat_distance)
	var trail := FireRetreatTrailZone.new()
	caster.get_tree().current_scene.add_child(trail)
	## 軌跡覆蓋「撤離前位置」到「預期撤離後位置」整段路徑，中心點在兩者中點——實際位移是
	## 下個 physics frame 才開始跑（見 Player._process_retreat()），這裡是用預期位移先算好，
	## 跟真正跑完的終點可能有些微落差（例如中途撞牆被 move_and_slide() 擋住），demo 階段
	## 不追求逐像素對齊。
	trail.global_position = start_pos + raw_offset * 0.5
	trail.setup(retreat_dir, raw_offset.length(), trail_width, damage_per_tick, tick_interval, duration)
