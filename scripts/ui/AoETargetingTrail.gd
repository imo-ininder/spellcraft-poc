extends Node2D

## scripts/ui/AoETargetingReticle.gd 專用的子節點，掛在 CanvasGroup 底下（見 Player.tscn 的
## AoETargetingReticle/TrailLayer/TrailMarkers 結構）：畫「這次吟唱已經確認選過的點」痕跡。
##
## 故意獨立成子節點＋CanvasGroup 母節點，不是直接在 AoETargetingReticle._draw() 裡疊加畫多個
## 半透明圈——選多個點時這些圈很容易彼此靠近/重疊，如果直接疊加畫多個 alpha<1 的圈，重疊處會
## 因為 alpha 合成疊加而比單一個圈更亮（使用者明確要求重疊處要維持原本亮度，不能變亮）。
## CanvasGroup 會先把底下所有子節點畫進同一塊緩衝區（緩衝區內部這裡用不透明色畫，彼此重疊只是
## 互相覆蓋，不會疊加變亮），再把整塊緩衝區當成一個單位，用 CanvasGroup 自己的 self_modulate
## 透明度跟背景合成一次——這樣無論疊幾個圈在同一塊區域，看起來永遠跟畫一個圈一樣亮，不會疊加。
## 這裡的顏色刻意用 alpha=1.0（不透明），整體看起來多透明交給 TrailLayer（CanvasGroup）的
## self_modulate 統一套用一次，不是在這裡本身調。

var points: Array[Vector2] = []
var radius: float = 0.0

const COLOR := Color(0.4, 1.0, 0.5, 1.0)

func _draw() -> void:
	for p in points:
		draw_polyline(GroundProjection.ellipse_points(to_local(p), radius), COLOR, 3.0, true)
