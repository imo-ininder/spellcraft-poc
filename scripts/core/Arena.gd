extends Node2D

const TILE_SIZE := 56.0
const ARENA_WIDTH := 1200.0
const ARENA_HEIGHT := 700.0
const WALL_THICKNESS := 36.0
const BRICK_SEED := 9173

var tile_colors: Array = []

func _ready() -> void:
	_generate_tile_colors()
	queue_redraw()

func _generate_tile_colors() -> void:
	var cols := int(ceil(ARENA_WIDTH / TILE_SIZE)) + 2
	var rows := int(ceil(ARENA_HEIGHT / TILE_SIZE))
	var rng := RandomNumberGenerator.new()
	rng.seed = BRICK_SEED
	tile_colors.clear()
	for y in range(rows):
		var row: Array = []
		for x in range(cols):
			var shade: float = rng.randf_range(-0.05, 0.05)
			row.append(Color(0.4 + shade, 0.4 + shade, 0.43 + shade))
		tile_colors.append(row)

func _draw() -> void:
	for y in range(tile_colors.size()):
		var row_offset: float = (TILE_SIZE / 2.0) if y % 2 == 1 else 0.0
		var row: Array = tile_colors[y]
		for x in range(row.size()):
			var rect := Rect2(x * TILE_SIZE - row_offset, y * TILE_SIZE, TILE_SIZE - 2, TILE_SIZE - 2)
			draw_rect(rect, row[x])
			draw_rect(rect, Color(0.22, 0.22, 0.24), false, 1.5)

	var border_color := Color(0.28, 0.26, 0.3)
	draw_rect(Rect2(-WALL_THICKNESS, -WALL_THICKNESS, ARENA_WIDTH + WALL_THICKNESS * 2, WALL_THICKNESS), border_color)
	draw_rect(Rect2(-WALL_THICKNESS, ARENA_HEIGHT, ARENA_WIDTH + WALL_THICKNESS * 2, WALL_THICKNESS), border_color)
	draw_rect(Rect2(-WALL_THICKNESS, -WALL_THICKNESS, WALL_THICKNESS, ARENA_HEIGHT + WALL_THICKNESS * 2), border_color)
	draw_rect(Rect2(ARENA_WIDTH, -WALL_THICKNESS, WALL_THICKNESS, ARENA_HEIGHT + WALL_THICKNESS * 2), border_color)
