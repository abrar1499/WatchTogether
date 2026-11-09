extends Node3D
## Dust Signal (Godot): the soldier, the rifles, a practice yard with enemy soldiers, and phone controls.

const REPO_API := "https://api.github.com/repos/abrar1499/WatchTogether/releases?per_page=10"

var player: CharacterBody3D
var ui: Control
var fx := FX.new()
var snd := Snd.new()
var music := Music.new()
var version := 0
var playing := false
var test_mode := ""
# enemies: where each one stands (position, facing, other end of his beat)
const POSTS := [
	[Vector3(12, 0, -18.5), PI, Vector3(7, 0, -18.5)],
	[Vector3(-10, 0, -18), PI, Vector3(-4, 0, -18)],
	[Vector3(8, 0, -19.5), PI * 0.5, Vector3(0, 0, -19.5)],
	[Vector3(20, 0, -6), 0.0, Vector3(20, 0, -16)],
	[Vector3(-20, 0, -10), -PI * 0.5, Vector3(-20, 0, -2)],
	[Vector3(0, 0, -27), PI, Vector3(-6, 0, -27)],
	[Vector3(15, 3.2, -21.6), PI, Vector3(15, 3.2, -21.6)],     # on the roof, behind the parapet
]
const ENEMY_KINDS := ["gasmask", "olive", "blue"]
var enemies := []
var wave := 0
var wave_t := -1.0
var kills := 0
var headshots := 0


func _ready() -> void:
	randomize()
	var vf := FileAccess.open("res://version.txt", FileAccess.READ)
	if vf:
		version = int(vf.get_as_text().strip_edges())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test_mode = a.substr(7)
	_build_environment()
	_build_yard()
	add_child(fx)
	add_child(snd)
	music.main = self
	add_child(music)
	player = load("res://scripts/player.gd").new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0, 0.05, 6)
	player.setup(fx, snd)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = load("res://scripts/touch.gd").new()
	ui.main = self
	ui.player = player
	layer.add_child(ui)
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	if test_mode != "":
		start_game()
		var tpath := "res://scripts/%s.gd" % test_mode
		if test_mode != "walk" and ResourceLoader.exists(tpath):
			var d = load(tpath).new()
			d.main = self
			add_child(d)
			d.run()
		else:
			_run_test()
		return
	ui.show_start(version)
	_check_update()


func start_game() -> void:
	playing = true
	ui.hide_start()
	if test_mode == "" or test_mode == "enemies" or test_mode == "music":
		_spawn_wave()
		music.begin()
	if not ui.is_touch and test_mode == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------- automated test: scripted inputs + screenshots ----------------
func _run_test() -> void:
	var out := "/tmp/gd_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var n := 0
	var steps := [["idle", Vector2.ZERO, 1.0], ["walk", Vector2(0, 0.6), 1.2], ["strafeR", Vector2(0.6, 0), 1.0], ["back", Vector2(0, -0.6), 1.0],
		["run", Vector2(0, 1), 1.2], ["strafeL_run", Vector2(-1, 0), 1.0], ["stop", Vector2.ZERO, 1.0]]
	for s in steps:
		player.move_in = s[1]
		for i in 3:
			await get_tree().create_timer(s[2] / 3.0).timeout
			n += 1
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, s[0]])
		print("STEP ", s[0], " state=", player.state, " speed=", snapped(player.speed, 0.01), " ik=", snapped(player.ik_w, 0.01))
	player.move_in = Vector2.ZERO
	player.toggle_crouch()
	await get_tree().create_timer(1.0).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_kneel.png" % [out, n])
	player.move_in = Vector2(0, 0.6)
	await get_tree().create_timer(1.0).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_crouchwalk.png" % [out, n])
	print("STEP crouchwalk state=", player.state)
	player.move_in = Vector2.ZERO
	player.toggle_crouch()
	player.aiming = true
	await get_tree().create_timer(1.0).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_aim.png" % [out, n])
	player.firing = true
	await get_tree().create_timer(0.5).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_fire.png" % [out, n])
	player.firing = false
	player.aiming = false
	player.move_in = Vector2(0, 0.6)
	player.firing = true
	await get_tree().create_timer(0.8).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_walkfire.png" % [out, n])
	player.firing = false
	player.move_in = Vector2.ZERO
	player.reload()
	await get_tree().create_timer(0.7).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_reload.png" % [out, n])
	print("AMMO ", player.weapons[player.wi]["mag"], " ", player.weapons[player.wi]["res"])
	await get_tree().create_timer(1.5).timeout
	player.swap()
	await get_tree().create_timer(1.0).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_pistol.png" % [out, n])
	print("TEST DONE")
	get_tree().quit()


# ---------------- world ----------------
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# a clear desert day: deep blue overhead, pale blue-grey haze at the horizon, neutral (not orange) light
	sm.sky_top_color = Color(0.2, 0.38, 0.66)
	sm.sky_horizon_color = Color(0.7, 0.78, 0.86)
	sm.ground_horizon_color = Color(0.68, 0.66, 0.62)
	sm.ground_bottom_color = Color(0.45, 0.42, 0.38)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	# a fixed, soft fill light instead of the sky's: the sky's own was strong and blue and greyed every colour
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.68, 0.72)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0         # room for the bright desert: sunlit sand no longer burns out to flat white
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.74, 0.76)
	env.fog_density = 0.0011
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -135, 0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.78          # soft, not black
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _noise_tex(c0: Color, c1: Color, freq := 0.02, size := 512) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.noise = n
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	nt.color_ramp = g
	return nt


