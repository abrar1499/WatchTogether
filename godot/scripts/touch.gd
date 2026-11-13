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
	{"id": "menu", "label": "MENU", "c": Vector2(0.955, 0.07), "r": 32.0},
	{"id": "nade", "label": "GRENADE", "c": Vector2(0.955, 0.66), "r": 38.0},
	{"id": "holster", "label": "HOLSTER", "c": Vector2(0.065, 0.2), "r": 34.0},
	{"id": "act", "label": "ACTION", "c": Vector2(0.705, 0.62), "r": 42.0},
	{"id": "knife", "label": "KNIFE", "c": Vector2(0.615, 0.87), "r": 36.0},
	{"id": "prone", "label": "PRONE", "c": Vector2(0.625, 0.72), "r": 34.0},
]
var mission_panel: PanelContainer
var brief_panel: PanelContainer
var result_panel: PanelContainer
var held := {}          # touch index -> button id
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_ids := {}      # touch index -> last position
var keys := {}

var font: Font
var start_panel: Control
var pause_panel: PanelContainer
var update_btn: Button
var update_url := ""
var ver_label: Label
var hint := ""
var hint_t := 0.0
var msg := ""
var msg_sub := ""
var msg_t := 0.0
var note := ""
var note_t := 0.0
var mark_t := 0.0       # hit marker
var mark_kill := false


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
		if b["id"] == "act" and player.act_label == "":
			continue
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
		"prone":
			if down: player.toggle_prone()
		"jump":
			if down: player.jump()
		"reload":
			if down: player.reload()
		"swap":
			if down:
				player.swap()
				_hint(player.weapons[player.wi]["name"])
		"nade":
			if down: player.throw_grenade()
		"holster":
			if down: player.toggle_holster()
		"act":
			if down: player.action()
		"knife":
			if down: player.knife()
		"view":
			if down:
				player.cycle_view()
				_hint(["Close view", "Closer view", "First person"][player.view])
		"menu":
			if down: show_pause()


func _input(e: InputEvent) -> void:
	# (with the result on screen the touches go to its buttons: they used to be taken for the joystick and fire,
	# so its buttons could not be pressed)
	if not main.playing or pause_panel.visible or result_panel.visible:
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
				KEY_Z: player.toggle_prone()
				KEY_SPACE: player.jump()
				KEY_R: player.reload()
				KEY_Q:
					player.swap()
					_hint(player.weapons[player.wi]["name"])
				KEY_G: player.throw_grenade()
				KEY_H: player.toggle_holster()
				KEY_E: player.action()
				KEY_F: player.knife()
				KEY_4: _set_weapon(3)
				KEY_5: _set_weapon(4)
				KEY_6: _set_weapon(5)
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
	player.select_weapon(i)
	_hint(player.weapons[i]["name"])


func _hint(s: String) -> void:
	hint = s
	hint_t = 1.6


func message(title: String, sub: String, secs: float) -> void:
	msg = title
	msg_sub = sub
	msg_t = secs


func kill_note(s: String) -> void:
	note = s
	note_t = 1.2


func pickup_note(s: String) -> void:
	hint = s
	hint_t = 2.2


func hit_marker(kill: bool) -> void:
	mark_t = 0.22 if kill else 0.14
	mark_kill = kill


func _process(dt: float) -> void:
	msg_t = max(0.0, msg_t - dt)
	note_t = max(0.0, note_t - dt)
	mark_t = max(0.0, mark_t - dt)
	if hint_t > 0:
		hint_t -= dt
	queue_redraw()


