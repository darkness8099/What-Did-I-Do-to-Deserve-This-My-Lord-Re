extends Node2D
## Ecology test (tasks ECO-001, ECO-002): dig nutrient soil, slimes hatch, wander by rule,
## carry nutrient between soil blocks, weaken, bud, bloom and release a new brood.
## See eco_spec.gd for the rules and numbers.
##
## Nutrient ledger, checked by the self-test every frame:
##   soil + carried by crawlers + collected by buds and flowers + floating pool
##   + spent on reproduction = the amount the map started with.
##
## Mouse: left click a soil block next to a tunnel to dig it.
## Keys:  Space demo digs, R reset, F fast-forward, P pause, G numbers and cells,
##        Z view size (64 / 48 / 83 px per cell), Esc quit.
## CLI (after `--`): --demo, --grid, --small, --zoom, --seed=<n>, --selftest, --log,
##        --quit-after=<s> (run the demo for s seconds of simulation, print the ledger, quit),
##        --shots=<dir> (run the demo, save stills, quit; optional --shots-from=<s>,
##        --shots-step=<s>, --shots-count=<n>; default one per second for 30 s).

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Grid := preload("res://scripts/eco/eco_grid.gd")
const MapScript := preload("res://scripts/burrow/burrow_map.gd")
const SoilScript := preload("res://scripts/eco/eco_soil.gd")
const FxScript := preload("res://scripts/eco/eco_fx.gd")
const Slime := preload("res://scripts/eco/slime.gd")
const Plant := preload("res://scripts/eco/plant.gd")
const SelfTest := preload("res://scripts/eco/eco_selftest.gd")

const WORLD_POS := Vector2(96, 46)
const VIEW_ZOOM: Array[float] = [1.0, 0.75, 1.3]
const VIEW_NAME: Array[String] = ["默认 64 px/格", "小一档 48 px/格", "放大 83 px/格"]
const FAST := 4.0
const LANE := 0.12                 ## cells; sideways visual shift when two slimes overlap
const BROOD_SPREAD_MAX := 0.44     ## cells; how far a newborn may sit from its cell centre
const C_SOIL_CHIP := Color("7a5a40")

var grid: RefCounted
var rng := RandomNumberGenerator.new()
var slimes: Array[Node2D] = []      ## crawlers, including ones still dissolving after starving
var plants: Array[Node2D] = []      ## buds and flowers, including ones still playing their end
var repro_spent := 0                ## nutrient turned into new slimes
var counts := {"born_dug": 0, "born_brood": 0, "buds": 0, "blooms": 0, "broods": 0, "starved": 0, "withered": 0}
var sim_time := 0.0
var initial_total := 0
var show_grid := false
var paused := false
var fast := false
var view := 0
var demo_on := false
var seed_value := 20261117

var map: Node2D
var soil: Node2D
var fx: Node2D

