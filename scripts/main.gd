extends Node2D
## Creature presentation lab: stage wiring, auto-demo director, manual controls, camera.
##
## Command-line switches (after `--`):
##   --manual            start in manual mode instead of playing the demo
##   --zoom              start zoomed in
##   --quit-after-demo   quit two seconds after the demo ends (used for recordings)
##   --selftest          run the scripted behaviour checks and exit
##   --tour              play a scripted manual-mode tour (turning, left-facing actions) and exit

enum Step { NONE, SPAWN, IDLE1, TO_FOOD, EAT, IDLE2, TO_DUMMY, ATTACK, IDLE3, HURT, IDLE4, DEATH, END }

const Creature := preload("res://scripts/creature.gd")

const GROUND_Y := 520.0
const SPAWN_X := 330.0
const FOOD_X := 600.0
const DUMMY_X := 960.0
const WALK_MIN := 250.0
const ZOOM_NORMAL := 1.5   ## "normal game size": the creature is about 90 px long on a 1280x720 screen
const ZOOM_IN := 4.0
const CAM_HOME := Vector2(645, 410)
const CAPTIONS := {
	Step.NONE: "手动检查",
	Step.SPAWN: "自动演示 1/8 · 出生",
	Step.IDLE1: "自动演示 2/8 · 待机",
	Step.TO_FOOD: "自动演示 3/8 · 移动 → 食物",
	Step.EAT: "自动演示 4/8 · 进食",
	Step.IDLE2: "自动演示 4/8 · 进食完成",
	Step.TO_DUMMY: "自动演示 5/8 · 移动 → 训练目标",
	Step.ATTACK: "自动演示 6/8 · 攻击",
	Step.IDLE3: "自动演示 6/8 · 攻击完成",
	Step.HURT: "自动演示 7/8 · 受击（训练目标反弹）",
	Step.IDLE4: "自动演示 7/8 · 受击后恢复",
	Step.DEATH: "自动演示 8/8 · 死亡",
	Step.END: "演示结束 · 按 Space 重播，或用下方按钮手动检查",
}

var demo_step: int = Step.NONE
var zoomed := false
var slow := false

var _step_t := 0.0
var _hurt_mark := 0
var _shake := 0.0
var _quit_after := false
var _end_t := 0.0
var _notice_t := 0.0

var _state_label: Label
var _caption_label: Label
var _notice_label: Label
var _zoom_btn: Button
var _slow_btn: Button

@onready var cave: Node2D = $Cave
@onready var food: Node2D = $Food
@onready var dummy: Node2D = $Dummy
@onready var creature: Node2D = $Creature
@onready var ground: Node2D = $GroundFront
@onready var fx: Node2D = $Fx
@onready var cam: Camera2D = $Camera
@onready var hud: CanvasLayer = $Hud


func _ready() -> void:
	cave.ground_y = GROUND_Y
	ground.ground_y = GROUND_Y
	fx.floor_y = GROUND_Y
	food.position = Vector2(FOOD_X, GROUND_Y)
	dummy.position = Vector2(DUMMY_X, GROUND_Y)
	dummy.fx = fx
	creature.position = Vector2(SPAWN_X, GROUND_Y)
	creature.food = food
	creature.dummy = dummy
	creature.fx = fx
	creature.cave = cave
	creature.ground = ground
	creature.min_x = WALK_MIN
	creature.max_x = DUMMY_X - Creature.ATTACK_DIST
	creature.impact.connect(func(s: float) -> void: _shake = maxf(_shake, s))
	creature.notice.connect(_show_notice)
	cam.position = CAM_HOME
	cam.zoom = Vector2(ZOOM_NORMAL, ZOOM_NORMAL)
	_build_hud()

	var args := OS.get_cmdline_user_args()
	_quit_after = args.has("--quit-after-demo")
	if args.has("--zoom"):
		toggle_zoom()
		cam.zoom = Vector2(ZOOM_IN, ZOOM_IN)
		cam.position = _cam_target()
	if args.has("--selftest") or args.has("--tour"):
		var t := Node.new()
		t.set_script(load("res://scripts/selftest.gd"))
		t.set("main", self)
		add_child(t)
	elif args.has("--manual"):
		do_reset()
	else:
		start_demo()


