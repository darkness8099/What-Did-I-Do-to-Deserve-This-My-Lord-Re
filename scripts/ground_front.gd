extends Node2D
## Front soil face below the walking line. Drawn over the actors so anything below
## ground level (a creature still in its burrow) is hidden, plus the burrow mound.

const W := 1280.0
const H := 720.0

var ground_y := 520.0
var _mound_x := 0.0
var _mound := 0.0


func set_mound(x: float, height: float) -> void:
	if is_equal_approx(height, _mound) and is_equal_approx(x, _mound_x):
		return
	_mound_x = x
	_mound = height
	queue_redraw()


func _blob(c: Vector2, rx: float, ry: float, n: int, wob: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var k := 1.0 + rng.randf_range(-wob, wob)
		pts.append(c + Vector2(cos(a) * rx * k, sin(a) * ry * k))
	return pts


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77012
	var gy := ground_y + 2.5  # the lip sits just under the feet line

	draw_polygon(PackedVector2Array([Vector2(-40, gy), Vector2(W + 40, gy), Vector2(W + 40, H + 40), Vector2(-40, H + 40)]),
		PackedColorArray([Color("503c2e"), Color("503c2e"), Color("1a1216"), Color("1a1216")]))

	# Strata and buried stones.
	for i in 3:
		var y := gy + 46.0 + i * 52.0
		var line := PackedVector2Array()
		for x in range(-40, int(W) + 81, 40):
			line.append(Vector2(x, y + sin(x * 0.013 + i * 2.1) * 8.0))
		draw_polyline(line, Color(0, 0, 0, 0.16), 5.0, true)
	for i in 34:
		var c := Vector2(rng.randf_range(0, W), rng.randf_range(gy + 16, H - 10))
		var r := rng.randf_range(4, 13)
		var depth := clampf((c.y - gy) / 200.0, 0.0, 1.0)
		var pts := _blob(c, r * rng.randf_range(1.1, 1.7), r, 9, 0.15, rng)
		draw_colored_polygon(pts, Color("6f5a4c").lerp(Color("2a2024"), depth))
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.35), 1.5, true)
	for i in 8:
		var b := Vector2(rng.randf_range(40, W - 40), gy + rng.randf_range(4, 30))
		var root := PackedVector2Array()
		for j in rng.randi_range(4, 7):
			root.append(b + Vector2(j * rng.randf_range(8, 14) * (1.0 if i % 2 == 0 else -1.0), j * j * 1.4 + sin(j * 1.9) * 3.0))
		draw_polyline(root, Color("3a2a22"), 2.4, true)

	# Lip of the floor.
	var lip := PackedVector2Array()
	for x in range(-40, int(W) + 61, 20):
		lip.append(Vector2(x, gy + sin(x * 0.05) * 0.8))
	draw_polyline(lip, Color("231a1c"), 5.0, true)
	draw_polyline(lip, Color("7a6048"), 2.0, true)
	for i in 26:
		var x := rng.randf_range(20, W - 20)
		draw_colored_polygon(_blob(Vector2(x, gy + rng.randf_range(3, 9)), rng.randf_range(2, 4.5), rng.randf_range(1.2, 2.2), 7, 0.1, rng), Color("231a1c"))

	# Burrow mound.
	if _mound > 0.05:
		var m := PackedVector2Array()
		var top := PackedVector2Array()
		for i in 21:
			var dx := -34.0 + i * 3.4
			var bump := _mound * exp(-pow(dx / 15.0, 2.0)) * (1.0 + 0.12 * sin(dx * 0.9))
			var v := Vector2(_mound_x + dx, gy - bump + 0.5)
			m.append(v)
			top.append(v)
		m.append(Vector2(_mound_x + 34, gy + 4))
		m.append(Vector2(_mound_x - 34, gy + 4))
		draw_colored_polygon(m, Color("5e4937"))
		draw_polyline(top, Color("231a1c"), 3.6, true)
		draw_polyline(top, Color("8a6f52"), 1.6, true)
		for k in 5:
			var dx := -18.0 + k * 9.0
			var bh := _mound * exp(-pow(dx / 15.0, 2.0))
			if bh > 2.0:
				draw_circle(Vector2(_mound_x + dx, gy - bh * 0.45), 1.3, Color("3a2c24"))

	# Foreground rocks in the corners, for depth.
	for c: Array in [[214.0, 668.0, 70.0, 62.0], [1080.0, 672.0, 76.0, 66.0], [196.0, 585.0, 26.0, 40.0], [1096.0, 590.0, 26.0, 42.0]]:
		draw_colored_polygon(_blob(Vector2(c[0], c[1]), c[2], c[3], 12, 0.08, rng), Color("0d0910"))
