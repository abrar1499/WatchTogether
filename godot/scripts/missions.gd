extends Node
## The missions: each builds its own ground and base into main, places its soldiers, and runs its objectives
## (with an alarm that brings reinforcements, and a pickup point to get out at). Thirty are planned; they open
## one after another (progress kept in user://progress.cfg). Missions not built yet say so on the mission list.

var main: Node
var n := 0
var title := ""
var briefing := ""
var objectives := []          # [{"text", "done", "pos" (where the marker points), "needs" (indexes done first)}]
var items := []               # things to pick up: Node3D with meta "label", "obj"
var posts := []               # soldiers: [pos, face, kind, gun, route]
var lz := Vector3.ZERO
var lz_smoke := 0.0
var alarm := false
var alarm_src: Node = null
var alarm_t := -1.0           # a soldier who has seen the player gets to the alarm in a few seconds
const ALARM_TIME := 5.0       # how long he takes to call it in (shown on the screen: kill him first)
var seen := false             # some soldier has seen the player for certain (the mission is no longer a ghost's)
var silenced := 0             # callers killed before they finished
var reinf_t := -1.0
var siren: AudioStreamPlayer3D
var siren_pos := Vector3.ZERO
var over := false
var start_t := 0.0
var t := 0.0
var mats := {}
var start_yaw := 0.0
var alarm_text := "The station knows you are here. More soldiers are coming."
var reinf_spots := [Vector3(70, 0, -27), Vector3(72, 0, -24), Vector3(70, 0, -21), Vector3(73, 0, -19)]
var target_post := -1         # a soldier whose death is an objective (index into posts)
var target_obj := -1
var target: Node = null
var power_zone := Rect2()     # where the lights go out when the mission's power supply is destroyed
var power_cut := false


## Build mission `num` into main; returns where the player starts.
func build(num: int) -> Vector3:
	n = num
	match num:
		1:
			return await _m1()
		2:
			return await _m2()
		3:
			return await _m3()
		4:
			return await _m4()
	return Vector3(0, 0.05, 6)


func ready_player() -> void:
	var p = main.player
	p.infinite = false
	# he starts with three guns (pistol, AK-47, M4A1), full; the rest are taken from the soldiers he kills
	for w in p.weapons:
		w["own"] = w["gun"] in START_GUNS
		w["mag"] = w["size"]
		w["res"] = w["res0"]
	p.wi = 2
	p.grenades = 3
	p.yaw = start_yaw


var mustered := false


const START_GUNS := ["pistol", "ak", "m4"]
const ENEMY_GUNS := ["ak", "m4", "badger", "smg", "ak", "shotgun", "m4", "badger"]   # (snipers keep their Dragunov)


## A rifleman's gun: every soldier carries one of the armoury's, taken in turn (the player can pick it up).
func _enemy_gun(g: String) -> String:
	if g != "ak":
		return g
	return ENEMY_GUNS[main.enemies.size() % ENEMY_GUNS.size()]


func _post_soldier(ps: Array) -> void:
	var e = load("res://scripts/enemy.gd").new()
	e.name = "Enemy%d" % main.enemies.size()
	main.add_child(e)
	e.setup(main, ps[0] + Vector3(0, 0.05, 0), ps[1], ps[0], ps[2], _enemy_gun(ps[3]), ps[4])
	main.enemies.append(e)
	_far_cull(e)


## The soldiers at their posts, made while the loading screen is still up: each is a model, a skeleton and an
## animation tree, and all of them together were a freeze of a second or two after START was pressed. They stand
## where they are, not thinking, until begin().
func muster() -> void:
	if mustered:
		return
	mustered = true
	for i in posts.size():
		_post_soldier(posts[i])
		var e = main.enemies[main.enemies.size() - 1]
		e.set_process(false)
		e.set_physics_process(false)
		if i % 3 == 2:
			await get_tree().process_frame
	if target_post >= 0:
		target = main.enemies[target_post]


func begin() -> void:
	start_t = t
	Engine.time_scale = 1.0
	if not mustered:
		mustered = true
		for ps in posts:
			_post_soldier(ps)
		if target_post >= 0:
			target = main.enemies[target_post]
	for e in main.enemies:
		e.set_process(true)
		e.set_physics_process(true)
		e.grace = 1.0
	if main.snow:
		var sn: Node3D = load("res://scripts/snow.gd").new()
		main.add_child(sn)
		sn.start(main)
	if n == 2:
		# the night: head lamps, tower lamps, and the weather turning to rain
		var nt: Node3D = load("res://scripts/night.gd").new()
		main.add_child(nt)
		nt.start(main)
	main.ui.message("MISSION %d" % n, title, 3.5)


# ---------------- objectives ----------------
func current() -> Dictionary:
	for o in objectives:
		if o["done"]:
			continue
		var ok := true
		for k in o.get("needs", []):
			ok = ok and objectives[k]["done"]
		if ok:
			return o
	return {}


func complete_objective(i: int) -> void:
	if objectives[i]["done"]:
		return
	objectives[i]["done"] = true
	main.ui.message("OBJECTIVE COMPLETE", objectives[i]["text"], 3.0)
	var nx := current()
	if not nx.is_empty():
		get_tree().create_timer(3.2).timeout.connect(func(): if not over: main.ui.message("NEW OBJECTIVE", nx["text"], 3.0))


func item_near(p: Vector3) -> Node3D:
	for it in items:
		if is_instance_valid(it) and it.visible and it.global_position.distance_to(p + Vector3(0, 0.9, 0)) < 1.6:
			return it
	return null


func take_item(it: Node3D) -> void:
	it.visible = false
	main.snd.holster()
	complete_objective(int(it.get_meta("obj")))


func on_destroyed(m: Node) -> void:
	if m.get_meta("power", false):
		power_cut = true
		city.power_cut(power_zone)
		get_tree().create_timer(1.5).timeout.connect(func(): if not over: main.ui.message("POWER CUT", "The streets round the hotel go dark. Their alarm has no power now.", 3.5))
	if m.has_meta("obj"):
		complete_objective(int(m.get_meta("obj")))


func fail() -> void:
	if over:
		return
	over = true
	get_tree().create_timer(2.5).timeout.connect(func():
		main.ui.show_result(false, "MISSION FAILED", "You were killed.", n))


func _win() -> void:
	over = true
	main.unlock(n + 1)
	var secs := int(t - start_t)
	# how it was done: unseen from start to finish, seen but never reported, or with the whole place awake
	var rank := "GHOST" if not seen else ("SILENT" if not alarm else "LOUD")
	var stats := "%s   Time %d:%02d   Kills %d   Headshots %d" % [rank, secs / 60, secs % 60, main.kills, main.headshots]
	if silenced > 0:
		stats += "   Calls cut short %d" % silenced
	main.ui.show_result(true, "MISSION COMPLETE", stats, n)


func _process(dt: float) -> void:
	t += dt
	_sweep(dt)
	if over or not main.playing:
		return
	if target != null and target.dead and target_obj >= 0 and not objectives[target_obj]["done"]:
		complete_objective(target_obj)
	var p = main.player
	# the alarm: a soldier in a fight raises it a few seconds later unless he is dead by then
	if not alarm:
		if alarm_t < 0.0:
			for e in main.enemies:
				if not e.dead and e.mode == "combat":
					alarm_src = e
					alarm_t = ALARM_TIME
					seen = true
					break
		else:
			alarm_t -= dt
			if alarm_src == null or alarm_src.dead:
				# the man calling it in is dead before he finished: the nearer the end, the closer the call
				if alarm_t < 1.3:
					main.ui.message("CLOSE CALL", "He never finished the call.", 2.2)
					_slow_motion(0.7)
				else:
					main.ui.message("RADIO SILENCED", "No one heard him.", 1.8)
				silenced += 1
				alarm_t = -1.0
			elif alarm_t <= 0.0:
				_raise_alarm()
	elif reinf_t > 0.0:
		reinf_t -= dt
		if reinf_t <= 0.0:
			_reinforce()
	# the pickup point: green smoke once it is the objective; reach it to finish
	var o := current()
	if not o.is_empty() and o.get("lz", false):
		lz_smoke -= dt
		if lz_smoke <= 0.0:
			lz_smoke = 0.12
			main.fx._big(lz + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2)), 1.0, 5.0, 5.0, Vector3(randf_range(-0.2, 0.5), 1.8, randf_range(-0.2, 0.2)),
				Color(0.3, 0.8, 0.3, 0.85), Color(0.55, 0.8, 0.5, 0.0))
		if Vector2(p.global_position.x - lz.x, p.global_position.z - lz.z).length() < 4.0:
			o["done"] = true
			_win()


## A soldier is not drawn beyond 150 m (far past where he can see or hit anyone).
var far_cull := 150.0


func _far_cull(e: Node) -> void:
	for g in e.find_children("*", "GeometryInstance3D", true, false):
		g.visibility_range_end = far_cull


