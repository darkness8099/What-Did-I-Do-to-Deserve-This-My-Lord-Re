extends Node2D
## Sacgrub (囤囊虫): a small low-tier tunnel dweller whose job is to carry nutrients.
## It eats root nodules, stores them in the translucent sac at its rear (which swells and
## glows as it fills) and gives them back to the soil when it dies.
##
## Behaviour is a state machine working in CELL units on the burrow grid. Every action is
## a timeline table (*_TL) read by one state clock; the same clock fires the gameplay
## events (bite, swallow, hit, hatch), so picture and logic cannot drift apart.
##
## Movement: the thorax point `pos` travels along a path built from the grid route
## (cell centre to cell centre, corners rounded, U-turns as a hairpin). The rest of the
## body is sampled from the trail `pos` has left behind, and being pushed back rewinds
## along that same trail, so the body only ever occupies space it has walked through.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Rig := preload("res://scripts/burrow/grub_rig.gd")

enum State { HIDDEN, SPAWN, IDLE, MOVE, EAT, ATTACK, HURT, DEAD }
enum Goal { NONE, MOVE, EAT, ATTACK }

signal state_changed(s: int)
signal impact(strength: float)
signal notice(text: String)

const STATE_NAMES: Array[String] = ["未出生", "出生", "待机", "移动", "进食", "攻击", "受击", "死亡"]

const FOOTPRINT := Vector2i(1, 1)   ## cells reserved in the grid
const SPEED := 1.3                  ## cells per second
const CREEP_SPEED := 0.55
const FACE_SPEED := 9.0             ## rad per second
const REST_STRETCH := 0.8           ## the body bunches up when it is not travelling
const APPROACH := 0.16              ## how far past the cell centre it leans toward what it interacts with
const MAX_CREEP := 0.42
const SAC_CAPACITY := 3

const SPAWN_TIME := 3.0
const HATCH_AT := 1.35
const BITE_TIME := 1.0
const BITE_AT := 0.31
const SWALLOW_AT := 0.9
const CONTENT_TIME := 0.8
const ATTACK_TIME := 1.0
const HIT_AT := 0.42
const HURT_TIME := 0.65
const KNOCK := 0.2
const DEATH_TIME := 2.4
const DEATH_KNOCK := 0.14
const BLEND := 0.12