func _mat(c0: Color, c1: Color, scale := 1.0, rough := 0.95, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(c0, c1, 0.03, 256)
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = rough
	m.metallic = metal
	return m


func _box(pos: Vector3, size: Vector3, mat: Material, rot := 0.0, surf := "concrete") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos + Vector3(0, size.y / 2, 0)
	b.rotation.y = rot
	b.set_meta("surf", surf)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	return b


const YARD_CENTRE := Vector2(0, -8)
var ground_h := PackedFloat32Array()
const GROUND_N := 128
const GROUND_CELL := 5.0


## Height of the ground at (x, z): flat in the yard, dunes beyond it.
func ground_height(x: float, z: float) -> float:
	var half := GROUND_N * GROUND_CELL * 0.5
	var fx: float = clamp((x + half) / GROUND_CELL, 0.0, GROUND_N - 0.001)
	var fz: float = clamp((z + half) / GROUND_CELL, 0.0, GROUND_N - 0.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var w := GROUND_N + 1
	var h0: float = lerp(ground_h[j * w + i], ground_h[j * w + i + 1], u)
	var h1: float = lerp(ground_h[(j + 1) * w + i], ground_h[(j + 1) * w + i + 1], u)
	return lerp(h0, h1, v)


func _tex_mat(albedo: String, normal: String, uv_scale: float, rough := 0.95, triplanar := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(albedo)
	m.normal_enabled = true
	m.normal_texture = load(normal)
	m.roughness = rough
	m.uv1_scale = Vector3.ONE * uv_scale
	m.uv1_triplanar = triplanar
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Sand: rippled sand texture tiling every 4 m, broken up by slow colour changes in the vertex colours;
## flat where the yard is, low dunes rising beyond about 60 m. Collides as a height map.
func _build_ground() -> void:
	var n := GROUND_N
	var cell := GROUND_CELL
	var half := n * cell * 0.5
	var dunes := FastNoiseLite.new()
	dunes.seed = 7
	dunes.frequency = 0.011
	dunes.fractal_octaves = 3
	var tone := FastNoiseLite.new()
	tone.seed = 11
	tone.frequency = 0.035
	var tone2 := FastNoiseLite.new()
	tone2.seed = 12
	tone2.frequency = 0.13
	var w := n + 1
	ground_h.resize(w * w)
	for j in w:
		for i in w:
			var x := -half + i * cell
			var z := -half + j * cell
			var r := Vector2(x, z).distance_to(YARD_CENTRE)
			var d := dunes.get_noise_2d(x, z) * 0.5 + 0.5
			ground_h[j * w + i] = smoothstep(58.0, 125.0, r) * (d * d * 11.0 + 0.8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in w:
		for i in w:
			var x := -half + i * cell
			var z := -half + j * cell
			var h: float = ground_h[j * w + i]
			var tn := tone.get_noise_2d(x, z) + tone2.get_noise_2d(x, z) * 0.6
			var k = 0.92 + 0.08 * tn - min(h, 8.0) * 0.004
			st.set_color(Color(k, k * (0.985 + 0.015 * tn), k * (0.97 + 0.03 * tn)))
			st.set_uv(Vector2(x, z) / 4.0)
			st.add_vertex(Vector3(x, h, z))
	for j in n:
		for i in n:
			var a := j * w + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + w)
			st.add_index(a + 1)
			st.add_index(a + w + 1)
			st.add_index(a + w)
	st.generate_normals()
	st.generate_tangents()
	var gm := MeshInstance3D.new()
	gm.mesh = st.commit()
	var sand := _tex_mat("res://assets/env/sand_albedo.jpg", "res://assets/env/sand_normal.png", 1.0, 1.0)
	sand.vertex_color_use_as_albedo = true
	sand.normal_scale = 0.8
	gm.material_override = sand
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ground := StaticBody3D.new()
	ground.set_meta("surf", "sand")
	ground.add_child(gm)
	var hs := HeightMapShape3D.new()
	hs.map_width = w
	hs.map_depth = w
	hs.map_data = ground_h
	var cs := CollisionShape3D.new()
	cs.shape = hs
	cs.scale = Vector3(cell, 1.0, cell)
	ground.add_child(cs)
	add_child(ground)


## A ring of rocky desert mountains from about half a kilometre out, fading into the haze.
func _build_mountains() -> void:
	var ridges := FastNoiseLite.new()
	ridges.seed = 3
	ridges.frequency = 0.0035
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	var segs := 200
	var rings := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings + 1:
		var r: float = lerp(480.0, 1150.0, pow(float(k) / rings, 0.85))
		for s in segs + 1:
			var a := TAU * s / segs
			var x := cos(a) * r
			var z := sin(a) * r
			var n := ridges.get_noise_2d(x, z) * 0.5 + 0.5
			var rise := smoothstep(480.0, 640.0, r)
			var h := rise * (pow(n, 1.8) * 120.0 + 10.0 * sin(a * 3.0 + 1.0) + 22.0)
			var rock: float = clamp(h / 45.0, 0.0, 1.0)
			var c := Color(0.52, 0.45, 0.37).lerp(Color(0.34, 0.3, 0.27), rock)
			st.set_color(c)
			st.add_vertex(Vector3(x, h - 2.0, z))
	var w := segs + 1
	for k in rings:
		for s in segs:
			var a := k * w + s
			st.add_index(a)
			st.add_index(a + w)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + w)
			st.add_index(a + w + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _tex_mat("res://assets/env/rock_albedo.jpg", "res://assets/env/rock_normal.png", 0.02, 1.0, true)
	m.uv1_world_triplanar = true
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Boulders: a sphere pushed in and out by noise, flattened underneath, rock texture all round.
var rock_meshes := []
func _rock_mesh(seed: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radial_segments = 18
	sm.rings = 10
	var arr := sm.get_mesh_arrays()
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.frequency = 1.4
	nz.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		var v: Vector3 = verts[i]
		var d := 1.0 + nz.get_noise_3dv(v * 1.3) * 0.45
		var p := v * d
		p.y = max(p.y, -0.25) * 0.75
		st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()


func _build_rocks(rock_mat: Material) -> void:
	for s in 3:
		rock_meshes.append(_rock_mesh(40 + s))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var placed := 0
	var tries := 0
	while placed < 22 and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(32.0, 95.0)
		var x := YARD_CENTRE.x + cos(a) * r
		var z := YARD_CENTRE.y + sin(a) * r
		if z > 24.0 and z < 36.0:
			continue          # keep the fence line clear
		var size := rng.randf_range(0.8, 3.2)
		var b := StaticBody3D.new()
		b.set_meta("surf", "rock")
		b.position = Vector3(x, ground_height(x, z) - size * 0.12, z)
		b.rotation.y = rng.randf() * TAU
		var mi := MeshInstance3D.new()
		mi.mesh = rock_meshes[placed % rock_meshes.size()]
		mi.material_override = rock_mat
		mi.scale = Vector3(size * rng.randf_range(0.9, 1.4), size * rng.randf_range(0.7, 1.0), size)
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = size * 0.85
		cs.shape = sp
		cs.position.y = size * 0.15
		b.add_child(cs)
		add_child(b)
		placed += 1


# ---------------- rounds, damage, things that break ----------------
const PIERCE := {"wood": 0.65, "sheet": 0.6, "drum": 0.5}    # damage left after going through
var breakables := []
var debris := []
const SANDBAG_COVER := [Vector3(-3.5, 0, -10), Vector3(-1.8, 0, -10), Vector3(-0.1, 0, -10), Vector3(1.6, 0, -10)]


## Low things a soldier can crouch behind and fire over: crates, drums and the sandbag wall, with their half size.
func cover_list() -> Array:
	var out := []
	for b in breakables:
		var n = b["node"]
		if n != null and is_instance_valid(n) and not n.get_meta("gone", false) and n.global_position.y < 0.5:
			out.append([n.global_position, 0.65 if b["kind"] == "crate" else 0.3])
	for c in SANDBAG_COVER:
		out.append([c, 0.3])
	return out
var scorches := []


## (Re)build every crate and drum that is missing (start, and each new wave).
func _restore_breakables() -> void:
	for b in breakables:
		if b["node"] != null and is_instance_valid(b["node"]):
			continue
		var n: StaticBody3D
		if b["kind"] == "crate":
			n = _prop("res://assets/env/crate.glb", b["pos"], b["rot"], Vector3(1.3, 1.3, 1.3), "wood")
			n.set_meta("hp", 140.0)
			n.set_meta("pierce", "wood")
		else:
			n = _prop("res://assets/env/drum_%s.glb" % b["color"], b["pos"], b["rot"], Vector3(0.3, 0.88, 0), "metal", true)
			n.set_meta("hp", 60.0)
			n.set_meta("pierce", "drum")
		n.set_meta("kind", b["kind"])
		b["node"] = n
	for d in debris:
		if is_instance_valid(d):
			d.queue_free()
	debris.clear()
	for sc in scorches:
		if is_instance_valid(sc):
			sc.queue_free()
	scorches.clear()


## One round from `from` along `dir`: stops in the first solid thing, but goes on through wood, container sheet
## and drums with less force each time; hurts what it hits. Enemy rounds pass through other enemies.
## Returns where it ended (for the tracer).
func shoot_ray(from: Vector3, dir: Vector3, dmg: float, shooter: Node, power := 1.0) -> Vector3:
	var space := get_world_3d().direct_space_state
	var exclude := [shooter.get_rid()]
	var start := from
	var end := from + dir * 400.0
	for i in 5:
		var q := PhysicsRayQueryParameters3D.create(start, end)
		q.exclude = exclude
		var h := space.intersect_ray(q)
		if h.is_empty():
			return end
		var col = h.collider
		var p: Vector3 = h.position
		if col == player:
			if shooter != player:
				player.hit(dmg, shooter.global_position)
			return p
		if col.has_method("take_hit"):
			if shooter == player:
				var was_dead: bool = col.dead
				col.take_hit(dmg, p, dir, power)
				if not was_dead:
					ui.hit_marker(col.dead)
				return p
			exclude.append(col.get_rid())
			start = p
			continue
		fx.impact(p, h.normal, col)
		if col.has_meta("hp"):
			damage_prop(col, dmg, p, h.normal)
		var keep: float = PIERCE.get(str(col.get_meta("pierce", "")), 0.0)
		if keep <= 0.0:
			return p
		dmg *= keep
		exclude.append(col.get_rid())
		start = p + dir * 0.02
	return end


func damage_prop(col: Node, dmg: float, p: Vector3, n: Vector3) -> void:
	if not is_instance_valid(col) or col.get_meta("gone", false):
		return
	var hp: float = float(col.get_meta("hp")) - dmg
	col.set_meta("hp", hp)
	if col.get_meta("kind") == "crate":
		fx.chips(p, n, "wood", 4)
		if hp <= 0.0:
			_break_crate(col)
	else:
		fx.chips(p, n, "metal", 3)
		if hp <= 0.0:
			col.set_meta("gone", true)
			get_tree().create_timer(0.12).timeout.connect(func(): _explode_drum(col))


## A crate gives way: planks fly, dust, and whatever stood on it comes down too.
func _break_crate(col: Node) -> void:
	if not is_instance_valid(col) or col.get_meta("gone", false):
		return
	col.set_meta("gone", true)
	var pos: Vector3 = col.global_position
	var mat: Material = null
	for m in col.find_children("*", "MeshInstance3D", true, false):
		mat = m.mesh.surface_get_material(0)
		break
	col.queue_free()
	fx.dust(pos + Vector3(0, 0.6, 0), 1.6)
	for i in 12:
		var rb := RigidBody3D.new()
		rb.collision_layer = 2
		rb.collision_mask = 1
		var size := Vector3(randf_range(0.5, 1.2), 0.03, randf_range(0.09, 0.14))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		rb.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		rb.add_child(cs)
		add_child(rb)
		rb.global_position = pos + Vector3(randf_range(-0.5, 0.5), randf_range(0.1, 1.2), randf_range(-0.5, 0.5))
		rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		rb.linear_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 3.5), randf_range(-2.5, 2.5))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		debris.append(rb)
	for b in breakables:
		var n = b["node"]
		if b["kind"] == "crate" and n != null and is_instance_valid(n) and n != col and not n.get_meta("gone", false):
			if n.global_position.y > pos.y + 1.0 and Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length() < 0.8:
				get_tree().create_timer(0.15).timeout.connect(func(): if is_instance_valid(n): _break_crate(n))


## A fuel drum blows up: fireball, smoke, light, debris, a scorch mark, a blast that hurts whoever is close and
## in the open (enemies and the player), sets off drums next to it and breaks crates.
func _explode_drum(col: Node) -> void:
	if not is_instance_valid(col):
		return
	var pos: Vector3 = col.global_position + Vector3(0, 0.45, 0)
	var rid: RID = col.get_rid()
	col.queue_free()
	explode_at(pos, 7.0, 260.0, 120.0, [rid], col)


## Any explosion (drum, grenade, rocket): hurts soldiers in the open within `radius` (more the closer), throws them
## back, shakes the camera, sets off drums and breaks crates nearby.
func explode_at(pos: Vector3, radius := 7.0, e_dmg := 260.0, p_dmg := 120.0, ignore: Array = [], src: Node = null) -> void:
	fx.explosion(pos)
	if pos.y < 1.3:
		scorches.append(fx.scorch(Vector3(pos.x, 0.02, pos.z)))
	snd.explosion(pos)
	noise(pos, 60.0)
	var space := get_world_3d().direct_space_state
	var in_open := func(target: Vector3, rid: RID) -> bool:
		var q := PhysicsRayQueryParameters3D.create(pos, target)
		q.exclude = ignore + [rid]
		q.collision_mask = 1
		var h := space.intersect_ray(q)
		return h.is_empty() or h.collider.has_method("take_hit")
	for e in enemies:
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(pos)
		if d < radius and in_open.call(e.global_position + Vector3(0, 1.0, 0), e.get_rid()):
			e.blast(e_dmg * (1.0 - d / radius), pos)
			if e.dead:
				ui.hit_marker(true)
	var dp: float = player.global_position.distance_to(pos)
	if dp < radius and in_open.call(player.global_position + Vector3(0, 1.0, 0), player.get_rid()):
		player.hit(p_dmg * (1.0 - dp / radius), pos)
	player.shake = max(player.shake, clamp(1.2 - dp / 22.0, 0.0, 1.2))
	for b in breakables:
		var n = b["node"]
		if n == null or not is_instance_valid(n) or n == src or n.get_meta("gone", false):
			continue
		var dn: float = n.global_position.distance_to(pos)
		if b["kind"] == "drum" and dn < radius * 0.64:
			damage_prop(n, 999.0, n.global_position + Vector3(0, 0.5, 0), Vector3.UP)
		elif b["kind"] == "crate" and dn < radius * 0.46:
			_break_crate(n)


# ---------------- grenades and rockets ----------------
var nades := []        # live grenades: {"b": body, "t": fuse left, "owner"}
var rockets := []      # {"n": node, "v": velocity, "t": age, "owner", "smoke": time to next puff}
var grenade_mat: StandardMaterial3D


## A grenade in flight: a small rigid body that bounces and rolls; goes off when its fuse runs out.
func spawn_grenade(pos: Vector3, v: Vector3, owner: Node) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 2
	rb.collision_mask = 1
	rb.mass = 0.4
	rb.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.9
	rb.physics_material_override = pm
	rb.angular_damp = 1.5
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.04
	cs.shape = sh
	rb.add_child(cs)
	rb.add_child(fx.grenade_mesh())
	add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = v
	rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	rb.add_collision_exception_with(owner)
	nades.append({"b": rb, "t": 2.4, "owner": owner})


## Live grenades near a point (enemies run from them, the player is warned).
func grenades_near(p: Vector3, r: float) -> Array:
	var out := []
	for g in nades:
		if is_instance_valid(g["b"]) and g["b"].global_position.distance_to(p) < r:
			out.append(g["b"].global_position)
	return out


func fire_rocket(pos: Vector3, dir: Vector3, owner: Node) -> void:
	var n := fx.rocket_mesh()
	add_child(n)
	n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if abs(dir.y) < 0.98 else Vector3.FORWARD), pos)
	rockets.append({"n": n, "v": dir * 48.0, "t": 0.0, "owner": owner, "smoke": 0.0})
	snd.rocket(pos)


