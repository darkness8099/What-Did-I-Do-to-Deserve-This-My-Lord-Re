extends RefCounted
## Pure rules of the minimal ecology slice. No nodes, no drawing, no time: every function
## takes what it needs and returns what happened, so the self-test can call them directly.

const Eco := preload("res://scripts/eco/eco_spec.gd")


## One movement decision. `can_enter` is terrain only: other creatures never block.
##   straight if open; otherwise a free side (random if both are free);
##   otherwise back; otherwise stay.
## Returns {"moved": bool, "pos": Vector2i, "dir": Vector2i}.
static func next_step(pos: Vector2i, dir: Vector2i, can_enter: Callable, rng: RandomNumberGenerator) -> Dictionary:
	if can_enter.call(pos + dir):
		return {"moved": true, "pos": pos + dir, "dir": dir}
	var left := Vector2i(dir.y, -dir.x)
	var right := Vector2i(-dir.y, dir.x)
	var l_open: bool = can_enter.call(pos + left)
	var r_open: bool = can_enter.call(pos + right)
	if l_open and r_open:
		var pick := left if rng.randf() < 0.5 else right
		return {"moved": true, "pos": pos + pick, "dir": pick}
	if l_open:
		return {"moved": true, "pos": pos + left, "dir": left}
	if r_open:
		return {"moved": true, "pos": pos + right, "dir": right}
	if can_enter.call(pos - dir):
		return {"moved": true, "pos": pos - dir, "dir": -dir}
	return {"moved": false, "pos": pos, "dir": dir}


## One absorb / release check for a slime standing on `pos` carrying `carried`.
## Changes the grid. Returns {"action": "absorb" | "release" | "none", "carried": int,
## "cells": Array[Vector2i]} where cells is the soil taken from, or one entry per point given.
static func resolve_ecology(carried: int, pos: Vector2i, grid: RefCounted, rng: RandomNumberGenerator) -> Dictionary:
	var cells: Array[Vector2i] = []
	if carried <= Eco.ABSORB_AT_OR_BELOW:
		for d in Eco.N4:
			var c: Vector2i = pos + d
			if grid.has_nutrient(c):
				grid.add_nutrient(c, -1)
				cells.append(c)
				return {"action": "absorb", "carried": carried + 1, "cells": cells}
		return {"action": "none", "carried": carried, "cells": cells}
	if carried >= Eco.RELEASE_AT_OR_ABOVE:
		var surplus := carried - Eco.KEEP_ON_RELEASE
		var candidates: Array[Vector2i] = []
		for d in Eco.N4:
			if grid.has_nutrient(pos + d):
				candidates.append(pos + d)
		if surplus <= 0 or candidates.is_empty():
			return {"action": "none", "carried": carried, "cells": cells}
		for i in surplus:
			var c := candidates[rng.randi_range(0, candidates.size() - 1)]
			grid.add_nutrient(c, 1)
			cells.append(c)
		return {"action": "release", "carried": carried - surplus, "cells": cells}
	return {"action": "none", "carried": carried, "cells": cells}


## Spread dig leftovers evenly over the nearest ring that has any soil (rings include
## diagonals). Nothing within reach: the amount goes to the floating pool.
## Returns the cells that received something, one entry per point.
static func scatter(origin: Vector2i, amount: int, grid: RefCounted, source: String) -> Array[Vector2i]:
	var got: Array[Vector2i] = []
	if amount <= 0:
		return got
	for ring in range(1, Eco.SCATTER_MAX_RING + 1):
		var soil: Array[Vector2i] = []
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := origin + Vector2i(dx, dy)
				if grid.is_soil(c):
					soil.append(c)
		if soil.is_empty():
			continue
		var share := amount / soil.size()
		var rest := amount - share * soil.size()
		for i in soil.size():
			var give := share + (1 if i < rest else 0)
			if give > 0:
				grid.add_nutrient(soil[i], give)
				for j in give:
					got.append(soil[i])
		return got
	grid.pool_deposit(amount, source)
	return got
