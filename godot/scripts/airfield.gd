extends "res://scripts/deadcity.gd"
## The training ground: a disused airfield late in the day. A steel hangar with its doors pushed open (a plywood
## shoot-house, a gallery on the back wall, stores along the side), the apron in front of it, a firing range down the
## taxiway, a wire fence round it all. Small on purpose: everything in it is drawn at full quality (a photographed sky
## that also lights the scene, surfaces with their own roughness, metal and occlusion maps, real shadows, a reflection
## probe in the hangar, glow and dust where the renderer has them).
## x: east, z: south; the hangar's doors face south.

const TEX := "res://assets/hd/tex/"
const SUN_AZ := 215.0      # where the sun stands: degrees round from north through east
const SUN_EL := 19.0
var hd := false


## A surface with the full set of maps: colour, normal, and occlusion/roughness/metal in one.
func hdmat(key: String, id: String, per_m: float, tint := Color(1, 1, 1), rough := 1.0) -> void:
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(TEX + id + "_diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + id + "_nor.jpg")
	m.orm_texture = load(TEX + id + "_orm.jpg")
	m.roughness = rough
	m.ao_enabled = true
	m.ao_light_affect = 0.3
	m.uv1_scale = Vector3(per_m, per_m, per_m)
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	city.mats[key] = m


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, col := Color(1, 1, 1)) -> void:
	var st: SurfaceTool = city._st(key)
	var n := (b - a).cross(c - a).normalized()
	var ux := (b - a).normalized()
	var uy := n.cross(ux)
	for q in [a, c, b]:
		st.set_color(col)
		st.set_normal(-n)
		st.set_uv(Vector2((q - a).dot(ux), (q - a).dot(uy)))
		st.add_vertex(q)


func sun_dir() -> Vector3:
	var az := deg_to_rad(SUN_AZ)
	var el := deg_to_rad(SUN_EL)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func light() -> void:
	var env: Environment = main.world_env
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hd/sky.hdr")
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(SKY_YAW), 0)
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.9 if hd else 1.25
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.76, 0.78)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_brightness = 1.0
	if hd:
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.1
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var sun: DirectionalLight3D = main.sun
	sun.global_transform = Transform3D(Basis.looking_at(-sun_dir(), Vector3.UP), Vector3.ZERO)
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 2.6
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = false     # (no shadows anywhere)
	sun.shadow_opacity = 1.0
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5


const SKY_YAW := 0.0


