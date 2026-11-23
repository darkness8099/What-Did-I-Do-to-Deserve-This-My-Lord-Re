extends Node2D
## Look preview for the pre-rendered leaf-cutter ant next to the code-drawn moss (task ART-006).
## Everything animates on the spot; no movement across the map and no ecology logic.
##
## Keys: Z cycles view size (64 / 80 / 48 px per cell), G cell bounds, Esc quit.
## CLI (after `--`): --grid, --zoom, --small, --t=<seconds before the shot>,
##       --shot=<png path> (save one still and quit).

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Grid := preload("res://scripts/burrow/burrow_grid.gd")
const MapScript := preload("res://scripts/burrow/burrow_map.gd")
const Moss := preload("res://scripts/moss/moss_sprite.gd")
const Ant := preload("res://scripts/ant/ant_look.gd")

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

## kind: "ant" | "moss". For ants: anim "walk" / "idle", or loop "attack" / "death".
## One unit is two ants sharing a cell (count, default 2), spread along the way they face.
const ENTRIES: Array[Dictionary] = [
	{"kind": "moss", "cell": Vector2i(2, 2), "heading": 0, "text": "苔"},
	{"kind": "ant", "cell": Vector2i(4, 2), "heading": 0, "anim": "walk", "text": "蚁 向右"},
	{"kind": "ant", "cell": Vector2i(8, 2), "heading": 2, "anim": "walk", "text": "蚁 向左"},
	{"kind": "ant", "cell": Vector2i(10, 2), "heading": 0, "anim": "idle", "text": "待机"},
	{"kind": "ant", "cell": Vector2i(14, 2), "heading": 0, "loop": "attack", "text": "攻击"},
	{"kind": "ant", "cell": Vector2i(6, 3), "heading": 3, "anim": "walk", "text": "向上（俯视）", "side": true},
	{"kind": "ant", "cell": Vector2i(6, 4), "heading": 3, "loop": "death", "text": "俯视 死亡消散", "side": true},
	{"kind": "ant", "cell": Vector2i(12, 3), "heading": 1, "anim": "walk", "text": "向下（俯视）", "side": true},
	{"kind": "ant", "cell": Vector2i(12, 4), "heading": 1, "loop": "close", "text": "相邻格：靠拢一起咬", "side": true},
	{"kind": "target", "cell": Vector2i(12, 5), "text": ""},
	{"kind": "moss", "cell": Vector2i(2, 5), "stage": 1, "text": "花苞"},
	{"kind": "ant", "cell": Vector2i(3, 5), "heading": 2, "anim": "idle", "text": ""},
	{"kind": "moss", "cell": Vector2i(4, 5), "stage": 2, "text": "花"},
	{"kind": "ant", "cell": Vector2i(8, 5), "heading": 0, "loop": "death", "text": "死亡：趴下后消散"},
	{"kind": "moss", "cell": Vector2i(10, 5), "heading": 0, "text": ""},
	{"kind": "ant", "cell": Vector2i(10, 5), "heading": 0, "anim": "walk", "text": "同格重叠"},
	{"kind": "ant", "cell": Vector2i(14, 5), "heading": 2, "anim": "walk", "text": "蚁 向左"},
	{"kind": "ant", "cell": Vector2i(3, 7), "heading": 0, "anim": "walk", "count": 1, "text": "只剩一只"},
	{"kind": "ant", "cell": Vector2i(6, 7), "heading": 0, "anim": "walk", "text": "一格两只"},
	{"kind": "ant", "cell": Vector2i(7, 7), "heading": 0, "anim": "walk", "text": ""},
	{"kind": "ant", "cell": Vector2i(8, 7), "heading": 0, "anim": "walk", "text": "三格连着走"},
	{"kind": "ant", "cell": Vector2i(10, 7), "heading": 0, "loop": "close", "text": "相邻格：靠拢一起咬"},
	{"kind": "target", "cell": Vector2i(11, 7), "text": "目标（占位）"},
	{"kind": "moss", "cell": Vector2i(13, 7), "heading": 0, "text": "苔（对比）"},
]

