extends RefCounted
## Builds mission 2's city into a few merged meshes (one surface per material, per block), so a street of buildings
## costs a handful of draw calls: blocks of flats assembled from a photo-scanned facade kit (see the kit section),
## glass office towers, streets with pavers and kerbs, street lights, signs, rubble.

var main: Node
var sts := {}            # material key -> SurfaceTool for the district being built
var mats := {}
var rng := RandomNumberGenerator.new()
var night := true


func _init(m: Node, seed_ := 7) -> void:
	main = m
	rng.seed = seed_
	_make_mats()
	_kit_mats()


func _make_mats() -> void:
	var trim: StandardMaterial3D = main._tex_mat("res://assets/env/stairs_0.jpg", "res://assets/env/stairs_1.png", 0.6, 0.92, true)
	trim.vertex_color_use_as_albedo = true
	mats["trim"] = trim
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.09)
	glass.metallic = 0.7
	glass.roughness = 0.12
	mats["glass"] = glass
	var wood: StandardMaterial3D = main._mat(Color(0.5, 0.5, 0.5), Color(0.75, 0.75, 0.75), 2.0, 0.85, 0.0)
	wood.vertex_color_use_as_albedo = true
	mats["wood"] = wood
	var steel: StandardMaterial3D = main._mat(Color(0.55, 0.55, 0.55), Color(0.8, 0.8, 0.8), 3.0, 0.55, 0.45)
	steel.vertex_color_use_as_albedo = true
	mats["steel"] = steel
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.roughness = 1.0
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["cloth"] = cloth
	var sign_m := StandardMaterial3D.new()
	sign_m.vertex_color_use_as_albedo = true
	sign_m.emission_enabled = true
	sign_m.emission = Color(1, 1, 1)
	sign_m.emission_energy_multiplier = 0.5
	mats["sign"] = sign_m
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.06, 0.06)
	dark.roughness = 0.8
	dark.vertex_color_use_as_albedo = true
	mats["dark"] = dark
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.13, 0.14, 0.15)
	frame.metallic = 0.6
	frame.roughness = 0.4
	frame.vertex_color_use_as_albedo = true
	mats["frame"] = frame
	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.6, 0.75, 0.8, 0.28)
	rail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rail.metallic = 0.5
	rail.roughness = 0.1
	rail.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["railglass"] = rail
	var led := StandardMaterial3D.new()
	led.vertex_color_use_as_albedo = true
	led.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["led"] = led
	var panel := StandardMaterial3D.new()
	panel.vertex_color_use_as_albedo = true
	panel.roughness = 0.75
	mats["panel"] = panel
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(1, 0.9, 0.75)
	bulb.emission_enabled = true
	bulb.emission = Color(1, 0.85, 0.65)
	bulb.emission_energy_multiplier = 5.0
	mats["bulb"] = bulb


var chunk := ""        # what is drawn goes into the mesh of this name (a mesh takes few lights: big interiors are cut up)


func _st(key: String) -> SurfaceTool:
	var k := key if chunk == "" else chunk + "|" + key
	if not sts.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[k] = st
	return sts[k]


## One flat rectangle: centre c, half extents along u and v, facing n.
func face(key: String, c: Vector3, u: Vector3, v: Vector3, col := Color(1, 1, 1)) -> void:
	var st := _st(key)
	var n := u.cross(v).normalized()
	var p := [c - u - v, c + u - v, c + u + v, c - u + v]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uv[i] * Vector2(u.length() * 2.0, v.length() * 2.0))
		st.add_vertex(p[i])


## A box: centre c, size s, turned yaw about y.
func box(key: String, c: Vector3, s: Vector3, yaw := 0.0, col := Color(1, 1, 1)) -> void:
	var b := Basis(Vector3.UP, yaw)
	var x: Vector3 = b.x * s.x * 0.5
	var y: Vector3 = Vector3.UP * s.y * 0.5
	var z: Vector3 = b.z * s.z * 0.5
	face(key, c + z, x, y, col)
	face(key, c - z, -x, y, col)
	face(key, c + x, -z, y, col)
	face(key, c - x, z, y, col)
	face(key, c + y, x, -z, col)
	face(key, c - y, x, z, col)


func cyl(key: String, base: Vector3, r: float, h: float, seg := 10, col := Color(1, 1, 1)) -> void:
	var st := _st(key)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var q := [base + d0 * r, base + d1 * r, base + d1 * r + Vector3(0, h, 0), base + d0 * r + Vector3(0, h, 0)]
		var ns := [d0, d1, d1, d0]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(ns[k])
			st.set_uv(Vector2(float(i) / seg, 0))
			st.add_vertex(q[k])
		for k in [[base + Vector3(0, h, 0), Vector3.UP], [base, Vector3.DOWN]]:
			var c: Vector3 = k[0]
			var tri := [c, c + d1 * r, c + d0 * r] if k[1] == Vector3.UP else [c, c + d0 * r, c + d1 * r]
			for v in tri:
				st.set_color(col)
				st.set_normal(k[1])
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)


## Put everything added since the last commit into one mesh (one surface per material) in the world.
func commit(shadows := true, gone := 0.0, layer := 1) -> MeshInstance3D:
	var groups := {"": ArrayMesh.new()}
	for k in sts:
		var parts: PackedStringArray = (k as String).split("|")
		var ch: String = parts[0] if parts.size() > 1 else ""
		var key: String = parts[parts.size() - 1]
		if not groups.has(ch):
			groups[ch] = ArrayMesh.new()
		var am: ArrayMesh = groups[ch]
		var st: SurfaceTool = sts[k]
		if key != "curtain" and key != "k_sign":
			st.generate_tangents()
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
	sts.clear()
	var first: MeshInstance3D = null
	for ch in groups:
		if ch != "" and (groups[ch] as ArrayMesh).get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = groups[ch]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = gone
		mi.layers = layer
		main.add_child(mi)
		if first == null:
			first = mi
	return first


func collider(c: Vector3, s: Vector3, yaw := 0.0, surf := "concrete") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta("surf", surf)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	b.add_child(cs)
	main.add_child(b)
	b.global_position = c
	b.rotation.y = yaw
	return b


## Something low to walk on (a pavement, a plinth): solid, with a short slope up every side so feet stand on its top
## and nobody is stopped by its edge. c: centre of its base; s: size (its top at s.y).
func step_collider(c: Vector3, s: Vector3, yaw := 0.0, surf := "concrete") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta("surf", surf)
	var r: float = max(0.25, s.y * 1.3)
	var pts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(Vector3(sx * (s.x * 0.5 + r), 0.0, sz * (s.z * 0.5 + r)))
			pts.append(Vector3(sx * s.x * 0.5, s.y, sz * s.z * 0.5))
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = sh
	b.add_child(cs)
	main.add_child(b)
	b.global_position = c
	b.rotation.y = yaw
	return b


# ---------------- street furniture ----------------
## Rubble: broken blocks and slabs in a heap.
func rubble(p: Vector3, r: float) -> void:
	for i in int(6 + r * 6):
		var q: Vector3 = p + Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r))
		var s := Vector3(rng.randf_range(0.2, 0.9), rng.randf_range(0.1, 0.45), rng.randf_range(0.2, 0.7))
		box("trim", q + Vector3(0, s.y * 0.5, 0), s, rng.randf() * TAU, Color(0.62, 0.6, 0.56).darkened(rng.randf_range(0, 0.3)))


# =============== lights, signs, towers ===============
const LEDS := [Color(1.0, 0.25, 0.35), Color(0.2, 0.85, 1.0), Color(0.45, 1.0, 0.5), Color(1.0, 0.75, 0.2), Color(0.9, 0.4, 1.0), Color(1, 1, 1)]
var glow_tex: Texture2D
var glows := {}


func _glow_material(col: Color, billboard: bool) -> StandardMaterial3D:
	var key := "%s|%s" % [col.to_html(), billboard]
	if glows.has(key):
		return glows[key]
	if glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.45))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		glow_tex = t
	var m := StandardMaterial3D.new()
	m.albedo_texture = glow_tex
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glows[key] = m
	return m


