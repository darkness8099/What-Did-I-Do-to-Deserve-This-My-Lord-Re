extends Node2D
## Vector rig of the Sacgrub, seen from its back as it crawls through a tunnel.
## All geometry is kept in CELL units and multiplied by `u` only inside _draw().
##
## The body is a head plus three segments that sit on the trail the grub has actually
## travelled, so it bends through corners on its own and can never be anywhere it has
## not walked. Feet are planted in the world and only move by stepping.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

const NECK := 0.15                              ## thorax centre -> head centre
const SEG_D: Array[float] = [0.0, 0.17, 0.36]   ## trail distance of thorax, mid, sac (at stretch 1)
const R_HEAD := 0.12
const R_THORAX := 0.15
const R_MID := 0.17
const R_SAC_EMPTY := 0.135
const R_SAC_FULL := 0.2
const MANDIBLE := 0.075
const TIP := 0.34                               ## thorax centre -> closed mandible tips
const LEG_REACH := 0.12                         ## how far a foot sits outside the body
const LEG_BONE := 0.125
const STEP_TRIGGER := 0.1
const STEP_TIME := 0.09

const C_LINE := Color("241a26")
const C_BODY := Color("ece4d2")
const C_BODY_SHADE := Color("b7a89c")
const C_PLATE := Color("8a5a6a")
const C_HEAD := Color("6a3a58")
const C_HEAD_LIT := Color("9a5f84")
const C_JAW := Color("f0c878")
const C_LEG := Color("cdbfae")
const C_EYE := Color("fff0b0")
const C_SAC := Color("c9c0e2")
const C_AMBER := Color("ffb347")
const C_AMBER_CORE := Color("ffe9a8")
const C_DEAD := Color("6f6672")
const C_EGG := Color("e6dcec")

var grid: RefCounted
var u := Spec.CELL_PX

# Geometry of the last update, in cells (world space).
var head := Vector2.ZERO
var head_dir := Vector2.RIGHT
var seg: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var seg_dir: Array[Vector2] = [Vector2.RIGHT, Vector2.RIGHT, Vector2.RIGHT]
var seg_ra: Array[float] = [0.1, 0.1, 0.1]   # radius along the body
var seg_rb: Array[float] = [0.1, 0.1, 0.1]   # radius across the body
var fill_shown := 0.0

var _p: Dictionary = {}
var _feet: Array[Dictionary] = []
var _foot_base: Array[Vector2] = []
var _foot_perp: Array[Vector2] = []
var _foot_r: Array[float] = []
var _prev_mid := Vector2.ZERO
var _ant: Array[float] = [0.0, 0.0]
var _ant_v: Array[float] = [0.0, 0.0]
var _ant2: Array[float] = [0.0, 0.0]
var _ant2_v: Array[float] = [0.0, 0.0]
var _sac_pos := Vector2.ZERO
var _sac_vel := Vector2.ZERO
var _fill_v := 0.0
var _bulge := 0.0
var _bulge_v := 0.0
var _snap := true


func _ready() -> void:
	for i in 6:
		_feet.append({"pos": Vector2.ZERO, "from": Vector2.ZERO, "to": Vector2.ZERO, "t": -1.0})
		_foot_base.append(Vector2.ZERO)
		_foot_perp.append(Vector2.ZERO)
		_foot_r.append(0.1)


## Forget all secondary motion (after a spawn or a reset).
func reset_springs() -> void:
	_snap = true
	_fill_v = 0.0
	_bulge = 0.0
	_bulge_v = 0.0


## Pop the sac (a swallow landing, a hit).
func kick(amount: float) -> void:
	_bulge_v += amount