var _world: Node2D
var _units: Node2D
var _plants: Node2D
var _debug: Node2D
var _camera: Camera2D
var _stats: Label
var _notice: Label
var _view_label: Label
var _notice_t := 0.0
var _demo_i := 0
var _next_uid := 1
var _shots_dir := ""
var _shot_n := 0
var _shot_step := 1.0
var _shot_from := 0.0
var _shot_count := 31
var _selftest := false
var _log := false
var _quit_after := -1.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--grid":
			show_grid = true
		elif a == "--small":
			view = 1
		elif a == "--zoom":
			view = 2
		elif a == "--demo":
			demo_on = true
		elif a == "--log":
			_log = true
		elif a.begins_with("--quit-after="):
			_quit_after = float(a.trim_prefix("--quit-after="))
			demo_on = true
		elif a == "--selftest":
			_selftest = true
		elif a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
		elif a.begins_with("--shots-step="):
			_shot_step = float(a.trim_prefix("--shots-step="))
		elif a.begins_with("--shots-from="):
			_shot_from = float(a.trim_prefix("--shots-from="))
		elif a.begins_with("--shots-count="):
			_shot_count = int(a.trim_prefix("--shots-count="))
		elif a.begins_with("--shots="):
			_shots_dir = a.trim_prefix("--shots=")
			demo_on = true

	grid = Grid.new()
	grid.load_layout(Eco.LAYOUT)
	grid.load_nutrient(Eco.NUTRIENT)
	initial_total = grid.soil_total()
	rng.seed = seed_value

	_world = Node2D.new()
	_world.position = WORLD_POS
	add_child(_world)
	map = Node2D.new()
	map.set_script(MapScript)
	_world.add_child(map)
	map.setup(grid)
	soil = Node2D.new()
	soil.set_script(SoilScript)
	_world.add_child(soil)
	soil.setup(grid)
	# Buds and flowers stand behind crawlers, so a crawler passing through stays visible.
	_plants = Node2D.new()
	_world.add_child(_plants)
	_units = Node2D.new()
	_units.y_sort_enabled = true
	_world.add_child(_units)
	fx = Node2D.new()
	fx.set_script(FxScript)
	fx.z_index = 20
	_world.add_child(fx)
	_debug = Node2D.new()
	_debug.z_index = 30
	_debug.draw.connect(_draw_debug)
	_world.add_child(_debug)

	_camera = Camera2D.new()
	add_child(_camera)
	_build_hud()
	_apply_view()

	if _selftest:
		_run_selftest.call_deferred()


func _run_selftest() -> void:
	var failures: int = SelfTest.new().run(self)
	get_tree().quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ actions

func do_reset() -> void:
	fx.clear()
	for s in slimes:
		s.queue_free()
	slimes.clear()
	for p in plants:
		p.queue_free()
	plants.clear()
	repro_spent = 0
	for k: String in counts:
		counts[k] = 0
	grid.reset()
	rng.seed = seed_value
	sim_time = 0.0
	_demo_i = 0
	demo_on = false
	_next_uid = 1
	_say("已重置")


func start_demo() -> void:
	do_reset()
	demo_on = true
	_say("自动演示：依次挖开几块含养分的土")


## Dig a soil block. Returns true if it was dug.
func do_dig(c: Vector2i) -> bool:
	if not grid.can_dig(c):
		if grid.in_bounds(c) and grid.kind(c) == Spec.SOIL:
			_say("只能挖与通道相邻的土块")
		return false
	var had: int = grid.dig_out(c)
	var at := Spec.center(c) * Spec.CELL_PX
	map.flash_cell(c)
	fx.chips(at, C_SOIL_CHIP)
	var leftover := had
	if had > 0 and had <= Eco.SPAWN_MAX_SOIL_NUTRIENT:
		var take := mini(had, Eco.NUTRIENT_CAPACITY)
		leftover = had - take
		_spawn(c, take)
		_say("养分 %d 的土块：史莱姆出生，带走 %d 点%s" % [had, take, "，其余散到周围" if leftover > 0 else ""])
	elif had > 0:
		_say("养分 %d 的土块过于肥沃，不出生基础史莱姆，养分散到周围" % had)
	if leftover > 0:
		var got := Rules.scatter(c, leftover, grid, "dig-leftover(%d,%d)" % [c.x, c.y])
		for i in got.size():
			var to_cell := got[i]
			soil.hide_incoming(to_cell)
			var to_px := Spec.center(to_cell) * Spec.CELL_PX
			fx.mote(at, func() -> Vector2: return to_px, 0.5, func() -> void: soil.reveal(to_cell), 0.06 * i)
	return true


func _open_ways(c: Vector2i) -> Array[Vector2i]:
	var ways: Array[Vector2i] = []
	for d in Spec.DIRS:
		if grid.is_open(c + d):
			ways.append(d)
	return ways