func build_airfield() -> Vector3:
	rng.seed = 707
	hd = main.hd
	city.make_mats3()
	city.night = false
	prop_path = "res://assets/hd/props/%s/%s_game.gltf"
	prop_shadows = false
	prop_body = StaticBody3D.new()
	prop_body.set_meta("surf", "metal")
	main.add_child(prop_body)
	hdmat("hd_floor", "hangar_concrete_floor", 0.25, Color(1, 1, 1), 0.85)
	hdmat("hd_iron", "worn_corrugated_iron", 0.5)
	hdmat("hd_green", "factory_wall", 0.5)
	hdmat("hd_door", "painted_metal_shutter", 0.5)
	hdmat("hd_plate", "metal_grate_rusty", 1.0)
	hdmat("hd_ply", "plywood", 0.5)
	hdmat("hd_asphalt", "aerial_asphalt_01", 0.125)
	hdmat("hd_pad", "concrete_floor_02", 0.25)
	hdmat("hd_rust", "rusty_painted_metal", 0.5)
	hdmat("hd_steel", "green_metal_rust", 0.5)
	hdmat("hd_grass", "aerial_grass_rock", 0.1)
	hdmat("hd_concrete", "brushed_concrete", 0.4)
	hdmat("hd_sheet", "box_profile_metal_sheet", 0.5, Color(0.62, 0.66, 0.7))
	light()
	# ---- the ground: flat; grass, the asphalt apron and taxiway, concrete pads
	main.ground_h.resize((main.GROUND_N + 1) * (main.GROUND_N + 1))
	main.ground_h.fill(0.0)
	main.area = Rect2(-44, -54, 128, 98)
	var gb := StaticBody3D.new()
	gb.set_meta("surf", "concrete")
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(700, 1, 700)
	gcs.shape = gsh
	gcs.position.y = -0.5
	gb.add_child(gcs)
	main.add_child(gb)
	city.face("hd_grass", Vector3(0, -0.02, 0), Vector3(350, 0, 0), Vector3(0, 0, -350), Color(0.8, 0.82, 0.74))
	city.face("hd_asphalt", Vector3(20, 0.0, 19), Vector3(66, 0, 0), Vector3(0, 0, -23))
	city.face("hd_asphalt", Vector3(150, 0.0, 26), Vector3(70, 0, 0), Vector3(0, 0, -9))
	city.face("hd_pad", Vector3(0, 0.012, -1.5), Vector3(20, 0, 0), Vector3(0, 0, -3.5), Color(0.9, 0.9, 0.9))
	for k in 26:
		# the taxiway's yellow line, worn
		if rng.randf() < 0.85:
			city.face("m3_paintwork", Vector3(-40 + k * 5.0, 0.02, 30), Vector3(1.6, 0, 0), Vector3(0, 0, -0.08), Color(0.75, 0.6, 0.1))
	city.commit(false)
	_hangar()
	_stores()
	_range()
	commit_props(0.0)
	# ---- the soldiers' posts, the player's place
	main.yard_posts = [
		[Vector3(6, 0, -20), PI, Vector3(6, 0, -32)],
		[Vector3(-9, 0, -30), PI, Vector3(-9, 0, -30)],
		[Vector3(-8, 0, -12), PI * 0.5, Vector3(10, 0, -12)],
		[Vector3(24, 0, -24), 0.0, Vector3(24, 0, -10)],
		[Vector3(-24, 0, -20), -PI * 0.5, Vector3(-24, 0, -36)],
		[Vector3(10, 0, -39), PI, Vector3(4, 0, -37)],
		[Vector3(10, 3.25, -42.2), PI, Vector3(10, 3.25, -42.2)]]
	return Vector3(0, 0.05, 16)


