extends RefCounted
## Headless checks for the ecology test. Run with:
##   godot --headless --path . --fixed-fps 60 res://scenes/eco_lab.tscn -- --selftest
## It calls the pure rules directly, drives single slime and plant nodes on small test
## grids, then drives the real scene with fixed time steps and checks invariants every
## frame. It cannot judge how anything looks.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Grid := preload("res://scripts/eco/eco_grid.gd")
const Slime := preload("res://scripts/eco/slime.gd")
const Plant := preload("res://scripts/eco/plant.gd")
const MapGen := preload("res://scripts/eco/eco_mapgen.gd")
const Soil := preload("res://scripts/eco/eco_soil.gd")

var _checks := 0
var _fails := 0
var _frame_fail := ""
var _events: Array[Dictionary] = []
var _visited: Dictionary = {}
var _watched: Dictionary = {}


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[eco-selftest] %s  %s" % ["PASS" if ok else "FAIL", what])


func _grid(layout: Array[String], nutrient: Array[String]) -> RefCounted:
	var g := Grid.new()
	g.load_layout(layout)
	g.load_nutrient(nutrient)
	return g


func run(main: Node) -> int:
	_rules_movement()
	_rules_ecology()
	_rules_scatter()
	_rules_life()
	_slime_node()
	_plant_node()
	_mapgen()
	_scene(main)
	_scene_generated(main)
	print("[eco-selftest] %d checks, %d failures" % [_checks, _fails])
	return _fails


# ------------------------------------------------------------------ pure rules

func _rules_movement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var open: Dictionary = {}
	var can := func(c: Vector2i) -> bool: return open.has(c)
	var p := Vector2i(5, 5)
	var right := Vector2i(1, 0)

	open.clear()
	open[p + right] = true
	open[p + Vector2i(0, 1)] = true
	var r := Rules.next_step(p, right, can, rng)
	_check(r.moved and r.pos == p + right and r.dir == right, "goes straight while the way ahead is open")

	open.clear()
	open[p + Vector2i(0, 1)] = true
	open[p - right] = true
	r = Rules.next_step(p, right, can, rng)
	_check(r.moved and r.pos == p + Vector2i(0, 1), "blocked with one free side: takes that side, not the way back")

	open.clear()
	open[p + Vector2i(0, 1)] = true
	open[p + Vector2i(0, -1)] = true
	var seen: Dictionary = {}
	for i in 60:
		seen[Rules.next_step(p, right, can, rng).dir] = true
	_check(seen.size() == 2 and seen.has(Vector2i(0, 1)) and seen.has(Vector2i(0, -1)), "blocked with both sides free: picks either at random")

	open.clear()
	open[p - right] = true
	r = Rules.next_step(p, right, can, rng)
	_check(r.moved and r.dir == -right, "dead end: turns back")

	open.clear()
	r = Rules.next_step(p, right, can, rng)
	_check(not r.moved and r.pos == p and r.dir == right, "walled in on all sides: stays put")


func _rules_ecology() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var layout: Array[String] = ["#####", "#...#", "#.o.#", "#...#", "#####"]
	var c := Vector2i(2, 2)

	var g := _grid(layout, ["00000", "00200", "03040", "00500", "00000"])
	var r := Rules.resolve_ecology(1, c, g, rng)
	_check(r.action == "absorb" and r.carried == 2 and g.nutrient(Vector2i(2, 1)) == 1, "carrying 1: absorbs 1, from the block above first")

	g = _grid(layout, ["00000", "00000", "00040", "00000", "00000"])
	r = Rules.resolve_ecology(0, c, g, rng)
	_check(r.action == "absorb" and g.nutrient(Vector2i(3, 2)) == 3, "skips empty soil and absorbs from the first block that has nutrient")

	g = _grid(layout, ["00000", "00000", "00000", "00000", "00000"])
	r = Rules.resolve_ecology(0, c, g, rng)
	var r2 := Rules.resolve_ecology(3, c, g, rng)
	_check(r.action == "none" and r2.action == "none" and r2.carried == 3 and g.soil_total() == 0, "no nutrient soil around: neither absorbs nor releases")

	var ok := true
	for i in 40:
		g = _grid(layout, ["00000", "00100", "00020", "00000", "00000"])
		r = Rules.resolve_ecology(3, c, g, rng)
		ok = ok and r.action == "release" and r.carried == 1 and g.soil_total() == 5
		ok = ok and g.nutrient(Vector2i(1, 2)) == 0 and g.nutrient(Vector2i(2, 3)) == 0
	_check(ok, "carrying 3: releases 2, keeps 1, never onto soil that had no nutrient")

	g = _grid(layout, ["00000", "00100", "00000", "00000", "00000"])
	r = Rules.resolve_ecology(2, c, g, rng)
	_check(r.action == "release" and r.carried == 1 and g.nutrient(Vector2i(2, 1)) == 2, "carrying 2: releases 1, keeps 1")