const SPAWN_TL := {
	"egg": [0.0, 0.0, 0.35, 1.1, 0.5, 1.0],
	"wob": [0.0, 0.0, 0.5, 0.05, 0.9, 0.13, 1.3, 0.26],
	"crack": [0.7, 0.0, 1.3, 1.0],
	"scale": [1.35, 0.55, 1.7, 1.06, 1.95, 1.0],
	"curl": [1.35, 1.0, 1.55, 1.0, 2.15, 0.0],
	"fold": [1.35, 1.0, 1.8, 1.0, 2.2, 0.0],
	"stretch": [1.35, 0.6, 2.1, 0.8, 2.3, 1.15, 2.65, 0.8],
	"yaw": [2.2, 0.0, 2.42, 0.6, 2.6, 0.6, 2.82, -0.5, 2.92, -0.5, 3.0, 0.0],
	"ant": [2.15, 0.0, 2.3, 0.5, 2.45, -0.1, 2.6, 0.0],
	"jaw": [2.3, 0.0, 2.4, 0.6, 2.5, 0.0, 2.6, 0.5, 2.7, 0.0],
}
const BITE_TL := {
	"back": [0.0, 0.0, 0.16, -0.05, 0.26, 0.0],
	"lunge": [0.2, 0.0, 0.3, 1.0, 0.4, 0.92, 0.58, 0.0],
	"jaw": [0.0, 0.15, 0.16, 1.0, 0.28, 1.0, 0.315, 0.0, 0.46, 0.05, 0.52, 0.5, 0.58, 0.0, 0.64, 0.45, 0.7, 0.0, 0.76, 0.3, 0.82, 0.0],
	"neck": [0.2, 0.0, 0.3, 0.04, 0.45, 0.0],
	"stretch": [0.0, 0.8, 0.16, 0.74, 0.3, 1.0, 0.58, 0.8],
	"s0": [0.7, 1.0, 0.77, 0.84, 0.85, 1.0],
	"s1": [0.77, 1.0, 0.84, 0.84, 0.92, 1.0],
	"ant": [0.0, 0.0, 0.2, -0.25, 0.32, 0.2, 0.5, 0.0],
}
const ATTACK_TL := {
	"back": [0.0, 0.0, 0.3, -0.09, 0.36, -0.09, 0.42, 0.0],
	"lunge": [0.36, 0.0, 0.42, 1.0, 0.5, 0.94, 0.74, -0.04, 0.88, 0.0],
	"stretch": [0.0, 0.8, 0.3, 0.68, 0.36, 0.68, 0.42, 1.05, 0.52, 0.95, 0.8, 0.78, 1.0, 0.8],
	"jaw": [0.0, 0.0, 0.14, 1.0, 0.38, 1.0, 0.42, 0.0, 0.62, 0.3, 0.72, 0.0],
	"ant": [0.0, 0.0, 0.3, 0.45, 0.42, -0.3, 0.6, 0.1, 0.8, 0.0],
	"fold": [0.0, 0.0, 0.3, 0.25, 0.42, 0.0],
	"neck": [0.36, 0.0, 0.42, 0.04, 0.55, 0.0],
}
const HURT_TL := {
	"knock": [0.0, 0.0, 0.12, 1.0],
	"flash": [0.0, 1.0, 0.08, 1.0, 0.26, 0.0],
	"curl": [0.0, 0.0, 0.09, 0.42, 0.32, 0.22, 0.65, 0.0],
	"stretch": [0.0, 0.6, 0.25, 0.66, 0.65, 0.8],
	"jaw": [0.0, 0.7, 0.3, 0.3, 0.5, 0.0],
	"fold": [0.0, 0.55, 0.3, 0.35, 0.6, 0.0],
	"ant": [0.0, 0.6, 0.4, 0.3, 0.65, 0.0],
}
const DEATH_TL := {
	"knock": [0.0, 0.0, 0.14, 1.0],
	"flash": [0.0, 1.0, 0.1, 1.0, 0.35, 0.0],
	"curl": [0.0, 0.0, 0.1, 0.5, 0.28, 0.15, 0.46, 0.7, 0.62, 0.4, 0.85, 0.85, 1.3, 1.0],
	"fold": [0.0, 0.3, 0.5, 0.4, 1.3, 1.0],
	"life": [0.0, 1.0, 0.9, 1.0, 2.2, 0.0],
	"roll": [0.0, 0.0, 0.9, 0.0, 1.5, 0.4],
	"jaw": [0.0, 0.8, 0.9, 0.6, 1.4, 0.25],
	"stretch": [0.0, 0.6, 0.5, 0.75, 1.3, 0.7],
	"glow": [0.0, 1.0, 0.9, 1.0, 2.0, 0.0],
	"fill": [0.0, 1.0, 0.95, 1.0, 2.0, 0.0],
	"ant": [0.0, 0.6, 1.3, 0.9],
}
const BLEND_KEYS: Array[String] = ["stretch", "shift", "neck", "yaw", "jaw", "curl", "fold", "sac_r", "s0", "s1", "ant", "scale", "roll", "glow"]

var grid: RefCounted
var fx: Node2D

var state: int = State.HIDDEN
var cell := Vector2i.ZERO       ## logical anchor cell
var pos := Vector2.ZERO         ## thorax point, cells
var face := 0.0                 ## where the head points, radians
var curl_side := 1.0
var sac_level := 0              ## meals stored, 0..SAC_CAPACITY
var goal: int = Goal.NONE
var bites_taken := 0
var attacks_landed := 0
var hurt_count := 0

var _t := 0.0
var _clock := 0.0
var _hitstop := 0.0
var _fired: Dictionary = {}
var _trail := PackedVector2Array()
var _path := PackedVector2Array()
var _path_i := 0
var _final_face := 0.0
var _face_goal := 0.0
var _gait := 0.0
var _flip := 1.0
var _crept := 0.0
var _need_plan := false
var _goal_cell := Vector2i.ZERO
var _goal_obj: Node2D
var _plan_dir := Vector2i.ZERO
var _engaged: Node2D
var _act_obj: Node2D
var _act_dir := Vector2.RIGHT
var _eat_phase := 0
var _bite: Dictionary = {}
var _creep_to := 0.0
var _lunge := 0.0
var _bite_yaw := 0.0
var _knock_total := 0.0
var _knocked := 0.0
var _look := 0.0
var _look_goal := 0.0
var _look_t := 2.0
var _click_t := -1.0
var _blink_t := 2.0
var _from: Dictionary = {}
var _shown: Dictionary = {}
var _blend_t := 1.0

