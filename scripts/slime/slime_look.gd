extends Node2D
## Look of the nutrient slime (养分史莱姆, working name): the first nutrient-line base creature.
## Built for reading at 64 px per cell: one bold silhouette per stage, a handful of flat
## colour areas, a thick outline, and a face. Drawing only; whoever owns this node drives
## the few animation inputs below (stretch, spot_pop, moving).
##
## What tells the stages apart is SHAPE, so levels and subspecies can recolour freely:
##   crawler - low teardrop lying along its heading, two eye bumps breaking the outline
##   bud     - upright closed bulb with a pointed tip; always points to the top of the screen
##   flower  - broad six-petal corolla on a stalk, a small grinning face in the middle
## Colour roles (see PALETTES): body, its shade/light, mark (nutrient spots, flower face),
## accent (petals, bud tip). Swapping a palette never changes a silhouette.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

enum Stage { CRAWL, BUD, FLOWER }

const PALETTES := {
	"green": {"body": Color("76c84a"), "shade": Color("3c8a3d"), "lit": Color("bdec7c"),
		"mark": Color("f8e68c"), "accent": Color("f0508f"), "accent_shade": Color("a82d68")},
	"blue": {"body": Color("58aede"), "shade": Color("2c6aa6"), "lit": Color("a9defa"),
		"mark": Color("fff0b0"), "accent": Color("f6922e"), "accent_shade": Color("b4551a")},
}
const C_LINE := Color("17100f")
const C_EYE := Color("fff8e8")
const C_PUPIL := Color("1a1116")
const C_MOUTH := Color("4a1428")
const C_WEAK := Color("9a9a86")
const LINE_W := 2.4
const LIGHT := Vector2(-0.55, -0.83)   ## world direction towards the light

var stage: int = Stage.CRAWL
var nutrient := 1                 ## carried nutrient 0..3 (crawler): body size and back spots
var vigor := 1.0                  ## 1 healthy .. 0 spent (crawler): a secondary cue only
var facing := 0.0                 ## radians, crawler heading
var palette := "green"
var silhouette := false           ## draw the bare outline shape in one flat colour
var stretch := 0.0                ## crawler: >0 longer and thinner, <0 squashed (driven by the owner)
var spot_pop := 1.0               ## crawler: scale of the newest back spot (pop-in)
var moving := false               ## crawler: the rear squirm is stronger while travelling
var breathe := true

var _t := 0.0
var _u := Spec.CELL_PX
var _pal: Dictionary


func _process(delta: float) -> void:
	if breathe:
		_t += delta
		queue_redraw()


## Visual bounds in cells, centred on the node (for the debug overlay).
func visual_half_extent() -> Vector2:
	match stage:
		Stage.BUD: return Vector2(0.27, 0.44)
		Stage.FLOWER: return Vector2(0.4, 0.44)
	var k := _crawl_scale()
	var ext := Vector2(0.4 * k, 0.31 * k)
	return ext if absf(cos(facing)) > 0.5 else Vector2(ext.y, ext.x)


func _draw() -> void:
	_pal = PALETTES[palette]
	match stage:
		Stage.BUD: _draw_bud()
		Stage.FLOWER: _draw_flower()
		_: _draw_crawl()
	draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- helpers

func _c(col: Color) -> Color:
	return Color("d9d3c6") if silhouette else col


func _fill(pts: PackedVector2Array, col: Color) -> void:
	draw_colored_polygon(pts, _c(col))


func _edge(pts: PackedVector2Array, w := LINE_W) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, _c(C_LINE), w, true)


func _shadow(pts: PackedVector2Array, off: Vector2) -> void:
	if silhouette:
		return
	var s := PackedVector2Array()
	for p in pts:
		s.append(p + off)
	draw_colored_polygon(s, Color(0, 0, 0, 0.4))


func _shrink(pts: PackedVector2Array, c: Vector2, k: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k + off)
	return out


## Disc with outline.
func _disc(c: Vector2, r: float, col: Color, w := LINE_W) -> void:
	draw_circle(c, r + w * 0.5, _c(C_LINE))
	draw_circle(c, r - w * 0.5, _c(col))


