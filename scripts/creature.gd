extends Node2D
## Sporeback behaviour: a small state machine that owns position, intent and timing.
## Every animation is a function of the current state and its clock, and gameplay
## events (bite, hit, death) fire from the same clock, so visuals and logic cannot drift.

signal state_changed(new_state: int)
signal impact(strength: float)
signal notice(text: String)

enum State { HIDDEN, SPAWN, IDLE, MOVE, TURN, EAT, ATTACK, HURT, DEAD }
enum Intent { NONE, MOVE, EAT, ATTACK }

const STATE_NAMES: Array[String] = ["未出生", "出生", "待机", "移动", "转身", "进食", "攻击", "受击", "死亡"]

const Pose := preload("res://scripts/creature_pose.gd")

const WALK_SPEED := 72.0
const GAIT_LEN := 26.0      ## ground covered per full leg cycle
const GAIT_DUTY := 0.6      ## fraction of the cycle a foot stays planted
const GAIT_PHASE: Array[float] = [0.5, 0.0, 0.0, 0.5]  # trot: diagonal pairs
const EAT_DIST := 40.0      ## stand this far from the food
const ATTACK_DIST := 84.0   ## stand this far from the dummy (snout reaches its pad at full lunge)
const BLEND_TIME := 0.13
const TURN_TIME := 0.22
const BITE_TIME := 0.8
const BITE_AT := 0.28
const HIT_AT := 0.42
const KNOCKBACK := 22.0

# Timelines: key -> [time, value, time, value, ...], smoothstep between keys.
# Values are added to the neutral/idle pose (sx, sy and glow multiply).
const SPAWN_TIME := 3.1
const SPAWN_TL := {
	"lift": [0.9, -62, 1.12, -17, 1.25, -20, 1.9, -20, 2.2, 5, 2.36, 0],
	"body_rot": [1.9, 0, 2.1, -0.22, 2.36, 0],
	"sy": [2.36, 1, 2.44, 0.84, 2.6, 1.05, 2.75, 1],
	"sx": [2.36, 1, 2.44, 1.1, 2.6, 0.98, 2.75, 1],
	"look_x": [1.25, 0, 1.4, -1, 1.58, -1, 1.75, 1, 1.9, 1, 2.3, 0],
	"lid": [1.58, 0, 1.64, 1, 1.70, 0],
	"ear": [1.2, 0, 1.3, 0.8, 1.5, 0, 1.7, 0.6, 1.9, 0],
	"front_lift": [1.9, 0, 2.1, 3, 2.36, 0],
}
const MOUND_TL: Array = [0.0, 0, 0.9, 9, 1.2, 11, 1.9, 11, 2.3, 4, 3.1, 0]
const HOLE_TL: Array = [0.8, 0, 1.1, 1, 2.4, 1, 3.1, 0]

const BITE_TL := {
	"head_x": [0.0, 0, 0.2, 8.5, 0.3, 9.5, 0.45, 3, 0.8, 0],
	"head_y": [0.0, 0, 0.2, 8, 0.28, 10, 0.45, 3, 0.8, 0],
	"head_rot": [0.0, 0, 0.2, 0.42, 0.28, 0.5, 0.45, 0.15, 0.8, 0],
	"jaw": [0.0, 0, 0.18, 1, 0.24, 1, 0.29, 0],
	"body_x": [0.0, 0, 0.2, 4, 0.45, 2, 0.8, 0],
	"body_rot": [0.0, 0, 0.2, 0.07, 0.5, 0.03, 0.8, 0],
	"lid": [0.3, 0, 0.4, 0.4, 0.7, 0.4, 0.8, 0],
	"tail": [0.0, 0.25, 0.2, 0.4, 0.8, 0.25],
}
const SWALLOW_TIME := 1.0
const SWALLOW_TL := {
	"head_y": [0.0, 0, 0.18, -4, 0.3, -2, 1.0, 0],
	"head_rot": [0.0, 0, 0.18, -0.3, 0.32, -0.1, 0.5, -0.2, 1.0, 0],
	"sx": [0.15, 1, 0.25, 1.07, 0.4, 1],
	"sy": [0.15, 1, 0.25, 0.95, 0.4, 1],
	"lift": [0.4, 0, 0.52, 5, 0.64, 0, 0.72, 2.5, 0.8, 0],
	"glow": [0.25, 1, 0.45, 1.9, 1.0, 1],
	"tail": [0.0, 0.25, 0.4, 0.5, 1.0, 0],
}

