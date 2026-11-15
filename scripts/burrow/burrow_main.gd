extends Node2D
## Burrow lab: a small diggable underground map and one Sacgrub living in it.
## Stage wiring, auto-demo director, manual controls, camera, HUD, debug overlay.
##
## Command-line switches (after `--`):
##   --manual     start in manual mode instead of playing the demo
##   --grid       start with the grid / footprint overlay on
##   --selftest   run the scripted checks and exit (use with --headless --fixed-fps 60)
##   --shots      play the demo, save still screenshots to deliverables/burrow_screenshots, exit

enum Step { NONE, SPAWN, IDLE1, TO_FOOD, EAT, IDLE2, DIG, TO_BURR, ATTACK, IDLE3, HURT, IDLE4, DEATH, END }

const Spec := preload("res://scripts/burrow/grid_spec.gd")
const Grid := preload("res://scripts/burrow/burrow_grid.gd")
const Grub := preload("res://scripts/burrow/grub.gd")
const Nodule := preload("res://scripts/burrow/nodule.gd")

const MAP_ORIGIN := Vector2(96, 46)
const ZOOM_IN := 2.4
const CAPTIONS := {
	Step.NONE: "手动检查",
	Step.SPAWN: "自动演示 1/8 · 出生（破卵）",
	Step.IDLE1: "自动演示 2/8 · 待机",
	Step.TO_FOOD: "自动演示 3/8 · 移动 → 根瘤（纵向、转角、交叉口）",
	Step.EAT: "自动演示 4/8 · 进食",
	Step.IDLE2: "自动演示 4/8 · 进食完成",
	Step.DIG: "自动演示 5/8 · 挖开土块，打通去路",
	Step.TO_BURR: "自动演示 5/8 · 掉头 → 穿过新通道 → 棘壳球",
	Step.ATTACK: "自动演示 6/8 · 攻击",
	Step.IDLE3: "自动演示 6/8 · 攻击完成",
	Step.HURT: "自动演示 7/8 · 受击（棘壳球反刺）",
	Step.IDLE4: "自动演示 7/8 · 受击后恢复",
	Step.DEATH: "自动演示 8/8 · 死亡",
	Step.END: "演示结束 · Space 重播，或直接手动操作",
}

var grid: RefCounted
var foods: Array[Node2D] = []
var demo_step: int = Step.NONE
var zoomed := false
var slow := false
var show_grid := false

var _u := Spec.CELL_PX
var _step_t := 0.0
var _hurt_mark := 0
var _shake := 0.0
var _notice_t := 0.0
var _font: Font

var _caption_label: Label
var _state_label: Label
var _notice_label: Label
var _legend_label: Label
var _zoom_btn: Button
var _slow_btn: Button
var _grid_btn: Button

@onready var world: Node2D = $World
@onready var map: Node2D = $World/Map
@onready var items: Node2D = $World/Items
@onready var burr: Node2D = $World/Items/Burr
@onready var grub: Node2D = $World/Grub
@onready var fx: Node2D = $World/Fx
@onready var debug: Node2D = $World/Debug
@onready var cam: Camera2D = $Camera
@onready var hud: CanvasLayer = $Hud


func _ready() -> void:
	world.position = MAP_ORIGIN
	grid = Grid.new()
	grid.load_layout(Spec.LAYOUT)
	map.setup(grid)
	fx.grid = grid
	for c in Spec.FOOD_CELLS:
		var f := Node2D.new()
		f.set_script(Nodule)
		f.grid = grid
		items.add_child(f)
		f.place(c)
		grid.occupy(f, f.cell, f.size)
		foods.append(f)
	burr.grid = grid
	burr.fx = fx
	burr.place(Spec.BURR_CELL)
	grid.occupy(burr, burr.cell, burr.size)
	grub.grid = grid
	grub.fx = fx
	grub.rig.grid = grid
	grub.impact.connect(func(s: float) -> void: _shake = maxf(_shake, s))
	grub.notice.connect(_show_notice)
	grid.cell_changed.connect(func(_c: Vector2i) -> void: _redraw_items())
	grid.was_reset.connect(_redraw_items)
	debug.draw.connect(_draw_debug)
	_build_hud()

	var args := OS.get_cmdline_user_args()
	if args.has("--grid"):
		toggle_grid()
	if args.has("--selftest") or args.has("--shots"):
		var t := Node.new()
		t.set_script(load("res://scripts/burrow/burrow_selftest.gd"))
		t.set("main", self)
		add_child(t)
	elif args.has("--manual"):
		do_reset()
	else:
		start_demo()


