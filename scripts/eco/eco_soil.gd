extends Node2D
## Draws the nutrient held in soil, on top of the map. One yellow dot per point of
## nutrient, the same mark the slimes carry on their backs, so the player can count what
## moves where. Up to 9 dots per cell; from 10 on, dots turn into large ones worth two.
## Drawing only: the amounts live in the grid.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

const C_MARK := Color("f8e68c")
const C_LINE := Color("17100f")
const SLOTS := 9

var grid: RefCounted

var _u := Spec.CELL_PX
var _hidden: Dictionary = {}          # cell -> points already in the grid but still flying in
var _pops: Array[Dictionary] = []     # {cell, slot_index, t}


func setup(g: RefCounted) -> void:
	grid = g
	grid.nutrient_changed.connect(func(_c: Vector2i, _a: int, _b: int) -> void: queue_redraw())
	grid.cell_changed.connect(func(c: Vector2i) -> void:
		_hidden.erase(c)
		queue_redraw())
	grid.was_reset.connect(clear)
	queue_redraw()


func clear() -> void:
	_hidden.clear()
	_pops.clear()
	queue_redraw()


func advance(delta: float) -> void:
	if _pops.is_empty():
		return
	for p in _pops:
		p.t += delta
	_pops = _pops.filter(func(p: Dictionary) -> bool: return p.t < 0.3)
	queue_redraw()


## A point has been added to the grid but its mote is still on the way: do not show it yet.
func hide_incoming(c: Vector2i) -> void:
	_hidden[c] = int(_hidden.get(c, 0)) + 1
	queue_redraw()


## The mote has landed: show the point, with a small pop.
func reveal(c: Vector2i) -> void:
	var left := int(_hidden.get(c, 0)) - 1
	if left <= 0:
		_hidden.erase(c)
	else:
		_hidden[c] = left
	_pops.append({"cell": c, "index": maxi(shown_count(c) - 1, 0), "t": 0.0})
	queue_redraw()


func shown_count(c: Vector2i) -> int:
	return maxi(grid.nutrient(c) - int(_hidden.get(c, 0)), 0)


func _h(c: Vector2i, k: int) -> float:
	var n := (c.x * 73856093) ^ (c.y * 19349663) ^ (k * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0


## Pixel position of the dot that shows point number `index` (0-based) of cell `c`.
## Each cell fills its 3x3 slots in its own fixed order.
func dot_pos(c: Vector2i, index: int) -> Vector2:
	var steps: Array[int] = [1, 2, 4, 5, 7, 8]
	var start := int(_h(c, 1) * SLOTS) % SLOTS
	var step := steps[int(_h(c, 2) * steps.size()) % steps.size()]
	var slot := (start + (index % SLOTS) * step) % SLOTS
	var gx := slot % 3
	var gy := slot / 3
	var jitter := Vector2(_h(c, 10 + slot) - 0.5, _h(c, 20 + slot) - 0.5) * 0.07
	return (Vector2(c) + Vector2(0.24 + 0.26 * gx, 0.24 + 0.26 * gy) + jitter) * _u


func _draw() -> void:
	if grid == null:
		return
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			if not grid.is_soil(c):
				continue
			var n := shown_count(c)
			if n <= 0:
				continue
			# Richer soil is a little greener; the dots carry the exact amount.
			draw_rect(Rect2(Vector2(c) * _u + Vector2(1, 1), Vector2(_u - 2, _u - 2)),
				Color(0.5, 0.78, 0.2, minf(0.05 + 0.018 * n, 0.24)))
			var doubles := clampi(n - SLOTS, 0, SLOTS)
			for i in mini(n, SLOTS):
				var r := (0.1 if i < doubles else 0.07) * _u
				for p in _pops:
					if p.cell == c and p.index % SLOTS == i:
						var f: float = p.t / 0.3
						r *= 0.3 + 0.7 * f + 0.5 * sin(PI * f)
				var at := dot_pos(c, i)
				draw_circle(at, r + 1.6, Color(C_LINE, 0.8))
				draw_circle(at, r, C_MARK)
