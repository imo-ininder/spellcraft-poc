class_name HealthOrb
extends Control

## PoE/暗黑那種液體血量圓球。2026-10-12 改版：使用者明確要求（1）血量沒變時不要有任何浮動/
## 呼吸動畫（原本手刻 _draw() 版本的 sine 波液面起伏會讓人誤以為血量在變動，造成誤判——
## 現在液面只在 hp_changed 訊號真的觸發時才會動，不會自己無緣無故起伏）；（2）這之後會換成
## 美術素材顯示，先用一張純紅色圓形 PNG（art/ui/health_orb_fill.png）測試整條「材質裁切做
## 液體填充」的管線能不能正常運作——之後真的有美術素材時，只要把這張圖換掉，不用改這支腳本
## 任何一行。
##
## 用 TextureProgressBar（fill_mode = FILL_BOTTOM_TO_TOP）而不是自己手刻圓弧多邊形——這是
## Godot 內建就支援「用一張既有材質，從下往上裁切顯示比例」的元件，液體從下往上淹沒的視覺
## 效果完全靠裁切這張圓形材質本身做出來，不需要自己算圓弧幾何。空血／滿血兩層共用同一張
## 材質，只是 tint 顏色不同（tint_under 暗、tint_progress 保留原色），不需要準備兩張圖。
##
## 用法跟 CastBar.gd 同一個模式：呼叫端只要在自己的 _ready() 呼叫一次 bind(player)。

@onready var fill_bar: TextureProgressBar = $FillBar
@onready var hp_label: Label = $HPLabel

var player: CharacterBody2D

func bind(target_player: CharacterBody2D) -> void:
	player = target_player
	player.hp_changed.connect(_on_hp_changed)
	_update(player.hp / player.MAX_HP)

func _on_hp_changed(ratio: float) -> void:
	_update(ratio)

func _update(ratio: float) -> void:
	fill_bar.value = clamp(ratio, 0.0, 1.0) * 100.0
	if is_instance_valid(player):
		hp_label.text = "%d / %d" % [int(ceil(player.hp)), int(player.MAX_HP)]