func _ellipse(c: Vector2, rx: float, ry: float, rot := 0.0, n := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


## Open eye: white, pupil looking along `look`, optional heavy lid from the `lid_from` side.
func _eye(c: Vector2, r: float, look: Vector2, lid := 0.0, lid_from := Vector2.UP) -> void:
	_disc(c, r, C_EYE, 2.0)
	draw_circle(c + look * r * 0.32, r * 0.5, _c(C_PUPIL))
	if silhouette:
		return
	draw_circle(c + look * r * 0.32 + Vector2(-0.3, -0.35) * r, r * 0.17, C_EYE)
	if lid > 0.05:
		# The lid is a body-coloured cap sliding over the eye.
		var cap := PackedVector2Array()
		var base_a := lid_from.angle()
		var half := lerpf(0.5, PI * 0.62, lid)
		for i in 9:
			var a := base_a - half + 2.0 * half * i / 8.0
			cap.append(c + Vector2(cos(a), sin(a)) * (r + 0.6))
		draw_colored_polygon(cap, _body())
		draw_line(cap[0], cap[8], C_LINE, 1.6, true)


func _body() -> Color:
	var col: Color = _pal.body
	return col.lerp(C_WEAK, 0.45 * (1.0 - vigor)) if stage == Stage.CRAWL else col


func _shade() -> Color:
	var col: Color = _pal.shade
	return col.lerp(C_WEAK.darkened(0.35), 0.45 * (1.0 - vigor)) if stage == Stage.CRAWL else col


# ---------------------------------------------------------------- crawler

func _crawl_scale() -> float:
	return 0.84 + 0.07 * clampi(nutrient, 0, 3)     # size says nutrient and nothing else


func _draw_crawl() -> void:
	var u := _u
	var weak := 1.0 - clampf(vigor, 0.0, 1.0)
	var k := _crawl_scale()
	var breath := sin(_t * 2.0)
	var light := LIGHT.rotated(-facing)
	var length := 0.74 * u * k * (1.0 + stretch)
	var radius := (0.215 + 0.012 * nutrient) * u * k * (1.0 + 0.025 * breath) * (1.0 - 0.55 * stretch)
	var wag := sin(_t * (3.2 if moving else 1.6)) * (0.5 if moving else 0.35) * (1.0 - 0.6 * weak)
	var mark: Color = _pal.mark
	var lit: Color = _pal.lit
	var shade: Color = _pal.shade

	draw_set_transform(Vector2.ZERO, facing)

	# A plump slug: round in front, blunt behind, with a slow squirm through the rear.
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var n := 22
	for i in n + 1:
		var uu := float(i) / n                                  # 0 tail tip .. 1 nose
		var x := (uu - 0.47) * length
		var w := radius * pow(maxf(sin(PI * pow(uu, 1.1)), 0.0), 0.4)
		var sway := 0.07 * u * k * pow(1.0 - uu, 2.2) * wag
		top.append(Vector2(x, -w + sway))
		bottom.append(Vector2(x, w + sway))
	var body := top.duplicate()
	for i in range(n - 1, 0, -1):
		body.append(bottom[i])
	var c := Vector2(0.08 * length, 0)

	var eye_r := 0.088 * u * k
	var eye_x := 0.4 * length
	var eye_y := radius * 0.56
	_shadow(body, -light * 4.0)
	# Eye bumps go down first so they fuse with the body outline.
	for s: float in [-1.0, 1.0]:
		draw_circle(Vector2(eye_x, s * eye_y), eye_r + LINE_W, _c(C_LINE))
	_fill(body, _shade())
	if not silhouette:
		draw_colored_polygon(_shrink(body, c, 0.86, light * 0.032 * u), _body())
	_edge(body)
	for s: float in [-1.0, 1.0]:
		draw_circle(Vector2(eye_x, s * eye_y), eye_r, _c(_body()))

	if not silhouette:
		# Back spots: one per carried nutrient, biggest first, running towards the tail.
		# Round, yellow and ringed in dark, so they can not be taken for the highlight.
		var xs: Array[float] = [-0.03, -0.2, -0.33]
		var rs: Array[float] = [0.078, 0.06, 0.044]
		var count := mini(nutrient, 3)
		for i in count:
			var sway := 0.07 * u * k * pow(1.0 - (xs[i] + 0.47), 2.2) * wag
			var p := Vector2(xs[i] * length, sway)
			var r := rs[i] * u * k * (spot_pop if i == count - 1 else 1.0)
			draw_circle(p, r + 1.8, Color(C_LINE, 0.85))
			draw_circle(p, r, mark.lerp(C_WEAK, 0.3 * weak))
		# Highlight: a thin streak hugging the lit flank near the head, never a round patch.
		var hl := Vector2(0.24 * length, 0) + light * radius * 0.62
		var along := Vector2(-light.y, light.x)
		draw_line(hl - along * 0.07 * u * k, hl + along * 0.07 * u * k, Color(lit, 0.85 * (1.0 - 0.6 * weak)), 2.2, true)

	for s: float in [-1.0, 1.0]:
		_eye(Vector2(eye_x + 0.008 * u, s * eye_y), eye_r * 0.74, Vector2(0.9, s * 0.25), weak * 0.62, Vector2.LEFT)
	if not silhouette:
		# Mouth: a small curve on the nose; it sags when weak.
		var mx := 0.49 * length
		if weak > 0.5:
			draw_arc(Vector2(mx + 0.045 * u * k, 0), 0.04 * u * k, PI * 0.62, PI * 1.38, 6, C_LINE, 1.8, true)
		else:
			draw_arc(Vector2(mx - 0.035 * u * k, 0), 0.05 * u * k, -0.85, 0.85, 6, C_LINE, 1.8, true)


# ---------------------------------------------------------------- bud and flower

## Foot of the plant: a small mound at the bottom of the cell, optionally with two leaves.
## Bud and flower always stand upright in their cell, whatever the tunnel around them does.
func _base(u: float, leaves: bool, breath: float) -> void:
	if leaves:
		for s: float in [-1.0, 1.0]:
			var root := Vector2(0.0, 0.38 * u)
			var tip := root + Vector2(s * 0.25 * u, -0.08 * u + 0.01 * u * breath)
			var leaf := PackedVector2Array([root, root.lerp(tip, 0.45) + Vector2(0, -0.08 * u), tip, root.lerp(tip, 0.5) + Vector2(0, 0.05 * u)])
			_fill(leaf, _pal.body)
			_edge(leaf)
	var mound := PackedVector2Array()
	for i in 9:
		var a := PI + PI * i / 8.0
		mound.append(Vector2(cos(a) * 0.17 * u, 0.435 * u + sin(a) * 0.07 * u))
	_fill(mound, _pal.shade)
	draw_polyline(mound, _c(C_LINE), LINE_W, true)


func _stem(from: Vector2, to: Vector2, width: float) -> void:
	var pts := PackedVector2Array([from, (from + to) * 0.5 + Vector2(0.04 * _u, 0), to])
	draw_polyline(pts, _c(C_LINE), width + LINE_W * 2.0, true)
	draw_polyline(pts, _c(_pal.shade), width, true)


func _draw_bud() -> void:
	var u := _u
	var breath := sin(_t * 1.2)
	var lit: Color = _pal.lit
	var lift := 0.0

	_base(u, false, breath)

	# Closed bulb: heavy below, drawn up into a point that leans a little.
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var mid := PackedVector2Array()
	var n := 20
	for i in n + 1:
		var s := float(i) / n                                   # 0 bottom .. 1 tip
		var y := lerpf(0.37, -0.42, s) * u + lift * (1.0 - s)
		var hw := 0.25 * u * pow(maxf(sin(PI * pow(s, 0.72)), 0.0), 0.6) * lerpf(1.0, 0.5, smoothstep(0.55, 1.0, s))
		hw *= 1.0 + 0.02 * breath
		var lean := 0.05 * u * pow(s, 3.0)
		left.append(Vector2(lean - hw, y))
		right.append(Vector2(lean + hw, y))
		mid.append(Vector2(lean + hw * 0.25 * sin(PI * s), y))
	var bulb := left.duplicate()
	for i in range(n - 1, 0, -1):
		bulb.append(right[i])

	_shadow(bulb, Vector2(3.0, 3.0))
	_fill(bulb, _pal.body)
	if not silhouette:
		# The overlapping outer leaf on the shaded side.
		var leaf := mid.duplicate()
		for i in range(n - 1, 0, -1):
			leaf.append(right[i])
		draw_colored_polygon(leaf, _pal.shade)
		# The petals show at the tip: a promise of the flower.
		var cut := int(n * 0.7)
		var tip := PackedVector2Array()
		for i in range(cut, n + 1):
			tip.append(left[i])
		for i in range(n - 1, cut - 1, -1):
			tip.append(right[i])
		draw_colored_polygon(tip, _pal.accent)
		draw_line(left[cut], right[cut], C_LINE, 1.8, true)
		draw_polyline(mid.slice(0, cut + 1), C_LINE, 1.8, true)
		draw_colored_polygon(_ellipse(Vector2(-0.1 * u, 0.12 * u + lift), 0.035 * u, 0.075 * u, 0.2), Color(lit, 0.9))
		# Asleep: two closed eyes.
		for s: float in [-1.0, 1.0]:
			draw_arc(Vector2(s * 0.085 * u - 0.01 * u, 0.1 * u + lift), 0.045 * u, 0.25, PI - 0.25, 6, C_LINE, 2.0, true)
	_edge(bulb)


func _petal(hc: Vector2, a: float, length: float, wid: float, u: float) -> PackedVector2Array:
	var dir := Vector2(cos(a), sin(a))
	var side := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		hc + dir * 0.06 * u - side * wid * 0.6,
		hc + dir * length * 0.5 - side * wid,
		hc + dir * length * 0.8 - side * wid * 0.72,
		hc + dir * length,
		hc + dir * length * 0.8 + side * wid * 0.72,
		hc + dir * length * 0.5 + side * wid,
		hc + dir * 0.06 * u + side * wid * 0.6])