func update(g: Node2D, p: Dictionary, dt: float) -> void:
	_p = p
	if not p.body:
		queue_redraw()
		return
	var st: float = p.stretch
	var sc: float = p.scale
	var b: Array[Vector2] = []
	var t: Array[Vector2] = []
	for i in 3:
		b.append(g.trail_point(SEG_D[i] * st))
		t.append(g.trail_dir(SEG_D[i] * st))
	# Lunge / recoil travels down the body.
	var shift: float = p.shift
	b[0] += t[0] * shift
	b[1] += t[1] * shift * 0.72
	b[2] += t[2] * shift * 0.42
	var hd := Vector2.from_angle(g.face + p.yaw)
	var neck: float = NECK + p.neck
	var h: Vector2 = b[0] + hd * neck

	# Curl into a C around the middle segment.
	var curl: float = p.curl
	if curl > 0.001:
		var a: float = curl * 1.05 * g.curl_side
		var k := 1.0 - 0.22 * curl
		var v10: Vector2 = (b[0] - b[1]).rotated(a) * k
		var v0h: Vector2 = (h - b[0]).rotated(a * 2.0) * k
		var v12: Vector2 = (b[2] - b[1]).rotated(-a) * k
		b[0] = b[1] + v10
		h = b[0] + v0h
		b[2] = b[1] + v12
		hd = hd.rotated(a * 2.0)
	# Whole-body scale (hatching) and roll (death) about the middle segment.
	var roll: float = p.roll * g.curl_side
	if absf(sc - 1.0) > 0.001 or absf(roll) > 0.001:
		h = b[1] + (h - b[1]).rotated(roll) * sc
		b[0] = b[1] + (b[0] - b[1]).rotated(roll) * sc
		b[2] = b[1] + (b[2] - b[1]).rotated(roll) * sc
		hd = hd.rotated(roll)

	head = h
	head_dir = hd
	seg[0] = b[0]
	seg[1] = b[1]
	seg_dir[0] = _dir(h - b[1], hd)
	seg_dir[1] = _dir(b[0] - b[2], seg_dir[0])
	seg_dir[2] = _dir(b[1] - b[2], seg_dir[1])
	seg_ra[0] = 0.125 * p.s0 * sc
	seg_rb[0] = R_THORAX * (2.0 - p.s0) * sc
	seg_ra[1] = 0.135 * p.s1 * sc
	seg_rb[1] = R_MID * (2.0 - p.s1) * sc

	# Sac: fill and jiggle are sprung.
	if _snap:
		fill_shown = p.fill
		_sac_pos = b[2]
		_sac_vel = Vector2.ZERO
	_fill_v += (150.0 * (p.fill - fill_shown) - 14.0 * _fill_v) * dt
	fill_shown = clampf(fill_shown + _fill_v * dt, 0.0, 1.15)
	_bulge_v += (-260.0 * _bulge - 13.0 * _bulge_v) * dt
	_bulge = clampf(_bulge + _bulge_v * dt, -0.3, 0.4)
	_sac_vel += ((b[2] - _sac_pos) * 420.0 - _sac_vel * 20.0) * dt
	_sac_pos += _sac_vel * dt
	var off := _sac_pos - b[2]
	if off.length() > 0.05:
		_sac_pos = b[2] + off.normalized() * 0.05
	seg[2] = _sac_pos
	var rs: float = lerpf(R_SAC_EMPTY, R_SAC_FULL, clampf(fill_shown, 0.0, 1.0)) * p.sac_r * (1.0 + _bulge) * sc
	seg_ra[2] = rs * 1.06
	seg_rb[2] = rs

	_update_feet(dt, sc)
	_update_antennae(dt)
	_snap = false
	queue_redraw()


func _dir(v: Vector2, fallback: Vector2) -> Vector2:
	return v.normalized() if v.length_squared() > 1e-8 else fallback


# ------------------------------------------------------------------ legs

