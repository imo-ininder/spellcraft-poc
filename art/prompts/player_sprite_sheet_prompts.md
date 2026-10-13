# 主角色 Sprite Sheet 生成提示詞

給 AI 繪圖工具（Midjourney / Stable Diffusion / PixelLab / Retro Diffusion 等）用的提示詞，目標是每次生成**一張包含完整網格的 sprite sheet 大圖**，之後再用切圖工具／程式依照下面標的格數切成個別幀。

每組提示詞都是**完整、可以直接複製貼上**的版本，不需要自己拼接。

> 角色設定：狂氣、自大的黑暗法師，不是溫馴可愛的傳統奇幻法師——沒有帽子，深藍黑色系服裝，金色滾邊傳達自大／貴氣，電光藍紫色魔法發光傳達狂氣／失控的能量感。保留遊戲既有的 Q 版誇張比例（大頭小身體），但姿態/表情/服裝要撐起「狂傲」的個性，不是走可愛路線。3/4 俯視視角（地板純俯視、角色本身有正面感，不是等角投影）——細節見 `docs/SYSTEMS.md` §3.1。

> 色票：外套底色 `#0B0F1A`／暗面`#1B2838`、金色滾邊`#D4AF37`、魔法發光（眼神/法杖光球/法陣）`#4FD8E8`、膚色`#F2D1A6`、頭髮`#12141A`。

> **2026-10-12 調整**：第一輪生成結果偏「精緻」——線條太細、細節太多，看起來像高解析度插畫硬套 pixel art 濾鏡，不是真正的低解析度像素圖。下面所有提示詞都加了明確的解析度/色塊粗細要求（約32px高的角色、色數從 10-14 色收到 6-8 色），逼生成工具往「色塊更粗、細節更少」的方向走，不是只靠「pixel art style」這種模糊形容詞。

---

## Sheet B：移動動畫（走路循環，上下左右 4 個基本方向）

**網格：4 欄 × 4 列（共 16 格）**，每個方向 4 幀一個循環。**每個方向的第1幀/第3幀（中立姿勢）直接拿來當該方向的站姿／idle 用，不需要另外生成 Sheet A。**

```
Chibi dark sorcerer character, pixel art style, top-down RPG game sprite (3/4
top-down camera angle like Stardew Valley / Secret of Mana — NOT isometric,
character stands upright facing camera, not tilted like a true isometric sprite).
Render at a deliberately LOW, CHUNKY pixel resolution — think a tiny ~32px-tall
retro sprite blown up to view, NOT a detailed illustration merely styled to
look pixel-ish: thick blocky pixels, simple flat shapes, minimal fine linework
or micro-detail, the kind of coarse resolution where individual pixel squares
are clearly visible.
Cute 2.5-head-tall exaggerated proportions, oversized round head, small body —
but with an arrogant, wild, dangerous personality, NOT innocent or soft. No hat —
messy, spiky, untamed dark hair (#12141A) swept back with a few loose strands,
conveying barely-restrained chaotic energy. Sharp narrow eyes glowing electric
cyan-violet (#4FD8E8), a confident smug smirk, eyebrows angled for a haughty
superior expression. Pale fair skin (#F0DCC4). Wears a long open dark coat
(deep navy-black #0B0F1A main, #1B2838 shaded folds) with bold gold trim
(#D4AF37) lining the high popped collar, cuffs, and hem — asymmetric design,
one side draped more dramatically than the other, proud imposing silhouette.
Holds a dark twisted staff (#12141A) topped with a glowing electric cyan-violet
crystal orb (#4FD8E8). Clean pixel art linework, hard crisp pixel edges, flat
solid color blocks, NO blur, NO soft gradients, NO anti-aliasing — genuine
low-resolution pixel art look, not a smooth illustration. Very limited color
palette (6-8 colors), flat cel-shading with 1-2 tones per surface. Saturated
high-contrast colors against the dark coat, dramatic intense fantasy tone —
proud, dangerous, unhinged, NOT cute or innocent despite the chibi proportions.

TRANSPARENT BACKGROUND — true PNG alpha transparency, completely empty, no
background content of any kind, not a solid color, not a pattern, not a
checkerboard. Critical: render all glow/magic particle effects (staff orb,
magic rings, sparks) as FLAT-SHADED shapes with HARD, CRISP pixel edges —
like layered solid-color diamonds, stars, and rings in genuine pixel art —
NOT as soft radial-gradient bloom or blurred glow. A blurred soft glow
blends into the background and leaves contaminated edges; a hard-edged flat
shape has a clean boundary.

Generate a single sprite sheet image, a precise grid of 4 columns x 4 rows,
16 cells total, equal-sized cells, no gaps/borders/grid lines/labels between
cells, character at identical scale/size/baseline in every single cell so the
sheet can be cut into a uniform grid.

Each row is a 4-frame looping walk cycle for one facing direction. Make the
pose difference between frames clearly, strongly visible (not subtle) — this
is a small sprite, weak differences won't read as motion:
- Frame 1: neutral mid-step pose, coat hanging straight down.
- Frame 2: body clearly shifted upward (a visible hop/bob), coat swinging
  forcefully outward to one side with a sharp silhouette change, like a
  confident long stride.
- Frame 3: neutral mid-step pose again, identical to frame 1.
- Frame 4: body clearly shifted downward (a visible dip), coat swinging
  forcefully to the opposite side from frame 2, mirrored silhouette change.

Row 1: facing down/front (toward camera), walk cycle frames 1-4 as described above.
Row 2: facing up/back (away from camera), walk cycle frames 1-4 as described above.
Row 3: facing left, walk cycle frames 1-4 as described above, body and staff-hand
  oriented for a leftward-facing pose.
Row 4: facing right — this row MUST be a precise horizontal mirror of row 3,
  the exact same walk cycle and silhouette flipped left-to-right, NOT a
  different pose. Staff should be in the opposite hand from row 3.

Character design, colors, and proportions must stay perfectly consistent across
all 16 cells.
```