func _draw_flower() -> void:
	var u := _u
	var breath := sin(_t * 1.6)
	var accent_shade: Color = _pal.accent_shade
	var hc := Vector2(0.0, -0.055 * u)

	_base(u, true, breath)
	_stem(Vector2(0, 0.4 * u), hc + Vector2(0, 0.2 * u), 0.1 * u)

	# The corolla is the stage: six broad petals filling most of the cell, flexing a little.
	var count := 6
	for layer in 2:
		for i in count:
			if i % 2 != layer:
				continue                                         # back three first, then front three
			var a := -PI * 0.5 + TAU * i / count
			var length := (0.375 if layer == 1 else 0.35) + 0.012 * sin(_t * 1.6 + i * 1.3)
			var petal := _petal(hc, a, length * u, 0.15 * u, u)
			_fill(petal, _pal.accent if layer == 1 else accent_shade.lerp(_pal.accent, 0.45))
			_edge(petal)

	# A small plain face in the middle: two dots and one big grin with a single tooth.
	var r := 0.135 * u
	_disc(hc, r, _pal.mark)
	if silhouette:
		return
	for s: float in [-1.0, 1.0]:
		draw_circle(hc + Vector2(s * 0.055 * u, -0.045 * u), 0.026 * u, C_PUPIL)
	var mouth := PackedVector2Array()
	var mc := hc + Vector2(0, 0.01 * u)
	for i in 9:
		var a := PI * i / 8.0
		mouth.append(mc + Vector2(cos(a) * 0.095 * u, sin(a) * (0.085 + 0.008 * breath) * u))
	draw_colored_polygon(mouth, C_MOUTH)
	draw_colored_polygon(PackedVector2Array([mc + Vector2(-0.03 * u, 0), mc + Vector2(0.03 * u, 0),
		mc + Vector2(0.03 * u, 0.04 * u), mc + Vector2(-0.03 * u, 0.04 * u)]), C_EYE)
	_edge(mouth, 1.8)
