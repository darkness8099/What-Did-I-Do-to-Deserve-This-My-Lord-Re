extends Node2D
## Tiny hand-rolled particle layer. burst(kind, world_pos, direction).

var floor_y := 520.0
var _p: Array[Dictionary] = []


func clear() -> void:
	_p.clear()
	queue_redraw()


func _add(shape: String, pos: Vector2, vel: Vector2, life: float, size: float, col: Color, grav := 0.0, drag := 0.0, spin := 0.0) -> void:
	_p.append({"shape": shape, "pos": pos, "vel": vel, "life": life, "max": life, "size": size,
		"col": col, "grav": grav, "drag": drag, "rot": randf() * TAU, "spin": spin, "seed": randf() * 10.0})


func burst(kind: String, pos: Vector2, dir := Vector2.ZERO) -> void:
	match kind:
		"dirt", "dirt_small":
			var n := 10 if kind == "dirt" else 3
			var pw := 1.0 if kind == "dirt" else 0.55
			for i in n:
				var col: Color = [Color("6b523c"), Color("4a382c"), Color("8a6f52")][randi() % 3]
				_add("chunk", pos + Vector2(randf_range(-12, 12), 0), Vector2(randf_range(-70, 70), randf_range(-190, -80)) * pw,
					randf_range(0.5, 0.9), randf_range(1.6, 3.6), col, 520.0, 0.0, randf_range(-12, 12))
		"dust":
			for i in 5:
				_add("puff", pos + Vector2(randf_range(-10, 10), -2), Vector2(randf_range(-38, 38), randf_range(-16, -4)),
					randf_range(0.35, 0.6), randf_range(4, 7), Color(0.78, 0.68, 0.56, 0.4), 0.0, 3.0)
		"crumbs":
			_add("ring", pos, Vector2.ZERO, 0.2, 5.5, Color("e6fbff"))
			for i in 8:
				_add("dot", pos, (dir.normalized() * 50.0 + Vector2(randf_range(-60, 60), randf_range(-110, -20))),
					randf_range(0.35, 0.65), randf_range(1.0, 2.2), Color("9eeaff"), 420.0)
		"impact":
			_add("star", pos, Vector2.ZERO, 0.16, 15.0, Color("fff6d8"))
			_add("ring", pos, Vector2.ZERO, 0.22, 16.0, Color("fff6d8"))
			for i in 7:
				var a := randf() * TAU
				_add("streak", pos, Vector2(cos(a), sin(a)) * randf_range(120, 220) + dir * 40.0,
					randf_range(0.14, 0.24), randf_range(5, 9), Color("ffe9a8"), 0.0, 5.0)
		"chips":
			for i in 7:
				var col: Color = [Color("c9a060"), Color("e6d3a0"), Color("8a6238")][randi() % 3]
				_add("chunk", pos, dir * 60.0 + Vector2(randf_range(-70, 50), randf_range(-170, -50)),
					randf_range(0.45, 0.8), randf_range(1.4, 3.0), col, 520.0, 0.0, randf_range(-16, 16))
		"spores":
			for i in 9:
				_add("glow", pos + Vector2(randf_range(-12, 12), randf_range(-4, 6)), Vector2(randf_range(-40, 40), randf_range(-70, -20)),
					randf_range(0.7, 1.3), randf_range(1.2, 2.4), Color("ffb070"), -20.0, 2.5)
		"sparkle":
			for i in 6:
				_add("twinkle", pos + Vector2(randf_range(-16, 16), randf_range(-8, 8)), Vector2(randf_range(-18, 18), randf_range(-55, -25)),
					randf_range(0.6, 1.0), randf_range(3.0, 5.0), Color("fff2a8"), 0.0, 1.0)
		"soul":
			for i in 11:
				_add("glow", pos + Vector2(randf_range(-18, 18), randf_range(-6, 6)), Vector2(randf_range(-8, 8), randf_range(-34, -14)),
					randf_range(1.6, 2.6), randf_range(1.2, 2.6), Color("ffc890"), -4.0, 0.6)


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
			if q.shape == "chunk" and pos.y > floor_y - 1.0 and v.y > 0.0:
				pos.y = floor_y - 1.0  # settle on the floor instead of falling through it
				v = Vector2(v.x * 0.3, -v.y * 0.25)
				q.spin *= 0.3
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
				draw_circle(pos + Vector2(sin(q.seed + q.life * 3.0) * 3.0, 0), size * 2.6, Color(col, 0.16 * a))
				draw_circle(pos + Vector2(sin(q.seed + q.life * 3.0) * 3.0, 0), size, Color(col, a))
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
