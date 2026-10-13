class_name CastBar
extends Control

## 可重用的吟唱讀條元件：進度條＋倒數秒數文字。Main.tscn（正式戰鬥）／scenes/SpellTestRange.tscn
## （法術測試場）都掛這個，不要再各自複製一份邏輯——這段邏輯原本在兩邊各自刻過一次，後來只改了
## 一邊（測試場加了倒數文字＋施法速度換算），另一邊沒跟著動，兩個讀條行為對不上。往後要調整讀條
## 的呈現方式（格式、顏色、加欄位...），改這一個檔案就好，兩邊會一起生效，不用到處找。
##
## 用法：呼叫端只要在自己的 _ready() 裡呼叫一次 bind(player)，不用自己接 cast_started/
## cast_progress/cast_ended 訊號，也不用自己重算秒數。

@onready var bar: ProgressBar = $ProgressBar
@onready var label: Label = $TimerLabel

var player: CharacterBody2D

func _ready() -> void:
	visible = false

func bind(target_player: CharacterBody2D) -> void:
	player = target_player
	player.cast_started.connect(_on_cast_started)
	player.cast_progress.connect(_on_cast_progress)
	player.cast_ended.connect(_on_cast_ended)

func _on_cast_started() -> void:
	visible = true
	bar.value = 0
	label.text = "%.2fs" % player.equipped_spell.cast_time

## ratio 是 Player.gd 算好的 0~1 進度（cast_timer/equipped_spell.cast_time 的倒數比例）。
## 顯示的秒數不能直接用 (1-ratio)*cast_time（那只是法術固定的「基礎秒數」）——cast_timer
## 是用 delta*(1+cast_speed_bonus) 在扣，不是真實時間，所以還要再除以 (1+cast_speed_bonus)
## 才是「照目前施法速度，實際還剩幾秒」。RR/LL 這類即時調整施法速度的超魔專長一旦中途觸發，
## cast_speed_bonus 改變，下一幀顯示的秒數就會直接跳到新速度算出來的值，不是照基礎秒數乾算。
func _on_cast_progress(ratio: float) -> void:
	bar.value = ratio * 100
	var remaining_base: float = (1.0 - ratio) * player.equipped_spell.cast_time
	var remaining_real: float = remaining_base / (1.0 + player.cast_speed_bonus)
	label.text = "%.2fs" % max(remaining_real, 0.0)

func _on_cast_ended() -> void:
	visible = false
