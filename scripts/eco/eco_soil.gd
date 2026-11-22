extends Node2D
## Draws the nutrient held in soil, on top of the map, in three tiers (as in the old project):
##   level 1 (1..10): one yellow dot per point, the mark the slimes carry on their backs;
##                    9 slots, so 10 shows one large dot worth two;
##   level 2 (11..20): small pale flowers, more of them as it grows;
##   level 3 (21+): a big golden bloom, with small ones added as it grows.
## Exact amounts are in the G overlay. Drawing only: the amounts live in the grid.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

const C_MARK := Color("f8e68c")
const C_PETAL2 := Color("fff2d8")
const C_PETAL3 := Color("ffad3b")
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


## Tier of a nutrient amount, as in the old project: 0 plain, 1 (1..10), 2 (11..20), 3 (21+).
static func tier(n: int) -> int:
	if n <= 0:
		return 0
	if n <= 10:
		return 1
	if n <= 20:
		return 2
	return 3


func _bloom(at: Vector2, r: float, petals: int, petal_col: Color, rot: float) -> void:
	for k in petals:
		var a := rot + TAU * k / petals
		var p := at + Vector2(cos(a), sin(a)) * r
		draw_circle(p, r * 0.72 + 1.3, Color(C_LINE, 0.85))
	for k in petals:
		var a := rot + TAU * k / petals
		draw_circle(at + Vector2(cos(a), sin(a)) * r, r * 0.72, petal_col)
	draw_circle(at, r * 0.62 + 1.2, Color(C_LINE, 0.85))
	draw_circle(at, r * 0.62, C_MARK)


func _draw() -> void:
	if grid == null:
		return
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			if not grid.is_soil(c):
				continue
			var n := shown_count(c)
			var t := tier(n)
			if t == 0:
				continue
			var o := Vector2(c) * _u
			# Richer soil is greener; each tier has its own mark so it reads at a glance.
			var tint: Color = [Color(0, 0, 0, 0), Color(0.5, 0.78, 0.2, 0.05 + 0.017 * n),
				Color(0.45, 0.8, 0.25, 0.26), Color(0.4, 0.85, 0.3, 0.36)][t]
			draw_rect(Rect2(o + Vector2(1, 1), Vector2(_u - 2, _u - 2)), tint)
			if t == 1:
				# Level 1: one yellow dot per point, the same mark slimes carry on their backs.
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
			elif t == 2:
				# Level 2: a handful of small pale flowers with yellow hearts.
				var count := 2 + (n - 11) / 3
				for i in count:
					_bloom(dot_pos(c, i * 2), 0.06 * _u, 5, C_PETAL2, _h(c, 40 + i) * TAU)
			else:
				# Level 3: one big golden bloom, plus small ones as it grows richer.
				_bloom(o + Vector2(0.5, 0.5) * _u + Vector2(_h(c, 50) - 0.5, _h(c, 51) - 0.5) * 0.12 * _u,
					0.12 * _u, 6, C_PETAL3, _h(c, 52) * TAU)
				var corners: Array[Vector2] = [Vector2(0.2, 0.2), Vector2(0.8, 0.22), Vector2(0.22, 0.8), Vector2(0.8, 0.8)]
				for i in mini((n - 21) / 4 + 1, 4):
					_bloom(o + corners[i] * _u, 0.05 * _u, 5, C_PETAL2, _h(c, 60 + i) * TAU)