@onready var rig: Node2D = $Rig


func _ready() -> void:
	_shown = _rest_pose()
	_shown.body = false
	_from = _shown


# ------------------------------------------------------------------ public API

func reset() -> void:
	goal = Goal.NONE
	_goal_obj = null
	_engaged = null
	_hitstop = 0.0
	_set_state(State.HIDDEN)


func spawn(c: Vector2i, facing: Vector2i) -> void:
	cell = c
	pos = Spec.center(c, FOOTPRINT)
	face = Vector2(facing).angle()
	_face_goal = face
	_final_face = face
	_trail_reset(Vector2(facing))
	_path.clear()
	_path_i = 0
	_crept = 0.0
	_need_plan = false
	_gait = 0.0
	sac_level = 0
	bites_taken = 0
	attacks_landed = 0
	hurt_count = 0
	goal = Goal.NONE
	_goal_obj = null
	_engaged = null
	_hitstop = 0.0
	_look = 0.0
	_look_goal = 0.0
	curl_side = -1.0 if randf() < 0.5 else 1.0
	rig.reset_springs()
	_set_state(State.SPAWN)


func command_move(c: Vector2i) -> bool:
	if not _can_take_orders():
		return false
	goal = Goal.MOVE
	_goal_cell = c
	_goal_obj = null
	_goal_changed()
	return true


func command_eat(food: Node2D) -> bool:
	if not _can_take_orders():
		return false
	if state == State.EAT and _act_obj == food:
		goal = Goal.NONE
		return true
	goal = Goal.EAT
	_goal_obj = food
	_goal_changed()
	return true


func command_attack(target: Node2D) -> bool:
	if not _can_take_orders():
		return false
	goal = Goal.ATTACK
	_goal_obj = target
	_goal_changed()
	return true


## A blow lands. Ignored while unborn, hatching or dead. Cancels whatever it was doing.
func take_hit(lethal: bool) -> bool:
	if state == State.HIDDEN or state == State.SPAWN or state == State.DEAD:
		return false
	hurt_count += 1
	goal = Goal.NONE
	_goal_obj = null
	_need_plan = false
	_knock_total = DEATH_KNOCK if lethal else KNOCK
	_knocked = 0.0
	_hitstop = 0.06
	rig.kick(2.4)
	impact.emit(9.0 if lethal else 6.0)
	if fx != null:
		fx.burst("impact_small", rig.head, Vector2.ZERO)
		if sac_level > 0:
			fx.burst("spores_few", rig.seg[2], Vector2.ZERO)
	_set_state(State.DEAD if lethal else State.HURT)
	return true


func is_busy() -> bool:
	return state != State.IDLE or goal != Goal.NONE


func is_dead_settled() -> bool:
	return state == State.DEAD and _t >= DEATH_TIME


func is_alive() -> bool:
	return state != State.HIDDEN and state != State.DEAD


## Point `d` cells behind the thorax along the path it has travelled.
func trail_point(d: float) -> Vector2:
	if d <= 0.0:
		return pos
	var left := d
	for i in range(1, _trail.size()):
		var seg := _trail[i - 1].distance_to(_trail[i])
		if seg >= left:
			return _trail[i - 1].lerp(_trail[i], left / seg)
		left -= seg
	var n := _trail.size()
	var out := (_trail[n - 1] - _trail[n - 2]).normalized()
	return _trail[n - 1] + out * left


## Forward direction of the trail at distance `d`.
func trail_dir(d: float) -> Vector2:
	var v := trail_point(maxf(d - 0.04, 0.0)) - trail_point(d + 0.05)
	return v.normalized() if v.length_squared() > 1e-8 else Vector2.from_angle(face)


# ------------------------------------------------------------------ orders