## A moment of slow motion (real seconds), for a close call.
func _slow_motion(secs: float) -> void:
	Engine.time_scale = 0.35
	get_tree().create_timer(secs, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _raise_alarm() -> void:
	alarm = true
	reinf_t = 9.0
	if power_cut and power_zone.has_point(Vector2(alarm_src.global_position.x, alarm_src.global_position.z)):
		# no power for the siren here: the fight is heard, but nobody else is called in
		reinf_t = -1.0
		main.ui.message("ALARM!", "They have seen you, but their alarm is dead. No one else is coming.", 3.5)
	else:
		main.ui.message("ALARM!", alarm_text, 3.5)
	main.music.alarm()
	# the ones within earshot come to look; the rest of the town keeps its posts
	for e in main.enemies:
		if not e.dead and e.global_position.distance_to(main.player.global_position) < 80.0:
			e.investigate(main.player.global_position)


func _reinforce() -> void:
	var spots := reinf_spots
	var kinds := ["olive", "blue", "gasmask", "olive"]
	for i in spots.size():
		var e = load("res://scripts/enemy.gd").new()
		e.name = "Enemy%d" % main.enemies.size()
		main.add_child(e)
		e.setup(main, spots[i] + Vector3(0, 0.05, 0), 0.0, spots[i], kinds[i], _enemy_gun("ak"), [])
		e.grace = 0.0
		main.enemies.append(e)
		_far_cull(e)
		e.alarm(main.player.global_position)


# ---------------- building blocks ----------------
func _m(key: String) -> BaseMaterial3D:
	if mats.has(key):
		return mats[key]
	var m: StandardMaterial3D
	match key:
		"plaster":
			return main.pbr("brushed_concrete", Color(0.95, 0.88, 0.76), 0.45, 0.0)
		"concrete":
			return main.pbr("brushed_concrete", Color(0.86, 0.84, 0.8), 0.5, 0.0)
		"cwall":
			return main.pbr("brushed_concrete", Color(0.9, 0.86, 0.8), 0.4, 0.0)
		"steel":
			return main.pbr("rusty_painted_metal", Color(0.62, 0.62, 0.6), 0.8)
		"green":
			return main.pbr("green_metal_rust", Color(1, 1, 1), 0.6)
		"dark":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.08, 0.08, 0.08)
			m.roughness = 0.8
		"red":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.6, 0.08, 0.06)
			m.roughness = 0.6
		"white":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.9, 0.9, 0.86)
			m.roughness = 0.7
		"glass":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.06, 0.08, 0.09)
			m.metallic = 0.6
			m.roughness = 0.12
		"wood":
			return main.pbr("plywood", Color(0.7, 0.58, 0.45), 0.8, 0.0)
		"fence":
			m = StandardMaterial3D.new()
			m.albedo_texture = _chainlink()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA       # (fades to a grey haze far off, as real mesh does)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic = 0.6
			m.roughness = 0.5
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 6.5      # a diamond about 15 cm across
	mats[key] = m
	return m


## A diamond-mesh chain-link tile (transparent between the wires).
func _chainlink() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in s:
		for w in [-1, 0, 1]:
			var a: int = (i + w + s) % s
			img.set_pixel(i, a, Color(0.62, 0.63, 0.6, 1))
			img.set_pixel(i, (s - 1 - i + w + s) % s, Color(0.55, 0.56, 0.53, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A solid box (mesh and collision) centred at c.
func _block(c: Vector3, size: Vector3, mat: String, surf := "concrete", rot := 0.0, collide := true) -> Node3D:
	var b: Node3D = StaticBody3D.new() if collide else Node3D.new()
	b.set_meta("surf", surf)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _m(mat)
	b.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)
	main.add_child(b)
	b.global_position = c
	b.rotation.y = rot
	return b


## A straight wall from a to b (x, z), height h, thickness th, with at most one opening [from, to (along the wall,
## metres), bottom, top].
func _wall(a: Vector2, b: Vector2, h: float, th: float, mat: String, hole := []) -> void:
	var d := b - a
	var L := d.length()
	var u := d / L
	var rot := atan2(-u.y, u.x)
	var at := func(s: float, y0: float, s1: float, y1: float) -> void:
		if s1 - s < 0.01 or y1 - y0 < 0.01:
			return
		var m := a + u * ((s + s1) * 0.5)
		_block(Vector3(m.x, (y0 + y1) * 0.5, m.y), Vector3(s1 - s, y1 - y0, th), mat, "concrete", rot)
	if hole.is_empty():
		at.call(0.0, 0.0, L, h)
		return
	at.call(0.0, 0.0, hole[0], h)
	at.call(hole[1], 0.0, L, h)
	at.call(hole[0], 0.0, hole[1], hole[2])
	at.call(hole[0], hole[3], hole[1], h)


## A one-room hut: plastered walls with a door opening (and a plank door in it) and a window, concrete floor and roof.
## c: centre of the floor; size x by z; the door in the +z wall at door_x (from the centre).
func _hut(c: Vector3, sx: float, sz: float, door_x: float, window_side := "x") -> StaticBody3D:
	var h := 2.9
	var th := 0.2
	var x0 := c.x - sx * 0.5
	var x1 := c.x + sx * 0.5
	var z0 := c.z - sz * 0.5
	var z1 := c.z + sz * 0.5
	var dl := (door_x + sx * 0.5) - 0.55
	_wall(Vector2(x0, z1), Vector2(x1, z1), h, th, "plaster", [dl, dl + 1.1, 0.0, 2.15])
	_wall(Vector2(x1, z0), Vector2(x0, z0), h, th, "plaster")
	_wall(Vector2(x0, z0 + th * 0.5), Vector2(x0, z1 - th * 0.5), h, th, "plaster", [sz * 0.5 - 0.6, sz * 0.5 + 0.6, 1.0, 1.9] if window_side == "-x" else [])
	_wall(Vector2(x1, z1 - th * 0.5), Vector2(x1, z0 + th * 0.5), h, th, "plaster", [sz * 0.5 - 0.6, sz * 0.5 + 0.6, 1.0, 1.9] if window_side == "x" else [])
	_block(Vector3(c.x, h + 0.1, c.z), Vector3(sx + 0.3, 0.2, sz + 0.3), "concrete")
	_block(Vector3(c.x, 0.03, c.z), Vector3(sx - 0.2, 0.06, sz - 0.2), "concrete")
	_block(Vector3(c.x + door_x, 2.2, z1 + 0.15), Vector3(1.5, 0.08, 0.35), "concrete")       # a little canopy
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 0.9
	light.omni_range = max(sx, sz)
	main.add_child(light)
	light.global_position = c + Vector3(0, 2.5, 0)
	return main.make_door(Vector3(c.x + door_x - 0.55, 0.06, z1), 0.0, 1.1, 2.1)


## Chain-link fence from a to b (x, z): concrete posts every 3 m, the mesh, three strands of barbed wire on top;
## too high to climb. gaps: [[from, to]] along it left open.
func _fence(a: Vector2, b: Vector2, gaps := []) -> void:
	var d := b - a
	var L := d.length()
	var u := d / L
	var rot := atan2(-u.y, u.x)
	var segs := []
	var s := 0.0
	for g in gaps:
		segs.append([s, g[0]])
		s = g[1]
	segs.append([s, L])
	for sg in segs:
		var s0: float = sg[0]
		var s1: float = sg[1]
		if s1 - s0 < 0.2:
			continue
		var m := a + u * ((s0 + s1) * 0.5)
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(s1 - s0, 2.4)
		mi.mesh = q
		var fm: StandardMaterial3D = _m("fence")
		mi.material_override = fm
		main.add_child(mi)
		mi.global_position = Vector3(m.x, 1.25, m.y)
		mi.rotation.y = rot
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var col := StaticBody3D.new()
		col.set_meta("surf", "metal")
		col.set_meta("pierce", "sheet")
		col.set_meta("seethrough", true)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(s1 - s0, 3.4, 0.08)
		cs.shape = sh
		col.add_child(cs)
		main.add_child(col)
		col.global_position = Vector3(m.x, 1.7, m.y)
		col.rotation.y = rot
		var k := s0
		while k <= s1 + 0.01:
			var pp := a + u * k
			_block(Vector3(pp.x, 1.4, pp.y), Vector3(0.12, 2.8, 0.12), "concrete", "concrete", rot)
			k += 3.0
		for hgt in [2.55, 2.7, 2.85]:
			_block(Vector3(m.x, hgt, m.y), Vector3(s1 - s0, 0.015, 0.015), "dark", "metal", rot, false)



## A watchtower: posts, a platform 3.2 m up with a low wall round it, a tin roof; the concrete stairs come up on its
## east side (foot at `base`, rising toward -z).
func _tower(base: Vector3) -> Vector3:
	main.stairs_flight(base)
	var pc := base + Vector3(-0.56 - 1.6, 0, -4.6)       # platform centre (x, z)
	for dx in [-1.5, 1.5]:
		for dz in [-1.5, 1.5]:
			_block(pc + Vector3(dx, 1.55, dz), Vector3(0.18, 3.1, 0.18), "steel", "metal")
			_block(pc + Vector3(dx, 4.45, dz), Vector3(0.08, 2.3, 0.08), "steel", "metal")
	_block(pc + Vector3(0, 3.1, 0), Vector3(3.3, 0.2, 3.3), "concrete")
	_block(pc + Vector3(0, 3.7, -1.6), Vector3(3.3, 1.0, 0.12), "plaster")
	_block(pc + Vector3(-1.6, 3.7, 0), Vector3(0.12, 1.0, 3.3), "plaster")
	_block(pc + Vector3(0, 3.7, 1.6), Vector3(3.3, 1.0, 0.12), "plaster")
	_block(pc + Vector3(1.6, 3.7, 0.95), Vector3(0.12, 1.0, 1.4), "plaster")
	_block(pc + Vector3(0, 5.65, 0), Vector3(3.6, 0.1, 3.6), "steel", "metal")
	return pc + Vector3(0, 3.2, 0)


## A lattice radio mast: three legs, braces, a red lamp on top.
func _mast(c: Vector3, h := 22.0) -> void:
	var legs := []
	for i in 3:
		var a: float = i * TAU / 3.0
		legs.append(Vector3(cos(a), 0, sin(a)) * 0.55)
	for l in legs:
		_block(c + l + Vector3(0, h * 0.5, 0), Vector3(0.07, h, 0.07), "steel", "metal", 0.0, false)
	var y := 1.0
	while y < h:
		for i in 3:
			var p0: Vector3 = c + legs[i] + Vector3(0, y, 0)
			var p1: Vector3 = c + legs[(i + 1) % 3] + Vector3(0, y, 0)
			var mid := (p0 + p1) * 0.5
			var bm := _block(mid, Vector3(p0.distance_to(p1), 0.04, 0.04), "steel", "metal", 0.0, false)
			bm.look_at(p1, Vector3.UP)
			bm.rotate_object_local(Vector3.UP, PI * 0.5)
		y += 1.5
	_block(c + Vector3(0, 1.0, 0), Vector3(1.4, 2.0, 1.4), "steel", "metal", 0.0, true).visible = false
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.1, 0.05)
	lamp.light_energy = 2.0
	lamp.omni_range = 3.0
	main.add_child(lamp)
	lamp.global_position = c + Vector3(0, h + 0.2, 0)
	var bulb := _block(c + Vector3(0, h + 0.1, 0), Vector3(0.18, 0.18, 0.18), "red", "metal", 0.0, false)
	var bm: StandardMaterial3D = _m("red").duplicate()
	bm.emission_enabled = true
	bm.emission = Color(1, 0.1, 0.05)
	bm.emission_energy_multiplier = 3.0
	bulb.get_child(0).material_override = bm