const ATTACK_TIME := 1.0
const ATTACK_TL := {
	"body_x": [0.0, 0, 0.30, -7, 0.34, -7.5, 0.42, 15, 0.50, 10.5, 0.62, 11, 0.85, -1.2, 1.0, 0],
	"body_y": [0.0, 0, 0.30, 3, 0.42, 0.5, 0.62, 1, 1.0, 0],
	"body_rot": [0.0, 0, 0.30, 0.13, 0.42, -0.02, 0.5, 0.05, 1.0, 0],
	"sx": [0.30, 1, 0.36, 1, 0.42, 1.17, 0.48, 0.9, 0.6, 1.03, 0.8, 1],
	"sy": [0.0, 1, 0.30, 0.9, 0.42, 0.9, 0.48, 1.08, 0.7, 1],
	"head_x": [0.0, 0, 0.30, -3, 0.42, 6, 0.5, 1.5, 1.0, 0],
	"head_y": [0.0, 0, 0.30, 3, 0.42, 1, 1.0, 0],
	"head_rot": [0.0, 0, 0.30, 0.38, 0.42, 0.12, 0.5, 0.3, 0.7, 0, 1.0, 0],
	"brow": [0.0, 0, 0.12, 1, 0.6, 1, 0.85, 0],
	"lid": [0.0, 0, 0.15, 0.25, 0.6, 0.25, 0.8, 0],
	"tail": [0.0, 0, 0.30, 0.55, 0.42, -0.3, 1.0, 0],
	"ear": [0.0, 0, 0.30, -0.6, 0.42, 0.5, 1.0, 0],
	"front_x": [0.30, 0, 0.42, 9, 0.62, 9, 0.82, 0],
	"front_lift": [0.32, 0, 0.37, 4, 0.42, 0, 0.62, 0, 0.72, 3.5, 0.82, 0],
}

const HURT_TIME := 0.62
const HURT_TL := {
	"lift": [0.0, 0, 0.11, 7, 0.24, 0],
	"body_rot": [0.0, 0, 0.08, -0.34, 0.24, -0.12, 0.34, 0.1, 0.62, 0],
	"sx": [0.0, 1, 0.06, 0.84, 0.2, 1.05, 0.3, 1],
	"sy": [0.0, 1, 0.06, 1.12, 0.24, 1, 0.3, 0.82, 0.45, 1.04, 0.62, 1],
	"head_rot": [0.0, 0, 0.08, -0.5, 0.3, 0.2, 0.62, 0],
	"head_x": [0.0, 0, 0.08, -4, 0.4, 0],
	"jaw": [0.0, 0, 0.06, 0.8, 0.3, 0.5, 0.5, 0],
	"flash": [0.0, 1, 0.09, 1, 0.16, 0],
	"ear": [0.0, 0, 0.08, 0.9, 0.4, -0.2, 0.62, 0],
	"tail": [0.0, 0, 0.08, 0.7, 0.62, 0],
	"glow": [0.0, 1, 0.05, 0.4, 0.6, 1],
	"front_x": [0.0, 0, 0.1, 3, 0.24, 0],
	"back_x": [0.0, 0, 0.1, -2, 0.24, 0],
}

