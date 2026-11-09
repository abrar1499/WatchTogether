extends Control
## On-screen controls (multi-touch), keyboard/mouse, HUD, start screen and pause menu.

var main: Node
var player: CharacterBody3D
var is_touch := false

# buttons: name, centre (fraction of the screen), radius (px at 720p height)
var buttons := [
	{"id": "fire", "label": "FIRE", "c": Vector2(0.855, 0.66), "r": 62.0},
	{"id": "aim", "label": "AIM", "c": Vector2(0.065, 0.36), "r": 46.0},
	{"id": "crouch", "label": "CROUCH", "c": Vector2(0.74, 0.86), "r": 42.0},
	{"id": "jump", "label": "JUMP", "c": Vector2(0.86, 0.9), "r": 38.0},
	{"id": "reload", "label": "RELOAD", "c": Vector2(0.955, 0.48), "r": 40.0},
	{"id": "swap", "label": "SWAP", "c": Vector2(0.955, 0.3), "r": 38.0},
	{"id": "view", "label": "VIEW", "c": Vector2(0.88, 0.17), "r": 34.0},
	{"id": "menu", "label": "MENU", "c": Vector2(0.955, 0.07), "r": 32.0},
]
var held := {}          # touch index -> button id
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_ids := {}      # touch index -> last position
var keys := {}

var font: Font
var start_panel: PanelContainer
var pause_panel: PanelContainer
var update_btn: Button
var update_url := ""
var ver_label: Label
var hint := ""
var hint_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	font = ThemeDB.fallback_font
	_build_panels()


func _scale() -> float:
	return get_viewport_rect().size.y / 720.0


func _btn_at(p: Vector2) -> Dictionary:
	var vs := get_viewport_rect().size
	var s := _scale()
	for b in buttons:
		var c: Vector2 = b["c"] * vs
		if p.distance_to(c) <= b["r"] * s * 1.25:
			return b
	return {}


func _in_joy_zone(p: Vector2) -> bool:
	var vs := get_viewport_rect().size
	return p.x < vs.x * 0.36 and p.y > vs.y * 0.42


func _press(id: String, down: bool) -> void:
	if not main.playing:
		return
	match id:
		"fire":
			player.firing = down
		"aim":
			player.aiming = down
		"crouch":
			if down: player.toggle_crouch()
		"jump":
			if down: player.jump()
		"reload":
			if down: player.reload()
		"swap":
			if down: player.swap()
		"view":
			if down:
				player.cycle_view()
				_hint(["Close view", "Closer view", "First person"][player.view])
		"menu":
			if down: show_pause()


func _input(e: InputEvent) -> void:
	if not main.playing or pause_panel.visible:
		return
	if e is InputEventScreenTouch:
		is_touch = true
		if e.pressed:
			var b := _btn_at(e.position)
			if not b.is_empty():
				held[e.index] = b["id"]
				_press(b["id"], true)
				if b["id"] == "fire":
					look_ids[e.index] = e.position   # the fire finger also aims
			elif _in_joy_zone(e.position) and joy_id == -1:
				joy_id = e.index
				joy_origin = e.position
				joy_pos = e.position
			else:
				look_ids[e.index] = e.position
		else:
			if held.has(e.index):
				_press(held[e.index], false)
				held.erase(e.index)
			if e.index == joy_id:
				joy_id = -1
				player.move_in = Vector2.ZERO
			look_ids.erase(e.index)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if e.index == joy_id:
			joy_pos = e.position
			var v: Vector2 = (joy_pos - joy_origin) / (85.0 * _scale())
			if v.length() > 1.0:
				v = v.normalized()
			player.move_in = Vector2(v.x, -v.y)
		elif look_ids.has(e.index):
			var d: Vector2 = e.position - look_ids[e.index]
			look_ids[e.index] = e.position
			player.look(d.x * 1.15 / _scale(), d.y * 1.15 / _scale())
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.look(e.relative.x, e.relative.y)
	elif e is InputEventMouseButton and not is_touch:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and e.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			player.firing = e.pressed
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			player.aiming = e.pressed
	elif e is InputEventKey and not e.echo:
		keys[e.keycode] = e.pressed
		if e.pressed:
			match e.keycode:
				KEY_C: player.toggle_crouch()
				KEY_SPACE: player.jump()
				KEY_R: player.reload()
				KEY_Q: player.swap()
				KEY_V:
					player.cycle_view()
					_hint(["Close view", "Closer view", "First person"][player.view])
				KEY_1: _set_weapon(0)
				KEY_2: _set_weapon(1)
				KEY_3: _set_weapon(2)
				KEY_ESCAPE:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					show_pause()
		if not is_touch:
			var mv := Vector2(float(keys.get(KEY_D, false)) - float(keys.get(KEY_A, false)), float(keys.get(KEY_W, false)) - float(keys.get(KEY_S, false)))
			player.move_in = mv.normalized() if mv.length() > 0 else Vector2.ZERO
			player.run_in = keys.get(KEY_SHIFT, false)