## A diesel generator: the machine to knock out (rounds wear it down; an explosion finishes it).
func _generator(c: Vector3, rot: float, obj: int) -> StaticBody3D:
	var g := StaticBody3D.new()
	g.set_meta("surf", "metal")
	g.set_meta("kind", "machine")
	g.set_meta("hp", 650.0)
	g.set_meta("obj", obj)
	var parts := [[Vector3(0, 0.75, 0), Vector3(2.4, 1.3, 1.1), "green"], [Vector3(0, 0.08, 0), Vector3(2.6, 0.16, 1.2), "steel"],
		[Vector3(1.15, 0.75, 0), Vector3(0.12, 1.0, 0.9), "dark"], [Vector3(-0.6, 1.62, 0.2), Vector3(0.12, 0.6, 0.12), "dark"],
		[Vector3(-0.2, 0.9, 0.56), Vector3(0.7, 0.4, 0.04), "steel"]]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[1]
		mi.mesh = bm
		mi.material_override = _m(pt[2])
		mi.position = pt[0]
		g.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.6, 1.5, 1.2)
	cs.shape = sh
	cs.position = Vector3(0, 0.75, 0)
	g.add_child(cs)
	main.add_child(g)
	g.global_position = c
	g.rotation.y = rot
	main.machines.append(g)
	return g


func _crate(p: Vector3) -> void:
	main.breakables.append({"kind": "crate", "pos": p, "rot": randf_range(-0.08, 0.08), "node": null})


func _drum(p: Vector3, color := "red") -> void:
	main.breakables.append({"kind": "drum", "pos": p, "rot": randf() * TAU, "color": color, "node": null})


# =============== MISSION 1: BROKEN RELAY ===============
## A militia radio relay station in the desert, in two parts: an outer yard inside the fence (gate with two guards,
## two watchtowers, containers, a patrol) and, behind an inner concrete wall with its own guarded gate, the inner
## compound (command hut, barracks with a man on the roof, a third tower, the mast and its generator). The player
## starts west of it behind a ruined wall; the way out is the east gate.
func _m1() -> Vector3:
	title = "BROKEN RELAY"
	briefing = "A militia unit has taken a radio relay station on the old mountain road, deep in the snow, and is using it to pass orders " + \
		"to its fighters across the border.\n\nYou start behind a ruined wall west of the station. Get through the outer " + \
		"yard and the inner wall, take the relay codes from the command hut, knock out the generator that powers the mast, " + \
		"and get out through the east gate to the pickup point.\n\nYou carry a pistol, an AK-47, an M4A1, a knife and three " + \
		"grenades. Take what you need from the guards. If a guard raises the alarm, more soldiers will come up the road."
	main.flat_c = Vector2(0, -25)
	main.flat_r = 80.0
	main.area = Rect2(-33, -54, 66, 58)
	main.snow = true
	Engine.set_meta("hd_people", true)        # (people drawn as on the training ground: deeper cloth, a sheen at the edges)
	await main.breathe(3)
	main._build_ground()
	main._build_mountains()
	await main.breathe(3)
	main._build_rocks(main._tex_mat("res://assets/env/rock_albedo.jpg", "res://assets/env/rock_normal.png", 0.6, 0.95, true), 70.0, false)
	main.scatter(500, 70, 44.0)        # (most of the stones and scrub are under the snow)
	main.apply_snow()
	main.extra_cover = []
	# the fence: west gate (the way in), east gate (the way out), a torn stretch in the south side
	_fence(Vector2(-34, 5), Vector2(34, 5), [[54.0, 57.0]])
	_fence(Vector2(34, 5), Vector2(34, -55), [[26.0, 32.0]])
	_fence(Vector2(34, -55), Vector2(-34, -55))
	_fence(Vector2(-34, -55), Vector2(-34, 5), [[28.0, 34.0]])
	# west gate: booth and a lowered barrier
	_block(Vector3(-31.5, 1.3, -31.0), Vector3(2.2, 2.6, 2.2), "plaster")
	_block(Vector3(-32.62, 1.6, -31.0), Vector3(0.04, 0.8, 1.6), "glass", "metal", 0.0, false)
	_block(Vector3(-31.5, 2.7, -31.0), Vector3(2.6, 0.15, 2.6), "steel", "metal")
	_block(Vector3(-34.0, 0.5, -28.4), Vector3(0.25, 1.0, 0.25), "steel", "metal")
	_block(Vector3(-34.0, 0.95, -24.0), Vector3(0.1, 0.1, 8.0), "white", "metal")
	for k in 4:
		_block(Vector3(-34.0, 0.95, -27.0 + k * 2.0), Vector3(0.11, 0.11, 0.9), "red", "metal", 0.0, false)
	# where the player starts: a ruined wall west of the station, and cover on the way in
	_block(Vector3(-61.0, 1.1, -8.0), Vector3(0.45, 2.2, 7.0), "plaster")
	_block(Vector3(-61.0, 0.7, -12.6), Vector3(0.45, 1.4, 2.2), "plaster")
	_block(Vector3(-61.0, 0.45, -3.6), Vector3(0.45, 0.9, 1.8), "plaster")
	for p in [Vector3(-52, 0, -14), Vector3(-47, 0, -2), Vector3(-44, 0, -30), Vector3(-41, 0, -17)]:
		_crate(p)
	_sandbags(Vector3(-48, 0, -23), 4)
	# the inner wall: concrete T-walls along x = -6, with a gate in the middle
	for z in range(4, -21, -2):
		main._prop("res://assets/env/barrier.glb", Vector3(-6, 0, z - 1.0), PI * 0.5 + randf_range(-0.015, 0.015), Vector3(2.0, 2.6, 0.3), "concrete")
	for z in range(-27, -55, -2):
		main._prop("res://assets/env/barrier.glb", Vector3(-6, 0, z - 1.0), PI * 0.5 + randf_range(-0.015, 0.015), Vector3(2.0, 2.6, 0.3), "concrete")
	# outer yard: two towers, containers, crates, sandbags, drums
	var tower_a := _tower(Vector3(-28.0, 0, 2.0))
	var tower_b := _tower(Vector3(-28.0, 0, -44.0))
	for c in [[Vector3(-20, 0, -12), 0.0, "green"], [Vector3(-18, 0, -40), PI * 0.5, "blue"]]:
		var cb: StaticBody3D = main._prop("res://assets/env/container_%s.glb" % c[2], c[0], c[1], Vector3(2.44, 2.59, 6.06), "metal")
		cb.set_meta("pierce", "sheet")
	for p in [Vector3(-25, 0, -22), Vector3(-23.6, 0, -22.3), Vector3(-14, 0, -4), Vector3(-21, 0, -30), Vector3(-10, 0, -48)]:
		_crate(p)
	_sandbags(Vector3(-14, 0, -25.5), 4)
	_drum(Vector3(-16, 0, -18.5), "red")
	_drum(Vector3(-16.6, 0, -19.1), "blue")
	await main.breathe(3)
	# inner compound: command hut, barracks, a third tower, mast and generator
	var hut_c := Vector3(8, 0, -12)
	_hut(hut_c, 6.0, 5.0, 1.2, "x")
	_car("land_rover_olive", hut_c + Vector3(6.2, 0, 1.5), 0.25)       # the commander's Land Rover by his hut
	_block(hut_c + Vector3(-1.4, 0.4, -1.2), Vector3(1.6, 0.8, 0.8), "wood", "wood")
	_block(hut_c + Vector3(-2.4, 0.35, -1.9), Vector3(0.5, 0.7, 0.5), "steel", "metal")
	_block(hut_c + Vector3(2.2, 0.5, -1.8), Vector3(1.0, 1.0, 0.6), "green", "metal")
	var codes := _block(hut_c + Vector3(-1.2, 0.83, -1.1), Vector3(0.32, 0.05, 0.24), "red", "wood", 0.3, false)
	codes.set_meta("label", "TAKE CODES")
	codes.set_meta("obj", 0)
	items.append(codes)
	main._prop("res://assets/env/building.glb", Vector3(20, 0, -40), 0.0, Vector3(10, 3.2, 7), "concrete")
	main._building_extras(Vector3(20, 0, -40))
	siren_pos = Vector3(15, 3.0, -36)
	var tower_c := _tower(Vector3(30.0, 0, -2.0))
	# evening: searchlights sweeping from the towers, lamps on poles round the compound
	_searchlight(tower_a, PI * 0.5, 2)
	_searchlight(tower_b, PI * 0.5, 3)
	_searchlight(tower_c, PI * 0.75, 14)
	for lp in [Vector3(-32.6, 0, -26.0), Vector3(-30.5, 0, -17.0), Vector3(-4.6, 0, -24.0), Vector3(-15, 0, -30), Vector3(11.5, 0, -8.6),
			Vector3(14.5, 0, -34.5), Vector3(4.5, 0, -44.5), Vector3(32.5, 0, -22.0), Vector3(-20, 0, -8.5), Vector3(20, 0, -18)]:
		_lamp(lp)
	_mast(Vector3(14, 0, -50))
	_generator(Vector3(6, 0, -47), 0.0, 1)
	_drum(Vector3(8.2, 0, -46.4), "red")
	_drum(Vector3(8.9, 0, -47.1), "blue")
	_drum(Vector3(3.4, 0, -48.0), "red")
	var cr: StaticBody3D = main._prop("res://assets/env/container_red.glb", Vector3(16, 0, -22), PI * 0.5, Vector3(2.44, 2.59, 6.06), "metal")
	cr.set_meta("pierce", "sheet")
	for p in [Vector3(2, 0, -6), Vector3(3.4, 0, -6.3), Vector3(24, 0, -26), Vector3(-2, 0, -38), Vector3(27, 0, -48)]:
		_crate(p)
	_sandbags(Vector3(4, 0, -32), 4)
	_drum(Vector3(22, 0, -12), "red")
	main._restore_breakables()
	# the way out: the pickup point east of the station
	lz = Vector3(60, 0, -24)
	objectives = [
		{"text": "Take the relay codes from the command hut", "done": false, "pos": hut_c + Vector3(-1.2, 1.0, -1.1)},
		{"text": "Knock out the generator powering the mast", "done": false, "pos": Vector3(6, 1.2, -47)},
		{"text": "Get out through the east gate to the pickup point", "done": false, "pos": lz + Vector3(0, 1, 0), "needs": [0, 1], "lz": true}]
	var west := PI * 0.5
	# the soldiers: [position, facing (0 faces north, PI/2 west), character, gun, patrol route]
	posts = [
		# the west gate: two guards, each pacing a few steps
		[Vector3(-31.0, 0, -27.6), west, "olive", "ak", [Vector3(-31.0, 0, -27.6), Vector3(-28.0, 0, -27.0)]],
		[Vector3(-31.5, 0, -20.4), west, "blue", "ak", [Vector3(-31.5, 0, -20.4), Vector3(-31.0, 0, -17.0)]],
		# the towers: each man walks round his platform
		[tower_a + Vector3(-0.9, 0, -0.9), west, "gasmask", "svd", _deck(tower_a)],
		[tower_b + Vector3(-0.9, 0, -0.9), west, "olive", "ak", _deck(tower_b)],
		[Vector3(-28, 0, -8), PI * 0.5, "blue", "ak", [Vector3(-28, 0, -8), Vector3(-12, 0, -8), Vector3(-12, 0, -42), Vector3(-24, 0, -42)]],
		[Vector3(-16, 0, -35.5), west, "gasmask", "ak", []],                                 # outer yard
		[Vector3(-14, 0, -24.5), west, "olive", "ak", []],                                   # behind the sandbags
		[Vector3(-3, 0, -28.6), west, "blue", "ak", [Vector3(-3, 0, -28.6), Vector3(-1, 0, -30.5)]],      # the inner gate
		[Vector3(-3, 0, -19.4), west, "gasmask", "ak", [Vector3(-3, 0, -19.4), Vector3(-1, 0, -17.5)]],
		[Vector3(10.6, 0, -8.6), PI, "olive", "ak", []],                                     # outside the command hut
		[hut_c + Vector3(1.5, 0, -1.2), PI * 0.85, "blue", "ak", []],                        # inside it
		[Vector3(16.5, 0, -35.0), west, "gasmask", "ak", []],                                # by the barracks
		[Vector3(21, 3.2, -37.2), PI, "olive", "ak", []],                                    # on its roof
		[Vector3(9.0, 0, -44.6), PI * 0.9, "blue", "ak", []],                                # at the generator
		[tower_c + Vector3(-0.9, 0, -0.9), west, "gasmask", "ak", _deck(tower_c)],          # tower C
		[Vector3(2, 0, -30), -PI * 0.5, "olive", "ak", [Vector3(2, 0, -30), Vector3(28, 0, -30), Vector3(28, 0, -16), Vector3(2, 0, -16)]],
	]
	start_yaw = -PI * 0.5
	return Vector3(-62.6, 0.05, -8.0)