const DEATH_TIME := 2.3
const DEATH_KNOCK := 9.0
const DEATH_TL := {
	"lift": [0.0, 0, 0.09, 4, 0.2, 0],
	"flash": [0.0, 1, 0.09, 1, 0.16, 0],
	"body_rot": [0.0, 0, 0.08, -0.3, 0.3, 0.08, 0.55, -0.14, 0.8, 0.12, 1.0, -0.05, 1.3, 0.06, 1.5, 0.04],
	"body_x": [0.2, 0, 0.55, -3, 0.8, 3, 1.0, -1.5, 1.3, 2],
	"body_y": [0.9, 0, 1.05, 1, 1.28, 5.5, 1.36, 4, 1.45, 5],
	"sy": [1.0, 1, 1.28, 0.8, 1.38, 0.92, 1.5, 0.86],
	"sx": [1.0, 1, 1.28, 1.1, 1.5, 1.06],
	"front_x": [1.0, 0, 1.3, 7],
	"back_x": [1.0, 0, 1.3, -6],
	"head_x": [1.0, 0, 1.32, 3],
	"head_y": [0.9, 0, 1.1, 1, 1.32, 4, 1.4, 2.2, 1.5, 3],
	"head_rot": [0.0, 0, 0.08, -0.4, 0.3, 0.1, 0.9, 0.15, 1.32, 0.3, 1.5, 0.24],
	"jaw": [0.0, 0, 0.06, 0.8, 0.3, 0.3, 0.9, 0.2, 1.3, 0.15, 1.6, 0.32],
	"lid": [0.3, 0, 0.6, 0.5, 0.9, 0.35, 1.1, 0.7],
	"tail": [0.0, 0, 0.08, 0.6, 0.9, 0.1, 1.3, -0.75, 1.9, -0.75, 1.98, -0.45, 2.12, -0.8],
	"ear": [0.0, 0, 0.08, 0.8, 0.5, 0, 1.3, -0.9, 1.6, -1.3],
	"shroom": [1.15, 0, 1.9, 1],
	"glow": [0.0, 1, 0.1, 0.3, 0.3, 0.9, 0.5, 0.4, 0.7, 0.8, 0.95, 0.3, 1.2, 0.5, 1.9, 0],
	"life": [1.3, 1, 2.2, 0],
}

var state: int = State.HIDDEN
var facing := 1.0
var intent: int = Intent.NONE
var intent_x := 0.0
var min_x := 0.0
var max_x := 1000.0
var food: Node2D
var dummy: Node2D
var fx: Node2D
var cave: Node2D
var ground: Node2D

# Counters the self-test reads.
var bites_taken := 0
var attacks_landed := 0
var hurt_count := 0

var _t := 0.0
var _clock := 0.0
var _hitstop := 0.0
var _from: RefCounted = Pose.new()
var _shown: RefCounted = Pose.new()
var _blend := 1.0
var _flags := {}
var _speed := 0.0
var _gait := 0.0
var _turn_to := 1.0
var _goal_x := 0.0
var _goal_face := 0.0
var _swallowing := false
var _bite_start := 0.0
var _bite_dip := 1.0
var _hurt_dir := -1.0
var _hurt_x := 0.0
var _blink_at := 1.0
var _blink_t := 0.0
var _look := Vector2.ZERO
var _look_target := Vector2.ZERO
var _look_at := 0.0
var _sniff_at := 3.0
var _sniff_t := 0.0

@onready var rig: Node2D = $Rig


func _ready() -> void:
	rig.visible = false


# --------------------------------------------------------------------------- commands

func reset() -> void:
	state = State.HIDDEN
	intent = Intent.NONE
	facing = 1.0
	_hitstop = 0.0
	_blend = 1.0
	_shown = Pose.new()
	_flags.clear()
	bites_taken = 0
	attacks_landed = 0
	hurt_count = 0
	rig.visible = false
	rig.scale.x = 1.0
	rig.reset_springs()
	_set_burrow(0.0, 0.0)
	state_changed.emit(state)


func spawn(at_x: float) -> void:
	reset()
	global_position.x = at_x
	_set_state(State.SPAWN)
	_blend = 1.0  # no blend: it starts underground


func command_move(x: float) -> void:
	if _commandable():
		intent = Intent.MOVE
		intent_x = clampf(x, min_x, max_x)


func command_eat() -> void:
	if _commandable():
		intent = Intent.EAT


func command_attack() -> void:
	if _commandable():
		intent = Intent.ATTACK


