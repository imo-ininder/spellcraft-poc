class_name FireRainZone
extends DamageZone

## 火雨術專屬的範圍——繼承 DamageZone 拿到共用的圓形 tick 判定/存活計時/畫法，只加這把
## 法術自己才有的東西：範圍內隨機冒出的掉落物特效。2026-10-13：原本直接寫在 DamageZone.gd
## 裡用 damage_mode==HIT 當開關，使用者指出這樣等於在共用類別裡 expose 了「只有火雨術在用、
## 調頻率還調不到（寫死的 const）」的參數——火焰地面/火牆術的火柱完全不需要這個效果，不該
## 因為它們剛好也是 DamageZone 就被迫一起背負這段邏輯。獨立成這支檔案，`rain_spawn_interval`
## 也變成真正的 export 欄位（FireRainSpell.gd 可以直接調），不是寫死的 const。

@export var rain_spawn_interval: float = 0.12
var _rain_timer := 0.0

func _process(delta: float) -> void:
	super._process(delta)
	_rain_timer += delta
	if _rain_timer >= rain_spawn_interval:
		_rain_timer = 0.0
		_spawn_rain_drop()

## 範圍內隨機挑一點生成小火花，模擬雨點落地——用 sqrt(randf()) 讓點在圓形面積內均勻分布
## （不是角度均勻，不然中心附近會比邊緣密），再用 GroundProjection.ellipse_point() 貼合
## 壓扁橢圓的視覺範圍（跟 _draw() 畫的橢圓是同一個形狀），不是正圓隨機點。純視覺，不影響
## DamageZone._apply_tick() 的傷害判定頻率。
func _spawn_rain_drop() -> void:
	var angle := randf() * TAU
	var r: float = radius * sqrt(randf())
	var point := GroundProjection.ellipse_point(global_position, r, angle)
	MagicFX.spawn_burst(get_tree().current_scene, point, Color(1.0, 0.65, 0.2), 5, 70.0)
