extends Node2D
## Back layers of the dug-out chamber: packed soil, the chamber cavity, and the floor
## strip the actors stand on. Everything is drawn in screen-sized world coordinates.

const W := 1280.0
const H := 720.0

var ground_y := 520.0
var _hole_x := 0.0
var _hole := 0.0


func set_hole(x: float, amount: float) -> void:
	if is_equal_approx(amount, _hole) and is_equal_approx(x, _hole_x):
		return
	_hole_x = x
	_hole = amount
	queue_redraw()


func _blob(c: Vector2, rx: float, ry: float, n := 14, wob := 0.0, rng: RandomNumberGenerator = null) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var k := 1.0 + (rng.randf_range(-wob, wob) if rng != null else 0.0)
		pts.append(c + Vector2(cos(a) * rx * k, sin(a) * ry * k))
	return pts


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115

	# Packed soil.
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([Color("15101b"), Color("15101b"), Color("261b22"), Color("261b22")]))
	for i in 5:
		var y := 40.0 + i * 46.0 + rng.randf_range(-8, 8)
		var line := PackedVector2Array()
		for x in range(0, int(W) + 41, 40):
			line.append(Vector2(x, y + sin(x * 0.011 + i * 1.7) * 9.0 + rng.randf_range(-2, 2)))
		draw_polyline(line, Color(1, 0.85, 0.75, 0.035), 3.0, true)
	for i in 150:
		var c := Vector2(rng.randf_range(0, W), rng.randf_range(0, H))
		var r := rng.randf_range(2.0, 7.0)
		var col := Color("2e2330") if rng.randf() < 0.6 else Color("0f0b14")
		draw_colored_polygon(_blob(c, r * rng.randf_range(1.0, 1.6), r, 8, 0.2, rng), col)

	# Chamber cavity.
	var left := 196.0
	var right := 1094.0
	var top := 236.0
	var roof := PackedVector2Array()
	var cav := PackedVector2Array()
	cav.append(Vector2(left - 6, ground_y))
	cav.append(Vector2(left, ground_y - 90))
	cav.append(Vector2(left + 22, top + 70))
	for x in range(int(left) + 50, int(right) - 30, 30):
		var u := (x - left) / (right - left)
		var arch := -sin(u * PI) * 34.0
		var v := Vector2(x, top + arch + sin(x * 0.045) * 9.0 + rng.randf_range(-5, 5))
		cav.append(v)
		roof.append(v)
	cav.append(Vector2(right - 22, top + 74))
	cav.append(Vector2(right, ground_y - 86))
	cav.append(Vector2(right + 6, ground_y))
	var cols := PackedColorArray()
	for v in cav:
		cols.append(Color("241c2e").lerp(Color("3d2f3d"), clampf((v.y - 200.0) / (ground_y - 200.0), 0.0, 1.0)))
	draw_polygon(cav, cols)

	# Light pooling in the middle of the room.
	for i in 7:
		draw_colored_polygon(_blob(Vector2(640, ground_y - 70), 520.0 - i * 60.0, 190.0 - i * 22.0, 28), Color(1.0, 0.82, 0.62, 0.016))

	# Side tunnels leading away.
	for t: Array in [[262.0, 474.0, 40.0, 36.0], [1040.0, 440.0, 34.0, 30.0]]:
		draw_colored_polygon(_blob(Vector2(t[0], t[1]), t[2], t[3], 16, 0.06, rng), Color("17111d"))
		draw_colored_polygon(_blob(Vector2(t[0], t[1] + 5), t[2] * 0.7, t[3] * 0.7, 14, 0.06, rng), Color("0e0a13"))

	# Dig marks and patches on the back wall.
	for i in 60:
		var c := Vector2(rng.randf_range(left + 60, right - 60), rng.randf_range(top + 40, ground_y - 40))
		var d := Vector2(rng.randf_range(8, 18), rng.randf_range(10, 22))
		draw_line(c, c + d, Color(0, 0, 0, 0.10), 2.0, true)
	for i in 18:
		var c := Vector2(rng.randf_range(left + 40, right - 40), rng.randf_range(top + 30, ground_y - 50))
		draw_colored_polygon(_blob(c, rng.randf_range(14, 34), rng.randf_range(8, 16), 10, 0.2, rng), Color(0, 0, 0, 0.08))

	# Roof teeth and hanging roots.
	for i in range(1, roof.size() - 1, 2):
		var b := roof[i]
		var len := rng.randf_range(10, 34)
		draw_colored_polygon(PackedVector2Array([b + Vector2(-13, -3), b + Vector2(13, -3), b + Vector2(rng.randf_range(-3, 3), len)]), Color("1a1320"))
	for i in 9:
		var b: Vector2 = roof[rng.randi_range(1, roof.size() - 2)]
		var root := PackedVector2Array()
		var n := rng.randi_range(4, 7)
		var sway := rng.randf_range(-1.0, 1.0)
		for j in n:
			root.append(b + Vector2(sin(j * 1.3 + sway) * 5.0 + sway * j * 2.0, j * rng.randf_range(9, 13)))
		draw_polyline(root, Color("4a3628"), 2.2, true)
	draw_polyline(roof, Color("0e0a13"), 4.0, true)

	# Dim glow-moss far back, for depth.
	for i in 11:
		var c := Vector2(rng.randf_range(left + 50, right - 50), rng.randf_range(top + 20, ground_y - 70))
		if absf(c.x - 640.0) < 60.0:
			continue
		draw_circle(c, 13.0, Color(0.35, 0.85, 0.8, 0.035))
		for j in 3:
			draw_circle(c + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4)), rng.randf_range(1.2, 2.2), Color(0.45, 0.85, 0.78, 0.4))

	# Floor strip: the surface the actors stand on.
	var fy := ground_y - 20.0
	draw_polygon(PackedVector2Array([Vector2(left - 20, fy), Vector2(right + 20, fy), Vector2(right + 20, ground_y + 2), Vector2(left - 20, ground_y + 2)]),
		PackedColorArray([Color("3b2d33"), Color("3b2d33"), Color("5d4838"), Color("5d4838")]))
	for i in 46:
		var c := Vector2(rng.randf_range(left, right), rng.randf_range(fy + 4, ground_y - 3))
		draw_colored_polygon(_blob(c, rng.randf_range(2.5, 7), rng.randf_range(1.0, 2.2), 8), Color(0, 0, 0, 0.16) if rng.randf() < 0.6 else Color(1, 0.9, 0.75, 0.10))

	# Burrow the creature climbs out of.
	if _hole > 0.01:
		draw_colored_polygon(_blob(Vector2(_hole_x, ground_y - 4), 27.0 * _hole, 5.5 * _hole, 16), Color("0c080f"))
		draw_colored_polygon(_blob(Vector2(_hole_x, ground_y - 3), 20.0 * _hole, 3.6 * _hole, 14), Color("050307"))
