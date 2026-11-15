extends Node2D
## Draws the burrow cross-section from the grid. Redraws only when a cell changes.
## Local coordinates are pixels with the map's top-left cell corner at (0, 0).

const Spec := preload("res://scripts/burrow/grid_spec.gd")

const C_SOIL_A := Color("5b4132")
const C_SOIL_B := Color("6a4c38")
const C_SOIL_DEEP := Color("3c2a26")
const C_CAVE := Color("1d151c")
const C_CAVE_DEEP := Color("140e15")
const C_LIP_LIT := Color("9a7650")
const C_LIP_MID := Color("7a5a40")
const C_LIP_DARK := Color("4a3429")
const C_ROCK := Color("4a495a")
const C_ROCK_LIT := Color("70708a")
const C_ROCK_DARK := Color("2f2e3b")
const C_LINE := Color("120c11")

var grid: RefCounted
var hover_cell := Vector2i(-1, -1)

var _u := Spec.CELL_PX
var _ov: Node2D
var _flashes: Array[Dictionary] = []


func setup(g: RefCounted) -> void:
	grid = g
	grid.cell_changed.connect(func(_c: Vector2i) -> void: queue_redraw())
	grid.was_reset.connect(func() -> void:
		_flashes.clear()
		queue_redraw())
	_ov = Node2D.new()
	add_child(_ov)
	_ov.draw.connect(_draw_overlay)
	queue_redraw()


func set_hover(c: Vector2i) -> void:
	if c != hover_cell:
		hover_cell = c
		_ov.queue_redraw()


## Brief crumble flash where a cell was just dug.
func flash_cell(c: Vector2i) -> void:
	_flashes.append({"cell": c, "t": 0.0})


func _process(delta: float) -> void:
	if _flashes.is_empty():
		return
	for f in _flashes:
		f.t += delta
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return f.t < 0.3)
	_ov.queue_redraw()


func _h(x: int, y: int, k: int) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0


func _blob(c: Vector2, rx: float, ry: float, n: int, x: int, y: int, k: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var w := 0.8 + 0.4 * _h(x * 7 + i, y, k)
		pts.append(c + Vector2(cos(a) * rx * w, sin(a) * ry * w))
	return pts


func _depth(y: int) -> float:
	return float(y) / float(maxi(grid.rows - 1, 1))


func _solid(c: Vector2i) -> bool:
	return not grid.is_open(c)


func _draw() -> void:
	if grid == null:
		return
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			match grid.kind(c):
				Spec.SOIL: _draw_soil(c)
				Spec.ROCK: _draw_rock(c)
				_: _draw_cave(c)
	for y in grid.rows:
		for x in grid.cols:
			if grid.is_open(Vector2i(x, y)):
				_draw_rims(Vector2i(x, y))
	# Frame around the board.
	draw_rect(Rect2(Vector2.ZERO, Vector2(grid.cols, grid.rows) * _u), C_LINE, false, 3.0)


func _draw_soil(c: Vector2i) -> void:
	var o := Vector2(c) * _u
	var base := C_SOIL_A.lerp(C_SOIL_B, _h(c.x, c.y, 1)).lerp(C_SOIL_DEEP, _depth(c.y) * 0.55)
	draw_rect(Rect2(o, Vector2(_u, _u)), base)
	# Packed-earth speckles.
	for i in 6:
		var p := o + Vector2(_h(c.x, c.y, 10 + i), _h(c.x, c.y, 20 + i)) * _u
		var r := (0.03 + 0.05 * _h(c.x, c.y, 30 + i)) * _u
		var dark := _h(c.x, c.y, 40 + i) < 0.6
		draw_colored_polygon(_blob(p, r * 1.5, r, 7, c.x, c.y, 50 + i), Color(0, 0, 0, 0.13) if dark else Color(1, 0.88, 0.7, 0.07))
	# A pebble or a root thread in some blocks.
	var pick := _h(c.x, c.y, 2)
	if pick < 0.28:
		var p := o + Vector2(0.25 + 0.5 * _h(c.x, c.y, 3), 0.25 + 0.5 * _h(c.x, c.y, 4)) * _u
		var pts := _blob(p, 0.09 * _u, 0.065 * _u, 7, c.x, c.y, 5)
		draw_colored_polygon(pts, Color("7d7482").lerp(base, 0.35))
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.35), 1.2, true)
	elif pick > 0.74:
		var a := o + Vector2(0.15 + 0.3 * _h(c.x, c.y, 6), 0.2 + 0.2 * _h(c.x, c.y, 7)) * _u
		var root := PackedVector2Array([a])
		for i in 4:
			a += Vector2(0.14 + 0.06 * _h(c.x, c.y, 60 + i), (0.18 * _h(c.x, c.y, 70 + i)) - 0.03) * _u
			root.append(a)
		draw_polyline(root, Color("8a6a4c").lerp(base, 0.3), 1.6, true)
	# Block seams: faint, so a block reads as one diggable unit without looking like tiles.
	draw_line(o + Vector2(0, _u), o + Vector2(_u, _u), Color(0, 0, 0, 0.13), 1.5)
	draw_line(o + Vector2(_u, 0), o + Vector2(_u, _u), Color(0, 0, 0, 0.13), 1.5)
	draw_line(o + Vector2(1, 1), o + Vector2(_u - 1, 1), Color(1, 0.9, 0.75, 0.05), 1.0)


