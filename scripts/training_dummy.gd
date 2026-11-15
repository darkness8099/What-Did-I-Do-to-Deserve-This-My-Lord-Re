extends Node2D
## Scarecrow training target holding a spring-loaded pad on its left side.
## take_hit(): it rocks, the pad compresses, chips fly.
## punch(): the pad fires out on its spring and hits whoever stands in front of it.
## Origin = base of the post on the floor.

enum Punch { REST, WIND, SHOOT, HOLD, RETRACT }

const OUT := Color("1d1512")
const C_WOOD := Color("9a6b3f")
const C_WOOD_D := Color("6e4a2c")
const C_SACK := Color("d9c08a")
const C_SACK_D := Color("b59a66")
const C_ROPE := Color("efe2b8")
const C_RED := Color("d9483b")
const C_WHITE := Color("f6efe0")
const C_SPRING := Color("b8c2c8")
const PAD_REST := Vector2(-17, -27)
const PAD_RX := 7.0
const PAD_RY := 15.0
const MAX_REACH := 80.0

var fx: Node2D
var hit_count := 0

var _rock := 0.0
var _rock_v := 0.0
var _pad := 0.0       # spring offset of the pad, + = pushed toward the post
var _pad_v := 0.0
var _head := 0.0
var _head_v := 0.0
var _flash := 0.0
var _wince := 0.0
var _punch: int = Punch.REST
var _pt := 0.0
var _ext := 0.0       # current punch extension (px to the left)
var _ext_target := 0.0
var _victim: Node2D
var _lethal := false
var _will_connect := false


func reset() -> void:
	hit_count = 0
	_rock = 0.0
	_rock_v = 0.0
	_pad = 0.0
	_pad_v = 0.0
	_head = 0.0
	_head_v = 0.0
	_flash = 0.0
	_wince = 0.0
	_punch = Punch.REST
	_ext = 0.0
	_victim = null
	queue_redraw()


func pad_face_x() -> float:
	return global_position.x + PAD_REST.x - PAD_RX


## True if a strike arriving at world x `tip_x`, travelling in `dir`, lands on the pad.
func is_in_front(tip_x: float, dir: float) -> bool:
	return dir > 0.0 and absf(tip_x - pad_face_x()) <= 10.0


func take_hit(dir: float) -> void:
	hit_count += 1
	_rock_v += 4.2 * dir
	_pad_v += 260.0
	_head_v += 9.0 * dir
	_flash = 1.0
	_wince = 0.45
	if fx != null:
		fx.burst("chips", global_position + Vector2(PAD_REST.x - PAD_RX, PAD_REST.y), Vector2(-dir, -0.6))


func is_punching() -> bool:
	return _punch != Punch.REST


func _victim_front(v: Node2D) -> float:
	return v.global_position.x + (38.0 if v.facing > 0.0 else 26.0)


func can_reach(v: Node2D) -> bool:
	var gap := pad_face_x() - _victim_front(v)
	return gap >= -12.0 and gap <= MAX_REACH


## Fires the pad at `victim`. The hit is applied when the pad actually arrives.
func punch(victim: Node2D, lethal: bool) -> bool:
	if _punch != Punch.REST:
		return false
	_victim = victim
	_lethal = lethal
	_punch = Punch.WIND
	_pt = 0.0
	return true


func _process(delta: float) -> void:
	_rock_v += (-70.0 * _rock - 5.0 * _rock_v) * delta
	_rock += _rock_v * delta
	_pad_v += (-420.0 * _pad - 13.0 * _pad_v) * delta
	_pad += _pad_v * delta
	_head_v += (-110.0 * (_head - _rock * 0.5) - 6.0 * _head_v) * delta
	_head += _head_v * delta
	_flash = maxf(0.0, _flash - delta * 4.0)
	_wince = maxf(0.0, _wince - delta)

	_pt += delta
	match _punch:
		Punch.WIND:
			_ext = -6.0 * smoothstep(0.0, 1.0, _pt / 0.18) + sin(_pt * 80.0) * 0.8
			if _pt >= 0.18:
				_will_connect = is_instance_valid(_victim) and can_reach(_victim)
				_ext_target = clampf(pad_face_x() - _victim_front(_victim) + 3.0, 6.0, MAX_REACH) if _will_connect else MAX_REACH * 0.7
				_punch = Punch.SHOOT
				_pt = 0.0
		Punch.SHOOT:
			var u := clampf(_pt / 0.07, 0.0, 1.0)
			_ext = lerpf(-6.0, _ext_target, u * u)
			if u >= 1.0:
				if _will_connect and is_instance_valid(_victim):
					_victim.take_hit(global_position.x, _lethal)
				_punch = Punch.HOLD
				_pt = 0.0
		Punch.HOLD:
			if _pt >= 0.07:
				_punch = Punch.RETRACT
				_pt = 0.0
		Punch.RETRACT:
			var u := clampf(_pt / 0.3, 0.0, 1.0)
			_ext = _ext_target * (1.0 - smoothstep(0.0, 1.0, u))
			if u >= 1.0:
				_ext = 0.0
				_pad_v += 120.0
				_rock_v += 1.2
				_punch = Punch.REST
	queue_redraw()