func _update_feet(dt: float, sc: float) -> void:
	var vel := (seg[1] - _prev_mid) / maxf(dt, 0.0001)
	_prev_mid = seg[1]
	var lead := vel.normalized() * 0.06 if vel.length() > 0.15 and vel.length() < 6.0 else Vector2.ZERO
	var stepping := [false, false]
	for i in 6:
		if _feet[i].t >= 0.0:
			stepping[_group(i)] = true
	for i in 6:
		var pair := i / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var base: Vector2
		var d: Vector2
		var r: float
		match pair:
			0:
				d = seg_dir[0]
				base = seg[0] + d * 0.06 * sc
				r = seg_rb[0] * 0.92
			1:
				d = seg_dir[0]
				base = seg[0] - d * 0.07 * sc
				r = seg_rb[0]
			_:
				d = seg_dir[1]
				base = seg[1] - d * 0.03 * sc
				r = seg_rb[1]
		var perp := d.orthogonal() * side
		var along: float = [0.05, 0.0, -0.05][pair]
		var home: Vector2 = base + perp * (r + LEG_REACH * sc) + d * along * sc
		if grid != null and not grid.is_open_at(home):
			home = base + perp * (r + 0.03)
		_foot_base[i] = base
		_foot_perp[i] = perp
		_foot_r[i] = r
		var f: Dictionary = _feet[i]
		if _snap or f.pos.distance_to(home) > 0.34:
			f.pos = home
			f.t = -1.0
			continue
		if f.t >= 0.0:
			f.t += dt / STEP_TIME
			if f.t >= 1.0:
				f.pos = f.to
				f.t = -1.0
			else:
				f.pos = f.from.lerp(f.to, smoothstep(0.0, 1.0, f.t))
		else:
			var far: float = f.pos.distance_to(home)
			if far > STEP_TRIGGER * 2.0 or (far > STEP_TRIGGER and not stepping[1 - _group(i)]):
				var to := home + lead
				if grid != null and not grid.is_open_at(to):
					to = home
				f.from = f.pos
				f.to = to
				f.t = 0.0
				stepping[_group(i)] = true


func _group(i: int) -> int:
	return (i / 2 + i % 2) % 2


# ------------------------------------------------------------------ antennae

func _update_antennae(dt: float) -> void:
	var base_ang := head_dir.angle()
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var want: float = base_ang + side * (0.55 + _p.ant)
		if _snap:
			_ant[i] = want
			_ant2[i] = want + side * 0.3
			_ant_v[i] = 0.0
			_ant2_v[i] = 0.0
		_ant_v[i] += (angle_difference(_ant[i], want) * 170.0 - _ant_v[i] * 13.0) * dt
		_ant[i] += _ant_v[i] * dt
		var want2: float = _ant[i] + side * 0.3
		_ant2_v[i] += (angle_difference(_ant2[i], want2) * 90.0 - _ant2_v[i] * 8.0) * dt
		_ant2[i] += _ant2_v[i] * dt


# ------------------------------------------------------------------ queries

## Circles (centre, radius) in cells that make up the solid body. Used for wall checks.
func body_circles() -> Array:
	return [[head, R_HEAD * _p.get("scale", 1.0)], [seg[0], seg_rb[0]], [seg[1], seg_rb[1]], [seg[2], seg_rb[2]]]


## Visual bounding box in cells (body, jaws and feet).
func visual_bounds() -> Rect2:
	var r := Rect2(head, Vector2.ZERO).grow(R_HEAD)
	r = r.expand(head + head_dir * (R_HEAD + MANDIBLE))
	for i in 3:
		r = r.merge(Rect2(seg[i], Vector2.ZERO).grow(maxf(seg_ra[i], seg_rb[i])))
	for f in _feet:
		r = r.expand(f.pos)
	return r


# ------------------------------------------------------------------ drawing

func _tint(c: Color) -> Color:
	var life: float = _p.life
	var out := c.lerp(C_DEAD.lerp(c, 0.25), 1.0 - life)
	var fl: float = _p.flash
	if fl > 0.0:
		out = out.lerp(Color(1.0, 0.96, 0.92), fl)
	out.a = c.a
	return out


func _ell(c: Vector2, d: Vector2, ra: float, rb: float, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var q := d.orthogonal()
	for i in n:
		var a := TAU * i / n
		pts.append((c + d * cos(a) * ra + q * sin(a) * rb) * u)
	return pts


func _blob(pts: PackedVector2Array, fill: Color, width := 1.6) -> void:
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, _tint(C_LINE), width, true)


