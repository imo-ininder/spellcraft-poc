class_name BossHealthBar
extends Control

## 畫面最上方單獨一條 boss 血條（2026-10-12 新增）。使用者要求：boss/分身頭上都不該有
## 血條（原本 Boss._draw_boss_body() 裡畫的小血條已移除），血量改成全畫面只有一條、
## 固定在畫面最上方，裡面要寫 boss 的名字——這樣分身再多也不會讓人誤以為「哪個分身的血條
## 掉了」，永遠只代表本體真實血量，分身完全沒有自己的血條顯示。
##
## BOSS_NAME 只是展示用的佔位名稱（使用者原文：「暫且叫他分身紅袍法師吧」），跟 Boss.gd/
## Boss.tscn 的檔名無關，之後有正式命名只要改這個常數，不用動其他邏輯。
##
## 用法跟 HealthOrb.gd/CastBar.gd 同一個模式：呼叫端在自己的 _ready() 呼叫一次 bind(boss)。

const BOSS_NAME := "分身紅袍法師"

@onready var fill_bar: ProgressBar = $FillBar
@onready var name_label: Label = $NameLabel

var boss: Node2D

func bind(target_boss: Node2D) -> void:
	boss = target_boss
	boss.hp_changed.connect(_on_hp_changed)
	name_label.text = BOSS_NAME
	_update(boss.hp / boss.MAX_HP)

func _on_hp_changed(ratio: float) -> void:
	_update(ratio)

func _update(ratio: float) -> void:
	fill_bar.value = clamp(ratio, 0.0, 1.0) * 100.0
