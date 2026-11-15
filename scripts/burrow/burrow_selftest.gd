extends Node
## Scripted checks for the burrow lab. Run with:  --headless --fixed-fps 60 -- --selftest
## Drives the same public actions the buttons and clicks call, and watches invariants on
## every frame (no wall penetration, no teleporting, logic and picture agree).
##
## With `-- --shots --shots-dir=<abs path>` it instead plays the demo in a window and saves
## still frames for visual inspection.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Grub := preload("res://scripts/burrow/grub.gd")
const S := Grub.State

var main: Node

var _fails := 0
var _checks := 0
var _seq: Array[int] = []
var _g: Node2D
var _grid: RefCounted
var _burr: Node2D
var _prev_pos := Vector2.ZERO
var _prev_state := 0
var _prev_hits := 0
var _prev_bites := 0
var _skip := 2
var _dead_pos := Vector2.ZERO
var _worst_wall := 0.0
var _inv_reported: Dictionary = {}


func _ready() -> void:
	_g = main.grub
	_grid = main.grid
	_burr = main.burr
	_g.state_changed.connect(func(s: int) -> void: _seq.append(s))
	_prev_bites = _total_bites()
	_run.call_deferred()


func check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[selftest] %s  %s" % ["PASS" if ok else "FAIL", what])