func _redraw_items() -> void:
	for f in foods:
		f.queue_redraw()


# --------------------------------------------------------------------------- actions

func _reset_stage() -> void:
	grid.reset()
	for f in foods:
		f.restock(true)
	burr.reset()
	fx.clear()
	grub.reset()
	_shake = 0.0


func start_demo() -> void:
	_reset_stage()
	grub.spawn(Spec.SPAWN_CELL, Spec.SPAWN_FACING)
	_set_step(Step.SPAWN)


## Full reset: map back to its original layout, items restored, a new grub hatches.
func do_reset() -> void:
	_set_step(Step.NONE)
	_reset_stage()
	grub.spawn(Spec.SPAWN_CELL, Spec.SPAWN_FACING)


func do_dig(c: Vector2i) -> bool:
	if not grid.dig(c):
		return false
	map.flash_cell(c)
	fx.burst("dig", Spec.center(c))
	_shake = maxf(_shake, 2.5)
	return true


func do_move(c: Vector2i) -> void:
	_manual()
	grub.command_move(c)


## Left click on a cell: dig soil that touches a tunnel, otherwise walk there.
func do_click(c: Vector2i) -> void:
	_manual()
	if not grid.in_bounds(c):
		return
	if grid.can_dig(c):
		do_dig(c)
	elif grid.kind(c) == Spec.SOIL:
		_show_notice("只能挖与通道相邻的土块")
	elif grid.kind(c) == Spec.ROCK:
		_show_notice("岩石挖不动")
	elif grid.blocker_at(c) != null:
		_show_notice("这一格被占用了")
	else:
		grub.command_move(c)


func do_eat() -> void:
	_manual()
	var f := _pick_food()
	if f == null:
		_show_notice("根瘤都吃光了（按 F 补充）")
		return
	grub.command_eat(f)


func do_attack() -> void:
	_manual()
	grub.command_attack(burr)


func do_hurt() -> void:
	_manual()
	_strike(false)


func do_kill() -> void:
	_manual()
	_strike(true)


func do_restock() -> void:
	_manual()
	for f in foods:
		f.restock()


func toggle_zoom() -> void:
	zoomed = not zoomed
	if _zoom_btn != null:
		_zoom_btn.text = "视图：%s [Z]" % ("放大" if zoomed else "默认")


func toggle_slow() -> void:
	slow = not slow
	Engine.time_scale = 0.25 if slow else 1.0
	if _slow_btn != null:
		_slow_btn.text = "慢放 %s [S]" % ("开" if slow else "关")


func toggle_grid() -> void:
	show_grid = not show_grid
	if _grid_btn != null:
		_grid_btn.text = "格线 %s [G]" % ("开" if show_grid else "关")
	if _legend_label != null:
		_legend_label.visible = show_grid
	debug.queue_redraw()


## Nearest food (by walking distance) that still has something on it.
func _pick_food() -> Node2D:
	var best: Node2D = null
	var best_len := 1 << 30
	var fallback: Node2D = null
	for f in foods:
		if f.bites_left <= 0:
			continue
		if fallback == null:
			fallback = f
		var spots: Array[Vector2i] = []
		for c: Vector2i in grid.cells_beside(f.cell, f.size, Grub.FOOTPRINT):
			if grid.area_free(c, Grub.FOOTPRINT):
				spots.append(c)
		var route: Array[Vector2i] = grid.find_path(grub.cell, spots, Grub.FOOTPRINT)
		if not route.is_empty() and route.size() < best_len:
			best_len = route.size()
			best = f
	return best if best != null else fallback


## Hits the grub. If it stands next to the thornpod the pod's spines do it,
## otherwise the blow is applied directly.
func _strike(lethal: bool) -> void:
	if not grub.is_alive() or grub.state == Grub.State.SPAWN:
		return
	if burr.can_reach(grub) and not burr.is_punching():
		burr.punch(grub, lethal)
	else:
		grub.take_hit(lethal)


func _manual() -> void:
	if demo_step != Step.NONE:
		_set_step(Step.NONE)