# --------------------------------------------------------------------------- actions

func _reset_stage() -> void:
	food.restock(true)
	dummy.reset()
	fx.clear()
	creature.reset()
	_shake = 0.0


func start_demo() -> void:
	_reset_stage()
	creature.spawn(SPAWN_X)
	_set_step(Step.SPAWN)


func do_reset() -> void:
	_set_step(Step.NONE)
	_reset_stage()
	creature.spawn(SPAWN_X)


func do_eat() -> void:
	_manual()
	if food.bites_left <= 0:
		_show_notice("没有食物了（按 F 补充）")
	creature.command_eat()


func do_attack() -> void:
	_manual()
	creature.command_attack()


func do_move(x: float) -> void:
	_manual()
	creature.command_move(x)


func do_step(dir: float) -> void:
	do_move(creature.global_position.x + dir * 140.0)


func do_hurt() -> void:
	_manual()
	_strike(false)


func do_kill() -> void:
	_manual()
	_strike(true)


func do_restock() -> void:
	_manual()
	food.restock()


func toggle_zoom() -> void:
	zoomed = not zoomed
	if _zoom_btn != null:
		_zoom_btn.text = "视图：%s [Z]" % ("放大观察" if zoomed else "正常尺寸")


func toggle_slow() -> void:
	slow = not slow
	Engine.time_scale = 0.25 if slow else 1.0
	if _slow_btn != null:
		_slow_btn.text = "慢放 %s [S]" % ("开" if slow else "关")


## Hits the creature. If it stands in front of the dummy the dummy's pad does it,
## otherwise the blow is applied directly.
func _strike(lethal: bool) -> void:
	if creature.state == Creature.State.HIDDEN or creature.state == Creature.State.SPAWN or creature.state == Creature.State.DEAD:
		return
	if dummy.can_reach(creature) and not dummy.is_punching():
		dummy.punch(creature, lethal)
	else:
		creature.take_hit(creature.global_position.x + creature.facing * 40.0, lethal)


func _manual() -> void:
	if demo_step != Step.NONE:
		_set_step(Step.NONE)


func _set_step(s: int) -> void:
	demo_step = s
	_step_t = 0.0
	_end_t = 0.0
	if _caption_label != null:
		_caption_label.text = CAPTIONS[s]


func _show_notice(text: String) -> void:
	if _notice_label != null:
		_notice_label.text = text
		_notice_t = 2.2


# --------------------------------------------------------------------------- director

func _run_demo(delta: float) -> void:
	_step_t += delta
	var st: int = creature.state
	match demo_step:
		Step.SPAWN:
			if st == Creature.State.IDLE:
				_set_step(Step.IDLE1)
		Step.IDLE1:
			if _step_t >= 2.6:
				creature.command_eat()
				_set_step(Step.TO_FOOD)
		Step.TO_FOOD:
			if st == Creature.State.EAT:
				_set_step(Step.EAT)
		Step.EAT:
			if st == Creature.State.IDLE and food.bites_left == 0:
				_set_step(Step.IDLE2)
		Step.IDLE2:
			if _step_t >= 1.0:
				creature.command_attack()
				_set_step(Step.TO_DUMMY)
		Step.TO_DUMMY:
			if st == Creature.State.ATTACK:
				_set_step(Step.ATTACK)
		Step.ATTACK:
			if st == Creature.State.IDLE:
				_set_step(Step.IDLE3)
		Step.IDLE3:
			if _step_t >= 0.7:
				_hurt_mark = creature.hurt_count
				dummy.punch(creature, false)
				_set_step(Step.HURT)
		Step.HURT:
			if creature.hurt_count > _hurt_mark and st == Creature.State.IDLE:
				_set_step(Step.IDLE4)
			elif _step_t > 3.0:
				_set_step(Step.IDLE4)
		Step.IDLE4:
			if _step_t >= 1.4 and not dummy.is_punching():
				if dummy.can_reach(creature):
					dummy.punch(creature, true)
				else:
					creature.take_hit(dummy.global_position.x, true)
				_set_step(Step.DEATH)
		Step.DEATH:
			if creature.is_dead_settled():
				_set_step(Step.END)
		Step.END:
			_end_t += delta
			if _quit_after and _end_t >= 2.0:
				get_tree().quit()