func _physics_process(dt: float) -> void:
	for i in range(nades.size() - 1, -1, -1):
		var g: Dictionary = nades[i]
		g["t"] -= dt
		var rb = g["b"]
		if not is_instance_valid(rb):
			nades.remove_at(i)
			continue
		if g["t"] <= 0.0:
			var p: Vector3 = rb.global_position + Vector3(0, 0.15, 0)
			rb.queue_free()
			nades.remove_at(i)
			explode_at(p, 6.5, 300.0, 130.0)
	if rockets.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for i in range(rockets.size() - 1, -1, -1):
		var r: Dictionary = rockets[i]
		var n: Node3D = r["n"]
		r["t"] += dt
		var v: Vector3 = r["v"]
		# the motor burns for half a second (faster), then a slight drop
		if r["t"] < 0.5:
			v += v.normalized() * 50.0 * dt
		v.y -= 2.0 * dt
		r["v"] = v
		var a: Vector3 = n.global_position
		var b: Vector3 = a + v * dt
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.exclude = [r["owner"].get_rid()]
		var h := space.intersect_ray(q)
		if not h.is_empty() or r["t"] > 6.0 or b.y < ground_height(b.x, b.z) - 0.2:
			var at: Vector3 = (h.position - v.normalized() * 0.15) if not h.is_empty() else b
			n.queue_free()
			rockets.remove_at(i)
			if not h.is_empty() and h.collider.has_meta("hp"):
				damage_prop(h.collider, 400.0, h.position, h.normal)
			explode_at(at, 7.5, 420.0, 140.0)
			continue
		n.global_transform = Transform3D(Basis.looking_at(v.normalized(), Vector3.UP if abs(v.normalized().y) < 0.98 else Vector3.FORWARD), b)
		r["smoke"] -= dt
		if r["smoke"] <= 0.0:
			r["smoke"] = 0.025
			fx.trail(b - v.normalized() * 0.5)


## A prop model with a plain box (or cylinder) to collide with.
func _prop(path: String, pos: Vector3, rot := 0.0, col := Vector3.ZERO, surf := "concrete", cylinder := false) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation.y = rot
	b.set_meta("surf", surf)
	var n: Node3D = load(path).instantiate()
	b.add_child(n)
	if col != Vector3.ZERO:
		var cs := CollisionShape3D.new()
		if cylinder:
			var cy := CylinderShape3D.new()
			cy.radius = col.x
			cy.height = col.y
			cs.shape = cy
		else:
			var sh := BoxShape3D.new()
			sh.size = col
			cs.shape = sh
		cs.position.y = col.y * 0.5
		b.add_child(cs)
	add_child(b)
	return b


