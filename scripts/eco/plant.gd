extends Node2D
## A nutrient slime in its rooted stages: bud, then flower. Fixed in its cell and always
## upright (towards the top of the screen), whatever the tunnel around it does. It acts
## once per Eco.STAGE_TICK; between ticks it only animates in place.
##
## The node sits on the bottom edge of its cell so that growing and wilting scale from
## the ground up. Only one bud or flower may stand in a cell; crawlers pass through it.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Look := preload("res://scripts/slime/slime_look.gd")

## Drew one point of nutrient out of `from` (a soil cell).
signal drew(plant: Node2D, from: Vector2i)
signal bloomed(plant: Node2D)
## Bud ran out of HP before blooming. `collected` is what it held; the scene settles it.
signal withered(plant: Node2D, collected: int)
## Flower ran out of HP. `collected` is what it held; the scene settles it.
signal released(plant: Node2D, collected: int)
## The closing animation is over and the node can go.
signal gone(plant: Node2D)

enum Stage { BUD, FLOWER }
enum Phase { FORM, IDLE, BLOOM, WITHER, BURST }

const FORM_SECONDS := 0.95
const BLOOM_SECONDS := 0.8
const WITHER_SECONDS := 1.3
const BURST_SECONDS := 1.0
const CURL_PART := 0.45           ## share of FORM spent curling the crawler up

var grid: RefCounted
var cell := Vector2i.ZERO
var stage: int = Stage.BUD
var hp := Eco.BUD_MAX_HP
var collected := 0
var starve_ticks := 0
var alive := true
var phase: int = Phase.FORM
var ticks := 0

var look: Node2D
var _pivot: Node2D
var _crawl: Node2D
var _t := 0.0
var _clock := 0.0
var _tick_clock := 0.0
var _gulp := 0.0
var _shiver := 0.0
var _from_angle := 0.0


## A crawler at `at`, heading `crawl_angle` and showing `shown_spots`, has turned into a bud
## holding `seed_collected` (what it carried; the crawler no longer has it).
func setup(g: RefCounted, at: Vector2i, seed_collected: int, crawl_angle: float, shown_spots: int, palette := "green") -> void:
	grid = g
	cell = at
	collected = seed_collected
	position = (Spec.center(cell) + Vector2(0, 0.42)) * Spec.CELL_PX
	_pivot = Node2D.new()
	add_child(_pivot)
	look = Node2D.new()
	look.set_script(Look)
	look.breathe = false
	look.stage = Look.Stage.BUD
	look.palette = palette
	look.position = Vector2(0, -0.42) * Spec.CELL_PX
	_pivot.add_child(look)
	# The crawler it came from, drawn only while it curls up.
	_crawl = Node2D.new()
	_crawl.set_script(Look)
	_crawl.breathe = false
	_crawl.stage = Look.Stage.CRAWL
	_crawl.palette = palette
	_crawl.nutrient = shown_spots
	_crawl.vigor = 0.0
	_crawl.facing = crawl_angle
	_crawl.position = Vector2(0, -0.42) * Spec.CELL_PX
	add_child(_crawl)
	_from_angle = crawl_angle
	phase = Phase.FORM
	_t = 0.0
	_sync()


## Visible head of the plant, in world-node pixels (where motes fly to).
func head_px() -> Vector2:
	var lift := 0.05 if stage == Stage.BUD else 0.12
	return (Spec.center(cell) - Vector2(0, lift)) * Spec.CELL_PX


func gulp() -> void:
	_gulp = 1.0


func advance(delta: float) -> void:
	_clock += delta
	_t += delta
	_gulp = maxf(_gulp - delta * 3.0, 0.0)
	_shiver = maxf(_shiver - delta * 2.5, 0.0)
	if alive:
		_tick_clock += delta
		while alive and _tick_clock >= Eco.STAGE_TICK:
			_tick_clock -= Eco.STAGE_TICK
			_tick()
	match phase:
		Phase.FORM:
			if _t >= FORM_SECONDS:
				phase = Phase.IDLE
		Phase.BLOOM:
			if _t >= BLOOM_SECONDS:
				phase = Phase.IDLE
		Phase.WITHER:
			if _t >= WITHER_SECONDS:
				gone.emit(self)
		Phase.BURST:
			if _t >= BURST_SECONDS:
				gone.emit(self)
	_sync()


func _tick() -> void:
	ticks += 1
	if stage == Stage.BUD:
		var from := Rules.plant_draw(cell, Eco.BUD_RADIUS, grid)
		var got := from.x >= 0
		if got:
			collected += 1
			drew.emit(self, from)
		if collected >= Eco.BUD_TO_FLOWER:
			stage = Stage.FLOWER
			hp = Eco.FLOWER_MAX_HP
			starve_ticks = 0
			phase = Phase.BLOOM
			_t = 0.0
			bloomed.emit(self)
			return
		if got:
			starve_ticks = 0
			return
		starve_ticks += 1
		if starve_ticks >= Eco.BUD_STARVE_TICKS:
			starve_ticks = 0
			hp -= Eco.BUD_HP_DECAY
			_shiver = 1.0
			if hp <= 0:
				alive = false
				phase = Phase.WITHER
				_t = 0.0
				var had := collected
				collected = 0
				withered.emit(self, had)
		return
	# Flower.
	if collected < Eco.FLOWER_MAX_COLLECT:
		var from := Rules.plant_draw(cell, Eco.FLOWER_RADIUS, grid)
		if from.x >= 0:
			collected += 1
			drew.emit(self, from)
	hp -= Eco.FLOWER_HP_DECAY
	if hp <= 0:
		alive = false
		phase = Phase.BURST
		_t = 0.0
		var had := collected
		collected = 0
		released.emit(self, had)


