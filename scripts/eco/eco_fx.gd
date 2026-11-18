extends Node2D
## Feedback for the ecology test: nutrient motes flying between soil and slime, short
## rings, and soil chips when a block is dug. Advanced by the scene so it follows the
## simulation speed. Positions are pixels in the world node's space.

const C_MARK := Color("f8e68c")
const C_LINE := Color("17100f")

var _motes: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _chips: Array[Dictionary] = []
var _drifts: Array[Dictionary] = []


func clear() -> void:
	_motes.clear()
	_rings.clear()
	_chips.clear()
	_drifts.clear()
	queue_redraw()


## A point of nutrient travelling from `from` to wherever `target` says it is right now.
func mote(from: Vector2, target: Callable, duration: float, on_arrive: Callable, delay := 0.0) -> void:
	_motes.append({"from": from, "target": target, "dur": duration, "t": -delay, "done": on_arrive,
		"bend": (randf() - 0.5) * 22.0})


func ring(at: Vector2, color: Color, r0: float, r1: float, duration := 0.3) -> void:
	_rings.append({"at": at, "col": color, "r0": r0, "r1": r1, "dur": duration, "t": 0.0})


## Nutrient leaving the loop for the floating pool: pale motes that rise and fade out.
func drift(at: Vector2, count: int) -> void:
	for i in count:
		_drifts.append({"p": at + Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0)), "t": -0.12 * i,
			"phase": randf() * TAU})


func chips(at: Vector2, color: Color, count := 7) -> void:
	for i in count:
		var a := randf() * TAU
		_chips.append({"p": at, "v": Vector2(cos(a), sin(a)) * randf_range(40.0, 110.0), "t": 0.0,
			"r": randf_range(2.0, 4.0), "col": color.lightened(randf() * 0.15)})


func advance(delta: float) -> void:
	if _motes.is_empty() and _rings.is_empty() and _chips.is_empty() and _drifts.is_empty():
		return
	for m in _motes:
		m.t += delta
		if m.t >= m.dur:
			var cb: Callable = m.done
			if cb.is_valid():
				cb.call()
	_motes = _motes.filter(func(m: Dictionary) -> bool: return m.t < m.dur)
	for r in _rings:
		r.t += delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r.t < r.dur)
	for c in _chips:
		c.t += delta
		c.v *= pow(0.02, delta)
		c.p += c.v * delta
	_chips = _chips.filter(func(c: Dictionary) -> bool: return c.t < 0.4)
	for d in _drifts:
		d.t += delta
	_drifts = _drifts.filter(func(d: Dictionary) -> bool: return d.t < 1.2)
	queue_redraw()


func _mote_pos(m: Dictionary, t: float) -> Vector2:
	var target: Callable = m.target
	var to: Vector2 = target.call() if target.is_valid() else m.from
	var f := smoothstep(0.0, 1.0, clampf(t / m.dur, 0.0, 1.0))
	var from: Vector2 = m.from
	var dir := (to - from).normalized()
	return from.lerp(to, f) + Vector2(-dir.y, dir.x) * m.bend * sin(PI * f)


func _draw() -> void:
	for d in _drifts:
		if d.t < 0.0:
			continue
		var f: float = d.t / 1.2
		var p: Vector2 = d.p + Vector2(6.0 * sin(d.phase + f * 7.0), -46.0 * f)
		var a := (1.0 - f) * minf(f * 6.0, 1.0)
		draw_circle(p, 3.6, Color(0.09, 0.06, 0.06, 0.5 * a))
		draw_circle(p, 2.6, Color(0.95, 0.92, 0.78, 0.8 * a))
	for c in _chips:
		draw_circle(c.p, c.r, Color(c.col, 1.0 - c.t / 0.4))
	for r in _rings:
		var f: float = r.t / r.dur
		draw_arc(r.at, lerpf(r.r0, r.r1, f), 0, TAU, 20, Color(r.col, 1.0 - f), 2.2, true)
	for m in _motes:
		if m.t < 0.0:
			continue
		for k in 3:
			var tt: float = m.t - 0.035 * (2 - k)
			if tt < 0.0:
				continue
			var p := _mote_pos(m, tt)
			var r := 2.2 + 1.3 * k
			if k == 2:
				draw_circle(p, r + 1.6, C_LINE)
			draw_circle(p, r, Color(C_MARK, 0.45 + 0.275 * k))
