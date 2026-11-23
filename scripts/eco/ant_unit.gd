extends Node2D
## One ant unit (二级魔物「群」, stage one: no nest yet). Task ECO-006.
##
## By rule it is ONE creature: one cell, one HP total, one decision. On screen it is two
## ants walking one behind the other along the path the unit takes. The HP is split in
## shares: when it drops under one share (Eco.ANT_MEMBER_HP) with two ants alive, one ant
## dies where it stands and never comes back. Bites and healing count the ants still alive.
##
## Movement is the moss's rule (straight, turn when blocked), one cell per second.
## Hungry (HP under Eco.ANT_EAT_BELOW_HP) and standing on a cell with prey, it stops and
## eats: a bud or flower in the cell first, otherwise a crawling moss within reach. The two
## ants stand on either side of the prey, facing it, and bite in turn. When the prey dies
## its nutrient moves onto the unit. Nothing is done with that nutrient yet (nests come in
## stage two): it returns to the soil when the unit starves.
##
## The scene supplies `find_prey` and settles what the signals report; this node changes
## the grid in no way.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Look := preload("res://scripts/ant/ant_look.gd")

## A meal ended with the prey dead. `gained` went onto the unit, `overflow` did not fit.
signal ate(unit: Node2D, kind: String, gained: int, overflow: int)
## One of the two ants died of hunger; the unit lives on.
signal member_died(unit: Node2D)
## Out of HP. `had` is the nutrient it carried; the scene returns it to the soil.
signal starved(unit: Node2D, had: int)
## Fired at the centre of every cell it reaches, after HP is settled.
signal arrived(unit: Node2D)
## Every closing animation is over and the node can go.
signal gone(unit: Node2D)

enum Phase { HATCH, TURN, MOVE, STUCK, EAT, DEAD }

const REVERSE_SECONDS := 0.3      ## about-turn at a dead end; part of the one-second step
const SPREAD := 0.245             ## cells from the unit's point to each ant while walking
const EAT_SPREAD := 0.36          ## ... and while they stand around their prey
const SECOND_BITE_AFTER := 0.27   ## the second ant starts its bite this much later
const HIT_AT := 0.24              ## seconds into the attack clip where the jaws close
const DEATH_SECONDS := 0.62       ## length of the death clip
const DISSOLVE_SECONDS := 0.9
const NO_CELL := Vector2i(-9999, -9999)

var grid: RefCounted
var rng: RandomNumberGenerator
var uid := 0
## func(cell: Vector2i) -> Dictionary {"node": Node2D, "kind": "bud"|"flower"|"moss"} or {}.
var find_prey := Callable()

# --- logic state
var cell := Vector2i.ZERO
var dir := Vector2i.RIGHT
var hp := Eco.ANT_HP_INITIAL
var members := Eco.ANT_MEMBERS
var carried := 0
var total_moves := 0
var meals := 0
var alive := true
var phase: int = Phase.HATCH
var age := 0.0

# --- presentation state
var pos := Vector2.ZERO           ## cells, continuous: the point between the two ants

var _t := 0.0
var _dur := 1.0
var _prev := Vector2i.ZERO        ## cell behind it on its path (may be a pretend one after an about-turn)
var _next := Vector2i.ZERO
var _next_dir := Vector2i.RIGHT
var _after := NO_CELL             ## the step after `_next`, planned ahead so the front ant can round a corner
var _after_dir := Vector2i.RIGHT
var _move_dur := 1.0
var _prey: Node2D
var _prey_kind := ""
var _ants: Array[Dictionary] = []     ## {look, off, bit}: off = cells ahead (+) or behind (-) the unit's point
var _corpses: Array[Dictionary] = []  ## {look, at (cells), t}
var _gone := false


func setup(g: RefCounted, r: RandomNumberGenerator, id: int, at: Vector2i, facing: Vector2i, start_nutrient: int) -> void:
	grid = g
	rng = r
	uid = id
	cell = at
	dir = facing
	carried = clampi(start_nutrient, 0, Eco.ANT_NUTRIENT_CAPACITY)
	pos = Spec.center(cell)
	_prev = cell - dir
	_next = cell
	_next_dir = dir
	phase = Phase.HATCH
	_t = 0.0
	_dur = Eco.HATCH_SECONDS
	z_index = 1                    # in front of the mosses it walks through and eats
	for i in members:
		var look := Node2D.new()
		look.set_script(Look)
		look.manual = true
		add_child(look)
		look.play(&"idle")
		look.advance(0.21 * i + 0.13 * (id % 5))
		_ants.append({"look": look, "off": (SPREAD if i == 0 else -SPREAD) if members > 1 else 0.0, "bit": false, "hit": false})
	_sync()