func _draw_rock(c: Vector2i) -> void:
	var o := Vector2(c) * _u
	var base := C_ROCK_DARK.lerp(C_ROCK, 0.35 + 0.3 * _h(c.x, c.y, 1)).lerp(Color("1b1a24"), _depth(c.y) * 0.3)
	draw_rect(Rect2(o, Vector2(_u, _u)), base)
	# Two or three stone slabs per block.
	var split := 0.4 + 0.2 * _h(c.x, c.y, 2)
	var slabs: Array[Rect2] = [Rect2(0.04, 0.05, 0.92, split - 0.07), Rect2(0.04, split + 0.02, 0.5 + 0.2 * _h(c.x, c.y, 3) - 0.06, 0.93 - split)]
	slabs.append(Rect2(slabs[1].end.x + 0.04, split + 0.02, 0.92 - slabs[1].end.x, 0.93 - split))
	for i in slabs.size():
		var r := slabs[i]
		var k := 0.04 * _u
		var a := o + r.position * _u
		var b := o + r.end * _u
		var pts := PackedVector2Array([a + Vector2(k, 0), Vector2(b.x - k, a.y), Vector2(b.x, a.y + k), Vector2(b.x, b.y - k),
			Vector2(b.x - k, b.y), Vector2(a.x + k, b.y), Vector2(a.x, b.y - k), a + Vector2(0, k)])
		draw_colored_polygon(pts, C_ROCK.lerp(C_ROCK_DARK, 0.5 * _h(c.x, c.y, 10 + i)).lerp(Color("1b1a24"), _depth(c.y) * 0.3))
		draw_polyline(PackedVector2Array([pts[7], pts[0], pts[1]]), Color(C_ROCK_LIT, 0.7), 1.5, true)
		draw_polyline(PackedVector2Array([pts[2], pts[3], pts[4], pts[5]]), Color(0, 0, 0, 0.45), 1.5, true)


func _draw_cave(c: Vector2i) -> void:
	var o := Vector2(c) * _u
	draw_rect(Rect2(o, Vector2(_u, _u)), C_CAVE.lerp(C_CAVE_DEEP, _depth(c.y)))
	# Scrape marks on the back wall.
	for i in 3:
		var p := o + Vector2(0.15 + 0.7 * _h(c.x, c.y, 80 + i), 0.15 + 0.6 * _h(c.x, c.y, 84 + i)) * _u
		draw_line(p, p + Vector2(0.1, 0.13) * _u, Color(1, 0.85, 0.8, 0.045), 2.0, true)
	draw_colored_polygon(_blob(o + Vector2(0.5, 0.52) * _u, 0.34 * _u, 0.3 * _u, 12, c.x, c.y, 90), Color(1, 0.8, 0.7, 0.022))


