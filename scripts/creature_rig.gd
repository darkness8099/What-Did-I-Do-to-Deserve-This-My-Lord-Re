extends Node2D
## Vector cut-out rig for the Sporeback ("菇背拱兽"). Draws one CreaturePose per frame.
## Origin = ground contact point under the body, facing +x. Flip with scale.x.

const Pose := preload("res://scripts/creature_pose.gd")

const OUT := Color("1b2418")
const C_BODY := Color("8fc65a")
const C_BODY_D := Color("5d9742")
const C_BELLY := Color("ece6b4")
const C_JAW := Color("b9dc7c")
const C_LEG_FAR := Color("4f8039")
const C_LEG_NEAR := Color("79b04e")
const C_PLATE := Color("e3b866")
const C_PLATE_D := Color("a9793a")
const C_MOUTH := Color("6e1c33")
const C_TONGUE := Color("ea6f86")
const C_EYE := Color("fdfcf0")
const C_STALK := Color("f1e8cc")
const C_CAP := Color("ff7a4a")
const C_CAP_DULL := Color("a8503a")
const C_SPOT := Color("ffe7b0")
const C_GLOW := Color("ffb070")

const BODY_C := Vector2(0, -19)
const BODY_RX := 22.0
const BODY_RY := 14.0
const HEAD_ANCHOR := Vector2(19, -6)
const HIP_F := Vector2(11, 8)
const HIP_B := Vector2(-11, 8)
const FOOT_NX: Array[float] = [14.0, -9.0, 12.0, -12.0]
const LEG_L := 7.0
const LW := 1.6

const SHROOM_ANCHOR: Array[Vector2] = [Vector2(-2, -13.6), Vector2(-11, -11.5), Vector2(7, -12.2)]
const SHROOM_H: Array[float] = [12.0, 8.0, 6.5]
const SHROOM_R: Array[float] = [7.0, 5.5, 4.8]
const SHROOM_TILT: Array[float] = [-0.05, -0.38, 0.32]
const SHROOM_DROOP: Array[float] = [-1.25, -1.45, 1.35]

var pose: RefCounted = Pose.new()

var _sh_a: Array[float] = [0.0, 0.0, 0.0]
var _sh_v: Array[float] = [0.0, 0.0, 0.0]
var _ear_a := 0.0
var _ear_v := 0.0
var _tail_a := 0.0
var _tail_v := 0.0
var _prev_x := 0.0
var _has_prev := false
var _lean := 0.0


func reset_springs() -> void:
	for i in 3:
		_sh_a[i] = 0.0
		_sh_v[i] = 0.0
	_ear_a = 0.0
	_ear_v = 0.0
	_tail_a = 0.0
	_tail_v = 0.0
	_has_prev = false
	_lean = 0.0


## Angular impulse on the floppy bits (mushrooms, ears, tail). + = thrown forward.
func kick(amount: float) -> void:
	for i in 3:
		_sh_v[i] += amount * (1.0 + 0.25 * i)
	_ear_v += amount * 1.3
	_tail_v -= amount * 0.8


func show_pose(p: RefCounted, dt: float) -> void:
	pose = p
	if dt > 0.0:
		# Secondary motion: floppy parts lag behind the body's horizontal movement.
		var facing := signf(scale.x) if scale.x != 0.0 else 1.0
		var wx: float = get_parent().global_position.x + facing * p.body_x
		var vx := 0.0
		if _has_prev:
			vx = clampf((wx - _prev_x) / dt * facing, -400.0, 400.0)
		_prev_x = wx
		_has_prev = true
		_lean = lerpf(_lean, clampf(-vx * 0.0035, -0.5, 0.5), 1.0 - exp(-14.0 * dt))
		var sub := 2
		var h := dt / sub
		for _s in sub:
			for i in 3:
				var k := 150.0 - 22.0 * i
				_sh_v[i] += (-k * (_sh_a[i] - _lean) - 7.5 * _sh_v[i]) * h
				_sh_a[i] = clampf(_sh_a[i] + _sh_v[i] * h, -1.2, 1.2)
			_ear_v += (-190.0 * (_ear_a - _lean * 1.4) - 9.0 * _ear_v) * h
			_ear_a = clampf(_ear_a + _ear_v * h, -1.3, 1.3)
			_tail_v += (-120.0 * (_tail_a + _lean * 0.8) - 8.0 * _tail_v) * h
			_tail_a = clampf(_tail_a + _tail_v * h, -1.0, 1.0)
	queue_redraw()