var lights := []      # searchlights: {"n": SpotLight3D, "yaw": centre of its sweep, "ph": phase, "guard": soldier index}
## A searchlight on a tower roof, sweeping the ground outward (facing `yaw`); the soldier at `guard` (index in the
## soldiers) is the one who sees what it lights.
func _searchlight(top: Vector3, yaw: float, guard: int) -> void:
	var head := _block(top + Vector3(0, 2.05, 0), Vector3(0.35, 0.3, 0.45), "dark", "metal", 0.0, false)
	var sl := SpotLight3D.new()
	sl.light_color = Color(0.86, 0.9, 1.0)
	sl.light_energy = 9.0
	sl.spot_range = 70.0
	sl.spot_angle = 9.0
	sl.spot_attenuation = 0.6
	sl.shadow_enabled = false
	main.add_child(sl)
	sl.global_position = top + Vector3(0, 2.0, 0)
	lights.append({"n": sl, "head": head, "yaw": yaw, "ph": randf() * TAU, "guard": guard})


## A lamp on a pole: a warm pool of light.
func _lamp(p: Vector3) -> void:
	_block(p + Vector3(0, 2.0, 0), Vector3(0.1, 4.0, 0.1), "steel", "metal")
	var bulb := _block(p + Vector3(0, 4.0, 0.25), Vector3(0.3, 0.12, 0.5), "dark", "metal", 0.0, false)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1, 0.85, 0.6)
	lm.emission_enabled = true
	lm.emission = Color(1, 0.8, 0.55)
	lm.emission_energy_multiplier = 4.0
	var glow := _block(p + Vector3(0, 3.93, 0.3), Vector3(0.22, 0.03, 0.3), "dark", "metal", 0.0, false)
	glow.get_child(0).material_override = lm
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.58)
	l.light_energy = 2.2
	l.omni_range = 12.0
	l.omni_attenuation = 1.4
	main.add_child(l)
	l.global_position = p + Vector3(0, 3.7, 0.3)


## Sweep the searchlights; a lit player is seen by that tower's man (he looks, then he sees).
func _sweep(dt: float) -> void:
	var pl = main.player
	for L in lights:
		var g = main.enemies[L["guard"]] if L["guard"] < main.enemies.size() else null
		var alive: bool = g != null and not g.dead
		if alive:
			L["ph"] += dt * 0.32
		var sl: SpotLight3D = L["n"]
		var yaw: float = L["yaw"] + sin(L["ph"]) * 0.95
		if alive and g.mode == "combat":
			var to: Vector3 = pl.global_position - sl.global_position
			yaw = lerp_angle(sl.rotation.y, atan2(-to.x, -to.z), min(1.0, dt * 3.0))    # on the player
		sl.rotation = Vector3(-0.19, yaw, 0)
		L["head"].rotation.y = yaw
		if not alive or pl.dead:
			continue
		var d: Vector3 = pl.global_position + Vector3(0, 1.0, 0) - sl.global_position
		var fwd: Vector3 = -sl.global_transform.basis.z
		if d.length() < 50.0 and fwd.dot(d.normalized()) > cos(deg_to_rad(10.0)) and g.mode == "guard":
			# only if the beam really reaches him (not through a wall)
			var q := PhysicsRayQueryParameters3D.create(sl.global_position, pl.global_position + Vector3(0, 1.0, 0))
			q.exclude = [pl.get_rid()]
			q.collision_mask = 1
			var h: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
			if h.is_empty() or h.collider.has_meta("seethrough"):
				g.investigate(pl.global_position)


## A walk round a tower's platform (top: its centre at floor level).
func _deck(top: Vector3) -> Array:
	return [top + Vector3(-0.9, 0, -0.9), top + Vector3(-0.9, 0, 0.9), top + Vector3(0.7, 0, 0.9), top + Vector3(0.7, 0, -0.9)]


# =============== MISSION 2: CITY 2026 (a border city under curfew, at night) ===============
## Map units from the design sheet: 3 px to a metre, the sheet's centre at the origin, north = -z.
func S(x: float, y: float, h := 0.0) -> Vector3:
	return Vector3((x - 500.0) / 3.0, h, (y - 350.0) / 3.0)


var city
## A block of the design sheet (x, y, w, h in px) filled with buildings side by side along its long side; rows of
## two when it is deep. shops: faces with shop fronts; floors: [min, max].
func _block_of(r: Array, shops := [], floors := [4, 7], towers := 0) -> void:
	var a := S(r[0], r[1])
	var b := S(r[0] + r[2], r[1] + r[3])
	var along_x := (b.x - a.x) >= (b.z - a.z)
	var length: float = (b.x - a.x) if along_x else (b.z - a.z)
	var depth: float = (b.z - a.z) if along_x else (b.x - a.x)
	var rows := 2 if depth > 24.0 else 1
	var n_tower := towers
	city.block_tones = [city.rng.randi() % city.PLASTER.size(), city.rng.randi() % city.PLASTER.size()]
	for row in rows:
		var d0: float = depth * row / rows
		var d1: float = depth * (row + 1) / rows
		var s0 := 0.0
		while s0 < length - 0.5:
			var wdt: float = min(length - s0, city.rng.randf_range(10.0, 17.0))
			if length - s0 - wdt < 7.0:
				wdt = length - s0
			var my_shops := []
			for sh in shops:
				if rows == 2 and ((row == 0 and sh in ["s", "e"]) or (row == 1 and sh in ["n", "w"])) and ((along_x and sh in ["n", "s"]) or (not along_x and sh in ["e", "w"])):
					continue
				my_shops.append(sh)
			var q: Array = [a.x + s0, a.z + d0, a.x + s0 + wdt, a.z + d1] if along_x else [a.x + d0, a.z + s0, a.x + d1, a.z + s0 + wdt]
			# sides against the neighbours (along the row, and the other row behind) stay plain
			var first := s0 < 0.1
			var last := wdt >= length - s0 - 0.01
			var blank := []
			if not first:
				blank.append("w" if along_x else "n")
			if not last:
				blank.append("e" if along_x else "s")
			if rows == 2:
				blank.append(("s" if row == 0 else "n") if along_x else ("e" if row == 0 else "w"))
			if n_tower > 0 and wdt > 11.0 and depth / rows > 11.0:
				city.office_tower(q[0] + 0.8, q[1] + 0.8, q[2] - 0.8, q[3] - 0.8, city.rng.randi_range(9, 14))
				n_tower -= 1
			else:
				city.apartment(q[0], q[1], q[2], q[3], city.rng.randi_range(floors[0], floors[1]), my_shops, blank)
			s0 += wdt
	city.commit_kit()
	city.commit(true, city.KIT_GONE)
	city.block_tones = []
	await main.breathe(38)


func _road(r: Array, _col := Color()) -> void:
	var a := S(r[0], r[1])
	var b := S(r[0] + r[2], r[1] + r[3])
	city.face("g_asphalt", Vector3((a.x + b.x) * 0.5, 0.03, (a.z + b.z) * 0.5), Vector3((b.x - a.x) * 0.5, 0, 0), Vector3(0, 0, -(b.z - a.z) * 0.5))