func _hangar() -> void:
	var x0 := -18.0
	var x1 := 18.0
	var z0 := -44.0
	var z1 := -4.0
	var eave := 7.0
	var ridge := 10.0
	begin_building("metal")
	var wc := Color(0.9, 0.9, 0.9)
	city.face("hd_floor", Vector3(0, 0.02, -24), Vector3(18, 0, 0), Vector3(0, 0, -20))
	# walls: sheet steel on a concrete plinth; a strip of windows high in the west side, doors in the east
	var wins := []
	for k in 5:
		wins.append([4.0 + k * 7.2, 7.0 + k * 7.2, 4.6, 6.2])
	wall(Vector2(x0, z0), Vector2(x0, z1), 1.2, eave - 1.2, 0.2, "hd_iron", wc, wins)
	wall(Vector2(x1, z1), Vector2(x1, z0), 1.2, eave - 1.2, 0.2, "hd_iron", wc, [[4.0, 5.2, 1.2, 2.2], [16.0, 20.5, 1.2, 4.6]])
	wall(Vector2(x1, z0), Vector2(x0, z0), 1.2, eave - 1.2, 0.2, "hd_iron", wc)
	wall(Vector2(x0, z1), Vector2(-11.0, z1), 1.2, eave - 1.2, 0.2, "hd_iron", wc)
	wall(Vector2(11.0, z1), Vector2(x1, z1), 1.2, eave - 1.2, 0.2, "hd_iron", wc)
	var pc := Color(0.85, 0.85, 0.85)
	wall(Vector2(x0, z0), Vector2(x0, z1), 0.0, 1.2, 0.36, "hd_concrete", pc)
	wall(Vector2(x1, z1), Vector2(x1, z0), 0.0, 1.2, 0.36, "hd_concrete", pc, [[4.0, 5.2, 0.0, 1.2], [16.0, 20.5, 0.0, 1.2]])
	wall(Vector2(x1, z0), Vector2(x0, z0), 0.0, 1.2, 0.36, "hd_concrete", pc)
	wall(Vector2(x0, z1), Vector2(-11.0, z1), 0.0, 1.2, 0.36, "hd_concrete", pc)
	wall(Vector2(11.0, z1), Vector2(x1, z1), 0.0, 1.2, 0.36, "hd_concrete", pc)
	# gable ends (the south one open below, over the doors)
	for gz in [z0, z1]:
		var s := 1.0 if gz == z1 else -1.0
		for off in [0.1 * s, -0.1 * s]:
			var a := Vector3(x0, eave, gz + off)
			var b := Vector3(x1, eave, gz + off)
			var c := Vector3(0, ridge, gz + off)
			if off * s > 0.0:
				tri("hd_iron", a, b, c, wc) if s > 0.0 else tri("hd_iron", b, a, c, wc)
			else:
				tri("hd_iron", b, a, c, wc) if s > 0.0 else tri("hd_iron", a, b, c, wc)
	# the door leaves pushed to the sides, their rail across the opening's head
	for sx in [-1.0, 1.0]:
		city.box("hd_door", Vector3(sx * 14.3, 3.5, z1 + 0.4), Vector3(6.4, 7.0, 0.14), 0.0, Color(0.75, 0.78, 0.8))
		add_shape(Vector3(sx * 14.3, 3.5, z1 + 0.4), Vector3(6.4, 7.0, 0.14))
	city.box("hd_steel", Vector3(0, 7.15, z1 + 0.4), Vector3(36.0, 0.3, 0.3), 0.0, wc)
	# the steel frames: a column each side, rafters up to the ridge; purlins along the roof
	var sl := atan2(ridge - eave, 18.0)
	for k in 6:
		var fz := z0 + 0.4 + k * 7.84
		for sx in [-1.0, 1.0]:
			city.box("hd_steel", Vector3(sx * 17.65, eave * 0.5, fz), Vector3(0.3, eave, 0.3), 0.0, wc)
			add_shape(Vector3(sx * 17.65, eave * 0.5, fz), Vector3(0.3, eave, 0.3))
			_tilted_box("hd_steel", Vector3(sx * 9.0, (eave + ridge) * 0.5 - 0.25, fz), Vector3(18.4, 0.34, 0.2), Basis(Vector3(0, 0, 1), -sx * sl), wc)
		city.box("hd_steel", Vector3(0, eave - 0.2, fz), Vector3(35.0, 0.12, 0.12), 0.0, wc)
	for sx in [-1.0, 1.0]:
		for q in 4:
			var px: float = sx * (3.0 + q * 4.2)
			city.box("hd_steel", Vector3(px, ridge - abs(px) * tan(sl) - 0.05, -24.0), Vector3(0.1, 0.14, 40.0), 0.0, wc)
	# the roof: sheets in four runs a side, clear strips between them that let the sun in
	for sx in [-1.0, 1.0]:
		for k in 4:
			var cz := z0 - 0.3 + 4.475 + k * 10.55
			ramp(Vector3(sx * 18.4, eave - 0.07, cz), Vector3(0, ridge, cz), 8.95, "hd_sheet", wc, 0.08)
	city.box("hd_steel", Vector3(0, ridge + 0.03, -24.0), Vector3(0.5, 0.08, 40.8), 0.0, wc)
	# painted lines on the floor: a walkway round the edge, a hatched keep-clear by the doors
	var yl := Color(0.72, 0.58, 0.1)
	for sx in [-1.0, 1.0]:
		city.face("m3_paintwork", Vector3(sx * 15.5, 0.026, -24), Vector3(0.06, 0, 0), Vector3(0, 0, -18.5), yl)
	city.face("m3_paintwork", Vector3(0, 0.026, -42.5), Vector3(15.5, 0, 0), Vector3(0, 0, -0.06), yl)
	for k in 14:
		_tilted_box("m3_paintwork", Vector3(-9.75 + k * 1.5, 0.027, -5.4), Vector3(0.12, 0.002, 1.9), Basis(Vector3.UP, 0.7), yl)
	# ---- the shoot-house: plywood walls on timber, open above
	var py := Color(0.95, 0.95, 0.95)
	var hx0 := -16.0
	var hx1 := -3.0
	var hz0 := -41.0
	var hz1 := -23.0
	wall(Vector2(hx0, hz1), Vector2(hx1, hz1), 0.02, 2.4, 0.1, "hd_ply", py, [[5.0, 6.3, 0.0, 2.1]])
	wall(Vector2(hx1, hz1), Vector2(hx1, hz0), 0.02, 2.4, 0.1, "hd_ply", py, [[10.0, 11.3, 0.0, 2.1]])
	wall(Vector2(hx1, hz0), Vector2(hx0, hz0), 0.02, 2.4, 0.1, "hd_ply", py)
	wall(Vector2(hx0, hz0), Vector2(hx0, hz1), 0.02, 2.4, 0.1, "hd_ply", py)
	wall(Vector2(hx0, -32.0), Vector2(hx1, -32.0), 0.02, 2.4, 0.1, "hd_ply", py, [[2.0, 3.3, 0.0, 2.1], [9.0, 10.3, 0.0, 2.1]])
	wall(Vector2(-10.0, hz1), Vector2(-10.0, -32.0), 0.02, 2.4, 0.1, "hd_ply", py, [[5.5, 6.8, 0.0, 2.1]])
	wall(Vector2(-8.0, -32.0), Vector2(-8.0, hz0), 0.02, 2.4, 0.1, "hd_ply", py, [[1.0, 2.3, 0.0, 2.1]])
	for wz in [hz1, -32.0, hz0]:
		for k in 6:
			city.box("hd_ply", Vector3(hx0 + 0.2 + k * 2.52, 1.25, wz + 0.09), Vector3(0.07, 2.45, 0.07), 0.0, Color(0.6, 0.5, 0.38))
	body.set_meta("pierce", "sheet")
	city.commit(true)
	end_building()
	# ---- the gallery along the back wall: a steel deck on posts, stairs up its west end, a rail
	begin_building("metal")
	slab(2.0, -44.0, 17.8, -40.0, 3.2, "hd_plate", wc, "hd_rust", wc)
	stairs(Vector3(-3.4, 0.02, -42.0), Vector3(1, 0, 0), 1.5, 3.18, 5.4, "hd_plate", wc)
	for k in 5:
		city.box("hd_steel", Vector3(2.2 + k * 3.85, 1.6, -40.15), Vector3(0.16, 3.2, 0.16), 0.0, wc)
		add_shape(Vector3(2.2 + k * 3.85, 1.6, -40.15), Vector3(0.16, 3.2, 0.16))
		main.extra_cover.append([Vector3(2.2 + k * 3.85, 0, -39.6), 0.4])
	city.box("hd_steel", Vector3(9.9, 4.25, -40.05), Vector3(15.8, 0.06, 0.06), 0.0, wc)
	city.box("hd_steel", Vector3(9.9, 3.75, -40.05), Vector3(15.8, 0.04, 0.04), 0.0, wc)
	for k in 9:
		city.box("hd_steel", Vector3(2.1 + k * 1.95, 3.72, -40.05), Vector3(0.05, 1.05, 0.05), 0.0, wc)
	add_shape(Vector3(9.9, 3.75, -40.05), Vector3(15.8, 1.05, 0.08))
	city.commit(true)
	end_building()
	# ---- lamps hanging from the frames (lit: it is late), strip lights under the gallery
	for k in 3:
		for sx in [-1.0, 1.0]:
			var lp := Vector3(sx * 7.0, 7.9, -36.0 + k * 12.0)
			prop("hanging_industrial_lamp", lp, rng.randf() * TAU)
			var l := SpotLight3D.new()
			l.light_color = Color(1.0, 0.82, 0.58)
			l.light_energy = 6.0
			l.spot_range = 10.0
			l.spot_angle = 52.0
			l.spot_attenuation = 0.7
			main.add_child(l)
			l.global_position = lp - Vector3(0, 1.3, 0)
			l.rotation.x = -PI * 0.5
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.07
			sm.height = 0.14
			bulb.mesh = sm
			bulb.material_override = city.mats["bulb"]
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			main.add_child(bulb)
			bulb.global_position = lp - Vector3(0, 1.22, 0)
	for k in 3:
		tube(Vector3(5.0 + k * 5.0, 2.93, -42.0), true, k == 1, Color(0.9, 0.95, 1.0), 1.2, 6.0)
	# the hangar's own reflections and fill light, taken once from its middle
	if hd:
		var rp := ReflectionProbe.new()
		rp.size = Vector3(36.4, 10.4, 40.4)
		rp.box_projection = true
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		rp.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
		rp.max_distance = 80.0
		rp.origin_offset = Vector3(0, -2.5, 6.0)
		main.add_child(rp)
		rp.global_position = Vector3(0, 5.0, -24.0)
	# dust hanging in the light near the doors
	var dust := CPUParticles3D.new()
	dust.amount = 260
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(15.0, 3.2, 14.0)
	dust.gravity = Vector3(0, -0.004, 0)
	dust.direction = Vector3(1, 0.2, 0.3)
	dust.spread = 180.0
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.08
	var dq := QuadMesh.new()
	dq.size = Vector2(0.025, 0.025)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_color = Color(1.0, 0.92, 0.78, 0.5)
	dq.material = dm
	dust.mesh = dq
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(dust)
	dust.global_position = Vector3(0, 3.4, -18.0)