func _can_take_orders() -> bool:
	return state != State.HIDDEN and state != State.DEAD


func _goal_changed() -> void:
	if state == State.IDLE or state == State.MOVE:
		_start_goal()
	# Otherwise the current action finishes (or yields between bites) and IDLE picks it up.


func _start_goal() -> void:
	if goal == Goal.NONE:
		return
	if (goal == Goal.EAT or goal == Goal.ATTACK) and _engaged != null and _engaged == _goal_obj and state == State.IDLE:
		_arrive()   # already leaning on it
		return
	if _crept > 0.005:
		_need_plan = true
		_path.clear()
		_path_i = 0
		if state != State.MOVE:
			_set_state(State.MOVE)
		return
	if _plan():
		if state != State.MOVE:
			_set_state(State.MOVE)
	else:
		goal = Goal.NONE
		_goal_obj = null
		if state == State.MOVE:
			var here: Array[Vector2i] = [cell]
			_build_path(here, Vector2i.ZERO)   # settle on the cell it is in


func _plan() -> bool:
	var route: Array[Vector2i] = []
	var final_dir := Vector2i.ZERO
	match goal:
		Goal.MOVE:
			if grid.area_free(_goal_cell, FOOTPRINT):
				var only: Array[Vector2i] = [_goal_cell]
				route = grid.find_path(cell, only, FOOTPRINT)
		Goal.EAT, Goal.ATTACK:
			if not is_instance_valid(_goal_obj):
				return false
			if goal == Goal.EAT and _goal_obj.bites_left <= 0:
				notice.emit("这株根瘤已经吃光了（按 F 补充）")
				return false
			var spots: Array[Vector2i] = []
			for c: Vector2i in grid.cells_beside(_goal_obj.cell, _goal_obj.size, FOOTPRINT):
				if grid.area_free(c, FOOTPRINT):
					spots.append(c)
			route = grid.find_path(cell, spots, FOOTPRINT)
			if not route.is_empty():
				var diff: Vector2 = _goal_obj.center() - Spec.center(route[route.size() - 1], FOOTPRINT)
				final_dir = Vector2i(signi(roundi(diff.x)), 0) if absf(diff.x) > absf(diff.y) else Vector2i(0, signi(roundi(diff.y)))
	if route.is_empty():
		notice.emit("到不了那里：没有连通的通道")
		return false
	_build_path(route, final_dir)
	return true


## Turns a cell route into the polyline the thorax follows.
func _build_path(route: Array[Vector2i], final_dir: Vector2i) -> void:
	_plan_dir = final_dir
	var c0 := Spec.center(route[0], FOOTPRINT)
	var targets: Array[Vector2] = []
	for i in range(1, route.size()):
		targets.append(Spec.center(route[i], FOOTPRINT))
	var last_center := c0 if targets.is_empty() else targets[targets.size() - 1]
	var off := pos - c0
	if off.length() > 0.02:
		var include := true
		if not targets.is_empty():
			var step := targets[0] - c0
			var ahead := (-off).dot(step)
			var along := off.dot(step)
			var lateral := (off - step * along).length()
			var t := clampf((0.5 - along) / maxf(1.0 - along, 0.01), 0.0, 1.0)
			include = ahead > 0.0 or lateral * (1.0 - t) > 0.2
		if include:
			targets.insert(0, c0)
	if final_dir != Vector2i.ZERO:
		targets.append(last_center + Vector2(final_dir) * APPROACH)
		_final_face = Vector2(final_dir).angle()
	elif route.size() >= 2:
		_final_face = Vector2(route[route.size() - 1] - route[route.size() - 2]).angle()
	else:
		_final_face = _face_goal

	var pts: Array[Vector2] = [pos]
	if not targets.is_empty():
		var tangent := trail_dir(0.0)
		var first := (targets[0] - pos).normalized()
		if first.dot(tangent) < -0.5 and pos.distance_to(targets[0]) > 0.05:
			# U-turn: swing the front out to one side and come back alongside the body.
			var n := Vector2(-tangent.y, tangent.x)
			var lat := (c0 - pos).dot(n)
			if absf(lat) > 0.05:
				n *= signf(lat)
			elif absf(n.dot(first)) > 0.1:
				n *= signf(n.dot(first))
			else:
				n *= _flip
				_flip = -_flip
			pts.append(pos + tangent * 0.05 + n * 0.12)
			if pos.distance_to(targets[0]) > 0.42:
				pts.append(pos + first * 0.28 + n * 0.09)
	for p in targets:
		if p.distance_to(pts[pts.size() - 1]) > 0.01:
			pts.append(p)
	_path = _round(pts)
	_path_i = 0


