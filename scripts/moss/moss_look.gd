extends Node2D
## Look of the moss (苔), the first nutrient-line creature, crawling stage, in SIDE view
## (task ART-004). The map is a side cut, so:
##   moving sideways  - seen from the side, sitting on the tunnel floor;
##   moving up        - seen from behind;
##   moving down      - seen from the front.
## It has no face. A short sprout on top shows where it is heading: it leans forward when
## the moss walks sideways, stands up when it climbs, and sways when it comes down.
##
## Drawn in code with four tones (under-shade, body, lit patches, highlights), leaf tips
## along the top edge and tufts in the lit parts only, so it has some depth when large and
## still reads as one clean lump when small. Light always comes from the upper left,
## whichever way the moss faces. Drawing only; the owner drives `heading`, `step`, `vigor`.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

enum Heading { RIGHT, LEFT, UP, DOWN }
enum Stage { CRAWL, BUD, FLOWER }

const C_LINE := Color("17100f")
const C_UNDER := Color("2c5529")
const C_BODY := Color("4b873a")
const C_LIT := Color("6ea544")
const C_TUFT := Color("8ec455")
const C_SHINE := Color("c6ea82")
const C_LEAF := Color("3c7634")
const C_STEM := Color("3c8a3d")
const C_STEM_LIT := Color("7acb4c")
const C_WEAK := Color("a39a52")           ## weak moss yellows
const C_PETAL := Color("ee5a96")
const C_PETAL_DARK := Color("a8306a")
const C_PETAL_LIT := Color("ffa6cb")
const C_CORE := Color("f0b43c")
const C_CORE_DARK := Color("a9691c")
const LINE_W := 2.4
const FLOOR_Y := 0.43                     ## cells below the cell centre: top of the floor lip
const BODY_SCALE := 1.1                   ## overall size; about 0.86 cell wide
const TALL := 1.22                        ## extra height, so it fills half the tunnel

var stage: int = Stage.CRAWL      ## bud and flower are rooted: fixed in the cell, always upright
var heading: int = Heading.RIGHT
var vigor := 1.0                  ## 1 healthy .. 0 spent
var step := 0.0                   ## crawl cycle position; one unit per cell travelled
var moving := true
## A transition being played, driven by the owner: "root" (crawler -> bud, stage still
## CRAWL), "starve" (crawler dying), "bloom" (stage BUD), "wither" (stage BUD),
## "release" (stage FLOWER), or "".
var anim := ""
var anim_t := 0.0                 ## 0..1 progress of `anim`
## Crawler only. Where it sits in the cell: 1 on the tunnel floor, 0 in mid-cell (in a
## shaft). Negative: decide from `heading`. Owners ease it so the body does not jump
## when it turns from a corridor into a shaft.
var seat := -1.0
var squash := 0.0                 ## >0 presses it flat and wide for a moment (gulp, turn, landing)
var breathe := true               ## advance its own clock (previews); owners may set _t

var _t := 0.0
var _weak := 0.0                  ## 0 healthy .. 1 spent, as drawn this frame (vigor and transitions)
var _u := Spec.CELL_PX


func _process(delta: float) -> void:
	if breathe:
		_t += delta
		queue_redraw()


## Visual bounds in cells, centred on the node.
func visual_half_extent() -> Vector2:
	return Vector2(0.44, 0.46)


func _tone(c: Color) -> Color:
	return c.lerp(C_WEAK.darkened(0.25 * (1.0 - c.v)), 0.6 * _weak)


## Catmull-Rom through the points: turns a handful of control points into a soft outline.
func _smooth(pts: PackedVector2Array, steps := 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for s in steps:
			var t := float(s) / steps
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[n - 1])
	return out


func _edge(pts: PackedVector2Array, w := LINE_W) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, C_LINE, w, true)


