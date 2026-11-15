extends Node2D
## Honey root nodules (蜜根瘤): a cluster of three amber tubers hanging on root threads
## that grow out of the surrounding soil. One bite each. Blocks its cell.
## Node origin = top-left corner of its cell, drawn in pixels.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

const OFFS: Array[Vector2] = [Vector2(-0.11, 0.04), Vector2(0.11, 0.05), Vector2(0.0, -0.1)]   # from the cell centre, cells
const RAD: Array[float] = [0.115, 0.12, 0.105]
const C_LINE := Color("2a1a14")
const C_NOD := Color("ffb347")
const C_NOD_DARK := Color("d9822b")
const C_NOD_HI := Color("fff0c0")
const C_ROOT := Color("a8845c")

var grid: RefCounted
var cell := Vector2i.ZERO
var size := Vector2i.ONE     ## footprint in cells
var bites_left := 3

var _u := Spec.CELL_PX
var _alive: Array[bool] = [true, true, true]
var _scale: Array[float] = [1.0, 1.0, 1.0]
var _vel: Array[float] = [0.0, 0.0, 0.0]
var _sway := Vector2.ZERO
var _sway_v := Vector2.ZERO
var _clock := 0.0


func place(c: Vector2i) -> void:
	cell = c
	position = Vector2(c) * _u
	_clock = float(c.x * 3 + c.y)


func center() -> Vector2:
	return Spec.center(cell, size)


func restock(instant := false) -> void:
	bites_left = 3
	for i in 3:
		if not _alive[i] and not instant:
			_scale[i] = 0.0
			_vel[i] = 0.0
		_alive[i] = true
		if instant:
			_scale[i] = 1.0
			_vel[i] = 0.0
	if instant:
		_sway = Vector2.ZERO
		_sway_v = Vector2.ZERO
	queue_redraw()


## The nodule an eater at `from` (cells) would take next: {index, pos, r}.
func next_bite(from: Vector2) -> Dictionary:
	var best := -1
	var best_d := 1e9
	for i in 3:
		if _alive[i]:
			var d := from.distance_to(center() + OFFS[i])
			if d < best_d:
				best_d = d
				best = i
	if best < 0:
		return {"index": -1, "pos": center(), "r": 0.1}
	return {"index": best, "pos": center() + OFFS[best], "r": RAD[best]}


## Removes one nodule and returns where it was (cells).
func take_bite(index: int) -> Vector2:
	if index < 0 or not _alive[index]:
		return center()
	_alive[index] = false
	_scale[index] = 0.0
	bites_left -= 1
	_sway_v += OFFS[index].normalized() * -1.6
	return center() + OFFS[index]


func _process(delta: float) -> void:
	_clock += delta
	for i in 3:
		if _alive[i]:
			_vel[i] += (240.0 * (1.0 - _scale[i]) - 15.0 * _vel[i]) * delta
			_scale[i] += _vel[i] * delta
	_sway_v += (-110.0 * _sway - 7.0 * _sway_v) * delta
	_sway += _sway_v * delta
	queue_redraw()


func _draw() -> void:
	var ctr := Vector2(0.5, 0.5) * _u + _sway * _u * 0.25
	# Root threads from every solid wall of the cell.
	var any := false
	for s in 4:
		var d: Vector2i = Spec.DIRS[s]
		if grid != null and grid.is_open(cell + d):
			continue
		any = true
		_root(Vector2(0.5, 0.5) * _u + Vector2(d) * 0.46 * _u + Vector2(d).orthogonal() * (0.12 if s % 2 == 0 else -0.1) * _u, ctr, s)
	if not any:
		_root(Vector2(0.5, 0.04) * _u, ctr, 3)
	var glow := float(bites_left) / 3.0
	if glow > 0.0:
		var pulse := 0.85 + 0.15 * sin(_clock * 1.8)
		draw_circle(ctr, 0.42 * _u, Color(C_NOD, 0.045 * glow * pulse))
		draw_circle(ctr, 0.3 * _u, Color(C_NOD, 0.07 * glow * pulse))
	for i in [2, 0, 1]:
		var p: Vector2 = ctr + OFFS[i] * _u + _sway * _u * (0.5 + 0.25 * i)
		var s: float = clampf(_scale[i], 0.0, 1.3)
		# Stalk from the knot in the middle.
		var stalk := PackedVector2Array([ctr, ctr.lerp(p, 0.5) + Vector2(0, -2), p if s > 0.05 else ctr.lerp(p, 0.55)])
		draw_polyline(stalk, C_LINE, 3.4, true)
		draw_polyline(stalk, C_ROOT, 1.7, true)
		if s <= 0.05:
			continue
		var r: float = RAD[i] * _u * s
		draw_circle(p, r + 1.5, C_LINE)
		draw_circle(p, r, C_NOD_DARK)
		draw_circle(p + Vector2(-0.1, -0.12) * r, r * 0.84, C_NOD)
		draw_circle(p + Vector2(-0.3, -0.36) * r, r * 0.34, C_NOD_HI)
		draw_circle(p + Vector2(0.38, 0.3) * r, r * 0.12, Color(C_LINE, 0.35))
	draw_circle(ctr, 3.0, C_LINE)
	draw_circle(ctr, 1.8, C_ROOT)


func _root(from: Vector2, to: Vector2, k: int) -> void:
	var mid := from.lerp(to, 0.5) + (to - from).orthogonal().normalized() * (4.0 if k % 2 == 0 else -4.0)
	var pts := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	draw_polyline(pts, C_LINE, 3.6, true)
	draw_polyline(pts, C_ROOT.darkened(0.15), 1.9, true)