func _poly(pts: PackedVector2Array, xf: Transform2D, fill: Color, lw := 1.6) -> void:
	var out := xf * pts
	draw_colored_polygon(out, fill)
	out.append(out[0])
	draw_polyline(out, OUT, lw, true)


func _oval(c: Vector2, rx: float, ry: float, n := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw() -> void:
	# Shadow and footing.
	draw_colored_polygon(_oval(Vector2(-2, 1.5), 24, 3.6), Color(0, 0, 0, 0.28))
	var id := Transform2D.IDENTITY
	_poly(_oval(Vector2(-9, -3), 7, 4.5, 10), id, Color("6b6066"))
	_poly(_oval(Vector2(8, -2.5), 8, 4, 10), id, Color("7a6f74"))

	var xf := Transform2D(_rock * 0.12, Vector2.ZERO)
	# Post and arms.
	_poly(PackedVector2Array([Vector2(-4, 0), Vector2(4, 0), Vector2(3.4, -46), Vector2(-3.4, -46)]), xf, C_WOOD)
	draw_line(xf * Vector2(-1, -4), xf * Vector2(-1, -40), C_WOOD_D, 1.2, true)
	_poly(PackedVector2Array([Vector2(-15, -41), Vector2(16, -43), Vector2(16, -38.5), Vector2(-15, -36.5)]), xf, C_WOOD)
	for y: float in [-33.0, -30.5]:
		draw_line(xf * Vector2(-4.4, y), xf * Vector2(4.4, y + 1.2), C_ROPE, 1.5, true)
	# Rag hanging from the far arm.
	_poly(PackedVector2Array([Vector2(11, -38.5), Vector2(16, -38.5), Vector2(15 + _rock * 2.0, -27), Vector2(12.5 + _rock * 2.0, -30)]), xf, Color("7b4a52"))

	# Sack head with stitched face.
	var hx := xf * Transform2D(_head * 0.14, Vector2(0, -46))
	_poly(_oval(Vector2(0, -8), 9.5, 9), hx, C_SACK)
	_poly(PackedVector2Array([Vector2(-4, -16), Vector2(0, -22), Vector2(4.5, -16.5)]), hx, C_SACK_D)
	draw_line(hx * Vector2(-9, -1.5), hx * Vector2(9, -1.5), C_ROPE, 1.6, true)
	if _wince > 0.0:
		draw_polyline(hx * PackedVector2Array([Vector2(-6.5, -11.5), Vector2(-3.5, -9.5), Vector2(-6.5, -7.5)]), OUT, 1.6, true)
		draw_polyline(hx * PackedVector2Array([Vector2(1.5, -11.5), Vector2(-1.5, -9.5), Vector2(1.5, -7.5)]), OUT, 1.6, true)
	else:
		for ex: float in [-5.0, 0.0]:
			draw_line(hx * Vector2(ex - 1.4, -11), hx * Vector2(ex + 1.4, -8.2), OUT, 1.5, true)
			draw_line(hx * Vector2(ex + 1.4, -11), hx * Vector2(ex - 1.4, -8.2), OUT, 1.5, true)
	draw_line(hx * Vector2(-6, -4.6), hx * Vector2(1, -4.6), OUT, 1.3, true)
	for sx2: float in [-4.5, -2.5, -0.5]:
		draw_line(hx * Vector2(sx2, -5.8), hx * Vector2(sx2, -3.4), OUT, 1.0, true)

	# Spring and pad.
	var pad_c := xf * (PAD_REST + Vector2(_pad - _ext, 0))
	var anchor := xf * Vector2(-3.5, PAD_REST.y)
	var coil := PackedVector2Array([anchor])
	var n := 9
	for i in range(1, n):
		var u := float(i) / n
		coil.append(anchor.lerp(pad_c + Vector2(PAD_RX * 0.6, 0), u) + Vector2(0, (5.0 if i % 2 == 0 else -5.0)))
	coil.append(pad_c + Vector2(PAD_RX * 0.6, 0))
	draw_polyline(coil, OUT, 3.4, true)
	draw_polyline(coil, C_SPRING, 1.6, true)
	var px := Transform2D(_rock * 0.12, pad_c)
	_poly(_oval(Vector2(2.5, 0), PAD_RX, PAD_RY), px, C_WOOD_D)
	_poly(_oval(Vector2.ZERO, PAD_RX, PAD_RY), px, C_WHITE)
	draw_colored_polygon(px * _oval(Vector2.ZERO, PAD_RX * 0.68, PAD_RY * 0.68), C_RED)
	draw_colored_polygon(px * _oval(Vector2.ZERO, PAD_RX * 0.38, PAD_RY * 0.38), C_WHITE)
	draw_colored_polygon(px * _oval(Vector2.ZERO, PAD_RX * 0.16, PAD_RY * 0.16), C_RED)
	if _flash > 0.0:
		draw_colored_polygon(px * _oval(Vector2.ZERO, PAD_RX, PAD_RY), Color(1, 1, 1, _flash * 0.8))