func _set_step(s: int) -> void:
	demo_step = s
	_step_t = 0.0
	if _caption_label != null:
		_caption_label.text = CAPTIONS[s]


func _show_notice(text: String) -> void:
	if _notice_label != null:
		_notice_label.text = text
		_notice_t = 2.4


# --------------------------------------------------------------------------- director

func _run_demo(delta: float) -> void:
	_step_t += delta
	var st: int = grub.state
	match demo_step:
		Step.SPAWN:
			if st == Grub.State.IDLE:
				_set_step(Step.IDLE1)
		Step.IDLE1:
			if _step_t >= 2.2:
				grub.command_eat(foods[0])
				_set_step(Step.TO_FOOD)
		Step.TO_FOOD:
			if st == Grub.State.EAT:
				_set_step(Step.EAT)
			elif st == Grub.State.IDLE and _step_t > 1.0:
				_set_step(Step.IDLE2)
		Step.EAT:
			if st == Grub.State.IDLE:
				_set_step(Step.IDLE2)
		Step.IDLE2:
			if _step_t >= 0.9:
				_set_step(Step.DIG)
		Step.DIG:
			var n := Spec.DEMO_DIG.size()
			for i in n:
				if _step_t >= 0.5 + 0.45 * i and grid.can_dig(Spec.DEMO_DIG[i]):
					do_dig(Spec.DEMO_DIG[i])
			if _step_t >= 0.5 + 0.45 * n + 0.5:
				grub.command_attack(burr)
				_set_step(Step.TO_BURR)
		Step.TO_BURR:
			if st == Grub.State.ATTACK:
				_set_step(Step.ATTACK)
			elif st == Grub.State.IDLE and _step_t > 1.0:
				_set_step(Step.IDLE3)
		Step.ATTACK:
			if st == Grub.State.IDLE:
				_set_step(Step.IDLE3)
		Step.IDLE3:
			if _step_t >= 0.8:
				_hurt_mark = grub.hurt_count
				_strike(false)
				_set_step(Step.HURT)
		Step.HURT:
			if (grub.hurt_count > _hurt_mark and st == Grub.State.IDLE) or _step_t > 3.0:
				_set_step(Step.IDLE4)
		Step.IDLE4:
			if _step_t >= 1.5 and not burr.is_punching():
				_strike(true)
				_set_step(Step.DEATH)
		Step.DEATH:
			if grub.is_dead_settled():
				_set_step(Step.END)


func _cam_target() -> Vector2:
	if not zoomed:
		return Vector2(640, 360)
	var p: Vector2 = MAP_ORIGIN + grub.pos * _u
	var half := Vector2(640, 360) * (1.0 - 1.0 / ZOOM_IN)
	return Vector2(clampf(p.x, 640 - half.x, 640 + half.x), clampf(p.y, 360 - half.y, 360 + half.y))


func _mouse_cell() -> Vector2i:
	return Spec.cell_of(world.get_local_mouse_position() / _u)


func _process(delta: float) -> void:
	if demo_step != Step.NONE:
		_run_demo(delta)

	var real := delta / maxf(Engine.time_scale, 0.01)
	var z := ZOOM_IN if zoomed else 1.0
	var k := 1.0 - exp(-7.0 * real)
	cam.zoom = cam.zoom.lerp(Vector2(z, z), k)
	cam.position = cam.position.lerp(_cam_target(), k)
	_shake = maxf(0.0, _shake - delta * 28.0)
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake / cam.zoom.x

	var mc := _mouse_cell()
	var over_map: bool = grid.in_bounds(mc) and get_viewport().get_mouse_position().y < 628.0
	map.set_hover(mc if over_map else Vector2i(-1, -1))

	if _state_label != null:
		_state_label.text = "行为状态：%s    囊内储量 %d/%d" % [Grub.STATE_NAMES[grub.state], grub.sac_level, Grub.SAC_CAPACITY]
	if _notice_t > 0.0:
		_notice_t -= real
		if _notice_t <= 0.0:
			_notice_label.text = ""
	if show_grid:
		debug.queue_redraw()


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
			KEY_G: toggle_grid()
			KEY_ESCAPE: get_tree().quit()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_click(_mouse_cell())


# --------------------------------------------------------------------------- debug overlay