func _new_slime(c: Vector2i) -> Node2D:
	var s := Node2D.new()
	s.set_script(Slime)
	_units.add_child(s)
	return s


func _wire_slime(s: Node2D) -> void:
	s.ecology_done.connect(_on_ecology)
	s.arrived.connect(_on_arrived)
	s.gone.connect(_on_slime_gone)
	slimes.append(s)


func _spawn(c: Vector2i, nutrient: int) -> void:
	# Old code picked any of the four directions; here it faces a way it can actually go.
	var ways := _open_ways(c)
	var facing: Vector2i = ways[rng.randi_range(0, ways.size() - 1)] if not ways.is_empty() else Vector2i.RIGHT
	var s := _new_slime(c)
	s.setup(grid, rng, _next_uid, c, facing, nutrient)
	_next_uid += 1
	_wire_slime(s)
	counts.born_dug += 1
	fx.ring(Spec.center(c) * Spec.CELL_PX, Color("bdec7c"), 8.0, 30.0, 0.4)


## Pixel position of a slime for a mote in flight, or `fallback` once it is gone.
## Motes hold a weak reference: a slime may root into a bud while a mote flies to it.
func _px_of(ref: WeakRef, fallback: Vector2) -> Vector2:
	var s: Node2D = ref.get_ref()
	return s.position if s != null and s.is_inside_tree() else fallback


func _on_ecology(s: Node2D, res: Dictionary) -> void:
	var cells: Array[Vector2i] = res.cells
	if _log:
		print("[eco] t=%.2f slime %d at %s %s %s -> carries %d" % [sim_time, s.uid, s.cell, res.action, cells, res.carried])
	if res.action == "absorb":
		# The dot leaves the soil at once and flies to the slime; the back spot appears on arrival.
		var c := cells[0]
		var from: Vector2 = soil.dot_pos(c, grid.nutrient(c))
		var now_carried: int = res.carried
		fx.ring(from, Color("f8e68c"), 3.0, 12.0, 0.25)
		var land := Spec.center(s.cell) * Spec.CELL_PX
		var ref: WeakRef = weakref(s)
		fx.mote(from, func() -> Vector2: return _px_of(ref, land), 0.45, func() -> void:
			var live: Node2D = ref.get_ref()
			if live != null and live.alive:
				live.set_shown(now_carried, true)
			fx.ring(_px_of(ref, land), Color("f8e68c"), 6.0, 20.0, 0.3))
	elif res.action == "release":
		# The spots leave the back at once; each point lands in its soil block a moment later.
		s.set_shown(res.carried, false)
		for i in cells.size():
			var c := cells[i]
			soil.hide_incoming(c)
			var to_px: Vector2 = soil.dot_pos(c, grid.nutrient(c) - 1)
			fx.mote(s.position, func() -> Vector2: return to_px, 0.45, func() -> void:
				soil.reveal(c)
				fx.ring(to_px, Color("f8e68c"), 3.0, 12.0, 0.25), 0.1 * i)


# ------------------------------------------------------------------ life cycle

func plant_at(c: Vector2i) -> Node2D:
	for p in plants:
		if p.alive and p.cell == c:
			return p
	return null


func _on_arrived(s: Node2D) -> void:
	match Rules.crawler_fate(s.hp, s.carried, plant_at(s.cell) != null):
		"bud": _make_bud(s)
		"starve": _starve(s)


## Weak, but carrying enough: it roots where it stands. What it carried becomes the bud's
## collected nutrient, and the crawler no longer holds it (settled exactly once).
func _make_bud(s: Node2D) -> void:
	var p := Node2D.new()
	p.set_script(Plant)
	_plants.add_child(p)
	p.setup(grid, s.cell, s.carried, s.angle(), s.shown_nutrient)
	p.drew.connect(_on_plant_drew)
	p.bloomed.connect(_on_bloomed)
	p.withered.connect(_on_withered)
	p.released.connect(_on_released)
	p.gone.connect(_on_plant_gone)
	plants.append(p)
	if _log:
		print("[eco] t=%.2f slime %d buds at %s with %d" % [sim_time, s.uid, s.cell, s.carried])
	s.carried = 0
	s.alive = false
	slimes.erase(s)
	s.queue_free()
	counts.buds += 1