func _rules_scatter() -> void:
	var layout: Array[String] = ["#####", "#...#", "#.o.#", "#...#", "#####"]
	var zero: Array[String] = ["00000", "00000", "00000", "00000", "00000"]
	var g := _grid(layout, zero)
	var got := Rules.scatter(Vector2i(2, 2), 11, g, "test")
	var lo := 99
	var hi := 0
	for y in range(1, 4):
		for x in range(1, 4):
			if Vector2i(x, y) != Vector2i(2, 2):
				lo = mini(lo, g.nutrient(Vector2i(x, y)))
				hi = maxi(hi, g.nutrient(Vector2i(x, y)))
	_check(g.soil_total() == 11 and got.size() == 11 and lo == 1 and hi == 2 and g.pool_total == 0, "dig leftovers spread evenly over the nearest ring of soil")

	g = _grid(["#########", "#########", "#########", "#########", "####o####", "#########", "#########", "#########", "#########"],
		["000000000", "000000000", "000000000", "000000000", "000000000", "000000000", "000000000", "000000000", "000000000"])
	Rules.scatter(Vector2i(4, 4), 4, g, "dig-leftover(test)")
	_check(g.soil_total() == 0 and g.pool_total == 4 and g.pool_entries.size() == 1 and g.pool_entries[0].source == "dig-leftover(test)",
		"no soil within three rings: leftovers go to the floating pool with amount and source")