func _build_yard() -> void:
	_build_ground()
	_build_mountains()
	var metal := _mat(Color(0.35, 0.37, 0.33), Color(0.5, 0.52, 0.46), 0.6, 0.55, 0.35)
	var rock_mat := _tex_mat("res://assets/env/rock_albedo.jpg", "res://assets/env/rock_normal.png", 0.6, 0.95, true)
	# wooden crates (rounds go through them; enough hits break them)
	for p in [Vector3(-3, 0, -2), Vector3(-1.6, 0, -2), Vector3(4, 0, -6), Vector3(6, 0, 3), Vector3(-7, 0, 4), Vector3(-7, 1.3, 4)]:
		breakables.append({"kind": "crate", "pos": p, "rot": randf_range(-0.06, 0.06), "node": null})
	# sandbag wall: the old two rows of boxes, now 144 bags laid like bricks
	for i in 6:
		for y in [0.0, 0.45]:
			var sb := StaticBody3D.new()
			sb.position = Vector3(-4 + i * 1.1, y + 0.225, -10)
			sb.set_meta("surf", "sandbag")
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(1.05, 0.45, 0.6)
			cs.shape = sh
			sb.add_child(cs)
			add_child(sb)
	var bag_scene: Node3D = load("res://assets/env/sandbag.glb").instantiate()
	var bag_mesh: Mesh = bag_scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
	bag_scene.free()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bag_mesh
	var xforms := []
	var brng := RandomNumberGenerator.new()
	brng.seed = 77
	for layer in 6:
		var off := 0.0 if layer % 2 == 0 else 0.275
		for row in 2:
			var x := -4.53 + off
			while x < 1.95:
				var t := Transform3D(Basis(Vector3.UP, PI * 0.5 + brng.randf_range(-0.06, 0.06)).scaled(Vector3(brng.randf_range(0.95, 1.05), 1.0, 1.0)),
					Vector3(x + 0.27, layer * 0.15, -10.15 + row * 0.3))
				xforms.append(t)
				x += 0.55
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# concrete T-wall barriers in place of the old walls (2 m segments)
	for wall in [[Vector3(10, 0, -14), 0.0, 4], [Vector3(-2, 0, -14), 0.0, 4], [Vector3(-14, 0, -4), PI * 0.5, 6]]:
		var c: Vector3 = wall[0]
		var rot: float = wall[1]
		var nseg: int = wall[2]
		var along := Vector3(cos(rot), 0, -sin(rot))
		for k in nseg:
			var p: Vector3 = c + along * ((k - (nseg - 1) * 0.5) * 2.0)
			_prop("res://assets/env/barrier.glb", p, rot + randf_range(-0.015, 0.015), Vector3(2.0, 2.6, 0.3), "concrete")
	# the building, fuel drums, containers
	_prop("res://assets/env/building.glb", Vector3(14, 0, -24), 0.0, Vector3(10, 3.2, 7), "concrete")
	_build_stairs()
	# fuel drums (a few rounds and they blow up), some near the enemy posts
	var di := 0
	for p in [Vector3(8, 0, -2), Vector3(8.7, 0, -2.6), Vector3(8.1, 0, -3.3), Vector3(11.5, 0, -19.6), Vector3(12.2, 0, -20.1),
			Vector3(-8.2, 0, -18.4), Vector3(18.6, 0, -9.0), Vector3(-18.5, 0, -6.5), Vector3(-1.5, 0, -25.5)]:
		breakables.append({"kind": "drum", "pos": p, "rot": randf() * TAU, "color": ["blue", "red"][di % 2], "node": null})
		di += 1
	_restore_breakables()
	for c in [[Vector3(-10, 0, -22), 0.3, "green"], [Vector3(24, 0, -14), 0.0, "red"], [Vector3(-24, 0, -18), PI * 0.5, "blue"], [Vector3(-24, 2.59, -18.1), PI * 0.5 + 0.03, "red"]]:
		var cb := _prop("res://assets/env/container_%s.glb" % c[2], c[0], c[1], Vector3(2.44, 2.59, 6.06), "metal")
		cb.set_meta("pierce", "sheet")
	_build_rocks(rock_mat)
	# practice targets: steel plates on posts
	for i in 5:
		var x := -8.0 + i * 4.0
		var z := -30.0 - (i % 2) * 6.0
		_box(Vector3(x, 0, z), Vector3(0.08, 1.2, 0.08), metal, 0.0, "metal")
		_box(Vector3(x, 1.2, z), Vector3(0.6, 0.8, 0.05), metal, 0.0, "metal")
	# fence line: posts and three strands of barbed wire
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.18, 0.17, 0.16)
	wire.metallic = 0.5
	wire.roughness = 0.6
	for i in 30:
		var post := _box(Vector3(-40 + i * 3.0, 0, 30), Vector3(0.07, 2.0, 0.07), metal, 0.0, "metal")
		post.rotation.z = randf_range(-0.04, 0.04)
	for hgt in [0.7, 1.3, 1.9]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(87.0, 0.012, 0.012)
		mi.mesh = bm
		mi.material_override = wire
		mi.position = Vector3(3.5, hgt, 30)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Outside stairs up the building's east wall to the roof (a smooth ramp under the steps to walk on, a railing to
## stop a fall), and the roof's parapet and water tank to take cover behind.
func _build_stairs() -> void:
	var base := Vector3(19.57, 0, -21.3)
	_prop("res://assets/env/stairs.glb", base, 0.0, Vector3.ZERO, "concrete")
	var u := Vector3(0, 3.2, -4.8).normalized()
	var n := Vector3(0, 4.8, 3.2).normalized()
	var mid := base + Vector3(0, 1.6, -2.1)
	var tilt := Basis(Vector3(1, 0, 0), n, Vector3(1, 0, 0).cross(n))
	_coll(Transform3D(tilt, mid - n * 0.1), Vector3(1.1, 0.2, 5.77), "concrete")
	_coll(Transform3D(Basis(), base + Vector3(0, 3.09, -5.2)), Vector3(1.1, 0.22, 1.6), "concrete")
	_coll(Transform3D(tilt, mid + Vector3(0.52, 0, 0) + n * 0.6), Vector3(0.06, 1.0, 5.77), "metal")
	_coll(Transform3D(Basis(), base + Vector3(0.52, 3.7, -5.4)), Vector3(0.06, 1.0, 1.2), "metal")
	_coll(Transform3D(Basis(), base + Vector3(0, 3.7, -5.97)), Vector3(1.1, 1.0, 0.06), "metal")
	# roof: parapet (with the gap where the stairs come up) and the tank
	for c in [[Vector3(14, 3.4, -20.62), Vector3(10, 0.4, 0.24)], [Vector3(14, 3.4, -27.38), Vector3(10, 0.4, 0.24)],
			[Vector3(9.12, 3.4, -24), Vector3(0.24, 0.4, 7)], [Vector3(18.88, 3.4, -23.3), Vector3(0.24, 0.4, 5.6)]]:
		_coll(Transform3D(Basis(), c[0]), c[1], "concrete")
	var tank := StaticBody3D.new()
	tank.set_meta("surf", "metal")
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 1.12
	cy.height = 0.6
	cs.shape = cy
	tank.add_child(cs)
	add_child(tank)
	tank.global_position = Vector3(11, 3.5, -25.5)


func _coll(xf: Transform3D, size: Vector3, surf: String) -> void:
	var b := StaticBody3D.new()
	b.set_meta("surf", surf)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_transform = xf


# ---------------- enemies ----------------
func _spawn_wave() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	if wave > 0:
		_restore_breakables()
		player.grenades = min(5, player.grenades + 2)
	wave += 1
	for p in POSTS:
		var e = load("res://scripts/enemy.gd").new()
		e.name = "Enemy%d" % enemies.size()
		add_child(e)
		# the three enemy characters, two of each, in a different order every wave
		e.setup(self, p[0] + Vector3(0, 0.05, 0), p[1], p[2], ENEMY_KINDS[(enemies.size() + wave) % ENEMY_KINDS.size()])
		enemies.append(e)
	ui.message("WAVE %d" % wave, "%d enemy soldiers in the yard" % enemies.size(), 2.5)


func alive() -> int:
	var n := 0
	for e in enemies:
		if not e.dead:
			n += 1
	return n


## The player fired: soldiers within earshot come to look.
func noise(pos: Vector3, radius: float) -> void:
	for e in enemies:
		e.hear(pos, radius)


## A soldier who has seen the player calls the ones near him.
func enemy_alarm(src: Node) -> void:
	for e in enemies:
		if e != src and not e.dead and e.global_position.distance_to(src.global_position) < 22.0:
			e.alarm(src.last_seen)


func on_enemy_killed(_e: Node, headshot: bool) -> void:
	kills += 1
	if headshot:
		headshots += 1
	ui.kill_note("HEADSHOT" if headshot else "KILL")
	if alive() == 0:
		wave_t = 7.0
		ui.message("AREA CLEAR", "Next wave in a few seconds", 4.0)


func on_player_dead() -> void:
	ui.message("YOU WERE KILLED", "Back in a moment", 3.5)
	music.player_died()


func on_player_respawn() -> void:
	for e in enemies:
		if not e.dead:
			e.mode = "guard"
			e.alert = 0.0
			e.grace = 3.0


func _process(dt: float) -> void:
	if wave_t > 0.0:
		wave_t -= dt
		if wave_t <= 0.0:
			_spawn_wave()


# ---------------- updates ----------------
func _check_update() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		if code != 200:
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) != TYPE_ARRAY:
			return
		var best := 0
		var url := ""
		for rel in data:
			var tag := str(rel.get("tag_name", ""))
			if not tag.begins_with("v"):
				continue
			var n := int(tag.substr(1))
			for asset in rel.get("assets", []):
				if str(asset.get("name", "")) == "DustSignal.apk" and n > best:
					best = n
					url = str(asset.get("browser_download_url", ""))
		if best > version and url != "":
			ui.offer_update(best, url))
	http.request(REPO_API, ["User-Agent: DustSignal", "Accept: application/vnd.github+json"])


func check_update_now() -> void:
	_check_update()