## A soft halo round a light (the bloom a camera sees at night).
func glow(p: Vector3, col: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = _glow_material(col, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 90.0 + size * 10.0
	main.add_child(mi)
	mi.global_position = p
	return mi


## The pool of light a lamp throws on the ground.
func pool(p: Vector3, col: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = _glow_material(col, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 50.0
	main.add_child(mi)
	mi.global_position = p + Vector3(0, 0.06, 0)
	return mi


## A modern LED street light: slim pole, long flat head, cool white; its glow and the pool under it.
func led_lamp(p: Vector3, dir: Vector3) -> void:
	cyl("frame", p, 0.08, 7.5, 8, Color(0.3, 0.31, 0.33))
	var yaw := atan2(dir.x, dir.z)
	box("frame", p + Vector3(0, 7.45, 0) + dir * 1.0, Vector3(0.22, 0.1, 2.0), yaw, Color(0.3, 0.31, 0.33))
	box("led", p + Vector3(0, 7.39, 0) + dir * 1.5, Vector3(0.16, 0.02, 0.9), yaw, Color(1.0, 0.95, 0.85))
	var c: Vector3 = p + Vector3(0, 7.3, 0) + dir * 1.5
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.86, 0.68)
	l.light_energy = 6.0
	l.omni_range = 17.0
	l.distance_fade_enabled = true      # far lamps light nothing the player can see: their halo and pool remain
	l.distance_fade_begin = 42.0
	l.distance_fade_length = 10.0
	l.omni_attenuation = 1.3
	main.add_child(l)
	l.global_position = c
	lamps.append([p, l, glow(c, Color(0.85, 0.75, 0.6, 0.8), 2.2), pool(Vector3(c.x, p.y, c.z), Color(0.3, 0.26, 0.2, 1.0), 6.5)])


## Street lights within `zone` (x, z) go dark: the light, its halo, the pool on the ground.
func power_cut(zone: Rect2) -> void:
	for lp in lamps:
		var at: Vector3 = lp[0]
		if zone.has_point(Vector2(at.x, at.z)):
			for k in [1, 2, 3]:
				lp[k].visible = false


func crossing(c: Vector3, along: Vector3, width: float, length: float) -> void:
	var across := Vector3(along.z, 0, -along.x)
	var n := int(width / 1.0)
	for i in n:
		var p: Vector3 = c + across * (-width * 0.5 + 0.5 + i * 1.0) + Vector3(0, 0.05, 0)
		face("panel", p, across * 0.25, along * length * 0.5, Color(0.85, 0.85, 0.82))


func dashes(a: Vector3, b: Vector3) -> void:
	var d := (b - a)
	var L := d.length()
	var u := d / L
	var s_ := 0.0
	while s_ < L - 3.0:
		face("panel", a + u * (s_ + 1.5) + Vector3(0, 0.05, 0), Vector3(u.z, 0, -u.x) * 0.07, u * 1.5, Color(0.85, 0.85, 0.82))
		s_ += 6.0


func traffic_light(p: Vector3, dir: Vector3, red := true) -> void:
	cyl("frame", p, 0.07, 3.4, 8, Color(0.2, 0.2, 0.2))
	var yaw := atan2(dir.x, dir.z)
	box("frame", p + Vector3(0, 3.9, 0), Vector3(0.32, 1.0, 0.25), yaw, Color(0.15, 0.15, 0.15))
	var col := Color(1, 0.15, 0.1) if red else Color(0.2, 1, 0.4)
	var lp: Vector3 = p + Vector3(0, 4.2 if red else 3.6, 0) + dir * 0.14
	box("led", lp, Vector3(0.18, 0.18, 0.04), yaw, col)
	glow(lp + dir * 0.05, Color(col.r, col.g, col.b, 0.7), 0.9)


## A bus shelter: roof, glass back, a lit advertising panel at one end.
func shelter(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	box("frame", p + Vector3(0, 2.5, 0), Vector3(4.0, 0.1, 1.6), yaw, Color(0.25, 0.26, 0.28))
	for sx in [-1.9, 1.9]:
		box("frame", p + b * Vector3(sx, 1.25, -0.7), Vector3(0.08, 2.5, 0.08), yaw, Color(0.25, 0.26, 0.28))
	box("railglass", p + b * Vector3(0, 1.3, -0.72), Vector3(3.7, 2.0, 0.02), yaw)
	var ad: Vector3 = p + b * Vector3(1.9, 1.3, 0.0)
	box("led", ad, Vector3(0.06, 1.8, 1.2), yaw, Color(0.75, 0.82, 0.9))
	glow(ad, Color(0.5, 0.55, 0.6, 0.6), 2.6)
	box("frame", p + b * Vector3(-0.4, 0.45, -0.4), Vector3(2.4, 0.06, 0.4), yaw, Color(0.3, 0.3, 0.3))


## A glass office tower: a curtain wall of reflecting glass on aluminium mullions, dark spandrels at every floor,
## some offices still lit behind it; a pale band round the crown, a mast with a red light.
func office_tower(x0: float, z0: float, x1: float, z1: float, floors: int, band := Color(0.8, 0.85, 0.9)) -> void:
	if not mats.has("curtain"):
		var cm := StandardMaterial3D.new()
		var tex := _curtain_texture()
		cm.albedo_texture = tex[0]
		cm.emission_enabled = true
		cm.emission_texture = tex[1]
		cm.emission_energy_multiplier = 1.3
		cm.metallic = 0.75
		cm.roughness = 0.08
		cm.uv1_scale = Vector3(1.0 / 12.8, 1.0 / 28.8, 1.0)
		cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mats["curtain"] = cm
	var fh := 3.6
	var h := floors * fh
	var c := Vector3((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5)
	var w := x1 - x0
	var d := z1 - z0
	# the walls (uv from the ground up so floors line up), the roof
	var sides := [[Vector3(0, 0, 1), Vector3(1, 0, 0), w, Vector3(c.x, 0, z1)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), w, Vector3(c.x, 0, z0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), d, Vector3(x1, 0, c.z)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), d, Vector3(x0, 0, c.z)]]
	var st := _st("curtain")
	for fc in sides:
		var nn: Vector3 = fc[0]
		var uu: Vector3 = fc[1]
		var L: float = fc[2]
		var b0: Vector3 = fc[3]
		var u0 := rng.randf_range(0.0, 12.8)
		var p := [b0 - uu * (L * 0.5), b0 + uu * (L * 0.5), b0 + uu * (L * 0.5) + Vector3(0, h, 0), b0 - uu * (L * 0.5) + Vector3(0, h, 0)]
		var uv := [Vector2(u0, h), Vector2(u0 + L, h), Vector2(u0 + L, 0), Vector2(u0, 0)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nn)
			st.set_tangent(Plane(uu, 1.0))
			st.set_uv(uv[i])
			st.add_vertex(p[i])
		face("panel", b0 + Vector3(0, h - 0.6, 0) + nn * 0.05, uu * L * 0.5, Vector3.UP * 0.1, band)
	box("frame", c + Vector3(0, h * 0.5 + 0.3, 0), Vector3(w + 0.2, 0.6, d + 0.2), 0.0, Color(0.55, 0.56, 0.58))
	collider(c, Vector3(w, h, d))
	footprints.append(Rect2(x0, z0, w, d))
	occluders.append(AABB(Vector3(x0 + 0.3, 0, z0 + 0.3), Vector3(w - 0.6, h - 0.3, d - 0.6)))
	box("frame", c + Vector3(0, h * 0.5 + 1.8, 0), Vector3(w * 0.5, 2.4, d * 0.5), 0.0, Color(0.5, 0.5, 0.52))
	var mast := c + Vector3(0, h * 0.5 + 3.0, 0)
	cyl("frame", mast, 0.12, 8.0, 6, Color(0.8, 0.8, 0.8))
	glow(mast + Vector3(0, 8.1, 0), Color(1.0, 0.1, 0.05, 0.95), 1.6)


## The curtain wall, 8 bays of 1.6 m by 8 floors of 3.6 m: albedo (glass, mullions, spandrels) and emission (the
## offices still lit: a warm or cool room, brighter under its ceiling lights).
func _curtain_texture() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 3601
	var W := 512
	var H := 1152
	var cw := W / 8
	var chh := H / 8
	var alb := Image.create(W, H, true, Image.FORMAT_RGB8)
	var emi := Image.create(W, H, true, Image.FORMAT_RGB8)
	alb.fill(Color(0.07, 0.09, 0.11))
	emi.fill(Color(0, 0, 0))
	for fy in 8:
		var lit_run := r.randf() < 0.5
		var run_a := r.randi_range(0, 5)
		var run_b := run_a + r.randi_range(1, 5)
		var warm := r.randf() < 0.5
		for bx in 8:
			var x0 := bx * cw
			var y0 := fy * chh
			# glass with a faint vertical reflection gradient
			for y in range(y0, y0 + chh):
				var t := float(y - y0) / chh
				alb.fill_rect(Rect2i(x0, y, cw, 1), Color(0.06, 0.08, 0.1).lerp(Color(0.1, 0.12, 0.15), t))
			if lit_run and bx >= run_a and bx <= run_b:
				var room: Color = Color(1.0, 0.8, 0.55) if warm else Color(0.78, 0.86, 1.0)
				room *= r.randf_range(0.55, 0.9)
				for y in range(y0 + 8, y0 + int(chh * 0.78)):
					var t := float(y - y0) / (chh * 0.78)
					emi.fill_rect(Rect2i(x0, y, cw, 1), room * (1.05 - t * 0.55))
				# ceiling lights, desks and a person's shape now and then
				emi.fill_rect(Rect2i(x0 + 6, y0 + 10, cw - 12, 4), room * 1.4)
				emi.fill_rect(Rect2i(x0, y0 + int(chh * 0.55), cw, int(chh * 0.08)), room * 0.35)
				if r.randf() < 0.25:
					emi.fill_rect(Rect2i(x0 + r.randi_range(10, cw - 24), y0 + int(chh * 0.36), 12, int(chh * 0.3)), room * 0.25)
			# spandrel (floor slab) and mullions
			alb.fill_rect(Rect2i(x0, y0 + int(chh * 0.78), cw, int(chh * 0.22)), Color(0.13, 0.14, 0.15))
			emi.fill_rect(Rect2i(x0, y0 + int(chh * 0.78), cw, int(chh * 0.22)), Color(0, 0, 0))
			alb.fill_rect(Rect2i(x0, y0, 3, chh), Color(0.42, 0.44, 0.46))
			emi.fill_rect(Rect2i(x0, y0, 3, chh), Color(0, 0, 0))
			alb.fill_rect(Rect2i(x0, y0 + int(chh * 0.78), cw, 2), Color(0.42, 0.44, 0.46))
	alb.generate_mipmaps()
	emi.generate_mipmaps()
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]


## A big LED video wall on a facade (n: facing), showing an advert.
func screen(c: Vector3, n: Vector3, w: float, h: float, img: Texture2D) -> void:
	var u := Vector3(n.z, 0, -n.x)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = img
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.material_override = m
	main.add_child(mi)
	mi.global_position = c + n * 0.08
	mi.look_at(c + n * 5.0, Vector3.UP)
	mi.rotate_object_local(Vector3.UP, PI)
	box("frame", c, Vector3(w + 0.4, h + 0.4, 0.2), atan2(n.x, n.z), Color(1, 1, 1))
	glow(c + n * 1.0, Color(0.5, 0.5, 0.6, 0.35), max(w, h) * 1.4)


## An advert to show on a screen: a colour field, a bright product shape, bars of "text".
func ad_image(seed_: int) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var W := 256
	var H := 144
	var img := Image.create(W, H, true, Image.FORMAT_RGB8)
	var c0: Color = [Color(0.05, 0.1, 0.35), Color(0.4, 0.02, 0.1), Color(0.02, 0.25, 0.2), Color(0.25, 0.05, 0.35)][seed_ % 4]
	var c1: Color = [Color(0.1, 0.6, 0.95), Color(1.0, 0.4, 0.1), Color(0.3, 0.95, 0.6), Color(0.95, 0.3, 0.9)][seed_ % 4]
	for y in H:
		for x in W:
			var t := float(x) / W * 0.7 + float(y) / H * 0.3
			img.set_pixel(x, y, c0.lerp(c0.lightened(0.25), t))
	var cx := r.randi_range(150, 200)
	var cy := r.randi_range(50, 90)
	for y in H:
		for x in W:
			var dd := Vector2(x - cx, (y - cy) * 1.2).length()
			if dd < 38:
				img.set_pixel(x, y, c1.lerp(Color(1, 1, 1), clamp(1.0 - dd / 38.0, 0, 1) * 0.5))
	for b in 3:
		var y0 := 30 + b * 26
		var len_ := r.randi_range(60, 110) if b == 0 else r.randi_range(40, 90)
		for y in range(y0, y0 + (14 if b == 0 else 8)):
			for x in range(18, 18 + len_):
				img.set_pixel(x, y, Color(1, 1, 1) if b == 0 else Color(0.85, 0.85, 0.9))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# =============== buildings ===============
## A building is put together from pieces, each one 3 x 3 m bay of wall (local x -3..0, y 0..3, facing +z) or what
## fits one: a wall with a window's hole and the window for it, a wall with a doorway, a plinth, a string course, a
## parapet, corner posts. The pieces are made here from a few rectangles each (see _piece): plastered walls, big
## windows of two to four panes in thin dark frames, plain bands. (They used to be a photo-scanned facade kit with
## moulded surrounds and small sash windows: forty times the vertices, and most of a mission's loading time.)
## Roller shutters and air conditioners (Poly Haven, CC0) join in as models.
const PLASTER_KEY := ["k_plaster0", "k_plaster1", "k_plaster2", "k_plaster3", "k_plaster4", "k_plaster5", "k_plaster6", "k_plaster7"]
const KIT_FAR := 75.0         # beyond this, a building is flat walls with its window panes on them
const KIT_GONE := 270.0       # and beyond this (deep in the haze) it is not drawn
const PLASTER := [Color(0.93, 0.9, 0.84), Color(0.84, 0.83, 0.8), Color(0.96, 0.87, 0.74), Color(0.76, 0.75, 0.72),
	Color(0.93, 0.83, 0.78), Color(0.8, 0.84, 0.86), Color(0.9, 0.9, 0.9), Color(0.82, 0.76, 0.66)]
const WINDOW_SETS := [["centered_large"], ["centered_small"], ["centered_double"], ["centered_large", "centered_small"],
	["offset_small"], ["centered_small", "centered_double", "centered_small"]]
const SIGN_BG := [Color(0.08, 0.32, 0.18), Color(0.55, 0.07, 0.06), Color(0.06, 0.16, 0.42), Color(0.92, 0.9, 0.86),
	Color(0.85, 0.62, 0.08), Color(0.12, 0.12, 0.13)]
const SHUTTER_SCENE := "res://assets/city/props/rollershutter_door/rollershutter_door_game.gltf"
const AIRCON_SCENE := "res://assets/city/props/exterior_aircon_unit/exterior_aircon_unit_game.gltf"
var detail := {}        # material key -> Buf: the buildings being made, as built
var plain := {}         # the same from far off: plain walls and panes
var dmg := []             # shell holes in the building being made: [centre, radius]
var broken_share := 0.0  # share of windows with their glass gone
var soot_share := 0.0    # share of windows with smoke stains above them
var block_tones := []   # the plaster colours of the block being built (a few, so a block needs few materials)
var prop_meshes := {}
var kit_ready := false
var occluders: Array[AABB] = []
var footprints: Array[Rect2] = []   # buildings' ground plans (x, z), to keep soldiers out of them
var lamps := []                     # street lights: [foot, light, halo, pool]
var force_open := Vector3(INF, 0, INF)   # the shop bay nearest this point is open and lit (a mission's)
var opened_bay := []                # that bay: [centre on the facade, along, out, width]


func _pbr(diff: String, nor: String, arm: String, tint: Color, uv := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(nor)
	m.roughness = 0.88
	if arm != "":
		# the scan's occlusion (red) and roughness (green): the training ground's way
		var a: Texture2D = load(arm)
		m.roughness_texture = a
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = 1.0
		m.ao_enabled = true
		m.ao_texture = a
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.3
	m.uv1_scale = Vector3(uv, uv, uv)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _kit_mats() -> void:
	if kit_ready:
		return
	kit_ready = true
	var t := "res://assets/city/facade/textures/modular_urban_apartments_facade_"
	for i in PLASTER.size():
		mats["k_plaster%d" % i] = _pbr("res://assets/city/tex/plaster_grey_diff.jpg", t + "plaster_nor_gl_1k.jpg", t + "plaster_arm_1k.jpg", PLASTER[i])
		# the same plaster on plain walls drawn here (uv in metres, the scan's bays are 3 m)
		mats["kq_plaster%d" % i] = _pbr("res://assets/city/tex/plaster_grey_diff.jpg", t + "plaster_nor_gl_1k.jpg", "", PLASTER[i], 1.0 / 3.0)
	# plinths, and the paler bands (string course, parapet): the same plaster
	mats["k_base"] = _pbr("res://assets/city/tex/plaster_grey_diff.jpg", t + "plaster_nor_gl_1k.jpg", t + "plaster_arm_1k.jpg", Color(0.5, 0.5, 0.51))
	mats["k_band"] = _pbr("res://assets/city/tex/plaster_grey_diff.jpg", t + "plaster_nor_gl_1k.jpg", t + "plaster_arm_1k.jpg", Color(0.88, 0.87, 0.84))
	var void_ := StandardMaterial3D.new()      # the unlit inside of a building, seen through an empty window frame
	void_.albedo_color = Color(0.035, 0.036, 0.04)
	void_.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["k_void"] = void_
	var fr := StandardMaterial3D.new()         # window and door frames: pale aluminium
	fr.albedo_color = Color(0.62, 0.63, 0.64)
	fr.metallic = 0.35
	fr.roughness = 0.5
	mats["k_frame"] = fr
	# every pane in one surface: dark reflecting glass, or a lit room (the vertex colour, set per window)
	var gs := Shader.new()
	gs.code = """shader_type spatial;
uniform float lit_energy = 1.8;
void fragment() {
	float lit = step(0.02, COLOR.r + COLOR.g + COLOR.b);
	// a lit room through a big pane: darker under the pelmet at the top and behind the furniture at the foot
	float room = mix(0.5, 1.0, smoothstep(0.0, 0.3, UV.y)) * mix(1.0, 0.7, smoothstep(0.72, 1.0, UV.y));
	// dark glass: a little of the sky in the top of a big pane, so it is not a black hole in the wall
	ALBEDO = mix(mix(vec3(0.085, 0.1, 0.125), vec3(0.03, 0.038, 0.046), smoothstep(0.0, 0.8, UV.y)), COLOR.rgb * 0.2, lit);
	METALLIC = 0.65 * (1.0 - lit);
	ROUGHNESS = mix(0.06, 0.3, lit);
	EMISSION = COLOR.rgb * lit_energy * room + vec3(0.012, 0.015, 0.02) * (1.0 - lit) * (1.0 - UV.y);
}
"""
	var g := ShaderMaterial.new()
	g.shader = gs
	mats["k_glass"] = g
	mats["k_roof"] = _pbr("res://assets/city/tex/gravel_concrete_diff.jpg", "res://assets/city/tex/gravel_concrete_nor.jpg", "", Color(0.7, 0.7, 0.68), 0.25)
	# shop insides seen under a raised shutter: plastered, lit warm
	var shop := _pbr("res://assets/city/tex/plaster_grey_diff.jpg", t + "plaster_nor_gl_1k.jpg", "", Color(1, 1, 1), 1.0 / 3.0)
	shop.vertex_color_use_as_albedo = true
	shop.emission_enabled = true
	shop.emission_texture = shop.albedo_texture
	shop.emission = Color(1.0, 0.86, 0.66)
	shop.emission_energy_multiplier = 0.45
	shop.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mats["k_shop"] = shop
	var sg := StandardMaterial3D.new()
	sg.albedo_texture = _sign_atlas()
	sg.emission_enabled = true
	sg.emission_texture = sg.albedo_texture
	sg.emission_energy_multiplier = 0.5
	sg.roughness = 0.5
	sg.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats["k_sign"] = sg
	# streets: worn asphalt, pavers, kerb stone, concrete walls
	mats["g_asphalt"] = _pbr("res://assets/city/tex/asphalt_02_diff.jpg", "res://assets/city/tex/asphalt_02_nor.jpg", "res://assets/city/tex/asphalt_02_arm.jpg", Color(0.78, 0.78, 0.78), 0.2)
	# a road worn smooth by tyres: the lamps shine along it
	mats["g_asphalt"].roughness = 0.62
	mats["g_asphalt"].metallic_specular = 0.7
	mats["g_worn"] = _pbr("res://assets/city/tex/worn_asphalt_diff.jpg", "res://assets/city/tex/worn_asphalt_nor.jpg", "res://assets/city/tex/worn_asphalt_arm.jpg", Color(0.8, 0.8, 0.8), 0.2)
	mats["g_pavers"] = _pbr("res://assets/city/tex/square_concrete_pavers_diff.jpg", "res://assets/city/tex/square_concrete_pavers_nor.jpg", "res://assets/city/tex/square_concrete_pavers_arm.jpg", Color(0.72, 0.72, 0.74), 0.4)
	mats["g_kerb"] = _pbr("res://assets/city/tex/concrete_pavement_diff.jpg", "res://assets/city/tex/concrete_pavement_nor.jpg", "", Color(0.85, 0.85, 0.83), 0.5)
	mats["g_wall"] = _pbr("res://assets/city/tex/concrete_wall_006_diff.jpg", "res://assets/city/tex/concrete_wall_006_nor.jpg", "res://assets/city/tex/concrete_wall_006_arm.jpg", Color(0.85, 0.85, 0.83), 0.33)


const FONT := {"A": "01110100011000111111100011000110001", "B": "11110100011000111110100011000111110",
	"C": "01110100011000010000100001000101110", "D": "11100100101000110001100011001011100",
	"E": "11111100001000011110100001000011111", "F": "11111100001000011110100001000010000",
	"G": "01110100011000010111100011000101111", "H": "10001100011000111111100011000110001",
	"I": "01110001000010000100001000010001110", "J": "00111000100001000010000101001001100",
	"K": "10001100101010011000101001001010001", "L": "10000100001000010000100001000011111",
	"M": "10001110111010110101100011000110001", "N": "10001100011100110101100111000110001",
	"O": "01110100011000110001100011000101110", "P": "11110100011000111110100001000010000",
	"Q": "01110100011000110001101011001001101", "R": "11110100011000111110101001001010001",
	"S": "01111100001000001110000010000111110", "T": "11111001000010000100001000010000100",
	"U": "10001100011000110001100011000101110", "V": "10001100011000110001100010101000100",
	"W": "10001100011000110101101011010101010", "X": "10001100010101000100010101000110001",
	"Y": "10001100011000101010001000010000100", "Z": "11111000010001000100010001000011111",
	"0": "01110100011001110101110011000101110", "1": "00100011000010000100001000010001110",
	"2": "01110100010000100010001000100011111", "3": "11111000100010000010000011000101110",
	"4": "00010001100101010010111110001000010", "5": "11111100001111000001000011000101110",
	"6": "00110010001000011110100011000101110", "7": "11111000010001000100010000100001000",
	"8": "01110100011000101110100011000101110", "9": "01110100011000101111000010001001100",
	"-": "00000000000000011111000000000000000", "&": "01100100101010001000101011001001101"}
const SHOP_NAMES := [["CITY PHARMACY", "MEDICINES 24 HOURS"], ["AL NOOR MOBILES", "EASYLOAD  REPAIRS"], ["STAR ELECTRONICS", "TV  AC  FRIDGE"],
	["ROYAL TAILORS", "GENTS & LADIES"], ["FRESH BAKERS", "CAKES  BREAD  SWEETS"], ["TEA CORNER", "TEA  SNACKS"], ["GENERAL STORE", "GROCERY ITEMS"],
	["SHAH JEWELLERS", "GOLD  SILVER"], ["PRINCE SHOES", "NEW ARRIVALS"], ["MONEY EXCHANGE", "DOLLAR  RIYAL  EURO"], ["NEW STYLE SALON", "HAIR & BEARD"],
	["GOLDEN SWEETS", "SINCE 1987"], ["AUTO PARTS", "TYRES  BATTERIES"], ["BOOK DEPOT", "STATIONERY"], ["PHOTO STUDIO", "COPY  PRINT"], ["TELECOM CENTRE", "SIM  INTERNET"]]
const SIGN_ROWS := 16


func _glyphs(img: Image, text: String, x0: int, y0: int, px: int, col: Color) -> void:
	var x := x0
	for ch in text:
		if FONT.has(ch):
			var bits: String = FONT[ch]
			for r in 7:
				for c in 5:
					if bits.substr(r * 5 + c, 1) == "1":
						img.fill_rect(Rect2i(x + c * px, y0 + r * px, px, px), col)
		x += 6 * px


## Every shop's name board in one texture, a row each: painted ground, the name in block capitals, a line under it.
func _sign_atlas() -> ImageTexture:
	var W := 512
	var H := 64
	var img := Image.create(W, H * SIGN_ROWS, true, Image.FORMAT_RGB8)
	for i in SIGN_ROWS:
		var bg: Color = SIGN_BG[i % SIGN_BG.size()].lerp(SIGN_BG[(i * 7 + 3) % SIGN_BG.size()], 0.15 if i >= SIGN_BG.size() else 0.0)
		var ink := Color(0.1, 0.1, 0.1) if bg.v > 0.7 else Color(0.97, 0.95, 0.88)
		if bg.r > 0.8 and bg.b < 0.2:
			ink = Color(0.55, 0.05, 0.05)
		img.fill_rect(Rect2i(0, i * H, W, H), bg)
		img.fill_rect(Rect2i(0, i * H, W, 3), bg.darkened(0.4))
		img.fill_rect(Rect2i(0, i * H + H - 3, W, 3), bg.darkened(0.4))
		var nm: Array = SHOP_NAMES[i % SHOP_NAMES.size()]
		var name_: String = nm[0]
		var px := mini(5, int(480.0 / (name_.length() * 6.0)))
		_glyphs(img, name_, (W - name_.length() * 6 * px) / 2, i * H + 8, px, ink)
		var sub: String = nm[1]
		_glyphs(img, sub, (W - sub.length() * 6 * 2) / 2, i * H + 8 + 7 * px + 6, 2, ink.lerp(bg, 0.2))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A shop's name board facing n, centre c, w by h: a lit panel cut from the sign atlas (row), on a dark frame.
func sign_board(c: Vector3, X: Vector3, n: Vector3, w: float, h: float, row: int) -> void:
	var st := _st("k_sign")
	var v0 := float(row) / SIGN_ROWS
	var v1 := float(row + 1) / SIGN_ROWS
	var p := [c - X * (w * 0.5) - Vector3.UP * (h * 0.5), c + X * (w * 0.5) - Vector3.UP * (h * 0.5), c + X * (w * 0.5) + Vector3.UP * (h * 0.5), c - X * (w * 0.5) + Vector3.UP * (h * 0.5)]
	var uv := [Vector2(0, v1), Vector2(1, v1), Vector2(1, v0), Vector2(0, v0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_uv(uv[i])
		st.add_vertex(p[i] + n * 0.05)
	box("dark", c, Vector3(w + 0.08, h + 0.08, 0.08), atan2(n.x, n.z), Color(0.15, 0.15, 0.16))


# ---- joining pieces ----
## A level's buildings are thousands of pieces joined into a few meshes. Placing a piece only notes where it
## stands; the mesh is put together at the end with whole-array work (a transform over a packed array, an append),
## the copies of one piece that face the same way taken together. (SurfaceTool.append_from, used before, read
## every piece back from the graphics card and copied it a vertex at a time: most of a minute on a phone.)
class Buf:
	var groups := {}       # Vector3i(part, basis, tint) -> PackedVector3Array: where each copy stands


const BIAS := 8388608.0      # 2^23: a float this much above a whole number holds that number in its low 23 bits
const TILE := 8              # copies of a part kept side by side, to add several at once
const P_V := 0               # a part: positions, normals, tangent directions, tangent signs, uvs, triangles,
const P_N := 1               # vertex count, then normals .. triangles again for TILE copies in a row
const P_T := 2
const P_W := 3
const P_UV := 4
const P_TRI := 5
const P_NV := 6
const P_TILED := 7
var parts := {}              # "mesh id|surface" -> number in part_list (the parts taken from prop models)
var part_list: Array = []
var basis_ids := {}
var basis_list: Array = []
var tint_ids := {}
var tint_list: Array = [Color(0, 0, 0), Color(0, 0, 0)]
var tint_fill: Array = [PackedColorArray(), PackedColorArray()]
var pieces := {}             # piece name -> [[kind, material key, part], ..]; kind 0 plaster, 1 glass, 2 other


## The number of the part made of surface s of mesh m (a prop's model: read back once and kept).
func _part(m: Mesh, s: int) -> int:
	var key := "%d|%d" % [m.get_instance_id(), s]
	if parts.has(key):
		return parts[key]
	var a := m.surface_get_arrays(s)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nv := v.size()
	var t3 := PackedVector3Array()
	var w := PackedFloat32Array()
	t3.resize(nv)
	w.resize(nv)
	if a[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
		for i in nv:
			t3[i] = Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])
			w[i] = t[i * 4 + 3]
	else:
		t3.fill(Vector3(1, 0, 0))
		w.fill(1.0)
	var tri := PackedVector3Array()
	if a[Mesh.ARRAY_INDEX] != null:
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		tri.resize(ix.size() / 3)
		for i in tri.size():
			tri[i] = Vector3(ix[i * 3], ix[i * 3 + 1], ix[i * 3 + 2])
	else:
		tri.resize(nv / 3)
		for i in tri.size():
			tri[i] = Vector3(i * 3, i * 3 + 1, i * 3 + 2)
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if uv.size() != nv:
		uv.resize(nv)
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	if nr.size() != nv:
		nr.resize(nv)
		nr.fill(Vector3.UP)
	part_list.append([v, nr, t3, w, uv, tri, nv, null])
	parts[key] = part_list.size() - 1
	return part_list.size() - 1


## TILE copies of a part's arrays in a row: [normals, tangent directions, signs, uvs, triangles].
func _tiled(p: Array) -> Array:
	if p[P_TILED] == null:
		var nv: int = p[P_NV]
		var out := []
		for k in [P_N, P_T, P_W, P_UV]:
			var one = p[k]
			var many = one.duplicate()
			for i in TILE - 1:
				many.append_array(one)
			out.append(many)
		var tri: PackedVector3Array = (p[P_TRI] as PackedVector3Array).duplicate()
		for i in range(1, TILE):
			var o := float(i * nv)
			tri.append_array(Transform3D(Basis.IDENTITY, Vector3(o, o, o)) * (p[P_TRI] as PackedVector3Array))
		out.append(tri)
		p[P_TILED] = out
	return p[P_TILED]


func _basis_id(b: Basis) -> int:
	var id = basis_ids.get(b)
	if id == null:
		id = basis_list.size()
		basis_list.append(b)
		basis_ids[b] = id
	return id


func _tint_id(c: Color) -> int:
	var id = tint_ids.get(c)
	if id == null:
		id = tint_list.size()
		tint_list.append(c)
		tint_fill.append(PackedColorArray())
		tint_ids[c] = id
	return id


## Note a copy of part `pid` for the mesh being made under `key` in `level`: turned as basis `bid`, standing at o.
## tint: every vertex takes that colour (window panes: 1 for dark glass, else the light of the room); 0 = none.
func _put(level: Dictionary, key: String, pid: int, bid: int, o: Vector3, tint := 0) -> void:
	var b: Buf = level.get(key)
	if b == null:
		b = Buf.new()
		level[key] = b
	var gk := Vector3i(pid, bid, tint)
	var g = b.groups.get(gk)
	if g == null:
		g = PackedVector3Array()
		b.groups[gk] = g
	g.append(o)


## One surface of the finished mesh from what was noted in b.
func _buf_surface(am: ArrayMesh, b: Buf) -> void:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var T := PackedVector3Array()
	var W := PackedFloat32Array()
	var UV := PackedVector2Array()
	var TRI := PackedVector3Array()
	var COL := PackedColorArray()
	for gk in b.groups:
		var p: Array = part_list[gk.x]
		var basis: Basis = basis_list[gk.y]
		var rot := Transform3D(basis, Vector3.ZERO)
		var org: PackedVector3Array = b.groups[gk]
		var v: PackedVector3Array = p[P_V]
		var nv: int = p[P_NV]
		var nt: int = (p[P_TRI] as PackedVector3Array).size()
		var k := org.size()
		var done := 0
		while done < k:
			var c := mini(TILE, k - done)
			var base := float(V.size()) + BIAS
			for j in c:
				V.append_array(Transform3D(basis, org[done + j]) * v)
			if c == 1:
				N.append_array(rot * (p[P_N] as PackedVector3Array))
				T.append_array(rot * (p[P_T] as PackedVector3Array))
				W.append_array(p[P_W])
				UV.append_array(p[P_UV])
				TRI.append_array(Transform3D(Basis.IDENTITY, Vector3(base, base, base)) * (p[P_TRI] as PackedVector3Array))
			else:
				var tl := _tiled(p)
				if c == TILE:
					N.append_array(rot * (tl[0] as PackedVector3Array))
					T.append_array(rot * (tl[1] as PackedVector3Array))
					W.append_array(tl[2])
					UV.append_array(tl[3])
					TRI.append_array(Transform3D(Basis.IDENTITY, Vector3(base, base, base)) * (tl[4] as PackedVector3Array))
				else:
					N.append_array(rot * (tl[0] as PackedVector3Array).slice(0, c * nv))
					T.append_array(rot * (tl[1] as PackedVector3Array).slice(0, c * nv))
					W.append_array((tl[2] as PackedFloat32Array).slice(0, c * nv))
					UV.append_array((tl[3] as PackedVector2Array).slice(0, c * nv))
					TRI.append_array(Transform3D(Basis.IDENTITY, Vector3(base, base, base)) * (tl[4] as PackedVector3Array).slice(0, c * nt))
			if gk.z > 0:
				var fill: PackedColorArray = tint_fill[gk.z]
				if fill.size() < c * nv:
					fill.resize(maxi(c * nv, 256))
					fill.fill(tint_list[gk.z])
				COL.append_array(fill.slice(0, c * nv))
			done += c
	var nv_all := V.size()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_TEX_UV] = UV
	if COL.size() == nv_all:
		arr[Mesh.ARRAY_COLOR] = COL
	# tangents want four floats a vertex (direction, sign). An image does the weaving: three "pixels" of four bytes
	# a row are a direction's floats; widened to four, the signs go in as the last column.
	var ti := Image.create_from_data(3, nv_all, false, Image.FORMAT_RGBA8, T.to_byte_array())
	ti.crop(4, nv_all)
	ti.blit_rect(Image.create_from_data(1, nv_all, false, Image.FORMAT_RGBA8, W.to_byte_array()), Rect2i(0, 0, 1, nv_all), Vector2i(3, 0))
	arr[Mesh.ARRAY_TANGENT] = ti.get_data().to_float32_array()
	# triangles: each vertex number is a float, 2^23 + number: its low three bytes are the number, the fourth is
	# not. Seen as rows of four one-byte pixels, the fourth column is painted black, and the bytes are the same
	# numbers as 32-bit integers.
	var ni := TRI.size() * 3
	var ii := Image.create_from_data(4, ni, false, Image.FORMAT_R8, TRI.to_byte_array())
	ii.fill_rect(Rect2i(3, 0, 1, ni), Color(0, 0, 0))
	arr[Mesh.ARRAY_INDEX] = ii.get_data().to_int32_array()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)


# ---- the pieces ----
## A piece put together from flat rectangles.
class Rects:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedVector3Array()
	var w := PackedFloat32Array()
	var uv := PackedVector2Array()
	var tri := PackedVector3Array()

	## A rectangle: middle c, facing nn; half as wide as hu along uu (to the right, seen from in front), half as
	## high as hv. Its texture repeats every 3 m as the plaster's does, or lies once over the rectangle (whole).
	func quad(c: Vector3, nn: Vector3, uu: Vector3, hu: float, hv: float, whole := false) -> void:
		var up := nn.cross(uu)
		var b0 := float(v.size())
		for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector3 = c + uu * (hu * k.x) + up * (hv * k.y)
			v.append(p)
			n.append(nn)
			t.append(uu)
			w.append(1.0)
			uv.append(Vector2(k.x * 0.5 + 0.5, 0.5 - k.y * 0.5) if whole else Vector2(p.dot(uu) / 3.0, -p.dot(up) / 3.0))
		tri.append(Vector3(b0, b0 + 2, b0 + 1))
		tri.append(Vector3(b0, b0 + 3, b0 + 2))

	## A flat surround facing +z at depth z: rectangle `outer` (x along the bay, y up) less the hole `inner`.
	## open_foot: the hole reaches the ground (a doorway), so there is no strip under it.
	func surround(outer: Rect2, inner: Rect2, z: float, open_foot := false) -> void:
		var b0 := float(v.size())
		for r in [outer, inner]:
			for k in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var p := Vector3(r.position.x + r.size.x * k.x, r.position.y + r.size.y * k.y, z)
				v.append(p)
				n.append(Vector3(0, 0, 1))
				t.append(Vector3(1, 0, 0))
				w.append(1.0)
				uv.append(Vector2(p.x / 3.0, -p.y / 3.0))
		# the strips right of, over and left of the hole (and under it): each as its corners low left, low right,
		# high right, high left, by number (0-3 the outer corners, 4-7 the hole's)
		var strips := [[5, 1, 2, 6], [7, 6, 2, 3], [0, 4, 7, 3]]
		if not open_foot:
			strips.append([0, 1, 5, 4])
		for q in strips:
			tri.append(Vector3(b0 + q[0], b0 + q[2], b0 + q[1]))
			tri.append(Vector3(b0 + q[0], b0 + q[3], b0 + q[2]))

	## The sides of a hole through the wall, from its face back to depth d.
	func reveal(h: Rect2, d: float, open_foot := false) -> void:
		var m := h.get_center()
		quad(Vector3(h.position.x, m.y, -d * 0.5), Vector3(1, 0, 0), Vector3(0, 0, -1), d * 0.5, h.size.y * 0.5)
		quad(Vector3(h.end.x, m.y, -d * 0.5), Vector3(-1, 0, 0), Vector3(0, 0, 1), d * 0.5, h.size.y * 0.5)
		quad(Vector3(m.x, h.end.y, -d * 0.5), Vector3(0, -1, 0), Vector3(1, 0, 0), h.size.x * 0.5, d * 0.5)
		if not open_foot:
			quad(Vector3(m.x, h.position.y, -d * 0.5), Vector3(0, 1, 0), Vector3(1, 0, 0), h.size.x * 0.5, d * 0.5)

	## The box from a to b, those of its faces named in `sides`: f(ront, +z), b(ack), l(eft, -x), r(ight), t(op), u(nder).
	func box(a: Vector3, b: Vector3, sides: String) -> void:
		var c := (a + b) * 0.5
		var h := (b - a) * 0.5
		if sides.contains("f"):
			quad(Vector3(c.x, c.y, b.z), Vector3(0, 0, 1), Vector3(1, 0, 0), h.x, h.y)
		if sides.contains("b"):
			quad(Vector3(c.x, c.y, a.z), Vector3(0, 0, -1), Vector3(-1, 0, 0), h.x, h.y)
		if sides.contains("r"):
			quad(Vector3(b.x, c.y, c.z), Vector3(1, 0, 0), Vector3(0, 0, -1), h.z, h.y)
		if sides.contains("l"):
			quad(Vector3(a.x, c.y, c.z), Vector3(-1, 0, 0), Vector3(0, 0, 1), h.z, h.y)
		if sides.contains("t"):
			quad(Vector3(c.x, b.y, c.z), Vector3(0, 1, 0), Vector3(1, 0, 0), h.x, h.z)
		if sides.contains("u"):
			quad(Vector3(c.x, a.y, c.z), Vector3(0, -1, 0), Vector3(1, 0, 0), h.x, h.z)


const BAY := Rect2(-3.0, 0.0, 3.0, 3.0)             # a wall piece, seen from in front: x along the wall, y up
const DOOR_SMALL := Rect2(-2.25, 0.0, 1.5, 2.5)     # the street door of a block of flats
const DOOR_LARGE := Rect2(-2.4, 0.0, 1.8, 2.7)      # the doorway of a building that can be gone into
const REVEAL := 0.12                                # how deep windows and doors sit in the wall
const BAR := 0.06                                   # the width of a frame's bars
const DADO := 0.4                                   # the plinth's height
const CROWN := 0.7                                  # the parapet's


## The window of a bay: [its hole in the wall, panes across, panes up].
func _window(kind: String) -> Array:
	if kind.contains("double"):
		return [Rect2(-2.75, 0.42, 2.5, 1.8), 4, 1]
	if kind.contains("small"):
		return [Rect2(-2.35, 0.42, 1.7, 1.8), 2, 1]
	return [Rect2(-2.45, 0.42, 1.9, 1.8), 2, 2]


func _new_part(r: Rects) -> int:
	part_list.append([r.v, r.n, r.t, r.w, r.uv, r.tri, r.v.size(), null])
	return part_list.size() - 1


## The surfaces of piece `name`, made the first time it is asked for: [[kind, material key, part], ..].
func _piece(name: String) -> Array:
	var out = pieces.get(name)
	if out != null:
		return out
	out = []
	var r := Rects.new()
	if name.begins_with("wall_window_"):
		var h: Rect2 = _window(name)[0]
		r.surround(BAY, h, 0.0)
		r.reveal(h, REVEAL)
		out.append([0, "", _new_part(r)])
	elif name.begins_with("window_"):
		# a frame with thin bars between its panes, and one sheet of glass behind them all
		var wd := _window(name)
		var g: Rect2 = (wd[0] as Rect2).grow(-BAR)
		var z := -REVEAL + 0.035
		r.surround(wd[0], g, z)
		for i in range(1, wd[1]):
			r.quad(Vector3(g.position.x + g.size.x * i / wd[1], g.get_center().y, z), Vector3(0, 0, 1), Vector3(1, 0, 0), BAR * 0.4, g.size.y * 0.5)
		for j in range(1, wd[2]):
			r.quad(Vector3(g.get_center().x, g.position.y + g.size.y * j / wd[2], z), Vector3(0, 0, 1), Vector3(1, 0, 0), g.size.x * 0.5, BAR * 0.4)
		out.append([2, "k_frame", _new_part(r)])
		var pane := Rects.new()
		pane.quad(Vector3(g.get_center().x, g.get_center().y, z - 0.015), Vector3(0, 0, 1), Vector3(1, 0, 0), g.size.x * 0.5, g.size.y * 0.5, true)
		out.append([1, "k_glass", _new_part(pane)])
	elif name.begins_with("wall_door_"):
		var h := DOOR_LARGE if name.contains("large") else DOOR_SMALL
		r.surround(BAY, h, 0.0, true)
		r.reveal(h, REVEAL, true)
		out.append([0, "", _new_part(r)])
	elif name.begins_with("door_"):
		# a glazed double door: frame, kick plates, the stile where the leaves meet, a rail under the fanlight
		var h := DOOR_LARGE if name.contains("large") else DOOR_SMALL
		var g := Rect2(h.position.x + BAR, 0.0, h.size.x - BAR * 2.0, h.size.y - BAR)
		var z := -REVEAL + 0.035
		r.surround(h, g, z, true)
		r.quad(Vector3(g.get_center().x, 0.11, z), Vector3(0, 0, 1), Vector3(1, 0, 0), g.size.x * 0.5, 0.11)
		r.quad(Vector3(g.get_center().x, g.end.y * 0.5, z), Vector3(0, 0, 1), Vector3(1, 0, 0), BAR * 0.5, g.end.y * 0.5)
		r.quad(Vector3(g.get_center().x, 2.08, z), Vector3(0, 0, 1), Vector3(1, 0, 0), g.size.x * 0.5, BAR * 0.5)
		out.append([2, "k_frame", _new_part(r)])
		var pane := Rects.new()
		pane.quad(Vector3(g.get_center().x, g.end.y * 0.5, z - 0.015), Vector3(0, 0, 1), Vector3(1, 0, 0), g.size.x * 0.5, g.end.y * 0.5, true)
		out.append([1, "k_glass", _new_part(pane)])
	elif name.begins_with("dado_door_"):
		var h := DOOR_LARGE if name.contains("large") else DOOR_SMALL
		r.box(Vector3(-3.0, 0.0, 0.0), Vector3(h.position.x, DADO, 0.05), "ftr")
		r.box(Vector3(h.end.x, 0.0, 0.0), Vector3(0.0, DADO, 0.05), "ftl")
		out.append([2, "k_base", _new_part(r)])
	elif name.begins_with("dado_pier"):
		r.box(Vector3(-0.26, 0.0, -0.26), Vector3(0.09, DADO + 0.04, 0.09), "frlbt")
		out.append([2, "k_base", _new_part(r)])
	elif name.begins_with("dado_"):
		r.box(Vector3(-3.0, 0.0, 0.0), Vector3(0.0, DADO, 0.05), "ft")
		out.append([2, "k_base", _new_part(r)])
	elif name.begins_with("cornice_pier"):
		r.box(Vector3(-0.26, 0.0, -0.26), Vector3(0.09, 0.2, 0.09), "frlbtu")
		out.append([2, "k_band", _new_part(r)])
	elif name.begins_with("cornice_"):
		r.box(Vector3(-3.0, 0.0, 0.0), Vector3(0.0, 0.2, 0.05), "ftu")
		out.append([2, "k_band", _new_part(r)])
	elif name.begins_with("crown_pier"):
		r.box(Vector3(-0.3, 0.0, -0.3), Vector3(0.16, CROWN, 0.16), "frlbtu")
		out.append([2, "k_band", _new_part(r)])
	elif name.begins_with("crown_"):
		# the parapet: its face over the street, its top, its underside, and its back over the roof
		r.box(Vector3(-3.0, 0.0, -0.22), Vector3(0.0, CROWN, 0.12), "ftub")
		out.append([2, "k_band", _new_part(r)])
	elif name.begins_with("wall_pier_corner"):
		r.box(Vector3(-0.22, 0.0, -0.22), Vector3(0.05, 3.0, 0.05), "frlb")
		out.append([0, "", _new_part(r)])
	elif name.begins_with("wall_pier_"):
		r.box(Vector3(-0.125, 0.0, 0.0), Vector3(0.125, 3.0, 0.05), "flr")
		out.append([0, "", _new_part(r)])
	else:
		if name != "wall_standard_standard_01":
			push_warning("no such building piece: " + name + " (a plain wall stands in)")
		r.quad(Vector3(-1.5, 1.5, 0.0), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.5, 1.5)
		out.append([0, "", _new_part(r)])
	pieces[name] = out
	return out


## Put piece `name` at xf into the buildings being made. Plaster takes the building's tone; panes are dark, or lit
## with colour `lit`; glass false: the pane is gone (an empty frame).
func piece(name: String, xf: Transform3D, tone: int, lit := Color(0, 0, 0), glass := true) -> void:
	var bid := _basis_id(xf.basis)
	var o := xf.origin
	var plaster: String = PLASTER_KEY[tone]
	for sf in _piece(name):
		if sf[0] == 0:
			_put(detail, plaster, sf[2], bid, o)
		elif sf[0] == 2:
			_put(detail, sf[1], sf[2], bid, o)
		elif glass:
			var tint := 1 if lit == Color(0, 0, 0) else _tint_id(lit)
			_put(detail, "k_glass", sf[2], bid, o, tint)
			_put(plain, "k_glass", sf[2], bid, o + xf.basis.z.normalized() * 0.2, tint)
	# from far off: a plain wall for every wall piece with the panes laid on it; no frames, bands or piers
	if name.begins_with("wall_") and not name.begins_with("wall_pier"):
		_put(plain, plaster, _piece("wall_standard_standard_01")[0][2], bid, o)


## A mesh of a Poly Haven prop (node of its scene), without the offset it has in the prop's scene.
func _prop_mesh(scene: String, node: String) -> Array:
	var k := scene + ":" + node
	if not prop_meshes.has(k):
		var root: Node = load(scene).instantiate()
		var mi: MeshInstance3D = root.find_child(node, true, false)
		prop_meshes[k] = [mi.mesh, Transform3D(mi.transform.basis, Vector3.ZERO)]
		root.free()
	return prop_meshes[k]


## A prop's model (a roller shutter, an air conditioner) joined into the buildings. far_too: it is seen from far
## off as well (the shutters: a shop front is a big thing).
func prop_piece(scene: String, node: String, xf: Transform3D, far_too := false) -> void:
	var pm := _prop_mesh(scene, node)
	var m: Mesh = pm[0]
	var at: Transform3D = xf * pm[1]
	var bid := _basis_id(at.basis)
	for s in m.get_surface_count():
		var mat: Material = m.surface_get_material(s)
		var key := "p_" + mat.resource_name
		if not mats.has(key):
			mats[key] = mat
		var pid := _part(m, s)
		_put(detail, key, pid, bid, at.origin)
		if far_too:
			_put(plain, key, pid, bid, at.origin)


## The buildings made so far, as two meshes that take turns by distance: as built, and (beyond KIT_FAR) plain
## walls with their panes on them.
func commit_kit(shadows := true, _far_shadows := false, reach := 0.0) -> void:
	# reach: half the size of a big building (the distances are measured from its middle)
	for li in 2:
		var level: Dictionary = detail if li == 0 else plain
		if level.is_empty():
			continue
		var am := ArrayMesh.new()
		for key in level:
			_buf_surface(am, level[key])
			am.surface_set_material(am.get_surface_count() - 1, mats[key])
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and li == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if li == 0:
			mi.visibility_range_end = (KIT_FAR + reach)
			mi.visibility_range_end_margin = 5.0
		else:
			mi.visibility_range_begin = (KIT_FAR + reach)
			mi.visibility_range_begin_margin = 5.0
			mi.visibility_range_end = KIT_GONE
		main.add_child(mi)
	detail = {}
	plain = {}
	for bx in occluders:
		var oc := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = bx.size
		oc.occluder = bo
		main.add_child(oc)
		oc.global_position = bx.get_center()
	occluders.clear()


const ROOM_LIGHT := [Color(1.0, 0.7, 0.4), Color(1.0, 0.82, 0.6), Color(0.82, 0.88, 1.0), Color(0.35, 0.5, 0.95)]
var lit_share := 0.3
var ac_share := 0.05


func _lit() -> Color:
	if not night or rng.randf() > lit_share:
		return Color(0, 0, 0)
	var r := rng.randf()
	var c: Color = ROOM_LIGHT[0 if r < 0.45 else (1 if r < 0.7 else (2 if r < 0.88 else 3))]
	return c * snappedf(rng.randf_range(0.45, 0.85), 0.1)      # (a few brightnesses: lit panes of one kind join as one)


func _wname(kind: String, row: int, i: int) -> String:
	if kind == "offset_small":
		return "offset_small_0%d" % (row * 2 - 1 + (i % 2))
	return "%s_0%d" % [kind, row]


## A block of flats from the scanned kit over (x0, z0)-(x1, z1): `floors` storeys of 3 m under a moulded crown, a
## cornice over the ground floor. Ground floor shops (roller shutters, name boards, a few open and lit) on the sides in
## `shops`, a front door on the others. `blank`: sides against a neighbour, plain plaster.
func apartment(x0: float, z0: float, x1: float, z1: float, floors: int, shops := [], blank := [], opts := {}) -> void:
	var tone: int = opts.get("tone", block_tones[rng.randi() % block_tones.size()] if not block_tones.is_empty() else rng.randi() % PLASTER.size())
	var wins: Array = opts.get("wins", WINDOW_SETS[rng.randi() % WINDOW_SETS.size()])
	var row: int = opts.get("row", [2, 2, 3, 1][rng.randi() % 4])
	var h := floors * 3.0
	dmg = opts.get("damage", [])
	if not dmg.is_empty():
		# shell holes: what shows through them: the floor slabs' edges and a dark inner wall a room's depth in
		var low := h
		for dm in dmg:
			low = min(low, (dm[0] as Vector3).y - float(dm[1]))
		var inset := 2.6
		if x1 - x0 > inset * 2.0 + 1.0 and z1 - z0 > inset * 2.0 + 1.0:
			box("m3_inner", Vector3((x0 + x1) * 0.5, h * 0.5 - 0.2, (z0 + z1) * 0.5), Vector3(x1 - x0 - inset * 2.0, h - 0.4, z1 - z0 - inset * 2.0), 0.0, Color(0.5, 0.48, 0.46))
		for f in range(maxi(1, int(floor(low / 3.0))), floors + 1):
			box("m3_slab", Vector3((x0 + x1) * 0.5, f * 3.0 - 0.14, (z0 + z1) * 0.5), Vector3(x1 - x0 - 0.12, 0.26, z1 - z0 - 0.12), 0.0, Color(0.72, 0.72, 0.72))
	var sides := {"s": [Vector3(0, 0, 1), Vector3(x0, 0, z1), x1 - x0], "n": [Vector3(0, 0, -1), Vector3(x1, 0, z0), x1 - x0],
		"e": [Vector3(1, 0, 0), Vector3(x1, 0, z1), z1 - z0], "w": [Vector3(-1, 0, 0), Vector3(x0, 0, z0), z1 - z0]}
	for side in sides:
		var sd: Array = sides[side]
		var n: Vector3 = sd[0]
		var X := Vector3.UP.cross(n)
		var A: Vector3 = sd[1]
		var L: float = sd[2]
		if side in blank:
			face("kq_plaster%d" % tone, A + X * (L * 0.5) + Vector3(0, h * 0.5, 0), X * (L * 0.5), Vector3.UP * (h * 0.5))
			box("k_roof", A + X * (L * 0.5) + Vector3(0, h + 0.35, 0) - n * 0.15, Vector3(L, 0.7, 0.3), atan2(n.x, n.z))
			continue
		_kit_side(A, X, n, L, floors, wins, row, side in shops, tone)
	# the flat roof inside the parapet: a stair head, black water tanks
	var c := Vector3((x0 + x1) * 0.5, h, (z0 + z1) * 0.5)
	face("k_roof", c + Vector3(0, 0.08, 0), Vector3((x1 - x0) * 0.5, 0, 0), Vector3(0, 0, -(z1 - z0) * 0.5))
	occluders.append(AABB(Vector3(x0 + 0.3, 0, z0 + 0.3), Vector3(x1 - x0 - 0.6, h - 0.3, z1 - z0 - 0.6)))
	if opts.get("bare_roof", false):
		collider(c - Vector3(0, h * 0.5, 0), Vector3(x1 - x0, h, z1 - z0))
		footprints.append(Rect2(x0, z0, x1 - x0, z1 - z0))
		return
	var sh := Vector3(c.x + (x1 - x0) * 0.2, h, c.z - (z1 - z0) * 0.15)
	box("kq_plaster%d" % tone, sh + Vector3(0, 1.3, 0), Vector3(2.6, 2.6, 3.0))
	for k in rng.randi_range(1, 3):
		cyl("dark", Vector3(c.x - (x1 - x0) * 0.25 + k * 1.6, h + 0.1, c.z + (z1 - z0) * 0.2), 0.62, 1.3, 12, Color(0.08, 0.08, 0.09))
	collider(c - Vector3(0, h * 0.5, 0), Vector3(x1 - x0, h, z1 - z0))
	footprints.append(Rect2(x0, z0, x1 - x0, z1 - z0))


func _kit_side(A: Vector3, X: Vector3, n: Vector3, L: float, floors: int, wins: Array, row: int, shops: bool, tone: int) -> void:
	var k := maxi(1, roundi(L / 3.0))
	var w := L / k
	var b := Basis(X * (w / 3.0), Vector3.UP, n)
	var b1 := Basis(X, Vector3.UP, n)
	var door := -1 if shops else k / 2
	var gone := {}          # bays shot away: Vector2i(bay, floor)
	# the dark of the rooms, a little way in: what is seen through a window whose glass is gone. (Not behind a row
	# of shops, which have insides of their own; nor in a shelled building, which shows its floors.)
	var foot := 3.0 if shops else 0.0
	if dmg.is_empty() and floors * 3.0 > foot:
		face("k_void", A + X * (L * 0.5) + Vector3(0, (foot + floors * 3.0) * 0.5, 0) - n * 0.3, X * (L * 0.5), Vector3.UP * ((floors * 3.0 - foot) * 0.5))
	for f in floors:
		for i in k:
			var o: Vector3 = A + X * (w * (i + 1)) + Vector3(0, f * 3.0, 0)
			var xf := Transform3D(b, o)
			var mid: Vector3 = o - X * (w * 0.5) + Vector3(0, 1.5, 0)
			for dm in dmg:
				if mid.distance_to(dm[0]) < float(dm[1]) * (0.85 + 0.3 * rng.randf()):
					gone[Vector2i(i, f)] = true
			if gone.has(Vector2i(i, f)):
				continue
			if f == 0:
				if shops:
					_shop_bay(o, X, n, w, tone)
				elif i == door:
					piece("wall_door_centered_small_01", xf, tone)
					piece("door_centered_small_01", xf, tone)
					piece("dado_door_centered_small_01", xf, tone)
				else:
					var g0: String = _wname(wins[i % wins.size()], 3, i)
					piece("wall_window_" + g0, xf, tone)
					piece("window_" + g0, xf, tone, _lit())
					piece("dado_standard_standard_01", xf, tone)
				continue
			var g: String = _wname(wins[i % wins.size()], row, i)
			piece("wall_window_" + g, xf, tone)
			piece("window_" + g, xf, tone, _lit(), rng.randf() >= broken_share)
			if soot_share > 0.0 and rng.randf() < soot_share:
				soot(mid + Vector3(0, 1.6, 0), X, n, w * 0.8, 2.6)
			# an air conditioner on the wall over some windows
			if rng.randf() < ac_share:
				prop_piece(AIRCON_SCENE, "exterior_aircon_unit",
					Transform3D(b1, o - X * (w * 0.5 + (0.55 if row != 1 else -0.55)) + Vector3(0, 2.3, 0) + n * 0.22))
	for i in k:
		var o2: Vector3 = A + X * (w * (i + 1))
		if not gone.has(Vector2i(i, 0)):
			piece("cornice_standard_standard_01", Transform3D(b, o2 + Vector3(0, 2.92, 0)), tone)
		if not gone.has(Vector2i(i, floors - 1)):
			piece("crown_standard_standard_01", Transform3D(b, o2 + Vector3(0, floors * 3.0, 0)), tone)
	# the corner where this side ends: a pilaster up every storey, capped
	var B := A + X * L
	for f in floors:
		if not gone.has(Vector2i(k - 1, f)):
			piece("wall_pier_corner_01", Transform3D(b1, B + Vector3(0, f * 3.0, 0)), tone)
	if not gone.has(Vector2i(k - 1, 0)):
		piece("dado_pier_corner_01", Transform3D(b1, B), tone)
		piece("cornice_pier_corner_01", Transform3D(b1, B + Vector3(0, 2.92, 0)), tone)
	if not gone.has(Vector2i(k - 1, floors - 1)):
		piece("crown_pier_corner_01", Transform3D(b1, B + Vector3(0, floors * 3.0, 0)), tone)


## One ground floor shop bay ending at o (it runs back along X for w): a pilaster, the name board, and the roller
## shutter: down (curfew) on most, up on a few with the shop lit inside.
func _shop_bay(o: Vector3, X: Vector3, n: Vector3, w: float, tone: int) -> void:
	var b1 := Basis(X, Vector3.UP, n)
	var c := o - X * (w * 0.5)
	piece("wall_pier_standard_01", Transform3D(b1, o), tone)
	# plaster above the opening and the board on it
	face("kq_plaster%d" % tone, c + Vector3(0, 2.75, 0), X * (w * 0.5), Vector3.UP * 0.25)
	sign_board(c + Vector3(0, 2.74, 0) + n * 0.05, X, n, w - 0.45, (w - 0.45) / 8.0 * 1.0 + 0.1, rng.randi() % SIGN_ROWS)
	var sw := (w - 0.2) / 1.08
	var open_ := night and rng.randf() < 0.14
	if Vector2(c.x - force_open.x, c.z - force_open.z).length() < w * 0.5 and opened_bay.is_empty():
		open_ = true
		opened_bay = [c, X, n, w]
	var node := "rollershutter_door" if rng.randf() < 0.7 else "rollershutter_door_graffiti"
	if open_:
		# shutter rolled up into its box; the shop inside: lit back wall, shelves, a counter
		prop_piece(SHUTTER_SCENE, node, Transform3D(Basis(X * sw, Vector3.UP * 0.18, n), c + Vector3(0, 2.05, 0)), true)
		var dpt := 1.6
		var wallc: Color = [Color(0.9, 0.88, 0.82), Color(0.75, 0.85, 0.8), Color(0.85, 0.8, 0.7)][rng.randi() % 3]
		face("k_shop", c - n * dpt + Vector3(0, 1.2, 0), X * (w * 0.5 - 0.1), Vector3.UP * 1.2, wallc)
		face("k_shop", c - n * (dpt * 0.5) + Vector3(0, 0.01, 0), X * (w * 0.5 - 0.1), -n * (dpt * 0.5), Color(0.45, 0.42, 0.38))
		face("k_shop", c - n * (dpt * 0.5) + Vector3(0, 2.4, 0), X * (w * 0.5 - 0.1), n * (dpt * 0.5), Color(1, 1, 1))
		box("bulb", c - n * (dpt * 0.5) + Vector3(0, 2.38, 0), Vector3(1.2, 0.04, 0.08), atan2(n.x, n.z))
		for sgn in [-1.0, 1.0]:
			face("k_shop", c + X * (sgn * (w * 0.5 - 0.1)) - n * (dpt * 0.5) + Vector3(0, 1.2, 0), n * (dpt * 0.5) * sgn, Vector3.UP * 1.2, wallc.darkened(0.25))
		for sy in [0.5, 1.1, 1.7]:
			box("dark", c - n * (dpt - 0.2) + Vector3(0, sy, 0), Vector3(w - 0.6, 0.05, 0.35), atan2(n.x, n.z), Color(0.2, 0.18, 0.16))
			var q := -w * 0.42
			while q < w * 0.4:
				var bw := rng.randf_range(0.08, 0.22)
				var bh := rng.randf_range(0.12, 0.42)
				box("k_shop", c - n * (dpt - 0.2) + X * (q + bw * 0.5) + Vector3(0, sy + 0.025 + bh * 0.5, 0), Vector3(bw, bh, rng.randf_range(0.12, 0.3)), atan2(n.x, n.z),
					[Color(0.75, 0.25, 0.18), Color(0.92, 0.85, 0.55), Color(0.25, 0.45, 0.75), Color(0.95, 0.95, 0.95), Color(0.3, 0.6, 0.35), Color(0.9, 0.55, 0.2)][rng.randi() % 6])
				q += bw + rng.randf_range(0.0, 0.05)
		box("dark", c - n * 0.6 + Vector3(0, 0.5, 0) + X * (w * 0.15), Vector3(w * 0.45, 1.0, 0.5), atan2(n.x, n.z), Color(0.25, 0.22, 0.2))
		pool(c + n * 2.0, Color(0.3, 0.26, 0.2, 1), 3.0)
	else:
		prop_piece(SHUTTER_SCENE, node, Transform3D(Basis(X * sw, Vector3.UP * (2.45 / 2.4), n), c), true)


# =============== mission 3: a city after the fighting ===============
const TEX3 := "res://assets/city/tex3/"


## A scanned surface (Poly Haven, CC0) as a material: key, texture id, tint, how many times it repeats per metre,
## roughness. Faces drawn with it are shaded by their colour too (dark for indoors).
## glow: a share of the surface's own colour given off as light: daylight bounced round a room, which this renderer
## cannot work out (without it a room with no lamp is black).
func mat3(key: String, id: String, tint := Color(1, 1, 1), per_m := 0.5, rough := 0.9, glow := 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX3 + id + "_diff.jpg")
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = tint
		m.emission_texture = m.albedo_texture
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_energy_multiplier = glow
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX3 + id + "_nor.jpg")
	m.roughness = rough
	m.uv1_scale = Vector3(per_m, per_m, per_m)
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats[key] = m


func make_mats3() -> void:
	if mats.has("m3_slab"):
		return
	mat3("m3_slab", "concrete_wall_008", Color(0.8, 0.8, 0.8), 0.4)
	mat3("m3_inner", "damaged_plaster", Color(0.55, 0.55, 0.55), 0.3)
	mat3("m3_tiles", "floor_tiles_06", Color(1, 1, 1), 0.5, 0.55, 0.16)
	mat3("m3_brown_tiles", "tiled_floor_001", Color(1, 1, 1), 0.5, 0.6, 0.16)
	mat3("m3_white_tiles", "long_white_tiles", Color(0.95, 0.97, 0.95), 0.6, 0.45, 0.2)
	mat3("m3_paint", "pale_paint", Color(1, 1, 1), 0.35, 0.9, 0.16)
	mat3("m3_salmon", "peeling_painted_wall", Color(1, 1, 1), 0.35, 0.9, 0.2)
	mat3("m3_green", "pale_paint", Color(0.74, 0.78, 0.66), 0.35, 0.9, 0.14)
	mat3("m3_plaster", "damaged_plaster", Color(1, 1, 1), 0.3, 0.9, 0.16)
	mat3("m3_ceiling", "white_ceiling", Color(1, 1, 1), 0.5, 1.0, 0.2)
	(mats["m3_ceiling"] as StandardMaterial3D).normal_scale = 0.35
	mat3("m3_floor", "concrete_floor_worn_001", Color(1, 1, 1), 0.3, 0.75, 0.16)
	mat3("m3_stair", "concrete_wall_008", Color(0.9, 0.9, 0.9), 0.4, 0.9, 0.2)
	mat3("m3_linen", "rough_linen", Color(1, 1, 1), 1.2, 1.0, 0.2)
	mat3("m3_dark_floor", "concrete_floor_worn_001", Color(0.8, 0.8, 0.8), 0.3, 0.8, 0.05)
	mat3("m3_dark_wall", "concrete_wall_008", Color(0.75, 0.75, 0.75), 0.33, 0.9, 0.05)
	mat3("m3_concrete", "concrete_wall_008", Color(1, 1, 1), 0.33)
	mat3("m3_iron", "corrugated_iron_02", Color(1, 1, 1), 0.5, 0.6, 0.1)
	mat3("m3_rusty", "rusty_corrugated_iron", Color(1, 1, 1), 0.5, 0.75, 0.08)
	mat3("m3_brick", "factory_brick", Color(1, 1, 1), 0.5, 0.9, 0.1)
	mat3("m3_rubble", "rubble", Color(0.9, 0.88, 0.85), 0.4, 1.0)
	mat3("m3_debris", "concrete_debris", Color(0.8, 0.82, 0.86), 0.5, 1.0)
	mat3("m3_cracked", "cracked_concrete", Color(0.8, 0.8, 0.8), 0.33, 0.95)
	mat3("m3_road", "road_damaged", Color(0.75, 0.75, 0.75), 0.2, 0.9)
	mat3("m3_burnt", "burned_ground_01", Color(0.5, 0.48, 0.46), 0.3, 1.0)
	mat3("m3_plate", "metal_plate", Color(1, 1, 1), 0.8, 0.5)
	mat3("m3_rust", "rusty_metal_02", Color(0.8, 0.8, 0.8), 0.5, 0.8)
	(mats["m3_plate"] as StandardMaterial3D).metallic = 0.5
	(mats["m3_iron"] as StandardMaterial3D).metallic = 0.4
	# smoke stains and scorch marks: a soft dark blot laid over a surface
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := (x - 31.5) / 32.0
			var t := y / 63.0                      # 0 at the top (thin), 1 at the bottom (the window's head)
			var wd: float = lerp(0.35, 1.0, t)
			var a: float = clamp(1.0 - abs(dx) / wd, 0.0, 1.0) * pow(t, 1.4)
			img.set_pixel(x, y, Color(0.03, 0.03, 0.03, a * 0.85))
	var so := StandardMaterial3D.new()
	so.albedo_texture = ImageTexture.create_from_image(img)
	so.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	so.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	so.uv1_scale = Vector3(1, 1, 1)
	mats["m3_soot"] = so
	var img2 := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			img2.set_pixel(x, y, Color(0.02, 0.02, 0.02, clamp(1.0 - d, 0.0, 1.0) * 0.9))
	var sc := StandardMaterial3D.new()
	sc.albedo_texture = ImageTexture.create_from_image(img2)
	sc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mats["m3_scorch"] = sc
	# daylight in a window seen from indoors, and the cold tube of a strip light
	var day := StandardMaterial3D.new()
	day.albedo_color = Color(0.75, 0.8, 0.82)
	day.emission_enabled = true
	day.emission = Color(0.8, 0.86, 0.9)
	day.emission_energy_multiplier = 1.3
	mats["m3_daylight"] = day
	var white := StandardMaterial3D.new()
	white.vertex_color_use_as_albedo = true
	white.roughness = 0.7
	mats["m3_paintwork"] = white


## A stain of smoke up a wall from the head of a window: centre c, on the face looking along n.
func soot(c: Vector3, X: Vector3, n: Vector3, w: float, h: float) -> void:
	var st := _st("m3_soot")
	var p := [c - X * (w * 0.5) - Vector3.UP * (h * 0.5), c + X * (w * 0.5) - Vector3.UP * (h * 0.5), c + X * (w * 0.5) + Vector3.UP * (h * 0.5), c - X * (w * 0.5) + Vector3.UP * (h * 0.5)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(Color(1, 1, 1))
		st.set_normal(n)
		st.set_uv(uv[i])
		st.add_vertex(p[i] + n * 0.03)


## A flat mark on the ground (a scorch, an oil stain): the whole texture once over a square of side `size`.
func decal(key: String, c: Vector3, size: float, yaw := 0.0) -> void:
	var st := _st(key)
	var b := Basis(Vector3.UP, yaw)
	var hx: Vector3 = b.x * size * 0.5
	var hz: Vector3 = b.z * size * 0.5
	var p := [c - hx + hz, c + hx + hz, c + hx - hz, c - hx - hz]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(Color(1, 1, 1))
		st.set_normal(Vector3.UP)
		st.set_uv(uv[i])
		st.add_vertex(p[i])