## Returns true if the hit connected. Spawning and dead creatures cannot be hit.
func take_hit(from_x: float, lethal: bool) -> bool:
	if state == State.HIDDEN or state == State.SPAWN or state == State.DEAD:
		return false
	if state == State.TURN and _t > TURN_TIME * 0.5:
		facing = _turn_to
	intent = Intent.NONE
	_hitstop = 0.0
	_hurt_dir = 1.0 if global_position.x >= from_x else -1.0
	_hurt_x = global_position.x
	hurt_count += 1
	_set_state(State.DEAD if lethal else State.HURT)
	return true


func is_dead_settled() -> bool:
	return state == State.DEAD and _t >= DEATH_TIME


func is_busy() -> bool:
	return state != State.IDLE or intent != Intent.NONE


func head_pos() -> Vector2:
	return global_position + Vector2(facing * (24.0 + _shown.body_x + _shown.head_x), -26.0 + _shown.body_y + _shown.head_y - _shown.lift)


func back_pos() -> Vector2:
	return global_position + Vector2(facing * (-2.0 + _shown.body_x), -46.0 + _shown.body_y - _shown.lift)


func _commandable() -> bool:
	return state != State.HIDDEN and state != State.DEAD


# --------------------------------------------------------------------------- core loop

func _set_state(s: int) -> void:
	_from = _shown.copy()
	_blend = 0.0
	state = s
	_t = 0.0
	_flags.clear()
	state_changed.emit(s)


func _once(key: String) -> bool:
	if _flags.has(key):
		return false
	_flags[key] = true
	return true


func _process(delta: float) -> void:
	if state == State.HIDDEN:
		rig.visible = false
		return
	rig.visible = true
	var dt := delta
	if _hitstop > 0.0:
		_hitstop -= delta
		dt = 0.0
	_clock += dt
	_t += dt

	var p: RefCounted = Pose.new()
	_idle_layer(p, dt)
	var turn_scale := facing
	match state:
		State.SPAWN: _tick_spawn(p)
		State.IDLE: _tick_idle(p, dt)
		State.MOVE: _tick_move(p, dt)
		State.TURN:
			var u := clampf(_t / TURN_TIME, 0.0, 1.0)
			turn_scale = lerpf(facing, _turn_to, smoothstep(0.0, 1.0, u))
			p.lift += sin(PI * u) * 3.0
			p.sy *= 1.0 + 0.05 * sin(PI * u)
			if u >= 1.0:
				facing = _turn_to
				turn_scale = facing
				_set_state(State.IDLE)
		State.EAT: _tick_eat(p)
		State.ATTACK: _tick_attack(p)
		State.HURT: _tick_hurt(p)
		State.DEAD: _tick_dead(p)

	_blend = minf(1.0, _blend + dt / BLEND_TIME)
	if _blend < 1.0:
		p.blend_from(_from, smoothstep(0.0, 1.0, _blend))
	_shown = p
	rig.scale.x = turn_scale
	rig.show_pose(p, dt)


## Life signs shared by every living state: breathing, blinking, wandering gaze.
func _idle_layer(p: RefCounted, dt: float) -> void:
	if state == State.DEAD:
		return
	var breath := sin(_clock * 2.6)
	p.sy = 1.0 + 0.03 * breath
	p.sx = 1.0 - 0.015 * breath
	p.glow = 1.0 + 0.1 * sin(_clock * 1.7)
	p.tail = 0.12 * sin(_clock * 2.1)
	if _clock >= _blink_at:
		_blink_t = 0.16
		_blink_at = _clock + randf_range(1.6, 4.0)
	if _blink_t > 0.0:
		_blink_t -= dt
		p.lid = sin(PI * clampf(1.0 - _blink_t / 0.16, 0.0, 1.0))
	if _clock >= _look_at:
		_look_target = Vector2(randf_range(-1.0, 1.0), randf_range(-0.4, 0.6)) if randf() < 0.7 else Vector2.ZERO
		_look_at = _clock + randf_range(1.2, 3.2)
	_look = _look.lerp(_look_target, 1.0 - exp(-8.0 * dt))
	p.look_x = _look.x
	p.look_y = _look.y


