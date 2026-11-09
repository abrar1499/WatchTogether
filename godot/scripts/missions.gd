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
var reinf_t := -1.0
var siren: AudioStreamPlayer3D
var siren_pos := Vector3.ZERO
var over := false
var start_t := 0.0
var t := 0.0
var mats := {}
var start_yaw := 0.0


## Build mission `num` into main; returns where the player starts.
func build(num: int) -> Vector3:
	n = num
	match num:
		1:
			return _m1()
	return Vector3(0, 0.05, 6)


func ready_player() -> void:
	var p = main.player
	p.infinite = false
	for w in p.weapons:
		w["own"] = w["gun"] in ["pistol", "ak"]
	p.weapons[0]["mag"] = 12
	p.weapons[0]["res"] = 36
	p.weapons[2]["mag"] = 30
	p.weapons[2]["res"] = 90
	p.wi = 2
	p.grenades = 3
	p.yaw = start_yaw


func begin() -> void:
	start_t = t
	for ps in posts:
		var e = load("res://scripts/enemy.gd").new()
		e.name = "Enemy%d" % main.enemies.size()
		main.add_child(e)
		e.setup(main, ps[0] + Vector3(0, 0.05, 0), ps[1], ps[0], ps[2], ps[3], ps[4])
		e.grace = 1.0
		main.enemies.append(e)
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
	var stats := "Time %d:%02d   Kills %d   Headshots %d" % [secs / 60, secs % 60, main.kills, main.headshots]
	main.ui.show_result(true, "MISSION COMPLETE", stats, n)


func _process(dt: float) -> void:
	t += dt
	_sweep(dt)
	if over or not main.playing:
		return
	var p = main.player
	# the alarm: a soldier in a fight raises it a few seconds later unless he is dead by then
	if not alarm:
		if alarm_t < 0.0:
			for e in main.enemies:
				if not e.dead and e.mode == "combat":
					alarm_src = e
					alarm_t = 4.0
					break
		else:
			alarm_t -= dt
			if alarm_src == null or alarm_src.dead:
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


func _raise_alarm() -> void:
	alarm = true
	reinf_t = 9.0
	main.ui.message("ALARM!", "The station knows you are here. More soldiers are coming.", 3.5)
	main.music.alarm()
	for e in main.enemies:
		if not e.dead:
			e.investigate(main.player.global_position)


func _reinforce() -> void:
	var spots := [Vector3(70, 0, -27), Vector3(72, 0, -24), Vector3(70, 0, -21), Vector3(73, 0, -19)]
	var kinds := ["olive", "blue", "gasmask", "olive"]
	for i in spots.size():
		var e = load("res://scripts/enemy.gd").new()
		e.name = "Enemy%d" % main.enemies.size()
		main.add_child(e)
		e.setup(main, spots[i] + Vector3(0, 0.05, 0), 0.0, spots[i], kinds[i], "ak", [])
		e.grace = 0.0
		main.enemies.append(e)
		e.alarm(main.player.global_position)


# ---------------- building blocks ----------------
func _m(key: String) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m: StandardMaterial3D
	match key:
		"plaster":
			m = main._tex_mat("res://assets/env/building_0.jpg", "res://assets/env/building_1.png", 0.31, 0.95, true)
			m.albedo_color = Color(0.92, 0.88, 0.8)
		"concrete":
			m = main._tex_mat("res://assets/env/stairs_0.jpg", "res://assets/env/stairs_1.png", 0.5, 0.92, true)
		"steel":
			m = main._mat(Color(0.32, 0.33, 0.31), Color(0.45, 0.46, 0.43), 0.6, 0.55, 0.5)
		"green":
			m = main._mat(Color(0.2, 0.27, 0.17), Color(0.26, 0.33, 0.21), 0.8, 0.6, 0.3)
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
			m = main._mat(Color(0.36, 0.25, 0.15), Color(0.48, 0.34, 0.2), 1.5, 0.85, 0.0)
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
	briefing = "A militia unit has taken a radio relay station on the old desert road and is using it to pass orders " + \
		"to its fighters across the border.\n\nYou start behind a ruined wall west of the station. Get through the outer " + \
		"yard and the inner wall, take the relay codes from the command hut, knock out the generator that powers the mast, " + \
		"and get out through the east gate to the pickup point.\n\nYou carry an AK-47, an SD-9 pistol, a knife and three " + \
		"grenades. Take what you need from the guards. If a guard raises the alarm, more soldiers will come up the road."
	main.flat_c = Vector2(0, -25)
	main.flat_r = 80.0
	main.area = Rect2(-33, -54, 66, 58)
	main._build_ground()
	main._build_mountains()
	main._build_rocks(main._tex_mat("res://assets/env/rock_albedo.jpg", "res://assets/env/rock_normal.png", 0.6, 0.95, true), 70.0, false)
	main.scatter(1200, 260, 44.0)
	main.apply_dusk()
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
	# inner compound: command hut, barracks, a third tower, mast and generator
	var hut_c := Vector3(8, 0, -12)
	_hut(hut_c, 6.0, 5.0, 1.2, "x")
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


func _sandbags(c: Vector3, n_bags: int) -> void:
	var bag_scene: Node3D = load("res://assets/env/sandbag.glb").instantiate()
	var bag_mesh: Mesh = bag_scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
	bag_scene.free()
	var w := n_bags * 0.55
	for layer in 5:
		var off := 0.0 if layer % 2 == 0 else 0.275
		var x := -w * 0.5 + off
		while x < w * 0.5 - 0.2:
			var mi := MeshInstance3D.new()
			mi.mesh = bag_mesh
			main.add_child(mi)
			mi.global_position = c + Vector3(x + 0.27, layer * 0.15, 0)
			mi.rotation.y = PI * 0.5 + randf_range(-0.06, 0.06)
			x += 0.55
	var sb := _block(c + Vector3(0, 0.4, 0), Vector3(w, 0.8, 0.55), "plaster", "sandbag")
	sb.get_child(0).visible = false
	main.extra_cover.append([c, 0.3])
