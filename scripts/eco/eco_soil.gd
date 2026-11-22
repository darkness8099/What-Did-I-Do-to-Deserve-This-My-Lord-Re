extends Node2D
## Shows the nutrient held in soil as the look of the soil surface itself (task ECO-004),
## through one shader quad over the whole map (soil_surface.gdshader):
##   1..9   green moss spreading over the block;
##   10..16 the moss is complete and pale gold veins appear on it;
##   17+    placeholder for now (the top look will be designed on its own).
## There are no dots and nothing flies: what is drawn simply eases towards the real amount
## (SHOW_RATE points per second), so a block that keeps gaining and losing a point looks
## like moss creeping out and back, never like a blink.
## Exact amounts are in the G overlay. Drawing only: the amounts live in the grid.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const SoilShader := preload("res://scripts/soil/soil_surface.gdshader")

const SHOW_RATE := 1.5            ## points per second the drawn value moves towards the real one

var grid: RefCounted

var _shown := PackedFloat32Array()
var _image: Image
var _texture: ImageTexture
var _dirty := true


func setup(g: RefCounted) -> void:
	grid = g
	_image = Image.create(grid.cols, grid.rows, false, Image.FORMAT_RGF)
	_shown.resize(grid.cols * grid.rows)
	_snap()
	_texture = ImageTexture.create_from_image(_image)
	var mat := ShaderMaterial.new()
	mat.shader = SoilShader
	mat.set_shader_parameter("nutrient_tex", _texture)
	mat.set_shader_parameter("grid_size", Vector2(grid.cols, grid.rows))
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var quad := Sprite2D.new()
	quad.texture = ImageTexture.create_from_image(white)
	quad.centered = false
	quad.scale = Vector2(grid.cols, grid.rows) * Spec.CELL_PX
	quad.material = mat
	add_child(quad)
	grid.nutrient_changed.connect(func(_c: Vector2i, _a: int, _b: int) -> void: _dirty = true)
	grid.cell_changed.connect(func(_c: Vector2i) -> void: _dirty = true)
	grid.was_reset.connect(clear)


## Look band of an amount; it follows what hatches when the block is dug:
## 0 nothing, 1 (1..9) slime, 2 (10..16) predator, 3 (17+) nothing yet.
static func tier(n: int) -> int:
	if n <= 0:
		return 0
	if n <= 9:
		return 1
	if n <= 16:
		return 2
	return 3


## Show the real amounts at once (new map, reset).
func clear() -> void:
	_snap()
	if _texture != null:
		_texture.update(_image)


func _snap() -> void:
	for y in grid.rows:
		for x in grid.cols:
			_shown[y * grid.cols + x] = grid.nutrient(Vector2i(x, y))
	_write()
	_dirty = false


func _write() -> void:
	for y in grid.rows:
		for x in grid.cols:
			var soil := 1.0 if grid.is_soil(Vector2i(x, y)) else 0.0
			_image.set_pixel(x, y, Color(_shown[y * grid.cols + x], soil, 0.0))


func advance(delta: float) -> void:
	if not _dirty:
		return
	var still_moving := false
	for y in grid.rows:
		for x in grid.cols:
			var i: int = y * grid.cols + x
			var want := float(grid.nutrient(Vector2i(x, y)))
			if _shown[i] != want:
				_shown[i] = move_toward(_shown[i], want, SHOW_RATE * delta)
				still_moving = still_moving or _shown[i] != want
	_write()
	_texture.update(_image)
	_dirty = still_moving