func _car(kind: String, p: Vector3, yaw: float) -> void:
	# parked cars under the curfew: the scanned covered car (Poly Haven, CC0)
	var path := "res://assets/city/%s.glb" % kind
	if kind.begins_with("land_rover"):
		# the old Land Rover (m8mazay, CC-BY 4.0), packed light for phones (its tyres a few centimetres up in the
		# model), painted for where it stands: desert sand, the militia's dark grey in the town, army olive
		path = "res://assets/city/props/land_rover/%s_game.gltf" % kind
		kind = "land_rover"
		p.y -= 0.08
	if kind.begins_with("sedan") or kind.begins_with("suv"):
		path = "res://assets/city/props/covered_car/covered_car_game.gltf"
		kind = "sedan"
	var cb: StaticBody3D = _merged_prop(path, p, yaw, "metal") if kind in ["sedan", "land_rover"] else main._prop(path, p, yaw, Vector3.ZERO, "metal")
	var big := kind.begins_with("bus")
	var size := Vector3(2.5, 3.0, 10.1) if big else (Vector3(1.9, 2.2, 5.1) if kind == "pickup" else Vector3(1.8, 1.45, 4.6))
	if kind == "land_rover":
		size = Vector3(1.55, 2.0, 3.95)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position.y = size.y * 0.5
	cb.add_child(cs)
	cb.set_meta("pierce", "sheet")
	main.extra_cover.append([p, 0.9])


func _m2() -> Vector3:
	title = "CITY 2026"
	briefing = "The relay codes name the man who gives the militia its orders: the Courier. He runs them from an old hotel in " + \
		"the middle of a border city under curfew; only militia patrols are out tonight.\n\nYou start in the dry riverbed south-west " + \
		"of the town. On the market street one shop has its shutter up and its light on: the informant has left you a message " + \
		"on its counter. Blow the transformer at the clock tower square: the streets round the hotel go dark and their alarm " + \
		"loses its power. Kill the Courier in the hotel forecourt, take his laptop, and get out through the back of the hotel " + \
		"to the helicopter in the rail yard.\n\nYou carry a pistol, an AK-47, an M4A1, a knife and three grenades. A sniper watches " + \
		"from the clock tower, another from the water tower by the bus terminal, a third from the hotel roof."
	main.flat_c = Vector2(0, 0)
	main.flat_r = 205.0
	main.area = Rect2(-160, -126, 330, 244)
	main._build_ground()
	main._build_mountains()
	main.apply_night()
	main.photo_sky("res://assets/sky/night.hdr", 0.08, 0.0, 0.0, false)
	# no moon shadows in the town: at night they barely show, and they cost as much as the town itself
	main.sun.shadow_enabled = main.ultra      # (only the HD app pays for them)
	main.extra_cover = []
	city = load("res://scripts/city.gd").new(main, 26)
	# the whole town paved
	var ta := S(0, 0)
	var tb := S(1000, 652)
	city.face("g_worn", Vector3((ta.x + tb.x) * 0.5, 0.012, (ta.z + tb.z) * 0.5), Vector3((tb.x - ta.x) * 0.5, 0, 0), Vector3(0, 0, -(tb.z - ta.z) * 0.5))
	city.commit(false)
	# ---- the town round about: blocks of flats, a few office towers ----
	for r in [[20, 20, 90, 70, 0], [120, 20, 110, 90, 1], [20, 104, 90, 128, 0], [120, 124, 110, 104, 1], [20, 246, 66, 160, 0], [96, 244, 134, 76, 0],
			[96, 332, 134, 74, 0], [250, 76, 130, 90, 1], [392, 76, 64, 90, 0], [250, 178, 100, 62, 0], [362, 178, 94, 62, 0], [468, 76, 90, 164, 1],
			[250, 252, 150, 70, 0], [410, 252, 148, 70, 0]]:
		await _block_of([r[0], r[1], r[2], r[3]], [], [4, 8], r[4])
	# ---- the market street: shuttered shops under their name boards; the informant's shop is open ----
	city.force_open = S(442, 414)
	for r in [[280, 338, 60, 76], [346, 338, 60, 76], [412, 338, 60, 76], [478, 338, 60, 76], [544, 338, 52, 76]]:
		await _block_of(r, ["s"], [4, 6])
	var msg_at := S(442, 414, 1.03)
	if not city.opened_bay.is_empty():
		var ob: Array = city.opened_bay
		msg_at = ob[0] - ob[2] * 0.45 + ob[1] * (ob[3] * 0.15) + Vector3(0, 1.03, 0)
	var msg := _block(msg_at, Vector3(0.3, 0.05, 0.22), "white", "wood", 0.4, false)
	msg.set_meta("label", "TAKE MESSAGE")
	msg.set_meta("obj", 0)
	items.append(msg)
	for r in [[280, 448, 70, 72], [356, 448, 70, 72], [432, 448, 80, 72], [518, 448, 78, 72]]:
		await _block_of(r, ["n"], [4, 6])
	for r in [[290, 540, 92, 82], [392, 540, 100, 92], [502, 530, 94, 102]]:
		await _block_of(r, [], [3, 5])
	_avenue(S(261, 700), S(261, 431), 26.0 / 3.0)
	_avenue(S(248, 431), S(608, 431), 34.0 / 3.0)          # pavements up to the shop fronts
	for i in 7:
		var x := 285 + i * 50
		city.led_lamp(S(x, 418 if i % 2 == 0 else 444), Vector3(0, 0, 1) if i % 2 == 0 else Vector3(0, 0, -1))
		_planter(S(x + 25, 416.5 if i % 2 == 0 else 445.5, 0.165), 0.0)
	for i in 4:
		city.led_lamp(S(250 if i % 2 == 0 else 272, 470 + i * 55), Vector3(1, 0, 0) if i % 2 == 0 else Vector3(-1, 0, 0))
	city.shelter(S(420, 446.5), PI)
	city.crossing(S(261, 437), Vector3(1, 0, 0), 26.0 / 3.0, 3.0)
	city.commit()
	_car("sedan_white", S(312, 439), PI * 0.5)
	_car("suv_black", S(352, 439), PI * 0.5)
	_car("car_burnt", S(468, 426), PI * 0.5 + 0.25)
	_car("sedan_silver", S(520, 424), -PI * 0.5)
	_car("sedan_red", S(395, 424), -PI * 0.5)
	_car("suv_white", S(575, 439), PI * 0.5)
	# ---- the clock tower square: an old tower kept among the new, a video wall, trees ----
	var a := S(600, 340)
	var b := S(772, 512)
	city.box("g_pavers", Vector3((a.x + b.x) * 0.5, 0.04, (a.z + b.z) * 0.5), Vector3(b.x - a.x, 0.06, b.z - a.z))
	city.step_collider(Vector3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5), Vector3(b.x - a.x, 0.07, b.z - a.z))
	city.commit(false)
	for r in [[610, 522, 80, 70], [700, 522, 90, 70]]:
		await _block_of(r, ["n"], [5, 7])
	for r in [[786, 290, 92, 100], [786, 402, 92, 110]]:
		await _block_of(r, ["w"], [5, 8])
	await _block_of([890, 290, 96, 222], [], [6, 9], 2)
	_clock_tower(S(686, 426))
	city.cyl("trim", S(632, 382), 3.2, 0.6, 24, Color(0.75, 0.74, 0.72))
	city.cyl("glass", S(632, 382, 0.45), 2.9, 0.02, 24)
	city.cyl("trim", S(632, 382), 0.5, 1.6, 10, Color(0.75, 0.74, 0.72))
	city.pool(S(632, 382), Color(0.15, 0.25, 0.35, 1), 3.5)
	for c in [[612, 352], [760, 352], [612, 500], [760, 500], [686, 352], [612, 426]]:
		_planter(S(c[0], c[1]), 0.0)
	for c in [[604, 344, 1, 1], [768, 344, -1, 1], [604, 508, 1, -1], [768, 508, -1, -1]]:
		city.led_lamp(S(c[0], c[1]), Vector3(c[2], 0, c[3]).normalized())
	city.traffic_light(S(598, 422), Vector3(-1, 0, 0), true)
	city.traffic_light(S(598, 440), Vector3(-1, 0, 0), false)
	var tp := S(751, 487)
	city.box("g_kerb", tp + Vector3(0, 0.15, 0), Vector3(4, 0.3, 4))
	city.step_collider(tp, Vector3(4, 0.3, 4))
	city.commit()
	_transformer(tp + Vector3(0, 0.3, 0), 1)
	city.screen(S(786, 360, 14.0), Vector3(-1, 0, 0), 16.0, 9.0, city.ad_image(1))
	city.screen(S(650, 522, 13.0), Vector3(0, 0, -1), 12.0, 6.75, city.ad_image(2))
	_car("bus_burnt", S(669, 365), -0.25 + PI * 0.5)
	_car("sedan_grey", S(720, 470), PI * 0.5 + 0.1)
	_car("car_burnt", S(735, 410), 1.1)
	_sandbags(S(646, 466), 4)
	_sandbags(S(646, 466) + Vector3(-1.5, 0, -1.2), 2)
	for k in 4:
		_barrier(S(604 + k * 8, 520), 0.0)
	# ---- the residential lanes: blocks of flats close together ----
	for r in [[566, 270, 96, 62], [694, 270, 60, 62], [566, 200, 66, 40], [694, 200, 58, 40], [566, 72, 66, 118], [662, 72, 90, 118]]:
		await _block_of(r, [], [4, 6])
	for r in [[670, 196, 15, 146], [566, 248, 206, 13], [640, 58, 13, 140]]:
		_road(r, Color(0.3, 0.3, 0.31))
	city.led_lamp(S(668, 258), Vector3(1, 0, 0))
	city.led_lamp(S(644, 150), Vector3(1, 0, 0))
	city.led_lamp(S(686, 300), Vector3(-1, 0, 0))
	city.rubble(S(676, 300), 1.0)
	city.commit()
	_car("sedan_black", S(610, 254), 0.0 + PI * 0.5)
	_car("suv_grey", S(677, 230), 0.0)
	# ---- the hotel tower: a walled forecourt, its gate, ten storeys and its name in lights ----
	var ha := S(800, 70)
	var hb := S(986, 244)
	for wseg in [[Vector2(ha.x, hb.z), Vector2(S(845, 0).x, hb.z)], [Vector2(S(875, 0).x, hb.z), Vector2(hb.x, hb.z)],
			[Vector2(ha.x, ha.z), Vector2(S(896, 0).x, ha.z)], [Vector2(S(911, 0).x, ha.z), Vector2(hb.x, ha.z)],
			[Vector2(ha.x, ha.z), Vector2(ha.x, hb.z)], [Vector2(hb.x, ha.z), Vector2(hb.x, hb.z)]]:
		_wall(wseg[0], wseg[1], 2.6, 0.35, "cwall")
	var h0 := S(818, 84)
	var h1 := S(968, 142)
	city.lit_share = 0.45
	city.apartment(h0.x, h0.z, h1.x, h1.z, 10, [], [], {"tone": 6, "wins": ["centered_double"], "row": 2})
	city.lit_share = 0.3
	var w0 := S(818, 142)
	var w1 := S(862, 188)
	city.apartment(w0.x, w0.z, w1.x, w1.z, 3, ["s", "e"])
	city.commit_kit()
	_hotel_sign(Vector3((h0.x + h1.x) * 0.5, 10 * 3.0 + 1.7, h1.z - 0.5))
	_avenue(S(760, 263), S(1000, 263), 26.0 / 3.0)
	city.led_lamp(S(840, 250), Vector3(0, 0, 1))
	city.led_lamp(S(900, 250), Vector3(0, 0, 1))
	city.led_lamp(S(960, 250), Vector3(0, 0, 1))
	for x in [815, 835, 955, 975]:
		_planter(S(x, 236), 0.0)
	for k in 3:
		_barrier(S(850 + k * 8, 252), 0.0)
	city.commit()
	_courier_post(S(893, 158))
	_car("pickup", S(917, 204), PI * 0.6)
	_car("land_rover_night", S(885, 218), PI * 0.45)
	_car("suv_black", S(842, 210), PI * 0.5)
	# ---- the bus terminal, the checkpoint, the water tower ----
	var da := S(112, 468)
	var db := S(236, 610)
	for wseg in [[Vector2(da.x, da.z), Vector2(db.x, da.z)], [Vector2(da.x, db.z), Vector2(db.x, db.z)], [Vector2(da.x, da.z), Vector2(da.x, db.z)],
			[Vector2(db.x, da.z), Vector2(db.x, S(0, 520).z)], [Vector2(db.x, S(0, 560).z), Vector2(db.x, db.z)]]:
		_wall(wseg[0], wseg[1], 2.0, 0.3, "cwall")
	# the terminal canopy: a long flat roof on slim columns, lit underneath
	var ca := S(118, 520)
	var cb := S(230, 600)
	city.box("frame", Vector3((ca.x + cb.x) * 0.5, 5.2, (ca.z + cb.z) * 0.5), Vector3(cb.x - ca.x, 0.4, cb.z - ca.z), 0.0, Color(0.85, 0.85, 0.85))
	city.box("led", Vector3((ca.x + cb.x) * 0.5, 4.98, (ca.z + cb.z) * 0.5), Vector3(cb.x - ca.x - 2.0, 0.02, 0.3), 0.0, Color(0.9, 0.95, 1.0))
	for px in [ca.x + 1.0, (ca.x + cb.x) * 0.5, cb.x - 1.0]:
		for pz in [ca.z + 1.0, cb.z - 1.0]:
			city.cyl("frame", Vector3(px, 0, pz), 0.18, 5.0, 10, Color(0.8, 0.8, 0.8))
	city.pool(Vector3((ca.x + cb.x) * 0.5, 0, (ca.z + cb.z) * 0.5), Color(0.22, 0.25, 0.3, 1), 14.0)
	var tl := OmniLight3D.new()
	tl.light_color = Color(0.88, 0.93, 1.0)
	tl.light_energy = 3.0
	tl.omni_range = 22.0
	main.add_child(tl)
	tl.global_position = Vector3((ca.x + cb.x) * 0.5, 4.6, (ca.z + cb.z) * 0.5)
	var wt := S(214, 492)
	for dx in [-1.2, 1.2]:
		for dz in [-1.2, 1.2]:
			city.box("steel", wt + Vector3(dx, 5.0, dz), Vector3(0.15, 10.0, 0.15), 0.0, Color(0.55, 0.55, 0.55))
	city.box("steel", wt + Vector3(0, 10.0, 0), Vector3(3.2, 0.2, 3.2), 0.0, Color(0.55, 0.55, 0.55))
	city.cyl("dark", wt + Vector3(0, 10.1, 0), 1.3, 2.6, 16, Color(0.85, 0.85, 0.82))
	city.collider(wt + Vector3(0, 5.0, 0), Vector3(2.6, 10.0, 2.6), 0.0, "metal")
	city.glow(wt + Vector3(0, 12.9, 0), Color(1, 0.1, 0.05, 0.9), 0.9)
	for k in 4:
		_barrier(S(250, 500) + Vector3(k * 1.7 - 2.5, 0, 0), 0.0)
	city.commit()
	for k in 4:
		_car("sedan_white", S(130 + k * 9, 600), 0.05 * k)
	_car("bus_burnt", S(206, 565), 0.05)
	_car("pickup", S(286, 520), PI)
	_sandbags(S(282, 504), 3)
	# ---- the start: the dry riverbed outside the town ----
	_car("car_burnt", S(108, 606), 0.5)
	city.rubble(S(80, 622), 1.5)
	city.commit()
	# ---- the rail yard and the landing zone ----
	_railway()
	main.scatter(250, 100, 200.0)
	main._restore_breakables()
	# the soldiers: [position, facing (0 faces north, PI/2 west), character, gun, patrol route]
	posts = []
	var kinds := ["olive", "blue", "gasmask"]
	for q in [[250, 512], [272, 512], [168, 600], [330, 428], [342, 436], [440, 436], [560, 452], [634, 478], [650, 482], [726, 374], [616, 380],
			[752, 452], [620, 255], [706, 252], [677, 214], [646, 120], [760, 262], [852, 268], [878, 268], [876, 176], [926, 170], [950, 230],
			[560, 34], [800, 30]]:
		posts.append([_outside(S(q[0], q[1])), city.rng.randf() * TAU, kinds[posts.size() % 3], "ak", []])
	# patrols: along the market street, round the clock tower square, through the rail yard
	posts.append([S(300, 431), -PI * 0.5, "blue", "ak", [S(300, 431), S(580, 431)]])
	posts.append([S(620, 360), PI, "olive", "ak", [S(620, 360), S(760, 360), S(760, 500), S(620, 500)]])
	posts.append([S(620, 32), -PI * 0.5, "gasmask", "ak", [S(620, 32), S(900, 32)]])
	# snipers: the clock tower, the water tower by the terminal, the hotel roof
	posts.append([S(686, 426, 15.1) + Vector3(2.2, 0, 2.2), PI * 0.25, "gasmask", "svd", []])
	posts.append([S(214, 492, 10.1) + Vector3(1.0, 0, 1.0), PI * 0.3, "olive", "svd", []])
	posts.append([S(826, 136, 30.1), PI * 0.75, "gasmask", "svd", []])
	# the Courier at his table in the hotel forecourt, a bodyguard either side
	target_post = posts.size()
	posts.append([S(893, 163), PI, "blue", "ak", []])
	posts.append([S(884, 166), PI * 0.9, "olive", "ak", []])
	posts.append([S(902, 166), PI * 1.1, "gasmask", "ak", []])
	target_obj = 2
	reinf_spots = [S(992, 258), S(992, 266), S(986, 258), S(986, 266)]
	alarm_text = "The militia knows you are in the town. More soldiers are coming."
	power_zone = Rect2(S(560, 0).x, S(0, 0).z, 200.0, (S(0, 330).z - S(0, 0).z))
	lz = S(720, -22)
	objectives = [
		{"text": "Take the informant's message from the open shop on the market street", "done": false, "pos": msg_at},
		{"text": "Blow the transformer at the clock tower square", "done": false, "pos": tp + Vector3(0, 1.5, 0)},
		{"text": "Kill the Courier in the hotel forecourt", "done": false, "pos": S(893, 163, 1.6)},
		{"text": "Take the Courier's laptop", "done": false, "pos": S(893, 160, 1.0), "needs": [2]},
		{"text": "Get out through the back of the hotel to the helicopter in the rail yard", "done": false, "pos": lz + Vector3(0, 1, 0), "needs": [0, 1, 2, 3], "lz": true}]
	start_yaw = -PI * 0.25
	return S(96, 616, 0.05)