func _rules_life() -> void:
	# HP: one point every second completed move.
	var hp := Eco.HP_INITIAL
	var moves := 0
	var trace: Array[int] = []
	for i in 6:
		var h := Rules.move_hp(hp, moves)
		hp = h.hp
		moves = h.moves
		trace.append(hp)
	_check(trace == [16, 15, 15, 14, 14, 13], "walking costs 1 HP every 2 completed moves (%s)" % [trace])

	_check(Rules.crawler_fate(2, 2, false) == "bud" and Rules.crawler_fate(3, 3, false) == "live"
		and Rules.crawler_fate(2, 1, false) == "live", "buds only when HP <= 2 and carrying >= 2")
	_check(Rules.crawler_fate(1, 3, true) == "live" and Rules.crawler_fate(0, 3, true) == "starve",
		"a cell that already holds a bud or flower: keeps crawling, starves if HP runs out there")
	_check(Rules.crawler_fate(0, 1, false) == "starve" and Rules.crawler_fate(0, 2, false) == "bud",
		"out of HP: starves with less than 2, buds with 2 or more")

	var g := _grid(["#######", "#.....#", "#.....#", "#..o..#", "#.....#", "#.....#", "#######"],
		["0000000", "0900000", "0000000", "0000000", "0000000", "0000000", "0000000"])
	var none := Rules.plant_draw(Vector2i(3, 3), 1, g)
	var got := Rules.plant_draw(Vector2i(3, 3), 2, g)
	_check(none == Vector2i(-1, -1) and got == Vector2i(1, 1) and g.nutrient(Vector2i(1, 1)) == 8,
		"a plant draws 1 point from soil inside its radius only")
	g = _grid(["#######", "#.....#", "#.....#", "#..o..#", "#.....#", "#.....#", "#######"],
		["0000000", "0900000", "0000000", "0000000", "0000100", "0000000", "0000000"])
	_check(Rules.plant_draw(Vector2i(3, 3), 2, g) == Vector2i(4, 4), "a plant draws from the nearest ring first")

	g = _grid(["#######", "#.....#", "#.....#", "#..o..#", "#.....#", "#.....#", "#######"],
		["0000000", "0000000", "0009000", "0000000", "0000000", "0000000", "0000000"])
	g.add_nutrient(Vector2i(3, 2), 2)
	var skipped := Rules.plant_draw(Vector2i(3, 3), 2, g)
	g.add_nutrient(Vector2i(3, 2), -1)
	var taken := Rules.plant_draw(Vector2i(3, 3), 2, g)
	_check(skipped == Vector2i(-1, -1) and taken == Vector2i(3, 2) and g.nutrient(Vector2i(3, 2)) == 9,
		"a plant leaves soil holding 11 or more alone, and draws again once it is below 11")

	# Death return: one point per soil cell, below first, then beside, then above; the rest is lost.
	var ring: Array[String] = ["#####", "#...#", "#.o.#", "#...#", "#####"]
	var zero5: Array[String] = ["00000", "00000", "00000", "00000", "00000"]
	g = _grid(ring, zero5)
	var back := Rules.death_scatter(Vector2i(2, 2), 3, g, "test")
	_check(back == [Vector2i(2, 3), Vector2i(1, 3), Vector2i(3, 3)] and g.soil_total() == 3 and g.pool_total == 0,
		"starved nutrient returns to soil, one point per cell, the cells below first")
	g = _grid(ring, zero5)
	back = Rules.death_scatter(Vector2i(2, 2), 11, g, "test")
	_check(back.size() == 8 and g.soil_total() == 8 and g.pool_total == 3 and g.pool_entries[0].source == "test:no-soil-left",
		"each soil cell takes at most 1; what finds no soil is lost to the floating pool with its source")

	var o11 := Rules.offspring(11)
	var o8 := Rules.offspring(8)
	var o20 := Rules.offspring(20)
	_check(o11.count == 5 and o11.spent == 10 and o11.left == 1 and o8.count == 4 and o8.left == 0
		and o20.count == 5 and o20.left == 10, "offspring = min(5, collected / 2); the rest is reported as left over")


# ------------------------------------------------------------------ single nodes

func _slime_node() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Walled in: it never completes a move, so it never loses HP.
	var g := _grid(["###", "#o#", "###"], ["000", "000", "000"])
	var s := Node2D.new()
	s.set_script(Slime)
	s.setup(g, rng, 1, Vector2i(1, 1), Vector2i.RIGHT, 0)
	for i in 600:
		s.advance(1.0 / 60.0)
	_check(s.hp == Eco.HP_INITIAL and s.total_moves == 0, "standing still costs no HP")
	s.free()

	# A barren corridor: it loses 1 HP every 2 moves, and absorbing heals 1 (capped).
	g = _grid(["#######", "#ooooo#", "#######"], ["0000000", "0000000", "0000000"])
	s = Node2D.new()
	s.set_script(Slime)
	s.setup(g, rng, 2, Vector2i(1, 1), Vector2i.RIGHT, 0)
	var at_moves: Dictionary = {}
	s.arrived.connect(func(x: Node2D) -> void: at_moves[x.total_moves] = x.hp)
	for i in 60 * 21:
		s.advance(1.0 / 60.0)
	_check(at_moves.get(10, -1) == 11 and at_moves.get(20, -1) == 6, "barren corridor: HP 11 after 10 moves, 6 after 20")
	s.free()

	g = _grid(["#######", "#.....#", "#ooooo#", "#######"], ["0000000", "0999990", "0000000", "0000000"])
	s = Node2D.new()
	s.set_script(Slime)
	s.setup(g, rng, 3, Vector2i(1, 2), Vector2i.RIGHT, 0)
	s.hp = Eco.HP_MAX
	var top := [0]
	var absorbed := [0]
	s.ecology_done.connect(func(_x: Node2D, r: Dictionary) -> void: absorbed[0] += 1 if r.action == "absorb" else 0)
	s.arrived.connect(func(x: Node2D) -> void: top[0] = maxi(top[0], x.hp))
	for i in 60 * 9:
		s.advance(1.0 / 60.0)
	_check(absorbed[0] >= 2 and top[0] == Eco.HP_MAX, "absorbing heals 1 HP, never above the maximum (%d absorbs)" % absorbed[0])
	s.free()


