extends Node2D
## Look study for the "mudling" (泥胎, working name): one body of wet clay around one dense
## core organ, shown in its three life stages. Drawing only: no movement, no ecology logic.
## The node sits at a cell centre; everything is sized in cells and scaled by CELL_PX.
##
## Continuity between stages, on purpose:
##   - the same core organ is visible in every stage;
##   - the three skin creases of the crawler become the seams of the bud's crust,
##     and the flower's crust splits along seams into shards;
##   - weakness is drawn as drying skin, which is what the bud's crust then is;
##   - the strands holding bud and flower are stretched body, the same clay.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

enum Stage { CRAWL, BUD, FLOWER }

const C_LINE := Color("1a1114")
const C_CLAY := Color("9d876d")
const C_CLAY_LIT := Color("cbb999")
const C_CLAY_SHADE := Color("635041")
const C_SKIRT := Color("473731")
const C_DRY := Color("b8ae9b")
const C_CRUST := Color("c6b596")
const C_CRUST_LIT := Color("e8dcc2")
const C_CRUST_SHADE := Color("8a7762")
const C_FLESH := Color("94705c")
const C_FLESH_LIT := Color("c09c84")
const C_FLESH_SHADE := Color("5e4037")
const C_CORE := Color("6a2826")
const C_CORE_LIT := Color("a9523f")
const C_PELLET := Color("5a4030")
const LIGHT := Vector2(-0.55, -0.83)   ## world direction towards the light

var stage: int = Stage.CRAWL
var nutrient := 1          ## carried nutrient 0..3 (crawler only)
var vigor := 1.0           ## 1 healthy .. 0 about to give out (crawler only)
var facing := 0.0          ## radians, crawler heading
var seed_id := 1
var breathe := true
var walls: Array[Vector2] = [Vector2.UP, Vector2.DOWN]   ## solid sides the strands can hold on to

var _t := 0.0
var _u := Spec.CELL_PX


func _process(delta: float) -> void:
	if breathe:
		_t += delta
		queue_redraw()


## Visual bounds in cells, centred on the node (for the debug overlay).
func visual_half_extent() -> Vector2:
	match stage:
		Stage.BUD: return Vector2(0.29, 0.29)
		Stage.FLOWER: return Vector2(0.46, 0.44)
	var long := 0.41
	var wide := 0.2 + 0.03 * nutrient
	return Vector2(long, wide) if absf(cos(facing)) > 0.5 else Vector2(wide, long)


func _draw() -> void:
	match stage:
		Stage.BUD: _draw_bud()
		Stage.FLOWER: _draw_flower()
		_: _draw_crawl()
	draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- helpers

func _h(k: int) -> float:
	var n := (seed_id * 73856093) ^ (k * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0


func _shrink(pts: PackedVector2Array, c: Vector2, k: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k + off)
	return out


func _outline(pts: PackedVector2Array, col: Color = C_LINE, w := 1.6) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, col, w, true)


## Three stacked fills give a soft, heavy volume lit from `light` (local direction).
func _volume(pts: PackedVector2Array, c: Vector2, shade: Color, base: Color, lit: Color, light: Vector2, depth: float) -> void:
	draw_colored_polygon(pts, shade)
	draw_colored_polygon(_shrink(pts, c, 0.84, light * depth), base)
	draw_colored_polygon(_shrink(pts, c, 0.4, light * depth * 2.6), base.lerp(lit, 0.38))