## p moved out of any building it falls in: to the nearest spot just outside a wall that is not inside another one.
func _outside(p: Vector3) -> Vector3:
	var inside := func(q: Vector3) -> bool:
		for r in city.footprints:
			if r.grow(0.8).has_point(Vector2(q.x, q.z)):
				return true
		return false
	if not inside.call(p):
		return p
	var best := p
	var best_d := INF
	for r in city.footprints:
		var g: Rect2 = r.grow(1.0)
		if not g.has_point(Vector2(p.x, p.z)):
			continue
		for q in [Vector3(g.position.x, p.y, p.z), Vector3(g.end.x, p.y, p.z), Vector3(p.x, p.y, g.position.y), Vector3(p.x, p.y, g.end.y)]:
			if not inside.call(q) and q.distance_to(p) < best_d:
				best = q
				best_d = q.distance_to(p)
	return best


## The transformer at the clock tower square: a pad-mounted unit with cooling fins and insulators, on a concrete
## plinth. It powers the streets round the hotel; destroyed, they go dark and its alarm is dead.
func _transformer(c: Vector3, obj: int) -> StaticBody3D:
	var g := StaticBody3D.new()
	g.set_meta("surf", "metal")
	g.set_meta("kind", "machine")
	g.set_meta("hp", 650.0)
	g.set_meta("obj", obj)
	g.set_meta("power", true)
	var parts := [[Vector3(0, 0.95, 0), Vector3(1.7, 1.9, 1.1), "steel"], [Vector3(0, 1.95, 0), Vector3(1.8, 0.1, 1.2), "steel"],
		[Vector3(0, 0.05, 0), Vector3(1.9, 0.1, 1.3), "dark"], [Vector3(0.0, 1.0, 0.56), Vector3(0.5, 0.4, 0.02), "white"]]
	for k in 7:
		parts.append([Vector3(-0.75 + k * 0.25, 0.9, -0.62), Vector3(0.03, 1.5, 0.16), "steel"])
		parts.append([Vector3(-0.75 + k * 0.25, 0.9, 0.62), Vector3(0.03, 1.5, 0.16), "steel"])
	for k in 3:
		parts.append([Vector3(-0.5 + k * 0.5, 2.25, 0), Vector3(0.14, 0.5, 0.14), "white"])
		parts.append([Vector3(-0.5 + k * 0.5, 2.55, 0), Vector3(0.04, 0.25, 0.04), "dark"])
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[1]
		mi.mesh = bm
		mi.material_override = _m(pt[2])
		mi.position = pt[0]
		g.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.8, 2.0, 1.3)
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	g.add_child(cs)
	main.add_child(g)
	g.global_position = c
	main.machines.append(g)
	return g