func _plant_node() -> void:
	var layout: Array[String] = ["#########", "#.......#", "#.......#", "#.......#", "#...o...#", "#.......#", "#.......#", "#.......#", "#########"]
	var c := Vector2i(4, 4)

	# Plenty of soil around: 6 draws take a bud from 2 to 8 and it blooms.
	var g := _grid(layout, ["000000000", "000000000", "000000000", "000900000", "000000000", "000000000", "000000000", "000000000", "000000000"])
	var p := Node2D.new()
	p.set_script(Plant)
	p.setup(g, c, 2, 0.0, 2)
	var bloom_tick := [-1]
	p.bloomed.connect(func(x: Node2D) -> void: bloom_tick[0] = x.ticks)
	for i in 6:
		p.advance(Eco.STAGE_TICK)
	_check(bloom_tick[0] == 6 and p.stage == Plant.Stage.FLOWER and p.hp == Eco.FLOWER_MAX_HP and p.collected == 8 and g.soil_total() == 3,
		"bud draws 1 per second and blooms on reaching 8")

	# The flower keeps drawing (7x7, capped at 11), loses 4 HP a second and releases on the sixth.
	g.add_nutrient(Vector2i(1, 1), 20)
	var released := [-1, -1]
	p.released.connect(func(x: Node2D, had: int) -> void:
		released[0] = x.ticks
		released[1] = had)
	for i in 8:
		p.advance(Eco.STAGE_TICK)
	_check(released[0] == 12 and released[1] == 11 and p.collected == 0 and not p.alive,
		"flower collects up to 11, lasts six seconds, and hands its collected nutrient over once")
	p.free()

	# Nothing to draw: 1 HP lost every 3 seconds; at 0 HP it withers and hands over what it held.
	g = _grid(layout, ["000000000", "000000000", "000000000", "000000000", "000000000", "000000000", "000000000", "000000000", "000000000"])
	p = Node2D.new()
	p.set_script(Plant)
	p.setup(g, c, 3, 0.0, 3)
	for i in 9:
		p.advance(Eco.STAGE_TICK)
	var hp_after_9: int = p.hp
	var wither := [-1, -1]
	p.withered.connect(func(x: Node2D, had: int) -> void:
		wither[0] = x.ticks
		wither[1] = had)
	for i in 30:
		p.advance(Eco.STAGE_TICK)
	_check(hp_after_9 == Eco.BUD_MAX_HP - 3 and wither[0] == 30 and wither[1] == 3 and p.collected == 0,
		"starving bud loses 1 HP every 3 seconds and withers at 0, handing over what it held once")
	p.free()


# ------------------------------------------------------------------ generated map