func _blob(c: Vector2, rx: float, ry: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	var u := _u * BODY_SCALE
	var weak := 1.0 - clampf(vigor, 0.0, 1.0)
	var a_root := anim_t if anim == "root" else 0.0
	var a_bloom := anim_t if anim == "bloom" else 0.0
	var a_wither := anim_t if anim == "wither" else 0.0
	var a_release := anim_t if anim == "release" else 0.0
	var a_starve := anim_t if anim == "starve" else 0.0
	weak = maxf(weak, maxf(smoothstep(0.0, 0.5, a_wither), maxf(smoothstep(0.35, 0.75, a_release), smoothstep(0.0, 0.4, a_starve))))
	var rooted := stage != Stage.CRAWL
	# 0: a crawling lump .. 1: spread out flat as the cushion under the plant.
	var settle := 1.0 if rooted else smoothstep(0.0, 0.5, a_root)
	var side := heading == Heading.RIGHT or heading == Heading.LEFT
	var dir := -1.0 if heading == Heading.LEFT else 1.0
	_weak = weak
	modulate.a = 1.0 - maxf(smoothstep(0.75, 1.0, a_wither), maxf(smoothstep(0.8, 1.0, a_release), smoothstep(0.7, 1.0, a_starve)))
	# Sideways it sits on the floor; in a shaft it is drawn in the middle of the cell.
	var crawl_seat := (FLOOR_Y if side else 0.26) if seat < 0.0 else lerpf(0.26, FLOOR_Y, clampf(seat, 0.0, 1.0))
	var base_y := lerpf(crawl_seat, FLOOR_Y, settle) * _u
	var crawling := moving and not rooted and anim != "root" and anim != "starve"
	var cycle := step * TAU * 2.0 if crawling else 0.0     # two pushes per cell
	var push := sin(cycle) if crawling else 0.0
	var breath := sin(_t * 1.8)
	# Squash and stretch of the whole lump: long and low while reaching, short and tall
	# while gathering. Weak moss is flatter and barely pushes.
	var sx := 1.0 + (0.06 * push if side else 0.03 * push) * (1.0 - 0.6 * weak)
	var sy := (1.0 - 0.07 * push + 0.015 * breath) * (1.0 - 0.2 * weak) * TALL
	# Rooted, the moss spreads out into a low cushion under the plant.
	sx = lerpf(sx, 1.06, settle)
	sy *= lerpf(1.0, 0.6, settle)
	sx *= 1.0 + 0.5 * squash
	sy *= 1.0 - squash
	# Starving: it slumps flat before it fades.
	sx *= 1.0 + 0.12 * smoothstep(0.25, 0.85, a_starve)
	sy *= lerpf(1.0, 0.4, smoothstep(0.25, 0.85, a_starve))

	# --- outline control points, in cells, y up from the floor
	var ctrl: Array[Vector2] = []
	if side:
		ctrl = [Vector2(-0.36, 0.0), Vector2(-0.39, 0.11), Vector2(-0.31, 0.23), Vector2(-0.20, 0.25),
			Vector2(-0.13, 0.35), Vector2(0.0, 0.39), Vector2(0.09, 0.32), Vector2(0.19, 0.35),
			Vector2(0.30, 0.27), Vector2(0.34, 0.15), Vector2(0.38, 0.07), Vector2(0.36, 0.0)]
	else:
		ctrl = [Vector2(-0.34, 0.0), Vector2(-0.37, 0.13), Vector2(-0.27, 0.26), Vector2(-0.13, 0.29),
			Vector2(0.0, 0.39), Vector2(0.13, 0.29), Vector2(0.27, 0.26), Vector2(0.37, 0.13), Vector2(0.34, 0.0)]
	var raw := PackedVector2Array()
	for i in ctrl.size():
		var p := ctrl[i]
		# A ripple runs through the top from back to front as it crawls.
		var ripple := 0.022 * sin(cycle - p.x * dir * 7.0) * (1.0 if crawling else 0.0) * (1.0 - weak)
		var y := (p.y + (ripple if p.y > 0.05 else 0.0)) * sy
		raw.append(Vector2(p.x * dir * sx, -y) * u + Vector2(0, base_y))
	var body := _smooth(raw)
	var centre := Vector2(0, base_y - 0.19 * u * sy)

	# --- contact shadow
	if (side and seat != 0.0) or settle > 0.5:
		_blob(Vector2(0, base_y + 0.012 * u), 0.37 * u * sx, 0.035 * u, Color(0, 0, 0, 0.42))

	# --- the sprout goes behind the body when the moss is seen from behind
	if heading == Heading.UP and not rooted and anim != "root":
		_draw_sprout(Vector2(0.0, base_y - 0.36 * u * sy), 0.0, 1.0, weak)

	# --- leaf tips poking out along the top edge (behind the body)
	var tips: Array[Vector2] = [Vector2(-0.25, 0.25), Vector2(-0.07, 0.38), Vector2(0.13, 0.34), Vector2(0.27, 0.28)]
	if not side:
		tips = [Vector2(-0.22, 0.28), Vector2(-0.06, 0.36), Vector2(0.08, 0.36), Vector2(0.23, 0.28)]
	for i in tips.size():
		var b := Vector2(tips[i].x * dir * sx, -tips[i].y * sy) * u + Vector2(0, base_y)
		var lean := (0.02 * sin(_t * 2.3 + i * 1.7) + (0.012 if i % 2 == 0 else -0.012)) * u
		var leaf := PackedVector2Array([b + Vector2(-0.035 * u, 0.03 * u), b + Vector2(lean, -0.075 * u), b + Vector2(0.035 * u, 0.03 * u)])
		draw_colored_polygon(leaf, _tone(C_LIT if i % 2 == 0 else C_LEAF))
		_edge(leaf, 2.0)

	# --- tone 1: the whole lump in under-shade, with the outline
	draw_colored_polygon(body, _tone(C_UNDER))
	_edge(body)

	# --- tone 2: body colour, leaving a dark band along the bottom and the shaded side
	var mid := PackedVector2Array()
	for p in body:
		mid.append(centre + Vector2((p.x - centre.x) * 0.9, (p.y - centre.y) * 0.84) + Vector2(-0.012, -0.022) * u)
	draw_colored_polygon(mid, _tone(C_BODY))

	# --- tone 3 and 4: lit patches on the upper left of each hump, tufts and highlights
	var humps: Array[Vector3] = []          # x, y (cells, y up), radius
	if side:
		humps = [Vector3(-0.22 * dir, 0.17, 0.12), Vector3(0.0, 0.26, 0.14), Vector3(0.22 * dir, 0.18, 0.11)]
	else:
		humps = [Vector3(-0.2, 0.17, 0.12), Vector3(0.0, 0.25, 0.14), Vector3(0.2, 0.17, 0.12)]
	for i in humps.size():
		var h := humps[i]
		var hc := Vector2(h.x * sx, -h.y * sy) * u + Vector2(0, base_y)
		var r := h.z * u
		_blob(hc + Vector2(-0.22, -0.3) * r, r * 0.78, r * 0.55, _tone(C_LIT), -0.5)
		var tufts: Array[Vector2] = [Vector2(-0.55, -0.35), Vector2(-0.15, -0.62), Vector2(0.2, -0.38), Vector2(-0.3, -0.05)]
		for k in tufts.size():
			draw_circle(hc + tufts[k] * r, r * (0.2 if k % 2 == 0 else 0.16), _tone(C_TUFT))
		draw_circle(hc + Vector2(-0.38, -0.55) * r, r * 0.09, _tone(C_SHINE))
		if i == 1:
			draw_circle(hc + Vector2(0.0, -0.72) * r, r * 0.07, _tone(C_SHINE))
	# A few dark flecks low down, away from the light.
	var flecks: Array[Vector2] = [Vector2(0.12, 0.07), Vector2(0.27, 0.09), Vector2(-0.1, 0.06), Vector2(-0.27, 0.05)]
	for f in flecks:
		draw_circle(Vector2(f.x * dir * sx, -f.y * sy) * u + Vector2(0, base_y), 0.016 * u, _tone(C_UNDER).darkened(0.25))

	# --- strands creeping out along the floor
	if side or settle > 0.5:
		for s: float in [-1.0, 1.0]:
			var a := Vector2(s * 0.35 * sx * u, base_y - 0.01 * u)
			draw_polyline(PackedVector2Array([a, a + Vector2(s * 0.05 * u, 0.012 * u), a + Vector2(s * 0.085 * u, -0.004 * u)]), C_LINE, 4.4, true)
			draw_polyline(PackedVector2Array([a, a + Vector2(s * 0.05 * u, 0.012 * u), a + Vector2(s * 0.085 * u, -0.004 * u)]), _tone(C_LEAF), 2.2, true)

	# --- the sprout, or what it has grown into
	var sprout_root := Vector2(0.11 * dir * sx * u if side else 0.0, base_y - (0.34 if side else 0.33) * u * sy)
	var plant_root := Vector2(0, base_y - 0.19 * u)
	if stage == Stage.BUD:
		if anim == "bloom":
			# The bud squats, splits, and the flower springs out of it.
			if a_bloom < 0.55:
				_draw_bud(plant_root, weak, 1.0 - 0.75 * smoothstep(0.3, 0.55, a_bloom), 0.2 * smoothstep(0.0, 0.3, a_bloom), 0.0)
			if a_bloom > 0.3:
				_draw_flower(plant_root, weak, _elastic((a_bloom - 0.3) / 0.7))
		elif anim == "wither":
			# Starved: it yellows, keels over and shrinks away.
			_draw_bud(plant_root, weak, 1.0 - 0.6 * smoothstep(0.45, 1.0, a_wither), 0.0, 1.0 * smoothstep(0.1, 0.6, a_wither))
		else:
			_draw_bud(plant_root, weak, 1.0, 0.0, 0.0)
	elif stage == Stage.FLOWER:
		if anim == "release":
			# Spent: one swell and a shudder, then the petals shrivel in.
			var swell := smoothstep(0.0, 0.2, a_release) * (1.0 - smoothstep(0.2, 0.35, a_release))
			var shake := 0.012 * u * sin(a_release * 95.0) * (1.0 - smoothstep(0.0, 0.35, a_release))
			_draw_flower(plant_root + Vector2(shake, 0), weak, 1.0 + 0.16 * swell - smoothstep(0.35, 0.85, a_release))
		else:
			_draw_flower(plant_root, weak, 1.0)
	elif anim == "root":
		# Rooting: the sprout straightens and stretches, then swells into the bud.
		var at := sprout_root.lerp(plant_root, settle)
		if a_root < 0.62:
			var lean0 := dir * 0.62 if side else 0.0
			_draw_sprout(at, lerpf(lean0, 0.0, smoothstep(0.0, 0.35, a_root)), lerpf(1.0, 1.7, smoothstep(0.1, 0.55, a_root)), weak)
		if a_root > 0.45:
			_draw_bud(plant_root, weak, _elastic((a_root - 0.45) / 0.55), 0.0, 0.0)
	elif heading == Heading.DOWN:
		# Coming towards the viewer: it simply sways from side to side.
		_draw_sprout(sprout_root, 0.5 * sin(_t * 2.6), 1.0, weak)
	elif side:
		# Leans the way it is going, bobbing with each push.
		_draw_sprout(sprout_root, dir * (0.62 + 0.14 * push + 0.05 * sin(_t * 3.1)), 1.0, weak)


## 0 -> 1 with one soft overshoot.
func _elastic(f: float) -> float:
	f = clampf(f, 0.0, 1.0)
	return 1.0 - pow(1.0 - f, 3.0) + 0.3 * sin(PI * f) * (1.0 - f)


## A short sprout: stubby stem, one small leaf and a pointed green leaf bud. `lean` in radians from
## upright (positive leans right).
func _draw_sprout(root: Vector2, lean: float, grow: float, weak: float) -> void:
	var u := _u * BODY_SCALE
	lean += signf(lean if lean != 0.0 else 1.0) * 0.7 * weak      # a weak sprout hangs over
	var length := 0.11 * u * grow
	var dirv := Vector2(sin(lean), -cos(lean))
	var side := Vector2(dirv.y, -dirv.x)
	var tip := root + dirv * length
	var w := 0.05 * u
	var stem := PackedVector2Array([root - side * w, tip - side * w * 0.7, tip + side * w * 0.7, root + side * w])
	draw_colored_polygon(stem, _tone(C_STEM))
	_edge(stem, 2.0)
	draw_line(root - side * w * 0.2 + dirv * 2.0, tip - side * w * 0.2, _tone(C_STEM_LIT), 2.0, true)
	# One small leaf on the trailing side.
	var lb := root + dirv * length * 0.45
	var out := -side * signf(lean if lean != 0.0 else 1.0)
	var leaf := PackedVector2Array([lb, lb + out * 0.075 * u + dirv * 0.03 * u, lb + out * 0.04 * u - dirv * 0.02 * u])
	draw_colored_polygon(leaf, _tone(C_STEM_LIT))
	_edge(leaf, 1.8)
	# Tip: a closed, pointed leaf bud, green like the rest. Its point shows the lean.
	var r := 0.058 * u * grow
	var base := tip - dirv * r * 0.3
	var bud := PackedVector2Array([base - side * r * 0.55, base - side * r * 0.95 + dirv * r * 0.9,
		base - side * r * 0.5 + dirv * r * 1.9, base + dirv * r * 2.7,
		base + side * r * 0.5 + dirv * r * 1.9, base + side * r * 0.95 + dirv * r * 0.9, base + side * r * 0.55])
	draw_colored_polygon(bud, _tone(C_STEM_LIT))
	# Shaded half and a pale vein, so it reads as a folded leaf and not a ball.
	var lit_side := side if side.x + side.y * 0.5 > 0.0 else -side      # the half away from the light
	draw_colored_polygon(PackedVector2Array([base, base + lit_side * r * 0.95 + dirv * r * 0.9,
		base + lit_side * r * 0.5 + dirv * r * 1.9, base + dirv * r * 2.7]), _tone(C_STEM))
	draw_line(base + dirv * r * 0.3, base + dirv * r * 2.3, _tone(C_SHINE), 1.6, true)
	_edge(bud, 2.0)


## Mirror-symmetric soft shape from one side's control points (x >= 0), bottom to top.
func _leaf_shape(at: Vector2, half: Array[Vector2], lean: float, k: float) -> PackedVector2Array:
	var raw := PackedVector2Array()
	for i in half.size():
		raw.append(Vector2(-half[i].x, -half[i].y))
	for i in range(half.size() - 2, -1, -1):
		raw.append(Vector2(half[i].x, -half[i].y))
	var out := PackedVector2Array()
	for p in _smooth(raw, 5):
		# Lean grows with height, so the shape bends from its base.
		out.append(at + Vector2(p.x + lean * -p.y, p.y) * k)
	return out


func _stem(a: Vector2, b: Vector2, w: float) -> void:
	var mid := (a + b) * 0.5 + Vector2(w * 0.4, 0)
	var pts := PackedVector2Array([a, mid, b])
	draw_polyline(pts, C_LINE, w + LINE_W * 2.0, true)
	draw_polyline(pts, _tone(C_STEM), w, true)
	draw_polyline(PackedVector2Array([a + Vector2(-w * 0.2, 0), mid + Vector2(-w * 0.2, 0), b + Vector2(-w * 0.2, 0)]), _tone(C_STEM_LIT), w * 0.3, true)


## A pointed leaf from `root`, pointing along `dirv`, with a vein.
func _leaf(root: Vector2, dirv: Vector2, length: float, width: float) -> void:
	var side := Vector2(-dirv.y, dirv.x)
	var pts := PackedVector2Array([root, root + dirv * length * 0.45 + side * width, root + dirv * length,
		root + dirv * length * 0.5 - side * width * 0.7])
	draw_colored_polygon(pts, _tone(C_STEM_LIT))
	draw_colored_polygon(PackedVector2Array([root, root + dirv * length, root + dirv * length * 0.5 - side * width * 0.7]), _tone(C_STEM))
	draw_line(root + dirv * length * 0.1, root + dirv * length * 0.9, _tone(C_SHINE), 1.4, true)
	_edge(pts, 2.0)


## The sprout grown into a closed bud: no face, wrapped in two leaves, a sliver of petal
## colour showing at the very tip. `k` scales it from its base, `squash` flattens it,
## `tilt` (radians) keels it over.
func _draw_bud(root: Vector2, weak: float, k: float, squash: float, tilt: float) -> void:
	var u := _u * BODY_SCALE
	var sway := 0.05 * sin(_t * 1.3) + 0.35 * weak
	var breath := 1.0 + 0.02 * sin(_t * 1.8)
	var base := root + Vector2(0, -0.09 * u * minf(k, 1.0))
	_stem(root + Vector2(0, 0.05 * u), base, 0.07 * u)
	for s: float in [-1.0, 1.0]:
		_leaf(root + Vector2(0, -0.02 * u), Vector2(s * 0.85, -0.5).normalized(), 0.17 * u * clampf(k, 0.3, 1.0), 0.05 * u)
	if k <= 0.02:
		return
	draw_set_transform(base, tilt, Vector2(k * (1.0 + 0.7 * squash), k * (1.0 - squash)))
	var o := Vector2.ZERO
	var half: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.12, 0.05), Vector2(0.17, 0.17), Vector2(0.13, 0.31), Vector2(0.04, 0.42), Vector2(0.0, 0.46)]
	var bud := _leaf_shape(o, half, sway, u * breath * 1.15)
	draw_colored_polygon(bud, _tone(C_STEM))
	# Lit left half, then the overlapping outer leaf on the right in the darker tone.
	var lit := PackedVector2Array()
	var n := bud.size()
	for i in n / 2 + 1:
		lit.append(bud[i])
	lit.append(o + Vector2(sway * 0.3 * 0.46 * u, -0.2 * u))
	draw_colored_polygon(lit, _tone(C_STEM_LIT))
	var top := bud[n / 2]
	draw_polyline(PackedVector2Array([o + Vector2(0.03 * u, 0), o + Vector2(0.07 * u + sway * 0.1 * u, -0.2 * u), top]), C_LINE, 2.0, true)
	draw_polyline(PackedVector2Array([o + Vector2(-0.09 * u, -0.1 * u), o + Vector2(-0.1 * u + sway * 0.1 * u, -0.26 * u)]), _tone(C_SHINE), 2.4, true)
	# Petal colour peeking out at the tip.
	var tip := PackedVector2Array([top, top + Vector2(-0.045 * u, 0.075 * u), top + Vector2(0.0, 0.1 * u), top + Vector2(0.045 * u, 0.075 * u)])
	draw_colored_polygon(tip, C_PETAL.lerp(C_WEAK, 0.5 * weak))
	_edge(tip, 1.8)
	_edge(bud)
	draw_set_transform(Vector2.ZERO)