var cine := false
func _draw() -> void:
	if not main or not main.playing:
		return
	var vs := get_viewport_rect().size
	var s := _scale()
	var c := vs * 0.5
	if cine:        # recording: no HUD, only the view through a scope
		if player.scoped():
			_draw_scope(c, vs, s, player.weapons[player.wi]["gun"])
		return
	# hit: red edge flash and a mark toward the shooter
	if player.hurt_t > 0.0:
		var a: float = player.hurt_t / 0.6
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.7, 0.0, 0.0, 0.22 * a))
		var ang: float = player.hurt_dir - PI * 0.5
		draw_arc(c, 110 * s, ang - 0.35, ang + 0.35, 16, Color(1, 0.15, 0.1, 0.85 * a), 7.0 * s)
	# wounded: the edges of the screen darken red, more the less health he has (a slow pulse when it is very low)
	if not player.dead and player.hp < 60.0 and main.fx.blood_on:
		var k: float = clamp((60.0 - player.hp) / 60.0, 0.0, 1.0)
		if player.hp < 25.0:
			k *= 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.006)
		var band: float = vs.y * 0.28
		for i in 20:
			var t: float = float(i) / 20.0
			var col := Color(0.36, 0.0, 0.01, 0.2 * k * (1.0 - t) * (1.0 - t))
			var w: float = band / 20.0
			draw_rect(Rect2(0, i * w, vs.x, w), col)
			draw_rect(Rect2(0, vs.y - (i + 1) * w, vs.x, w), col)
			draw_rect(Rect2(i * w, 0, w, vs.y), col)
			draw_rect(Rect2(vs.x - (i + 1) * w, 0, w, vs.y), col)
	if player.dead:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.35, 0.0, 0.0, 0.35))
	# crosshair (red dot while aiming); the SVD's PSO-1 or the RPG's PGO-7 when looking through them
	var gun: String = player.weapons[player.wi]["gun"]
	if player.scoped():
		_draw_scope(c, vs, s, gun)
	elif player.holstered or player.throw_t >= 0.0 or player.hol_t >= 0.0:
		pass
	elif player.aiming:
		# (red on a soldier: the round will hit him)
		draw_circle(c, 3.0 * s, Color(1, 0.12, 0.08) if player.on_target != null else Color(1, 1, 1, 0.9))
	else:
		var g = (7.0 + player.recoil * 6.0 + (4.0 if player.speed > 0.5 else 0.0)) * s
		if player.on_target != null:
			g = 5.0 * s           # on a soldier the crosshair closes up: no spread
		var col := Color(1, 0.12, 0.08, 0.95) if player.on_target != null else Color(1, 1, 1, 0.85)
		draw_line(c + Vector2(-g - 9 * s, 0), c + Vector2(-g, 0), col, 2.0 * s)
		draw_line(c + Vector2(g, 0), c + Vector2(g + 9 * s, 0), col, 2.0 * s)
		draw_line(c + Vector2(0, -g - 9 * s), c + Vector2(0, -g), col, 2.0 * s)
		draw_line(c + Vector2(0, g), c + Vector2(0, g + 9 * s), col, 2.0 * s)
	# hit marker: four short strokes round the crosshair, red on a kill
	if mark_t > 0.0:
		var mc := Color(1, 0.2, 0.15, 0.95) if mark_kill else Color(1, 1, 1, 0.9)
		for k in 4:
			var dv := Vector2(1, 1).rotated(k * PI * 0.5).normalized()
			draw_line(c + dv * 9 * s, c + dv * 17 * s, mc, 2.4 * s)
	# a live grenade close by: warning and which way it is
	var near: Array = main.grenades_near(player.global_position, 7.0)
	if not near.is_empty():
		var to: Vector3 = near[0] - player.global_position
		var ang: float = atan2(to.dot(Vector3(cos(player.yaw), 0, -sin(player.yaw))), to.dot(Vector3(-sin(player.yaw), 0, -cos(player.yaw)))) - PI * 0.5
		var blink: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.02)
		draw_arc(c, 80 * s, ang - 0.3, ang + 0.3, 12, Color(1, 0.75, 0.1, blink), 6.0 * s)
		var gs := int(18 * s)
		var gw: float = font.get_string_size("GRENADE!", HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
		draw_string(font, c + Vector2(-gw / 2, -100 * s), "GRENADE!", HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(1, 0.8, 0.15, blink))
	# ammo
	var w: Dictionary = player.weapons[player.wi]
	var ammo := "%d / %d" % [w["mag"], w["res"]]
	var ap := Vector2(vs.x * 0.70, 52 * s)
	draw_rect(Rect2(ap - Vector2(12, 40) * s, Vector2(220, 64) * s), Color(0.05, 0.06, 0.06, 0.6))
	var state_s := "  RELOADING" if player.reloading > 0 else ("  ON BACK" if player.holstered else "")
	draw_string(font, ap + Vector2(0, -16 * s), w["name"] + state_s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), Color(0.85, 0.82, 0.72))
	draw_string(font, ap + Vector2(0, 14 * s), ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * s), Color(1, 1, 1))
	# frames a second, small at the top: so the player can say how smooth it really runs
	var fps := Engine.get_frames_per_second()
	draw_string(font, Vector2(vs.x * 0.5 - 22 * s, 18 * s), "%d FPS" % fps, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s),
		Color(0.6, 1.0, 0.6, 0.75) if fps >= 45 else (Color(1.0, 0.85, 0.4, 0.8) if fps >= 28 else Color(1.0, 0.45, 0.35, 0.85)))
	draw_string(font, ap + Vector2(128 * s, 14 * s), "GRENADES %d" % player.grenades, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), Color(0.8, 0.85, 0.6))
	# health
	var hp_k: float = clamp(player.hp / 100.0, 0.0, 1.0)
	var hb := Rect2(ap + Vector2(-12, 30) * s, Vector2(220, 10) * s)
	draw_rect(hb, Color(0.05, 0.06, 0.06, 0.6))
	draw_rect(Rect2(hb.position, Vector2(hb.size.x * hp_k, hb.size.y)), Color(0.85, 0.2, 0.15) if hp_k < 0.35 else Color(0.55, 0.85, 0.45))
	draw_string(font, ap + Vector2(0, 56 * s), "HEALTH %d" % int(ceil(player.hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), Color(0.9, 0.88, 0.8))
	if main.mission:
		_draw_mission(vs, s)
	# enemies left and score
	if main.enemies.size() > 0 and not main.mission:
		var tl := Vector2(24 * s, 34 * s)
		draw_rect(Rect2(tl - Vector2(12, 24) * s, Vector2(190, 52) * s), Color(0.05, 0.06, 0.06, 0.55))
		draw_string(font, tl, "ENEMIES  %d / %d" % [main.alive(), main.enemies.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), Color(1, 0.86, 0.7))
		draw_string(font, tl + Vector2(0, 20 * s), "KILLS %d   HEADSHOTS %d" % [main.kills, main.headshots], HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), Color(0.85, 0.83, 0.75))
	if note_t > 0.0:
		var fsn := int(15 * s)
		var tw: float = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, fsn).x
		draw_string(font, c + Vector2(-tw / 2, 46 * s), note, HORIZONTAL_ALIGNMENT_LEFT, -1, fsn, Color(1, 0.35, 0.25, min(1.0, note_t * 2.0)))
	if msg_t > 0.0:
		var al: float = min(1.0, msg_t * 1.5)
		var f1 := int(30 * s)
		var f2 := int(14 * s)
		var w1: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, f1).x
		var w2: float = font.get_string_size(msg_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, f2).x
		draw_string(font, Vector2(c.x - w1 / 2, vs.y * 0.3), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, f1, Color(1, 0.92, 0.75, al))
		draw_string(font, Vector2(c.x - w2 / 2, vs.y * 0.3 + 26 * s), msg_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, f2, Color(0.95, 0.9, 0.8, al))
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
		if b["id"] == "act" and player.act_label == "":
			continue
		var bc: Vector2 = b["c"] * vs
		var r: float = b["r"] * s
		var on: bool = active.has(b["id"]) or (b["id"] == "crouch" and player.crouch) or (b["id"] == "prone" and player.prone) or (b["id"] == "aim" and player.aiming) or (b["id"] == "holster" and player.holstered)
		var fill := Color(0.95, 0.7, 0.27, 0.55) if on else (Color(1, 0.35, 0.26, 0.22) if b["id"] == "fire" else Color(0.05, 0.06, 0.05, 0.3))
		draw_circle(bc, r, fill)
		draw_arc(bc, r, 0, TAU, 40, Color(1, 0.4, 0.3, 0.8) if b["id"] == "fire" else Color(0.92, 0.89, 0.8, 0.4), 1.5 * s)
		var label: String = b["label"]
		if b["id"] == "jump" and player.can_climb:
			label = "CLIMB"
		elif b["id"] == "holster" and player.holstered:
			label = "DRAW"
		elif b["id"] == "nade":
			label = "NADE %d" % player.grenades
		elif b["id"] == "act":
			label = player.act_label
		var fs := int((14 if b["id"] == "fire" else (10 if label.length() > 6 else 11)) * s)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, bc + Vector2(-tw / 2, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.93, 0.86))