func _round(pts: Array[Vector2]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, pts.size()):
		if i == pts.size() - 1:
			out.append(pts[i])
			break
		var v := pts[i]
		var din := v - pts[i - 1]
		var dout := pts[i + 1] - v
		var r := minf(Spec.CORNER_RADIUS, minf(din.length(), dout.length()) * 0.48)
		if absf(din.angle_to(dout)) < 0.05 or r < 0.01:
			out.append(v)
			continue
		var a := v - din.normalized() * r
		var b := v + dout.normalized() * r
		for k in 9:
			var t := k / 8.0
			out.append(a.lerp(v, t).lerp(v.lerp(b, t), t))
	return out


# ------------------------------------------------------------------ trail

func _trail_reset(dir: Vector2) -> void:
	_trail.clear()
	for i in 61:
		_trail.append(pos - dir * i * 0.02)


func _advance(p: Vector2) -> void:
	pos = p
	_trail[0] = p
	if _trail[0].distance_to(_trail[1]) >= 0.02:
		_trail.insert(0, p)
		if _trail.size() > 280:
			_trail.resize(280)
	var c := Spec.cell_of(pos)
	if c != cell and grid.is_open(c):
		cell = c


## Slides the whole body backwards along the way it came.
func _rewind(d: float) -> void:
	if d <= 0.0:
		return
	var p := trail_point(d)
	var left := d
	var cut := 1
	for i in range(1, _trail.size()):
		var seg := _trail[i - 1].distance_to(_trail[i])
		if seg >= left:
			cut = i
			break
		left -= seg
		cut = i
	var rest := _trail.slice(cut)
	if rest.size() < 2:
		var dir := trail_dir(0.0)
		rest = PackedVector2Array([p - dir * 0.02, p - dir * 1.2])
	_trail = PackedVector2Array([p, p])
	_trail.append_array(rest)
	pos = p
	var c := Spec.cell_of(pos)
	if c != cell and grid.is_open(c):
		cell = c


func _follow(step: float) -> void:
	while step > 0.0 and _path_i < _path.size():
		var to := _path[_path_i]
		var d := pos.distance_to(to)
		if d <= step:
			_advance(to)
			step -= d
			_path_i += 1
		else:
			_advance(pos + (to - pos) / d * step)
			step = 0.0


func _ahead(dist: float) -> Vector2:
	var p := pos
	var left := dist
	for i in range(_path_i, _path.size()):
		var d := p.distance_to(_path[i])
		if d >= left:
			return p.lerp(_path[i], left / maxf(d, 0.0001))
		left -= d
		p = _path[i]
	return p


# ------------------------------------------------------------------ state machine

func _set_state(s: int) -> void:
	_from = _shown.duplicate()
	_blend_t = 0.0
	_t = 0.0
	_fired.clear()
	state = s
	if s == State.IDLE:
		_look_t = randf_range(1.2, 2.4)
		_look_goal = 0.0
	state_changed.emit(s)


func _once(key: String, at: float) -> bool:
	if _t >= at and not _fired.has(key):
		_fired[key] = true
		return true
	return false


func _tl(table: Dictionary, key: String, t: float) -> float:
	var a: Array = table[key]
	if t <= a[0]:
		return a[1]
	var n := a.size()
	for i in range(2, n, 2):
		if t <= a[i]:
			var k := smoothstep(a[i - 2], a[i], t)
			return lerpf(a[i - 1], a[i + 1], k)
	return a[n - 1]


