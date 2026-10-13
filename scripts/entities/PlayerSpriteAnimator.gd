class_name PlayerSpriteAnimator
extends AnimatedSprite2D

## 2026-10-12 新增：AI 生成的像素風格 sprite sheet 正式取代 Player.gd `_draw()` 手繪造型，
## 第一批落地的美術資源（見 docs/ROADMAP.md §2 美術遷移計畫第3項「角色與怪物的動畫」）。
## 生圖提示詞見 art/prompts/player_sprite_sheet_prompts.md，原始大圖（完整 sheet）保留在
## art/characters/player/_source_sheets/，這裡用的是切好的單幀 PNG（art/characters/player/
## <animation>_<index>.png），用檔名慣例建表、不是手刻 SpriteFrames .tres——之後要抽換/增補
## 哪個動畫，只要照這個檔名規則把新圖丟進資料夾、改這份表的幀數，不用動其他程式碼。
##
## 6 張來源 sheet 不是同一次生成、構圖比例不一致（角色在畫布裡佔的比例差很多——走路系列
## 幾乎頂滿畫布，蓄力/釋放/受擊系列因為要留空間給往上延伸的魔法特效，角色相對小很多），
## 如果全部套同一個 scale/offset，切換動畫時角色會「跳大小」。TRANSFORM_BY_CATEGORY 記錄
## 每一類動畫各自的縮放／錨點校正（用 Python/Pillow 分析每張圖 alpha 通道算出角色腳底
## 位置，反推出讓「腳底落在節點原點」所需的 offset，scale 則是反推「讓角色在畫面上維持
## 約80px高、不管哪個動畫播放中看起來都一樣大」），讓最終呈現的角色大小/落地點一致。
## 這組數字是估算值，不是精確量測（取樣幾幀平均），到時候美術正式定案了再微調即可。
const TRANSFORM_BY_CATEGORY := {
	"walk": {"scale": 0.28, "offset": Vector2(0, -140)},
	"cast_charge": {"scale": 0.157, "offset": Vector2(0, -331)}, # 2026-10-12 換乾淨版素材後重新量測，數值跟舊的幾乎沒差
	"cast_release_buff": {"scale": 0.125, "offset": Vector2(0, -443)},
	"cast_release_attack": {"scale": 0.16, "offset": Vector2(0, -230)},
	"hurt": {"scale": 0.15, "offset": Vector2(0, -290)},
}

const FRAME_DIR := "res://art/characters/player/"
const ANIMATIONS := {
	"walk_down": 4, "walk_up": 4, "walk_left": 4, "walk_right": 4,
	"walk_down_left": 4, "walk_down_right": 4, "walk_up_left": 4, "walk_up_right": 4,
	"cast_charge": 4,
	"cast_release_buff": 3,
	"cast_release_attack": 3,
	"hurt": 4,
}
## 持續動畫（走路/蓄力）用 play_state() 每幀呼叫、照目前狀態決定要不要換；一次性動畫
## （釋放/受擊）用 play_one_shot()，播放期間 play_state() 的呼叫會被忽略（見 _one_shot_playing），
## 不會被移動/蓄力這類持續動畫打斷到一半。
const LOOPING := ["walk_down", "walk_up", "walk_left", "walk_right",
	"walk_down_left", "walk_down_right", "walk_up_left", "walk_up_right", "cast_charge"]

var _one_shot_playing := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_frames = _build_sprite_frames()
	animation_finished.connect(_on_animation_finished)
	_apply_transform("walk_down")
	play("walk_down")
	frame = 0
	stop()

func _build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	for anim_name in ANIMATIONS.keys():
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, anim_name in LOOPING)
		frames.set_animation_speed(anim_name, 8.0)
		for i in range(ANIMATIONS[anim_name]):
			var tex: Texture2D = load("%s%s_%d.png" % [FRAME_DIR, anim_name, i])
			frames.add_frame(anim_name, tex)
	return frames

## 持續性狀態動畫（走路8方向／蓄力）。idle_paused=true 時播放同一份動畫但停在第0幀（给
## 站立不動用——8方向的站姿直接重用對應走路動畫的第1幀，見生圖提示詞文件「實際操作建議」
## 第4點，不需要另外一組站姿素材）。一次性動畫播放中這裡的呼叫整個略過，等它自己播完。
func play_state(anim_name: String, idle_paused: bool = false) -> void:
	if _one_shot_playing:
		return
	if idle_paused:
		if animation != anim_name:
			_apply_transform(anim_name)
			animation = anim_name
		frame = 0
		stop()
	elif animation != anim_name or not is_playing():
		_apply_transform(anim_name)
		play(anim_name)

## 一次性動畫（法術釋放/受擊），播完自然觸發 animation_finished 解除佔用，不需要呼叫端
## 自己追蹤播完了沒——呼叫端只要繼續照常呼叫 play_state()，播放期間會被忽略，播完後下一幀
## 自動接回目前該有的狀態動畫。
func play_one_shot(anim_name: String) -> void:
	_one_shot_playing = true
	_apply_transform(anim_name)
	play(anim_name)

func _on_animation_finished() -> void:
	_one_shot_playing = false

func _apply_transform(anim_name: String) -> void:
	var category := anim_name if not anim_name.begins_with("walk_") else "walk"
	var t: Dictionary = TRANSFORM_BY_CATEGORY.get(category, {"scale": 0.28, "offset": Vector2.ZERO})
	scale = Vector2(t["scale"], t["scale"])
	offset = t["offset"]