## The Courier's table in the hotel forecourt (c: the table), under an awning and a bare bulb: a laptop on it
## (the objective's item), chairs, a radio.
func _courier_post(c: Vector3) -> void:
	_block(c + Vector3(0, 0.38, 0), Vector3(1.6, 0.05, 0.8), "wood", "wood")
	for sx in [-0.7, 0.7]:
		for sz in [-0.33, 0.33]:
			_block(c + Vector3(sx, 0.18, sz), Vector3(0.05, 0.36, 0.05), "steel", "metal", 0.0, false)
	for cx in [-0.5, 0.5]:
		_block(c + Vector3(cx, 0.22, 0.75), Vector3(0.45, 0.45, 0.45), "steel", "metal")
	_block(c + Vector3(0.55, 0.47, -0.1), Vector3(0.22, 0.12, 0.1), "dark", "metal", 0.0, false)
	var lap := _block(c + Vector3(-0.2, 0.42, 0.05), Vector3(0.34, 0.03, 0.24), "dark", "metal", 0.0, false)
	lap.set_meta("label", "TAKE LAPTOP")
	lap.set_meta("obj", 3)
	items.append(lap)
	var scr := _block(c + Vector3(-0.2, 0.53, -0.07), Vector3(0.34, 0.22, 0.02), "glass", "metal", 0.0, false)
	scr.reparent(lap)
	city.box("frame", c + Vector3(0, 2.6, 0.3), Vector3(4.0, 0.08, 3.0), 0.0, Color(0.3, 0.32, 0.3))
	for sx in [-1.9, 1.9]:
		for sz in [-1.1, 1.7]:
			city.cyl("frame", c + Vector3(sx, 0, sz), 0.05, 2.6, 6, Color(0.3, 0.3, 0.3))
	city.commit()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.6)
	l.light_energy = 2.5
	l.omni_range = 9.0
	main.add_child(l)
	l.global_position = c + Vector3(0, 2.4, 0.2)
	city.glow(c + Vector3(0, 2.45, 0.2), Color(1.0, 0.8, 0.55, 0.8), 0.7)


## A city street from a to b (straight, along x or z): asphalt, kerbed pavements both sides, a dashed centre line.
func _avenue(a: Vector3, b: Vector3, width: float) -> void:
	var d := b - a
	var L := d.length()
	var u := d / L
	var side := Vector3(u.z, 0, -u.x)
	var mid := (a + b) * 0.5
	var yaw := atan2(u.x, u.z)
	city.face("g_asphalt", mid + Vector3(0, 0.03, 0), u * (L * 0.5), side * ((width - 3.0) * 0.5))
	for sg in [-1.0, 1.0]:
		# pavement of square pavers behind a kerb stone
		city.box("g_pavers", mid + side * sg * (width * 0.5 - 0.7) + Vector3(0, 0.08, 0), Vector3(1.4, 0.16, L), yaw)
		city.box("g_kerb", mid + side * sg * (width * 0.5 - 1.5) + Vector3(0, 0.09, 0), Vector3(0.2, 0.18, L), yaw)
		city.step_collider(mid + side * sg * (width * 0.5 - 0.8), Vector3(1.6, 0.165, L), yaw)
	city.dashes(a, b)


## The clock tower: a sandstone shaft of the scanned kit (small windows, a door each side, moulded crown), the clock
## stage on its roof with a lit face on every side, a pyramid roof; the sniper's parapet round it.
func _clock_tower(c: Vector3) -> void:
	city.lit_share = 0.0
	city.ac_share = 0.0
	city.apartment(c.x - 3.0, c.z - 3.0, c.x + 3.0, c.z + 3.0, 5, [], [], {"tone": 7, "wins": ["centered_small"], "row": 3, "bare_roof": true})
	city.commit_kit()
	city.lit_share = 0.3
	city.ac_share = 0.06
	var top := 15.0
	city.box("kq_plaster7", c + Vector3(0, top + 1.9, 0), Vector3(3.6, 3.8, 3.6))
	for y in [top + 0.1, top + 3.85]:
		city.box("g_kerb", c + Vector3(0, y, 0), Vector3(3.9, 0.22, 3.9))
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = _clock_face()
	cm.emission_enabled = true
	cm.emission_texture = cm.albedo_texture
	cm.emission_energy_multiplier = 0.7
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	for k in 4:
		var n := Vector3(sin(k * PI * 0.5), 0, cos(k * PI * 0.5))
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.6, 2.6)
		q.mesh = qm
		q.material_override = cm
		main.add_child(q)
		q.global_position = c + Vector3(0, top + 2.0, 0) + n * 1.82
		q.look_at(q.global_position - n, Vector3.UP)
	# pyramid roof
	var st: SurfaceTool = city._st("dark")
	var apex := c + Vector3(0, top + 6.6, 0)
	var cs := [c + Vector3(-2.1, top + 3.95, -2.1), c + Vector3(2.1, top + 3.95, -2.1), c + Vector3(2.1, top + 3.95, 2.1), c + Vector3(-2.1, top + 3.95, 2.1)]
	for i in 4:
		var p0: Vector3 = cs[i]
		var p1: Vector3 = cs[(i + 1) % 4]
		var nn := (p1 - p0).cross(apex - p0).normalized()
		if nn.dot(p0 - c) < 0:
			nn = -nn
		for v in [p0, apex, p1]:
			st.set_color(Color(0.22, 0.2, 0.19))
			st.set_normal(nn)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v)
	city.collider(c + Vector3(0, top + 1.9, 0), Vector3(3.6, 3.8, 3.6))


