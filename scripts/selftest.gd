extends Node
## Scripted behaviour checks. Run with:  --headless --fixed-fps 60 -- --selftest
## Drives the same public actions the buttons call and watches invariants every frame.

const Creature := preload("res://scripts/creature.gd")
const S := Creature.State

var main: Node

var _fails := 0
var _checks := 0
var _seq: Array[int] = []
var _c: Node2D
var _food: Node2D
var _dummy: Node2D
var _prev_x := 0.0
var _prev_hits := 0
var _prev_bites := 3
var _prev_state := 0
var _dead_x := 0.0
var _skip_jump := 2


func _ready() -> void:
	_c = main.creature
	_food = main.food
	_dummy = main.dummy
	_c.state_changed.connect(func(s: int) -> void: _seq.append(s))
	_prev_x = _c.global_position.x
	_run.call_deferred()


func check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[selftest] %s  %s" % ["PASS" if ok else "FAIL", what])


func _inv(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
		print("[selftest] FAIL invariant: %s (state=%s x=%.1f)" % [what, Creature.STATE_NAMES[_c.state], _c.global_position.x])


## Per-frame invariants, whatever the test is doing.
func _process(_delta: float) -> void:
	var st: int = _c.state
	var x: float = _c.global_position.x
	_inv("position is finite and inside the walk range", is_finite(x) and x >= _c.min_x - 0.5 and x <= _c.max_x + 0.5 or st == S.HIDDEN or st == S.SPAWN)
	if st == S.HIDDEN or st == S.SPAWN:
		_skip_jump = 2
	if _skip_jump > 0:
		_skip_jump -= 1
	else:
		_inv("no teleport (%.1f px in one frame)" % absf(x - _prev_x), absf(x - _prev_x) <= 8.0)
	if _dummy.hit_count > _prev_hits:
		_inv("dummy only takes hits during ATTACK", st == S.ATTACK or _prev_state == S.ATTACK)
	if _food.bites_left < _prev_bites:
		_inv("food only shrinks during EAT", st == S.EAT or _prev_state == S.EAT)
	if st == S.DEAD:
		if _prev_state != S.DEAD:
			_dead_x = x
		elif _c.is_dead_settled():
			_inv("settled corpse does not move", is_equal_approx(x, _prev_x))
		_inv("corpse stays within knock distance", absf(x - _dead_x) <= Creature.DEATH_KNOCK + 0.5)
	_prev_x = x
	_prev_hits = _dummy.hit_count
	_prev_bites = _food.bites_left
	_prev_state = st


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
	await _until(func() -> bool: return _c.state == S.IDLE, 8.0)


## Scripted manual-mode tour for visual checks (turning, left-facing actions). Run with -- --tour
func _tour() -> void:
	await _fresh()
	main.do_move(700.0)
	await _until(func() -> bool: return not _c.is_busy(), 15.0)
	await _secs(0.4)
	main.do_eat()  # food is now behind it: turn, walk back, eat facing left
	await _until(func() -> bool: return _food.bites_left == 0 and _c.state == S.IDLE, 20.0)
	main.do_hurt()
	await _secs(1.2)
	main.do_step(-1.0)
	await _until(func() -> bool: return not _c.is_busy(), 15.0)
	main.do_attack()
	await _until(func() -> bool: return _dummy.hit_count == 1 and _c.state == S.IDLE, 20.0)
	main.do_kill()
	await _secs(3.5)
	print("[tour] done, %d invariant failures" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	await _secs(0.2)
	if OS.get_cmdline_user_args().has("--tour"):
		await _tour()
		return

	# 1. Full demo, start to end.
	_seq.clear()
	main.start_demo()
	var ended: bool = await _until(func() -> bool: return main.demo_step == main.Step.END, 60.0)
	check("demo plays through to the end", ended)
	var order: Array[int] = []
	for s in _seq:
		if s != S.IDLE and s != S.TURN and s != S.HIDDEN:
			order.append(s)
	var want: Array[int] = [S.SPAWN, S.MOVE, S.EAT, S.MOVE, S.ATTACK, S.HURT, S.DEAD]
	check("demo state order is spawn>move>eat>move>attack>hurt>dead (got %s)" % str(order), order == want)
	check("food fully eaten in demo", _food.bites_left == 0 and _c.bites_taken == 3)
	check("exactly one attack landed in demo", _dummy.hit_count == 1 and _c.attacks_landed == 1)
	var x0: float = _c.global_position.x
	await _secs(4.0)
	check("demo stays on the ending (no auto loop)", main.demo_step == main.Step.END and _c.state == S.DEAD)
	check("corpse did not move after demo", is_equal_approx(x0, _c.global_position.x))

	# 2. Dead creatures ignore every command.
	main.do_eat(); main.do_attack(); main.do_move(200.0); main.do_hurt(); main.do_kill()
	await _secs(1.5)
	check("dead creature ignores commands", _c.state == S.DEAD and is_equal_approx(x0, _c.global_position.x) and _dummy.hit_count == 1)

	# 3. Replay restores the stage.
	main.start_demo()
	await _secs(0.1)
	check("replay restores food, dummy and creature", _food.bites_left == 3 and _dummy.hit_count == 0 and _c.state == S.SPAWN)

	# 4. Killed mid-meal: no more bites afterwards.
	await _fresh()
	main.do_eat()
	await _until(func() -> bool: return _c.bites_taken >= 1, 15.0)
	await _secs(0.3)
	main.do_kill()
	await _secs(0.5)
	var bites: int = _food.bites_left
	await _secs(3.0)
	check("death during eating stops the meal (bites left %d)" % bites, _c.state == S.DEAD and _food.bites_left == bites and bites == 2)

	# 5. Hurt during attack wind-up: the hit never lands.
	await _fresh()
	main.do_attack()
	await _until(func() -> bool: return _c.state == S.ATTACK, 20.0)
	await _secs(0.15)
	_c.take_hit(_c.global_position.x + 40.0, false)
	await _secs(2.0)
	check("hurt during wind-up cancels the hit", _dummy.hit_count == 0 and _c.state == S.IDLE)

	# 6. New order while eating: leaves between bites, food keeps the rest, attack then lands.
	await _fresh()
	main.do_eat()
	await _until(func() -> bool: return _c.state == S.EAT, 15.0)
	await _secs(0.1)
	main.do_attack()
	await _until(func() -> bool: return _dummy.hit_count == 1, 20.0)
	await _until(func() -> bool: return _c.state == S.IDLE, 5.0)
	check("eat interrupted by attack: one bite taken, attack landed", _food.bites_left == 2 and _dummy.hit_count == 1)

	# 7. Eating with no food left is refused; restock makes it work again.
	await _fresh()
	main.do_eat()
	await _until(func() -> bool: return _food.bites_left == 0 and _c.state == S.IDLE, 20.0)
	var bt: int = _c.bites_taken
	main.do_eat()
	await _secs(1.5)
	check("eat with no food is refused", _c.state == S.IDLE and _c.bites_taken == bt)
	main.do_restock()
	main.do_eat()
	await _until(func() -> bool: return _food.bites_left == 0 and _c.state == S.IDLE, 20.0)
	check("restock allows a second meal", _c.bites_taken == bt + 3)

	# 8. Same button mashed repeatedly.
	await _fresh()
	for i in 30:
		main.do_attack()
		await _secs(0.05)
	await _until(func() -> bool: return not _c.is_busy(), 20.0)
	check("mashing attack does not queue extra attacks (hits %d)" % _dummy.hit_count, _dummy.hit_count >= 1 and _dummy.hit_count <= 3 and _c.state == S.IDLE)

	# 9. Reset mashed during every phase of the demo.
	main.start_demo()
	for i in 25:
		await _secs(randf_range(0.05, 1.6))
		if i % 3 == 0:
			main.do_reset()
		else:
			main.start_demo()
	await _fresh()
	check("stage is clean after reset spam", _c.state == S.IDLE and _food.bites_left == 3 and _dummy.hit_count == 0 and is_equal_approx(_c.global_position.x, main.SPAWN_X))

	# 10. Random input storm; the per-frame invariants do the judging.
	var before := _fails
	seed(12345)
	for i in 400:
		match randi() % 12:
			0, 1: main.do_eat()
			2, 3: main.do_attack()
			4: main.do_hurt()
			5: main.do_move(randf_range(0.0, 1280.0))
			6: main.do_step(-1.0 if randf() < 0.5 else 1.0)
			7: main.do_restock()
			8: main.toggle_zoom()
			9:
				if randf() < 0.25:
					main.do_kill()
			10:
				if randf() < 0.3:
					main.do_reset()
			11:
				if randf() < 0.1:
					main.start_demo()
		await _secs(randf_range(0.02, 0.5))
	check("random input storm kept every invariant", _fails == before)
	await _fresh()
	main.do_eat()
	await _until(func() -> bool: return _food.bites_left == 0 and _c.state == S.IDLE, 20.0)
	check("still fully functional after the storm", _food.bites_left == 0 and _c.state == S.IDLE)

	print("[selftest] %d checks, %d failures" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