func _mapgen() -> void:
	var cols := Eco.GEN_COLS
	var rows := Eco.GEN_ROWS
	var m := MapGen.generate(cols, rows, 12345)
	var lines: Array[String] = m.layout
	var shape_ok := lines.size() == rows and lines[0].length() == cols
	for y in rows:
		for x in cols:
			var ch := lines[y][x]
			var border := x == 0 or y == 0 or x == cols - 1 or y == rows - 1
			var shaft := x == Eco.GEN_ENTRANCE_COL and y >= 1 and y <= Eco.GEN_ENTRANCE_DEPTH
			var want := "#" if border else ("o" if shaft else ".")
			shape_ok = shape_ok and ch == want
	_check(shape_ok, "generated map is %d x %d: rock border, entrance shaft from the top, soil everywhere else" % [cols, rows])

	var again := MapGen.generate(cols, rows, 12345)
	var other := MapGen.generate(cols, rows, 54321)
	_check(again.nutrient == m.nutrient and other.nutrient != m.nutrient, "the same seed gives the same nutrient, another seed a different one")

	var counts := MapGen.scaled_counts((cols - 2) * (rows - 2))
	var soil := 0
	var holding := 0
	var low := 0
	var max_v := 0
	var elevens := 0
	var values: PackedInt32Array = m.nutrient
	for y in rows:
		for x in cols:
			if lines[y][x] != ".":
				continue
			var v := values[y * cols + x]
			soil += 1
			holding += 1 if v > 0 else 0
			low += 1 if v >= 1 and v <= 3 else 0
			max_v = maxi(max_v, v)
			elevens += 1 if v == MapGen.LV2_SEED_VALUE else 0
	_check(m.clusters.size() == counts.clusters and counts.clusters == 3 and counts.lv2 == 2,
		"cluster and level-2 seed counts scale with area from the old 70 x 40 map (%d clusters, %d seeds)" % [counts.clusters, counts.lv2])
	_check(max_v <= MapGen.MAX_INITIAL and elevens == m.lv2.size() and m.lv2.size() <= counts.lv2,
		"no level 3 at the start; level 2 appears only at the seed points (max %d, %d seeds)" % [max_v, m.lv2.size()])
	var share := float(holding) / soil
	_check(share > 0.35 and share < 0.8 and low > holding / 3, "background scatter plus clusters: %d%% of soil holds nutrient, mostly low values" % roundi(share * 100.0))

	var seeds_in_clusters := true
	for p: Vector2i in m.lv2:
		var inside := false
		for c: Dictionary in m.clusters:
			if MapGen._norm_dist(p.x, p.y, c) <= 0.55:
				inside = true
		seeds_in_clusters = seeds_in_clusters and inside
	_check(seeds_in_clusters, "level-2 seed points sit in the dense middle of a cluster")

	# The demo plan can be dug in order from the entrance.
	var g := Grid.new()
	g.load_layout(m.layout)
	g.load_nutrient_values(m.nutrient)
	var plan := MapGen.demo_plan(cols, rows, m.clusters)
	var plan_ok := plan.size() > 20
	for c in plan:
		plan_ok = plan_ok and (g.is_open(c) or g.dig_out(c) >= 0)
	_check(plan_ok, "the demo dig plan (%d cells) can be dug in order from the entrance" % plan.size())

	_check(Soil.tier(0) == 0 and Soil.tier(1) == 1 and Soil.tier(9) == 1 and Soil.tier(10) == 2
		and Soil.tier(16) == 2 and Soil.tier(17) == 3, "soil look bands follow what hatches: 0 / 1-9 / 10-16 / 17+")


func _scene_generated(main: Node) -> void:
	main.load_map("gen", Eco.GEN_SEED)
	var grid: RefCounted = main.grid
	_check(grid.cols == Eco.GEN_COLS and grid.rows == Eco.GEN_ROWS and main.ledger_total() == main.initial_total and main.initial_total > 300,
		"the scene loads the generated map (%d nutrient in the soil)" % main.initial_total)
	main.demo_on = true
	_frame_fail = ""
	_run(main, 200.0)
	var n: Dictionary = main.counts
	_check(_frame_fail == "" and n.born_dug > 5 and n.buds >= 1 and n.blooms >= 1 and n.broods >= 1,
		"200 s of demo on the generated map: every invariant holds and the cycle runs (dug-born %d, buds %d, blooms %d)" % [n.born_dug, n.buds, n.blooms]
		+ ("" if _frame_fail == "" else "  -> " + _frame_fail))
	var before: int = main.initial_total
	main.load_map("gen", 777)
	_check(main.initial_total != before and main.slimes.is_empty() and main.plants.is_empty(), "loading another seed builds a different map and clears every creature")
	main.load_map("gen", Eco.GEN_SEED)
	_check(main.initial_total == before, "loading the default seed again gives the same map")


# ------------------------------------------------------------------ the real scene

func _on_ecology(s: Node2D, res: Dictionary) -> void:
	var last: int = _watched.get(s.uid, 0)
	_events.append({"action": res.action, "gap": s.total_moves - last, "carried": res.carried})
	_watched[s.uid] = s.total_moves
	if res.action == "release":
		for c: Vector2i in res.cells:
			if s.grid.nutrient(c) < 2:
				_frame_fail = "released onto soil that had no nutrient at %s" % c


