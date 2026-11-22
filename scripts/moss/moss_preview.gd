extends Node2D
## Look preview for the moss in side view: crawling, bud and flower (task ART-004). No movement across the
## map and no ecology logic: each sample crawls on the spot so its cycle can be watched.
##
## Keys: Z cycles view size (64 / 80 / 48 px per cell), G cell and visual bounds, Esc quit.
## CLI (after `--`): --grid, --zoom, --small, --t=<seconds before the shot>,
##       --shot=<png path> (save one still and quit).

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Grid := preload("res://scripts/burrow/burrow_grid.gd")
const MapScript := preload("res://scripts/burrow/burrow_map.gd")
const Moss := preload("res://scripts/moss/moss_look.gd")

const LAYOUT: Array[String] = [
	"#################",
	"#...............#",
	"#.ooooooooooooo.#",
	"#.....o.....o...#",
	"#.....o.....o...#",
	"#.ooooooooooooo.#",
	"#...............#",
	"#.ooooooooooooo.#",
	"#...............#",
	"#################",
]

const ENTRIES: Array[Dictionary] = [
	{"cell": Vector2i(3, 2), "heading": Moss.Heading.RIGHT, "text": "向右"},
	{"cell": Vector2i(9, 2), "heading": Moss.Heading.LEFT, "text": "向左"},
	{"cell": Vector2i(6, 3), "heading": Moss.Heading.UP, "text": "向上（背面）", "side": true},
	{"cell": Vector2i(12, 4), "heading": Moss.Heading.DOWN, "text": "向下（正面）", "side": true},
	{"cell": Vector2i(11, 2), "stage": Moss.Stage.BUD, "text": "花苞"},
	{"cell": Vector2i(13, 2), "stage": Moss.Stage.FLOWER, "text": "花"},
	{"cell": Vector2i(6, 4), "stage": Moss.Stage.BUD, "text": "竖井中的花苞", "side": true},
	{"cell": Vector2i(3, 5), "heading": Moss.Heading.RIGHT, "text": "健康"},
	{"cell": Vector2i(5, 5), "heading": Moss.Heading.RIGHT, "vigor": 0.0, "text": "虚弱"},
	{"cell": Vector2i(8, 5), "heading": Moss.Heading.RIGHT, "still": true, "text": "静止"},
	{"cell": Vector2i(10, 5), "heading": Moss.Heading.RIGHT, "text": "从花苞前经过"},
	{"cell": Vector2i(10, 5), "stage": Moss.Stage.BUD, "text": "", "under": true},
	{"cell": Vector2i(12, 5), "stage": Moss.Stage.BUD, "vigor": 0.0, "text": "枯萎的花苞"},
	{"cell": Vector2i(13, 5), "stage": Moss.Stage.FLOWER, "vigor": 0.0, "text": "谢了的花"},
	{"cell": Vector2i(3, 7), "loop": "root", "text": "过渡：扎根结苞"},
	{"cell": Vector2i(6, 7), "loop": "bloom", "text": "过渡：开花"},
	{"cell": Vector2i(9, 7), "loop": "wither", "text": "过渡：花苞枯萎"},
	{"cell": Vector2i(12, 7), "loop": "release", "text": "过渡：花谢"},
]

## Looping demos of each transition: [seconds before, seconds of transition, seconds after].
const LOOPS := {"root": [1.2, 1.2, 1.6], "bloom": [1.2, 1.0, 1.8], "wither": [1.2, 1.4, 1.0], "release": [1.4, 1.2, 1.0]}

const VIEW_ZOOM: Array[float] = [1.0, 1.25, 0.75]
const VIEW_NAME: Array[String] = ["默认 64 px/格", "放大 80 px/格", "小一档 48 px/格"]
const WORLD_POS := Vector2(96, 50)

var grid: RefCounted
var show_grid := false
var view := 0

