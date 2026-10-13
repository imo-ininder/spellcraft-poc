class_name AoETargetingDelivery
extends SpellDelivery

## 鎖定選點的範圍法術：吟唱結束後暫停遊戲、顯示跟隨滑鼠的指示圈（受 max_range 限制），
## 確認後恢復遊戲並在選定點造成範圍傷害。右鍵瞬發跳過的是吟唱/符紋累積階段，不是這個暫停選點流程——
## 瞬發一樣要暫停等玩家選位置，只是少了符紋強化、傷害用固定倍率（見 Player.gd:_fire_instant_spell）。
@export var radius: float = 90.0
## 量詞（「這次丟幾顆」），法術強效縮放的目標，見 SpellDelivery.scale_count() 的註解。count>1
## 時依序選多個點（每次各自開一次選點介面，可以點不同位置），不是同一個點疊加好幾次爆炸——
## 2026-10-12 使用者確認的手感：像連續丟 N 顆火球，不是單點多重爆炸。
@export var count: int = 1

## 選 count 個點、依序標示痕跡、左鍵確認/右鍵撤銷上一個/ESC整個取消，這整套邏輯都在
## AoETargetingReticle.gd 內部處理（見該腳本開頭註解）——這裡只要 start() 一次、await
## finished 一次，拿到的是「這次吟唱最終確認下來的所有點」（可能是空陣列，代表整個取消，
## 一個都不會爆炸）。count=1（沒套用法術強效，或套用後 floor 下來還是1）時行為跟改動前
## 完全一致：選一個點就直接完成，取消就是整個沒有任何爆炸。
##
## 法術迴響（echo）**不會**讓選點介面再開一次——使用者明確要求「點一次，效果變兩次」，不是
## 「點兩次」。選完的這組點（不管是1個還是 count>1 個）先整批解算一次，echo 生效的話再等
## ECHO_DELAY 秒、對同一批點整批再解算一次。沒選到任何點（整個取消）時 echo 不會額外觸發
## 一次空等待，points 是空陣列時兩個迴圈本來就都是 no-op，但還是先判斷一次避免白白等 0.15 秒。
func fire(caster: Node2D, _direction: Vector2, stats: Dictionary, max_range: float, _effects: Array = [], echo: bool = false) -> void:
	var reticle: AoETargetingReticle = caster.get_node("AoETargetingReticle")
	caster.get_tree().paused = true
	reticle.start(caster, max_range, radius, count)
	var points: Array = await reticle.finished
	caster.get_tree().paused = false
	if points.is_empty():
		return
	for point in points:
		_resolve(caster, point, stats.damage)
	if echo:
		await caster.get_tree().create_timer(ECHO_DELAY).timeout
		for point in points:
			_resolve(caster, point, stats.damage)

func _resolve(caster: Node2D, point: Vector2, damage: float) -> void:
	for target in caster.get_tree().get_nodes_in_group("enemies"):
		if target.has_method("take_damage") and GroundProjection.projected_distance(target.global_position, point) <= radius:
			target.take_damage(damage)
	MagicFX.spawn_burst(caster.get_tree().current_scene, point, Color(1, 0.5, 0.1), 28, 260.0)
	MagicFX.spawn_explosion_ring(caster.get_tree().current_scene, point, radius, Color(1, 0.35, 0.1))

func scale_radius(mult: float) -> void:
	radius *= mult

func has_scalable_radius() -> bool:
	return true

func get_radius() -> float:
	return radius

## floor 無條件捨去、下限夾在1，跟 HomingMissileDelivery.scale_count() 同一條規則。
func scale_count(mult: float) -> void:
	count = maxi(1, int(floor(count * mult)))

func has_scalable_count() -> bool:
	return true

func get_count() -> int:
	return count

func get_preview_center(caster: Node2D, max_range: float) -> Vector2:
	return GroundProjection.clamp_to_radius(caster.global_position, caster.get_global_mouse_position(), max_range)