## Out of HP without enough nutrient: what it carried leaves for the floating pool.
func _starve(s: Node2D) -> void:
	var had: int = s.carried
	grid.pool_deposit(had, "starvation(slime %d at %d,%d)" % [s.uid, s.cell.x, s.cell.y])
	if had > 0:
		fx.drift(s.position, had)
	if _log:
		print("[eco] t=%.2f slime %d starves at %s carrying %d" % [sim_time, s.uid, s.cell, had])
	s.starve()
	counts.starved += 1


func _on_slime_gone(s: Node2D) -> void:
	slimes.erase(s)
	s.queue_free()


func _on_plant_drew(p: Node2D, from: Vector2i) -> void:
	var at: Vector2 = soil.dot_pos(from, grid.nutrient(from))
	fx.ring(at, Color("f8e68c"), 3.0, 12.0, 0.25)
	var head: Vector2 = p.head_px()
	var ref: WeakRef = weakref(p)
	fx.mote(at, func() -> Vector2: return head, 0.5, func() -> void:
		var live: Node2D = ref.get_ref()
		if live != null:
			live.gulp()
		fx.ring(head, Color("f8e68c"), 5.0, 16.0, 0.25))


func _on_bloomed(p: Node2D) -> void:
	var head: Vector2 = p.head_px()
	fx.chips(head, Color("f0508f"), 10)
	fx.ring(head, Color("f0508f"), 8.0, 34.0, 0.45)
	counts.blooms += 1
	if _log:
		print("[eco] t=%.2f bloom at %s" % [sim_time, p.cell])


## A bud that starved: its collected nutrient leaves for the floating pool.
func _on_withered(p: Node2D, had: int) -> void:
	grid.pool_deposit(had, "bud-wither(%d,%d)" % [p.cell.x, p.cell.y])
	fx.drift(p.head_px(), had)
	counts.withered += 1
	if _log:
		print("[eco] t=%.2f bud withers at %s holding %d" % [sim_time, p.cell, had])


## A flower at the end of its life: its collected nutrient becomes a brood; the leftover
## goes where Eco.REMAINDER_TO_POOL says.
func _on_released(p: Node2D, had: int) -> void:
	var o := Rules.offspring(had)
	repro_spent += o.spent
	var head: Vector2 = p.head_px()
	if o.left > 0:
		if Eco.REMAINDER_TO_POOL:
			grid.pool_deposit(o.left, "flower-remainder(%d,%d)" % [p.cell.x, p.cell.y])
			fx.drift(head, o.left)
		else:
			var got := Rules.scatter(p.cell, o.left, grid, "flower-remainder(%d,%d)" % [p.cell.x, p.cell.y])
			for c in got:
				soil.hide_incoming(c)
				var to_px := Spec.center(c) * Spec.CELL_PX
				fx.mote(head, func() -> Vector2: return to_px, 0.5, func() -> void: soil.reveal(c))
	var ways := _open_ways(p.cell)
	var per_way: Dictionary = {}
	for i in o.count:
		var facing: Vector2i = ways[rng.randi_range(0, ways.size() - 1)] if not ways.is_empty() else Vector2i.RIGHT
		var appear: float = 0.25 + 0.09 * i
		# Each waits a random 0..SPAWN_DELAY_MAX after it has popped out, so they leave one by one.
		var wait: float = appear + Slime.APPEAR_SECONDS + rng.randf_range(0.0, Eco.SPAWN_DELAY_MAX)
		# Spill out along the way each one will go, one behind the other.
		var k: int = per_way.get(facing, 0)
		per_way[facing] = k + 1
		var fan := Vector2(facing) * minf(0.24 + 0.1 * k, BROOD_SPREAD_MAX)
		var s := _new_slime(p.cell)
		s.setup_brood(grid, rng, _next_uid, p.cell, facing, wait, appear, fan)
		_next_uid += 1
		_wire_slime(s)
		counts.born_brood += 1
	counts.broods += 1
	fx.chips(head, Color("f0508f"), 8)
	if _log:
		print("[eco] t=%.2f flower at %s releases %d (collected %d, left %d)" % [sim_time, p.cell, o.count, had, o.left])