---

## Sheet B2：移動動畫（走路循環，左上/右上/左下/右下 4 個對角方向）

**網格：4 欄 × 4 列（共 16 格）**，跟 Sheet B 同一套走路幀結構，補上 Sheet B 沒有的對角方向。刻意跟 Sheet B 分開生成成兩張各 16 格的圖，不是合併成一張 32 格——格數越多，AI 一次生成的一致性通常越差，拆成兩張風險比較低（這也是下面「實際操作建議」原本就有的建議）。

```
Chibi dark sorcerer character, pixel art style, top-down RPG game sprite (3/4
top-down camera angle like Stardew Valley / Secret of Mana — NOT isometric,
character stands upright facing camera, not tilted like a true isometric sprite).
Render at a deliberately LOW, CHUNKY pixel resolution — think a tiny ~32px-tall
retro sprite blown up to view, NOT a detailed illustration merely styled to
look pixel-ish: thick blocky pixels, simple flat shapes, minimal fine linework
or micro-detail, the kind of coarse resolution where individual pixel squares
are clearly visible.
Cute 2.5-head-tall exaggerated proportions, oversized round head, small body —
but with an arrogant, wild, dangerous personality, NOT innocent or soft. No hat —
messy, spiky, untamed dark hair (#12141A) swept back with a few loose strands,
conveying barely-restrained chaotic energy. Sharp narrow eyes glowing electric
cyan-violet (#4FD8E8), a confident smug smirk, eyebrows angled for a haughty
superior expression. Pale fair skin (#F0DCC4). Wears a long open dark coat
(deep navy-black #0B0F1A main, #1B2838 shaded folds) with bold gold trim
(#D4AF37) lining the high popped collar, cuffs, and hem — asymmetric design,
one side draped more dramatically than the other, proud imposing silhouette.
Holds a dark twisted staff (#12141A) topped with a glowing electric cyan-violet
crystal orb (#4FD8E8). Clean pixel art linework, hard crisp pixel edges, flat
solid color blocks, NO blur, NO soft gradients, NO anti-aliasing — genuine
low-resolution pixel art look, not a smooth illustration. Very limited color
palette (6-8 colors), flat cel-shading with 1-2 tones per surface. Saturated
high-contrast colors against the dark coat, dramatic intense fantasy tone —
proud, dangerous, unhinged, NOT cute or innocent despite the chibi proportions.

TRANSPARENT BACKGROUND — true PNG alpha transparency, completely empty, no
background content of any kind, not a solid color, not a pattern, not a
checkerboard. Critical: render all glow/magic particle effects (staff orb,
magic rings, sparks) as FLAT-SHADED shapes with HARD, CRISP pixel edges —
like layered solid-color diamonds, stars, and rings in genuine pixel art —
NOT as soft radial-gradient bloom or blurred glow. A blurred soft glow
blends into the background and leaves contaminated edges; a hard-edged flat
shape has a clean boundary.

Generate a single sprite sheet image, a precise grid of 4 columns x 4 rows,
16 cells total, equal-sized cells, no gaps/borders/grid lines/labels between
cells, character at identical scale/size/baseline in every single cell so the
sheet can be cut into a uniform grid. The character's scale and proportions
must exactly match the previously generated 4-direction walk cycle sheet
(same character, same outfit, same staff, same size) — this is a second sheet
that extends that same walk cycle to 4 more directions.

Each row is a 4-frame looping walk cycle for one 3/4-angled facing direction.
Make the pose difference between frames clearly, strongly visible (not subtle):
- Frame 1: neutral mid-step pose, coat hanging straight down.
- Frame 2: body clearly shifted upward (a visible hop/bob), coat swinging
  forcefully outward to one side with a sharp silhouette change, like a
  confident long stride.
- Frame 3: neutral mid-step pose again, identical to frame 1.
- Frame 4: body clearly shifted downward (a visible dip), coat swinging
  forcefully to the opposite side from frame 2, mirrored silhouette change.

Row 1: facing down-left (southwest) — a 3/4 front-left angle, character body
  and face angled toward the lower-left, mostly facing the camera but turned,
  walk cycle frames 1-4 as described above.
Row 2: facing down-right (southeast) — this row MUST be a precise horizontal
  mirror of row 1, the exact same walk cycle and silhouette flipped
  left-to-right, NOT a different pose. Staff in the opposite hand from row 1.
Row 3: facing up-left (northwest) — a 3/4 back-left angle, character body and
  back angled toward the upper-left, mostly facing away from the camera but
  turned, no face visible, walk cycle frames 1-4 as described above.
Row 4: facing up-right (northeast) — this row MUST be a precise horizontal
  mirror of row 3, the exact same walk cycle and silhouette flipped
  left-to-right, NOT a different pose. Staff in the opposite hand from row 3.

Character design, colors, and proportions must stay perfectly consistent across
all 16 cells, and consistent with the 4-cardinal-direction walk cycle sheet
generated separately.
```