func advance(delta: float) -> void:
	age += delta
	for a in _ants:
		a.look.advance(delta)
	for c in _corpses.duplicate():
		c.t += delta
		c.look.advance(delta)
		c.look.dissolve = clampf((c.t - DEATH_SECONDS) / DISSOLVE_SECONDS, 0.0, 1.0)
		if c.t >= DEATH_SECONDS + DISSOLVE_SECONDS:
			c.look.queue_free()
			_corpses.erase(c)
	if phase == Phase.DEAD:
		if _corpses.is_empty() and not _gone:
			_gone = true
			gone.emit(self)
		_sync()
		return
	var left := delta
	var guard := 0
	while left > 0.0 and guard < 64 and phase != Phase.DEAD:
		guard += 1
		var use := minf(left, _dur - _t)
		_t += use
		left -= use
		if phase == Phase.EAT:
			_eat_tick()
		if _t >= _dur - 0.00001:
			_finish_phase()
		else:
			break
	_ease_spread(delta)
	_sync()


func _finish_phase() -> void:
	match phase:
		Phase.TURN:
			phase = Phase.MOVE
			_t = 0.0
			_dur = _move_dur
		Phase.MOVE:
			_prev = cell
			cell = _next
			dir = _next_dir
			pos = Spec.center(cell)
			total_moves += 1
			hp -= Eco.ANT_HP_COST
			if hp <= 0:
				_die()
				return
			_settle_members()
			arrived.emit(self)
			if not _try_eat():
				_plan()
		Phase.EAT:
			_end_bite()
		_:
			if not _try_eat():
				_plan()


## One ant dies when the HP no longer covers two shares.
func _settle_members() -> void:
	var want := Rules.ant_members_after(hp, members)
	while members > want and _ants.size() > 1:
		members -= 1
		# the one walking behind is the one that drops
		var k := 0
		for i in _ants.size():
			if _ants[i].off < _ants[k].off:
				k = i
		_to_corpse(_ants[k])
		_ants.remove_at(k)
		member_died.emit(self)


func _to_corpse(a: Dictionary) -> void:
	a.look.play(&"death", true)
	_corpses.append({"look": a.look, "at": _point(a.off), "t": 0.0})


func _die() -> void:
	alive = false
	hp = 0
	members = 0
	var had := carried
	carried = 0
	for a in _ants:
		_to_corpse(a)
	_ants.clear()
	phase = Phase.DEAD
	starved.emit(self, had)


# ------------------------------------------------------------------ eating

func _try_eat() -> bool:
	if not Rules.ant_wants_food(hp) or not find_prey.is_valid():
		return false
	var found: Dictionary = find_prey.call(cell)
	if found.is_empty():
		return false
	_prey = found.node
	_prey_kind = found.kind
	if _prey_kind == "moss":
		_prey.hold(Spec.center(cell))
	phase = Phase.EAT
	_start_bite()
	return true


func _start_bite() -> void:
	_t = 0.0
	_dur = Eco.ANT_BITE_SECONDS
	for a in _ants:
		a.bit = false


## Start each ant's bite at its own moment, so the two take turns.
func _eat_tick() -> void:
	for i in _ants.size():
		var a := _ants[i]
		if not a.bit and _t >= SECOND_BITE_AFTER * i:
			a.bit = true
			a.look.play(&"attack", true)
		if a.bit and _t >= SECOND_BITE_AFTER * i + HIT_AT and not a.hit:
			a.hit = true
			if is_instance_valid(_prey) and _prey.alive:
				_prey.flinch()


## The round is over: the damage of every living ant lands at once.
func _end_bite() -> void:
	for a in _ants:
		a.hit = false
	var got := -1
	if is_instance_valid(_prey) and _prey.alive:
		got = _prey.bitten(Rules.ant_bite_damage(members))
		hp = mini(hp + Rules.ant_bite_heal(members), Rules.ant_hp_cap(members))
		if got < 0:
			_start_bite()
			return
	if got >= 0:
		var res := Rules.ant_take(carried, got)
		carried = res.carried
		meals += 1
		ate.emit(self, _prey_kind, res.gained, res.overflow)
	_prey = null
	for a in _ants:
		a.look.play(&"idle")
	# still hungry and something else is right here: carry on eating
	if not _try_eat():
		_plan()


