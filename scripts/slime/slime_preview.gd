extends Node2D
## Look preview for the nutrient slime (养分史莱姆, working name): crawler, bud and flower
## in real tunnel cells at the default play size. No movement and no ecology logic here.
##
## Keys: G cell / visual bounds, Z cycles view size (64 / 83 / 48 px per cell), Esc quit.
## CLI (after `--`): --grid, --zoom, --small, --shot=<png path> (save one still frame and quit).

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Grid := preload("res://scripts/burrow/burrow_grid.gd")
const MapScript := preload("res://scripts/burrow/burrow_map.gd")
const Look := preload("res://scripts/slime/slime_look.gd")

const LAYOUT: Array[String] = [
	"#################",
	"#...............#",
	"#.ooooooooooooo.#",
	"#.o...........o.#",
	"#.ooooooooooooo.#",
	"#.............o.#",
	"#.ooooooooooooo.#",
	"#...............#",
	"#################",
]

## cell, stage, nutrient, vigor, facing (radians), caption; optional palette / silhouette.
## "side": the cell is in a vertical shaft, so its caption goes beside it.
const ENTRIES: Array[Dictionary] = [
	{"cell": Vector2i(5, 2), "stage": Look.Stage.CRAWL, "n": 2, "vigor": 1.0, "facing": 0.0, "text": "爬行"},
	{"cell": Vector2i(8, 2), "stage": Look.Stage.BUD, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "结苞"},
	{"cell": Vector2i(11, 2), "stage": Look.Stage.FLOWER, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "开花"},
	{"cell": Vector2i(2, 3), "stage": Look.Stage.BUD, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "竖向花苞", "side": true},
	{"cell": Vector2i(14, 3), "stage": Look.Stage.CRAWL, "n": 2, "vigor": 1.0, "facing": -PI * 0.5, "text": "竖向爬行", "side": true},
	{"cell": Vector2i(14, 5), "stage": Look.Stage.FLOWER, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "竖向花", "side": true},
	{"cell": Vector2i(10, 4), "stage": Look.Stage.CRAWL, "n": 2, "vigor": 1.0, "facing": 0.0, "text": "健康"},
	{"cell": Vector2i(12, 4), "stage": Look.Stage.CRAWL, "n": 2, "vigor": 0.0, "facing": 0.0, "text": "虚弱"},
	{"cell": Vector2i(2, 6), "stage": Look.Stage.CRAWL, "n": 2, "vigor": 1.0, "facing": 0.0, "text": "剪影", "sil": true},
	{"cell": Vector2i(4, 6), "stage": Look.Stage.BUD, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "剪影", "sil": true},
	{"cell": Vector2i(6, 6), "stage": Look.Stage.FLOWER, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "剪影", "sil": true},
	{"cell": Vector2i(9, 6), "stage": Look.Stage.CRAWL, "n": 2, "vigor": 1.0, "facing": 0.0, "text": "换色示例", "pal": "blue"},
	{"cell": Vector2i(11, 6), "stage": Look.Stage.BUD, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "换色示例", "pal": "blue"},
	{"cell": Vector2i(13, 6), "stage": Look.Stage.FLOWER, "n": 0, "vigor": 1.0, "facing": 0.0, "text": "换色示例", "pal": "blue"},
]

const VIEW_ZOOM: Array[float] = [1.0, 1.3, 0.75]
const VIEW_NAME: Array[String] = ["默认 64 px/格", "放大 83 px/格", "小一档 48 px/格"]
const WORLD_POS := Vector2(96, 46)

var grid: RefCounted
var show_grid := false
var view := 0

var _world: Node2D
var _debug: Node2D
var _camera: Camera2D
var _looks: Array[Node2D] = []
var _view_label: Label
var _shot_path := ""
var _frames := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--grid":
			show_grid = true
		elif a == "--zoom":
			view = 1
		elif a == "--small":
			view = 2
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
		look.palette = e.get("pal", "green")
		look.silhouette = e.get("sil", false)
		_world.add_child(look)
		_looks.append(look)
		if e.get("side", false):
			_world.add_child(_caption(e.text, Vector2((e.cell.x + 1) * u, e.cell.y * u + 21), Vector2(u, 22), 14))
		else:
			_world.add_child(_caption(e.text, Vector2(e.cell.x * u - 48, (e.cell.y + 1) * u + 6), Vector2(u + 96, 22), 14))

	_debug = Node2D.new()
	_debug.z_index = 30
	_debug.draw.connect(_draw_debug)
	_world.add_child(_debug)

	_camera = Camera2D.new()
	add_child(_camera)

	var hud := CanvasLayer.new()
	add_child(hud)
	var title := _caption("养分史莱姆（暂定名）· 造型基线    1 格 = 64 px，默认游玩尺寸", Vector2(0, 8), Vector2(1280, 26), 17)
	hud.add_child(title)
	var hint := _caption("上：三个生命阶段    中：健康与虚弱并排    下：纯剪影、换色示例    两侧竖井：竖向通道中的样子    [G] 边界   [Z] 尺寸   [Esc] 退出",
		Vector2(0, 684), Vector2(1280, 24), 14)
	hint.add_theme_color_override("font_color", Color(0.78, 0.74, 0.7))
	hud.add_child(hint)
	_view_label = _caption("", Vector2(0, 34), Vector2(1280, 22), 14)
	_view_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.7))
	hud.add_child(_view_label)
	_apply_zoom()


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
	var z := VIEW_ZOOM[view]
	_camera.zoom = Vector2(z, z)
	_camera.position = WORLD_POS + Vector2(8.5, 4.7) * Spec.CELL_PX if view == 1 else Vector2(640, 360)
	if _view_label != null:
		_view_label.text = "视图：%s  [Z 切换]" % VIEW_NAME[view]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				show_grid = not show_grid
				_debug.queue_redraw()
			KEY_Z:
				view = (view + 1) % VIEW_ZOOM.size()
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
		# Visual bounds of the drawn body.
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
