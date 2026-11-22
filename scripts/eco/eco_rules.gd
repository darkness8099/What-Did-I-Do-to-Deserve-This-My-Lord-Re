extends RefCounted
## Pure rules of the ecology test. No nodes, no drawing, no time: every function
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


## HP after one completed move. `moves` counts completed moves since the last HP cost.
## Returns {"hp": int, "moves": int}.
static func move_hp(hp: int, moves: int) -> Dictionary:
	moves += 1
	if moves >= Eco.HP_COST_EVERY_MOVES:
		return {"hp": hp - Eco.HP_COST, "moves": 0}
	return {"hp": hp, "moves": moves}


## What a crawler becomes after a completed move: "bud", "starve" or "live".
## `cell_has_plant`: only one bud or flower per cell; a weak slime on a taken cell keeps
## crawling and may bud on a free cell later (or starve if its HP runs out first).
static func crawler_fate(hp: int, carried: int, cell_has_plant: bool) -> String:
	if hp <= Eco.BUD_HP_THRESHOLD and carried >= Eco.BUD_REQUIRED_NUTRIENT and not cell_has_plant:
		return "bud"
	if hp <= 0:
		return "starve"
	return "live"


## Bud / flower: take 1 nutrient from the nearest soil holding some, ring by ring out to
## `radius` (Chebyshev). Rich soil (Eco.PLANT_SKIPS_SOIL_FROM or more) is left alone, as in
## the original game, so soil can stay rich enough to hatch higher creatures. Returns the cell drawn from, or (-1, -1) if there was none.
static func plant_draw(pos: Vector2i, radius: int, grid: RefCounted) -> Vector2i:
	for r in range(1, radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := pos + Vector2i(dx, dy)
				if grid.has_nutrient(c) and grid.nutrient(c) < Eco.PLANT_SKIPS_SOIL_FROM:
					grid.add_nutrient(c, -1)
					return c
	return Vector2i(-1, -1)


## Newborns from a flower that collected `collected`, and what is left over.
static func offspring(collected: int) -> Dictionary:
	var count := mini(Eco.SPAWN_MAX, collected / Eco.NUTRIENT_PER_SPAWN)
	return {"count": count, "spent": count * Eco.NUTRIENT_PER_SPAWN, "left": collected - count * Eco.NUTRIENT_PER_SPAWN}


## Nutrient of a creature that starved or withered returns to the soil around it, as in the
## original game: within DEATH_SCATTER_RING (7x7), each soil cell takes at most 1 point,
## nearest ring first and, inside a ring, cells below before cells beside before cells
## above. What finds no soil is lost: it goes to the floating pool with its source.
## (The original's exact fill order beyond the first ring is not documented; this follows
## its first-ring order outwards.) Returns the cells that received a point.
static func death_scatter(origin: Vector2i, amount: int, grid: RefCounted, source: String) -> Array[Vector2i]:
	var got: Array[Vector2i] = []
	var left := amount
	for ring in range(1, Eco.DEATH_SCATTER_RING + 1):
		if left <= 0:
			break
		var cells: Array[Vector2i] = []
		for dy in range(ring, -ring - 1, -1):
			var xs: Array[int] = [0]
			for k in range(1, ring + 1):
				xs.append(-k)
				xs.append(k)
			for dx in xs:
				if maxi(absi(dx), absi(dy)) == ring:
					cells.append(origin + Vector2i(dx, dy))
		for c in cells:
			if left <= 0:
				break
			if grid.is_soil(c):
				grid.add_nutrient(c, 1)
				got.append(c)
				left -= 1
	if left > 0:
		grid.pool_deposit(left, source + ":no-soil-left")
	return got