func _draw() -> void:
	if _p.is_empty():
		return
	if _p.egg > 0.06:
		_draw_egg()
	if not _p.body:
		return
	var sc: float = _p.scale

	# Contact shadow on the tunnel's back wall.
	for i in 3:
		draw_colored_polygon(_ell(seg[i] + Vector2(0.03, 0.045), seg_dir[i], seg_ra[i], seg_rb[i], 14), Color(0, 0, 0, 0.28))
	draw_colored_polygon(_ell(head + Vector2(0.03, 0.045), head_dir, R_HEAD * sc, R_HEAD * sc, 12), Color(0, 0, 0, 0.28))

	_draw_legs(sc)

	# Sac (rear): membrane, stored food, shine.
	var sp := seg[2]
	var fill := clampf(fill_shown, 0.0, 1.0)
	var glow: float = _p.glow * _p.life
	if fill > 0.03 and glow > 0.01:
		draw_circle(sp * u, seg_rb[2] * u * 2.1, Color(C_AMBER, 0.05 * fill * glow))
		draw_circle(sp * u, seg_rb[2] * u * 1.5, Color(C_AMBER, 0.10 * fill * glow))
	_blob(_ell(sp, seg_dir[2], seg_ra[2], seg_rb[2]), _tint(C_SAC.lerp(C_AMBER, 0.25 * fill)))
	if fill > 0.03:
		var k := 0.36 + 0.5 * fill
		draw_colored_polygon(_ell(sp, seg_dir[2], seg_ra[2] * k, seg_rb[2] * k, 16), _tint(C_AMBER.lerp(C_BODY_SHADE, 1.0 - glow * 0.9 - 0.1)))
		draw_colored_polygon(_ell(sp + Vector2(-0.012, -0.015), seg_dir[2], seg_ra[2] * k * 0.5, seg_rb[2] * k * 0.5, 12), _tint(C_AMBER_CORE.lerp(C_BODY_SHADE, 1.0 - glow)))
	draw_colored_polygon(_ell(sp + Vector2(-0.3, -0.36) * seg_rb[2], Vector2.from_angle(-0.7), seg_rb[2] * 0.32, seg_rb[2] * 0.16, 10), Color(1, 1, 1, 0.5 * _p.life))

	# Mid and thorax rings.
	for i in [1, 0]:
		var c: Vector2 = seg[i]
		var d: Vector2 = seg_dir[i]
		_blob(_ell(c, d, seg_ra[i], seg_rb[i]), _tint(C_BODY))
		draw_colored_polygon(_ell(c + Vector2(0.018, 0.026), d, seg_ra[i] * 0.82, seg_rb[i] * 0.86, 16), _tint(C_BODY_SHADE))
		draw_colored_polygon(_ell(c + Vector2(-0.012, -0.016), d, seg_ra[i] * 0.8, seg_rb[i] * 0.84, 16), _tint(C_BODY))
		if i == 0:
			# Neck shield.
			draw_colored_polygon(_ell(c + d * seg_ra[0] * 0.25, d, seg_ra[0] * 0.55, seg_rb[0] * 0.7, 14), _tint(C_PLATE))
			draw_colored_polygon(_ell(c + d * seg_ra[0] * 0.3 + Vector2(-0.012, -0.016), d, seg_ra[0] * 0.3, seg_rb[0] * 0.42, 12), _tint(C_HEAD_LIT))
		else:
			var q := d.orthogonal()
			for s: float in [-1.0, 1.0]:
				draw_circle((c + q * s * seg_rb[1] * 0.45 - d * seg_ra[1] * 0.1) * u, 0.022 * u * sc, _tint(C_PLATE))
		draw_colored_polygon(_ell(c + Vector2(-0.3, -0.38) * seg_rb[i], Vector2.from_angle(-0.7), seg_rb[i] * 0.3, seg_rb[i] * 0.13, 10), Color(1, 1, 1, 0.45 * _p.life))

	_draw_head(sc)


