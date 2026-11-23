extends Node2D
## Look of the moss (苔) played from sprites pre-rendered with SpriteKiln (task ART-007).
## It replaced the code-drawn look (moss_look.gd, in Git history) and kept its owner-driven interface, so the
## ecology scripts only had to change which script they load: the owner sets `stage`,
## `heading`, `step`, `anim`, `anim_t`, `vigor`... every frame and this node shows the frame
## that matches.
##
## Sources: art_src/specs/characters/moss (the crawler; 4 directions: sideways it is seen from
## the side, going up from behind, coming down from the front) and moss_plant (the rooted
## bud and flower; one view, always upright).
##
## Rooting is a hand-off between the two models: the crawler plays `root_in` (stops, stands
## its sprout up and spreads into a round mat), then the plant plays `root` from that same mat.
## Yellowing and the final fade are not in the art: they come from sprite_fx.gdshader.
##
## The node origin is the CELL CENTRE. Drawing only; no game logic.

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const CrawlFrames := preload("res://assets/spritekiln/moss/moss.tres")
const PlantFrames := preload("res://assets/spritekiln/moss_plant/moss_plant.tres")
const FxShader := preload("res://scripts/fx/sprite_fx.gdshader")

enum Heading { RIGHT, LEFT, UP, DOWN }
enum Stage { CRAWL, BUD, FLOWER }

const DIR := ["e", "w", "n", "s"]         ## by Heading
const FLOOR_Y := 0.43                     ## cells below the cell centre: top of the floor lip
const SHAFT_Y := 0.30                     ## where the crawler's underside is while in a shaft
const PIVOT := Vector2(-32, -54)          ## frame corner relative to the ground point (from the export)
const WALK_FRAMES := 8
const IDLE_FRAMES := 6
const IDLE_FPS := 1.0 / 0.17
const PLANT_FPS := 1.0 / 0.18
const ROOT_SPLIT := 0.45                  ## share of the rooting time the crawler's own part takes

var stage: int = Stage.CRAWL      ## bud and flower are rooted: fixed in the cell, always upright
var heading: int = Heading.RIGHT
var vigor := 1.0                  ## 1 healthy .. 0 spent
var step := 0.0                   ## crawl cycle position; one unit per cell travelled
var moving := true
## A transition being played, driven by the owner: "root" (crawler -> bud, stage still
## CRAWL), "starve" (crawler dying), "bloom" (stage BUD), "wither" (stage BUD),
## "release" (stage FLOWER), or "".
var anim := ""
var anim_t := 0.0                 ## 0..1 progress of `anim`
## Crawler only. Where it sits in the cell: 1 on the tunnel floor, 0 in mid-cell (in a
## shaft). Negative: decide from `heading`.
var seat := -1.0
var squash := 0.0                 ## >0 presses it flat and wide for a moment (gulp, turn, landing)
var flash := 0.0                  ## 0..1 pale blink (being bitten)
var breathe := true               ## advance its own clock (previews); owners may set _t

var _t := 0.0
var _crawl: AnimatedSprite2D
var _plant: AnimatedSprite2D
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = FxShader
	_mat.set_shader_parameter("seed", float(get_instance_id() % 97))
	_crawl = _make(CrawlFrames)
	_plant = _make(PlantFrames)
	_show()


func _make(frames: SpriteFrames) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.centered = false
	s.offset = PIVOT
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.material = _mat
	add_child(s)
	return s


func _process(delta: float) -> void:
	if breathe:
		_t += delta
	_show()


## Visual bounds in cells, centred on the node.
func visual_half_extent() -> Vector2:
	return Vector2(0.44, 0.46)


func _frame(sprite: AnimatedSprite2D, clip: StringName, index: int) -> void:
	sprite.animation = clip
	sprite.frame = clampi(index, 0, sprite.sprite_frames.get_frame_count(clip) - 1)


## Frame of a clip played once over 0..1.
func _once(sprite: AnimatedSprite2D, clip: StringName, t: float) -> void:
	var n := sprite.sprite_frames.get_frame_count(clip)
	_frame(sprite, clip, int(clampf(t, 0.0, 0.9999) * n))


func _show() -> void:
	if _crawl == null:
		return
	var u := Spec.CELL_PX
	var dir: String = DIR[heading]
	var side := heading == Heading.RIGHT or heading == Heading.LEFT
	var wither := 0.6 * (1.0 - clampf(vigor, 0.0, 1.0))
	var dissolve := 0.0
	var press := squash
	var crawl_shown := stage == Stage.CRAWL

	if stage == Stage.CRAWL and anim == "root":
		# first the crawler's own half, then the plant grows out of the mat it left
		if anim_t < ROOT_SPLIT:
			_once(_crawl, StringName("root_in_" + dir), anim_t / ROOT_SPLIT)
		else:
			crawl_shown = false
			_once(_plant, &"root_s", (anim_t - ROOT_SPLIT) / (1.0 - ROOT_SPLIT))
	elif stage == Stage.CRAWL and anim == "starve":
		# no clip for this: it stops, dries out, slumps and crumbles away
		_frame(_crawl, StringName("idle_" + dir), 0)
		wither = maxf(wither, smoothstep(0.0, 0.45, anim_t))
		press += 0.30 * smoothstep(0.1, 0.6, anim_t)
		dissolve = smoothstep(0.5, 1.0, anim_t)
	elif stage == Stage.CRAWL:
		if moving:
			_frame(_crawl, StringName("walk_" + dir), int(fposmod(step, 1.0) * WALK_FRAMES))
		else:
			_frame(_crawl, StringName("idle_" + dir), int(_t * IDLE_FPS) % IDLE_FRAMES)
	elif anim == "bloom":
		_once(_plant, &"bloom_s", anim_t)
	elif anim == "wither":
		_once(_plant, &"wither_s", anim_t / 0.8)
		wither = maxf(wither, smoothstep(0.0, 0.6, anim_t))
		dissolve = smoothstep(0.75, 1.0, anim_t)
	elif anim == "release":
		_once(_plant, &"release_s", anim_t / 0.85)
		wither = smoothstep(0.3, 0.75, anim_t)
		dissolve = smoothstep(0.8, 1.0, anim_t)
	else:
		var clip := &"bud_s" if stage == Stage.BUD else &"flower_s"
		_frame(_plant, clip, int(_t * PLANT_FPS) % _plant.sprite_frames.get_frame_count(clip))

	_crawl.visible = crawl_shown
	_plant.visible = not crawl_shown
	# The sprites' origin is the ground under them. Rooted plants stand on the floor lip; the
	# crawler does too in a corridor, and sits a little higher while it is in a shaft.
	var seat_k := (1.0 if side else 0.0) if seat < 0.0 else clampf(seat, 0.0, 1.0)
	_crawl.position = Vector2(0, lerpf(SHAFT_Y, FLOOR_Y, seat_k) * u)
	_plant.position = Vector2(0, FLOOR_Y * u)
	var s := Vector2(1.0 + 0.5 * press, 1.0 - press)
	_crawl.scale = s
	_plant.scale = s
	_mat.set_shader_parameter("wither", wither)
	_mat.set_shader_parameter("dissolve", dissolve)
	_mat.set_shader_parameter("flash", flash)
