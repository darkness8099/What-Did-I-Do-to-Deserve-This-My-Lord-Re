extends Node2D
## Look preview for the mudling (泥胎, working name): crawler, bud and flower side by side
## in real tunnel cells at the default play size. No movement and no ecology logic here.
##
## Keys: G cell / visual bounds, Z zoom, Esc quit.
## CLI (after `--`): --grid, --zoom, --shot=<png path> (save one still frame and quit).

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Grid := preload("res://scripts/burrow/burrow_grid.gd")
const MapScript := preload("res://scripts/burrow/burrow_map.gd")
const Look := preload("res://scripts/mudling/mudling_look.gd")

const LAYOUT: Array[String] = [
	"#################",
	"#...............#",
	"#...............#",
	"#..ooooooooooo..#",
	"#...............#",
	"#...............#",
	"#..ooooooooooo..#",
	"#...............#",
	"#################",
]

## cell, stage, nutrient, vigor, facing (radians), caption
const ENTRIES: Array[Dictionary] = [
	{"cell": Vector2i(5, 3), "stage": Look.Stage.CRAWL, "n": 1, "vigor": 1.0, "facing": 0.0, "text": "爬行"},
	{"cell": Vector2i(8, 3), "stage": Look.Stage.BUD, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "结苞"},
	{"cell": Vector2i(11, 3), "stage": Look.Stage.FLOWER, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "开花"},
	{"cell": Vector2i(5, 6), "stage": Look.Stage.CRAWL, "n": 0, "vigor": 1.0, "facing": PI, "text": "养分 0"},
	{"cell": Vector2i(8, 6), "stage": Look.Stage.CRAWL, "n": 3, "vigor": 1.0, "facing": 0.0, "text": "养分 3"},
	{"cell": Vector2i(11, 6), "stage": Look.Stage.CRAWL, "n": 2, "vigor": 0.0, "facing": 0.0, "text": "虚弱"},
]

const ZOOM := 2.0
const WORLD_POS := Vector2(96, 46)

var grid: RefCounted
var show_grid := false
var zoomed := false

var _world: Node2D
var _debug: Node2D
var _camera: Camera2D
var _looks: Array[Node2D] = []
var _shot_path := ""
var _frames := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--grid":
			show_grid = true
		elif a == "--zoom":
			zoomed = true
		elif a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")

	grid = Grid.new()
	grid.load_layout(LAYOUT)

	_world = Node2D.new()
	_world.position = WORLD_POS
	add_child(_world)
	var map := Node2D.new()
	map.set_script(MapScript)
	_world.add_child(map)
	map.setup(grid)

	var u := Spec.CELL_PX
	for i in ENTRIES.size():
		var e := ENTRIES[i]
		var look := Node2D.new()
		look.set_script(Look)
		look.position = Spec.center(e.cell) * u
		look.stage = e.stage
		look.nutrient = e.n
		look.vigor = e.vigor
		look.facing = e.facing
		look.seed_id = i + 1
		var walls: Array[Vector2] = []
		for d in Spec.DIRS:
			if not grid.is_open(e.cell + d):
				walls.append(Vector2(d))
		look.walls = walls
		_world.add_child(look)
		_looks.append(look)
		_world.add_child(_caption(e.text, Vector2(e.cell.x * u - 48, (e.cell.y + 1) * u + 8), Vector2(u + 96, 22), 15))

	_debug = Node2D.new()
	_debug.z_index = 30
	_debug.draw.connect(_draw_debug)
	_world.add_child(_debug)

	_camera = Camera2D.new()
	add_child(_camera)
	_apply_zoom()

	var hud := CanvasLayer.new()
	add_child(hud)
	var title := _caption("泥胎（暂定名）· 造型预览    1 格 = 64 px，默认游玩尺寸", Vector2(0, 8), Vector2(1280, 26), 17)
	hud.add_child(title)
	var hint := _caption("上排：三个生命阶段    下排：爬行阶段的养分与虚弱小样    [G] 一格范围与视觉边界   [Z] 放大   [Esc] 退出",
		Vector2(0, 684), Vector2(1280, 24), 14)
	hint.add_theme_color_override("font_color", Color(0.78, 0.74, 0.7))
	hud.add_child(hint)


func _caption(text: String, pos: Vector2, size: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.82))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _apply_zoom() -> void:
	if zoomed:
		_camera.zoom = Vector2(ZOOM, ZOOM)
		_camera.position = WORLD_POS + Vector2(8.5, 5.1) * Spec.CELL_PX
	else:
		_camera.zoom = Vector2.ONE
		_camera.position = Vector2(640, 360)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				show_grid = not show_grid
				_debug.queue_redraw()
			KEY_Z:
				zoomed = not zoomed
				_apply_zoom()
			KEY_ESCAPE:
				get_tree().quit()


func _draw_debug() -> void:
	if not show_grid:
		return
	var u := Spec.CELL_PX
	for i in ENTRIES.size():
		var cell: Vector2i = ENTRIES[i].cell
		# Logical footprint: exactly one cell.
		_debug.draw_rect(Rect2(Vector2(cell) * u, Vector2(u, u)), Color(0.45, 0.9, 1.0, 0.9), false, 1.5)
		# Visual bounds of the drawn body (strands excluded).
		var half: Vector2 = _looks[i].visual_half_extent() * u
		_debug.draw_rect(Rect2(_looks[i].position - half, half * 2.0), Color(1.0, 0.85, 0.35, 0.9), false, 1.2)


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_frames += 1
	if _frames == 40:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_shot_path)
		print("shot saved: ", _shot_path, " err=", err)
		get_tree().quit()