## Looking through a sight: black all round a round field of view, and the reticle. PSO-1 (SVD): the aiming
## chevron with three lower ones for longer range, a side scale, the rangefinder curve. PGO-7 (RPG): range marks.
func _draw_scope(c: Vector2, vs: Vector2, s: float, gun: String) -> void:
	var r: float = vs.y * 0.47
	var big: float = vs.length()
	draw_arc(c, r + big * 0.5, 0, TAU, 96, Color(0, 0, 0), big)
	draw_arc(c, r + 5 * s, 0, TAU, 96, Color(0.02, 0.02, 0.02, 0.8), 10 * s)
	var red := Color(0.95, 0.15, 0.08, 0.95)
	var blk := Color(0.02, 0.02, 0.02, 0.9)
	var u := r / 10.0
	if gun == "svd":
		for k in 4:
			var cc := c + Vector2(0, k * u * 1.1)
			var sz: float = u * (0.55 if k == 0 else 0.35)
			draw_line(cc + Vector2(-sz, sz), cc, red if k == 0 else blk, 2.0 * s)
			draw_line(cc, cc + Vector2(sz, sz), red if k == 0 else blk, 2.0 * s)
		draw_line(c + Vector2(-r * 0.75, 0), c + Vector2(-u * 1.2, 0), blk, 1.6 * s)
		for k in range(1, 6):
			draw_line(c + Vector2(-u * 1.2 - k * u * 0.55, 0), c + Vector2(-u * 1.2 - k * u * 0.55, -u * (0.5 if k % 2 == 0 else 0.3)), blk, 1.4 * s)
			draw_line(c + Vector2(u * 1.2 + k * u * 0.55, 0), c + Vector2(u * 1.2 + k * u * 0.55, -u * (0.5 if k % 2 == 0 else 0.3)), blk, 1.4 * s)
		draw_line(c + Vector2(u * 1.2, 0), c + Vector2(r * 0.75, 0), blk, 1.6 * s)
		var pts := PackedVector2Array()
		for k in 12:
			var x: float = -r * 0.62 + k * u * 0.25
			pts.append(c + Vector2(x, u * 2.0 + pow(k / 11.0, 1.6) * u * 2.4))
		draw_polyline(pts, blk, 1.4 * s)
		draw_line(c + Vector2(-r * 0.62, u * 2.0), c + Vector2(-r * 0.62 + 11 * u * 0.25, u * 2.0), blk, 1.4 * s)
	else:
		draw_line(c + Vector2(-r * 0.8, 0), c + Vector2(r * 0.8, 0), blk, 1.6 * s)
		draw_line(c + Vector2(0, -u * 0.8), c + Vector2(0, u * 0.6), red, 2.2 * s)
		for k in range(1, 5):
			var y: float = k * u * 1.0
			draw_line(c + Vector2(-u * 0.6, y), c + Vector2(u * 0.6, y), blk, 1.6 * s)
			draw_string(font, c + Vector2(u * 0.8, y + 5 * s), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), blk)
		for k in range(-4, 5):
			if k != 0:
				draw_line(c + Vector2(k * u * 0.9, 0), c + Vector2(k * u * 0.9, -u * 0.4), blk, 1.4 * s)


