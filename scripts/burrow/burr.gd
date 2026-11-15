extends Node2D
## Thornpod (棘壳球): a spiny pod tethered in a tunnel. It is the thing to attack, and it
## answers back by shooting its spines out, which is what hurts or kills the grub.
## Node origin = top-left corner of its cell, drawn in pixels.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

enum Phase { REST, WIND, SHOOT, HOLD, RETRACT }

const WIND_TIME := 0.34
const SHOOT_TIME := 0.07
const HOLD_TIME := 0.12
const RETRACT_TIME := 0.38
const SPIKES := 14
const C_LINE := Color("17201f")
const C_POD := Color("5f9482")
const C_POD_DARK := Color("35594f")
const C_POD_LIT := Color("9cc9ae")
const C_SPIKE := Color("e9e2c4")
const C_EYE := Color("ff7a5c")
const C_VINE := Color("4d6b52")

var grid: RefCounted
var fx: Node2D
var cell := Vector2i.ZERO
var size := Vector2i.ONE      ## footprint in cells
var body_radius := 0.27       ## collision radius in cells (spines not included)
var hit_count := 0

var _u := Spec.CELL_PX
var _phase: int = Phase.REST
var _t := 0.0
var _victim: Node2D
var _lethal := false
var _aim := Vector2.LEFT
var _off := Vector2.ZERO
var _off_v := Vector2.ZERO
var _squash := 0.0
var _squash_v := 0.0
var _flash := 0.0
var _wince := 0.0
var _clock := 0.0


func place(c: Vector2i) -> void:
	cell = c
	position = Vector2(c) * _u


func center() -> Vector2:
	return Spec.center(cell, size)


func reset() -> void:
	hit_count = 0
	_phase = Phase.REST
	_victim = null
	_off = Vector2.ZERO
	_off_v = Vector2.ZERO
	_squash = 0.0
	_squash_v = 0.0
	_flash = 0.0
	_wince = 0.0


## Struck from direction `dir` (unit vector pointing from the attacker to the pod).
func take_hit(dir: Vector2) -> void:
	hit_count += 1
	_off_v += dir * 2.6
	_squash_v += 7.0
	_flash = 1.0
	_wince = 0.5
	_aim = -dir
	if fx != null:
		fx.burst("chips", center() - dir * body_radius, -dir)


func can_reach(victim: Node2D) -> bool:
	var d: Vector2i = victim.cell - cell
	return victim.is_alive() and absi(d.x) + absi(d.y) == 1


func is_punching() -> bool:
	return _phase != Phase.REST


## Bristles toward `victim`; the hit is applied when the spines arrive.
func punch(victim: Node2D, lethal: bool) -> void:
	if _phase != Phase.REST:
		return
	_victim = victim
	_lethal = lethal
	_aim = (victim.pos - center()).normalized()
	_phase = Phase.WIND
	_t = 0.0


func _process(delta: float) -> void:
	_clock += delta
	_off_v += (-190.0 * _off - 9.0 * _off_v) * delta
	_off += _off_v * delta
	_squash_v += (-260.0 * _squash - 12.0 * _squash_v) * delta
	_squash += _squash_v * delta
	_flash = maxf(0.0, _flash - delta * 5.0)
	_wince = maxf(0.0, _wince - delta)
	if _phase != Phase.REST:
		_t += delta
		match _phase:
			Phase.WIND:
				if is_instance_valid(_victim):
					_aim = (_victim.pos - center()).normalized()
				if _t >= WIND_TIME:
					_next(Phase.SHOOT)
			Phase.SHOOT:
				if _t >= SHOOT_TIME:
					if is_instance_valid(_victim) and can_reach(_victim):
						_victim.take_hit(_lethal)
					_off_v += _aim * 1.2
					_next(Phase.HOLD)
			Phase.HOLD:
				if _t >= HOLD_TIME:
					_next(Phase.RETRACT)
			Phase.RETRACT:
				if _t >= RETRACT_TIME:
					_next(Phase.REST)
	queue_redraw()


func _next(p: int) -> void:
	_phase = p
	_t = 0.0


## 0..1 how far the aimed spines are out.
func _extend() -> float:
	match _phase:
		Phase.SHOOT: return smoothstep(0.0, 1.0, _t / SHOOT_TIME)
		Phase.HOLD: return 1.0
		Phase.RETRACT: return 1.0 - smoothstep(0.0, 1.0, _t / RETRACT_TIME)
	return 0.0