static func _track(t: float, k: Array) -> float:
	if t <= k[0]:
		return k[1]
	var n := k.size()
	for i in range(2, n, 2):
		if t <= k[i]:
			var u: float = (t - k[i - 2]) / (k[i] - k[i - 2])
			return lerpf(k[i - 1], k[i + 1], u * u * (3.0 - 2.0 * u))
	return k[n - 1]


func _foot_add(p: RefCounted, i: int, dx: float, dl: float) -> void:
	var f: Vector2 = p.feet[i]
	f.x += dx
	f.y += dl
	p.feet[i] = f


func _apply_tl(p: RefCounted, tl: Dictionary, t: float, weight := 1.0) -> void:
	for key: String in tl:
		var v := _track(t, tl[key])
		match key:
			"sx": p.sx *= lerpf(1.0, v, weight)
			"sy": p.sy *= lerpf(1.0, v, weight)
			"glow": p.glow *= v
			"life": p.life = v
			"front_x":
				_foot_add(p, 0, v, 0.0)
				_foot_add(p, 2, v, 0.0)
			"front_lift":
				_foot_add(p, 0, 0.0, v)
				_foot_add(p, 2, 0.0, v)
			"back_x":
				_foot_add(p, 1, v, 0.0)
				_foot_add(p, 3, v, 0.0)
			"back_lift":
				_foot_add(p, 1, 0.0, v)
				_foot_add(p, 3, 0.0, v)
			_:
				var cur: float = p.get(key)
				p.set(key, cur + v * weight)


func _burst(kind: String, pos: Vector2, dir := Vector2.ZERO) -> void:
	if fx != null:
		fx.burst(kind, pos, dir)


func _set_burrow(mound: float, hole: float) -> void:
	if ground != null:
		ground.set_mound(global_position.x, mound)
	if cave != null:
		cave.set_hole(global_position.x, hole)


# --------------------------------------------------------------------------- states

func _tick_spawn(p: RefCounted) -> void:
	_apply_tl(p, SPAWN_TL, _t)
	var gx := global_position
	var mound := _track(_t, MOUND_TL)
	if _t < 0.9:
		mound += sin(_t * 55.0) * 0.9
		if _once("rumble%d" % int(_t / 0.2)):
			_burst("dirt_small", gx + Vector2(randf_range(-10, 10), -4))
	_set_burrow(mound, _track(_t, HOLE_TL))
	if _t >= 0.9 and _once("break"):
		_burst("dirt", gx + Vector2(0, -6))
		impact.emit(2.0)
		rig.kick(-5.0)
	if _t >= 1.9 and _once("heave"):
		_burst("dirt", gx + Vector2(0, -6))
		rig.kick(4.0)
	if _t >= 2.36 and _once("land"):
		_burst("dust", gx + Vector2(0, -1))
		rig.kick(-3.0)
	# Shake the dirt off.
	if _t >= 2.55 and _t < 3.05:
		var env := sin(PI * (_t - 2.55) / 0.5)
		p.body_rot += sin((_t - 2.55) * 44.0) * 0.09 * env
		p.head_rot -= sin((_t - 2.55) * 44.0) * 0.12 * env
		p.eye = 1
		if _once("shake%d" % int((_t - 2.55) / 0.12)):
			rig.kick(6.0 if int((_t - 2.55) / 0.12) % 2 == 0 else -6.0)
			_burst("dirt_small", back_pos() + Vector2(randf_range(-10, 10), 6))
	if _t >= SPAWN_TIME:
		_set_state(State.IDLE)


func _tick_idle(p: RefCounted, dt: float) -> void:
	p.body_x += sin(_clock * 0.9) * 0.8
	if _clock >= _sniff_at:
		_sniff_t = 0.5
		_sniff_at = _clock + randf_range(3.0, 5.5)
		rig.kick(2.5)
	if _sniff_t > 0.0:
		_sniff_t -= dt
		var e := sin(PI * clampf(1.0 - _sniff_t / 0.5, 0.0, 1.0))
		p.head_y += sin(_clock * 34.0) * 0.9 * e
		p.head_x += 1.6 * e
		p.head_rot -= 0.08 * e
		p.ear += 0.5 * e
	if intent != Intent.NONE:
		_pursue()


