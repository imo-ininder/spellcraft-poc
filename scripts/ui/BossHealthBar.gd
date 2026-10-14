class_name BossHealthBar
extends Control

## Boss 血量條——畫面正上方置中，跟 StatusBars（玩家血量/專注值，畫面左上角）同一套
## 「bind(target) 掛 hp_changed 訊號」慣例。這支只服務「目前場上這一隻 Boss」，不是通用的
## 「任何敵人都可以掛」血條——之後如果同時有多隻敵人在場，要怎麼呈現是另一個設計問題，
## 這次只處理 BossTestRange 的單一 Boss 需求。

@onready var hp_bar: ProgressBar = $HPBar

var boss: Node

func bind(target_boss: Node) -> void:
	boss = target_boss
	boss.hp_changed.connect(_on_hp_changed)
	_on_hp_changed(boss.hp / boss.MAX_HP)

func _on_hp_changed(ratio: float) -> void:
	hp_bar.value = clamp(ratio, 0.0, 1.0) * 100.0