var _world: Node2D
var _debug: Node2D
var _camera: Camera2D
var _looks: Array[Node2D] = []
var _view_label: Label
var _shot_path := ""
var _time := 0.0
var _shot_at := 0.9
var _only := ""                    ## debug: play just this transition loop


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--grid":
			show_grid = true
		elif a == "--zoom":
			view = 1
		elif a == "--small":
			view = 2
		elif a.begins_with("--only="):
			_only = a.trim_prefix("--only=")
		elif a.begins_with("--t="):
			_shot_at = float(a.trim_prefix("--t="))
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
	for e in ENTRIES:
		var look := Node2D.new()
		look.set_script(Moss)
		look.position = Spec.center(e.cell) * u
		look.heading = e.get("heading", Moss.Heading.RIGHT)
		look.stage = e.get("stage", Moss.Stage.CRAWL)
		look.z_index = -1 if e.get("under", false) else 0
		look.vigor = e.get("vigor", 1.0)
		look.moving = not e.get("still", false)
		_world.add_child(look)
		_looks.append(look)
		if e.get("side", false):
			_world.add_child(_caption(e.text, Vector2((e.cell.x + 1) * u - 8, e.cell.y * u + 21), Vector2(u * 2, 22), 14))
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
	hud.add_child(_caption("苔 · 爬行、花苞、花（侧视）造型预览    1 格 = 64 px", Vector2(0, 8), Vector2(1280, 26), 17))
	_view_label = _caption("", Vector2(0, 34), Vector2(1280, 22), 14)
	hud.add_child(_view_label)
	hud.add_child(_caption("每只都在原地循环爬行动作    [Z] 尺寸   [G] 一格范围与视觉边界   [Esc] 退出", Vector2(0, 690), Vector2(1280, 22), 14))
	_apply_view()


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


func _apply_view() -> void:
	var z := VIEW_ZOOM[view]
	_camera.zoom = Vector2(z, z)
	_camera.position = WORLD_POS + Vector2(8.5, 4.9) * Spec.CELL_PX if view == 1 else Vector2(640, 360)
	_view_label.text = "视图：%s  [Z 切换]" % VIEW_NAME[view]


func _process(delta: float) -> void:
	_time += delta
	for i in _looks.size():
		var look := _looks[i]
		look.step = _time          # one cell's worth of crawl cycle per second
		var loop: String = ENTRIES[i].get("loop", "")
		if loop != "":
			if _only != "" and loop != _only:
				look.visible = false
				continue
			_drive_loop(look, loop)
	if _shot_path != "" and _time >= _shot_at:
		var path := _shot_path
		_shot_path = ""
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(path)
		print("shot saved: ", path, " err=", err)
		get_tree().quit()


## Play one transition over and over: the state before, the transition, the state after.
func _drive_loop(look: Node2D, loop: String) -> void:
	var d: Array = LOOPS[loop]
	var t := fmod(_time, d[0] + d[1] + d[2])
	var before: int = Moss.Stage.CRAWL if loop == "root" else (Moss.Stage.FLOWER if loop == "release" else Moss.Stage.BUD)
	var after: int = Moss.Stage.BUD if loop == "root" else Moss.Stage.FLOWER
	look.visible = true
	if t < d[0]:
		look.stage = before
		look.anim = ""
	elif t < d[0] + d[1]:
		look.stage = before
		look.anim = loop
		look.anim_t = (t - d[0]) / d[1]
	elif loop == "wither" or loop == "release":
		look.visible = false          # gone; the loop starts again shortly
		look.anim = ""
	else:
		look.stage = after
		look.anim = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				show_grid = not show_grid
				_debug.queue_redraw()
			KEY_Z:
				view = (view + 1) % VIEW_ZOOM.size()
				_apply_view()
			KEY_ESCAPE:
				get_tree().quit()


func _draw_debug() -> void:
	if not show_grid:
		return
	var u := Spec.CELL_PX
	for i in ENTRIES.size():
		var cell: Vector2i = ENTRIES[i].cell
		_debug.draw_rect(Rect2(Vector2(cell) * u, Vector2(u, u)), Color(0.45, 0.9, 1.0, 0.9), false, 1.5)
		var half: Vector2 = _looks[i].visual_half_extent() * u
		_debug.draw_rect(Rect2(_looks[i].position - half, half * 2.0), Color(1.0, 0.85, 0.35, 0.9), false, 1.2)