func _process(delta: float) -> void:
	if state == State.HIDDEN:
		_shown.body = false
		_shown.egg = 0.0
		rig.update(self, _shown, delta)
		return
	_clock += delta
	var dt := delta
	if _hitstop > 0.0:
		_hitstop -= delta
		dt = 0.0
	_t += dt
	match state:
		State.SPAWN: _tick_spawn()
		State.IDLE: _tick_idle(dt)
		State.MOVE: _tick_move(dt)
		State.EAT: _tick_eat(dt)
		State.ATTACK: _tick_attack()
		State.HURT: _tick_hurt()
		State.DEAD: _tick_dead()
	face = rotate_toward(face, _face_goal, FACE_SPEED * dt)
	_look = lerpf(_look, _look_goal, 1.0 - exp(-7.0 * dt))

	var p := _pose()
	_blend_t += dt
	if _blend_t < BLEND:
		var w := smoothstep(0.0, 1.0, _blend_t / BLEND)
		for k in BLEND_KEYS:
			p[k] = lerpf(_from[k], p[k], w)
	_shown = p
	rig.update(self, p, delta)


func _tick_spawn() -> void:
	if _once("hatch", HATCH_AT):
		rig.reset_springs()
		if fx != null:
			fx.burst("shell", pos + Vector2(0, 0.02), Vector2.ZERO)
			fx.burst("sparkle", pos, Vector2.ZERO)
		impact.emit(2.5)
	if _t >= SPAWN_TIME:
		_set_state(State.IDLE)


func _tick_idle(dt: float) -> void:
	if goal != Goal.NONE:
		_start_goal()
		if state != State.IDLE:
			return
	# Life: now and then it peers down the tunnel and clicks its jaws.
	_look_t -= dt
	if _look_t <= 0.0:
		if absf(_look_goal) > 0.01:
			_look_goal = 0.0
			_look_t = randf_range(2.2, 4.2)
		else:
			_look_goal = randf_range(0.35, 0.6) * (-1.0 if randf() < 0.5 else 1.0)
			_look_t = randf_range(0.8, 1.3)
			if randf() < 0.5:
				_click_t = 0.0
	if _click_t >= 0.0:
		_click_t += dt
		if _click_t > 0.45:
			_click_t = -1.0


func _tick_move(dt: float) -> void:
	_look_goal = 0.0
	if _need_plan:
		# Back off to the cell centre before going anywhere else.
		var d := minf(CREEP_SPEED * dt, _crept)
		_rewind(d)
		_gait += d
		_crept -= d
		_engaged = null
		if _crept <= 0.005:
			_crept = 0.0
			_need_plan = false
			if not _plan():
				goal = Goal.NONE
				_goal_obj = null
				_set_state(State.IDLE)
		return
	if _path_i < _path.size():
		_engaged = null
		var a := _ahead(0.14)
		if a.distance_to(pos) > 0.03:
			_face_goal = (a - pos).angle()
		else:
			_face_goal = _final_face
		var turn := absf(angle_difference(face, _face_goal))
		var surge := 1.0 + 0.28 * sin(TAU * _gait / 0.42 + 1.2)
		var step := SPEED * surge * clampf(1.15 - turn * 0.6, 0.4, 1.0) * dt
		_follow(step)
		_gait += step
	else:
		_face_goal = _final_face
		if absf(angle_difference(face, _face_goal)) < 0.15:
			_arrive()


func _arrive() -> void:
	var g := goal
	var obj := _goal_obj
	goal = Goal.NONE
	_goal_obj = null
	if (g == Goal.EAT or g == Goal.ATTACK) and is_instance_valid(obj):
		if _engaged != obj:
			_crept = APPROACH if _plan_dir != Vector2i.ZERO else 0.0
			_act_dir = Vector2(_plan_dir)
		_engaged = obj
		_act_obj = obj
		if g == Goal.EAT:
			if obj.bites_left > 0:
				_eat_phase = 0
				_bite = {}
				_set_state(State.EAT)
				return
			notice.emit("这株根瘤已经吃光了（按 F 补充）")
		else:
			var gap: float = (obj.center() - pos).dot(_act_dir) - obj.body_radius - Rig.TIP
			_lunge = clampf(gap + 0.03, 0.08, 0.45)
			_set_state(State.ATTACK)
			return
	_set_state(State.IDLE)


