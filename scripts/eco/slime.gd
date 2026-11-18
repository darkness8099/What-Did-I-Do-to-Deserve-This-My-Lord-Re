extends Node2D
## One crawling nutrient slime: rule-driven movement and nutrient carrying, plus the
## continuous animation that shows it. Logic advances in whole cells (one per
## Eco.STEP_SECONDS); between cells the body only interpolates.
##
## Sizes kept apart, as elsewhere in the project:
##   footprint - exactly one cell (`cell`), used by every rule;
##   body      - none: slimes do not collide with each other, only terrain stops them;
##   visual    - the drawn look, which may shift sideways (`lane`) to stay readable when
##               two slimes overlap. The shift never changes any rule.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Look := preload("res://scripts/slime/slime_look.gd")

## Fired after a check that did something. `result` is Rules.resolve_ecology's dictionary.
signal ecology_done(slime: Node2D, result: Dictionary)
signal stepped(slime: Node2D)

enum Phase { HATCH, TURN, MOVE, STUCK }

const TURN_SECONDS := 0.22        ## quarter turn; part of the one-second step, not extra
const REVERSE_SECONDS := 0.36     ## about-turn at a dead end

var grid: RefCounted
var rng: RandomNumberGenerator
var uid := 0

# --- logic state
var cell := Vector2i.ZERO
var dir := Vector2i.RIGHT
var carried := 0
var moves_since_ecology := 0
var total_moves := 0
var phase: int = Phase.HATCH

# --- presentation state
var pos := Vector2.ZERO           ## cells, continuous
var lane := 0.0                   ## cells, sideways visual shift (set by the scene)
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
	look = Node2D.new()
	look.set_script(Look)
	look.breathe = false
	add_child(look)
	_sync()


## Show a new carried amount on the body. `gained`: pop the new spot in and gulp.
func set_shown(n: int, gained: bool) -> void:
	shown_nutrient = clampi(n, 0, Eco.NUTRIENT_CAPACITY)
	_gulp = 1.0
	_pop = 0.0 if gained else 1.0


func advance(delta: float) -> void:
	_clock += delta
	_gulp = maxf(_gulp - delta * 2.6, 0.0)
	_pop = minf(_pop + delta * 3.5, 1.0)
	var left := delta
	var guard := 0
	while left > 0.0 and guard < 64:
		guard += 1
		var use := minf(left, _dur - _t)
		_t += use
		left -= use
		if _t >= _dur - 0.00001:
			_finish_phase()
		else:
			break
	_sync()


func _finish_phase() -> void:
	match phase:
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
			moves_since_ecology += 1
			if moves_since_ecology >= Eco.ECOLOGY_COOLDOWN_MOVES:
				moves_since_ecology = 0
				var res := Rules.resolve_ecology(carried, cell, grid, rng)
				carried = res.carried
				if res.action != "none":
					ecology_done.emit(self, res)
			stepped.emit(self)
			_plan()
		_:
			_plan()


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


func _sync() -> void:
	var f := clampf(_t / _dur, 0.0, 1.0)
	var stretch := 0.0
	var grow := 1.0
	match phase:
		Phase.HATCH:
			# Pops out of the fresh hole: overshoot, then settle.
			grow = clampf(1.0 - pow(1.0 - f, 3.0) + 0.22 * sin(PI * f) * (1.0 - f), 0.0, 1.3)
			stretch = -0.12 * (1.0 - f)
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
	# Gulp: a quick squeeze when nutrient goes in or out.
	stretch -= 0.14 * sin(PI * _gulp) * _gulp

	var perp := Vector2(-sin(_angle), cos(_angle))
	if perp.x + perp.y < 0.0:
		perp = -perp                       # same world side for both of two slimes meeting head-on
	position = (pos + perp * lane) * Spec.CELL_PX
	scale = Vector2(grow, grow)
	look.facing = _angle
	look.nutrient = shown_nutrient
	look.stretch = stretch
	look.spot_pop = 0.35 + 0.65 * _pop + 0.35 * sin(PI * _pop)
	look.moving = phase == Phase.MOVE
	look._t = _clock
	look.queue_redraw()


## Where the visible body is, in cells (lane shift included).
func visual_pos() -> Vector2:
	return position / Spec.CELL_PX