func _draw() -> void:
	var wind := smoothstep(0.0, 1.0, _t / WIND_TIME) if _phase == Phase.WIND else 0.0
	var ext := _extend()
	var shiver := Vector2(sin(_clock * 71.0), cos(_clock * 63.0)) * 0.012 * wind
	var ctr := (Vector2(0.5, 0.5) + _off + shiver) * _u
	var breathe := 1.0 + 0.025 * sin(_clock * 1.7)
	var r := body_radius * _u * breathe * (1.0 - 0.1 * wind + 0.06 * ext)
	var sq := clampf(_squash, -0.25, 0.25)
	var ax := _aim if _aim.length() > 0.1 else Vector2.LEFT

	# Tethers to the solid walls around it.
	for s in 4:
		var d: Vector2i = Spec.DIRS[s]
		if grid != null and grid.is_open(cell + d):
			continue
		for k: float in [-0.2, 0.22]:
			var wall := Vector2(0.5, 0.5) * _u + Vector2(d) * 0.47 * _u + Vector2(d).orthogonal() * k * _u
			var grip := ctr + Vector2(d) * r * 0.8 + Vector2(d).orthogonal() * k * r
			var pts := PackedVector2Array([wall, wall.lerp(grip, 0.5) + Vector2(0, 3), grip])
			draw_polyline(pts, C_LINE, 3.6, true)
			draw_polyline(pts, C_VINE, 1.8, true)

	draw_circle(ctr + Vector2(2, 3.5), r * 1.05, Color(0, 0, 0, 0.3))

	# Spines: short at rest, pulled in while winding up, shot out toward the victim.
	for i in SPIKES:
		var a := TAU * i / SPIKES + 0.2
		var dir := Vector2.from_angle(a)
		var toward := maxf(0.0, dir.dot(ax))
		var len := (0.075 - 0.045 * wind + ext * (0.05 + 0.36 * pow(toward, 3.0)) + 0.02 * maxf(sq, 0.0)) * _u
		var base := ctr + dir * r * 0.86
		var tip := ctr + dir * (r + len)
		var q := dir.orthogonal() * 2.6
		var tri := PackedVector2Array([base + q, tip, base - q])
		draw_colored_polygon(tri, C_SPIKE.lerp(Color.WHITE, _flash * 0.6))
		draw_polyline(PackedVector2Array([base + q, tip, base - q]), C_LINE, 1.4, true)

	# Pod body, squashed along the direction it was last struck from.
	var body := PackedVector2Array()
	var hi := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var v := Vector2(cos(a), sin(a))
		var along := v.dot(ax)
		var w := v - ax * along
		var p := (ax * along * (1.0 - sq) + w * (1.0 + sq * 0.6))
		body.append(ctr + p * r)
		hi.append(ctr + Vector2(-0.1, -0.13) * r + p * r * 0.8)
	draw_colored_polygon(body, C_POD_DARK.lerp(Color.WHITE, _flash * 0.7))
	draw_colored_polygon(hi, C_POD.lerp(Color.WHITE, _flash * 0.7))
	# Shell ribs.
	for k: float in [-0.45, 0.0, 0.45]:
		var rib := PackedVector2Array()
		for i in 7:
			var t := lerpf(-0.85, 0.85, i / 6.0)
			rib.append(ctr + Vector2(k * r * sqrt(maxf(0.0, 1.0 - t * t)) * 1.0, t * r * 0.92))
		draw_polyline(rib, Color(C_POD_DARK, 0.75), 1.5, true)
	draw_circle(ctr + Vector2(-0.38, -0.42) * r, r * 0.16, Color(C_POD_LIT, 0.8))
	# Dents from the hits it has taken.
	for i in mini(hit_count, 3):
		var a := 2.4 + i * 1.3
		var c := ctr + Vector2.from_angle(a) * r * 0.45
		draw_polyline(PackedVector2Array([c + Vector2(-4, -2), c + Vector2(0, 1), c + Vector2(3, -3), c + Vector2(5, 2)]), C_LINE, 1.3, true)
	body.append(body[0])
	draw_polyline(body, C_LINE, 1.8, true)
	# Eye slit: narrow at rest, wide and hot when it bristles, shut when struck.
	var open := 0.22 + 0.5 * wind + 0.6 * ext
	if _wince > 0.0:
		open = 0.05
	var eye := ctr + ax * r * 0.32
	var eq := ax.orthogonal()
	var slit := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		slit.append(eye + eq * cos(a) * r * 0.3 + ax * sin(a) * r * 0.26 * open)
	draw_colored_polygon(slit, C_LINE)
	if open > 0.12:
		var inner := PackedVector2Array()
		for i in 10:
			var a := TAU * i / 10.0
			inner.append(eye + eq * cos(a) * r * 0.16 + ax * sin(a) * r * 0.2 * open)
		draw_colored_polygon(inner, C_EYE.lerp(Color("ffe0a0"), ext))