## Grid lines plus the three sizes of every object: footprint (logic), body (collision),
## visual bounds (what is drawn), and the cells the grub can interact with.
func _draw_debug() -> void:
	if not show_grid:
		return
	var w: float = grid.cols * _u
	var h: float = grid.rows * _u
	for x in grid.cols + 1:
		debug.draw_line(Vector2(x * _u, 0), Vector2(x * _u, h), Color(1, 1, 1, 0.13), 1.0)
	for y in grid.rows + 1:
		debug.draw_line(Vector2(0, y * _u), Vector2(w, y * _u), Color(1, 1, 1, 0.13), 1.0)
	var things: Array = foods.duplicate()
	things.append(burr)
	for it: Node2D in things:
		debug.draw_rect(Rect2(Vector2(it.cell) * _u, Vector2(it.size) * _u).grow(-3), Color(0.5, 1.0, 0.6, 0.7), false, 1.5)
	if grub.state == Grub.State.HIDDEN:
		return
	var foot := Rect2(Vector2(grub.cell) * _u, Vector2(Grub.FOOTPRINT) * _u)
	for c: Vector2i in grid.cells_beside(grub.cell, Grub.FOOTPRINT, Vector2i.ONE):
		debug.draw_rect(Rect2(Vector2(c) * _u, Vector2(_u, _u)).grow(-6), Color(1.0, 0.6, 0.2, 0.55), false, 1.5)
	debug.draw_rect(foot.grow(-2), Color(0.3, 0.9, 1.0, 0.9), false, 2.0)
	if grub.rig.get("_p").get("body", false):
		for circle: Array in grub.rig.body_circles():
			debug.draw_arc(circle[0] * _u, circle[1] * _u, 0.0, TAU, 20, Color(1.0, 0.3, 0.9, 0.9), 1.2, true)
		var vb: Rect2 = grub.rig.visual_bounds()
		debug.draw_rect(Rect2(vb.position * _u, vb.size * _u), Color(1.0, 0.95, 0.3, 0.9), false, 1.2)


# --------------------------------------------------------------------------- HUD

func _build_hud() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	_font = font
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	hud.add_child(root)

	_caption_label = _label("", 19, Color("ffe9b0"))
	_caption_label.position = Vector2(96, 8)
	root.add_child(_caption_label)

	_state_label = _label("", 15, Color("e8f5d0"))
	_state_label.position = Vector2(1280 - 96 - 420, 4)
	_state_label.size = Vector2(420, 20)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_state_label)

	var spec := _label("囤囊虫 · 格子 %dpx · 地图 %d×%d 格 · 魔物占地 1×1 格" % [int(_u), Spec.COLS, Spec.ROWS], 12, Color("9a8f86"))
	spec.position = Vector2(1280 - 96 - 420, 25)
	spec.size = Vector2(420, 18)
	spec.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(spec)

	var hint := _label("左键土块：挖掘（须与通道相邻）    左键通道：走到该格    Esc：退出", 13, Color("b9ad9c"))
	hint.position = Vector2(96, 628)
	root.add_child(hint)

	_notice_label = _label("", 14, Color("ff9a7a"))
	_notice_label.position = Vector2(1280 - 96 - 420, 628)
	_notice_label.size = Vector2(420, 20)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_notice_label)

	_legend_label = _label("青：逻辑占地    品红：碰撞体    黄：视觉边界    橙：可交互的邻格    绿：物品占地", 12, Color("d8d0c4"))
	_legend_label.position = Vector2(96, 648)
	_legend_label.visible = false
	root.add_child(_legend_label)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.position = Vector2(0, 674)
	bar.size = Vector2(1280, 38)
	root.add_child(bar)
	_button(bar, "▶ 自动演示 [Space]", start_demo, Color("ffe9b0"))
	_button(bar, "重置地图与魔物 [R]", do_reset)
	_button(bar, "进食 [E]", do_eat)
	_button(bar, "攻击 [A]", do_attack)
	_button(bar, "受击 [H]", do_hurt)
	_button(bar, "死亡 [K]", do_kill)
	_button(bar, "补充食物 [F]", do_restock)
	_zoom_btn = _button(bar, "视图：默认 [Z]", toggle_zoom, Color("a8e6ff"))
	_slow_btn = _button(bar, "慢放 关 [S]", toggle_slow, Color("a8e6ff"))
	_grid_btn = _button(bar, "格线 关 [G]", toggle_grid, Color("a8e6ff"))


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
