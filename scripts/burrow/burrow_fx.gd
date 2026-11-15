extends Node2D
## Particle layer for the burrow. burst(kind, pos_in_cells, direction).
## Chunks stop when they reach solid ground instead of flying through walls.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

var grid: RefCounted
var _u := Spec.CELL_PX
var _p: Array[Dictionary] = []


func clear() -> void:
	_p.clear()
	queue_redraw()


func _add(shape: String, pos: Vector2, vel: Vector2, life: float, size: float, col: Color, grav := 0.0, drag := 0.0, spin := 0.0) -> void:
	_p.append({"shape": shape, "pos": pos, "vel": vel, "life": life, "max": life, "size": size,
		"col": col, "grav": grav, "drag": drag, "rot": randf() * TAU, "spin": spin, "seed": randf() * 10.0})


func burst(kind: String, cell_pos: Vector2, dir := Vector2.ZERO) -> void:
	var pos := cell_pos * _u
	match kind:
		"dig":
			for i in 14:
				var col: Color = [Color("7a5a40"), Color("5b4132"), Color("9a7650")][randi() % 3]
				_add("chunk", pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)), Vector2(randf_range(-80, 80), randf_range(-150, -20)),
					randf_range(0.45, 0.85), randf_range(1.8, 4.2), col, 520.0, 0.0, randf_range(-12, 12))
			for i in 6:
				_add("puff", pos + Vector2(randf_range(-18, 18), randf_range(-18, 18)), Vector2(randf_range(-22, 22), randf_range(-22, 6)),
					randf_range(0.4, 0.7), randf_range(6, 10), Color(0.78, 0.66, 0.52, 0.4), 0.0, 3.0)
		"dust":
			for i in 5:
				_add("puff", pos + Vector2(randf_range(-8, 8), randf_range(-4, 4)), Vector2(randf_range(-26, 26), randf_range(-16, 6)),
					randf_range(0.35, 0.6), randf_range(3.5, 6), Color(0.78, 0.68, 0.56, 0.35), 0.0, 3.0)
		"crumbs":
			_add("ring", pos, Vector2.ZERO, 0.2, 5.0, Color("fff0c0"))
			for i in 8:
				_add("dot", pos, dir.normalized() * 45.0 + Vector2(randf_range(-60, 60), randf_range(-70, 40)),
					randf_range(0.3, 0.55), randf_range(1.0, 2.1), Color("ffc866"), 260.0, 2.0)
		"gulp":
			_add("ring", pos, Vector2.ZERO, 0.28, 7.0, Color("ffd890"))
			for i in 3:
				_add("glow", pos + Vector2(randf_range(-5, 5), randf_range(-5, 5)), Vector2(randf_range(-14, 14), randf_range(-26, -8)),
					randf_range(0.5, 0.8), randf_range(1.0, 1.8), Color("ffc070"), -10.0, 2.0)
		"impact":
			_add("star", pos, Vector2.ZERO, 0.16, 12.0, Color("fff6d8"))
			_add("ring", pos, Vector2.ZERO, 0.22, 12.0, Color("fff6d8"))
			for i in 7:
				var a := randf() * TAU
				_add("streak", pos, Vector2(cos(a), sin(a)) * randf_range(90, 170) - dir * 40.0,
					randf_range(0.14, 0.22), randf_range(4, 8), Color("ffe9a8"), 0.0, 5.0)
		"impact_small":
			_add("star", pos, Vector2.ZERO, 0.14, 9.0, Color("ffd8c8"))
			for i in 5:
				var a := randf() * TAU
				_add("streak", pos, Vector2(cos(a), sin(a)) * randf_range(70, 130), randf_range(0.12, 0.2), randf_range(3, 6), Color("ffb8a0"), 0.0, 5.0)
		"chips":
			for i in 7:
				var col: Color = [Color("e9e2c4"), Color("5f9482"), Color("35594f")][randi() % 3]
				_add("chunk", pos, dir * 70.0 + Vector2(randf_range(-60, 60), randf_range(-120, 20)),
					randf_range(0.4, 0.7), randf_range(1.3, 2.8), col, 480.0, 0.0, randf_range(-16, 16))
		"spores", "spores_few":
			for i in (9 if kind == "spores" else 4):
				_add("glow", pos + Vector2(randf_range(-7, 7), randf_range(-6, 6)), Vector2(randf_range(-24, 24), randf_range(-34, -6)),
					randf_range(0.9, 1.6), randf_range(1.1, 2.2), Color("ffb860"), -6.0, 1.6)
		"sparkle":
			for i in 6:
				_add("twinkle", pos + Vector2(randf_range(-14, 14), randf_range(-12, 10)), Vector2(randf_range(-14, 14), randf_range(-34, -12)),
					randf_range(0.5, 0.9), randf_range(2.6, 4.4), Color("fff2a8"), 0.0, 1.0)
		"shell":
			for i in 9:
				var col: Color = [Color("e6dcec"), Color("cdbfd8"), Color("ffcf8a")][randi() % 3]
				_add("chunk", pos + Vector2(randf_range(-8, 8), randf_range(-10, 8)), Vector2(randf_range(-110, 110), randf_range(-150, -30)),
					randf_range(0.7, 1.3), randf_range(2.0, 4.4), col, 520.0, 0.0, randf_range(-14, 14))


