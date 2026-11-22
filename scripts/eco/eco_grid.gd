extends "res://scripts/burrow/burrow_grid.gd"
## The burrow grid plus one integer of nutrient per soil cell, and the floating pool ledger.
## Only soil holds nutrient: digging a cell takes its nutrient out (the caller decides
## where it goes). Knows nothing about pixels or drawing.

signal nutrient_changed(cell: Vector2i, old_value: int, new_value: int)

var _nutrient := PackedInt32Array()
var _nutrient_initial := PackedInt32Array()

## Floating pool: nutrient that left the soil / creature loop. Stored with its source,
## never taken out again in this slice.
var pool_total := 0
var pool_entries: Array[Dictionary] = []


func load_nutrient(lines: Array[String]) -> void:
	_nutrient.resize(cols * rows)
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			_nutrient[y * cols + x] = int(lines[y][x]) if kind(c) == Spec.SOIL else 0
	_nutrient_initial = _nutrient.duplicate()


## Starting nutrient from a row-major array (generated maps). Ignored where not soil.
func load_nutrient_values(values: PackedInt32Array) -> void:
	_nutrient.resize(cols * rows)
	for i in _nutrient.size():
		var c := Vector2i(i % cols, i / cols)
		_nutrient[i] = values[i] if kind(c) == Spec.SOIL else 0
	_nutrient_initial = _nutrient.duplicate()


func reset() -> void:
	_nutrient = _nutrient_initial.duplicate()
	pool_total = 0
	pool_entries.clear()
	super.reset()


func nutrient(c: Vector2i) -> int:
	return _nutrient[c.y * cols + c.x] if in_bounds(c) else 0


func is_soil(c: Vector2i) -> bool:
	return kind(c) == Spec.SOIL


## Soil a moss can trade with: it must already hold nutrient.
func has_nutrient(c: Vector2i) -> bool:
	return is_soil(c) and nutrient(c) > 0


func add_nutrient(c: Vector2i, amount: int) -> void:
	if amount == 0 or not is_soil(c):
		return
	var i := c.y * cols + c.x
	var old := _nutrient[i]
	_nutrient[i] = maxi(old + amount, 0)
	nutrient_changed.emit(c, old, _nutrient[i])


## Dig a cell and return the nutrient that was in it (-1 if it could not be dug).
func dig_out(c: Vector2i) -> int:
	if not can_dig(c):
		return -1
	var i := c.y * cols + c.x
	var had := _nutrient[i]
	_nutrient[i] = 0
	dig(c)
	return had


func soil_total() -> int:
	var sum := 0
	for v in _nutrient:
		sum += v
	return sum


func pool_deposit(amount: int, source: String) -> void:
	if amount <= 0:
		return
	pool_total += amount
	pool_entries.append({"amount": amount, "source": source})