## A clock face: cream dial, a dark ring, hour marks, hands at ten past ten (transparent round it).
func _clock_face() -> ImageTexture:
	var N := 128
	var img := Image.create(N, N, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ctr := Vector2(N * 0.5, N * 0.5)
	for y in N:
		for x in N:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(ctr)
			if d < N * 0.5 - 1:
				img.set_pixel(x, y, Color(0.93, 0.9, 0.8) if d < N * 0.44 else Color(0.18, 0.16, 0.14))
	for hr in 12:
		var a := TAU * hr / 12.0
		var dir := Vector2(sin(a), -cos(a))
		for t in range(int(N * 0.34), int(N * 0.42)):
			var p := ctr + dir * t
			img.fill_rect(Rect2i(int(p.x) - 1, int(p.y) - 1, 3 if hr % 3 == 0 else 2, 3 if hr % 3 == 0 else 2), Color(0.1, 0.1, 0.1))
	for hand in [[TAU * (10.17 / 12.0), N * 0.24, 3], [TAU * (10.0 / 60.0), N * 0.36, 2]]:
		var dir2 := Vector2(sin(hand[0]), -cos(hand[0]))
		for t in int(hand[1]):
			var p2 := ctr + dir2 * t
			img.fill_rect(Rect2i(int(p2.x) - 1, int(p2.y) - 1, hand[2], hand[2]), Color(0.08, 0.08, 0.08))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## HOTEL in tall lit letters on the roof edge, facing south.
func _hotel_sign(c: Vector3) -> void:
	var strokes := {"H": [[0, 0, 0.12, 1], [0.48, 0, 0.12, 1], [0, 0.44, 0.6, 0.12]],
		"O": [[0, 0, 0.12, 1], [0.48, 0, 0.12, 1], [0, 0, 0.6, 0.12], [0, 0.88, 0.6, 0.12]],
		"T": [[0.24, 0, 0.12, 1], [0, 0.88, 0.6, 0.12]],
		"E": [[0, 0, 0.12, 1], [0, 0, 0.6, 0.12], [0, 0.44, 0.48, 0.12], [0, 0.88, 0.6, 0.12]],
		"L": [[0, 0, 0.12, 1], [0, 0, 0.6, 0.12]]}
	var size := 1.4
	var x := c.x - 2.5 * 0.85 * size
	for ch in "HOTEL":
		for s_ in strokes[ch]:
			city.box("sign", Vector3(x + (s_[0] + s_[2] * 0.5) * size, c.y + (s_[1] + s_[3] * 0.5) * size, c.z), Vector3(s_[2] * size, s_[3] * size, 0.12), 0.0, Color(0.95, 0.35, 0.2) if ch != "T" else Color(0.4, 0.15, 0.1))
		x += 0.85 * size
	city.box("steel", Vector3(c.x, c.y - 0.2, c.z + 0.1), Vector3(5.0 * 0.85 * size, 0.08, 0.08), 0.0, Color(0.3, 0.3, 0.3))


## Two tracks of rails on sleepers across the north, goods wagons (containers on flat cars), the helicopter pad.
func _railway() -> void:
	for tz in [S(0, 20).z, S(0, 44).z]:
		for rx in [-0.72, 0.72]:
			city.box("steel", Vector3(S(735, 0).x, 0.12, tz + rx), Vector3(S(1000, 0).x - S(470, 0).x, 0.12, 0.08), 0.0, Color(0.45, 0.42, 0.38))
		var x := S(470, 0).x
		while x < S(1000, 0).x:
			city.box("wood", Vector3(x, 0.05, tz), Vector3(0.24, 0.1, 2.5), 0.0, Color(0.3, 0.25, 0.2))
			x += 0.65
		city.box("trim", Vector3(S(735, 0).x, 0.02, tz), Vector3(S(1000, 0).x - S(470, 0).x, 0.04, 3.4), 0.0, Color(0.42, 0.4, 0.37))
	# the helicopter pad
	var lzp := S(720, -22)
	city.box("trim", lzp + Vector3(0, 0.03, 0), Vector3(14, 0.06, 14), 0.0, Color(0.5, 0.5, 0.48))
	for s_ in [[Vector3(-1.6, 0.07, 0), Vector3(0.5, 0.02, 4.0)], [Vector3(1.6, 0.07, 0), Vector3(0.5, 0.02, 4.0)], [Vector3(0, 0.07, 0), Vector3(3.2, 0.02, 0.5)]]:
		city.box("cloth", lzp + s_[0], s_[1], 0.0, Color(0.9, 0.9, 0.85))
	city.led_lamp(S(700, 60), Vector3(0, 0, -1))
	city.led_lamp(S(900, 60), Vector3(0, 0, -1))
	city.commit()
	var colors := ["red", "blue", "green"]
	var i := 0
	for wg in [[S(532, 20), 0], [S(602, 20), 0], [S(825, 44), 0], [S(898, 44), 0], [S(980, 20), 0]]:
		var p: Vector3 = wg[0]
		_block(p + Vector3(0, 0.75, 0), Vector3(13.0, 0.3, 2.6), "dark", "metal", 0.0, true)
		for bx in [-4.5, 4.5]:
			_block(p + Vector3(bx, 0.35, 0), Vector3(2.2, 0.5, 2.0), "dark", "metal", 0.0, false)
		var cb: StaticBody3D = main._prop("res://assets/env/container_%s.glb" % colors[i % 3], p + Vector3(-3.05, 0.9, 0), PI * 0.5, Vector3(2.44, 2.59, 6.06), "metal")
		cb.set_meta("pierce", "sheet")
		var cb2: StaticBody3D = main._prop("res://assets/env/container_%s.glb" % colors[(i + 1) % 3], p + Vector3(3.05, 0.9, 0), PI * 0.5, Vector3(2.44, 2.59, 6.06), "metal")
		cb2.set_meta("pierce", "sheet")
		i += 1


func _sandbags(c: Vector3, n_bags: int) -> void:
	var bag_scene: Node3D = load("res://assets/env/sandbag.glb").instantiate()
	var bag_mesh: Mesh = bag_scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
	bag_scene.free()
	var w := n_bags * 0.55
	var xs := []
	for layer in 5:
		var off := 0.0 if layer % 2 == 0 else 0.275
		var x := -w * 0.5 + off
		while x < w * 0.5 - 0.2:
			xs.append(Transform3D(Basis(Vector3.UP, PI * 0.5 + randf_range(-0.06, 0.06)), Vector3(x + 0.27, layer * 0.15, 0)))
			x += 0.55
	# the whole wall in one draw
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bag_mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	main.add_child(mmi)
	mmi.global_position = c
	var sb := _block(c + Vector3(0, 0.4, 0), Vector3(w, 0.8, 0.55), "plaster", "sandbag")
	sb.get_child(0).visible = false
	main.extra_cover.append([c, 0.3])


## A concrete planter of shrubs on the pavement (Poly Haven planter box, CC0).
func _planter(p: Vector3, yaw: float) -> void:
	main._prop("res://assets/city/props/planter_box_01/planter_box_01_game.gltf", p, yaw, Vector3(0.9, 0.42, 0.42), "concrete").scale = Vector3(1.6, 1.6, 1.6)


## A concrete road barrier (Poly Haven, CC0), solid cover.
func _barrier(p: Vector3, yaw: float) -> void:
	var b: StaticBody3D = main._prop("res://assets/city/props/concrete_road_barrier/concrete_road_barrier_game.gltf", p, yaw, Vector3(1.55, 0.82, 0.6), "concrete")
	b.scale = Vector3(1.0, 1.0, 1.0)
	main.extra_cover.append([p, 0.6])


var merged := {}
## A prop scene drawn as one mesh (its parts merged by material), as a static body at p turned by yaw.
func _merged_prop(path: String, p: Vector3, yaw: float, surf: String) -> StaticBody3D:
	if not merged.has(path):
		var root: Node3D = load(path).instantiate()
		var sts := {}
		var mats_ := {}
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = mi.transform
			var par: Node = mi.get_parent()
			while par != root and par is Node3D:
				xf = par.transform * xf
				par = par.get_parent()
			for k in mi.mesh.get_surface_count():
				var mat: Material = mi.mesh.surface_get_material(k)
				if not sts.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					sts[mat] = st
				sts[mat].append_from(mi.mesh, k, xf)
		var am := ArrayMesh.new()
		for mat in sts:
			sts[mat].commit(am)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		root.free()
		merged[path] = am
	var b := StaticBody3D.new()
	b.position = p
	b.rotation.y = yaw
	b.set_meta("surf", surf)
	var m := MeshInstance3D.new()
	m.mesh = merged[path]
	b.add_child(m)
	main.add_child(b)
	return b


# =============== MISSION 3: DEAD CITY (a modern city after the fighting, by day) ===============
var dead
func _m3() -> Vector3:
	title = "DEAD CITY"
	briefing = "The Courier's laptop names the militia's headquarters: an office block behind a wall in the north-east of " + \
		"a city the war has emptied. Its people are gone; its streets belong to the militia now.\n\nYou come in from the " + \
		"south. The avenue ahead is blocked and watched, and a checkpoint holds the crossroads in the middle of the city. " + \
		"The car park under the mall plaza on your left is a way past it out of sight.\n\nA wounded officer was treated " + \
		"in the city hospital and left his codebook in the operating room: take it. In the headquarters, destroy the " + \
		"radio set in the signals room upstairs and take the war plans from the commander's office beside it. Then get " + \
		"to the pickup point among the containers in the industrial yard, south-east of the crossroads.\n\nYou carry a pistol, an AK-47, " + \
		"an M4A1, a knife and three grenades. Snipers watch from the headquarters' tower and a warehouse roof."
	main.flat_c = Vector2(0, 0)
	main.flat_r = 230.0
	main.area = Rect2(-146, -146, 292, 292)
	dead = load("res://scripts/deadcity.gd").new()
	main.ground_collide = false
	main.ground_holes.clear()
	for h in dead.HOLES:
		main.ground_holes.append(h)
	main.snow = true
	main.snow_night = true
	main._build_ground()
	main._build_mountains()
	main.apply_snow_night()
	main.extra_cover = []
	city = load("res://scripts/city.gd").new(main, 33)
	dead.main = main
	dead.mis = self
	dead.city = city
	dead.name = "DeadCity"
	main.add_child(dead)
	var spawn: Vector3 = await dead.build()
	dead.snow_ground()
	main._restore_breakables()
	posts = dead.posts
	far_cull = 80.0
	lz = Vector3(26, 0, 60)
	var book := _block(dead.codes_at, Vector3(0.22, 0.04, 0.3), "red", "wood", 0.4, false)
	book.set_meta("label", "TAKE CODEBOOK")
	book.set_meta("obj", 0)
	items.append(book)
	dead.radio_set.set_meta("obj", 1)
	var plans := _block(dead.plans_at, Vector3(0.34, 0.03, 0.26), "wood", "wood", -0.3, false)
	plans.set_meta("label", "TAKE PLANS")
	plans.set_meta("obj", 2)
	items.append(plans)
	objectives = [
		{"text": "Take the codebook from the hospital's operating room", "done": false, "pos": dead.codes_at},
		{"text": "Destroy the radio set in the headquarters", "done": false, "pos": dead.radio_set.global_position + Vector3(0, 1, 0)},
		{"text": "Take the war plans from the commander's office", "done": false, "pos": dead.plans_at},
		{"text": "Reach the pickup point in the industrial yard", "done": false, "pos": lz + Vector3(0, 1, 0), "needs": [0, 1, 2], "lz": true}]
	reinf_spots = [Vector3(39, 0, -6), Vector3(43, 0, -6), Vector3(39, 0, -3), Vector3(43, 0, -3)]
	alarm_text = "The headquarters knows you are in the city. More soldiers are coming."
	siren_pos = Vector3(42, 9.5, -50)
	start_yaw = 0.0
	return spawn


# =============== MISSION 4: IRON TIDE (a freighter at anchor, boarded from the sea at night) ===============
var ship
func _m4() -> Vector3:
	title = "IRON TIDE"
	briefing = "The war plans name a ship: the freighter Northern Gannet, running down the coast tonight with the " + \
		"militia's rockets in her containers. Two patrol launches keep station off her sides, sweeping her decks with " + \
		"their lights, and men on jet skis come racing up from astern in ones, twos and threes.\n\nYour boat has come up under her side and made fast at the foot " + \
		"of her ladder. Take the cargo manifest from the bridge, high at her stern: it says which containers carry the " + \
		"rockets. Destroy the two marked containers. Then get back down the ladder to your boat.\n\nYou carry a pistol, " + \
		"an AK-47, an M4A1, a knife and three grenades. Keep out of the launches' lights. Once the ship knows you are " + \
		"aboard, the men riding behind will fire on you whenever they see you: the jet skis can be sunk. Do not go over the side."
	main.flat_c = Vector2(0, 0)
	main.flat_r = 900.0
	main.area = Rect2(-60, -30, 120, 60)
	main.sea = true
	main.ground_collide = false
	main.ground_holes.clear()
	main.perch_y = 9.0
	main._build_ground()
	main.extra_cover = []
	city = load("res://scripts/city.gd").new(main, 44)
	ship = load("res://scripts/ship.gd").new()
	ship.main = main
	ship.mis = self
	ship.city = city
	ship.name = "Ship"
	main.add_child(ship)
	ship.night_look()
	var spawn: Vector3 = await ship.build()
	posts = ship.posts
	far_cull = 120.0
	lz = ship.boat_at
	var book := _block(ship.manifest_at, Vector3(0.24, 0.03, 0.32), "red", "wood", 0.3, false)
	book.set_meta("label", "TAKE MANIFEST")
	book.set_meta("obj", 0)
	items.append(book)
	objectives = [
		{"text": "Take the cargo manifest from the bridge", "done": false, "pos": ship.manifest_at},
		{"text": "Destroy the marked container on the fore deck", "done": false, "pos": ship.marked[0].global_position + Vector3(0, 1.5, 0)},
		{"text": "Destroy the marked container by the deckhouse", "done": false, "pos": ship.marked[1].global_position + Vector3(0, 1.5, 0)},
		{"text": "Get back down the ladder to your boat", "done": false, "pos": lz + Vector3(0, 1, 0), "needs": [0, 1, 2], "lz": true}]
	reinf_spots = [Vector3(-44, 5.0, 0), Vector3(-44, 5.0, 2), Vector3(29, 5.0, 0), Vector3(29, 5.0, 2)]
	alarm_text = "The ship knows you are aboard. Every man is turning out."
	siren_pos = Vector3(-33, 17, 0)
	start_yaw = PI * 0.5
	return spawn