func _draw_legs(sc: float) -> void:
	var fold: float = _p.fold
	for i in 6:
		var pair := i / 2
		var base: Vector2 = _foot_base[i]
		var perp: Vector2 = _foot_perp[i]
		var r: float = _foot_r[i]
		var hip := base + perp * r * 0.7
		var f: Dictionary = _feet[i]
		var foot: Vector2 = f.pos
		var ft: float = f.t
		var lift: float = sin(PI * ft) if ft >= 0.0 else 0.0
		if fold > 0.001:
			foot = foot.lerp(base + perp * (r + 0.035), fold)
		var d := foot - hip
		var bone := LEG_BONE * sc
		var dist := minf(d.length(), bone * 1.96)
		if dist < 0.001:
			continue
		var dn := d / d.length()
		foot = hip + dn * dist
		var fwd := -perp.orthogonal() * (-1.0 if i % 2 == 0 else 1.0)
		var bend := sqrt(maxf(0.0, bone * bone - dist * dist * 0.25))
		var kdir := dn.orthogonal()
		if kdir.dot(fwd * (1.0 if pair == 0 else -1.0)) < 0.0:
			kdir = -kdir
		var knee := (hip + foot) * 0.5 + kdir * bend
		var pts := PackedVector2Array([hip * u, knee * u, foot * u])
		draw_polyline(pts, _tint(C_LINE), 4.6 * sc, true)
		draw_polyline(pts, _tint(C_LEG.lerp(Color.WHITE, 0.25 * lift)), 2.4 * sc, true)
		draw_circle(foot * u, (1.9 + 0.9 * lift) * sc, _tint(C_LINE))
		draw_circle(foot * u, (1.0 + 0.6 * lift) * sc, _tint(C_JAW))


func _draw_head(sc: float) -> void:
	var d := head_dir
	var q := d.orthogonal()
	var r := R_HEAD * sc
	# Antennae (behind the head capsule).
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var b := head + d * r * 0.7 + q * side * r * 0.5
		var m := b + Vector2.from_angle(_ant[i]) * 0.085 * sc
		var e := m + Vector2.from_angle(_ant2[i]) * 0.08 * sc
		var pts := PackedVector2Array([b * u, m * u, e * u])
		draw_polyline(pts, _tint(C_LINE), 3.2 * sc, true)
		draw_polyline(pts, _tint(C_BODY_SHADE), 1.4 * sc, true)
		draw_circle(e * u, 2.3 * sc, _tint(C_LINE))
		draw_circle(e * u, 1.4 * sc, _tint(C_JAW))
	# Mandibles: jaw 0 closed (tips meet), 1 wide open.
	var jaw: float = _p.jaw
	for side: float in [-1.0, 1.0]:
		var b := head + d * r * 0.78 + q * side * r * 0.5
		var a1 := d.rotated(side * (0.25 + jaw * 0.75))
		var a2 := d.rotated(side * (-0.75 + jaw * 1.15))
		var m := b + a1 * MANDIBLE * 0.6 * sc
		var e := m + a2 * MANDIBLE * 0.62 * sc
		var pts := PackedVector2Array([b * u, m * u, e * u])
		draw_polyline(pts, _tint(C_LINE), 5.0 * sc, true)
		draw_polyline(pts, _tint(C_JAW), 2.6 * sc, true)
	_blob(_ell(head, d, r * 1.04, r), _tint(C_HEAD))
	draw_colored_polygon(_ell(head + Vector2(-0.012, -0.018), d, r * 0.7, r * 0.66, 14), _tint(C_HEAD_LIT))
	draw_colored_polygon(_ell(head + Vector2(0.004, 0.004), d, r * 0.5, r * 0.46, 14), _tint(C_HEAD))
	# Eyes.
	var eye: int = _p.eye
	var lid: float = _p.lid
	for side: float in [-1.0, 1.0]:
		var e := (head + d * r * 0.3 + q * side * r * 0.66) * u
		if eye == 2:
			draw_circle(e, 2.2 * sc, _tint(C_LINE))
			draw_circle(e, 1.2 * sc, Color("8d8590"))
		elif eye == 1 or lid > 0.6:
			draw_line(e - q * 2.4 * sc, e + q * 2.4 * sc, _tint(C_LINE), 2.6, true)
			draw_line(e - q * 2.0 * sc, e + q * 2.0 * sc, _tint(C_EYE), 1.0, true)
		else:
			draw_circle(e, 3.1 * sc, _tint(C_LINE))
			draw_circle(e, 2.2 * sc, _tint(C_EYE))
			draw_circle(e + d * 0.7 * sc, 1.1 * sc, _tint(C_LINE))