# =============== effects ===============
class FX extends Node3D:
	const TRACER_SPEED := 260.0      # m/s: quick, but a streak you can follow
	const TRACER_LEN := 4.5
	var soft_tex: Texture2D
	var hole_tex: Texture2D
	var flash_rigs := []             # front star + two crossed side flames, per shot
	var flash_i := 0
	var shot_n := 0
	var light: OmniLight3D
	var light_t := 0.0
	var puffs := []
	var holes := []
	var hole_i := 0
	var puff_i := 0
	var tracers := []
	var tr_i := 0

	## Unlit, two-sided, full-bright. Blended over (not added to) the background, so fire stays orange and
	## yellow against bright sand and sky instead of washing out to white.
	func _glow_mat(tex: Texture2D, billboard := false) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		if billboard:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			m.billboard_keep_scale = true
		return m

	func _ready() -> void:
		soft_tex = _radial(Color(1, 1, 1, 0.9), Color(1, 1, 1, 0))
		hole_tex = _radial(Color(0.05, 0.04, 0.03, 1), Color(0.25, 0.2, 0.15, 0), 0.45)
		light = OmniLight3D.new()
		light.light_color = Color(1, 0.62, 0.28)
		light.omni_range = 9.0
		light.light_energy = 0
		add_child(light)
		# muzzle flash: a star seen from the front, and the flame leaving the muzzle seen from the side
		var t_front: Texture2D = load("res://assets/fx/flash_front.png")
		var t_side: Texture2D = load("res://assets/fx/flash_side.png")
		var fq := QuadMesh.new()
		fq.size = Vector2(1, 1)
		var sq := QuadMesh.new()
		sq.size = Vector2(1, 0.36)
		sq.center_offset = Vector3(0.5, 0, 0)      # from the muzzle outward
		for i in 4:
			var root := Node3D.new()
			root.visible = false
			add_child(root)
			var front := MeshInstance3D.new()
			front.mesh = fq
			front.material_override = _glow_mat(t_front, true)
			front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(front)
			var side_mat := _glow_mat(t_side)
			var sides := []
			for b in [Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0))]:
				var sm := MeshInstance3D.new()
				sm.mesh = sq
				sm.material_override = side_mat
				sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				sm.transform = Transform3D(b, Vector3.ZERO)
				root.add_child(sm)
				sides.append(sm)
			flash_rigs.append({"root": root, "front": front, "sides": sides, "t": 0.0})
		for i in 16:
			var s := Sprite3D.new()
			s.texture = soft_tex
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.shaded = false
			s.visible = false
			s.set_meta("t", 0.0)
			add_child(s)
			puffs.append(s)
		for i in 40:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.11, 0.11)
			mi.mesh = q
			var m := StandardMaterial3D.new()
			m.albedo_texture = hole_tex
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = m
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			holes.append(mi)
		# tracers: a short glowing streak (white-hot head, orange tail) that flies down the bullet's path
		var tq := QuadMesh.new()
		tq.size = Vector2(1, 1)
		var t_mat := _glow_mat(load("res://assets/fx/tracer.png"))
		t_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR   # no mipmaps: a streak a few pixels wide keeps its bright core
		# and a glowing head, so a round flying straight away from the camera still shows as a bright point
		var g_mat := _glow_mat(soft_tex, true)
		g_mat.albedo_color = Color(1.0, 0.72, 0.3)
		for i in 14:
			var mi := MeshInstance3D.new()
			mi.mesh = tq
			mi.material_override = t_mat
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var gl := MeshInstance3D.new()
			gl.mesh = tq
			gl.material_override = g_mat
			gl.visible = false
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(gl)
			tracers.append({"m": mi, "g": gl, "a": Vector3.ZERO, "dir": Vector3.FORWARD, "total": 0.0, "s": 0.0, "on": false,
				"len": TRACER_LEN, "speed": TRACER_SPEED, "wide": 1.0})

	func _radial(c0: Color, c1: Color, mid := 0.0) -> GradientTexture2D:
		var g := Gradient.new()
		g.set_color(0, c0)
		g.set_color(1, c1)
		if mid > 0:
			g.add_point(mid, c0.lerp(c1, 0.3))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		return t

	## Muzzle flash along the shot: random size and roll, about three frames long; smaller close to the eye
	## (first person); the suppressed pistol only gives a small spark. A thin wisp of smoke follows.
	func muzzle_flash(p: Vector3, d: Vector3, gun: String) -> void:
		var f: Dictionary = flash_rigs[flash_i % flash_rigs.size()]
		flash_i += 1
		shot_n += 1
		var root: Node3D = f["root"]
		var near := 1.0
		var cam := get_viewport().get_camera_3d()
		if cam:
			near = clamp(cam.global_position.distance_to(p) / 1.2, 0.5, 1.0)
		var size: float = {"pistol": 0.11, "m4": 0.34, "ak": 0.42, "svd": 0.55, "shotgun": 0.62, "rpg": 0.85}.get(gun, 0.34) * near * randf_range(0.8, 1.2)
		var dn := d.normalized()
		var up := Vector3.UP if abs(dn.y) < 0.98 else Vector3.FORWARD
		root.global_transform = Transform3D(Basis.looking_at(dn, up), p)
		root.rotate_object_local(Vector3.FORWARD, randf() * TAU)
		root.scale = Vector3.ONE * size
		f["front"].scale = Vector3.ONE * (0.7 if gun != "pistol" else 1.0) * randf_range(0.85, 1.15)
		f["front"].material_override.albedo_color = Color(1, 1, 1, randf_range(0.75, 1.0))
		for sm in f["sides"]:
			sm.visible = gun != "pistol"
			sm.scale = Vector3(randf_range(0.8, 1.2), 1, 1)
		root.visible = true
		f["t"] = 0.045
		light.global_position = p + dn * 0.15
		light.light_energy = 0.8 if gun == "pistol" else (6.0 if gun == "rpg" or gun == "shotgun" else 3.5)
		light_t = 0.05
		if gun != "pistol" and shot_n % 2 == 0:
			var s: Sprite3D = puffs[puff_i % puffs.size()]
			puff_i += 1
			s.global_position = p + dn * 0.12
			s.modulate = Color(0.82, 0.8, 0.76, 0.3)
			s.pixel_size = 0.0018 * near
			s.visible = true
			s.set_meta("t", 0.7)
			s.set_meta("max", 0.7)

	func impact(p: Vector3, n: Vector3, col: Object) -> void:
		var surf := "sand"
		if col and col.has_meta("surf"):
			surf = str(col.get_meta("surf"))
		var color = {"sand": Color(0.85, 0.72, 0.52), "wood": Color(0.7, 0.55, 0.35), "metal": Color(1, 0.75, 0.35), "concrete": Color(0.75, 0.73, 0.68), "rock": Color(0.7, 0.58, 0.44), "sandbag": Color(0.8, 0.7, 0.5)}.get(surf, Color(0.8, 0.75, 0.7))
		var s: Sprite3D = puffs[puff_i % puffs.size()]
		puff_i += 1
		s.global_position = p + n * 0.05
		s.modulate = color
		s.pixel_size = 0.004 if surf != "metal" else 0.002
		s.visible = true
		s.set_meta("t", 0.6 if surf != "metal" else 0.12)
		s.set_meta("max", s.get_meta("t"))
		if surf == "sand":
			return
		var h: MeshInstance3D = holes[hole_i % holes.size()]
		hole_i += 1
		h.visible = true
		h.global_position = p + n * 0.01
		var up := Vector3.UP if abs(n.y) < 0.95 else Vector3.FORWARD
		h.look_at(p + n, up)
		h.rotate_object_local(Vector3.FORWARD, randf() * TAU)

	# ---- chips (wood splinters, metal bits), dust, explosions ----
	var chip_list := []
	var chip_i := 0
	var chip_mats := {}
	var big := []          # fireball and smoke sprites
	var big_i := 0
	var boom_light: OmniLight3D
	var boom_t := 0.0

	func _make_chips() -> void:
		for k in ["wood", "metal", "dark"]:
			var m := StandardMaterial3D.new()
			m.albedo_color = {"wood": Color(0.55, 0.38, 0.2), "metal": Color(0.75, 0.72, 0.66), "dark": Color(0.12, 0.1, 0.09)}[k]
			m.roughness = 0.9
			chip_mats[k] = m
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.012, 0.03)
		for i in 40:
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			chip_list.append({"m": mi, "v": Vector3.ZERO, "t": 0.0, "spin": Vector3.ZERO})
		for i in 40:
			var s := Sprite3D.new()
			s.texture = soft_tex
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.shaded = false
			s.visible = false
			add_child(s)
			big.append({"s": s, "t": 0.0, "life": 1.0, "v": Vector3.ZERO, "grow": 0.0, "c0": Color.WHITE, "c1": Color.WHITE})
		boom_light = OmniLight3D.new()
		boom_light.light_color = Color(1.0, 0.6, 0.25)
		boom_light.omni_range = 16.0
		boom_light.light_energy = 0.0
		add_child(boom_light)

	func chips(p: Vector3, n: Vector3, kind: String, count: int, speed := 3.0) -> void:
		if chip_list.is_empty():
			_make_chips()
		for i in count:
			var c: Dictionary = chip_list[chip_i % chip_list.size()]
			chip_i += 1
			var mi: MeshInstance3D = c["m"]
			mi.material_override = chip_mats[kind]
			mi.global_position = p + n * 0.03
			mi.scale = Vector3.ONE * randf_range(0.7, 1.6) * (2.5 if kind == "dark" else 1.0)
			mi.visible = true
			c["v"] = (n + Vector3(randf_range(-0.8, 0.8), randf_range(0.2, 1.2), randf_range(-0.8, 0.8))).normalized() * speed * randf_range(0.5, 1.3)
			c["spin"] = Vector3(randf_range(-15, 15), randf_range(-15, 15), randf_range(-15, 15))
			c["t"] = randf_range(0.6, 1.2) * (2.0 if kind == "dark" else 1.0)

	var flame_tex: Texture2D
	func _big(p: Vector3, size: float, grow: float, life: float, v: Vector3, c0: Color, c1: Color, flame := false) -> void:
		if chip_list.is_empty():
			_make_chips()
		if flame_tex == null:
			flame_tex = load("res://assets/fx/flash_front.png")
		var b: Dictionary = big[big_i % big.size()]
		big_i += 1
		var s: Sprite3D = b["s"]
		s.texture = flame_tex if flame else soft_tex
		s.rotation.z = randf() * TAU
		s.global_position = p
		s.pixel_size = size / 64.0
		s.modulate = c0
		s.visible = true
		b["t"] = life
		b["life"] = life
		b["v"] = v
		b["grow"] = grow / 64.0
		b["c0"] = c0
		b["c1"] = c1

	func dust(p: Vector3, size: float) -> void:
		for i in 3:
			_big(p + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.3), randf_range(-0.4, 0.4)), size, size * 0.8, 1.4,
				Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3)), Color(0.72, 0.62, 0.48, 0.7), Color(0.72, 0.62, 0.48, 0.0))

	func explosion(p: Vector3) -> void:
		# flash and fireball, then a column of dark smoke
		_big(p, 5.0, 8.0, 0.3, Vector3.ZERO, Color(1.0, 0.97, 0.8, 1.0), Color(1.0, 0.6, 0.15, 0.0), true)
		for i in 12:
			var off := Vector3(randf_range(-0.9, 0.9), randf_range(0.0, 1.4), randf_range(-0.9, 0.9))
			_big(p + off, randf_range(2.0, 3.4), randf_range(3.5, 5.5), randf_range(0.8, 1.3), off * 1.8 + Vector3(0, 2.0, 0),
				Color(1.0, randf_range(0.42, 0.7), randf_range(0.05, 0.18), 1.0), Color(0.3, 0.1, 0.03, 0.0), i % 2 == 0)
		for i in 12:
			var off2 := Vector3(randf_range(-0.8, 0.8), randf_range(0.3, 1.8), randf_range(-0.8, 0.8))
			_big(p + off2, randf_range(1.8, 2.8), randf_range(4.0, 7.0), randf_range(3.0, 5.5), Vector3(randf_range(-0.4, 0.4), randf_range(1.4, 2.8), randf_range(-0.4, 0.4)),
				Color(0.16, 0.14, 0.12, 0.85), Color(0.32, 0.3, 0.28, 0.0))
		chips(p, Vector3.UP, "dark", 12, 9.0)
		boom_light.global_position = p + Vector3(0, 1.0, 0)
		boom_light.light_energy = 9.0
		boom_t = 0.55

	func scorch(p: Vector3) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(3.4, 3.4)
		q.orientation = PlaneMesh.FACE_Y
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = hole_tex
		m.albedo_color = Color(0.25, 0.2, 0.16, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = p
		mi.rotation.y = randf() * TAU
		return mi

	## A frag grenade: dark olive egg, fuse on top, the spoon down one side (metres).
	func grenade_mesh() -> Node3D:
		if grenade_m == null:
			grenade_m = StandardMaterial3D.new()
			grenade_m.albedo_color = Color(0.2, 0.23, 0.15)
			grenade_m.roughness = 0.7
			grenade_m.metallic = 0.2
			steel_m = StandardMaterial3D.new()
			steel_m.albedo_color = Color(0.5, 0.5, 0.48)
			steel_m.metallic = 0.6
			steel_m.roughness = 0.45
		var root := Node3D.new()
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.032
		sm.height = 0.074
		sm.radial_segments = 14
		sm.rings = 8
		body.mesh = sm
		body.material_override = grenade_m
		root.add_child(body)
		var fuse := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.009
		cm.bottom_radius = 0.011
		cm.height = 0.026
		cm.radial_segments = 8
		fuse.mesh = cm
		fuse.material_override = steel_m
		fuse.position = Vector3(0, 0.044, 0)
		root.add_child(fuse)
		var spoon := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.012, 0.07, 0.006)
		spoon.mesh = bm
		spoon.material_override = steel_m
		spoon.position = Vector3(0, 0.022, 0.03)
		spoon.rotation.x = -0.15
		root.add_child(spoon)
		return root

	var grenade_m: StandardMaterial3D
	var steel_m: StandardMaterial3D
	var rocket_m: Mesh

	## The PG-7V in flight (the warhead from the RPG model) with a flame and a glow at the tail.
	func rocket_mesh() -> Node3D:
		if rocket_m == null:
			var g: Node3D = load("res://assets/guns/rpg.glb").instantiate()
			var w: MeshInstance3D = g.find_child("warhead", true, false)
			rocket_m = w.mesh
			g.free()
		var root := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = rocket_m
		mi.position = Vector3(0, -0.072, 0.05)
		mi.rotation.y = PI          # the warhead model points along +z; the node flies along -z
		root.add_child(mi)
		var fl := Sprite3D.new()
		fl.texture = load("res://assets/fx/flash_front.png")
		fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		fl.shaded = false
		fl.pixel_size = 0.0018
		fl.modulate = Color(1, 0.8, 0.5)
		fl.position = Vector3(0, 0, 0.12)
		root.add_child(fl)
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.6, 0.3)
		l.light_energy = 2.5
		l.omni_range = 5.0
		l.position = Vector3(0, 0, 0.3)
		root.add_child(l)
		return root

	## Rocket smoke: a grey puff left behind, slowly growing and fading.
	func trail(p: Vector3) -> void:
		if chip_list.is_empty():
			_make_chips()
		_big(p + Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05)), 0.35, 1.4, randf_range(1.2, 1.8),
			Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2)), Color(0.78, 0.77, 0.74, 0.55), Color(0.85, 0.84, 0.8, 0.0))

	## RPG back-blast: a burst of flame and dust out of the back of the tube.
	func backblast(p: Vector3, d: Vector3) -> void:
		if chip_list.is_empty():
			_make_chips()
		_big(p, 0.9, 1.6, 0.18, d * 3.0, Color(1.0, 0.85, 0.5, 0.9), Color(1.0, 0.5, 0.2, 0.0), true)
		for i in 5:
			_big(p + d * (0.3 + i * 0.35), 0.8 + i * 0.25, 2.5, randf_range(1.0, 1.8), d * (2.0 + i) + Vector3(0, 0.4, 0),
				Color(0.75, 0.68, 0.56, 0.6), Color(0.8, 0.74, 0.62, 0.0))

	func blood(p: Vector3, n: Vector3) -> void:
		for i in 2:
			var s: Sprite3D = puffs[puff_i % puffs.size()]
			puff_i += 1
			s.global_position = p + n * (0.04 + i * 0.08) + Vector3(randf_range(-0.04, 0.04), randf_range(-0.03, 0.05), randf_range(-0.04, 0.04))
			s.modulate = Color(0.45, 0.02, 0.02) if i == 0 else Color(0.6, 0.06, 0.04)
			s.pixel_size = 0.0045 if i == 0 else 0.003
			s.visible = true
			s.set_meta("t", 0.45)
			s.set_meta("max", 0.45)

	## mine: the player's own rounds fly away from the shoulder camera and look short end-on, so they get a
	## longer, slower, thicker streak.
	func tracer(a: Vector3, b: Vector3, mine := false) -> void:
		var total := a.distance_to(b)
		if total < 2.0:
			return
		var t: Dictionary = tracers[tr_i % tracers.size()]
		tr_i += 1
		t["a"] = a
		t["dir"] = (b - a) / total
		t["total"] = total
		t["s"] = 0.6
		t["len"] = 8.0 if mine else TRACER_LEN
		t["speed"] = 200.0 if mine else TRACER_SPEED
		t["wide"] = 2.2 if mine else 1.0
		t["on"] = true
		t["m"].visible = true
		t["g"].visible = true
		_place_tracer(t)

	## A camera-facing ribbon from the tail to the head, a few pixels wide however far away it is.
	func _place_tracer(t: Dictionary) -> void:
		var head: float = min(t["s"], t["total"])
		var tail: float = max(0.0, float(t["s"]) - float(t["len"]))
		if head - tail < 0.05 or float(t["s"]) > float(t["total"]) + 0.5:
			t["on"] = false
			t["m"].visible = false
			t["g"].visible = false
			return
		var dir: Vector3 = t["dir"]
		var mid: Vector3 = t["a"] + dir * (head + tail) * 0.5
		var cam := get_viewport().get_camera_3d()
		var to_cam := Vector3.UP
		var dist := 10.0
		if cam:
			to_cam = cam.global_position - mid
			dist = to_cam.length()
		var side := dir.cross(to_cam)
		if side.length() < 0.001:
			side = dir.cross(Vector3.UP)
		side = side.normalized()
		var width: float = clamp(dist * 0.008, 0.035, 0.35) * float(t["wide"])
		t["m"].global_transform = Transform3D(Basis(dir * (head - tail), side * width, dir.cross(side)), mid)
		var hp: Vector3 = t["a"] + dir * head
		var hd := cam.global_position.distance_to(hp) if cam else 10.0
		t["g"].global_transform = Transform3D(Basis().scaled(Vector3.ONE * clamp(hd * 0.018, 0.06, 0.7)), hp)

	func _process(dt: float) -> void:
		for c in chip_list:
			if c["t"] > 0.0:
				c["t"] -= dt
				var mi: MeshInstance3D = c["m"]
				c["v"] += Vector3(0, -9.8, 0) * dt
				mi.global_position += c["v"] * dt
				mi.rotation += c["spin"] * dt
				if mi.global_position.y < 0.01:
					mi.global_position.y = 0.01
					c["v"] = Vector3.ZERO
					c["spin"] = Vector3.ZERO
				if c["t"] <= 0.0:
					mi.visible = false
		for b in big:
			if b["t"] > 0.0:
				b["t"] -= dt
				var s: Sprite3D = b["s"]
				var k: float = 1.0 - b["t"] / b["life"]
				s.global_position += b["v"] * dt
				b["v"] *= 1.0 - min(1.0, dt * 1.2)
				s.pixel_size += b["grow"] * dt / b["life"]
				s.modulate = (b["c0"] as Color).lerp(b["c1"], k)
				if b["t"] <= 0.0:
					s.visible = false
		if boom_t > 0.0:
			boom_t -= dt
			boom_light.light_energy = max(0.0, boom_t / 0.55) * 9.0
		for f in flash_rigs:
			if f["t"] > 0.0:
				f["t"] -= dt
				if f["t"] <= 0.0:
					f["root"].visible = false
		if light_t > 0:
			light_t -= dt
			if light_t <= 0:
				light.light_energy = 0
		for s in puffs:
			var tt: float = s.get_meta("t")
			if tt > 0:
				tt -= dt
				s.set_meta("t", tt)
				var k := 1.0 - tt / float(s.get_meta("max", 0.6))
				s.pixel_size += dt * 0.006
				s.global_position.y += dt * 0.4
				s.modulate.a = (1.0 - k) * 0.8
				if tt <= 0:
					s.visible = false
		for t in tracers:
			if t["on"]:
				t["s"] += float(t["speed"]) * dt
				_place_tracer(t)


