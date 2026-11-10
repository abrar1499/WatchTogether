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


func _st(key: String) -> SurfaceTool:
	if not sts.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[key] = st
	return sts[key]


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
func commit(shadows := true) -> MeshInstance3D:
	var am := ArrayMesh.new()
	for key in sts:
		var st: SurfaceTool = sts[key]
		if key != "curtain" and key != "k_sign":
			st.generate_tangents()
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
	sts.clear()
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	return mi


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
func glow(p: Vector3, col: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = _glow_material(col, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	mi.global_position = p


## The pool of light a lamp throws on the ground.
func pool(p: Vector3, col: Color, r: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = _glow_material(col, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	mi.global_position = p + Vector3(0, 0.06, 0)


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
	l.omni_range = 22.0
	l.omni_attenuation = 1.3
	main.add_child(l)
	l.global_position = c
	glow(c, Color(0.85, 0.75, 0.6, 0.8), 2.2)
	pool(Vector3(c.x, p.y, c.z), Color(0.3, 0.26, 0.2, 1.0), 6.5)


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
	box("led", ad, Vector3(0.06, 1.8, 1.2), yaw, LEDS[rng.randi() % LEDS.size()].lerp(Color(1, 1, 1), 0.5))
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


# =============== real buildings: the scanned apartment kit ===============
## Poly Haven's "Modular Urban Apartments Facade" (CC0, photo-scanned), simplified for phones by tools/citybuild
## (kit_lod.py, then kitbake.gd). Every wall piece is one 3 x 3 m bay (local x -3..0, y 0..3, facing +z) and its window
## or door fits the same frame. A building is assembled twice, from the near pieces and from the light ones; the two
## meshes swap at KIT_SWAP metres. Props from the same library (roller shutters, air conditioners, lamps) join in.
const KIT := "res://assets/city/kit/"
const KIT_SWAP := 40.0
const PLASTER := [Color(0.93, 0.9, 0.84), Color(0.84, 0.83, 0.8), Color(0.96, 0.87, 0.74), Color(0.76, 0.75, 0.72),
	Color(0.93, 0.83, 0.78), Color(0.8, 0.84, 0.86), Color(0.9, 0.9, 0.9), Color(0.82, 0.76, 0.66)]
const WINDOW_SETS := [["centered_large"], ["centered_small"], ["centered_double"], ["centered_large", "centered_small"],
	["offset_small"], ["centered_small", "centered_double", "centered_small"]]
const SIGN_BG := [Color(0.08, 0.32, 0.18), Color(0.55, 0.07, 0.06), Color(0.06, 0.16, 0.42), Color(0.92, 0.9, 0.86),
	Color(0.85, 0.62, 0.08), Color(0.12, 0.12, 0.13)]
const SHUTTER_SCENE := "res://assets/city/props/rollershutter_door/rollershutter_door_game.gltf"
const AIRCON_SCENE := "res://assets/city/props/exterior_aircon_unit/exterior_aircon_unit_game.gltf"
var kit := {}
var near := {}          # material key -> SurfaceTool: near pieces of the building being made
var far := {}
var prop_meshes := {}
var kit_ready := false
var shutter := "rollershutter_door"
var occluders: Array[AABB] = []


func _pbr(diff: String, nor: String, arm: String, tint: Color, uv := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(nor)
	m.roughness = 0.88
	if arm != "":
		m.roughness_texture = load(arm)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = 1.0
	m.uv1_scale = Vector3(uv, uv, uv)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _kit_mats() -> void:
	if kit_ready:
		return
	kit_ready = true
	var t := "res://assets/city/facade/textures/modular_urban_apartments_facade_"
	for i in PLASTER.size():
		mats["k_plaster%d" % i] = _pbr("res://assets/city/tex/plaster_grey_diff.jpg", t + "plaster_nor_gl_1k.jpg", "", PLASTER[i])
		# the same plaster on plain walls drawn here (uv in metres, the scan's bays are 3 m)
		mats["kq_plaster%d" % i] = _pbr("res://assets/city/tex/plaster_grey_diff.jpg", t + "plaster_nor_gl_1k.jpg", "", PLASTER[i], 1.0 / 3.0)
	mats["k_trim_01"] = _pbr("res://assets/city/tex/trim_01_grey_diff.jpg", t + "trim_01_nor_gl_1k.jpg", "", Color(0.92, 0.91, 0.88))
	var crown := _pbr("res://assets/city/tex/trim_02_grey_diff.jpg", t + "trim_02_nor_gl_1k.jpg", "", Color(0.9, 0.89, 0.86))
	crown.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["k_trim_02"] = crown
	mats["k_objects"] = _pbr(t + "objects_diff_1k.jpg", t + "objects_nor_gl_1k.jpg", "", Color(1, 1, 1))
	# every pane in one surface: dark reflecting glass, or a lit room (the vertex colour, set per window)
	var gs := Shader.new()
	gs.code = """shader_type spatial;
uniform float lit_energy = 1.5;
void fragment() {
	float lit = step(0.02, COLOR.r + COLOR.g + COLOR.b);
	ALBEDO = mix(vec3(0.03, 0.038, 0.046), COLOR.rgb * 0.2, lit);
	METALLIC = 0.65 * (1.0 - lit);
	ROUGHNESS = mix(0.06, 0.3, lit);
	EMISSION = COLOR.rgb * lit_energy;
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
	mats["g_asphalt"] = _pbr("res://assets/city/tex/asphalt_02_diff.jpg", "res://assets/city/tex/asphalt_02_nor.jpg", "", Color(0.78, 0.78, 0.78), 0.2)
	mats["g_worn"] = _pbr("res://assets/city/tex/worn_asphalt_diff.jpg", "res://assets/city/tex/worn_asphalt_nor.jpg", "", Color(0.8, 0.8, 0.8), 0.2)
	mats["g_pavers"] = _pbr("res://assets/city/tex/square_concrete_pavers_diff.jpg", "res://assets/city/tex/square_concrete_pavers_nor.jpg", "", Color(0.72, 0.72, 0.74), 0.4)
	mats["g_kerb"] = _pbr("res://assets/city/tex/concrete_pavement_diff.jpg", "res://assets/city/tex/concrete_pavement_nor.jpg", "", Color(0.85, 0.85, 0.83), 0.5)
	mats["g_wall"] = _pbr("res://assets/city/tex/concrete_wall_006_diff.jpg", "res://assets/city/tex/concrete_wall_006_nor.jpg", "", Color(0.85, 0.85, 0.83), 0.33)


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
	["ROYAL TAILORS", "GENTS & LADIES"], ["FRESH BAKERS", "CAKES  BREAD  SWEETS"], ["CHAI CORNER", "TEA  PARATHA"], ["GENERAL STORE", "GROCERY ITEMS"],
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


func _kit_mesh(name: String, lo: bool) -> ArrayMesh:
	var k := name + ("_lo" if lo else "")
	if not kit.has(k):
		kit[k] = load(KIT + k + ".res")
	return kit[k]


func _kst(d: Dictionary, key: String) -> SurfaceTool:
	if not d.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		d[key] = st
	return d[key]


## Put kit piece `name` at xf into the building being made, near and far. Plaster takes the building's tone; panes
## are dark, or lit with colour `lit`.
func piece(name: String, xf: Transform3D, tone: int, lit := Color(0, 0, 0)) -> void:
	for lo in [false, true]:
		var m := _kit_mesh(name, lo)
		for s in m.get_surface_count():
			var sn := m.surface_get_name(s)
			if sn == "glass":
				_kst(far if lo else near, "k_glass").append_from(_glass_mesh(m, s, lit), 0, xf)
				continue
			var key := "k_" + sn
			if sn == "plaster":
				key = "k_plaster%d" % tone
			_kst(far if lo else near, key).append_from(m, s, xf)


## A piece's glass with every vertex coloured (black: dark glass; else the light of the room).
func _glass_mesh(m: ArrayMesh, s: int, col: Color) -> ArrayMesh:
	var key := "%d|%d|%s" % [m.get_instance_id(), s, col.to_html()]
	if not kit.has(key):
		var a := m.surface_get_arrays(s)
		var cols := PackedColorArray()
		cols.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		cols.fill(col)
		a[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		kit[key] = am
	return kit[key]


## A mesh of a Poly Haven prop (node of its scene), without the offset it has in the prop's scene.
func _prop_mesh(scene: String, node: String) -> Array:
	var k := scene + ":" + node
	if not prop_meshes.has(k):
		var root: Node = load(scene).instantiate()
		var mi: MeshInstance3D = root.find_child(node, true, false)
		prop_meshes[k] = [mi.mesh, Transform3D(mi.transform.basis, Vector3.ZERO)]
		root.free()
	return prop_meshes[k]


func prop_piece(scene: String, node: String, xf: Transform3D, far_too := true) -> void:
	var pm := _prop_mesh(scene, node)
	var m: Mesh = pm[0]
	for s in m.get_surface_count():
		var mat: Material = m.surface_get_material(s)
		var key := "p_" + mat.resource_name
		if not mats.has(key):
			mats[key] = mat
		_kst(near, key).append_from(m, s, xf * pm[1])
		if far_too:
			_kst(far, key).append_from(m, s, xf * pm[1])


## The building made so far, as a near mesh and a far one that take turns by distance.
func commit_kit(shadows := true) -> void:
	for level in [near, far]:
		if level.is_empty():
			continue
		var am := ArrayMesh.new()
		for key in level:
			var st: SurfaceTool = level[key]
			st.commit(am, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
			am.surface_set_material(am.get_surface_count() - 1, mats[key])
		var mi := MeshInstance3D.new()
		mi.mesh = am
		if level == near:
			mi.visibility_range_end = KIT_SWAP
			mi.visibility_range_end_margin = 3.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.visibility_range_begin = KIT_SWAP
			mi.visibility_range_begin_margin = 3.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(mi)
	near = {}
	far = {}
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
var ac_share := 0.14


func _lit() -> Color:
	if not night or rng.randf() > lit_share:
		return Color(0, 0, 0)
	var r := rng.randf()
	var c: Color = ROOM_LIGHT[0 if r < 0.45 else (1 if r < 0.7 else (2 if r < 0.88 else 3))]
	return c * rng.randf_range(0.45, 0.85)


func _wname(kind: String, row: int, i: int) -> String:
	if kind == "offset_small":
		return "offset_small_0%d" % (row * 2 - 1 + (i % 2))
	return "%s_0%d" % [kind, row]


## A block of flats from the scanned kit over (x0, z0)-(x1, z1): `floors` storeys of 3 m under a moulded crown, a
## cornice over the ground floor. Ground floor shops (roller shutters, name boards, a few open and lit) on the sides in
## `shops`, a front door on the others. `blank`: sides against a neighbour, plain plaster.
func apartment(x0: float, z0: float, x1: float, z1: float, floors: int, shops := [], blank := [], opts := {}) -> void:
	var tone: int = opts.get("tone", rng.randi() % PLASTER.size())
	var wins: Array = opts.get("wins", WINDOW_SETS[rng.randi() % WINDOW_SETS.size()])
	var row: int = opts.get("row", [2, 2, 3, 1][rng.randi() % 4])
	shutter = "rollershutter_door" if rng.randf() < 0.6 else "rollershutter_door_graffiti"
	var h := floors * 3.0
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
		return
	var sh := Vector3(c.x + (x1 - x0) * 0.2, h, c.z - (z1 - z0) * 0.15)
	box("kq_plaster%d" % tone, sh + Vector3(0, 1.3, 0), Vector3(2.6, 2.6, 3.0))
	for k in rng.randi_range(1, 3):
		cyl("dark", Vector3(c.x - (x1 - x0) * 0.25 + k * 1.6, h + 0.1, c.z + (z1 - z0) * 0.2), 0.62, 1.3, 12, Color(0.08, 0.08, 0.09))
	collider(c - Vector3(0, h * 0.5, 0), Vector3(x1 - x0, h, z1 - z0))


func _kit_side(A: Vector3, X: Vector3, n: Vector3, L: float, floors: int, wins: Array, row: int, shops: bool, tone: int) -> void:
	var k := maxi(1, roundi(L / 3.0))
	var w := L / k
	var b := Basis(X * (w / 3.0), Vector3.UP, n)
	var b1 := Basis(X, Vector3.UP, n)
	var door := -1 if shops else k / 2
	for f in floors:
		for i in k:
			var o: Vector3 = A + X * (w * (i + 1)) + Vector3(0, f * 3.0, 0)
			var xf := Transform3D(b, o)
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
			piece("window_" + g, xf, tone, _lit())
			# an air conditioner hung under some windows
			if rng.randf() < ac_share:
				prop_piece(AIRCON_SCENE, "exterior_aircon_unit",
					Transform3D(b1, o - X * (w * 0.5 + (0.9 if row != 1 else 0.0)) + Vector3(0, 0.35 if row != 1 else 2.75, 0) + n * 0.22))
	for i in k:
		var o2: Vector3 = A + X * (w * (i + 1))
		piece("cornice_standard_standard_01", Transform3D(b, o2 + Vector3(0, 2.92, 0)), tone)
		piece("crown_standard_standard_01", Transform3D(b, o2 + Vector3(0, floors * 3.0, 0)), tone)
	# the corner where this side ends: a pilaster up every storey, capped
	var B := A + X * L
	for f in floors:
		piece("wall_pier_corner_01", Transform3D(b1, B + Vector3(0, f * 3.0, 0)), tone)
	piece("dado_pier_corner_01", Transform3D(b1, B), tone)
	piece("cornice_pier_corner_01", Transform3D(b1, B + Vector3(0, 2.92, 0)), tone)
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
	var node := shutter
	if open_:
		# shutter rolled up into its box; the shop inside: lit back wall, shelves, a counter
		prop_piece(SHUTTER_SCENE, node, Transform3D(Basis(X * sw, Vector3.UP * 0.18, n), c + Vector3(0, 2.05, 0)))
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
		prop_piece(SHUTTER_SCENE, node, Transform3D(Basis(X * sw, Vector3.UP * (2.45 / 2.4), n), c))