---

## Sheet C：施放動畫 — 蓄力階段

**網格：4 欄 × 1 列（共 4 格）**，所有法術施放都共用這個蓄力動畫，之後接 Sheet D（buff類）或 Sheet E（攻擊類）其中一個釋放動畫。4 幀首尾能接起來循環播放。

```
Chibi dark sorcerer character, pixel art style, top-down RPG game sprite (3/4
top-down camera angle like Stardew Valley / Secret of Mana — NOT isometric,
character stands upright facing camera, not tilted like a true isometric sprite).
Render at a deliberately LOW, CHUNKY pixel resolution — think a tiny ~32px-tall
retro sprite blown up to view, NOT a detailed illustration merely styled to
look pixel-ish: thick blocky pixels, simple flat shapes, minimal fine linework
or micro-detail, the kind of coarse resolution where individual pixel squares
are clearly visible.
Cute 2.5-head-tall exaggerated proportions, oversized round head, small body —
but with an arrogant, wild, dangerous personality, NOT innocent or soft. No hat —
messy, spiky, untamed dark hair (#12141A) swept back with a few loose strands,
conveying barely-restrained chaotic energy. Sharp narrow eyes glowing electric
cyan-violet (#4FD8E8), a confident smug smirk, eyebrows angled for a haughty
superior expression. Pale fair skin (#F0DCC4). Wears a long open dark coat
(deep navy-black #0B0F1A main, #1B2838 shaded folds) with bold gold trim
(#D4AF37) lining the high popped collar, cuffs, and hem — asymmetric design,
one side draped more dramatically than the other, proud imposing silhouette.
Holds a dark twisted staff (#12141A) topped with a glowing electric cyan-violet
crystal orb (#4FD8E8). Clean pixel art linework, hard crisp pixel edges, flat
solid color blocks, NO blur, NO soft gradients, NO anti-aliasing — genuine
low-resolution pixel art look. Very limited color palette (6-8 colors), flat
cel-shading with 1-2 tones per surface. Saturated high-contrast colors,
dramatic intense fantasy tone.

TRANSPARENT BACKGROUND — true PNG alpha transparency, completely empty, no
background content of any kind, not a solid color, not a pattern, not a
checkerboard. Critical: render all glow/magic particle effects (staff orb,
magic rings, sparks) as FLAT-SHADED shapes with HARD, CRISP pixel edges —
like layered solid-color diamonds, stars, and rings in genuine pixel art —
NOT as soft radial-gradient bloom or blurred glow. A blurred soft glow
blends into the background and leaves contaminated edges; a hard-edged flat
shape has a clean boundary.

Generate a single sprite sheet image, a precise grid of 4 columns x 1 row,
4 cells total, equal-sized cells, no gaps/borders/grid lines/labels between
cells, character at identical scale/size/baseline in every cell.

Front view, character facing the camera (facing down/front), staff held
raised slightly forward, pose stays mostly static across all 4 frames
(charging up, not moving yet) — only the glow/aura/particles animate, forming
a loop (frame 4 should flow smoothly back into frame 1):

Frame 1: staff orb glowing dim, eyes glowing faintly, a thin faint magic ring
  around the character's feet, small radius.
Frame 2: staff orb glowing brighter, eyes glowing more intensely, the magic
  ring expanding to medium radius with jagged crackling edges.
Frame 3: staff orb at brightest/largest glow, eyes blazing, the magic ring at
  its largest radius with erratic crackling arcs of energy, a few small
  electric spark particles around the staff tip and shoulders.
Frame 4: staff orb dimming slightly back down from peak, eyes still intense,
  the magic ring settling back toward medium size, sparks fading — this frame
  represents "fully charged, about to release," not back to frame 1's resting
  state (the actual release happens in a separate animation).
```