# ------------------------------------------------------------------ movement

func _plan() -> void:
	_t = 0.0
	var step: Dictionary
	if _after != NO_CELL and grid.is_open(_after):
		step = {"moved": true, "pos": _after, "dir": _after_dir}
	else:
		step = Rules.next_step(cell, dir, grid.is_open, rng)
	_after = NO_CELL
	if not step.moved:
		phase = Phase.STUCK
		_dur = Eco.STEP_SECONDS
		_next = cell
		_next_dir = dir
		_play_all(&"idle")
		return
	_next = step.pos
	_next_dir = step.dir
	var ahead := Rules.next_step(_next, _next_dir, grid.is_open, rng)
	if ahead.moved:
		_after = ahead.pos
		_after_dir = ahead.dir
	_play_all(&"walk")
	if _next_dir == -dir:
		# About-turn: the ants turn where they stand, so the one behind now leads.
		_prev = cell + dir
		for a in _ants:
			a.off = -a.off
		phase = Phase.TURN
		_dur = REVERSE_SECONDS
		_move_dur = Eco.STEP_SECONDS - _dur
		return
	phase = Phase.MOVE
	_dur = Eco.STEP_SECONDS


func _play_all(anim: StringName) -> void:
	for a in _ants:
		a.look.play(anim)


## Where each ant wants to be relative to the unit's point.
func _ease_spread(delta: float) -> void:
	var eating := phase == Phase.EAT
	for a in _ants:
		var want: float
		if _ants.size() == 1:
			want = -EAT_SPREAD if eating else 0.0
		else:
			want = (EAT_SPREAD if eating else SPREAD) * signf(a.off if a.off != 0.0 else 1.0)
		a.off = move_toward(a.off, want, delta * 0.6)


func _f() -> float:
	return clampf(_t / _dur, 0.0, 1.0) if phase == Phase.MOVE else 0.0


## Point on the unit's path `off` cells ahead of (or behind) where the unit is, in cells.
func _point(off: float) -> Vector2:
	return _track(_f() + off).at


## Path position `u` cells past the centre of `cell`: {"at": Vector2, "dir": Vector2i}.
func _track(u: float) -> Dictionary:
	var here := Spec.center(cell)
	if u < 0.0:
		var back := cell - _prev
		return {"at": here + Vector2(back) * u, "dir": back}
	var fwd := _next - cell
	if fwd == Vector2i.ZERO:
		fwd = dir
	if u <= 1.0 or _next == cell:
		return {"at": here + Vector2(fwd) * u, "dir": fwd}
	var there := Spec.center(_next)
	if _after != NO_CELL and _after != cell:
		var on := _after - _next
		return {"at": there + Vector2(on) * (u - 1.0), "dir": on}
	return {"at": there + Vector2(fwd) * (u - 1.0), "dir": fwd}


static func _heading_of(d: Vector2i) -> int:
	if d.x > 0:
		return Look.Heading.RIGHT
	if d.x < 0:
		return Look.Heading.LEFT
	return Look.Heading.UP if d.y < 0 else Look.Heading.DOWN


func _sync() -> void:
	var f := _f()
	if phase == Phase.MOVE:
		pos = Spec.center(cell).lerp(Spec.center(_next), f)
	position = pos * Spec.CELL_PX
	var grow := 1.0
	if phase == Phase.HATCH:
		var k := clampf(_t / _dur, 0.0, 1.0)
		grow = clampf(1.0 - pow(1.0 - k, 3.0) + 0.22 * sin(PI * k) * (1.0 - k), 0.0, 1.3)
	for a in _ants:
		var p := _track(f + a.off)
		var d: Vector2i = p.dir
		# around the prey the one in front turns back to face it
		if phase == Phase.EAT and a.off > 0.0:
			d = -d
		a.look.position = (p.at - pos) * Spec.CELL_PX
		a.look.heading = _heading_of(d)
		a.look.scale = Vector2(grow, grow)
	for c in _corpses:
		c.look.position = (c.at - pos) * Spec.CELL_PX


## Where each living ant is drawn, in cells (for checks).
func ant_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for a in _ants:
		out.append(_point(a.off))
	return out