## Mission HUD: the objectives (done ones struck through) and a marker on the next one with its distance.
func _draw_mission(vs: Vector2, s: float) -> void:
	var m = main.mission
	var tl := Vector2(24 * s, 30 * s)
	var h: float = (18 + 18 * m.objectives.size()) * s
	draw_rect(Rect2(tl - Vector2(12, 20) * s, Vector2(330, 0) * s + Vector2(0, h)), Color(0.05, 0.06, 0.06, 0.55))
	draw_string(font, tl, "MISSION %d  %s" % [m.n, m.title], HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), Color(1, 0.86, 0.7))
	var cur: Dictionary = m.current()
	for i in m.objectives.size():
		var o: Dictionary = m.objectives[i]
		var y: float = tl.y + (18 + 18 * i) * s
		var col := Color(0.55, 0.85, 0.5) if o["done"] else (Color(1, 1, 1) if o == cur else Color(0.7, 0.7, 0.66))
		var txt: String = ("[x] " if o["done"] else "[  ] ") + str(o["text"])
		draw_string(font, Vector2(tl.x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), col)
	if m.alarm:
		draw_string(font, tl + Vector2(0, h + 2 * s), "ALARM RAISED", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), Color(1, 0.3, 0.2, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01)))
	_draw_danger(vs, s)
	if cur.is_empty() or player.dead or player.scoped():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var wp: Vector3 = cur["pos"]
	var sp: Vector2
	var behind := cam.is_position_behind(wp)
	sp = cam.unproject_position(wp)
	if behind:
		sp = vs - sp
	var margin := 40.0 * s
	var clamped := sp.clamp(Vector2(margin, margin), vs - Vector2(margin, margin))
	if behind:
		clamped.y = vs.y - margin
	var col := Color(1.0, 0.82, 0.25, 0.9)
	var r := 9.0 * s
	draw_colored_polygon(PackedVector2Array([clamped + Vector2(0, -r), clamped + Vector2(r, 0), clamped + Vector2(0, r), clamped + Vector2(-r, 0)]), col)
	var dist := int(player.global_position.distance_to(wp))
	draw_string(font, clamped + Vector2(-14 * s, 24 * s), "%d m" % dist, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), col)