## Works out where the current intent wants the creature to stand and which way to face.
func _resolve_goal() -> bool:
	match intent:
		Intent.MOVE:
			_goal_x = intent_x
			_goal_face = 0.0
		Intent.EAT:
			if food == null or food.bites_left <= 0:
				intent = Intent.NONE
				notice.emit("没有食物了（按 F 补充）")
				return false
			var side := -1.0 if global_position.x <= food.global_position.x else 1.0
			_goal_x = food.global_position.x + side * EAT_DIST
			_goal_face = -side
		Intent.ATTACK:
			if dummy == null:
				intent = Intent.NONE
				return false
			_goal_x = dummy.global_position.x - ATTACK_DIST
			_goal_face = 1.0
		_:
			return false
	_goal_x = clampf(_goal_x, min_x, max_x)
	return true


func _start_turn(to: float) -> void:
	_turn_to = to
	_set_state(State.TURN)


func _pursue() -> void:
	if not _resolve_goal():
		return
	var dx := _goal_x - global_position.x
	if absf(dx) > 1.0:
		var dir := signf(dx)
		if dir != facing:
			_start_turn(dir)
		else:
			_speed = 0.0
			_set_state(State.MOVE)
		return
	if _goal_face != 0.0 and _goal_face != facing:
		_start_turn(_goal_face)
		return
	match intent:
		Intent.MOVE:
			intent = Intent.NONE
		Intent.EAT:
			_swallowing = false
			_bite_start = 0.0
			_set_state(State.EAT)
			_begin_bite()
		Intent.ATTACK:
			intent = Intent.NONE
			_set_state(State.ATTACK)


func _gait_foot(ph: float) -> Vector2:
	var stride := GAIT_LEN * GAIT_DUTY
	if ph < GAIT_DUTY:
		# Stance: the foot travels backwards exactly as fast as the body goes forwards.
		return Vector2(stride * (0.5 - ph / GAIT_DUTY), 0.0)
	var u := (ph - GAIT_DUTY) / (1.0 - GAIT_DUTY)
	return Vector2(stride * (-0.5 + u * u * (3.0 - 2.0 * u)), sin(PI * u) * 5.0)


func _tick_move(p: RefCounted, dt: float) -> void:
	if not _resolve_goal():
		_set_state(State.IDLE)
		return
	var dx := _goal_x - global_position.x
	if absf(dx) <= 1.0 or signf(dx) != facing:
		if absf(dx) <= 1.0:
			global_position.x = _goal_x
		_set_state(State.IDLE)
		return
	var want := minf(WALK_SPEED, maxf(18.0, absf(dx) * 7.0))
	_speed = move_toward(_speed, want, 480.0 * dt)
	var step := minf(_speed * dt, absf(dx))
	global_position.x += facing * step
	_gait = fposmod(_gait + step / GAIT_LEN, 1.0)
	for i in 4:
		p.feet[i] = _gait_foot(fposmod(_gait + GAIT_PHASE[i], 1.0))
	var w := sin(_gait * TAU)
	p.body_y += 0.8 - absf(w) * 1.6
	p.body_rot += w * 0.035
	p.head_y += sin(_gait * TAU * 2.0 + 1.0) * 0.9
	p.head_rot += 0.05
	p.look_x = 0.7
	p.look_y = 0.1
	p.tail += w * 0.25 + 0.15
	p.ear += 0.2


func _begin_bite() -> void:
	_bite_start = _t
	_flags.erase("bite")
	var off: Vector2 = food.next_bite_offset(global_position.x)
	_bite_dip = clampf(remap(-off.y, 5.0, 14.0, 1.0, 0.55), 0.55, 1.0)


