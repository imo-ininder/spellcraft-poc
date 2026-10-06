class_name InvisibilityEffect
extends SpellEffect

## 隱形術：持續期間 boss 完全找不到玩家位置（Boss.gd/BossFireball.gd/BossOrb.gd/BossSuctionZone.gd
## 的 _find_player() 在玩家隱形時一律回傳 null，已經鎖定飛行中的攻擊不受影響——隱形防的是「新的
## 鎖定」，不是幫玩家擋掉已經飛出去的攻擊）。打斷規則（施放任意法術就中斷）不在這裡處理，
## 在 Player._fire_spell()/_fire_instant_spell() 開頭統一檢查，因為那是「玩家主動做了什麼」
## 觸發的，不是這個效果本身的倒數邏輯，見 Player.gd 開頭的 is_invisible 欄位註解。

func _init() -> void:
	self.apply_mode = SpellEffect.ApplyMode.DURATION
	self.buff_id = "invisibility"

func on_start(target: Node) -> void:
	target.is_invisible = true
	MagicFX.spawn_burst(target.get_tree().current_scene, target.global_position, Color(0.6, 0.65, 0.8, 0.6), 24, 180.0)

func on_expire(target: Node) -> void:
	target.is_invisible = false
	MagicFX.spawn_burst(target.get_tree().current_scene, target.global_position, Color(0.6, 0.65, 0.8, 0.6), 16, 140.0)
