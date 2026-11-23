extends Node2D
## A moss in its rooted stages: bud, then flower. Fixed in its cell and always upright
## (towards the top of the screen), whatever the tunnel around it does. It acts once per
## Eco.STAGE_TICK; between ticks it only animates in place.
##
## The look (moss_sprite.gd) plays the transitions: rooting (crawler -> bud), bloom, wither
## and the flower's end. Only one bud or flower may stand in a cell; crawlers pass through.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Eco := preload("res://scripts/eco/eco_spec.gd")
const Rules := preload("res://scripts/eco/eco_rules.gd")
const Look := preload("res://scripts/moss/moss_sprite.gd")

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

const FORM_SECONDS := 1.2
const BLOOM_SECONDS := 1.0
const WITHER_SECONDS := 1.4
const BURST_SECONDS := 1.2

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
var _t := 0.0
var _clock := 0.0
var _tick_clock := 0.0
var _gulp := 0.0


## A crawler at `at`, heading `crawl_heading` (a moss_sprite Heading), has rooted and holds
## `seed_collected` (what it carried; the crawler no longer has it).
func setup(g: RefCounted, at: Vector2i, seed_collected: int, crawl_heading: int) -> void:
	grid = g
	cell = at
	collected = seed_collected
	position = Spec.center(cell) * Spec.CELL_PX
	look = Node2D.new()
	look.set_script(Look)
	look.breathe = false
	look.heading = crawl_heading
	look.moving = false
	add_child(look)
	phase = Phase.FORM
	_t = 0.0
	_sync()


## Top of the plant, in world-node pixels (where its effects appear).
func head_px() -> Vector2:
	var lift := 0.05 if stage == Stage.BUD else 0.12
	return (Spec.center(cell) - Vector2(0, lift)) * Spec.CELL_PX


func gulp() -> void:
	_gulp = 1.0


func advance(delta: float) -> void:
	_clock += delta
	_t += delta
	_gulp = maxf(_gulp - delta * 3.0, 0.0)
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


func _sync() -> void:
	# The look's own stage only changes once a transition has finished playing.
	match phase:
		Phase.FORM:
			look.stage = Look.Stage.CRAWL
			look.anim = "root"
			look.anim_t = clampf(_t / FORM_SECONDS, 0.0, 1.0)
		Phase.BLOOM:
			look.stage = Look.Stage.BUD
			look.anim = "bloom"
			look.anim_t = clampf(_t / BLOOM_SECONDS, 0.0, 1.0)
		Phase.WITHER:
			look.stage = Look.Stage.BUD
			look.anim = "wither"
			look.anim_t = clampf(_t / WITHER_SECONDS, 0.0, 1.0)
		Phase.BURST:
			look.stage = Look.Stage.FLOWER
			look.anim = "release"
			look.anim_t = clampf(_t / BURST_SECONDS, 0.0, 1.0)
		_:
			look.stage = Look.Stage.BUD if stage == Stage.BUD else Look.Stage.FLOWER
			look.anim = ""
	# A starving bud yellows as its HP drops; a healthy plant keeps its colour.
	look.vigor = clampf(float(hp - 1) / 6.0, 0.0, 1.0) if stage == Stage.BUD and phase == Phase.IDLE else 1.0
	look.squash = 0.08 * sin(PI * _gulp) * _gulp
	look._t = _clock
	look.queue_redraw()