## A soldier who has seen the player, or is growing suspicious of him, has a small red mark over his head: faint
## while he only suspects, clear once he has seen. Nothing else on the screen (the ring, the countdown bar and the
## reinforcements' count were more than was wanted).
func _draw_danger(vs: Vector2, s: float) -> void:
	if player.dead:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for e in main.enemies:
		if e.dead:
			continue
		var seen: bool = e.mode == "combat"
		var al: float = clamp(float(e.alert), 0.0, 1.0)
		if not seen and al < 0.2:
			continue
		var dist: float = e.global_position.distance_to(player.global_position)
		if dist > 80.0:
			continue
		var head: Vector3 = e.global_position + Vector3(0, 2.12, 0)
		if cam.is_position_behind(head):
			continue
		var sp := cam.unproject_position(head)
		if sp.x < 0 or sp.x > vs.x or sp.y < 0 or sp.y > vs.y:
			continue
		var r: float = clamp(7.0 - dist * 0.06, 3.5, 7.0) * s
		var col := Color(1, 0.14, 0.1, 0.8) if seen else Color(1, 0.14, 0.1, 0.25 + 0.3 * al)
		draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)]), col)


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
	# the start screen: the soldier in the yard behind a blue haze; the name top left, the menu bottom left,
	# the missions as a row of picture cards along the bottom
	var k := _scale()
	mono = FontVariation.new()
	mono.base_font = ThemeDB.fallback_font
	mono.spacing_glyph = 3
	menu_back = MenuBack.new()
	menu_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_back.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_back.visible = false
	add_child(menu_back)
	start_panel = Control.new()
	start_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(start_panel)
	var t := Label.new()
	t.text = "OPERATION\nDUST SIGNAL"
	var tf := FontVariation.new()
	tf.base_font = ThemeDB.fallback_font
	tf.spacing_glyph = 6
	tf.variation_embolden = 0.9
	t.add_theme_font_override("font", tf)
	t.add_theme_font_size_override("font_size", int(46 * k))
	t.add_theme_color_override("font_color", TERM)
	t.add_theme_constant_override("line_spacing", int(-8 * k))
	t.add_theme_color_override("font_shadow_color", Color(0.05, 0.15, 0.3, 0.6))
	t.add_theme_constant_override("shadow_offset_y", 2)
	t.position = Vector2(70, 46) * k
	start_panel.add_child(t)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(4 * k))
	v.anchor_top = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 62 * k
	v.offset_top = -330 * k
	v.offset_bottom = -30 * k
	v.alignment = BoxContainer.ALIGNMENT_END
	start_panel.add_child(v)
	_entry(v, "PLAY", func(): main.go_level("m%d" % mini(main.unlocked(), main.MISSIONS_BUILT)))
	_entry(v, "ALL MISSIONS", func(): show_missions())
	_entry(v, "TRAINING YARD", func(): menu_back.visible = false; main.start_game())
	update_btn = _entry(v, "UPDATE", func(): OS.shell_open(update_url))
	update_btn.visible = false
	_entry(v, "QUIT", func(): get_tree().quit())
	ver_label = Label.new()
	ver_label.add_theme_font_size_override("font_size", int(12 * k))
	ver_label.add_theme_color_override("font_color", TERM_DIM)
	v.add_child(ver_label)
	card_scroll = ScrollContainer.new()
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.anchor_left = 0.0
	card_scroll.anchor_right = 1.0
	card_scroll.anchor_top = 1.0
	card_scroll.anchor_bottom = 1.0
	card_scroll.offset_left = 330 * k
	card_scroll.offset_top = -292 * k
	card_scroll.offset_bottom = -44 * k
	start_panel.add_child(card_scroll)
	card_row = HBoxContainer.new()
	card_row.add_theme_constant_override("separation", int(8 * k))
	card_scroll.add_child(card_row)
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
	var rb := _button(pv, "Restart mission", func(): main.go_level(main.level))
	rb.name = "Restart"
	var qb := _button(pv, "Quit to menu", func(): main.go_level(""))
	qb.name = "Quit"
	var bb := _button(pv, "Blood: On", func(): pass)
	bb.name = "Blood"
	bb.text = "Blood: On" if main.fx.blood_on else "Blood: Off"
	bb.pressed.connect(func():
		main.set_blood(not main.fx.blood_on)
		bb.text = "Blood: On" if main.fx.blood_on else "Blood: Off")
	_button(pv, "Check for update", func(): main.check_update_now(); _hint("Checking for update"))
	_button(pv, "Exit", func(): get_tree().quit())
	pause_panel.visible = false

	# the thirty missions: a list, a picture of each one built so far
	mission_panel = _panel()
	mission_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mission_panel.add_child(mv)
	var mt := Label.new()
	mt.text = "MISSION SELECT"
	mt.add_theme_font_override("font", mono)
	mt.add_theme_font_size_override("font_size", 28)
	mt.add_theme_color_override("font_color", TERM)
	mv.add_child(mt)
	mission_scroll = ScrollContainer.new()
	mission_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(mission_scroll)
	mission_grid = VBoxContainer.new()
	mission_grid.add_theme_constant_override("separation", 6)
	mission_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_scroll.add_child(mission_grid)
	_entry(mv, "BACK", func(): mission_panel.visible = false; start_panel.visible = true; menu_back.deep = false; menu_back.queue_redraw())
	mission_panel.visible = false

	brief_panel = _panel()
	brief_panel.visible = false
	result_panel = _panel()
	result_panel.visible = false