const VIEW_ZOOM: Array[float] = [1.0, 1.25, 0.75]
const VIEW_NAME: Array[String] = ["默认 64 px/格", "放大 80 px/格", "小一档 48 px/格"]
const WORLD_POS := Vector2(96, 50)

var grid: RefCounted
var show_grid := false
var view := 0

var _world: Node2D
var _debug: Node2D
var _camera: Camera2D
var _mosses: Array[Node2D] = []
var _loops: Array[Dictionary] = []          ## {ants: Array, kind: String, t: float, phase: int}
var _view_label: Label
var _shot_path := ""
var _time := 0.0
var _shot_at := 0.9


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--grid":
			show_grid = true
		elif a == "--zoom":
			view = 1
		elif a == "--small":
			view = 2
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
		var centre: Vector2 = Spec.center(e.cell) * u
		if e.kind == "moss":
			var look := Node2D.new()
			look.set_script(Moss)
			look.position = centre
			look.heading = e.get("heading", 0)
			look.stage = e.get("stage", 0)
			_world.add_child(look)
			_mosses.append(look)
		elif e.kind == "target":
			# stand-in for something that blocks its cell (a hero, later): the unit attacks it from next door
			var block := ColorRect.new()
			block.color = Color(0.55, 0.6, 0.72)
			block.size = Vector2(26, 42)
			block.position = centre + Vector2(-13, 0.43 * u - 42)
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_world.add_child(block)
		else:
			_add_ants(e, centre)
		var text: String = e.get("text", "")
		if text == "":
			continue
		if e.get("side", false):
			_world.add_child(_caption(text, Vector2((e.cell.x + 1) * u - 4, e.cell.y * u + 36), Vector2(u * 2.4, 22), 14))
		else:
			_world.add_child(_caption(text, Vector2(e.cell.x * u - 64, (e.cell.y + 1) * u + 6), Vector2(u + 128, 22), 14))

	_debug = Node2D.new()
	_debug.z_index = 30
	_debug.draw.connect(_draw_debug)
	_world.add_child(_debug)
	_camera = Camera2D.new()
	add_child(_camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	hud.add_child(_caption("切叶蚁与苔同屏预览（均为 SpriteKiln 预渲染）    1 格 = 64 px", Vector2(0, 8), Vector2(1280, 26), 17))
	_view_label = _caption("", Vector2(0, 34), Vector2(1280, 22), 14)
	hud.add_child(_view_label)
	hud.add_child(_caption("全部在原地循环动作    [Z] 尺寸   [G] 一格范围   [Esc] 退出", Vector2(0, 690), Vector2(1280, 22), 14))
	_apply_view()


func _add_ants(e: Dictionary, centre: Vector2) -> void:
	var u := Spec.CELL_PX
	var count: int = e.get("count", 2)
	var heading: int = e.get("heading", 0)
	var along := Vector2(0, 1) if heading == Ant.Heading.UP or heading == Ant.Heading.DOWN else Vector2(1, 0)
	var ants: Array = []
	for i in count:
		var spread := 0.0 if count == 1 else lerpf(-0.245, 0.245, float(i) / float(count - 1))
		var ant := Node2D.new()
		ant.set_script(Ant)
		ant.position = centre + along * spread * u
		ant.heading = heading
		_world.add_child(ant)
		ant.play(StringName(e.get("anim", "idle")))
		if i > 0:
			ant.advance(0.23 * i)
		ants.append(ant)
	if e.has("loop"):
		_loops.append({"ants": ants, "kind": e.loop, "t": 0.0, "phase": 0, "centre": centre, "heading": heading})


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
	for m in _mosses:
		m.step = _time
	for l in _loops:
		_drive_loop(l, delta)
	if _shot_path != "" and _time >= _shot_at:
		var path := _shot_path
		_shot_path = ""
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(path)
		print("shot saved: ", path, " err=", err)
		get_tree().quit()


## attack: idle 1.0 s, then the attack clip, again.
## death:  idle 1.0 s, collapse clip (0.62 s) + 0.25 s lying still, dissolve 0.8 s, gone 0.6 s, again.
func _drive_loop(l: Dictionary, delta: float) -> void:
	l.t += delta
	if l.kind == "close":
		_drive_close(l)
		return
	var next := ""
	var dissolve := -1.0
	if l.kind == "attack":
		if l.phase == 0 and l.t >= 1.0:
			next = "attack"
			l.phase = 1
		elif l.phase == 1 and l.t >= 1.6:
			next = "idle"
			l.phase = 0
			l.t = 0.0
	elif l.phase == 0 and l.t >= 1.0:
		next = "death"
		l.phase = 1
	elif l.phase == 1 and l.t >= 1.87:
		l.phase = 2
	elif l.phase == 2:
		dissolve = (l.t - 1.87) / 0.8
		if l.t >= 2.67:
			l.phase = 3
	elif l.phase == 3 and l.t >= 3.27:
		dissolve = 0.0
		next = "idle"
		l.phase = 0
		l.t = 0.0
	for ant in l.ants:
		if dissolve >= 0.0:
			ant.dissolve = dissolve
		if next != "":
			ant.play(StringName(next), true)


## Attacking something in the NEXT cell: the ant behind closes up beside the one in front, so
## both reach, and they bite in turn, each darting forward as its jaws close. Both keep their
## feet on the same floor line: nothing is shifted up or down. 1 s apart, 0.35 s closing up, three rounds of 0.8 s,
## 0.35 s falling back.
const CLOSE_FRONT := 0.33        ## cells ahead of the cell centre, while closed up
const CLOSE_REAR := 0.10
const CLOSE_LUNGE := 0.16        ## cells each ant darts forward as it bites; the lunge may reach into the next cell
const CLOSE_ABREAST := 0.11      ## top view: each ant steps this far (cells) to its own side

func _drive_close(l: Dictionary) -> void:
	var u := Spec.CELL_PX
	var t: float = l.t
	var k := smoothstep(1.0, 1.35, t) - smoothstep(3.75, 4.1, t)
	var heading: int = l.heading
	var vertical := heading == Ant.Heading.UP or heading == Ant.Heading.DOWN
	var fwd := Vector2(0, 1) if heading == Ant.Heading.DOWN else (Vector2(0, -1) if heading == Ant.Heading.UP else (Vector2(-1, 0) if heading == Ant.Heading.LEFT else Vector2(1, 0)))
	var want := "idle"
	if (t >= 1.0 and t < 1.35) or t >= 3.75:
		want = "walk"
	for i in l.ants.size():
		var ant: Node2D = l.ants[i]
		var front: bool = i == l.ants.size() - 1          # the last one added stands furthest along
		if fwd.x < 0.0 or fwd.y < 0.0:
			front = i == 0
		var off := lerpf(0.245, CLOSE_FRONT, k) if front else lerpf(-0.245, CLOSE_REAR, k)
		var side := Vector2.ZERO
		if vertical:
			side = Vector2(CLOSE_ABREAST * (1.0 if front else -1.0) * k * u, 0)
		ant.z_index = 1 if front else 0
		if t >= 1.35 and t < 3.75:
			var round_t := fmod(t - 1.35, 0.8) - (0.0 if front else 0.27)
			var key := "bit%d" % i
			if round_t >= 0.0 and round_t < 0.1 and not l.get(key, false):
				l[key] = true
				ant.play(&"attack", true)
			elif round_t >= 0.6 or round_t < 0.0:
				l[key] = false
			if round_t >= 0.0 and round_t < 0.48:
				off += CLOSE_LUNGE * sin(PI * round_t / 0.48)
		else:
			ant.play(StringName(want))
		ant.position = l.centre + fwd * off * u + side
	if t >= 4.6:
		l.t = 0.0


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
	for e in ENTRIES:
		_debug.draw_rect(Rect2(Vector2(e.cell) * u, Vector2(u, u)), Color(0.45, 0.9, 1.0, 0.9), false, 1.5)
