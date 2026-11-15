extends Node2D
## Glow-berry sprout: three berries, one bite each. Origin = where the stem meets the floor.

const OUT := Color("10303a")
const C_BERRY := Color("7fe3ff")
const C_BERRY_HI := Color("e6fbff")
const C_STEM := Color("4f9a78")
const C_LEAF := Color("3f8a6a")
const BERRY_POS: Array[Vector2] = [Vector2(-6, -6), Vector2(5.5, -5.5), Vector2(0, -12.5)]
const BERRY_R: Array[float] = [5.2, 5.6, 4.8]

var bites_left := 3
var _alive: Array[bool] = [true, true, true]
var _scale: Array[float] = [1.0, 1.0, 1.0]
var _vel: Array[float] = [0.0, 0.0, 0.0]
var _sway := 0.0
var _sway_v := 0.0
var _clock := 0.0


func restock(instant := false) -> void:
	bites_left = 3
	for i in 3:
		_alive[i] = true
		if instant:
			_scale[i] = 1.0
			_vel[i] = 0.0
	if instant:
		_sway = 0.0
		_sway_v = 0.0
	queue_redraw()


func _next_index(eater_x: float) -> int:
	# Lower berries first, nearest side first; the top one goes last.
	var best := -1
	var best_d := 1e9
	for i in 2:
		if _alive[i]:
			var d := absf(global_position.x + BERRY_POS[i].x - eater_x)
			if d < best_d:
				best_d = d
				best = i
	if best == -1 and _alive[2]:
		best = 2
	return best


## Offset (relative to this node) of the berry that would be bitten next.
func next_bite_offset(eater_x: float) -> Vector2:
	var i := _next_index(eater_x)
	return BERRY_POS[i] if i >= 0 else Vector2(0, -6)


## Removes one berry and returns its global position.
func take_bite(eater_x: float) -> Vector2:
	var i := _next_index(eater_x)
	if i < 0:
		return global_position
	_alive[i] = false
	_scale[i] = 0.0  # gone the instant the jaw shuts; the crumbs carry the hand-off
	bites_left -= 1
	_sway_v += 9.0 * signf(global_position.x - eater_x)
	return global_position + BERRY_POS[i]


func _process(delta: float) -> void:
	_clock += delta
	for i in 3:
		var target := 1.0 if _alive[i] else 0.0
		if _alive[i]:
			_vel[i] += (220.0 * (target - _scale[i]) - 14.0 * _vel[i]) * delta
			_scale[i] += _vel[i] * delta
		else:
			_scale[i] = 0.0
			_vel[i] = 0.0
	_sway_v += (-90.0 * _sway - 6.0 * _sway_v) * delta
	_sway += _sway_v * delta
	queue_redraw()


func _draw() -> void:
	var lean := _sway * 0.1 + sin(_clock * 1.3) * 0.03
	# Leaves.
	for s: float in [-1.0, 1.0]:
		var leaf := PackedVector2Array([Vector2(0, 0), Vector2(s * 6, -4), Vector2(s * 13, -3), Vector2(s * 8, 0.5)])
		draw_colored_polygon(leaf, C_LEAF)
		leaf.append(leaf[0])
		draw_polyline(leaf, OUT, 1.4, true)
	var glow := float(bites_left) / 3.0
	if glow > 0.0:
		draw_circle(Vector2(0, -8), 24.0, Color(C_BERRY, 0.05 * glow))
		draw_circle(Vector2(0, -8), 15.0, Color(C_BERRY, 0.07 * glow))
	for i in [2, 0, 1]:
		var tip: Vector2 = BERRY_POS[i].rotated(lean * (1.0 + 0.4 * i))
		var mid := tip * 0.5 + Vector2(signf(tip.x) * 1.5, 0)
		var s: float = clampf(_scale[i], 0.0, 1.4)
		var stem_tip := tip if s > 0.05 else tip * 0.72  # bitten-off stub
		draw_polyline(PackedVector2Array([Vector2.ZERO, mid, stem_tip]), OUT, 3.2, true)
		draw_polyline(PackedVector2Array([Vector2.ZERO, mid, stem_tip]), C_STEM, 1.6, true)
		if s > 0.05:
			var r: float = BERRY_R[i] * s
			draw_circle(tip, r + 1.3, OUT)
			draw_circle(tip, r, C_BERRY)
			draw_circle(tip + Vector2(-r * 0.3, -r * 0.35), r * 0.36, C_BERRY_HI)