## What stands in and round the hangar: stores, benches, things to hide behind, things that break.
func _stores() -> void:
	# along the east wall: racking with crates, a workbench corner
	for k in 4:
		var rp := Vector3(16.6, 0.02, -40.0 + k * 2.3)
		prop("steel_frame_shelves_01", rp, PI * 0.5, Vector3(1.0, 4.3, 2.2), 0.2)
		for q in 2:
			prop(["wooden_crate_02", "old_military_crate", "cardboard_box_01"][(k + q) % 3], rp + Vector3(0, 0.1 + q * 1.32, rng.randf_range(-0.4, 0.4)), rng.randf_range(-0.15, 0.15))
	prop("metal_office_desk", Vector3(16.3, 0.02, -8.5), PI * 0.5, Vector3(0.95, 0.8, 2.0))
	prop("metal_tool_chest", Vector3(16.3, 0.81, -8.9), -PI * 0.5)
	prop("tool_cart", Vector3(14.6, 0.02, -11.0), 0.4, Vector3(1.2, 0.95, 0.75))
	prop("plastic_monobloc_chair_01", Vector3(15.0, 0.02, -8.0), -1.2)
	prop("korean_fire_extinguisher_01", Vector3(17.3, 0.02, -6.4), -PI * 0.5)
	prop("power_box_01", Vector3(17.75, 1.6, -13.0), -PI * 0.5, Vector3.ZERO, 1.6)
	prop("ladder_sectioned_01", Vector3(-17.55, 0.02, -8.0), PI * 0.5, Vector3.ZERO, 1.6, -0.12)
	# out on the floor: stacks to fight round
	stack("old_military_crate", Vector3(3.0, 0.02, -15.0), 0.2, 1, 1, 4, Vector3(1.82, 0.3, 0.98))
	stack("wooden_military_crate", Vector3(8.5, 0.02, -27.0), PI * 0.5, 1, 2, 3, Vector3(1.24, 0.46, 0.52))
	stack("wooden_crate_02", Vector3(-1.0, 0.02, -34.0), 0.3, 2, 1, 2, Vector3(0.55, 0.46, 1.17))
	stack("cement_bag", Vector3(12.0, 0.02, -20.0), 0.0, 2, 2, 4, Vector3(0.48, 0.18, 0.72))
	stack("old_military_crate", Vector3(-6.0, 0.02, -9.0), -0.3, 1, 1, 3, Vector3(1.82, 0.3, 0.98))
	for k in 3:
		prop("Barrel_01", Vector3(12.6 + (k % 2) * 0.62, 0.02, -31.0 - (k / 2) * 0.62), rng.randf() * TAU, Vector3(0.56, 0.87, 0.56))
	prop("industrial_storage_cart", Vector3(1.5, 0.02, -24.0), 0.5, Vector3(1.1, 1.38, 1.6))
	prop("portable_generator", Vector3(-15.5, 0.02, -20.5), 0.3, Vector3(0.82, 0.58, 0.56))
	prop("metal_jerrycan", Vector3(-14.7, 0.02, -20.2), 1.0)
	prop("metal_jerrycan", Vector3(-14.5, 0.02, -20.7), 2.1)
	prop("hand_truck", Vector3(14.0, 0.02, -35.0), 2.3)
	for k in 4:
		prop("old_tyre", Vector3(-16.9, 0.1 + k * 0.17, -14.0), 0.0, Vector3.ZERO, 1.0, 1.57)
	prop("propane_tank", Vector3(-16.8, 0.02, -15.2), 0.0, Vector3(0.34, 0.55, 0.34))
	# two containers in the east half, one outside by the roller door
	for c in [[Vector3(11.5, 0.02, -36.2), PI * 0.5, "green"], [Vector3(26.0, 0, -30.0), 0.1, "red"], [Vector3(-27.0, 0, -12.0), PI * 0.5, "blue"]]:
		var cb: StaticBody3D = main._prop("res://assets/env/container_%s.glb" % c[2], c[0], c[1], Vector3(2.44, 2.59, 6.06), "metal")
		cb.set_meta("pierce", "sheet")
	# sandbags, road barriers: cover between the doors and the apron
	mis._sandbags(Vector3(-5.0, 0.02, -19.5), 5)
	mis._sandbags(Vector3(4.5, 0.0, 1.5), 6)
	mis._sandbags(Vector3(-13.0, 0.0, 4.0), 4)
	for k in 5:
		var bp := Vector3(-22.0 + k * 1.7, 0, -2.0) if k < 3 else Vector3(18.0 + (k - 3) * 1.7, 0, 3.0)
		prop("concrete_road_barrier", bp, 0.03 * k, Vector3(1.55, 0.83, 0.64))
		main.extra_cover.append([bp, 0.6])
	# things that break: wooden crates, fuel drums
	for p in [Vector3(-3, 0.02, -8), Vector3(-1.6, 0.02, -8), Vector3(7, 0, 6), Vector3(-8, 0, 9), Vector3(-8, 1.3, 9), Vector3(0.5, 0.02, -29)]:
		main.breakables.append({"kind": "crate", "pos": p, "rot": rng.randf_range(-0.06, 0.06), "node": null})
	var di := 0
	for p in [Vector3(9, 0, 4), Vector3(9.7, 0, 3.4), Vector3(14.5, 0.02, -15.5), Vector3(15.2, 0.02, -16.0), Vector3(-12.0, 0.02, -21.0), Vector3(25.0, 0, -14.0), Vector3(-23.0, 0, -28.0),
			Vector3(6.0, 0.02, -38.5), Vector3(30.0, 0, 8.0)]:
		main.breakables.append({"kind": "drum", "pos": p, "rot": rng.randf() * TAU, "color": ["blue", "red"][di % 2], "node": null})
		di += 1
	main._restore_breakables()
	# lights over the doors outside
	for sx in [-12.5, 12.5]:
		prop("security_light", Vector3(sx, 6.6, -3.7), 0.0, Vector3.ZERO, 1.5)