## Soil lips where an open cell meets solid ground, plus corner fillets.
func _draw_rims(c: Vector2i) -> void:
	var o := Vector2(c) * _u
	var rim := Spec.WALL_RIM * _u
	# side index: 0 right, 1 bottom, 2 left, 3 top (matches Spec.DIRS)
	var corners: Array[Vector2] = [o + Vector2(_u, 0), o + Vector2(_u, _u), o + Vector2(0, _u), o]
	for s in 4:
		var d: Vector2i = Spec.DIRS[s]
		if not _solid(c + d):
			continue
		var a: Vector2 = corners[s]
		var b: Vector2 = corners[(s + 1) % 4]
		var inward := -Vector2(d)
		var rock: bool = grid.kind(c + d) == Spec.ROCK
		var col: Color
		if rock:
			col = [C_ROCK, C_ROCK_LIT, C_ROCK, C_ROCK_DARK][s]
		else:
			col = [C_LIP_MID, C_LIP_LIT, C_LIP_MID, C_LIP_DARK][s]
		col = col.lerp(C_CAVE_DEEP, _depth(c.y) * 0.3)
		var inner := PackedVector2Array()
		var n := 6
		for i in n + 1:
			var t := float(i) / n
			var depth := rim if (i <= 1 or i >= n - 1) else rim * (0.65 + 0.85 * _h(c.x * 4 + s, c.y, 100 + i))
			inner.append(a.lerp(b, t) + inward * depth)
		var poly := PackedVector2Array([a])
		poly.append_array(inner)
		poly.append(b)
		if s == 3:
			# Ceiling: a soft shadow falls into the tunnel.
			var sh := 0.26 * _u
			draw_polygon(PackedVector2Array([a, b, b + inward * sh, a + inward * sh]),
				PackedColorArray([Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.42), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
		draw_colored_polygon(poly, col)
		draw_polyline(inner, C_LINE, 1.6, true)
		if s == 1:
			# Floor: a lit edge and a few crumbs.
			var lit := PackedVector2Array()
			for v in inner:
				lit.append(v + Vector2(0, 1.6))
			draw_polyline(lit, Color(1, 0.92, 0.75, 0.22), 1.2, true)
			for i in 2:
				if _h(c.x, c.y, 120 + i) < 0.55:
					var p := a.lerp(b, 0.15 + 0.7 * _h(c.x, c.y, 124 + i)) + inward * (rim + 1.5)
					draw_circle(p, 1.3 + 1.2 * _h(c.x, c.y, 128 + i), C_LIP_MID.lerp(C_CAVE, 0.2))
		elif s == 3 and not rock and _h(c.x, c.y, 130) < 0.4:
			# A root tip hanging from the ceiling.
			var p := a.lerp(b, 0.2 + 0.6 * _h(c.x, c.y, 131)) + inward * rim * 0.8
			var len := (0.1 + 0.1 * _h(c.x, c.y, 132)) * _u
			draw_polyline(PackedVector2Array([p, p + Vector2(1.5, len * 0.5), p + Vector2(-1.0, len)]), Color("8a6a4c"), 1.5, true)
	# Corners.
	for s in 4:
		var d1: Vector2i = Spec.DIRS[(s + 3) % 4]   # side that ends at corners[s]
		var d2: Vector2i = Spec.DIRS[s]             # side that starts at corners[s]
		var k: Vector2 = corners[s]
		var in1 := -Vector2(d1)
		var in2 := -Vector2(d2)
		var s1 := _solid(c + d1)
		var s2 := _solid(c + d2)
		if s1 and s2:
			# Convex pocket: round it off with packed earth.
			# The curve runs between the inner edges of the two lips, so it joins them cleanly.
			var r := _u / 6.0
			var pts := PackedVector2Array([k, k + in2 * r])
			var arc := PackedVector2Array()
			for i in 7:
				var t := float(i) / 6.0
				var p0 := k + in2 * r + in1 * rim
				var p2 := k + in1 * r + in2 * rim
				var ctrl := k + (in1 + in2) * rim * 1.5
				arc.append(p0.lerp(ctrl, t).lerp(ctrl.lerp(p2, t), t))
			pts.append_array(arc)
			pts.append(k + in1 * r)
			var rocky: bool = grid.kind(c + d1) == Spec.ROCK and grid.kind(c + d2) == Spec.ROCK
			draw_colored_polygon(pts, (C_ROCK if rocky else C_LIP_MID).lerp(C_CAVE_DEEP, _depth(c.y) * 0.3 + (0.25 if in1.y + in2.y > 0 else 0.0)))
			draw_polyline(arc, C_LINE, 1.6, true)
		elif not s1 and not s2 and _solid(c + d1 + d2):
			# Outer corner of a soil block poking into a junction: soften its tip.
			var r := rim
			var pts := PackedVector2Array([k])
			var arc := PackedVector2Array()
			for i in 6:
				var ang := lerpf(in2.angle(), in2.angle() + angle_difference(in2.angle(), in1.angle()), float(i) / 5.0)
				arc.append(k + Vector2.from_angle(ang) * r)
			pts.append_array(arc)
			draw_colored_polygon(pts, (C_ROCK if grid.kind(c + d1 + d2) == Spec.ROCK else C_LIP_MID).lerp(C_CAVE_DEEP, _depth(c.y) * 0.3))
			draw_polyline(arc, C_LINE, 1.6, true)


func _draw_overlay() -> void:
	for f in _flashes:
		var k: float = 1.0 - f.t / 0.3
		var o := Vector2(f.cell) * _u
		_ov.draw_rect(Rect2(o, Vector2(_u, _u)), Color(C_LIP_LIT, 0.55 * k * k))
	if grid != null and grid.in_bounds(hover_cell):
		var o := Vector2(hover_cell) * _u
		var r := Rect2(o + Vector2(3, 3), Vector2(_u - 6, _u - 6))
		if grid.can_dig(hover_cell):
			_ov.draw_rect(r, Color(1, 0.9, 0.55, 0.13))
			_ov.draw_rect(r, Color(1, 0.9, 0.55, 0.85), false, 2.0)
		elif grid.is_open(hover_cell):
			_ov.draw_rect(r, Color(0.7, 0.95, 1.0, 0.35), false, 1.5)
		else:
			_ov.draw_rect(r, Color(1, 0.4, 0.35, 0.3), false, 1.5)