## phases: 0 creep up to the next nodule, 1 bite + swallow, 2 content, 3 back off
func _tick_eat(dt: float) -> void:
	_face_goal = _act_dir.angle()
	if not is_instance_valid(_act_obj):
		_eat_phase = 3
	match _eat_phase:
		0:
			if _bite.is_empty():
				if _act_obj.bites_left <= 0:
					_eat_phase = 3
					return
				_bite = _act_obj.next_bite(pos)
				var c0 := pos - _act_dir * _crept
				var fwd: float = (_bite.pos - c0).dot(_act_dir) - _bite.r * 0.5
				_creep_to = clampf(fwd - Rig.TIP - 0.28, APPROACH, MAX_CREEP)
			if _crept < _creep_to - 0.003:
				var d := minf(CREEP_SPEED * dt, _creep_to - _crept)
				_advance(pos + _act_dir * d)
				_crept += d
				_gait += d
			else:
				var to: Vector2 = _bite.pos - pos
				_lunge = clampf(to.dot(_act_dir) - _bite.r * 0.5 - Rig.TIP, 0.04, 0.42)
				var side := to.dot(_act_dir.orthogonal())
				_bite_yaw = clampf(-atan2(side, maxf(to.dot(_act_dir) - _lunge, 0.05)), -0.6, 0.6)
				_eat_phase = 1
				_t = 0.0
				_fired.clear()
		1:
			if _once("bite", BITE_AT):
				if _act_obj.bites_left > 0:
					var at: Vector2 = _act_obj.take_bite(_bite.index)
					bites_taken += 1
					rig.kick(0.5)
					if fx != null:
						fx.burst("crumbs", at, -_act_dir)
			if _once("swallow", SWALLOW_AT) and _fired.has("bite"):
				sac_level = mini(SAC_CAPACITY, sac_level + 1)
				rig.kick(1.9)
				if fx != null:
					fx.burst("gulp", rig.seg[2], Vector2.ZERO)
			if _t >= BITE_TIME:
				_bite = {}
				_t = 0.0
				_fired.clear()
				if _act_obj.bites_left <= 0:
					_eat_phase = 2
					if fx != null:
						fx.burst("sparkle", rig.seg[2], Vector2.ZERO)
				elif goal != Goal.NONE:
					_eat_phase = 3   # a new order came in: leave the rest for later
				else:
					_eat_phase = 0
		2:
			if _t >= CONTENT_TIME:
				_eat_phase = 3
		3:
			var d := minf(CREEP_SPEED * dt, _crept)
			_rewind(d)
			_crept -= d
			_gait += d
			if _crept <= 0.005:
				_crept = 0.0
				_engaged = null
				_set_state(State.IDLE)


func _tick_attack() -> void:
	_face_goal = _act_dir.angle()
	if _once("hit", HIT_AT):
		if is_instance_valid(_act_obj):
			_act_obj.take_hit(_act_dir)
			attacks_landed += 1
			_hitstop = 0.07
			impact.emit(5.0)
			if fx != null:
				fx.burst("impact", pos + _act_dir * (Rig.TIP + _lunge), _act_dir)
	if _t >= ATTACK_TIME:
		_set_state(State.IDLE)


func _apply_knock(table: Dictionary) -> void:
	var want := _tl(table, "knock", _t) * _knock_total
	var d := want - _knocked
	if d > 0.0:
		_rewind(d)
		_knocked = want
		_crept = maxf(0.0, _crept - d)
		_engaged = null


func _tick_hurt() -> void:
	_apply_knock(HURT_TL)
	if _t >= HURT_TIME:
		_set_state(State.IDLE)


func _tick_dead() -> void:
	_apply_knock(DEATH_TL)
	if sac_level > 0 and fx != null:
		for i in 3:
			if _once("leak%d" % i, 1.0 + 0.3 * i):
				fx.burst("spores", rig.seg[2], Vector2.ZERO)
	if _once("husk", 1.35):
		if fx != null:
			fx.burst("dust", rig.seg[1], Vector2.ZERO)


# ------------------------------------------------------------------ poses