func _set_weapon(i: int) -> void:
	while player.wi != i:
		player.switching = 0
		player.swap()


func _hint(s: String) -> void:
	hint = s
	hint_t = 1.6


func _process(dt: float) -> void:
	if hint_t > 0:
		hint_t -= dt
	queue_redraw()


func _draw() -> void:
	if not main or not main.playing:
		return
	var vs := get_viewport_rect().size
	var s := _scale()
	var c := vs * 0.5
	# crosshair (red dot while aiming)
	if player.aiming:
		draw_circle(c, 3.0 * s, Color(1, 0.25, 0.15))
	else:
		var g = (7.0 + player.recoil * 6.0 + (4.0 if player.speed > 0.5 else 0.0)) * s
		var col := Color(1, 1, 1, 0.85)
		draw_line(c + Vector2(-g - 9 * s, 0), c + Vector2(-g, 0), col, 2.0 * s)
		draw_line(c + Vector2(g, 0), c + Vector2(g + 9 * s, 0), col, 2.0 * s)
		draw_line(c + Vector2(0, -g - 9 * s), c + Vector2(0, -g), col, 2.0 * s)
		draw_line(c + Vector2(0, g), c + Vector2(0, g + 9 * s), col, 2.0 * s)
	# ammo
	var w: Dictionary = player.weapons[player.wi]
	var ammo := "%d / %d" % [w["mag"], w["res"]]
	var ap := Vector2(vs.x * 0.70, 52 * s)
	draw_rect(Rect2(ap - Vector2(12, 40) * s, Vector2(220, 64) * s), Color(0.05, 0.06, 0.06, 0.6))
	draw_string(font, ap + Vector2(0, -16 * s), w["name"] + ("  RELOADING" if player.reloading > 0 else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), Color(0.85, 0.82, 0.72))
	draw_string(font, ap + Vector2(0, 14 * s), ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * s), Color(1, 1, 1))
	if hint_t > 0:
		draw_string(font, Vector2(vs.x * 0.5 - 60 * s, vs.y * 0.62), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), Color(0.6, 1, 0.6, min(1.0, hint_t)))
	if not is_touch:
		return
	# joystick
	var zone := Rect2(Vector2(0, vs.y * 0.42), Vector2(vs.x * 0.36, vs.y * 0.58))
	if joy_id >= 0:
		draw_circle(joy_origin, 85 * s, Color(0.1, 0.1, 0.1, 0.25))
		draw_arc(joy_origin, 85 * s, 0, TAU, 48, Color(0.92, 0.89, 0.8, 0.35), 2.0 * s)
		var k: Vector2 = joy_origin + (joy_pos - joy_origin).limit_length(85 * s)
		draw_circle(k, 28 * s, Color(0.92, 0.89, 0.8, 0.45))
	else:
		draw_arc(Vector2(zone.position.x + 110 * s, zone.end.y - 110 * s), 70 * s, 0, TAU, 40, Color(0.92, 0.89, 0.8, 0.18), 2.0 * s)
	# buttons
	var active := {}
	for i in held:
		active[held[i]] = true
	for b in buttons:
		var bc: Vector2 = b["c"] * vs
		var r: float = b["r"] * s
		var on: bool = active.has(b["id"]) or (b["id"] == "crouch" and player.crouch) or (b["id"] == "aim" and player.aiming)
		var fill := Color(0.95, 0.7, 0.27, 0.55) if on else (Color(1, 0.35, 0.26, 0.22) if b["id"] == "fire" else Color(0.05, 0.06, 0.05, 0.3))
		draw_circle(bc, r, fill)
		draw_arc(bc, r, 0, TAU, 40, Color(1, 0.4, 0.3, 0.8) if b["id"] == "fire" else Color(0.92, 0.89, 0.8, 0.4), 1.5 * s)
		var fs := int((14 if b["id"] == "fire" else 11) * s)
		var tw := font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, bc + Vector2(-tw / 2, fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.93, 0.86))


