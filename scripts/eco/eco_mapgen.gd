extends RefCounted
## Builds the generated ecology map (task MAP-001): rock border, soil inside, an entrance
## shaft from the top, and the starting nutrient laid out by the old Unity project's
## "Stage 1" rule (LevelConfig.GenerateInitialNutrient), scaled to this map's area:
##   - low background scatter: about 35% of soil holds 1..3;
##   - a few probabilistic elliptical clusters (power 6..9, ragged edges, holes allowed);
##   - a few level-2 seed points (11) inside dense parts of clusters; no level 3;
##   - the final value is the highest of the three, capped at MAX_INITIAL.
## The same seed always gives the same map.

const Eco := preload("res://scripts/eco/eco_spec.gd")

## Old map underground area the counts below were tuned for (70 x 40 cells).
const REFERENCE_AREA := 70 * 40
const REFERENCE_CLUSTERS := 10
const REFERENCE_LV2_SEEDS := 6

const SCATTER_CHANCE := 0.35
const SCATTER_MIN := 1
const SCATTER_MAX := 3
const LV2_SEED_VALUE := 11
const MAX_INITIAL := 11


static func _hash(x: int, y: int, salt: int) -> int:
	var n := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return absi(n) % 1000003


static func _roll(x: int, y: int, salt: int) -> float:
	return float(_hash(x, y, salt) % 10000) / 10000.0


## Cluster count and seed count for a map with `area` soil cells, scaled from the old map.
static func scaled_counts(area: int) -> Dictionary:
	var k := float(area) / REFERENCE_AREA
	return {"clusters": maxi(1, roundi(REFERENCE_CLUSTERS * k)), "lv2": maxi(0, roundi(REFERENCE_LV2_SEEDS * k))}


static func layout(cols: int, rows: int) -> Array[String]:
	var lines: Array[String] = []
	for y in rows:
		var line := ""
		for x in cols:
			if x == 0 or y == 0 or x == cols - 1 or y == rows - 1:
				line += "#"
			elif x == Eco.GEN_ENTRANCE_COL and y <= Eco.GEN_ENTRANCE_DEPTH:
				line += "o"
			else:
				line += "."
		lines.append(line)
	return lines


## Returns {"layout": Array[String], "nutrient": Array[String]-like PackedInt32Array (row-major),
##          "clusters": Array[Dictionary], "lv2": Array[Vector2i]}.
static func generate(cols: int, rows: int, seed: int) -> Dictionary:
	var lines := layout(cols, rows)
	var soil := func(x: int, y: int) -> bool: return lines[y][x] == "."
	var inner_w := cols - 2
	var inner_h := rows - 2
	var counts := scaled_counts(inner_w * inner_h)

	# Clusters: spread across the width, at varied depths below the entrance.
	var clusters: Array[Dictionary] = []
	var n: int = counts.clusters
	for i in n:
		var span := maxi(1, roundi(inner_w * 0.12))
		var jitter := _hash(i, seed, 1201) % (span * 2 + 1) - span
		var cx := clampi(1 + roundi(inner_w * (i + 0.5) / n) + jitter, 1, cols - 2)
		var top := Eco.GEN_ENTRANCE_DEPTH + 2
		var cy := clampi(top + _hash(i, seed, 1601) % maxi(1, rows - 2 - top), 1, rows - 2)
		clusters.append({
			"center": Vector2i(cx, cy),
			"rx": 6 + _hash(i, seed, 1901) % 4,
			"ry": 3 + _hash(i, seed, 2201) % 4,
			"power": 6 + _hash(i, seed, 2401) % 4,
			"falloff": 1.1 + 0.05 * (_hash(i, seed, 2451) % 3),
			"density": 0.72 + float(_hash(i, seed, 2501) % 16) / 100.0,
		})

	var nutrient := PackedInt32Array()
	nutrient.resize(cols * rows)
	for y in rows:
		for x in cols:
			if not soil.call(x, y):
				continue
			var v := maxi(_scatter(x, y, seed), _cluster_value(x, y, clusters, seed))
			nutrient[y * cols + x] = v

	# Level-2 seed points: only near the dense middle of a cluster, on soil that cluster filled.
	var lv2: Array[Vector2i] = []
	var want: int = counts.lv2
	var attempts := maxi(want * 24, 48)
	for i in attempts:
		if lv2.size() >= want or clusters.is_empty():
			break
		var c: Dictionary = clusters[_hash(i, seed, 211) % clusters.size()]
		var sx: int = c.center.x + _hash(i, seed, 211 ^ 101) % (c.rx * 2 + 1) - c.rx
		var sy: int = c.center.y + _hash(i, seed, 211 ^ 307) % (c.ry * 2 + 1) - c.ry
		if sx < 1 or sy < 1 or sx > cols - 2 or sy > rows - 2 or not soil.call(sx, sy):
			continue
		if _norm_dist(sx, sy, c) > 0.55 or _cluster_value(sx, sy, clusters, seed) <= 0:
			continue
		var p := Vector2i(sx, sy)
		if lv2.has(p):
			continue
		lv2.append(p)
		nutrient[sy * cols + sx] = maxi(nutrient[sy * cols + sx], LV2_SEED_VALUE)

	for i in nutrient.size():
		nutrient[i] = clampi(nutrient[i], 0, MAX_INITIAL)
	return {"layout": lines, "nutrient": nutrient, "clusters": clusters, "lv2": lv2}


