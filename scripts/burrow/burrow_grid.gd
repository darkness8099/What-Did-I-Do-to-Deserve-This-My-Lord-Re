extends RefCounted
## Grid logic: cell kinds, digging, reset, item occupancy and pathfinding.
## Knows nothing about pixels or drawing.

const Spec := preload("res://scripts/burrow/grid_spec.gd")

signal cell_changed(cell: Vector2i)
signal was_reset

var cols := 0
var rows := 0
var _cells := PackedByteArray()
var _initial := PackedByteArray()
var _blockers: Dictionary = {}   # Vector2i -> Object occupying that cell


func load_layout(lines: Array[String]) -> void:
	rows = lines.size()
	cols = lines[0].length()
	_cells.resize(cols * rows)
	for y in rows:
		for x in cols:
			var ch := lines[y][x]
			_cells[y * cols + x] = Spec.ROCK if ch == "#" else (Spec.OPEN if ch == "o" else Spec.SOIL)
	_initial = _cells.duplicate()


func reset() -> void:
	_cells = _initial.duplicate()
	was_reset.emit()


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func kind(c: Vector2i) -> int:
	return _cells[c.y * cols + c.x] if in_bounds(c) else Spec.ROCK


func is_open(c: Vector2i) -> bool:
	return kind(c) == Spec.OPEN


func is_open_at(p: Vector2) -> bool:
	return is_open(Spec.cell_of(p))


## Soil can be dug only from an already open neighbour, so tunnels always stay connected.
func can_dig(c: Vector2i) -> bool:
	if kind(c) != Spec.SOIL:
		return false
	for d in Spec.DIRS:
		if is_open(c + d):
			return true
	return false


func dig(c: Vector2i) -> bool:
	if not can_dig(c):
		return false
	_cells[c.y * cols + c.x] = Spec.OPEN
	cell_changed.emit(c)
	return true


# ------------------------------------------------------------------ occupancy

func occupy(who: Object, cell: Vector2i, size := Vector2i.ONE) -> void:
	for y in size.y:
		for x in size.x:
			_blockers[cell + Vector2i(x, y)] = who


func vacate(who: Object) -> void:
	for c: Vector2i in _blockers.keys():
		if _blockers[c] == who:
			_blockers.erase(c)


func blocker_at(c: Vector2i) -> Object:
	return _blockers.get(c)


## True if a footprint of `size` anchored at `c` fits: all cells open and unoccupied.
func area_free(c: Vector2i, size := Vector2i.ONE) -> bool:
	for y in size.y:
		for x in size.x:
			var q := c + Vector2i(x, y)
			if not is_open(q) or _blockers.has(q):
				return false
	return true


# ------------------------------------------------------------------ paths

## Breadth-first route of anchor cells for a footprint of `size`. Returns [] if `goals`
## cannot be reached; otherwise the cells from `from` to the nearest goal, inclusive.
func find_path(from: Vector2i, goals: Array[Vector2i], size := Vector2i.ONE) -> Array[Vector2i]:
	var want: Dictionary = {}
	for g in goals:
		want[g] = true
	var prev: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	var found := Vector2i(-1, -1)
	while head < queue.size():
		var c := queue[head]
		head += 1
		if want.has(c):
			found = c
			break
		for d in Spec.DIRS:
			var n := c + d
			if not prev.has(n) and area_free(n, size):
				prev[n] = c
				queue.append(n)
	var out: Array[Vector2i] = []
	if found.x < 0:
		return out
	var c := found
	while c != from:
		out.append(c)
		c = prev[c]
	out.append(from)
	out.reverse()
	return out


## Anchor cells from which a footprint of `size` touches the rectangle (cell, tsize) edge to edge.
func cells_beside(cell: Vector2i, tsize: Vector2i, size := Vector2i.ONE) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(cell.x - size.x + 1, cell.x + tsize.x):
		out.append(Vector2i(x, cell.y - size.y))
		out.append(Vector2i(x, cell.y + tsize.y))
	for y in range(cell.y - size.y + 1, cell.y + tsize.y):
		out.append(Vector2i(cell.x - size.x, y))
		out.append(Vector2i(cell.x + tsize.x, y))
	return out