func _rest_pose() -> Dictionary:
	return {
		"stretch": REST_STRETCH, "shift": 0.0, "neck": 0.0, "yaw": 0.0, "jaw": 0.0, "curl": 0.0, "fold": 0.0,
		"sac_r": 1.0, "s0": 1.0, "s1": 1.0, "ant": 0.0, "scale": 1.0, "roll": 0.0, "glow": 1.0,
		"lid": 0.0, "flash": 0.0, "life": 1.0, "eye": 0, "body": true,
		"egg": 0.0, "egg_crack": 0.0, "egg_rot": 0.0, "egg_pos": pos,
		"fill": float(sac_level) / SAC_CAPACITY,
	}


func _pose() -> Dictionary:
	var p := _rest_pose()
	var alive := true
	match state:
		State.SPAWN:
			if _t < HATCH_AT:
				p.body = false
				p.egg = _tl(SPAWN_TL, "egg", _t)
				p.egg_crack = _tl(SPAWN_TL, "crack", _t)
				p.egg_rot = _tl(SPAWN_TL, "wob", _t) * sin(_t * 17.0)
				alive = false
			for k: String in ["scale", "curl", "fold", "stretch", "yaw", "ant", "jaw"]:
				p[k] = _tl(SPAWN_TL, k, _t)
			p.eye = 1 if _t < 1.75 else 0
		State.IDLE:
			p.yaw = _look
			if _click_t >= 0.0:
				p.jaw = absf(sin(_click_t / 0.45 * TAU)) * 0.5
		State.MOVE:
			_gait_pose(p)
		State.EAT:
			if _eat_phase == 1:
				var k := _tl(BITE_TL, "lunge", _t)
				p.shift = _tl(BITE_TL, "back", _t) + k * _lunge
				p.yaw = _bite_yaw * k
				for key: String in ["jaw", "neck", "stretch", "s0", "s1", "ant"]:
					p[key] = _tl(BITE_TL, key, _t)
				p.stretch += 0.08 * k
				p.eye = 0
			elif _eat_phase == 2:
				# Fed: a pleased wriggle while the sac glows.
				var w := sin(_t / CONTENT_TIME * PI)
				p.yaw = sin(_t * 15.0) * 0.28 * w
				p.sac_r = 1.0 + 0.07 * sin(_t * 15.0 + 1.0) * w
				p.ant = 0.35 * w
				p.glow = 1.0 + 0.6 * w
				p.eye = 1
			else:
				_gait_pose(p)
		State.ATTACK:
			p.shift = _tl(ATTACK_TL, "back", _t) + _tl(ATTACK_TL, "lunge", _t) * _lunge
			for key: String in ["stretch", "jaw", "ant", "fold", "neck"]:
				p[key] = _tl(ATTACK_TL, key, _t)
			if _t > 0.3 and _t < 0.36:
				p.shift += sin(_t * 90.0) * 0.006   # tension shiver before the release
		State.HURT:
			for key: String in ["flash", "curl", "stretch", "jaw", "fold", "ant"]:
				p[key] = _tl(HURT_TL, key, _t)
			p.eye = 1 if _t < 0.45 else 0
		State.DEAD:
			alive = false
			for key: String in ["flash", "curl", "fold", "life", "roll", "jaw", "stretch", "glow", "ant"]:
				p[key] = _tl(DEATH_TL, key, _t)
			p.fill = p.fill * _tl(DEATH_TL, "fill", _t)
			p.eye = 1 if _t < 0.6 else 2
	if alive:
		# Life layer: breathing, antenna sway, blinking, sac glow pulse.
		var br := sin(_clock * 2.3)
		p.s1 *= 1.0 - 0.03 * br
		p.sac_r *= 1.0 + 0.03 * sin(_clock * 2.3 - 0.9)
		p.ant += 0.1 * sin(_clock * 1.6)
		p.glow *= 0.86 + 0.14 * sin(_clock * 2.0)
		_blink_t -= get_process_delta_time()
		if _blink_t < 0.0:
			_blink_t = randf_range(2.0, 4.5)
		p.lid = 1.0 if _blink_t < 0.12 else 0.0
	return p


func _gait_pose(p: Dictionary) -> void:
	var ph := TAU * _gait / 0.42
	p.stretch = 1.0 + 0.1 * sin(ph)
	p.s0 = 1.0 + 0.06 * sin(ph - 0.5)
	p.s1 = 1.0 + 0.07 * sin(ph - 1.3)
	p.ant = 0.12 + 0.06 * sin(ph * 0.5)