---

## Sheet D：施放動畫 — 釋放瞬間（buff 類，法杖往上舉）

**網格：3 欄 × 1 列（共 3 格）**，接在 Sheet C 蓄力完之後播放一次（不循環）。buff 類法術（例如隱形術、速度提升）用這個。

```
Chibi dark sorcerer character, pixel art style, top-down RPG game sprite (3/4
top-down camera angle like Stardew Valley / Secret of Mana — NOT isometric,
character stands upright facing camera, not tilted like a true isometric sprite).
Render at a deliberately LOW, CHUNKY pixel resolution — think a tiny ~32px-tall
retro sprite blown up to view, NOT a detailed illustration merely styled to
look pixel-ish: thick blocky pixels, simple flat shapes, minimal fine linework
or micro-detail, the kind of coarse resolution where individual pixel squares
are clearly visible.
Cute 2.5-head-tall exaggerated proportions, oversized round head, small body —
but with an arrogant, wild, dangerous personality, NOT innocent or soft. No hat —
messy, spiky, untamed dark hair (#12141A) swept back with a few loose strands,
conveying barely-restrained chaotic energy. Sharp narrow eyes glowing electric
cyan-violet (#4FD8E8), a confident smug smirk, eyebrows angled for a haughty
superior expression. Pale fair skin (#F0DCC4). Wears a long open dark coat
(deep navy-black #0B0F1A main, #1B2838 shaded folds) with bold gold trim
(#D4AF37) lining the high popped collar, cuffs, and hem. Holds a dark twisted
staff (#12141A) topped with a glowing electric cyan-violet crystal orb
(#4FD8E8). Clean pixel art linework, hard crisp pixel edges, flat solid color
blocks, NO blur, NO anti-aliasing — genuine low-resolution pixel art look.
Very limited color palette (6-8 colors), flat cel-shading.

TRANSPARENT BACKGROUND — true PNG alpha transparency, completely empty, no
background content of any kind, not a solid color, not a pattern, not a
checkerboard. Critical: render all glow/magic particle effects (staff orb,
magic rings, sparks, energy bursts) as FLAT-SHADED shapes with HARD, CRISP
pixel edges — like layered solid-color diamonds, stars, and rings in genuine
pixel art — NOT as soft radial-gradient bloom or blurred glow. A blurred
soft glow blends into the background and leaves contaminated edges; a
hard-edged flat shape has a clean boundary.

Generate a single sprite sheet image, a precise grid of 3 columns x 1 row,
3 cells total, equal-sized cells, no gaps/borders/grid lines/labels between
cells, character at identical scale/size/baseline in every cell.

Front view, character facing the camera. A triumphant, self-empowering "claiming
power" release gesture — the staff is thrust straight UP overhead, not forward:

Frame 1 (anticipation): character begins raising the staff upward and overhead,
  arm extending up, head tilting back slightly, body coiling upward, orb
  glow intensifying.
Frame 2 (peak release): staff fully raised straight up overhead, arm fully
  extended, head tilted back, eyes blazing wide open, a bright burst of
  cyan-violet energy erupts upward from the orb in an expanding upward
  spiral/column, triumphant arrogant expression (like claiming victory),
  this is the dramatic peak of the animation.
Frame 3 (settle): staff lowering slightly back down from overhead, energy
  burst dissipating into fading sparkles drifting upward, expression
  settling back to a confident smirk.
```

