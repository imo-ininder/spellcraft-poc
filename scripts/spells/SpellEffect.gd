class_name SpellEffect
extends Resource

## INSTANT：吟唱結束當下套用一次，走 apply(stats)（例如傷害）。
## DURATION：在目標身上安裝一個有倒數時間的 buff，走 on_start()/on_expire()，不走 apply()——
## 倒數計時狀態存在目標節點身上（Player.active_buffs），不存在這個 Resource 上（CLAUDE.md 架構規則1：
## Resource 是共享引用，裝備同一份 .tres 的多個角色不能共享同一個倒數）。
enum ApplyMode { INSTANT, DURATION }

@export var apply_mode: ApplyMode = ApplyMode.INSTANT
@export var duration: float = 0.0 # 只有 apply_mode == DURATION 時才有意義
## DURATION 類效果用：同類型 buff 再次命中時用這個判斷「是不是同一種」以刷新時間，
## 不是疊加兩份獨立倒數——見 Player.add_buff()。INSTANT 類效果不需要這個欄位。
@export var buff_id: String = ""

func apply(_stats: Dictionary) -> void:
	push_error("SpellEffect.apply() not implemented on " + get_class())

## DURATION 類效果覆寫：buff 剛安裝時要做的事（例如設定 target.is_invisible = true）。
func on_start(_target: Node) -> void:
	pass

## DURATION 類效果覆寫：buff 到期時要復原的事（跟 on_start() 成對，必須能完整抵銷）。
func on_expire(_target: Node) -> void:
	pass