func _draw_egg() -> void:
	var s: float = _p.egg
	var c: Vector2 = _p.egg_pos
	var rot: float = _p.egg_rot
	var up := Vector2.from_angle(rot - PI / 2.0)
	var ctr := c
	# The egg is glued to the tunnel's back wall: sticky threads and a contact shadow.
	for th: Array in [[-0.36, -0.2, -0.9], [0.34, -0.26, 0.8], [-0.3, 0.3, -2.2], [0.33, 0.27, 2.3]]:
		var far := c + Vector2(th[0], th[1]) * s
		var near := ctr + Vector2.from_angle(th[2]).rotated(rot) * Vector2(0.17, 0.2) * s
		draw_line(far * u, near * u, Color(C_EGG, 0.45), 1.3, true)
		draw_circle(far * u, 1.8, Color(C_EGG, 0.5))
	draw_colored_polygon(_ell(ctr + Vector2(0.03, 0.045), up, 0.25 * s, 0.19 * s, 16), Color(0, 0, 0, 0.3))
	var shell := _ell(ctr, up, 0.25 * s, 0.19 * s, 22)
	draw_colored_polygon(shell, C_EGG)
	draw_colored_polygon(_ell(ctr + Vector2(0.02, 0.03) * s, up, 0.2 * s, 0.15 * s, 18), C_EGG.darkened(0.14))
	draw_colored_polygon(_ell(ctr + Vector2(-0.015, -0.02) * s, up, 0.2 * s, 0.15 * s, 18), C_EGG)
	var q := up.orthogonal()
	for sp: Array in [[0.1, 0.07, 0.03], [-0.06, -0.08, 0.035], [-0.12, 0.04, 0.022], [0.02, -0.02, 0.02]]:
		draw_circle((ctr + up * sp[0] * s + q * sp[1] * s) * u, sp[2] * s * u, Color(C_AMBER, 0.55))
	draw_colored_polygon(_ell(ctr + up * 0.1 * s - q * 0.07 * s, up.rotated(0.5), 0.06 * s, 0.03 * s, 10), Color(1, 1, 1, 0.55))
	shell.append(shell[0])
	draw_polyline(shell, C_LINE, 1.8, true)
	var crack: float = _p.egg_crack
	if crack > 0.01:
		var zig: Array[Vector2] = [Vector2(0.2, -0.02), Vector2(0.11, 0.05), Vector2(0.06, -0.04), Vector2(-0.01, 0.06), Vector2(-0.06, -0.03), Vector2(-0.13, 0.04)]
		var pts := PackedVector2Array()
		var n := int(ceil(crack * (zig.size() - 1)))
		for i in n + 1:
			pts.append((ctr + up * zig[i].x * s + q * zig[i].y * s) * u)
		if pts.size() >= 2:
			draw_polyline(pts, C_LINE, 1.6, true)
		if crack > 0.6:
			draw_polyline(PackedVector2Array([(ctr + up * 0.06 * s - q * 0.04 * s) * u, (ctr + up * 0.02 * s - q * 0.13 * s) * u]), C_LINE, 1.4, true)
			draw_circle((ctr + up * 0.08 * s) * u, 0.05 * u * (crack - 0.6) * 2.5, Color(C_AMBER, 0.25))