# =============== sounds (the player's files, played as they are) ===============
class Snd extends Node:
	const AK_LOOP := [4.145, 7.345]
	const M4_LOOP := [0.695, 2.42]
	const PISTOL_ON := [0.04, 0.77, 1.515, 2.435, 3.025, 3.67]
	const SAND_STEPS := [1.34, 1.925, 2.605, 3.845, 4.435, 9.555, 11.485, 12.185, 13.62, 16.51, 17.37, 23.095]
	const RUN_STEPS := [0.1, 0.4, 0.665, 1.21, 1.515, 1.82, 2.11, 2.42, 3.04, 3.36, 3.685, 4.01]
	const AK_SINGLE := [0.4, 1.31, 2.19, 3.41]      # the four single shots at the start of the AK recording
	# the ElevenLabs grunts: ten short ones (start, end)
	const GRUNTS := [[0.1, 0.58], [0.92, 1.46], [1.74, 2.47], [2.81, 3.21], [3.5, 4.04], [4.36, 4.59], [5.03, 5.49],
		[5.74, 6.41], [6.7, 6.98], [7.31, 7.93]]
	var auto: AudioStreamPlayer
	var auto_loop := []
	var auto_kind := ""
	var one_shots := []
	var streams := {}
	var pistol_i := 0
	var world_shots := []

	func _ready() -> void:
		for k in ["ak", "m4", "pistol", "reload_rifle", "reload_pistol", "steps_sand", "steps_run",
				"enemy_ak", "die_male", "die_collapse", "die_scream", "die_fall", "die_breath", "hurt_groan", "cry_pain", "grunts"]:
			streams[k] = load("res://assets/sfx/%s.mp3" % k)
		streams["whoosh"] = load("res://assets/music/whoosh.mp3")
		streams["boom"] = load("res://assets/music/escape.mp3")   # the impact hit near the end of "Action trailer"
		auto = AudioStreamPlayer.new()
		add_child(auto)
		for i in 8:
			var p := AudioStreamPlayer.new()
			p.set_meta("stop", -1.0)
			add_child(p)
			one_shots.append(p)
		for i in 10:
			var p := AudioStreamPlayer3D.new()
			p.set_meta("stop", -1.0)
			p.unit_size = 9.0
			p.max_distance = 140.0
			add_child(p)
			world_shots.append(p)

	## from/dur in the file's own seconds; pitch only changes how it is played back; fade: the last seconds faded out
	func _play(k: String, from: float, dur: float, vol_db := 0.0, pitch := 1.0, fade := 0.0) -> void:
		var best: AudioStreamPlayer = one_shots[0]
		for p in one_shots:
			if not p.playing:
				best = p
				break
		best.stream = streams[k]
		best.volume_db = vol_db
		best.pitch_scale = pitch
		best.play(from)
		best.set_meta("stop", from + dur)
		best.set_meta("vol", vol_db)
		best.set_meta("fade", fade)

	func _play3d(k: String, pos: Vector3, from: float, dur: float, vol_db := 0.0, pitch := 1.0, fade := 0.0) -> void:
		var best: AudioStreamPlayer3D = world_shots[0]
		for p in world_shots:
			if not p.playing:
				best = p
				break
		best.stream = streams[k]
		best.volume_db = vol_db
		best.pitch_scale = pitch
		best.global_position = pos
		best.play(from)
		best.set_meta("stop", from + dur)
		best.set_meta("vol", vol_db)
		best.set_meta("fade", fade)

	## SVD, shotgun, RPG: one of the AK's single shots played lower (heavier) and louder.
	func shot(gun: String) -> void:
		var at: float = AK_SINGLE[randi() % AK_SINGLE.size()]
		match gun:
			"svd":
				_play("ak", at, 0.85, 3.0, 0.8, 0.2)
			"shotgun":
				_play("ak", at, 0.85, 5.0, 0.62, 0.25)
			"rpg":
				_play("ak", at, 0.85, 2.0, 0.48, 0.3)

	func rocket(_pos: Vector3) -> void:
		_play("whoosh", 0.0, 2.5, 2.0, 1.0, 0.8)

	## The shotgun's pump: the bolt rack from the rifle reload, a little quicker.
	func pump() -> void:
		_play("reload_rifle", 0.44, 0.42, -1.0, 1.15)

	func holster() -> void:
		_play("reload_rifle", 0.05, 0.32, -7.0, 0.9)

	func climb() -> void:
		_play("steps_run", RUN_STEPS[randi() % RUN_STEPS.size()], 0.28, -3.0)
		get_tree().create_timer(0.3).timeout.connect(func(): _play("steps_run", RUN_STEPS[randi() % RUN_STEPS.size()], 0.28, -5.0))

	## The player hit: a short groan (the first one in the file), a longer one for a heavy hit.
	func hurt(heavy: bool) -> void:
		if heavy:
			_play("hurt_groan", 1.45, 1.1, 0.0, 1.0, 0.35)
		else:
			_play("hurt_groan", 0.1, 0.88, -2.0, 1.0, 0.15)

	## An enemy hit but not killed: one of the grunts, from where he is.
	func grunt(pos: Vector3) -> void:
		var g: Array = GRUNTS[randi() % GRUNTS.size()]
		_play3d("grunts", pos, g[0], g[1] - g[0] + 0.05, 2.0, randf_range(0.92, 1.05))

	## A drum going up: the impact hit near the end of the action trailer, from where it happened.
	func explosion(pos: Vector3) -> void:
		_play3d("boom", pos, 20.0, 4.2, 4.0)

	## An enemy burst: the enemy rifle recording from where he stands, a little quieter than the player's gun.
	func enemy_burst(pos: Vector3, shots: int) -> void:
		var long := shots > 4
		_play3d("enemy_ak", pos, 0.595 if long else 0.78, 0.97 if long else 0.79, -7.0)

	## A death cry (none for most headshots), then the body hitting the ground.
	func death(pos: Vector3, kind: String) -> void:
		var pl := kind == "player"
		var voice := ""
		if pl:
			voice = "die_male" if randf() < 0.5 else "die_collapse"
		elif kind == "head":
			voice = "die_collapse" if randf() < 0.3 else ""
		elif kind == "blast":
			voice = "die_scream" if randf() < 0.5 else "cry_pain"
		else:
			var r := randf()
			voice = "die_male" if r < 0.35 else ("die_collapse" if r < 0.6 else ("cry_pain" if r < 0.85 else "die_scream"))
		if voice == "cry_pain":
			_play3d(voice, pos, 0.05, 2.6, 0.0, 1.0, 0.6)    # the cry of pain, its first breath and the loud part
		elif voice != "":
			if pl:
				_play(voice, 0.0, 4.0)
			else:
				_play3d(voice, pos, 0.0, 4.0, -2.0)
		get_tree().create_timer(0.4 if kind == "head" else 0.55).timeout.connect(func():
			if pl:
				_play("die_fall", 0.0, 3.0, -4.0)
			else:
				_play3d("die_fall", pos, 0.0, 3.0, -4.0))
		if pl:
			get_tree().create_timer(1.4).timeout.connect(func(): _play("die_breath", 0.0, 6.0, 2.0))

	func start_auto(kind: String) -> void:
		if auto.playing and auto_kind == kind:
			return
		auto_kind = kind
		auto_loop = AK_LOOP if kind == "ak" else M4_LOOP
		auto.stream = streams[kind]
		auto.play(auto_loop[0])

	func stop_auto() -> void:
		if auto.playing:
			auto.stop()

	func pistol() -> void:
		_play("pistol", PISTOL_ON[pistol_i % PISTOL_ON.size()], 0.62)
		pistol_i += 1

	func reload(kind: String) -> void:
		var k := "reload_pistol" if kind == "pistol" else "reload_rifle"
		_play(k, 0.0, 9.0)

	func step(run: bool, crouch: bool) -> void:
		if run:
			_play("steps_run", RUN_STEPS[randi() % RUN_STEPS.size()], 0.28, -3.0)
		else:
			_play("steps_sand", SAND_STEPS[randi() % SAND_STEPS.size()], 0.45, -12.0 if crouch else -5.0)

	func _process(_dt: float) -> void:
		if auto.playing and auto.get_playback_position() >= auto_loop[1]:
			auto.seek(auto_loop[0])
		for p in one_shots:
			_tail(p)
		for p in world_shots:
			_tail(p)

	func _tail(p: Node) -> void:
		if not p.playing:
			return
		var left: float = float(p.get_meta("stop")) - p.get_playback_position()
		if left <= 0.0:
			p.stop()
			return
		var fade: float = p.get_meta("fade", 0.0)
		if fade > 0.0 and left < fade:
			p.volume_db = float(p.get_meta("vol", 0.0)) + linear_to_db(max(0.001, left / fade))