func _inv(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
		var n: int = _inv_reported.get(what, 0)
		_inv_reported[what] = n + 1
		if n < 4:
			print("[selftest] FAIL invariant: %s (state=%s pos=%s cell=%s)" % [what, Grub.STATE_NAMES[_g.state], str(_g.pos), str(_g.cell)])


func _total_bites() -> int:
	var n := 0
	for f in main.foods:
		n += f.bites_left
	return n


## Deepest any body circle reaches into solid ground, in cells (0 = clean).
func _wall_depth() -> float:
	var worst := 0.0
	for c: Array in _g.rig.body_circles():
		var ctr: Vector2 = c[0]
		var r: float = c[1]
		for i in 12:
			var d := Vector2.from_angle(TAU * i / 12.0)
			if _grid.is_open_at(ctr + d * r):
				continue
			# Walk back toward the centre until we are in the open again.
			var k := 1.0
			while k > 0.0 and not _grid.is_open_at(ctr + d * r * k):
				k -= 0.05
			worst = maxf(worst, r * (1.0 - k))
	return worst


func _process(_delta: float) -> void:
	var st: int = _g.state
	if st == S.HIDDEN:
		_skip = 3
		_prev_state = st
		_prev_hits = _burr.hit_count
		_prev_bites = _total_bites()
		return
	var p: Vector2 = _g.pos
	if st == S.SPAWN and _prev_state != S.SPAWN:
		_skip = 2   # a new grub was placed on the spawn cell; that is not a teleport
	_inv("logical cell is open", _grid.is_open(_g.cell))
	_inv("logical cell is not an item's cell", _grid.blocker_at(_g.cell) == null)
	_inv("thorax point stays inside its logical cell", Rect2(Vector2(_g.cell), Vector2.ONE).grow(0.02).has_point(p))
	if _skip > 0:
		_skip -= 1
	else:
		_inv("no teleport (%.2f cells in one frame)" % p.distance_to(_prev_pos), p.distance_to(_prev_pos) <= 0.12)
	if _g.rig.get("_p").get("body", false):
		var depth := _wall_depth()
		_worst_wall = maxf(_worst_wall, depth)
		_inv("body stays out of the walls (%.3f cells deep)" % depth, depth <= 0.03)
	if _burr.hit_count > _prev_hits:
		_inv("thornpod only takes hits during ATTACK", st == S.ATTACK or _prev_state == S.ATTACK)
	var bites := _total_bites()
	if bites < _prev_bites:
		_inv("food only shrinks during EAT", st == S.EAT or _prev_state == S.EAT)
	if st == S.DEAD:
		if _prev_state != S.DEAD:
			_dead_pos = p
		elif _g.is_dead_settled():
			_inv("settled corpse does not move", p.is_equal_approx(_prev_pos))
		_inv("corpse stays within knock distance", p.distance_to(_dead_pos) <= Grub.DEATH_KNOCK + 0.02)
	_prev_pos = p
	_prev_state = st
	_prev_hits = _burr.hit_count
	_prev_bites = bites


func _secs(t: float) -> void:
	var left := t
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await get_tree().process_frame
		left -= get_process_delta_time()
	return cond.call()


func _fresh() -> void:
	main.do_reset()
	await _until(func() -> bool: return _g.state == S.IDLE, 8.0)


func _idle() -> bool:
	return _g.state == S.IDLE and _g.goal == Grub.Goal.NONE


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _run() -> void:
	await _secs(0.2)
	if OS.get_cmdline_user_args().has("--shots"):
		await _shots()
		return

	# 1. Full demo, start to end.
	_seq.clear()
	main.start_demo()
	var ended: bool = await _until(func() -> bool: return main.demo_step == main.Step.END, 90.0)
	check("demo plays through to the end", ended)
	var order: Array[int] = []
	for s in _seq:
		if s != S.IDLE and s != S.HIDDEN and (order.is_empty() or order[order.size() - 1] != s):
			order.append(s)
	var want: Array[int] = [S.SPAWN, S.MOVE, S.EAT, S.MOVE, S.ATTACK, S.HURT, S.DEAD]
	check("demo state order is spawn>move>eat>move>attack>hurt>dead (got %s)" % str(order), order == want)
	check("first food fully eaten, sac full", main.foods[0].bites_left == 0 and _g.bites_taken == 3 and _g.sac_level == 3)
	check("exactly one attack landed", _burr.hit_count == 1 and _g.attacks_landed == 1)
	check("demo dug its tunnel", _grid.is_open(Spec.DEMO_DIG[0]))
	var p0: Vector2 = _g.pos
	await _secs(4.0)
	check("demo stays on the ending (no auto loop)", main.demo_step == main.Step.END and _g.state == S.DEAD)
	check("corpse did not move after the demo", p0.is_equal_approx(_g.pos))

	# 2. Dead creatures ignore every command.
	main.do_eat(); main.do_attack(); main.do_move(Vector2i(9, 4)); main.do_hurt(); main.do_kill()
	await _secs(1.5)
	check("dead grub ignores commands", _g.state == S.DEAD and p0.is_equal_approx(_g.pos) and _burr.hit_count == 1)

	# 3. Replay restores map, items and creature.
	main.start_demo()
	await _secs(0.1)
	check("replay restores map, food, thornpod and grub",
		_grid.kind(Spec.DEMO_DIG[0]) == Spec.SOIL and _total_bites() == 6 and _burr.hit_count == 0 and _g.state == S.SPAWN and _g.sac_level == 0)

	# 4. Digging rules.
	await _fresh()
	check("rock cannot be dug", not main.do_dig(Vector2i(0, 0)) and not main.do_dig(Vector2i(5, 5)))
	check("soil away from any tunnel cannot be dug", not main.do_dig(Vector2i(14, 2)))
	check("open cells cannot be dug", not main.do_dig(Vector2i(9, 4)))

	# 5. Reachability before and after digging.
	main.do_attack()
	await _secs(1.0)
	check("thornpod is unreachable before digging: order refused", _idle() and _g.cell == Spec.SPAWN_CELL)
	check("soil next to a tunnel can be dug", main.do_dig(Vector2i(10, 6)))
	main.do_attack()
	var hit: bool = await _until(func() -> bool: return _burr.hit_count == 1 and _idle(), 40.0)
	check("after digging the grub walks through the new cell and the attack lands", hit and _g.cell == Vector2i(13, 6))

	# 6. A freshly dug vertical shortcut is used at once.
	main.do_dig(Vector2i(12, 5))
	main.do_move(Vector2i(12, 4))
	var there: bool = await _until(func() -> bool: return _idle() and _g.cell == Vector2i(12, 4), 20.0)
	check("freshly dug vertical cell is walkable", there)
	main.do_reset()
	await _secs(0.1)
	check("reset closes dug cells again", _grid.kind(Vector2i(10, 6)) == Spec.SOIL and _grid.kind(Vector2i(12, 5)) == Spec.SOIL)

	# 7. Killed mid-meal: no more bites afterwards.
	await _fresh()
	main.do_eat()
	await _until(func() -> bool: return _g.bites_taken >= 1, 40.0)
	await _secs(0.3)
	main.do_kill()
	await _secs(0.5)
	var bites: int = _total_bites()
	await _secs(3.0)
	check("death during eating stops the meal (bites left %d)" % bites, _g.state == S.DEAD and _total_bites() == bites and bites == 5)

	# 8. Hurt during attack wind-up: the hit never lands.
	await _fresh()
	main.do_dig(Vector2i(10, 6))
	main.do_attack()
	await _until(func() -> bool: return _g.state == S.ATTACK, 40.0)
	await _secs(0.15)
	_g.take_hit(false)
	await _secs(2.0)
	check("hurt during wind-up cancels the hit", _burr.hit_count == 0 and _g.state == S.IDLE)

	# 9. New order while eating: leaves between bites, food keeps the rest.
	await _fresh()
	main.do_eat()
	await _until(func() -> bool: return _g.state == S.EAT, 40.0)
	await _secs(0.4)
	main.do_move(Vector2i(6, 4))
	var moved: bool = await _until(func() -> bool: return _idle() and _g.cell == Vector2i(6, 4), 20.0)
	check("eat interrupted by a move order: one bite taken, then it walks off", moved and main.foods[0].bites_left == 2 and _g.sac_level == 1)

	# 10. Eating with nothing left is refused; restock makes it work again.
	main.do_eat()
	await _until(func() -> bool: return main.foods[0].bites_left == 0 and _idle(), 30.0)
	var bt: int = _g.bites_taken
	_g.command_eat(main.foods[0])
	await _secs(1.5)
	check("eating an empty cluster is refused", _idle() and _g.bites_taken == bt)
	main.do_restock()
	_g.command_eat(main.foods[0])
	await _until(func() -> bool: return main.foods[0].bites_left == 0 and _idle(), 30.0)
	check("restock allows another meal; sac caps at capacity", _g.bites_taken == bt + 3 and _g.sac_level == Grub.SAC_CAPACITY)

	# 11. Walk a tour through every kind of place: chamber, dead ends, crossing, corners.
	await _fresh()
	var tour_ok := true
	for c: Vector2i in [Vector2i(4, 2), Vector2i(2, 6), Vector2i(9, 7), Vector2i(12, 4), Vector2i(9, 3), Vector2i(6, 5), Vector2i(2, 2), Vector2i(4, 3)]:
		main.do_move(c)
		var ok: bool = await _until(func() -> bool: return _idle() and _g.cell == c, 30.0)
		if not ok:
			tour_ok = false
			print("[selftest]   did not reach %s (at %s)" % [str(c), str(_g.cell)])
	check("tour of chamber, corridors, crossing and dead ends reaches every stop", tour_ok)

	# 12. Rapid re-targeting while moving (reversals in narrow tunnels).
	seed(777)
	var open_cells: Array[Vector2i] = []
	for y in _grid.rows:
		for x in _grid.cols:
			if _grid.area_free(Vector2i(x, y)):
				open_cells.append(Vector2i(x, y))
	var before := _fails
	for i in 160:
		main.do_move(open_cells[randi() % open_cells.size()])
		await _secs(randf_range(0.03, 0.7))
	await _until(_idle, 30.0)
	check("160 rapid re-targets: no wall penetration, no teleport", _fails == before and _idle())

	# 13. Same button mashed repeatedly.
	await _fresh()
	main.do_dig(Vector2i(10, 6))
	for i in 30:
		main.do_attack()
		await _secs(0.05)
	await _until(_idle, 40.0)
	check("mashing attack does not pile up attacks (hits %d)" % _burr.hit_count, _burr.hit_count >= 1 and _burr.hit_count <= 2)

	# 14. Reset mashed during every phase of the demo.
	main.start_demo()
	for i in 30:
		await _secs(randf_range(0.05, 2.5))
		if i % 3 == 0:
			main.do_reset()
		else:
			main.start_demo()
	await _fresh()
	check("stage is clean after reset spam", _g.state == S.IDLE and _total_bites() == 6 and _burr.hit_count == 0
		and _g.cell == Spec.SPAWN_CELL and _grid.kind(Vector2i(10, 6)) == Spec.SOIL)

	# 15. Random input storm with digging; the per-frame invariants do the judging.
	before = _fails
	seed(12345)
	for i in 500:
		match randi() % 14:
			0, 1: main.do_eat()
			2, 3: main.do_attack()
			4: main.do_hurt()
			5, 6, 7: main.do_click(Vector2i(randi() % _grid.cols, randi() % _grid.rows))
			8: main.do_move(open_cells[randi() % open_cells.size()])
			9: main.do_restock()
			10: main.toggle_zoom()
			11:
				if randf() < 0.2:
					main.do_kill()
			12:
				if randf() < 0.25:
					main.do_reset()
			13:
				if randf() < 0.1:
					main.start_demo()
		await _secs(randf_range(0.02, 0.5))
	check("random input storm (500 inputs, with digging) kept every invariant", _fails == before)
	await _fresh()
	main.do_eat()
	await _until(func() -> bool: return main.foods[0].bites_left == 0 and _idle(), 40.0)
	check("still fully functional after the storm", main.foods[0].bites_left == 0 and _idle())

	print("[selftest] deepest wall overlap seen: %.3f cells" % _worst_wall)
	print("[selftest] %d checks, %d failures" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ------------------------------------------------------------------ still frames

func _grab(path: String, around_grub: bool) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if around_grub:
		var sz := 192
		var scale := float(img.get_width()) / 1280.0
		var c: Vector2 = (main.MAP_ORIGIN + _g.pos * Spec.CELL_PX) * scale
		var r := Rect2i(int(c.x - sz * scale * 0.5), int(c.y - sz * scale * 0.5), int(sz * scale), int(sz * scale))
		r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		img = img.get_region(r)
	img.save_png(path)


func _shots() -> void:
	var dir := _arg("--shots-dir=")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://deliverables/burrow_screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var manual := OS.get_cmdline_user_args().has("--manual-tour")
	if manual:
		main.do_reset()
		_manual_tour.call_deferred()
	else:
		main.start_demo()
	var t := 0.0
	var next_crop := 0.0
	var next_full := 0.5
	var n := 0
	var m := 0
	while t < 120.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _done:
			break
		if not manual and main.demo_step == main.Step.END and _g.is_dead_settled():
			_done = true
		if t >= next_crop:
			next_crop += 0.1
			await _grab("%s/c_%04d_s%02d.png" % [dir, n, main.demo_step], true)
			n += 1
		if t >= next_full:
			next_full += 1.0
			await _grab("%s/full_%03d_s%02d.png" % [dir, m, main.demo_step], false)
			m += 1
	await _secs(0.5)
	await _grab("%s/full_%03d_end.png" % [dir, m], false)
	print("[shots] saved %d crops and %d full frames to %s" % [n, m + 1, dir])
	get_tree().quit(0)


var _done := false


## Manual-mode situations the demo does not show.
func _manual_tour() -> void:
	await _until(func() -> bool: return _g.state == S.IDLE, 8.0)
	main.toggle_grid()
	main.do_move(Vector2i(4, 2))
	await _until(_idle, 20.0)
	main.do_move(Vector2i(2, 6))
	await _until(_idle, 20.0)
	main.toggle_grid()
	main.do_dig(Vector2i(10, 6))
	main.do_dig(Vector2i(11, 5))
	main.do_dig(Vector2i(11, 4 + 1))
	_g.command_eat(main.foods[1])   # second cluster: eaten from above, facing down
	await _until(func() -> bool: return main.foods[1].bites_left == 0 and _idle(), 60.0)
	main.do_hurt()
	await _secs(1.2)
	main.do_move(Vector2i(9, 7))    # dead end, then straight back out
	await _until(_idle, 20.0)
	main.do_move(Vector2i(12, 4))
	await _secs(1.6)
	main.do_move(Vector2i(6, 5))    # reversal in the middle of a corridor
	await _until(_idle, 20.0)
	main.do_kill()
	await _secs(3.0)
	_done = true