func _cam_target() -> Vector2:
	if not zoomed:
		return CAM_HOME
	var half := 640.0 / ZOOM_NORMAL - 640.0 / ZOOM_IN
	return Vector2(clampf(creature.global_position.x + creature.facing * 14.0, CAM_HOME.x - half, CAM_HOME.x + half), GROUND_Y - 40.0)


func _process(delta: float) -> void:
	if demo_step != Step.NONE:
		_run_demo(delta)

	# Camera (uses unscaled time so zooming stays snappy in slow motion).
	var real := delta / maxf(Engine.time_scale, 0.01)
	var z := ZOOM_IN if zoomed else ZOOM_NORMAL
	var k := 1.0 - exp(-7.0 * real)
	cam.zoom = cam.zoom.lerp(Vector2(z, z), k)
	cam.position = cam.position.lerp(_cam_target(), k)
	_shake = maxf(0.0, _shake - delta * 28.0)
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake / cam.zoom.x

	if _state_label != null:
		_state_label.text = "行为状态：%s" % Creature.STATE_NAMES[creature.state]
	if _notice_t > 0.0:
		_notice_t -= real
		if _notice_t <= 0.0:
			_notice_label.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER: start_demo()
			KEY_R: do_reset()
			KEY_E: do_eat()
			KEY_A: do_attack()
			KEY_H: do_hurt()
			KEY_K: do_kill()
			KEY_F: do_restock()
			KEY_Z: toggle_zoom()
			KEY_S: toggle_slow()
			KEY_LEFT: do_step(-1.0)
			KEY_RIGHT: do_step(1.0)
			KEY_ESCAPE: get_tree().quit()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_move(get_global_mouse_position().x)


# --------------------------------------------------------------------------- HUD

func _build_hud() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	hud.add_child(root)

	var info := VBoxContainer.new()
	info.position = Vector2(18, 12)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(info)
	var title := _label("魔物表现测试 · 菇背拱兽", 14, Color("b9ad9c"))
	info.add_child(title)
	_caption_label = _label("", 20, Color("ffe9b0"))
	info.add_child(_caption_label)
	_state_label = _label("", 16, Color("e8f5d0"))
	info.add_child(_state_label)
	_notice_label = _label("", 15, Color("ff9a7a"))
	info.add_child(_notice_label)

	var hint := _label("鼠标点击地面：走到该处    ← →：左右移动    Esc：退出", 13, Color("9a8f86"))
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.position = Vector2(1280 - 18 - 420, 14)
	hint.size = Vector2(420, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(hint)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.position = Vector2(0, 668)
	bar.size = Vector2(1280, 38)
	root.add_child(bar)
	_button(bar, "▶ 自动演示 [Space]", start_demo, Color("ffe9b0"))
	_button(bar, "重置 [R]", do_reset)
	_button(bar, "◀ 移动 [←]", do_step.bind(-1.0))
	_button(bar, "移动 ▶ [→]", do_step.bind(1.0))
	_button(bar, "进食 [E]", do_eat)
	_button(bar, "攻击 [A]", do_attack)
	_button(bar, "受击 [H]", do_hurt)
	_button(bar, "死亡 [K]", do_kill)
	_button(bar, "补充食物 [F]", do_restock)
	_zoom_btn = _button(bar, "视图：正常尺寸 [Z]", toggle_zoom, Color("a8e6ff"))
	_slow_btn = _button(bar, "慢放 关 [S]", toggle_slow, Color("a8e6ff"))


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _button(parent: Control, text: String, action: Callable, col := Color("e6ded2")) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for sname: String in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.07, 0.05, 0.08, 0.78), "hover": Color(0.2, 0.15, 0.2, 0.9), "pressed": Color(0.34, 0.25, 0.2, 0.95)}[sname]
		sb.border_color = Color(1, 0.9, 0.75, 0.25)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(sname, sb)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