const MISSION_INFO := {
	1: ["BROKEN RELAY", "A militia radio station in the desert, at dusk. Take the codes, kill the generator, get out."],
	2: ["CITY 2026", "A border city under curfew, at night. The message, the transformer, the Courier, his laptop."],
	3: ["DEAD CITY", "A city the war has emptied, by day. The hospital, the car park, the headquarters, the yard."],
	4: ["IRON TIDE", "A freighter at anchor in a bay, at night. Board her from the sea: the manifest, the cargo, away."]}


func show_missions() -> void:
	for c in mission_grid.get_children():
		c.queue_free()
	var open: int = main.unlocked()
	var vs := get_viewport_rect().size
	var w: float = min(920.0, vs.x - 120.0)
	mission_scroll.custom_minimum_size = Vector2(w, vs.y - 190.0)
	for i in range(1, 31):
		var built: bool = i <= main.MISSIONS_BUILT
		var ok: bool = i <= open and built
		var info: Array = MISSION_INFO.get(i, ["CLASSIFIED", ""])
		var row := Button.new()
		row.custom_minimum_size = Vector2(w - 16.0, 104 if built else 58)
		row.disabled = not ok
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.1, 0.2, 0.85)
		sb.border_color = TERM if ok else Color(0.25, 0.32, 0.45)
		sb.border_width_left = 4
		sb.border_width_bottom = 1
		var sbh: StyleBoxFlat = sb.duplicate()
		sbh.bg_color = Color(0.14, 0.24, 0.42, 0.95)
		sbh.border_color = AMBER
		for st in ["normal", "disabled"]:
			row.add_theme_stylebox_override(st, sb)
		for st in ["hover", "pressed", "focus"]:
			row.add_theme_stylebox_override(st, sbh)
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -12
		h.offset_top = 6
		h.offset_bottom = -6
		h.add_theme_constant_override("separation", 14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		if built:
			var th := TextureRect.new()
			th.texture = load("res://assets/ui/m%d.jpg" % i)
			th.custom_minimum_size = Vector2(164, 92)
			th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			th.modulate = Color(1, 1, 1) if ok else Color(0.35, 0.35, 0.35)
			th.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(th)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		var l1 := Label.new()
		l1.text = "MISSION %02d   %s" % [i, info[0] if (built and i <= open) else ("CLASSIFIED" if not built else info[0])]
		l1.add_theme_font_override("font", mono)
		l1.add_theme_font_size_override("font_size", 20 if built else 16)
		l1.add_theme_color_override("font_color", TERM if ok else TERM_DIM)
		tv.add_child(l1)
		if built:
			var l2 := Label.new()
			l2.text = info[1]
			l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l2.add_theme_font_size_override("font_size", 13)
			l2.add_theme_color_override("font_color", Color(0.72, 0.78, 0.7) if ok else Color(0.4, 0.44, 0.4))
			tv.add_child(l2)
		var tag := Label.new()
		tag.text = ("COMPLETE" if i < open else "OPEN") if ok else ("COMING SOON" if i <= open else "LOCKED")
		tag.add_theme_font_override("font", mono)
		tag.add_theme_font_size_override("font_size", 14)
		tag.add_theme_color_override("font_color", (Color(0.55, 0.75, 0.5) if i < open else AMBER) if ok else Color(0.45, 0.48, 0.44))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tag)
		var lv := "m%d" % i
		row.pressed.connect(func(): main.go_level(lv))
		mission_grid.add_child(row)
	start_panel.visible = false
	mission_panel.visible = true
	menu_back.visible = true
	menu_back.deep = true
	menu_back.queue_redraw()
	_place_menu(mission_panel)


