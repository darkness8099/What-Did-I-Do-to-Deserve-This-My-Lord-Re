extends RefCounted
## Headless checks for the minimal ecology slice. Run with:
##   godot --headless --path . res://scenes/eco_lab.tscn -- --selftest
## It calls the pure rules directly, then drives the real scene with fixed time steps and
## checks invariants every frame. It cannot judge how anything looks.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Grid := preload("res://scripts/eco/eco_grid.gd")

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
	_scene(main)
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


# ------------------------------------------------------------------ the real scene

func _on_ecology(s: Node2D, res: Dictionary) -> void:
	var last: int = _watched.get(s.uid, 0)
	_events.append({"action": res.action, "gap": s.total_moves - last, "carried": res.carried})
	_watched[s.uid] = s.total_moves
	if res.action == "release":
		for c: Vector2i in res.cells:
			if s.grid.nutrient(c) < 2:
				_frame_fail = "released onto soil that had no nutrient at %s" % c


func _on_stepped(s: Node2D) -> void:
	_visited[s.cell] = true


func _hook(main: Node) -> void:
	for s in main.slimes:
		if not s.ecology_done.is_connected(_on_ecology):
			s.ecology_done.connect(_on_ecology)
			s.stepped.connect(_on_stepped)


func _frame_checks(main: Node) -> void:
	if _frame_fail != "":
		return
	var total: int = main.grid.soil_total() + main.carried_total() + main.grid.pool_total
	if total != main.initial_total:
		_frame_fail = "nutrient not conserved at t=%.2f: %d vs %d" % [main.sim_time, total, main.initial_total]
	for s in main.slimes:
		if not main.grid.is_open(Spec.cell_of(s.pos)):
			_frame_fail = "slime %d logical position in a solid cell at t=%.2f" % [s.uid, main.sim_time]
		if not main.grid.is_open(Spec.cell_of(s.visual_pos())):
			_frame_fail = "slime %d drawn inside a solid cell at t=%.2f" % [s.uid, main.sim_time]
		var off: Vector2 = (s.visual_pos() - s.pos).abs()
		if maxf(off.x, off.y) > main.LANE + 0.001:
			_frame_fail = "slime %d visual shift too large" % s.uid
		if s.carried < 0 or s.carried > Eco.NUTRIENT_CAPACITY:
			_frame_fail = "slime %d carries %d" % [s.uid, s.carried]


func _run(main: Node, seconds: float, step := 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		main.sim_advance(step)
		_hook(main)
		_frame_checks(main)
		t += step


func _scene(main: Node) -> void:
	var grid: RefCounted = main.grid
	main.do_reset()
	var total: int = main.initial_total
	_check(total > 0 and grid.soil_total() == total, "scene starts with all nutrient in the soil (%d)" % total)

	_check(not main.do_dig(Vector2i(1, 1)) and not main.do_dig(Vector2i(0, 0)) and not main.do_dig(Vector2i(6, 3)),
		"cannot dig soil away from tunnels, rock, or an open cell")

	var plain := Vector2i(11, 4)
	_check(grid.nutrient(plain) == 0 and main.do_dig(plain) and main.slimes.is_empty() and grid.is_open(plain),
		"digging soil without nutrient opens the cell and hatches nothing")

	var rich := Vector2i(5, 2)         # 4 nutrient, next to the shaft cell (6, 2)
	var before: int = grid.nutrient(rich)
	_check(main.do_dig(rich) and main.slimes.size() == 1 and main.slimes[0].carried == 3 and before == 4
		and grid.soil_total() + main.carried_total() + grid.pool_total == total,
		"digging soil with 4 nutrient hatches one slime carrying 3; the last point is scattered, nothing lost")
	_check(main.slimes[0].cell == rich and grid.is_open(rich + main.slimes[0].dir), "the newborn sits in the dug cell and faces an open way")

	# Free play with the scripted digs, checked every frame.
	main.do_reset()
	main.demo_on = true
	_events.clear()
	_visited.clear()
	_watched.clear()
	_run(main, 90.0)
	_check(_frame_fail == "", "90 s of demo: conservation, positions and carried amounts hold every frame" + ("" if _frame_fail == "" else "  -> " + _frame_fail))
	_check(main.slimes.size() >= 4, "several slimes are alive together (%d)" % main.slimes.size())

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
		pace_ok = pace_ok and s.total_moves <= int(main.sim_time) + 1 and s.total_moves >= 60
	_check(pace_ok, "pace is one cell per second (turning is inside the step, not extra)")

	var changed := 0
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			if grid.is_soil(c) and grid.nutrient(c) != int(Eco.NUTRIENT[y][x]):
				changed += 1
	_check(changed > 0, "soil amounts changed through carrying (%d cells differ from the start)" % changed)

	# Digging changes routes: open a new dead-end branch and see it get visited.
	var branch := Vector2i(11, 4)
	_visited.clear()
	_check(main.do_dig(branch), "can dig a new branch while slimes are moving")
	_run(main, 120.0)
	_check(_visited.has(branch) and _frame_fail == "", "a slime wandered into the newly dug branch")

	# Large time steps (fast-forward) must not break anything.
	_run(main, 40.0, 0.27)
	_check(_frame_fail == "", "fast-forward sized steps keep every invariant" + ("" if _frame_fail == "" else "  -> " + _frame_fail))

	main.do_reset()
	var same := true
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			var want: int = Spec.ROCK if Eco.LAYOUT[y][x] == "#" else (Spec.OPEN if Eco.LAYOUT[y][x] == "o" else Spec.SOIL)
			same = same and grid.kind(c) == want and grid.nutrient(c) == (int(Eco.NUTRIENT[y][x]) if want == Spec.SOIL else 0)
	_check(same and main.slimes.is_empty() and grid.pool_total == 0 and grid.soil_total() == total, "reset restores the map, the nutrient and removes every slime")