static func _scatter(x: int, y: int, seed: int) -> int:
	if _roll(x, y, 503 ^ seed) >= SCATTER_CHANCE:
		return 0
	return SCATTER_MIN + _hash(x, y, 907 ^ seed) % (SCATTER_MAX - SCATTER_MIN + 1)


static func _norm_dist(x: int, y: int, c: Dictionary) -> float:
	var dx: float = float(x - c.center.x) / c.rx
	var dy: float = float(y - c.center.y) / c.ry
	return sqrt(dx * dx + dy * dy)


static func _cluster_value(x: int, y: int, clusters: Array[Dictionary], seed: int) -> int:
	var best := 0
	for i in clusters.size():
		var c := clusters[i]
		var d := _norm_dist(x, y, c)
		if d > 1.0:
			continue
		var strength := pow(1.0 - d, c.falloff)
		var chance := clampf(c.density * (0.15 + strength * 0.85), 0.0, 1.0)
		if _roll(x, y, seed ^ (i * 4099 + 2801)) > chance:
			continue
		var lo := maxi(1, roundi(c.power * 0.25))
		var hi := maxi(lo, roundi(lerpf(1.0, c.power, strength)))
		best = maxi(best, lo + _hash(x, y, seed ^ (i * 4099 + 3101)) % (hi - lo + 1))
	return best


## A dig plan for the built-in demo on a generated map: carry on down the entrance shaft,
## open a long top tunnel, three shafts down from it, a bottom tunnel joining them (so the
## network has loops and mosses spread out), then a branch towards every cluster centre.
## Cells are in dig order; each touches an earlier one, so all can be dug in turn.
static func demo_plan(cols: int, rows: int, clusters: Array[Dictionary]) -> Array[Vector2i]:
	var plan: Array[Vector2i] = []
	var ex := Eco.GEN_ENTRANCE_COL
	var top := Eco.GEN_ENTRANCE_DEPTH + 4
	var bottom := rows - 7
	var x_lo := 4
	var x_hi := cols - 5
	var shafts: Array[int] = [roundi(cols * 0.2), ex, roundi(cols * 0.8)]
	var add := func(c: Vector2i) -> void:
		if not plan.has(c):
			plan.append(c)
	for y in range(Eco.GEN_ENTRANCE_DEPTH + 1, top + 1):
		add.call(Vector2i(ex, y))
	var left := ex - 1
	var right := ex + 1
	while left >= x_lo or right <= x_hi:
		if right <= x_hi:
			add.call(Vector2i(right, top))
			right += 1
		if left >= x_lo:
			add.call(Vector2i(left, top))
			left -= 1
	for sx in [shafts[1], shafts[0], shafts[2]]:
		for y in range(top + 1, bottom + 1):
			add.call(Vector2i(sx, y))
	for x in range(shafts[0] + 1, shafts[2]):
		add.call(Vector2i(x, bottom))
	for c in clusters:
		var cx := clampi(c.center.x, x_lo, x_hi)
		var cy := clampi(c.center.y, 1, rows - 2)
		var from := top
		if cy > bottom and cx > shafts[0] and cx < shafts[2]:
			from = bottom
		var step := 1 if cy > from else -1
		var y := from + step
		while cy != from and y != cy + step:
			add.call(Vector2i(cx, y))
			y += step
	return plan