## Start and mission screens sit left of centre, over the map table.
func _place_menu(p: Control) -> void:
	if p == start_panel:
		return
	await get_tree().process_frame
	var vs := get_viewport_rect().size
	p.reset_size()
	p.position = Vector2(max(40.0, vs.x * 0.07), max(20.0, (vs.y - p.size.y) * 0.5))


const TERM := Color(0.96, 0.98, 1.0)
const TERM_DIM := Color(0.66, 0.78, 0.9)
const AMBER := Color(0.55, 0.9, 1.0)
var mono: FontVariation
var card_scroll: ScrollContainer
var card_row: HBoxContainer


## The missions along the bottom of the start screen: each a picture with its name on a dark band; the one to play
## next is larger, with a bright edge and a bar under it; the ones not built yet say so.
func _build_cards() -> void:
	for c in card_row.get_children():
		c.queue_free()
	var k := _scale()
	var open: int = main.unlocked()
	var cur: int = mini(open, main.MISSIONS_BUILT)
	for i in range(1, 31):
		var built: bool = i <= main.MISSIONS_BUILT
		var ok: bool = i <= open and built
		var info: Array = MISSION_INFO.get(i, ["CLASSIFIED", ""])
		var sel := i == cur
		var b := Button.new()
		b.custom_minimum_size = Vector2(390 if sel else 290, 248 if sel else 236) * k
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		b.disabled = not ok
		b.clip_contents = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.1, 0.18, 0.92)
		if sel:      # the next mission: a bright edge and a bar under it
			sb.border_color = AMBER
			sb.set_border_width_all(int(2 * k))
			sb.border_width_bottom = int(7 * k)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		if built:
			var th := TextureRect.new()
			th.texture = load("res://assets/ui/m%d.jpg" % i)
			th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			th.mouse_filter = Control.MOUSE_FILTER_IGNORE
			th.anchor_right = 1.0
			th.anchor_bottom = 1.0
			th.offset_left = 2 * k if sel else 0.0
			th.offset_top = 2 * k if sel else 0.0
			th.offset_right = -2 * k if sel else 0.0
			th.offset_bottom = -7 * k if sel else 0.0
			th.modulate = Color(0.95, 0.97, 1.0) if sel else (Color(0.55, 0.62, 0.75) if ok else Color(0.25, 0.28, 0.34))
			# a dark band under the words so they read over any picture
			var band := ColorRect.new()
			band.color = Color(0.03, 0.06, 0.14, 0.72)
			band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			band.anchor_right = 1.0
			band.anchor_top = 0.6
			band.anchor_bottom = 1.0
			band.offset_bottom = -7 * k if sel else 0.0
			b.add_child(band)
			b.add_child(th)
		var tv := VBoxContainer.new()
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.anchor_right = 1.0
		tv.anchor_top = 0.6
		tv.anchor_bottom = 1.0
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.add_theme_constant_override("separation", int(4 * k))
		b.add_child(tv)
		var ink := Color(1, 1, 1) if ok else Color(0.6, 0.66, 0.75)
		var lines := [["MISSION %02d" % i, 13, ink.lerp(Color(0.5, 0.55, 0.6), 0.4)], [info[0] if built else "CLASSIFIED", 22 if sel else 19, ink],
			[("NEXT UP" if sel else ("COMPLETE" if i < open else "OPEN")) if ok else ("COMING SOON" if i <= open else "LOCKED"), 12, AMBER if sel else ink.lerp(Color(0.5, 0.55, 0.6), 0.5)]]
		for ln in lines:
			var l := Label.new()
			l.text = ln[0]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_font_override("font", mono)
			l.add_theme_font_size_override("font_size", int(ln[1] * k))
			l.add_theme_color_override("font_color", ln[2])
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tv.add_child(l)
		var lv := "m%d" % i
		b.pressed.connect(func(): main.go_level(lv))
		card_row.add_child(b)
var menu_back: Control
var mission_scroll: ScrollContainer
var mission_grid: VBoxContainer