func _on_arrived(s: Node2D) -> void:
	_visited[s.cell] = true


func _hook(main: Node) -> void:
	for s in main.slimes:
		if not s.ecology_done.is_connected(_on_ecology):
			s.ecology_done.connect(_on_ecology)
			s.arrived.connect(_on_arrived)


func _frame_checks(main: Node) -> void:
	if _frame_fail != "":
		return
	if main.ledger_total() != main.initial_total:
		_frame_fail = "nutrient not conserved at t=%.2f: %d vs %d" % [main.sim_time, main.ledger_total(), main.initial_total]
	var limit: float = main.LANE + main.BROOD_SPREAD_MAX + 0.001
	for s in main.slimes:
		if not main.grid.is_open(Spec.cell_of(s.pos)):
			_frame_fail = "slime %d logical position in a solid cell at t=%.2f" % [s.uid, main.sim_time]
		if s.visible and not main.grid.is_open(Spec.cell_of(s.visual_pos())):
			_frame_fail = "slime %d drawn inside a solid cell at t=%.2f" % [s.uid, main.sim_time]
		var off: Vector2 = (s.visual_pos() - s.pos).abs()
		if maxf(off.x, off.y) > limit:
			_frame_fail = "slime %d visual shift too large at t=%.2f" % [s.uid, main.sim_time]
		if s.carried < 0 or s.carried > Eco.NUTRIENT_CAPACITY:
			_frame_fail = "slime %d carries %d" % [s.uid, s.carried]
		if not s.alive and s.carried != 0:
			_frame_fail = "dead slime %d still carries %d" % [s.uid, s.carried]
	var taken: Dictionary = {}
	for p in main.plants:
		if not p.alive:
			if p.collected != 0:
				_frame_fail = "finished plant at %s still holds %d" % [p.cell, p.collected]
			continue
		if taken.has(p.cell):
			_frame_fail = "two buds or flowers in cell %s at t=%.2f" % [p.cell, main.sim_time]
		taken[p.cell] = true
		if not main.grid.is_open(p.cell):
			_frame_fail = "plant in a solid cell %s" % p.cell
		if p.stage == Plant.Stage.FLOWER and p.collected > Eco.FLOWER_MAX_COLLECT:
			_frame_fail = "flower at %s holds %d" % [p.cell, p.collected]