func _elastic(f: float) -> float:
	# 0 -> 1 with one soft overshoot.
	return 1.0 - pow(1.0 - f, 3.0) + 0.3 * sin(PI * f) * (1.0 - f)


func _sync() -> void:
	var sx := 1.0
	var sy := 1.0
	var tilt := 0.0
	var fade := 1.0
	var vigor := 1.0
	var breath := sin(_clock * (1.2 if stage == Stage.BUD else 1.7))
	match phase:
		Phase.FORM:
			var f := _t / FORM_SECONDS
			var c := clampf(f / CURL_PART, 0.0, 1.0)
			# The crawler rears up to face the top of the screen and bunches together ...
			_crawl.visible = f < CURL_PART + 0.12
			_crawl.facing = lerp_angle(_from_angle, -PI * 0.5, smoothstep(0.0, 0.7, c))
			_crawl.stretch = -0.28 * smoothstep(0.2, 1.0, c)
			var shrink := 1.0 - smoothstep(CURL_PART - 0.05, CURL_PART + 0.12, f)
			_crawl.scale = Vector2.ONE * (1.0 - 0.15 * c) * shrink
			_crawl._t = _clock
			_crawl.queue_redraw()
			# ... and the bud pushes up out of it from the ground.
			var g := clampf((f - CURL_PART + 0.05) / (1.0 - CURL_PART + 0.05), 0.0, 1.0)
			sy = _elastic(g)
			sx = lerpf(1.35, 1.0, smoothstep(0.0, 0.6, g)) * minf(g * 3.0, 1.0)
		Phase.BLOOM:
			var f := _t / BLOOM_SECONDS
			if f < 0.3:
				# The bud squats, gathering itself ...
				look.stage = Look.Stage.BUD
				sy = 1.0 - 0.25 * smoothstep(0.0, 1.0, f / 0.3)
				sx = 1.0 + 0.18 * smoothstep(0.0, 1.0, f / 0.3)
			else:
				# ... and springs open into the flower.
				look.stage = Look.Stage.FLOWER
				var g := (f - 0.3) / 0.7
				sy = 0.55 + 0.45 * _elastic(g)
				sx = 1.25 - 0.25 * smoothstep(0.0, 1.0, g)
		Phase.IDLE:
			if stage == Stage.BUD:
				sy = 1.0 + 0.025 * breath
				sx = 1.0 - 0.015 * breath
			else:
				# The flower sways and bobs; the closer to the end, the more restless.
				var urgency := 1.0 - clampf(float(hp) / Eco.FLOWER_MAX_HP, 0.0, 1.0)
				sy = 1.0 + (0.03 + 0.03 * urgency) * sin(_clock * (2.4 + 3.0 * urgency))
				sx = 1.0 - 0.02 * sin(_clock * (2.4 + 3.0 * urgency))
				tilt = (0.05 + 0.05 * urgency) * sin(_clock * 1.3)
			if stage == Stage.BUD and hp < Eco.BUD_MAX_HP:
				vigor = clampf(float(hp - 1) / 6.0, 0.0, 1.0)
		Phase.WITHER:
			# The starved bud greys, keels over and sinks into the floor.
			var f := _t / WITHER_SECONDS
			vigor = 1.0 - smoothstep(0.0, 0.4, f)
			tilt = 0.55 * smoothstep(0.1, 0.7, f)
			sy = 1.0 - 0.75 * smoothstep(0.35, 1.0, f)
			sx = 1.0 + 0.15 * smoothstep(0.35, 1.0, f)
			fade = 1.0 - smoothstep(0.7, 1.0, f)
		Phase.BURST:
			# The spent flower swells, throws out its brood, then shrivels away.
			var f := _t / BURST_SECONDS
			var swell := smoothstep(0.0, 0.25, f) * (1.0 - smoothstep(0.25, 0.4, f))
			sx = 1.0 + 0.2 * swell + 0.06 * sin(f * 50.0) * (1.0 - smoothstep(0.0, 0.3, f))
			sy = 1.0 + 0.12 * swell - 0.85 * smoothstep(0.4, 1.0, f)
			vigor = 1.0 - smoothstep(0.35, 0.7, f)
			fade = 1.0 - smoothstep(0.8, 1.0, f)
	if phase != Phase.FORM:
		_crawl.visible = false
	# Gulp when it draws nutrient; shiver when hunger costs it HP.
	sy *= 1.0 + 0.1 * sin(PI * _gulp) * _gulp
	sx *= 1.0 - 0.05 * sin(PI * _gulp) * _gulp
	tilt += 0.08 * sin(_clock * 45.0) * _shiver
	_pivot.scale = Vector2(sx, maxf(sy, 0.0))
	_pivot.rotation = tilt
	modulate.a = fade
	look.vigor = vigor
	look._t = _clock
	look.queue_redraw()