## The range down the taxiway (steel plates out to 110 m), and the fence round the field.
func _range() -> void:
	var metal: Material = main._mat(Color(0.35, 0.37, 0.33), Color(0.5, 0.52, 0.46), 0.6, 0.55, 0.35)
	for i in 6:
		var x := 40.0 + i * 14.0
		var z := 24.0 + (i % 2) * 5.0
		main._box(Vector3(x, 0, z), Vector3(0.08, 1.2, 0.08), metal, 0.0, "metal")
		main._box(Vector3(x, 1.2, z), Vector3(0.6, 0.8, 0.05), metal, PI * 0.5, "metal")
	# the firing point: a bench, ammunition, a sandbag rest
	prop("metal_office_desk", Vector3(22.0, 0, 26.0), PI * 0.5, Vector3(0.95, 0.8, 2.0))
	stack("wooden_military_crate", Vector3(22.0, 0, 29.0), 0.1, 1, 1, 2, Vector3(1.24, 0.46, 0.52))
	mis._sandbags(Vector3(26.0, 0, 33.0), 4)
	fence(Vector2(-44, -54), Vector2(84, -54))
	fence(Vector2(84, -54), Vector2(84, 44), [[70.0, 90.0]])
	fence(Vector2(84, 44), Vector2(-44, 44))
	fence(Vector2(-44, 44), Vector2(-44, -54))
	city.commit(true)
