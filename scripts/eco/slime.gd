extends Node2D
## One crawling nutrient slime: rule-driven movement, nutrient carrying and HP, plus the
## continuous animation that shows it. Logic advances in whole cells (one per
## Eco.STEP_SECONDS); between cells the body only interpolates.
##
## Sizes kept apart, as elsewhere in the project:
##   footprint - exactly one cell (`cell`), used by every rule;
##   body      - none: slimes do not collide with each other, only terrain stops them;
##   visual    - the drawn look, which may shift sideways (`lane`) to stay readable when
##               two slimes overlap, or fan out (`fan`) right after a flower releases a
##               brood into one cell. Neither shift changes any rule.
##
## What it turns into (bud, starvation) is decided by the scene on `arrived`, because only
## the scene knows whether the cell already holds a bud or flower.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Look := preload("res://scripts/slime/slime_look.gd")

## Fired after a check that did something. `result` is Rules.resolve_ecology's dictionary.
signal ecology_done(slime: Node2D, result: Dictionary)
## Fired at the centre of every cell it reaches, after HP and ecology are settled.
signal arrived(slime: Node2D)
## Fired when the starving animation has finished and the node can go.
signal gone(slime: Node2D)

enum Phase { HATCH, WAIT, TURN, MOVE, STUCK, DIE }

const TURN_SECONDS := 0.22        ## quarter turn; part of the one-second step, not extra
const REVERSE_SECONDS := 0.36     ## about-turn at a dead end
const DIE_SECONDS := 1.1
const APPEAR_SECONDS := 0.45      ## newborn pop-in

var grid: RefCounted
var rng: RandomNumberGenerator
var uid := 0

# --- logic state
var cell := Vector2i.ZERO
var dir := Vector2i.RIGHT
var carried := 0
var hp := Eco.HP_INITIAL
var moves_since_ecology := 0
var moves_since_hp := 0
var total_moves := 0
var alive := true
var phase: int = Phase.HATCH
var age := 0.0                    ## seconds since it came into being
var start_delay := 0.0            ## seconds it waited before its first move (hatch or brood wait)

# --- presentation state
var pos := Vector2.ZERO           ## cells, continuous
var lane := 0.0                   ## cells, sideways visual shift (set by the scene)
var fan_dir := Vector2.ZERO       ## brood spread offset in cells; shrinks to nothing once it moves
var see_through := 0.0            ## 0..1, set by the scene while it crosses a bud or flower
var fan := 0.0
var shown_nutrient := 0           ## what the back spots show; lags `carried` while a mote flies
var look: Node2D

var _t := 0.0
var _dur := 1.0
var _next_cell := Vector2i.ZERO
var _next_dir := Vector2i.RIGHT
var _angle := 0.0
var _from_angle := 0.0
var _to_angle := 0.0
var _move_dur := 1.0
var _gulp := 0.0
var _pop := 1.0
var _clock := 0.0
var _appear := 1.0                ## 0..1 pop-in progress (newborns)
var _appear_wait := 0.0
var _vigor_shown := 1.0


## Dug out of the soil: pops out of the hole, then sets off.
func setup(g: RefCounted, r: RandomNumberGenerator, id: int, at: Vector2i, facing: Vector2i, start_nutrient: int) -> void:
	grid = g
	rng = r
	uid = id
	cell = at
	dir = facing
	carried = clampi(start_nutrient, 0, Eco.NUTRIENT_CAPACITY)
	shown_nutrient = carried
	pos = Spec.center(cell)
	_angle = Vector2(dir).angle()
	phase = Phase.HATCH
	_t = 0.0
	_dur = Eco.HATCH_SECONDS
	start_delay = Eco.HATCH_SECONDS
	look = Node2D.new()
	look.set_script(Look)
	look.breathe = false
	add_child(look)
	_sync()


## Released by a flower: appears after `appear_after` seconds, spread out by `fan_to` cells,
## and waits `wait` seconds (from now) before its first move. Carries nothing.
func setup_brood(g: RefCounted, r: RandomNumberGenerator, id: int, at: Vector2i, facing: Vector2i,
		wait: float, appear_after: float, fan_to: Vector2) -> void:
	setup(g, r, id, at, facing, 0)
	phase = Phase.WAIT
	_dur = maxf(wait, 0.001)
	start_delay = wait
	_appear = 0.0
	_appear_wait = appear_after
	fan_dir = fan_to
	fan = 1.0
	_sync()


## Show a new carried amount on the body. `gained`: pop the new spot in and gulp.
func set_shown(n: int, gained: bool) -> void:
	shown_nutrient = clampi(n, 0, Eco.NUTRIENT_CAPACITY)
	_gulp = 1.0
	_pop = 0.0 if gained else 1.0


## Ran out of HP: stop where it is and dissolve. Logic is over from this moment.
func starve() -> void:
	alive = false
	carried = 0
	phase = Phase.DIE
	_t = 0.0
	_dur = DIE_SECONDS


func advance(delta: float) -> void:
	_clock += delta
	age += delta
	_gulp = maxf(_gulp - delta * 2.6, 0.0)
	_pop = minf(_pop + delta * 3.5, 1.0)
	if _appear_wait > 0.0:
		_appear_wait -= delta
	else:
		_appear = minf(_appear + delta / APPEAR_SECONDS, 1.0)
	if phase != Phase.WAIT and phase != Phase.DIE:
		fan = maxf(fan - delta * 1.6, 0.0)
	var left := delta
	var guard := 0
	while left > 0.0 and guard < 64:
		guard += 1
		var use := minf(left, _dur - _t)
		_t += use
		left -= use
		if _t >= _dur - 0.00001:
			if not _finish_phase():
				break
		else:
			break
	_sync()