func _process(delta: float) -> void:
	if _p.is_empty():
		return
	var i := _p.size() - 1
	while i >= 0:
		var q := _p[i]
		q.life -= delta
		if q.life <= 0.0:
			_p.remove_at(i)
		else:
			var v: Vector2 = q.vel
			v.y += q.grav * delta
			v *= maxf(0.0, 1.0 - q.drag * delta)
			var pos: Vector2 = q.pos + v * delta
			if q.shape == "chunk" and grid != null and not grid.is_open_at(pos / _u):
				# Landed on (or bumped into) solid ground: stay put and fade.
				pos = q.pos
				v = Vector2.ZERO
				q.spin = 0.0
				q.grav = 0.0
			q.vel = v
			q.pos = pos
			q.rot += q.spin * delta
		i -= 1
	queue_redraw()


func _draw() -> void:
	for q in _p:
		var k: float = clampf(q.life / q.max, 0.0, 1.0)
		var pos: Vector2 = q.pos
		var col: Color = q.col
		var size: float = q.size
		match q.shape:
			"chunk":
				var xf := Transform2D(q.rot, pos)
				draw_colored_polygon(xf * PackedVector2Array([Vector2(-size, -size * 0.7), Vector2(size, -size * 0.8),
					Vector2(size * 0.8, size * 0.7), Vector2(-size * 0.7, size * 0.8)]), Color(col, minf(1.0, k * 3.0)))
			"dot":
				draw_circle(pos, size, Color(col, minf(1.0, k * 2.5)))
			"puff":
				draw_circle(pos, size * (1.6 - k * 0.6), Color(col, col.a * k))
			"glow":
				var tw: float = 0.6 + 0.4 * sin(q.seed + q.life * 9.0)
				var a: float = minf(1.0, k * 2.0) * tw
				var p2: Vector2 = pos + Vector2(sin(q.seed + q.life * 3.0) * 3.0, 0)
				draw_circle(p2, size * 2.6, Color(col, 0.16 * a))
				draw_circle(p2, size, Color(col, a))
			"ring":
				draw_arc(pos, size * (1.0 + (1.0 - k) * 1.2), 0.0, TAU, 24, Color(col, k), 2.0, true)
			"streak":
				var v: Vector2 = q.vel
				draw_line(pos, pos - v.normalized() * size * k, Color(col, k), 2.0, true)
			"star", "twinkle":
				var s: float = size * (0.5 + 0.9 * sin(PI * (1.0 - k))) if q.shape == "star" else size * sin(PI * k)
				if s > 0.3:
					var pts := PackedVector2Array()
					for j in 8:
						var a := TAU * j / 8.0 + (PI / 4.0 if q.shape == "star" else 0.0)
						var r := s if j % 2 == 0 else s * 0.28
						pts.append(pos + Vector2(cos(a), sin(a)) * r)
					draw_colored_polygon(pts, Color(col, minf(1.0, k * 2.0 + 0.3)))