func _run(main: Node, seconds: float, step := 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		main.sim_advance(step)
		_hook(main)
		_frame_checks(main)
		t += step


func _scene(main: Node) -> void:
	# Soil holding 10 or more no longer hatches a slime (10..16 is kept for the predator).
	main.load_map("small")
	main.grid.add_nutrient(Vector2i(5, 3), 6)
	var ten: int = main.grid.nutrient(Vector2i(5, 3))
	var nine_ok: bool = Eco.SPAWN_MAX_SOIL_NUTRIENT == 9
	_check(ten == 9 and nine_ok, "slimes hatch from soil holding 1..9")
	main.grid.add_nutrient(Vector2i(5, 3), 1)
	_check(main.do_dig(Vector2i(5, 3), true) and main.slimes.is_empty(), "digging soil that holds 10 opens it without hatching a slime")

	main.load_map("small")
	var grid: RefCounted = main.grid
	var total: int = main.initial_total
	_check(total > 0 and grid.soil_total() == total, "scene starts with all nutrient in the soil (%d)" % total)

	_check(not main.do_dig(Vector2i(1, 1)) and not main.do_dig(Vector2i(0, 0)) and not main.do_dig(Vector2i(6, 3)),
		"cannot dig soil away from tunnels, rock, or an open cell")

	var plain := Vector2i(1, 4)
	_check(grid.nutrient(plain) == 0 and main.do_dig(plain) and main.slimes.is_empty() and grid.is_open(plain),
		"digging soil without nutrient opens the cell and hatches nothing")

	var rich := Vector2i(5, 2)         # 4 nutrient, next to the shaft cell (6, 2)
	var before: int = grid.nutrient(rich)
	_check(main.do_dig(rich) and main.slimes.size() == 1 and main.slimes[0].carried == 3 and before == 4
		and main.ledger_total() == total,
		"digging soil with 4 nutrient hatches one slime carrying 3; the last point is scattered, nothing lost")
	_check(main.slimes[0].cell == rich and grid.is_open(rich + main.slimes[0].dir) and main.slimes[0].hp == Eco.HP_INITIAL,
		"the newborn sits in the dug cell, faces an open way and has 16 HP")

	# The scripted demo, checked every frame, long enough for a full generation and more.
	main.do_reset()
	main.demo_on = true
	_events.clear()
	_visited.clear()
	_watched.clear()
	_run(main, 300.0)
	_check(_frame_fail == "", "300 s of demo: ledger, positions, carried amounts and one plant per cell hold every frame" + ("" if _frame_fail == "" else "  -> " + _frame_fail))
	var n: Dictionary = main.counts
	_check(n.buds >= 1 and n.blooms >= 1 and n.broods >= 1 and n.born_brood >= 1,
		"the whole cycle happens: buds %d, blooms %d, broods %d (%d newborns)" % [n.buds, n.blooms, n.broods, n.born_brood])
	_check(n.starved >= 1, "some slimes starved (%d)" % n.starved)
	_check(main.repro_spent == 2 * n.born_brood, "reproduction spent exactly 2 per newborn (%d for %d)" % [main.repro_spent, n.born_brood])

	var absorbs := 0
	var releases := 0
	var min_gap := 99
	for e in _events:
		absorbs += 1 if e.action == "absorb" else 0
		releases += 1 if e.action == "release" else 0
		min_gap = mini(min_gap, e.gap)
	_check(absorbs > 0 and releases > 0, "slimes both absorbed (%d) and released (%d)" % [absorbs, releases])
	_check(min_gap >= Eco.ECOLOGY_COOLDOWN_MOVES, "at least %d completed moves between any two absorb / release actions (min %d)" % [Eco.ECOLOGY_COOLDOWN_MOVES, min_gap])

	var pace_ok := true
	for s in main.slimes:
		if s.alive:
			pace_ok = pace_ok and s.total_moves <= int(s.age) + 1 and s.total_moves >= int(s.age - s.start_delay) - 2
	_check(pace_ok, "pace is one cell per second for every living slime (turning is inside the step)")

	var changed := 0
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			if grid.is_soil(c) and grid.nutrient(c) != int(Eco.NUTRIENT[y][x]):
				changed += 1
	_check(changed > 0, "soil amounts changed through carrying and drawing (%d cells differ from the start)" % changed)

	# Fast-forward sized steps from a fresh start must not break anything either.
	main.do_reset()
	main.demo_on = true
	_frame_fail = ""
	_run(main, 200.0, 0.27)
	_check(_frame_fail == "" and main.counts.blooms >= 1, "fast-forward sized steps keep every invariant through the cycle" + ("" if _frame_fail == "" else "  -> " + _frame_fail))

	# Digging a new branch while the cycle runs changes where slimes go.
	var branch := Vector2i(1, 4)
	_visited.clear()
	_check(main.do_dig(branch), "can dig a new branch while slimes are moving")
	_run(main, 150.0)
	_check(_visited.has(branch) or main.count_alive() == 0, "a slime wandered into the newly dug branch (or none were left alive)")

	main.do_reset()
	var same := true
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			var want: int = Spec.ROCK if Eco.LAYOUT[y][x] == "#" else (Spec.OPEN if Eco.LAYOUT[y][x] == "o" else Spec.SOIL)
			same = same and grid.kind(c) == want and grid.nutrient(c) == (int(Eco.NUTRIENT[y][x]) if want == Spec.SOIL else 0)
	_check(same and main.slimes.is_empty() and main.plants.is_empty() and grid.pool_total == 0 and main.repro_spent == 0
		and grid.soil_total() == total, "reset restores the map and the nutrient and removes every slime, bud and flower")