# =============== music: the player's tracks, mixed softly by what is happening ===============
## Quiet yard: a low suspense bed and the night sound, the odd raven call. Seen: a short stinger. Firefight: one
## action piece at a time, faded in and out, with a rest between pieces so it never drums on. Low health: a heartbeat.
class Music extends Node:
	const LOOPS := ["amb", "night", "heart"]
	const PIECES := ["combat", "escape", "intro"]
	var main: Node
	var streams := {}
	var layers := {}
	var level := {}
	var piece: AudioStreamPlayer
	var piece_vol := 0.0
	var piece_start := 0.0
	var piece_end := 0.0
	var piece_i := 0
	var rest_until := 0.0
	var shots := []
	var t := 0.0
	var on := false
	var contact_t := -99.0
	var spotted_t := -99.0
	var raven_t := 40.0

	func _ready() -> void:
		for k in ["amb", "night", "heart", "combat", "escape", "intro", "spotted", "raven", "whoosh"]:
			streams[k] = load("res://assets/music/%s.mp3" % k)
		for k in LOOPS:
			streams[k].loop = true
			var p := AudioStreamPlayer.new()
			p.stream = streams[k]
			p.volume_db = -80.0
			add_child(p)
			layers[k] = p
			level[k] = 0.0
		piece = AudioStreamPlayer.new()
		add_child(piece)
		for i in 3:
			var p := AudioStreamPlayer.new()
			p.set_meta("stop", -1.0)
			add_child(p)
			shots.append(p)

	func _shot(k: String, vol: float, from := 0.0, dur := -1.0) -> void:
		var best: AudioStreamPlayer = shots[0]
		for p in shots:
			if not p.playing:
				best = p
				break
		best.stream = streams[k]
		best.volume_db = linear_to_db(vol)
		best.play(from)
		best.set_meta("stop", from + dur if dur > 0 else 9999.0)

	## Play pressed: a whoosh and the opening of the trailer, softly, then the quiet bed.
	func begin() -> void:
		on = true
		_shot("whoosh", 0.5)
		_start_piece("intro", 24.0, 0.2)
		rest_until = t + 30.0
		for k in ["amb", "night"]:
			var p: AudioStreamPlayer = layers[k]
			p.play(randf() * streams[k].get_length() * 0.6)

	func _start_piece(k: String, max_len: float, vol: float) -> void:
		piece.stream = streams[k]
		piece.volume_db = -80.0
		piece.play()
		piece_vol = vol
		piece_start = t
		piece_end = t + min(streams[k].get_length(), max_len)

	func spotted() -> void:
		if on and t - spotted_t > 15.0:
			spotted_t = t
			_shot("spotted", 0.55)

	func player_died() -> void:
		_shot("whoosh", 0.4)
		piece_end = min(piece_end, t + 2.0)

	func _process(dt: float) -> void:
		t += dt
		for p in shots:
			if p.playing and p.get_playback_position() >= float(p.get_meta("stop")):
				p.stop()
		if not on:
			return
		var pl = main.player
		var fight := false
		for e in main.enemies:
			if not e.dead and e.mode == "combat":
				fight = true
				if e.sees:
					contact_t = t
		fight = fight and t - contact_t < 20.0
		var dead: bool = pl.dead
		var want := {"amb": 0.0 if dead else (0.04 if fight else 0.09),
			"night": 0.0 if dead else (0.06 if fight else 0.18),
			"heart": (0.1 + clamp((30.0 - pl.hp) / 30.0, 0.0, 1.0) * 0.35) if (not dead and pl.hp < 30.0) else 0.0}
		for k in LOOPS:
			var rate := 0.25 if want[k] > level[k] else 0.12
			level[k] = move_toward(level[k], want[k], rate * dt)
			var p: AudioStreamPlayer = layers[k]
			if level[k] > 0.002:
				if not p.playing:
					p.play()
				p.volume_db = linear_to_db(level[k])
			elif p.playing and want[k] == 0.0:
				p.stop()
		# firefight pieces, one at a time with a rest between
		var fight_on := fight and not dead
		if fight_on and not piece.playing and t >= rest_until:
			var k: String = PIECES[piece_i % PIECES.size()]
			piece_i += 1
			_start_piece(k, 36.0, 0.17)
		if piece.playing:
			# the fight is over: fade the piece out (the opening at the start plays through)
			if not fight_on and piece_end > t + 3.0 and t - piece_start > 1.0 and piece.stream != streams["intro"]:
				piece_end = t + 3.0
			if t >= piece_end:
				piece.stop()
				rest_until = t + randf_range(20.0, 32.0)
			else:
				var env: float = clamp((t - piece_start) / 1.5, 0.0, 1.0) * clamp((piece_end - t) / 3.0, 0.0, 1.0)
				piece.volume_db = linear_to_db(max(0.0001, piece_vol * env))
		# now and then a raven, while it is quiet
		if not fight and not dead:
			raven_t -= dt
			if raven_t <= 0.0:
				raven_t = randf_range(35.0, 80.0)
				_shot("raven", 0.5, randf_range(0.0, 15.0), 5.5)