---

## Sheet E：施放動畫 — 釋放瞬間（攻擊類，法杖往前指）

**網格：3 欄 × 1 列（共 3 格）**，接在 Sheet C 蓄力完之後播放一次（不循環）。攻擊類法術（例如火球術、魔法飛彈）用這個。

```
Chibi dark sorcerer character, pixel art style, top-down RPG game sprite (3/4
top-down camera angle like Stardew Valley / Secret of Mana — NOT isometric,
character stands upright facing camera, not tilted like a true isometric sprite).
Render at a deliberately LOW, CHUNKY pixel resolution — think a tiny ~32px-tall
retro sprite blown up to view, NOT a detailed illustration merely styled to
look pixel-ish: thick blocky pixels, simple flat shapes, minimal fine linework
or micro-detail, the kind of coarse resolution where individual pixel squares
are clearly visible.
Cute 2.5-head-tall exaggerated proportions, oversized round head, small body —
but with an arrogant, wild, dangerous personality, NOT innocent or soft. No hat —
messy, spiky, untamed dark hair (#12141A) swept back with a few loose strands,
conveying barely-restrained chaotic energy. Sharp narrow eyes glowing electric
cyan-violet (#4FD8E8), a confident smug smirk, eyebrows angled for a haughty
superior expression. Pale fair skin (#F0DCC4). Wears a long open dark coat
(deep navy-black #0B0F1A main, #1B2838 shaded folds) with bold gold trim
(#D4AF37) lining the high popped collar, cuffs, and hem. Holds a dark twisted
staff (#12141A) topped with a glowing electric cyan-violet crystal orb
(#4FD8E8). Clean pixel art linework, hard crisp pixel edges, flat solid color
blocks, NO blur, NO anti-aliasing — genuine low-resolution pixel art look.
Very limited color palette (6-8 colors), flat cel-shading.

TRANSPARENT BACKGROUND — true PNG alpha transparency, completely empty, no
background content of any kind, not a solid color, not a pattern, not a
checkerboard. Critical: render all glow/magic particle effects (staff orb,
magic rings, sparks, energy bursts) as FLAT-SHADED shapes with HARD, CRISP
pixel edges — like layered solid-color diamonds, stars, and rings in genuine
pixel art — NOT as soft radial-gradient bloom or blurred glow. A blurred
soft glow blends into the background and leaves contaminated edges; a
hard-edged flat shape has a clean boundary.

Generate a single sprite sheet image, a precise grid of 3 columns x 1 row,
3 cells total, equal-sized cells, no gaps/borders/grid lines/labels between
cells, character at identical scale/size/baseline in every cell.

Front view, character facing the camera. An aggressive attacking jab gesture —
the staff is thrust straight FORWARD toward the viewer/downward, not overhead:

Frame 1 (anticipation): character pulls the staff back slightly, leaning back,
  coiling for the strike, orb glow intensifying, aggressive narrowed eyes.
Frame 2 (peak release): staff thrust sharply forward/downward toward the
  camera, arm fully extended forward, body leaning forward aggressively,
  sharp predatory grin, a sharp concentrated burst of cyan-violet energy
  fires forward from the orb tip like a muzzle flash, this is the dramatic
  peak of the animation.
Frame 3 (recoil): body/staff recoiling slightly back from the forward thrust,
  energy burst fading into dissipating sparks, confident smirk remaining.
```

---

## Sheet F：受傷動畫

**網格：4 欄 × 1 列（共 4 格）**，表現「會痛但不服輸」——不是哀號退縮，是咬牙硬撐、眼神依然挑釁。