# ---------------- menus ----------------
func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.08, 0.94)
	sb.border_color = Color(0.3, 0.33, 0.28)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _button(parent: Node, text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 54)
	b.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.71, 0.27) if primary else Color(0, 0, 0, 0)
	sb.border_color = Color(0.95, 0.71, 0.27)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.03) if primary else Color(0.95, 0.71, 0.27))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.03) if primary else Color(1, 0.8, 0.4))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_panels() -> void:
	start_panel = _panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	start_panel.add_child(v)
	var t := Label.new()
	t.text = "OPERATION DUST SIGNAL"
	t.add_theme_font_size_override("font_size", 30)
	v.add_child(t)
	var sub := Label.new()
	sub.text = "Godot test build: the soldier, the rifles and a practice yard."
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.75, 0.73, 0.65))
	v.add_child(sub)
	_button(v, "Play", func(): main.start_game(), true)
	update_btn = _button(v, "Update", func(): OS.shell_open(update_url))
	update_btn.visible = false
	_button(v, "Exit", func(): get_tree().quit())
	ver_label = Label.new()
	ver_label.add_theme_font_size_override("font_size", 13)
	ver_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	v.add_child(ver_label)
	start_panel.visible = false

	pause_panel = _panel()
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	pause_panel.add_child(pv)
	var pt := Label.new()
	pt.text = "PAUSED"
	pt.add_theme_font_size_override("font_size", 28)
	pv.add_child(pt)
	_button(pv, "Resume", func(): hide_pause(), true)
	_button(pv, "Check for update", func(): main.check_update_now(); _hint("Checking for update"))
	_button(pv, "Exit", func(): get_tree().quit())
	pause_panel.visible = false


func show_start(ver: int) -> void:
	ver_label.text = "Installed: v%d" % ver if ver > 0 else "Installed: test build"
	start_panel.visible = true
	_center(start_panel)


func hide_start() -> void:
	start_panel.visible = false


func show_pause() -> void:
	player.firing = false
	player.aiming = false
	player.move_in = Vector2.ZERO
	held.clear()
	joy_id = -1
	look_ids.clear()
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.visible = true
	_center(pause_panel)


func hide_pause() -> void:
	pause_panel.visible = false
	get_tree().paused = false
	if not is_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func offer_update(n: int, url: String) -> void:
	update_url = url
	update_btn.text = "Update to v%d" % n
	update_btn.visible = true
	if main.playing:
		_hint("Update v%d available (MENU)" % n)
		var pv: Node = pause_panel.get_child(0)
		if not pv.has_node("Upd"):
			var b := _button(pv, "Update to v%d" % n, func(): OS.shell_open(update_url))
			b.name = "Upd"


func _center(p: Control) -> void:
	await get_tree().process_frame
	var vs := get_viewport_rect().size
	p.position = (vs - p.size) * 0.5