## Returns false when the slime has stopped for good (turned into something, or gone).
func _finish_phase() -> bool:
	match phase:
		Phase.DIE:
			_t = _dur
			gone.emit(self)
			return false
		Phase.TURN:
			_angle = _to_angle
			phase = Phase.MOVE
			_t = 0.0
			_dur = _move_dur
		Phase.MOVE:
			cell = _next_cell
			dir = _next_dir
			pos = Spec.center(cell)
			total_moves += 1
			var h := Rules.move_hp(hp, moves_since_hp)
			hp = h.hp
			moves_since_hp = h.moves
			moves_since_ecology += 1
			if moves_since_ecology >= Eco.ECOLOGY_COOLDOWN_MOVES:
				moves_since_ecology = 0
				var res := Rules.resolve_ecology(carried, cell, grid, rng)
				carried = res.carried
				if res.action == "absorb":
					hp = mini(hp + Eco.HP_HEAL_ON_ABSORB, Eco.HP_MAX)
				if res.action != "none":
					ecology_done.emit(self, res)
			arrived.emit(self)
			if not alive or phase == Phase.DIE:
				return phase == Phase.DIE
			_plan()
		_:
			_plan()
	return true


## Decide the next cell. Turning in place is part of the same one-second step.
func _plan() -> void:
	var res := Rules.next_step(cell, dir, grid.is_open, rng)
	_t = 0.0
	if not res.moved:
		phase = Phase.STUCK
		_dur = Eco.STEP_SECONDS
		return
	_next_cell = res.pos
	_next_dir = res.dir
	if _next_dir == dir:
		phase = Phase.MOVE
		_dur = Eco.STEP_SECONDS
		return
	phase = Phase.TURN
	_from_angle = _angle
	_to_angle = Vector2(_next_dir).angle()
	_dur = REVERSE_SECONDS if _next_dir == -dir else TURN_SECONDS
	_move_dur = Eco.STEP_SECONDS - _dur


## HP shown as a secondary cue: full colour down to 8 HP, then fading towards the bud
## threshold.
func vigor() -> float:
	return clampf(float(hp - Eco.BUD_HP_THRESHOLD) / 6.0, 0.0, 1.0)


func _sync() -> void:
	var f := clampf(_t / _dur, 0.0, 1.0)
	var stretch := 0.0
	var grow := 1.0
	var fade := 1.0
	match phase:
		Phase.HATCH:
			# Pops out of the fresh hole: overshoot, then settle.
			grow = clampf(1.0 - pow(1.0 - f, 3.0) + 0.22 * sin(PI * f) * (1.0 - f), 0.0, 1.3)
			stretch = -0.12 * (1.0 - f)
		Phase.WAIT:
			# A brood slime getting its bearings: small restless squirms.
			stretch = 0.04 * sin(_clock * 4.0 + uid)
		Phase.TURN:
			# Bunches up against the wall while swinging round.
			_angle = lerp_angle(_from_angle, _to_angle, smoothstep(0.0, 1.0, f))
			stretch = -0.13 * sin(PI * f)
		Phase.MOVE:
			# Two reach-and-gather pulses per cell; it is longest when it is fastest.
			var p := f + 0.03 * sin(TAU * 2.0 * f)
			pos = Spec.center(cell).lerp(Spec.center(_next_cell), p)
			stretch = 0.075 * cos(TAU * 2.0 * f)
		Phase.STUCK:
			stretch = 0.03 * sin(_clock * 3.0)
		Phase.DIE:
			# Starving: a last shudder, then it slumps flat, greys and seeps away.
			var shudder := 0.06 * sin(f * 40.0) * (1.0 - smoothstep(0.0, 0.35, f))
			stretch = shudder - 0.3 * smoothstep(0.2, 0.7, f)
			grow = 1.0 - 0.25 * smoothstep(0.3, 1.0, f)
			fade = 1.0 - smoothstep(0.55, 1.0, f)
	# Gulp: a quick squeeze when nutrient goes in or out.
	stretch -= 0.14 * sin(PI * _gulp) * _gulp
	if _appear < 1.0:
		var a := _appear
		grow *= clampf(1.0 - pow(1.0 - a, 3.0) + 0.25 * sin(PI * a) * (1.0 - a), 0.0, 1.3)
	_vigor_shown = 0.0 if phase == Phase.DIE else vigor()

	var perp := Vector2(-sin(_angle), cos(_angle))
	if perp.x + perp.y < 0.0:
		perp = -perp                       # same world side for both of two slimes meeting head-on
	position = (pos + perp * lane + fan_dir * smoothstep(0.0, 1.0, fan)) * Spec.CELL_PX
	scale = Vector2(grow, grow)
	modulate.a = fade * (1.0 - 0.5 * see_through)
	visible = _appear > 0.0
	look.facing = _angle
	look.nutrient = shown_nutrient
	look.vigor = _vigor_shown
	look.stretch = stretch
	look.spot_pop = 0.35 + 0.65 * _pop + 0.35 * sin(PI * _pop)
	look.moving = phase == Phase.MOVE
	look._t = _clock
	look.queue_redraw()


## Where the visible body is, in cells (lane and fan shifts included).
func visual_pos() -> Vector2:
	return position / Spec.CELL_PX


## Heading of the drawn body, radians.
func angle() -> float:
	return _angle
