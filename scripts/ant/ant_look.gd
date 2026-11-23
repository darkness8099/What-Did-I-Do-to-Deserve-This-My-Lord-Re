extends Node2D
## Look of one leaf-cutter ant, played from sprites pre-rendered with SpriteKiln (task ART-006).
## Sources: art_src/specs/characters/ant (side view, used when heading left / right) and
## ant_top (seen from straight above, used when heading up / down: the ant hugs the surface it
## walks on, so in a shaft the side-on camera sees its back).
##
## The node origin is the CELL CENTRE. No movement and no game logic here.

const SideScene := preload("res://assets/spritekiln/ant/ant.tscn")
const TopScene := preload("res://assets/spritekiln/ant_top/ant_top.tscn")
const DissolveShader := preload("res://scripts/fx/pixel_dissolve.gdshader")

enum Heading { RIGHT, DOWN, LEFT, UP }

const FLOOR_Y := 0.43            ## cells below the cell centre: top of the floor lip (same as the moss)
const CELL_PX := 64.0

signal anim_finished(anim: StringName)

var heading: int = Heading.RIGHT:
	set(v):
		heading = v
		_apply_heading()

## 0 = whole, 1 = fully dissolved (death).
var dissolve := 0.0:
	set(v):
		dissolve = clampf(v, 0.0, 1.0)
		if _mat:
			_mat.set_shader_parameter("progress", dissolve)

var _side: AnimatedSprite2D
var _top: AnimatedSprite2D
var _mat: ShaderMaterial
var _anim: StringName = &"idle"


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = DissolveShader
	_mat.set_shader_parameter("seed", float(get_instance_id() % 97))
	_side = SideScene.instantiate()
	_side.position = Vector2(0, FLOOR_Y * CELL_PX)      # its origin is the ground under the feet
	_side.material = _mat
	add_child(_side)
	_top = TopScene.instantiate()
	_top.material = _mat                                # its origin is the middle of the body
	add_child(_top)
	_side.anim_finished.connect(func(a): if _is_side(): anim_finished.emit(a))
	_top.anim_finished.connect(func(a): if not _is_side(): anim_finished.emit(a))
	_apply_heading()
	play(_anim)


func play(anim: StringName, restart: bool = false) -> void:
	_anim = anim
	if _side:
		_side.play_anim(anim, restart)
		_top.play_anim(anim, restart)


## Shift this ant's animation clock, so that several ants do not step in unison.
func advance(seconds: float) -> void:
	_side.advance(seconds)
	_top.advance(seconds)


func _is_side() -> bool:
	return heading == Heading.RIGHT or heading == Heading.LEFT


func _apply_heading() -> void:
	if not _side:
		return
	_side.visible = _is_side()
	_top.visible = not _is_side()
	if _is_side():
		_side.set_facing(&"e" if heading == Heading.RIGHT else &"w")
	else:
		_top.set_facing(&"n" if heading == Heading.UP else &"s")