func _on_plant_gone(p: Node2D) -> void:
	plants.erase(p)
	p.queue_free()


# ------------------------------------------------------------------ simulation

func carried_total() -> int:
	var sum := 0
	for s in slimes:
		sum += s.carried
	return sum


func collected_total() -> int:
	var sum := 0
	for p in plants:
		sum += p.collected
	return sum


## Everything the ledger can account for; equals initial_total when nothing is lost.
func ledger_total() -> int:
	return grid.soil_total() + carried_total() + collected_total() + grid.pool_total + repro_spent


func count_alive(stage := -1) -> int:
	var n := 0
	if stage < 0:
		for s in slimes:
			n += 1 if s.alive else 0
		return n
	for p in plants:
		n += 1 if p.alive and p.stage == stage else 0
	return n


func sim_advance(delta: float) -> void:
	sim_time += delta
	while demo_on and _demo_i < Eco.DEMO_DIGS.size() and sim_time >= Eco.DEMO_DIGS[_demo_i][0]:
		do_dig(Eco.DEMO_DIGS[_demo_i][1])
		_demo_i += 1
	for s in slimes.duplicate():
		s.advance(delta)
	for p in plants.duplicate():
		p.advance(delta)
	# Slimes pass through each other; when two overlap, each leans to its own side so
	# both stay readable. Purely visual.
	for s in slimes:
		var want := 0.0
		for o in slimes:
			if o != s and o.alive and s.alive and s.fan <= 0.0 and s.pos.distance_to(o.pos) < 0.8:
				want = -LANE if s.uid < o.uid else LANE
				break
		s.lane = move_toward(s.lane, want, delta * 0.45)
		# Crossing a bud or flower: the crawler stays on top but turns half see-through,
		# so the plant behind it can still be read.
		var over := 0.0
		for p in plants:
			if p.alive and s.pos.distance_to(Spec.center(p.cell)) < 0.8:
				over = 1.0
				break
		s.see_through = move_toward(s.see_through, over, delta * 4.0)
	soil.advance(delta)
	fx.advance(delta)


func _process(delta: float) -> void:
	if _selftest:
		return
	if not paused:
		sim_advance(delta * (FAST if fast else 1.0))
	if _notice_t > 0.0:
		_notice_t -= delta
		if _notice_t <= 0.0:
			_notice.text = ""
	_stats.text = "土壤 %d · 携带 %d · 苞花累计 %d · 漂浮池 %d · 繁殖消耗 %d · 合计 %d / 初始 %d      爬行 %d · 花苞 %d · 花 %d      %s%s" % [
		grid.soil_total(), carried_total(), collected_total(), grid.pool_total, repro_spent,
		ledger_total(), initial_total, count_alive(), count_alive(Plant.Stage.BUD), count_alive(Plant.Stage.FLOWER),
		"快进 ×4" if fast else "速度 ×1", "    已暂停" if paused else ""]
	if show_grid:
		_debug.queue_redraw()
	if _quit_after >= 0.0 and sim_time >= _quit_after:
		print("[eco] t=%.1f ledger %d / %d  pool %d  spent %d  counts %s" % [sim_time, ledger_total(), initial_total, grid.pool_total, repro_spent, counts])
		get_tree().quit()
	var hover := Spec.cell_of(_world.get_local_mouse_position() / Spec.CELL_PX)
	map.set_hover(hover)

	if _shots_dir != "" and sim_time >= _shot_from + _shot_step * _shot_n:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/f_%02d.png" % [_shots_dir, _shot_n])
		_shot_n += 1
		if _shot_n >= _shot_count:
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_dig(Spec.cell_of(_world.get_local_mouse_position() / Spec.CELL_PX))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: start_demo()
			KEY_R: do_reset()
			KEY_F: fast = not fast
			KEY_P: paused = not paused
			KEY_G:
				show_grid = not show_grid
				_debug.queue_redraw()
			KEY_Z:
				view = (view + 1) % VIEW_ZOOM.size()
				_apply_view()
			KEY_ESCAPE: get_tree().quit()