## The open flower: two rings of petals round a plain centre of stamens. No face.
## `open`: 0 closed .. 1 fully open (may overshoot a little).
func _draw_flower(root: Vector2, weak: float, open: float) -> void:
	var u := _u * BODY_SCALE
	var sway := 0.03 * sin(_t * 1.5)
	open = maxf(open, 0.0)
	var head := root + Vector2(sway * u, -(0.13 + 0.15 * minf(open, 1.0)) * u + 0.008 * u * sin(_t * 2.1))
	_stem(root + Vector2(0, 0.05 * u), head + Vector2(0, 0.12 * u), 0.065 * u)
	for s: float in [-1.0, 1.0]:
		_leaf(root + Vector2(0, -0.06 * u), Vector2(s * 0.9, -0.42).normalized(), 0.18 * u, 0.05 * u)
	var petal := C_PETAL.lerp(C_WEAK, 0.5 * weak)
	var petal_dark := C_PETAL_DARK.lerp(C_WEAK.darkened(0.3), 0.5 * weak)
	var petal_lit := C_PETAL_LIT.lerp(C_WEAK, 0.5 * weak)
	for ring in 2:
		for i in 6:
			var a := -PI * 0.5 + TAU * i / 6.0 + (PI / 6.0 if ring == 0 else 0.0)
			var dirv := Vector2(cos(a), sin(a))
			var side := Vector2(-dirv.y, dirv.x)
			var length := (0.25 if ring == 0 else 0.29) * u * (1.0 + 0.03 * sin(_t * 1.7 + i)) * open
			var w := (0.1 if ring == 0 else 0.115) * u * clampf(open, 0.0, 1.1)
			if open < 0.15:
				continue                 # too closed to draw as a petal
			var inner := minf(0.04 * u, length * 0.15)      # petal root; must stay behind its widest part
			var pts := PackedVector2Array([head + dirv * inner, head + dirv * length * 0.45 + side * w, head + dirv * length * 0.85 + side * w * 0.6,
				head + dirv * length, head + dirv * length * 0.85 - side * w * 0.6, head + dirv * length * 0.45 - side * w])
			draw_colored_polygon(pts, petal_dark if ring == 0 else petal)
			if ring == 1:
				# Darker throat near the centre and a light streak towards the tip.
				draw_colored_polygon(PackedVector2Array([head + dirv * inner, head + dirv * length * 0.45 + side * w * 0.5, head + dirv * length * 0.45 - side * w * 0.5]), petal_dark)
				draw_line(head + dirv * length * 0.55 - side * w * 0.25, head + dirv * length * 0.88 - side * w * 0.1, petal_lit, 2.0, true)
			_edge(pts, 2.0)
	var r := 0.092 * u * clampf(open, 0.45, 1.1)
	draw_circle(head, r + 1.6, C_LINE)
	draw_circle(head, r, C_CORE.lerp(C_WEAK, 0.5 * weak))
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		draw_circle(head + Vector2(cos(a), sin(a)) * r * 0.5, r * 0.2, C_CORE_DARK)
	draw_circle(head, r * 0.2, C_CORE_DARK)
	draw_circle(head + Vector2(-0.35, -0.4) * r, r * 0.18, C_SHINE)
