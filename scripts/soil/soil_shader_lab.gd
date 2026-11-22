extends Node2D
## Soil surface shader sample (task ART-003). Soil only: no creatures, no ecology logic.
## Shows the generated 40 x 24 map's starting nutrient through the shader, plus
##   - a reference row holding 0, 1, 2 ... 20 from left to right, and
##   - a patch whose nutrient slowly rises and falls, to watch moss grow and recede.
## What is drawn eases towards the real value (SHOW_RATE points per second), which is the
## slow transition agreed instead of any flash.
##
## Keys: Z view (64 px per cell / whole map), arrows or WASD pan, B blend between blocks
##       on / off, O outline on / off, G numbers on the reference row, Esc quit.
## CLI (after `--`): --view=<0|1>, --cam=<x>,<y> (cells), --t=<seconds to run before a
##       shot>, --shot=<png path> (save one still and quit).

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Grid := preload("res://scripts/eco/eco_grid.gd")
const MapScript := preload("res://scripts/burrow/burrow_map.gd")
const MapGen := preload("res://scripts/eco/eco_mapgen.gd")
const SoilShader := preload("res://scripts/soil/soil_surface.gdshader")

const SHOW_RATE := 1.5             ## points per second the drawn value moves towards the real one
const RAMP_ROW := 6
const RAMP_X0 := 9
const PULSE := Rect2i(4, 15, 6, 4)
const PULSE_PERIOD := 24.0
const HUD_TOP := 34.0
const HUD_BOTTOM := 60.0

var grid: RefCounted
var view := 0
var show_numbers := true