# --------------------------------------------------------------------------- helpers

func _tint(c: Color) -> Color:
	var o := c
	if pose.life < 1.0:
		var g := c.get_luminance()
		var dead := Color(g * 0.80 + 0.06, g * 0.76 + 0.05, g * 0.70 + 0.05)
		o = o.lerp(dead, (1.0 - pose.life) * 0.82)
	if pose.flash > 0.0:
		o = o.lerp(Color(1.0, 0.96, 0.9), pose.flash * 0.85)
	o.a = c.a
	return o


func _poly(pts: PackedVector2Array, xf: Transform2D, fill: Color, line := true) -> void:
	var out := xf * pts
	draw_colored_polygon(out, _tint(fill))
	if line:
		out.append(out[0])
		draw_polyline(out, _tint(OUT), LW, true)


static func _ellipse(c: Vector2, rx: float, ry: float, n := 20, a0 := 0.0, a1 := TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var closed := is_equal_approx(a1 - a0, TAU)
	var steps := n if closed else n + 1
	for i in steps:
		var a := a0 + (a1 - a0) * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _knee(hip: Vector2, foot: Vector2, bend: float) -> Vector2:
	var d := foot - hip
	var raw := d.length()
	if raw < 0.01:
		return hip + Vector2(bend * LEG_L, 0)
	var dist := minf(raw, LEG_L * 2.0 - 0.01)
	var dir := d / raw
	var h := sqrt(maxf(LEG_L * LEG_L - dist * dist * 0.25, 0.0))
	return hip + dir * (dist * 0.5) + Vector2(-dir.y, dir.x) * h * bend


func _leg(hip: Vector2, foot: Vector2, bend: float, col: Color) -> void:
	var knee := _knee(hip, foot, bend)
	var pts := PackedVector2Array([hip, knee, foot])
	var oc := _tint(OUT)
	var fc := _tint(col)
	draw_polyline(pts, oc, 6.4, true)
	for q in pts:
		draw_circle(q, 3.2, oc)
	# paw
	var paw := _ellipse(foot + Vector2(1.6, -1.3), 4.3, 2.5, 12)
	draw_colored_polygon(paw, oc)
	draw_polyline(pts, fc, 3.4, true)
	for q in pts:
		draw_circle(q, 1.7, fc)
	draw_colored_polygon(_ellipse(foot + Vector2(1.6, -1.3), 3.0, 1.4, 12), fc)


# --------------------------------------------------------------------------- draw

func _draw() -> void:
	var p := pose
	var lift: float = p.lift
	var sx: float = p.sx
	var sy: float = p.sy

	# Body frame. Squash keeps the belly line where it was.
	var bc := BODY_C + Vector2(p.body_x, p.body_y - lift + (1.0 - sy) * BODY_RY)
	var body := Transform2D(p.body_rot, Vector2(sx, sy), 0.0, bc)
	var body_rig := Transform2D(p.body_rot, bc)  # rotation only, for attached parts

	# Contact shadow (only while above ground).
	if lift > -12.0:
		var k := clampf(1.0 - lift * 0.04, 0.5, 1.0) * clampf(1.0 + lift / 12.0, 0.0, 1.0)
		draw_colored_polygon(_ellipse(Vector2(p.body_x * 0.6 + 2, 1.5), 25.0 * k, 3.6 * k, 18), Color(0, 0, 0, 0.28 * k))

	var feet: Array[Vector2] = []
	for i in 4:
		var f: Vector2 = p.feet[i]
		var far := i < 2
		feet.append(Vector2(FOOT_NX[i] + f.x, -lift - f.y + (-1.6 if far else 0.0)))
	var hip_f := body * HIP_F
	var hip_b := body * HIP_B

	# Far legs.
	_leg(hip_f + Vector2(2.5, -1), feet[0], -1.0, C_LEG_FAR)
	_leg(hip_b + Vector2(2.5, -1), feet[1], 1.0, C_LEG_FAR)

	# Tail.
	var tail_xf := Transform2D(p.body_rot + p.tail + _tail_a, body * Vector2(-19, -3))
	_poly(PackedVector2Array([Vector2(2, -4.5), Vector2(-6, -7.5), Vector2(-13, -12.5), Vector2(-16.5, -12),
		Vector2(-11, -4), Vector2(-2, 4), Vector2(2, 3)]), tail_xf, C_BODY_D)

	# Back mushrooms (rooted in the back, drawn before the body).
	var glow: float = clampf(p.glow, 0.0, 2.0) * p.life
	for i in 3:
		var ang: float = p.body_rot + SHROOM_TILT[i] + _sh_a[i] + p.shroom * SHROOM_DROOP[i]
		var h: float = SHROOM_H[i] * (1.0 - 0.3 * p.shroom)
		var r: float = SHROOM_R[i]
		var xf := Transform2D(ang, body * SHROOM_ANCHOR[i])
		var cap_c := xf * Vector2(0, -h - r * 0.3)
		if glow > 0.02:
			draw_circle(cap_c, r * 2.6, Color(C_GLOW, 0.07 * glow))
			draw_circle(cap_c, r * 1.7, Color(C_GLOW, 0.10 * glow))
		_poly(PackedVector2Array([Vector2(-1.7, 1), Vector2(1.7, 1), Vector2(1.3, -h), Vector2(-1.3, -h)]), xf, C_STALK)
		var cap := _ellipse(Vector2(0, -h), r, r * 0.82, 12, PI, TAU)
		cap.append(Vector2(r * 0.55, -h + 1.3))
		cap.append(Vector2(-r * 0.55, -h + 1.3))
		var col := C_CAP_DULL.lerp(C_CAP, clampf(glow, 0.0, 1.0))
		col = col.lerp(Color(1.0, 0.93, 0.75), clampf(glow - 1.0, 0.0, 1.0) * 0.55)
		_poly(cap, xf, col)
		var spot := _tint(C_SPOT)
		draw_circle(xf * Vector2(-r * 0.4, -h - r * 0.42), r * 0.17, spot)
		draw_circle(xf * Vector2(r * 0.3, -h - r * 0.3), r * 0.13, spot)

	# Head frame.
	var head_rot: float = p.body_rot + p.head_rot
	var head := Transform2D(head_rot, body * HEAD_ANCHOR + Vector2(p.head_x, p.head_y))

	# Far ear (behind head and body).
	var ear_ang: float = p.ear * 0.6 + _ear_a - 0.3
	var ear_pts := PackedVector2Array([Vector2(-2, 0.5), Vector2(-4.5, -5), Vector2(-3, -11), Vector2(0.5, -8),
		Vector2(2.5, -2), Vector2(2, 0.5)])
	_poly(ear_pts, Transform2D(head_rot + ear_ang + 0.22, head * Vector2(-2, -11)), C_LEG_FAR)

	# Body.
	_poly(_ellipse(Vector2.ZERO, BODY_RX, BODY_RY, 26), body, C_BODY)
	_poly(_ellipse(Vector2(2, 5.6), 15, 7, 18), body, C_BELLY, false)
	_poly(_ellipse(Vector2(-9, -5.5), 3.3, 2.4, 10), body, C_BODY_D, false)
	_poly(_ellipse(Vector2(-15, -0.5), 2.3, 1.9, 10), body, C_BODY_D, false)
	_poly(_ellipse(Vector2(1, -8.5), 2.4, 1.8, 10), body, C_BODY_D, false)

	# Near legs.
	_leg(hip_f, feet[2], -1.0, C_LEG_NEAR)
	_leg(hip_b, feet[3], 1.0, C_LEG_NEAR)

	# Jaw + mouth.
	var jaw: float = clampf(p.jaw, 0.0, 1.2)
	var jaw_pivot := Vector2(-4, 4.5)
	var jaw_xf := head * Transform2D(jaw * 0.78, jaw_pivot) * Transform2D(0.0, -jaw_pivot)
	if jaw > 0.06:
		var inside := PackedVector2Array([head * jaw_pivot, head * Vector2(15, 5.2),
			jaw_xf * Vector2(14.5, 4.8), jaw_xf * Vector2(4, 4.8)])
		draw_colored_polygon(inside, _tint(C_MOUTH))
		if jaw > 0.3:
			_poly(_ellipse(Vector2(7.5, 4.0), 4.6, 1.7, 10), jaw_xf, C_TONGUE, false)
		draw_colored_polygon(jaw_xf * PackedVector2Array([Vector2(10, 4.8), Vector2(11.1, 2.3), Vector2(12.2, 4.8)]), _tint(C_EYE))
	_poly(PackedVector2Array([Vector2(-5, 3.5), Vector2(4, 4.6), Vector2(14, 4.6), Vector2(15.5, 6.6),
		Vector2(11, 9.6), Vector2(2, 10.8), Vector2(-5, 9.5)]), jaw_xf, C_JAW)

	# Upper head.
	var skull := _ellipse(Vector2(0, -1), 12.5, 12.5, 16, deg_to_rad(150), deg_to_rad(350))
	skull.append_array(PackedVector2Array([Vector2(16.5, 0.2), Vector2(19, 3.6), Vector2(14.5, 5.4),
		Vector2(4, 6.2), Vector2(-6, 6.4)]))
	_poly(skull, head, C_BODY)
	if jaw > 0.15:
		draw_colored_polygon(head * PackedVector2Array([Vector2(11.6, 5.3), Vector2(12.8, 7.9), Vector2(14.0, 5.3)]), _tint(C_EYE))

	# Digging plate on the snout: this is what it rams with.
	_poly(PackedVector2Array([Vector2(8.5, -5.5), Vector2(13.5, -3.6), Vector2(17.2, 0), Vector2(19.4, 3.6),
		Vector2(14.5, 5.6), Vector2(9.5, 5.4), Vector2(11, 1), Vector2(9.5, -2)]), head, C_PLATE)
	draw_polyline(head * PackedVector2Array([Vector2(11.2, -3.2), Vector2(14.6, -0.4), Vector2(16.4, 2.6)]), _tint(C_PLATE_D), 1.1, true)

	# Eye.
	var eo := _tint(OUT)
	var ec := Vector2(2.6, -3.4)
	match int(p.eye):
		1:
			draw_polyline(head * PackedVector2Array([ec + Vector2(-2.6, -3.2), ec + Vector2(2.8, 0), ec + Vector2(-2.6, 3.2)]), eo, 2.0, true)
		2:
			draw_line(head * (ec + Vector2(-2.8, -2.8)), head * (ec + Vector2(2.8, 2.8)), eo, 2.0, true)
			draw_line(head * (ec + Vector2(2.8, -2.8)), head * (ec + Vector2(-2.8, 2.8)), eo, 2.0, true)
		3:
			draw_polyline(head * PackedVector2Array([ec + Vector2(-3.4, 1.6), ec + Vector2(-1.8, -1.6), ec + Vector2(0, -2.6),
				ec + Vector2(1.8, -1.6), ec + Vector2(3.4, 1.6)]), eo, 2.0, true)
		_:
			var open: float = 1.0 - clampf(p.lid, 0.0, 1.0)
			if open < 0.14:
				draw_line(head * (ec + Vector2(-4, 0.6)), head * (ec + Vector2(4, 0.6)), eo, 1.8, true)
			else:
				_poly(_ellipse(ec, 4.5, 4.7 * open, 16), head, C_EYE)
				var lk := Vector2(clampf(p.look_x, -1, 1) * 1.5 + 0.5, clampf(p.look_y, -1, 1) * 1.1 * open)
				draw_colored_polygon(head * _ellipse(ec + lk, 2.4, minf(2.6, 4.2 * open), 12), eo)
				if open > 0.5:
					draw_circle(head * (ec + lk + Vector2(-0.9, -1.0)), 0.8, _tint(C_EYE))
	if p.brow > 0.05:
		var b: float = clampf(p.brow, 0.0, 1.0)
		draw_line(head * (ec + Vector2(-5, -5.2 - b * 0.6)), head * (ec + Vector2(5.2, -5.4 + b * 4.2)), Color(eo, b), 2.4, true)

	# Near ear.
	_poly(ear_pts, Transform2D(head_rot + ear_ang, head * Vector2(-6, -10.5)), C_BODY_D)