```
Chibi dark sorcerer character, pixel art style, top-down RPG game sprite (3/4
top-down camera angle like Stardew Valley / Secret of Mana — NOT isometric,
character stands upright facing camera, not tilted like a true isometric sprite).
Render at a deliberately LOW, CHUNKY pixel resolution — think a tiny ~32px-tall
retro sprite blown up to view, NOT a detailed illustration merely styled to
look pixel-ish: thick blocky pixels, simple flat shapes, minimal fine linework
or micro-detail, the kind of coarse resolution where individual pixel squares
are clearly visible.
Cute 2.5-head-tall exaggerated proportions, oversized round head, small body —
but with an arrogant, wild, dangerous personality, NOT innocent or soft. No hat —
messy, spiky, untamed dark hair (#12141A) swept back with a few loose strands.
Pale fair skin (#F0DCC4). Wears a long open dark coat (deep navy-black #0B0F1A
main, #1B2838 shaded folds) with bold gold trim (#D4AF37) lining the high
popped collar, cuffs, and hem. Clean pixel art linework, hard crisp pixel
edges, flat solid color blocks, NO blur, NO anti-aliasing — genuine
low-resolution pixel art look. Very limited color palette (6-8 colors),
flat cel-shading.

TRANSPARENT BACKGROUND — true PNG alpha transparency, completely empty, no
background content of any kind, not a solid color, not a pattern, not a
checkerboard. Critical: render all glow/magic particle effects (staff orb,
magic rings, sparks, energy bursts) as FLAT-SHADED shapes with HARD, CRISP
pixel edges — like layered solid-color diamonds, stars, and rings in genuine
pixel art — NOT as soft radial-gradient bloom or blurred glow. A blurred
soft glow blends into the background and leaves contaminated edges; a
hard-edged flat shape has a clean boundary.

Generate a single sprite sheet image, a precise grid of 4 columns x 1 row,
4 cells total, equal-sized cells, no gaps/borders/grid lines/labels between
cells, character at identical scale/size/baseline in every cell.

Front view, character facing the camera, reacting to taking damage. The
expression must read as "hurt but defiant/unyielding" — gritted teeth bared
in a snarl, NOT whimpering or cowering, NOT crumpling down. One eye glowing
cyan-violet (#4FD8E8) and squeezed tightly shut from pain, the OTHER eye kept
wide open and still glowing fiercely, glaring back with defiance. Body flinches
but posture stays proud and upright, chin still slightly raised even while hurt.

Frame 1: normal confident neutral pose, both eyes open, smug expression —
  the moment just before impact.
Frame 2 (impact): body flinches sharply, head snaps slightly to one side,
  one eye slams shut tight in pain, teeth gritted bared in a snarl, small
  spark/impact flash effect near the point of contact.
Frame 3 (peak pain, defiant): body still slightly hunched/tense from the hit,
  one eye still squeezed shut, the other eye wide open glowing intensely and
  glaring with defiance, teeth still gritted — this is the "hurt but refuses
  to back down" key pose, held for emphasis.
Frame 4 (recovering): body straightening back up, the shut eye beginning to
  reopen, snarl easing back toward the usual confident smirk, posture
  returning to proud and upright.
```

---

## 實際操作建議

1. 每張 sheet 分開生成，彼此靠提示詞裡重複的角色描述維持一致，不是靠同一次生成保證一致。如果工具支援 img2img／reference image，拿第一張生成好、品質滿意的圖（例如 Sheet B）當參考圖去生其他張，一致性會比每次從零生成好很多——**Sheet B2 尤其建議這樣做**，確保跟 Sheet B 是同一個角色、同一個比例。
2. 洋紅色鍵去背這招在這個角色身上行不通，發光法杖/魔法陣/火花這些柔邊特效會跟底色混色，去背之後到處殘留色塊，上面所有提示詞已經改回去。額外加了「發光特效要硬邊色塊、不要柔和暈染」這條規則，降低殘留風險。拿到圖之後交給我，我只做邊緣清理（不是色鍵去背）＋最近鄰縮圖。
3. 走路循環（Sheet B／B2）如果生成出來「左」「右」兩排還是長得很像、不是鏡像，或是每一幀動作差異還是很小，可以考慮拆成兩次各生成一半（例如 Sheet B 拆成「正面+背面」一次、「左+右」一次），格數變少通常生成品質/一致性會更好。
4. **站姿／idle 直接重用 Sheet B／B2 的第1幀（中立姿勢）**，不需要另外生成 Sheet A 那組靜態 8 方向——8 個方向的站姿已經包含在這兩張走路 sheet 裡了（Sheet B 給上下左右、Sheet B2 給四個對角）。
5. 施法動畫現在是「蓄力(Sheet C，循環播放) → 放開按鍵後接 Sheet D 或 Sheet E 其中一個（依裝備法術是 buff 還是攻擊類，播一次不循環）」，這個分支邏輯之後會對應到遊戲裡 `Spell` 的類型（看 `SpellDelivery` 是 `SelfBuffDelivery` 還是其他攻擊類）去決定要接哪一段，不是程式碼現在就有的機制，記錄在這裡提醒以後串接動畫系統時要接這個邏輯。
6. 受傷動畫（Sheet F）同樣只做正面一版，之後要不要做其他方向視實際效果需求再說。