## A menu entry: plain capitals, a dot beside the one touched.
func _entry(parent: Node, text: String, cb: Callable) -> Button:
	var k := _scale()
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(250, 46) * k
	b.add_theme_font_override("font", mono)
	b.add_theme_font_size_override("font_size", int(21 * k))
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 26 * k
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1, 1, 1, 0.0)
	sh.border_color = Color(1, 1, 1)
	sh.border_width_left = int(6 * k)
	sh.content_margin_left = 20 * k
	b.add_theme_stylebox_override("normal", sb)
	for st in ["hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sh)
	b.add_theme_color_override("font_color", TERM)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_shadow_color", Color(0.03, 0.1, 0.25, 0.7))
	b.add_theme_constant_override("shadow_offset_y", 1)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Over the 3D scene behind the menus: a haze, pale blue-green above and deep blue below (deeper for the list).
class MenuBack extends Control:
	var deep := false
	func _draw() -> void:
		var vs := get_viewport_rect().size
		var top := Color(0.3, 0.72, 0.85, 0.42)
		var mid := Color(0.12, 0.38, 0.7, 0.5)
		var bot := Color(0.04, 0.08, 0.36, 0.9)
		if deep:
			top = Color(0.05, 0.12, 0.3, 0.9)
			mid = Color(0.04, 0.09, 0.28, 0.93)
		var h := vs.y * 0.55
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, h), Vector2(0, h)]), PackedColorArray([top, top, mid, mid]))
		draw_polygon(PackedVector2Array([Vector2(0, h), Vector2(vs.x, h), Vector2(vs.x, vs.y), Vector2(0, vs.y)]), PackedColorArray([mid, mid, bot, bot]))


## Before a mission: its name, the briefing and the objectives.
func show_briefing(m: Node) -> void:
	for c in brief_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(min(760.0, get_viewport_rect().size.x - 80.0), 0)
	brief_panel.add_child(v)
	var t := Label.new()
	t.text = "MISSION %d: %s" % [m.n, m.title]
	t.add_theme_font_size_override("font_size", 26)
	v.add_child(t)
	var b := Label.new()
	b.text = m.briefing
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.85, 0.83, 0.76))
	v.add_child(b)
	var o := Label.new()
	var lines := "OBJECTIVES"
	for ob in m.objectives:
		lines += "\n-  " + str(ob["text"])
	o.text = lines
	o.add_theme_font_size_override("font_size", 15)
	o.add_theme_color_override("font_color", Color(1, 0.86, 0.6))
	v.add_child(o)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	_button(h, "Start mission", func(): brief_panel.visible = false; main.start_game(), true)
	_button(h, "Back", func(): main.go_level(""))
	brief_panel.visible = true
	_center(brief_panel)


## Mission over: complete (next mission, the list) or failed (try again).
func show_result(win: bool, title: String, sub: String, n: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.firing = false
	held.clear()
	for c in result_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	result_panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.6, 1, 0.55) if win else Color(1, 0.4, 0.3))
	v.add_child(t)
	var st := Label.new()
	st.text = sub
	st.add_theme_font_size_override("font_size", 15)
	v.add_child(st)
	if win and n + 1 <= main.MISSIONS_BUILT:
		_button(v, "Next mission", func(): main.go_level("m%d" % (n + 1)), true)
	elif win:
		var nx := Label.new()
		nx.text = "Mission %d is unlocked and comes in the next update." % (n + 1)
		nx.add_theme_font_size_override("font_size", 14)
		nx.add_theme_color_override("font_color", Color(0.85, 0.83, 0.76))
		v.add_child(nx)
	_button(v, "Play again" if win else "Try again", func(): main.go_level("m%d" % n), not win)
	_button(v, "Mission list", func(): Engine.set_meta("show_missions", true); main.go_level(""))
	_button(v, "Main menu", func(): main.go_level(""))
	player.move_in = Vector2.ZERO
	joy_id = -1
	look_ids.clear()
	result_panel.visible = true
	_center(result_panel)


func show_start(ver: int) -> void:
	ver_label.text = "      v%d" % ver if ver > 0 else "      test build"
	_build_cards()
	start_panel.position = Vector2.ZERO
	start_panel.size = get_viewport_rect().size
	start_panel.visible = true
	menu_back.visible = true
	menu_back.deep = false
	main.hero_shot(true)
	if Engine.get_meta("show_missions", false):
		Engine.set_meta("show_missions", false)
		show_missions()


func hide_start() -> void:
	start_panel.visible = false
	menu_back.visible = false
	main.hero_shot(false)


func show_pause() -> void:
	player.firing = false
	player.aiming = false
	player.move_in = Vector2.ZERO
	held.clear()
	joy_id = -1
	look_ids.clear()
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.get_child(0).get_node("Restart").visible = main.mission != null
	pause_panel.get_child(0).get_node("Quit").visible = true
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