# ------------------------------------------------------------------ view and hud

func _apply_view() -> void:
	var z := VIEW_ZOOM[view]
	_camera.zoom = Vector2(z, z)
	_camera.position = Vector2(640, 360)
	_view_label.text = "视图：%s  [Z 切换]" % VIEW_NAME[view]


func _say(text: String) -> void:
	if _notice != null:
		_notice.text = text
		_notice_t = 3.0


func _caption(text: String, pos: Vector2, size: Vector2, font_size: int, col := Color(0.95, 0.9, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var grey := Color(0.78, 0.74, 0.7)
	hud.add_child(_caption("养分史莱姆 · 生态循环试验：出生、搬运、衰弱、结苞、开花、繁殖", Vector2(0, 4), Vector2(1280, 24), 16))
	_view_label = _caption("", Vector2(900, 26), Vector2(380, 20), 13, grey)
	hud.add_child(_view_label)
	_stats = _caption("", Vector2(0, 626), Vector2(1280, 22), 14)
	hud.add_child(_stats)
	_notice = _caption("", Vector2(0, 650), Vector2(1280, 22), 15, Color(1.0, 0.92, 0.6))
	hud.add_child(_notice)
	hud.add_child(_caption("左键：挖与通道相邻的土块（黄点 = 养分）    [Space] 自动演示   [R] 重置   [F] 快进   [P] 暂停   [G] 数值与格子   [Z] 尺寸   [Esc] 退出",
		Vector2(0, 690), Vector2(1280, 22), 13, grey))


func _draw_debug() -> void:
	if not show_grid:
		return
	var u := Spec.CELL_PX
	var font := ThemeDB.fallback_font
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			_debug.draw_rect(Rect2(Vector2(c) * u, Vector2(u, u)), Color(1, 1, 1, 0.06), false, 1.0)
			if grid.is_soil(c) and grid.nutrient(c) > 0:
				_debug.draw_string_outline(font, Vector2(c) * u + Vector2(4, 16), str(grid.nutrient(c)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
				_debug.draw_string(font, Vector2(c) * u + Vector2(4, 16), str(grid.nutrient(c)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.6))
	for s in slimes:
		# Logical footprint (one cell) and what it carries / how many moves since the last check.
		_debug.draw_rect(Rect2(Vector2(s.cell) * u, Vector2(u, u)), Color(0.45, 0.9, 1.0, 0.9), false, 1.5)
		var at: Vector2 = s.position + Vector2(-18, -24)
		var text := "HP%d 养%d 步%d" % [s.hp, s.carried, s.moves_since_ecology]
		_debug.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
		_debug.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.95, 1.0))
	for p in plants:
		if not p.alive:
			continue
		_debug.draw_rect(Rect2(Vector2(p.cell) * u + Vector2(3, 3), Vector2(u - 6, u - 6)), Color(1.0, 0.6, 0.85, 0.9), false, 1.5)
		var at := Vector2(p.cell) * u + Vector2(4, u - 6)
		var text := "%s HP%d 累%d" % ["苞" if p.stage == Plant.Stage.BUD else "花", p.hp, p.collected]
		_debug.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
		_debug.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.92))