func _blob(c: Vector2, rx: float, ry: float, n: int, k: int, wob := 0.07, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var p1 := _h(k) * TAU
	var p2 := _h(k + 1) * TAU
	for i in n:
		var a := TAU * i / n
		var w := 1.0 + wob * (sin(a * 2.0 + p1) + 0.6 * sin(a * 3.0 + p2))
		pts.append(c + Vector2(cos(a) * rx * w, sin(a) * ry * w).rotated(rot))
	return pts


## A stretched strand of body from a (thick root) to b (small holdfast), sagging sideways.
func _strand(a: Vector2, b: Vector2, w0: float, sag: float, col: Color) -> void:
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var ctrl := (a + b) * 0.5 + perp * sag
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := 9
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
		var tan := (ctrl - a).lerp(b - ctrl, t).normalized()
		var nrm := Vector2(-tan.y, tan.x)
		var w := w0 * (0.2 + 0.8 * pow(1.0 - t, 2.2)) + w0 * 0.22 * pow(t, 6.0)
		left.append(p + nrm * w)
		right.append(p - nrm * w)
	var poly := left.duplicate()
	for i in range(n, -1, -1):
		poly.append(right[i])
	draw_colored_polygon(poly, col)
	draw_polyline(left, Color(C_LINE, 0.75), 1.2, true)
	draw_polyline(right, Color(C_LINE, 0.75), 1.2, true)
	# Holdfast: a small smear pressed onto the wall.
	var pad := _blob(b, w0 * 0.75, w0 * 0.5, 8, int(absf(b.x * 7.0 + b.y * 13.0)), 0.1, perp.angle())
	draw_colored_polygon(pad, col.darkened(0.12))
	_outline(pad, Color(C_LINE, 0.75), 1.2)


## The body is stuck to every solid side by a pulled column of its own clay: wide where it
## leaves the body, necked in the middle, spread out again where it grips the wall.
## `r` is where the columns leave the body.
func _draw_strands(r: float, w0: float, col: Color) -> void:
	var u := _u
	var reach := (0.5 - Spec.WALL_RIM) * u
	for wi in walls.size():
		var d := walls[wi]
		var side := Vector2(-d.y, d.x)
		var lean := (_h(40 + wi) - 0.5) * 0.1 * u
		var neck := w0 * (1.0 + 0.5 * _h(44 + wi))
		var foot := (0.2 + 0.07 * _h(48 + wi)) * u
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var n := 8
		for i in n + 1:
			var t := float(i) / n
			var along := lerpf(r * 0.55, reach, t)
			var w := lerpf(r * 0.8, foot, t) * (1.0 - 4.0 * t * (1.0 - t)) + neck * 4.0 * t * (1.0 - t)
			var mid := d * along + side * lean * sin(PI * t * 0.5)
			left.append(mid - side * w)
			right.append(mid + side * w)
		var poly := left.duplicate()
		for i in range(n, -1, -1):
			poly.append(right[i])
		draw_colored_polygon(poly, col)
		# Lit on the side facing the light, and a couple of stretch wrinkles along the pull.
		var lit_side := left if side.dot(LIGHT) < 0.0 else right
		draw_polyline(_shrink(lit_side, Vector2.ZERO, 1.0, (side if lit_side == left else -side) * 2.0), Color(C_CLAY_LIT, 0.4), 1.2, true)
		for j in 2:
			var k := -0.35 + 0.7 * j
			draw_line(left[2].lerp(right[2], 0.5 + k * 0.5), left[6].lerp(right[6], 0.5 + k * 0.4), Color(C_LINE, 0.3), 1.0, true)
		draw_polyline(left, C_LINE, 1.4, true)
		draw_polyline(right, C_LINE, 1.4, true)


func _core(c: Vector2, rx: float, ry: float, rot: float, light: Vector2, veil: Color, veil_a: float) -> void:
	var pts := _blob(c, rx, ry, 16, 70, 0.05, rot)
	draw_colored_polygon(_shrink(pts, c, 1.22, -light * rx * 0.18), Color(0, 0, 0, 0.22))
	draw_colored_polygon(pts, C_CORE)
	draw_colored_polygon(_shrink(pts, c, 0.55, light * rx * 0.3), C_CORE_LIT)
	draw_colored_polygon(pts, Color(veil, veil_a))
	_outline(pts, Color(C_LINE, 0.55), 1.2)
	draw_circle(c + light * rx * 0.45, maxf(rx * 0.13, 1.0), Color(1, 0.96, 0.9, 0.55))


# ---------------------------------------------------------------- crawler

func _crawl_w(uu: float, half_w: float, bulge: float) -> float:
	var w := half_w * pow(maxf(sin(PI * pow(uu, 0.92)), 0.0), 0.42)
	return w + bulge * exp(-pow((uu - 0.38) / 0.2, 2.0))


## A heavy lump, blunt at both ends; each flank gets its own slow unevenness.
func _crawl_side(length: float, half_w: float, bulge: float, ripple: float, phase: float) -> PackedVector2Array:
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var n := 22
	for i in n + 1:
		var uu := float(i) / n                                   # 0 tail .. 1 head
		var w := _crawl_w(uu, half_w, bulge)
		w *= 1.0 + 0.03 * sin(uu * 8.0 - phase)                  # slow peristaltic swell
		var x := (uu - 0.5) * length
		var rip := ripple * sin(PI * uu)
		top.append(Vector2(x, -w * (1.0 + 0.07 * sin(uu * 5.0 + _h(60) * TAU)) - rip * sin(uu * 30.0 + phase * 1.7)))
		bottom.append(Vector2(x, w * (1.0 + 0.07 * sin(uu * 6.0 + _h(61) * TAU)) + rip * sin(uu * 26.0 - phase * 1.3)))
	var pts := top.duplicate()
	for i in range(n - 1, 0, -1):
		pts.append(bottom[i])
	return pts


func _draw_crawl() -> void:
	var u := _u
	var weak := 1.0 - clampf(vigor, 0.0, 1.0)
	var light := LIGHT.rotated(-facing)
	var phase := _t * 1.5
	var breath := sin(_t * 1.7) * 0.5 + 0.5
	var length := (0.7 + 0.012 * breath) * u
	var half_w := (0.175 - 0.03 * weak + 0.005 * breath) * u
	var bulge := (0.006 + 0.02 * nutrient) * u * (1.0 - 0.3 * weak)
	var clay := C_CLAY.lerp(C_DRY, 0.65 * weak)
	var clay_lit := C_CLAY_LIT.lerp(C_CRUST_LIT, 0.65 * weak)
	var clay_shade := C_CLAY_SHADE.lerp(C_CRUST_SHADE, 0.55 * weak)
	var c := Vector2(-0.03 * u, 0)

	draw_set_transform(Vector2.ZERO, facing)

	# Wet smear left on the back wall behind it (drier when weak).
	var tail_x := -length * 0.5
	var smear := PackedVector2Array([Vector2(tail_x + 0.1 * u, -0.09 * u), Vector2(tail_x - 0.2 * u, -0.05 * u),
		Vector2(tail_x - 0.26 * u, 0), Vector2(tail_x - 0.2 * u, 0.05 * u), Vector2(tail_x + 0.1 * u, 0.09 * u)])
	draw_colored_polygon(smear, Color(0.85, 0.78, 0.66, 0.09 * (1.0 - 0.7 * weak)))

	var skirt := _crawl_side(length * 1.06, half_w * (1.17 - 0.07 * weak), bulge * 1.1, 0.014 * u, phase)
	var mantle := _crawl_side(length, half_w, bulge, 0.0, phase)

	# Contact shadow, then the wet foot spreading out from under the body.
	draw_colored_polygon(_shrink(skirt, c, 1.0, -light * 3.2), Color(0, 0, 0, 0.4))
	draw_colored_polygon(skirt, C_SKIRT.lerp(C_CRUST_SHADE, 0.45 * weak))
	_outline(skirt, C_LINE, 1.4)

	# A blunt probing lip pushed out ahead of the body.
	var lip_c := Vector2(length * 0.47 + sin(_t * 1.5) * 0.006 * u, 0.012 * u)
	var lip := _blob(lip_c, (0.075 - 0.015 * weak) * u, 0.07 * u, 14, 62, 0.06)
	_volume(lip, lip_c, clay_shade, clay, clay_lit, light, 0.012 * u)
	_outline(lip, C_LINE, 1.4)

	_volume(mantle, c, clay_shade, clay, clay_lit, light, 0.032 * u)

	# Three uneven skin folds (they become the seams of the bud).
	for i in 3:
		var uu := 0.55 + 0.105 * i
		var x := (uu - 0.5) * length
		var w := _crawl_w(uu, half_w, bulge)
		# Each fold only crosses part of the back, from alternating flanks: folds, not rings.
		var lo := -0.92 if i % 2 == 0 else -0.25 - 0.2 * _h(63 + i)
		var hi := 0.92 if i % 2 == 1 else 0.15 + 0.25 * _h(66 + i)
		var lean := (_h(69 + i) - 0.5) * 0.05 * u
		var arc := PackedVector2Array()
		for j in 9:
			var t := lerpf(lo, hi, float(j) / 8.0)
			arc.append(Vector2(x + 0.03 * u * (1.0 - t * t) + lean * t, t * w))
		draw_polyline(arc, Color(C_LINE, 0.45), 1.5, true)
		draw_polyline(_shrink(arc, Vector2.ZERO, 1.0, Vector2(1.4, 0)), Color(clay_lit, 0.35), 1.0, true)

	# Swallowed pellets of soil packed around the core: this is the carried nutrient.
	var core_c := Vector2(-0.085 * u, 0)
	var slots: Array[Vector2] = [Vector2(-0.115, 0.01), Vector2(-0.045, -0.095), Vector2(-0.04, 0.1)]
	for i in mini(nutrient, 3):
		var pc := core_c + slots[i] * u
		var r := 0.046 * u
		draw_circle(pc - light * r * 0.3, r * 1.25, Color(0, 0, 0, 0.22))
		draw_circle(pc, r, C_PELLET.lerp(clay, 0.25))
		draw_circle(pc + light * r * 0.35, r * 0.45, clay.lerp(clay_lit, 0.3))
		draw_arc(pc, r, 0, TAU, 12, Color(C_LINE, 0.5), 1.0, true)
	_core(core_c, 0.072 * u, 0.06 * u, 0.0, light, clay, 0.3)

	# Head: two sensing pits pressed into the clay.
	for s: float in [-1.0, 1.0]:
		var p := Vector2(length * 0.37, s * 0.06 * u)
		draw_circle(p, 0.027 * u, Color(C_LINE, 0.9))
		draw_arc(p, 0.027 * u, 0.4, 2.4, 6, Color(clay_lit, 0.5), 1.0, true)

	# Thumbed dents and grit in the surface.
	for i in 3:
		var uu := 0.14 + 0.1 * i
		var p := Vector2((uu - 0.5) * length, (2.0 * _h(74 + i) - 1.0) * _crawl_w(uu, half_w, bulge) * 0.5)
		draw_circle(p, 0.02 * u, Color(clay_shade, 0.55))
		draw_arc(p, 0.02 * u, 0.3, 2.6, 6, Color(clay_lit, 0.45), 1.0, true)
	for i in 6:
		var uu := 0.12 + 0.7 * _h(10 + i)
		var p := Vector2((uu - 0.5) * length, (2.0 * _h(20 + i) - 1.0) * _crawl_w(uu, half_w, bulge) * 0.75)
		draw_circle(p, 0.8 + 0.9 * _h(30 + i), Color(0, 0, 0, 0.32) if _h(34 + i) < 0.6 else Color(1, 0.95, 0.85, 0.3))

	# Drying cracks appear as it weakens.
	if weak > 0.3:
		for i in 5:
			var uu := 0.16 + 0.15 * i
			var p := Vector2((uu - 0.5) * length, (2.0 * _h(80 + i) - 1.0) * half_w * 0.6)
			var q := p + Vector2(0.03 + 0.03 * _h(84 + i), 0.07 * (_h(88 + i) - 0.5)) * u
			var r := q + Vector2(0.02, 0.07 * (_h(92 + i) - 0.5)) * u
			draw_polyline(PackedVector2Array([p, q, r]), Color(C_LINE, 0.55 * weak), 1.1, true)

	# Wet sheen on the lit flank (gone when dry).
	var sheen_c := c + light * half_w * 0.55 + Vector2(0.05 * u, 0)
	var along := Vector2(-light.y, light.x)
	draw_line(sheen_c - along * 0.08 * u, sheen_c + along * 0.05 * u, Color(1, 0.98, 0.92, 0.5 * (1.0 - weak)), 2.2, true)
	draw_circle(sheen_c + along * 0.09 * u, 1.4, Color(1, 0.98, 0.92, 0.55 * (1.0 - weak)))

	_outline(mantle)


# ---------------------------------------------------------------- bud

func _draw_bud() -> void:
	var u := _u
	var breath := sin(_t * 1.1)
	var r := (0.265 + 0.004 * breath) * u
	var c := Vector2(0, 0.01 * u)

	# Stain where the foot has spread out and stuck to the back wall.
	draw_colored_polygon(_blob(c, r * 1.3, r * 1.2, 18, 3, 0.09), Color(C_SKIRT.lerp(Color("1d151c"), 0.45), 0.9))
	_draw_strands(r, 0.05 * u, C_CLAY.lerp(C_CLAY_SHADE, 0.25))

	var body := PackedVector2Array()
	var n := 30
	for i in n:
		var a := TAU * i / n
		var w := 1.0 + 0.035 * sin(a * 2.0 + 1.0) + 0.025 * sin(a * 5.0 + 2.0)
		var p := Vector2(cos(a), sin(a)) * r * w
		if p.y > 0:
			p.y *= 1.07                                  # it sags: heavier underneath
		body.append(c + p)

	draw_colored_polygon(_shrink(body, c, 1.03, Vector2(2.5, 3.5)), Color(0, 0, 0, 0.4))
	# What is left of the skirt, dried into a frill on the underside.
	for i in 7:
		var a := 0.35 + i * 0.4
		draw_circle(c + Vector2(cos(a), sin(a) * 1.07) * r * 1.02, 0.03 * u, C_CRUST_SHADE.darkened(0.15))
		draw_arc(c + Vector2(cos(a), sin(a) * 1.07) * r * 1.02, 0.03 * u, a - 1.3, a + 1.3, 6, C_LINE, 1.2, true)
	_volume(body, c, C_CRUST_SHADE, C_CRUST, C_CRUST_LIT, LIGHT, 0.045 * u)

	# The body is curled round its core: one seam spirals in from the rim.
	var a0 := -2.5
	var spiral := PackedVector2Array()
	var turns := 1.3
	var m := 34
	for i in m + 1:
		var t := float(i) / m
		var a := a0 + t * turns * TAU
		spiral.append(c + Vector2(cos(a), sin(a)) * r * lerpf(0.97, 0.3, pow(t, 0.8)))
	draw_polyline(spiral, Color(C_LINE, 0.8), 1.7, true)
	draw_polyline(_shrink(spiral, c, 1.0, Vector2(1.0, 1.4)), Color(C_CRUST_LIT, 0.45), 1.0, true)
	# The crawler's three creases, now seams across the outer coil.
	for i in 3:
		var t := 0.2 + 0.2 * i
		var a := a0 + t * turns * TAU
		var r_in := r * lerpf(0.97, 0.3, pow(t, 0.8))
		var dir := Vector2(cos(a + 0.12), sin(a + 0.12))
		draw_line(c + dir * r_in * 0.98, c + Vector2(cos(a), sin(a)) * r * 1.0, Color(C_LINE, 0.7), 1.5, true)
	# Shrinkage cracks in the crust.
	for i in 6:
		var a := _h(100 + i) * TAU
		var p := c + Vector2(cos(a), sin(a)) * r * (0.45 + 0.4 * _h(110 + i))
		var q := p + Vector2(_h(120 + i) - 0.5, _h(130 + i) - 0.5) * 0.11 * u
		var e := q + Vector2(_h(140 + i) - 0.5, _h(150 + i) - 0.5) * 0.07 * u
		draw_polyline(PackedVector2Array([p, q, e]), Color(C_CRUST_SHADE.darkened(0.35), 0.75), 1.0, true)

	# Along the last stretch of the seam the crust has pulled apart, and the moist core
	# shows in the gash.
	var end_a := a0 + turns * TAU
	var gash := PackedVector2Array()
	for i in 9:
		var t := 0.74 + 0.26 * float(i) / 8.0
		var a := a0 + t * turns * TAU
		gash.append(c + Vector2(cos(a), sin(a)) * r * lerpf(0.97, 0.3, pow(t, 0.8)) * 0.94)
	var slit_c := gash[5]
	draw_polyline(gash, C_LINE, 0.13 * u, true)
	draw_circle(gash[0], 0.065 * u, C_LINE)
	draw_circle(gash[8], 0.065 * u, C_LINE)
	draw_polyline(gash, C_FLESH_SHADE, 0.095 * u, true)
	draw_circle(gash[0], 0.047 * u, C_FLESH_SHADE)
	draw_circle(gash[8], 0.047 * u, C_FLESH_SHADE)
	var inner := gash.slice(1, 8)
	draw_polyline(inner, C_CORE, (0.06 + 0.004 * breath) * u, true)
	draw_polyline(_shrink(inner, Vector2.ZERO, 1.0, LIGHT * 1.2), C_CORE_LIT, 0.02 * u, true)
	# The head is tucked in beside it: the two pits are still there.
	var head_dir := Vector2(cos(end_a - 1.5), sin(end_a - 1.5))
	var head_side := Vector2(-head_dir.y, head_dir.x)
	for s: float in [-1.0, 1.0]:
		draw_circle(slit_c + head_dir * 0.1 * u + head_side * s * 0.04 * u, 0.02 * u, Color(C_LINE, 0.85))

	_outline(body)


# ---------------------------------------------------------------- flower

func _draw_flower() -> void:
	var u := _u
	var c := Vector2(0, 0.0)
	var breath := sin(_t * 1.3)

	draw_colored_polygon(_blob(c, 0.4 * u, 0.38 * u, 18, 3, 0.09), Color(C_SKIRT.lerp(Color("1d151c"), 0.45), 0.9))
	_draw_strands(0.26 * u, 0.065 * u, C_CLAY.lerp(C_CLAY_SHADE, 0.25))

	# The crust has burst along its seams. Two shards still stand above, two have been
	# forced down and outwards by the weight of what is inside.
	# Each shard is a curved piece of the round shell, so the bud is still readable in it.
	var angs: Array[float] = [-2.3, -0.85, 0.4, 2.75]
	var spans: Array[float] = [0.6, 0.62, 0.46, 0.5]
	var push: Array[float] = [0.035, 0.03, 0.085, 0.075]     # the lower two have slid further out
	var tilt: Array[float] = [0.0, 0.0, 0.22, -0.2]
	for i in 4:
		var a := angs[i] + (_h(200 + i) - 0.5) * 0.16
		var dir := Vector2(cos(a), sin(a))
		var sc := c + dir * (push[i] + 0.265) * u
		var shard := PackedVector2Array()
		var m := 6
		for j in m + 1:
			var t := float(j) / m
			var aa := a + (t * 2.0 - 1.0) * spans[i] + tilt[i]
			var r_out := (0.335 + 0.035 * (_h(210 + i * 8 + j) - 0.5) * 2.0) * u
			shard.append(c + dir * push[i] * u + Vector2(cos(aa), sin(aa)) * r_out)
		for j in range(m, -1, -1):
			var t := float(j) / m
			var aa := a + (t * 2.0 - 1.0) * spans[i] * 0.9 + tilt[i]
			shard.append(c + dir * push[i] * u + Vector2(cos(aa), sin(aa)) * 0.215 * u)
		draw_colored_polygon(_shrink(shard, sc, 1.0, Vector2(2.5, 3.5)), Color(0, 0, 0, 0.38))
		draw_colored_polygon(shard, C_CRUST_SHADE)
		draw_colored_polygon(_shrink(shard, sc, 0.82, LIGHT * 0.012 * u), C_CRUST)
		for j in 2:
			var aa := a + (_h(240 + i * 2 + j) - 0.5) * spans[i] * 1.3 + tilt[i]
			var p0 := c + dir * push[i] * u + Vector2(cos(aa), sin(aa)) * 0.24 * u
			var p1 := c + dir * push[i] * u + Vector2(cos(aa + 0.12), sin(aa + 0.12)) * 0.31 * u
			draw_line(p0, p1, Color(C_CRUST_SHADE.darkened(0.35), 0.8), 1.0, true)
		_outline(shard)

	# The wet inside has swollen out through the split and sags under its own weight.
	var mc := c + Vector2(0.0, 0.045 * u)
	var mass := PackedVector2Array()
	for i in 26:
		var a := TAU * i / 26.0
		var w := 1.0 + 0.06 * sin(a * 3.0 + 0.7) + 0.04 * sin(a * 5.0 + 2.0)
		var p := Vector2(cos(a) * 0.21, sin(a) * 0.2) * u * w
		if p.y > 0:
			p.y *= 1.22
		mass.append(mc + p)
	draw_colored_polygon(_shrink(mass, mc, 1.03, Vector2(2.5, 3.5)), Color(0, 0, 0, 0.35))
	_volume(mass, mc, C_FLESH_SHADE, C_FLESH, C_FLESH_LIT, LIGHT, 0.035 * u)
	# Heavy folds in it.
	for i in 3:
		var a := 0.5 + i * 1.05
		var p0 := mc + Vector2(cos(a), sin(a)) * 0.09 * u
		var p1 := mc + Vector2(cos(a + 0.25), sin(a + 0.25) * 1.2) * 0.2 * u
		draw_polyline(PackedVector2Array([p0, (p0 + p1) * 0.5 + Vector2(0.015 * u, 0), p1]), Color(C_LINE, 0.45), 1.4, true)
	_outline(mass)
	draw_line(mc + Vector2(-0.13, -0.11) * u, mc + Vector2(-0.07, -0.15) * u, Color(1, 0.98, 0.92, 0.45), 2.0, true)

	# One brood lump has already sagged free and hangs by a thread.
	var hang := c + Vector2(0.075 * u, 0.345 * u)
	_strand(c + Vector2(0.05 * u, 0.2 * u), hang, 0.022 * u, 0.008 * u, C_CLAY.lerp(C_CLAY_SHADE, 0.2))
	_brood(hang, 0.05 * u, 7)

	# Brood lumps pinching off the lower half, crowded round the swollen core.
	var spots: Array[Vector2] = [Vector2(-0.14, 0.07), Vector2(-0.045, 0.19), Vector2(0.1, 0.17), Vector2(0.155, 0.04)]
	for i in spots.size():
		_brood(c + spots[i] * u, (0.062 + 0.012 * _h(270 + i)) * u, 10 + i)
	_core(c + Vector2(0.0, -0.035 * u), (0.095 + 0.004 * breath) * u, (0.085 + 0.004 * breath) * u, 0.4, LIGHT, C_FLESH, 0.16)


## A small lump of the same clay with its own speck of core: a crawler about to be.
func _brood(p: Vector2, r: float, k: int) -> void:
	var pts := _blob(p, r, r * 0.9, 12, 300 + k, 0.06, _h(310 + k) * TAU)
	draw_colored_polygon(_shrink(pts, p, 1.15, Vector2(1.5, 2.0)), Color(0, 0, 0, 0.3))
	_volume(pts, p, C_CLAY_SHADE, C_CLAY, C_CLAY_LIT, LIGHT, r * 0.16)
	# Its own speck of core, seen dimly through the clay.
	draw_circle(p + Vector2(r * 0.15, r * 0.12), r * 0.2, Color(C_CORE, 0.4))
	draw_arc(p, r * 0.62, 2.6, 4.4, 5, Color(C_LINE, 0.4), 1.0, true)
	_outline(pts, C_LINE, 1.3)