func _tick_eat(p: RefCounted) -> void:
	if _swallowing:
		var s := _t - _bite_start
		_apply_tl(p, SWALLOW_TL, s)
		if s > 0.25 and s < 0.9:
			p.eye = 3
			p.tail += sin(s * 32.0) * 0.3
		if s >= 0.42 and _once("yum"):
			_burst("sparkle", back_pos())
			rig.kick(5.0)
		if s >= SWALLOW_TIME:
			intent = Intent.NONE
			_set_state(State.IDLE)
		return

	var u := _t - _bite_start
	_apply_tl(p, BITE_TL, u, _bite_dip)
	if u > 0.36:
		var chew := absf(sin((u - 0.36) * PI * 5.0)) * (1.0 - clampf((u - 0.7) / 0.1, 0.0, 1.0))
		p.jaw += 0.3 * chew
		p.sy *= 1.0 + 0.03 * chew
		p.head_y += chew * 0.8
	if u >= BITE_AT and _once("bite"):
		# The bite only counts if the food is still there when the jaw shuts.
		if food.bites_left > 0:
			var at: Vector2 = food.take_bite(global_position.x)
			bites_taken += 1
			_burst("crumbs", at, Vector2(-facing, -1))
			rig.kick(-3.0)
	if u >= BITE_TIME:
		if food.bites_left <= 0:
			_swallowing = true
			_bite_start = _t
		elif intent != Intent.EAT:
			_set_state(State.IDLE)  # interrupted between bites; food keeps what is left
		else:
			_begin_bite()


func _tick_attack(p: RefCounted) -> void:
	_apply_tl(p, ATTACK_TL, _t)
	if _t < 0.3:
		p.body_x += sin(_t * 70.0) * 0.5 * (_t / 0.3)  # coiled tremble
	if _t >= HIT_AT and _once("hit"):
		var tip := global_position.x + facing * 62.0
		if dummy != null and dummy.is_in_front(tip, facing):
			dummy.take_hit(facing)
			attacks_landed += 1
			_burst("impact", Vector2(tip, global_position.y - 24.0), Vector2(facing, 0))
			_hitstop = 0.08
			impact.emit(5.0)
			rig.kick(7.0)
	if _t >= ATTACK_TIME:
		_set_state(State.IDLE)


func _knock(dist: float, dur: float) -> void:
	var u := clampf(_t / dur, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 3.0)
	global_position.x = clampf(_hurt_x + _hurt_dir * dist * e, min_x, max_x)


func _tick_hurt(p: RefCounted) -> void:
	_knock(KNOCKBACK, 0.24)
	var from_front := _hurt_dir != facing
	_apply_tl(p, HURT_TL, _t)
	if not from_front:
		p.body_rot = -p.body_rot
		p.head_rot = -p.head_rot
	if _t < 0.45:
		p.eye = 1
	if _t > 0.34 and _t < 0.56:
		p.head_rot += sin((_t - 0.34) * 52.0) * 0.1
	if _once("ouch"):
		_burst("impact", head_pos(), Vector2(_hurt_dir, -0.3))
		_burst("spores", back_pos())
		rig.kick(9.0 if from_front else -9.0)
		impact.emit(4.0)
	if _t >= 0.24 and _once("land"):
		_burst("dust", global_position)
	if _t >= HURT_TIME:
		_set_state(State.IDLE)


func _tick_dead(p: RefCounted) -> void:
	var t := minf(_t, DEATH_TIME)
	if _t <= 0.3:
		_knock(DEATH_KNOCK, 0.2)
	_apply_tl(p, DEATH_TL, t)
	if t < 0.3:
		p.eye = 1
	elif t >= 1.3:
		p.eye = 2
	if _once("ouch"):
		_burst("impact", head_pos(), Vector2(_hurt_dir, -0.3))
		_burst("spores", back_pos())
		rig.kick(8.0)
		impact.emit(5.0)
	if t >= 1.28 and _once("thud"):
		_burst("dust", global_position + Vector2(facing * 8.0, 0))
		impact.emit(2.5)
		rig.kick(4.0)
	if t >= 1.6 and _once("soul"):
		_burst("soul", back_pos() + Vector2(0, 14))