var _camera: Camera2D
var _overlay: Node2D
var _material: ShaderMaterial
var _image: Image
var _texture: ImageTexture
var _shown := PackedFloat32Array()
var _time := 0.0
var _view_label: Label
var _shot_path := ""
var _shot_at := 1.0
var _cam_cells := Vector2(-1, -1)
var _soften := true
var _outline := true


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = clampi(int(a.trim_prefix("--view=")), 0, 1)
		elif a.begins_with("--cam="):
			var xy := a.trim_prefix("--cam=").split(",")
			_cam_cells = Vector2(float(xy[0]), float(xy[1]))
		elif a.begins_with("--t="):
			_shot_at = float(a.trim_prefix("--t="))
		elif a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")

	var m := MapGen.generate(Eco.GEN_COLS, Eco.GEN_ROWS, Eco.GEN_SEED)
	grid = Grid.new()
	grid.load_layout(m.layout)
	grid.load_nutrient_values(m.nutrient)
	# A few tunnels so the soil is seen next to open cells, as in play.
	for c in MapGen.demo_plan(Eco.GEN_COLS, Eco.GEN_ROWS, m.clusters).slice(0, 40):
		grid.dig_out(c)
	# Reference row: 0, 1, 2 ... 20.
	for i in 21:
		_put(Vector2i(RAMP_X0 + i, RAMP_ROW), i)

	var map := Node2D.new()
	map.set_script(MapScript)
	add_child(map)
	map.setup(grid)

	_image = Image.create(grid.cols, grid.rows, false, Image.FORMAT_RGF)
	_shown.resize(grid.cols * grid.rows)
	for y in grid.rows:
		for x in grid.cols:
			_shown[y * grid.cols + x] = grid.nutrient(Vector2i(x, y))
	_write_image()
	_texture = ImageTexture.create_from_image(_image)

	_material = ShaderMaterial.new()
	_material.shader = SoilShader
	_material.set_shader_parameter("nutrient_tex", _texture)
	_material.set_shader_parameter("grid_size", Vector2(grid.cols, grid.rows))
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var quad := Sprite2D.new()
	quad.texture = ImageTexture.create_from_image(white)
	quad.centered = false
	quad.scale = Vector2(grid.cols, grid.rows) * Spec.CELL_PX
	quad.material = _material
	add_child(quad)

	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_camera = Camera2D.new()
	add_child(_camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	for r: Rect2 in [Rect2(0, 0, 1280, HUD_TOP), Rect2(0, 720 - HUD_BOTTOM, 1280, HUD_BOTTOM)]:
		var bar := ColorRect.new()
		bar.position = r.position
		bar.size = r.size
		bar.color = Color(0.06, 0.04, 0.07, 0.86)
		hud.add_child(bar)
	hud.add_child(_caption("土块表面着色器小样：1–9 苔藓密度，10 以上淡金纹路（17 以上为占位）", Vector2(0, 5), 16))
	_view_label = _caption("", Vector2(0, 664), 13)
	hud.add_child(_view_label)
	hud.add_child(_caption("[Z] 视角   方向键/WASD 平移   [B] 相邻土块融合   [O] 描边   [G] 参考行数字   [Esc] 退出", Vector2(0, 690), 13))
	_camera.position = Vector2(RAMP_X0 + 10.5, RAMP_ROW + 2.5) * Spec.CELL_PX
	if _cam_cells.x >= 0.0:
		_camera.position = _cam_cells * Spec.CELL_PX
	_apply_view()


func _put(c: Vector2i, value: int) -> void:
	if grid.is_soil(c):
		grid.add_nutrient(c, value - grid.nutrient(c))


func _caption(text: String, pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(1280, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.82))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _write_image() -> void:
	for y in grid.rows:
		for x in grid.cols:
			var soil := 1.0 if grid.is_soil(Vector2i(x, y)) else 0.0
			_image.set_pixel(x, y, Color(_shown[y * grid.cols + x], soil, 0.0))


func _apply_view() -> void:
	var z := 1.0
	if view == 1:
		z = minf(1280.0 / (grid.cols * Spec.CELL_PX), (720.0 - HUD_TOP - HUD_BOTTOM) / (grid.rows * Spec.CELL_PX))
		_camera.position = Vector2(grid.cols, grid.rows) * 0.5 * Spec.CELL_PX + Vector2(0, (HUD_BOTTOM - HUD_TOP) * 0.5 / z)
	_camera.zoom = Vector2(z, z)
	_view_label.text = "视角：%s    相邻融合 %s    描边 %s    左下方一小片养分在自动升降" % [
		"64 px/格" if view == 0 else "全图（约 %d px/格）" % roundi(Spec.CELL_PX * z), "开" if _soften else "关", "开" if _outline else "关"]
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	# The pulsing patch: a slow wave from 0 up to about 20 and back.
	var wave := 0.5 - 0.5 * cos(TAU * _time / PULSE_PERIOD)
	for y in range(PULSE.position.y, PULSE.end.y):
		for x in range(PULSE.position.x, PULSE.end.x):
			var phase := 0.12 * (x - PULSE.position.x) + 0.08 * (y - PULSE.position.y)
			_put(Vector2i(x, y), roundi(20.0 * clampf(wave * 1.2 - phase, 0.0, 1.0)))

	var changed := false
	for y in grid.rows:
		for x in grid.cols:
			var i: int = y * grid.cols + x
			var want := float(grid.nutrient(Vector2i(x, y)))
			if _shown[i] != want:
				_shown[i] = move_toward(_shown[i], want, SHOW_RATE * delta)
				changed = true
	if changed:
		_write_image()
		_texture.update(_image)

	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if pan != Vector2.ZERO and view == 0:
		_camera.position += pan.normalized() * 900.0 * delta

	if _shot_path != "" and _time >= _shot_at:
		var path := _shot_path
		_shot_path = ""
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(path)
		print("shot saved: ", path, " err=", err)
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z:
				view = 1 - view
				if view == 0:
					_camera.position = Vector2(RAMP_X0 + 10.5, RAMP_ROW + 2.5) * Spec.CELL_PX
				_apply_view()
			KEY_B:
				_soften = not _soften
				_material.set_shader_parameter("soften", 0.35 if _soften else 0.0)
				_material.set_shader_parameter("edge_wobble", 0.28 if _soften else 0.0)
				_apply_view()
			KEY_O:
				_outline = not _outline
				_material.set_shader_parameter("outline", 1.0 if _outline else 0.0)
				_apply_view()
			KEY_G:
				show_numbers = not show_numbers
				_overlay.queue_redraw()
			KEY_ESCAPE:
				get_tree().quit()


func _draw_overlay() -> void:
	if not show_numbers or view != 0:
		return
	var font := ThemeDB.fallback_font
	var u := Spec.CELL_PX
	for i in 21:
		var at := Vector2(RAMP_X0 + i, RAMP_ROW) * u + Vector2(4, 16)
		_overlay.draw_string_outline(font, at, str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		_overlay.draw_string(font, at, str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.97, 0.85))
