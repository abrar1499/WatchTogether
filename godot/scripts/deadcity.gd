extends Node
## Mission 3's map: a modern city after the fighting, 300 m square. Two avenues cross at its centre, four side
## streets ring the inner blocks; sixteen blocks of 65 m. The four inner blocks hold the hospital (north-west), the
## enemy headquarters (north-east), the mall and plaza over the underground car park (south-west) and the industrial
## yard (south-east); the outer ring is flats, offices, shops, a supermarket, a depot. Buildings are assembled from
## the scanned facade kit (city.gd); the ones that can be entered have rooms, stairs and furniture built here.
## x: east, z: south, metres from the central crossroads.

var main: Node
var mis: Node
var city
var rng := RandomNumberGenerator.new()
var props := {}            # prop id -> Array of Transform3D (drawn as one MultiMesh each)
var prop_body: StaticBody3D
var lights := []           # strip lights that flicker: [light, phase]
var t := 0.0
var steps := 0

var posts := []            # soldiers placed as the map is built: [pos, face, kind, gun, route]
var chunker := Callable()  # where a piece of a big interior goes: position -> mesh name (see city.chunk)
const HOLES := [Rect2(-70, 20, 5, 20), Rect2(-20, 60, 5, 5), Rect2(-45, 25, 5, 5), Rect2(-40, 50, 5, 5)]   # ramp, stairs, mall stairs, blast hole
const PY := -3.4           # the car park's floor

const AV := 8.0            # half an avenue (road 5 + pavement 3)
const ST := 5.0            # half a side street (road 3 + pavement 2)
const SX := 78.0           # side streets at +-78
const EDGE := 148.0
var prop_path := "res://assets/city/props/%s/%s_game.gltf"   # where the scanned props are (id, id)
var prop_shadows := false  # whether the props cast shadows (not in the big city)


func _process(dt: float) -> void:
	t += dt
	for l in lights:
		var k: float = sin(t * 31.0 + l[1]) * sin(t * 7.3 + l[1] * 2.0)
		(l[0] as OmniLight3D).light_energy = l[2] * (1.0 if k > -0.55 else 0.15)


func tick() -> void:
	await main.breathe(18)


# ---------------- small helpers ----------------
func rect(ix: int, iz: int) -> Rect2:
	var a := func(i: int) -> float: return [-EDGE, -SX + ST, AV, SX + ST][i + 2 if i < 0 else i + 1]
	var x0: float = a.call(ix)
	var z0: float = a.call(iz)
	return Rect2(x0, z0, 65.0, 65.0)


func solid(c: Vector3, s: Vector3, yaw := 0.0, surf := "concrete") -> StaticBody3D:
	return city.collider(c, s, yaw, surf)


## A prop from the scanned library at p (drawn with all its kind in one batch); size: its solid box (0: none).
func prop(id: String, p: Vector3, yaw := 0.0, size := Vector3.ZERO, scale := 1.0, tilt := 0.0) -> void:
	if p.y < -1.0:
		id += "#d"             # under the ground: out of the sun
	if not props.has(id):
		props[id] = []
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), tilt)
	props[id].append(Transform3D(b.scaled(Vector3.ONE * scale), p))
	if size != Vector3.ZERO:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = p + Vector3(0, size.y * 0.5, 0)
		cs.rotation.y = yaw
		prop_body.add_child(cs)


## Shadows: nothing in this map casts its own (every surface of every mesh would be drawn again for each of the
## sun's shadow maps). Plain boxes stand in: one for each building, wall, lorry, container.
var shade_st: SurfaceTool
var shade_mat: StandardMaterial3D


func shade(c: Vector3, size: Vector3, yaw := 0.0) -> void:
	if not main.sun.shadow_enabled:
		return            # (no shadows in the game now: nothing to cast them)
	if shade_st == null:
		shade_st = SurfaceTool.new()
		shade_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := Basis(Vector3.UP, yaw)
	var x: Vector3 = b.x * size.x * 0.5
	var y: Vector3 = Vector3.UP * size.y * 0.5
	var z: Vector3 = b.z * size.z * 0.5
	for f in [[c + z, x, y], [c - z, -x, y], [c + x, -z, y], [c - x, z, y], [c + y, x, -z], [c - y, x, z]]:
		var o: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		for q in [o - u - v, o + u + v, o + u - v, o - u - v, o - u + v, o + u + v]:
			shade_st.add_vertex(q)


func commit_shade() -> void:
	if shade_st == null:
		return
	if shade_mat == null:
		shade_mat = StandardMaterial3D.new()
		shade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = shade_st.commit()
	mi.material_override = shade_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	main.add_child(mi)
	shade_st = null


## A chain-link fence from a to b (x, z), too high to climb; gaps: [[from, to]] along it left open. Its posts and wires
## go into the mesh being built (the mission's own fence makes a separate object of every post).
func fence(a: Vector2, b: Vector2, gaps := []) -> void:
	var d := b - a
	var L := d.length()
	var u := d / L
	var rot := atan2(-u.y, u.x)
	var segs := []
	var s0 := 0.0
	for g in gaps:
		segs.append([s0, g[0]])
		s0 = g[1]
	segs.append([s0, L])
	for sg in segs:
		var f0: float = sg[0]
		var f1: float = sg[1]
		if f1 - f0 < 0.2:
			continue
		var m: Vector2 = a + u * ((f0 + f1) * 0.5)
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(f1 - f0, 2.4)
		mi.mesh = q
		mi.material_override = mis._m("fence")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 140.0
		main.add_child(mi)
		mi.global_position = Vector3(m.x, 1.25, m.y)
		mi.rotation.y = rot
		var col: StaticBody3D = solid(Vector3(m.x, 1.7, m.y), Vector3(f1 - f0, 3.4, 0.08), rot, "metal")
		col.set_meta("pierce", "sheet")
		col.set_meta("seethrough", true)
		var k := f0
		while k <= f1 + 0.01:
			var pp: Vector2 = a + u * k
			city.box("m3_concrete", Vector3(pp.x, 1.4, pp.y), Vector3(0.12, 2.8, 0.12), rot, Color(0.8, 0.8, 0.8))
			k += 3.0
		for hgt in [2.55, 2.7, 2.85]:
			city.box("dark", Vector3(m.x, hgt, m.y), Vector3(f1 - f0, 0.015, 0.015), rot, Color(0.1, 0.1, 0.1))


## What stands in for a building's rooms from far off (they are not drawn beyond `begin`): a plain dark core.
func far_core(c: Vector3, size: Vector3, begin: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = city.mats["m3_inner"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = begin
	mi.visibility_range_end = 280.0
	main.add_child(mi)
	mi.global_position = c


## Something big and solid that hides what is behind it (so that is not drawn).
func occ(c: Vector3, size: Vector3) -> void:
	var oc := OccluderInstance3D.new()
	var bo := BoxOccluder3D.new()
	bo.size = size
	oc.occluder = bo
	main.add_child(oc)
	oc.global_position = c


## Everything placed since the last call, as batches of its own (so a place out of sight costs nothing).
func commit_props(gone := 130.0) -> void:
	commit_shade()
	for key in props:
		var id: String = (key as String).trim_suffix("#d")
		var scene: Node = load(prop_path % [id, id]).instantiate()
		var mesh: Mesh = (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		scene.free()
		var arr: Array = props[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if prop_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if (key as String).ends_with("#d"):
			mi.layers = 2
		mi.visibility_range_end = gone
		main.add_child(mi)
	props.clear()


func car(kind: String, p: Vector3, yaw: float, size := Vector3(1.8, 1.45, 4.6)) -> void:
	var path := "res://assets/city/%s.glb" % kind
	if kind == "land_rover":
		path = prop_path % [kind, kind]
		p.y -= 0.08
	var cb: StaticBody3D = main._prop(path, p, yaw, Vector3.ZERO, "metal")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position.y = size.y * 0.5
	cb.add_child(cs)
	cb.set_meta("pierce", "sheet")
	cb.add_to_group("m3car")
	for g in cb.find_children("*", "GeometryInstance3D", true, false):
		g.visibility_range_end = 90.0 if p.y > -1.0 else 60.0
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if p.y < -1.0:
			g.layers = 2
	if p.y > -1.0:
		shade(p + Vector3(0, size.y * 0.42 + 0.12, 0), Vector3(size.x * 0.92, size.y * 0.75, size.z * 0.94), yaw)
	main.extra_cover.append([p, 0.9])


# ---------------- ground, streets ----------------
func _ground() -> void:
	# the town's floor: worn asphalt and concrete, drawn in runs of 5 m cells so the openings to the car park stay open
	var cell := 5.0
	var n := 62
	for j in n:
		var z := -155.0 + (j + 0.5) * cell
		var i0 := -1
		for i in n + 1:
			var x := -155.0 + (i + 0.5) * cell
			var open_ := i == n
			if not open_:
				for hr in main.ground_holes:
					if hr.has_point(Vector2(x, z)):
						open_ = true
			if not open_ and i0 < 0:
				i0 = i
			if open_ and i0 >= 0:
				var xa := -155.0 + i0 * cell
				var xb := -155.0 + i * cell
				city.face("m3_debris", Vector3((xa + xb) * 0.5, 0.012, z), Vector3((xb - xa) * 0.5, 0, 0), Vector3(0, 0, -cell * 0.5), Color(0.5, 0.5, 0.5))
				i0 = -1
	city.commit(false)


## A street along x (axis 0) or z (axis 1) at `pos`, from a to b: the road, cracked pavements both sides on kerbs,
## left out where `gaps` (cross streets: [centre, half width]) cut it.
func street(axis: int, pos: float, a: float, b: float, road: float, walk: float, gaps: Array) -> void:
	var cuts := [a]
	for g in gaps:
		cuts.append(g[0] - g[1])
		cuts.append(g[0] + g[1])
	cuts.append(b)
	var along := Vector3(1, 0, 0) if axis == 0 else Vector3(0, 0, 1)
	var across := Vector3(0, 0, 1) if axis == 0 else Vector3(1, 0, 0)
	var mid := along * ((a + b) * 0.5) + across * pos
	# the road right through (crossings share it)
	var u := along * ((b - a) * 0.5)
	var v := across * road
	if axis == 0:
		city.face("g_asphalt", mid + Vector3(0, 0.03, 0), u, -v, Color(0.8, 0.8, 0.8))
	else:
		city.face("g_asphalt", mid + Vector3(0, 0.03, 0), v, -u, Color(0.8, 0.8, 0.8))
	for k in range(0, cuts.size(), 2):
		var s0: float = cuts[k]
		var s1: float = cuts[k + 1]
		if s1 - s0 < 1.0:
			continue
		for sg in [-1.0, 1.0]:
			var c: Vector3 = along * ((s0 + s1) * 0.5) + across * (pos + sg * (road + walk * 0.5))
			var size := Vector3(s1 - s0, 0.16, walk) if axis == 0 else Vector3(walk, 0.16, s1 - s0)
			city.box("m3_cracked", c + Vector3(0, 0.08, 0), size, 0.0, Color(0.95, 0.95, 0.95))
			var kc: Vector3 = along * ((s0 + s1) * 0.5) + across * (pos + sg * (road + 0.1))
			city.box("g_kerb", kc + Vector3(0, 0.09, 0), Vector3(s1 - s0, 0.18, 0.2) if axis == 0 else Vector3(0.2, 0.18, s1 - s0))
			city.step_collider(c, size + Vector3(0, 0.005, 0))
		# worn centre line
		var d := s0 + 2.0
		while d < s1 - 3.0:
			if rng.randf() < 0.7:
				var lc: Vector3 = along * (d + 1.5) + across * pos + Vector3(0, 0.05, 0)
				city.face("panel", lc, along * 1.5, -across * 0.07 if axis == 0 else across * 0.07, Color(0.7, 0.7, 0.66))
			d += 6.0


func _streets() -> void:
	var cross := [[-SX, ST], [0.0, AV], [SX, ST]]
	for axis in 2:
		street(axis, 0.0, -EDGE, EDGE, 5.0, 3.0, cross)
		for p in [-SX, SX]:
			street(axis, p, -EDGE, EDGE, 3.0, 2.0, cross)
	city.commit(false)


# ---------------- rubble, craters, wrecks ----------------
## A heap of broken masonry: a mound with slabs and blocks lying on it. Low ones can be walked over.
func rubble(c: Vector3, r: float, h: float) -> void:
	var st: SurfaceTool = city._st("m3_rubble")
	var rings := 3
	var seg := 9
	var pts := []
	for ri in rings + 1:
		var row := []
		for si in seg:
			var a := TAU * si / seg + ri * 0.3
			var rr := r * ri / rings * (0.85 + 0.3 * rng.randf())
			var y := h * (1.0 - pow(float(ri) / rings, 1.4)) * (0.8 + 0.4 * rng.randf()) if ri < rings else 0.0
			row.append(c + Vector3(cos(a) * rr, y, sin(a) * rr))
		pts.append(row)
	for ri in rings:
		for si in seg:
			var q := [pts[ri][si], pts[ri][(si + 1) % seg], pts[ri + 1][(si + 1) % seg], pts[ri + 1][si]]
			for tri in [[0, 2, 1], [0, 3, 2]]:
				var nn: Vector3 = ((q[tri[1]] as Vector3) - (q[tri[0]] as Vector3)).cross((q[tri[2]] as Vector3) - (q[tri[0]] as Vector3)).normalized()
				if nn.y < 0.0:
					nn = -nn
				var sh := 0.75 + 0.25 * rng.randf()
				for k in tri:
					var pv: Vector3 = q[k]
					st.set_color(Color(sh, sh, sh))
					st.set_normal(nn)
					st.set_uv(Vector2(pv.x, pv.z))
					st.add_vertex(pv)
	for i in int(4 + r * 2.5):
		var a := rng.randf() * TAU
		var d := r * sqrt(rng.randf()) * 0.95
		var s := Vector3(rng.randf_range(0.3, 1.3), rng.randf_range(0.12, 0.3), rng.randf_range(0.3, 0.9))
		var y := h * (1.0 - pow(d / r, 1.4)) * 0.85
		var key: String = ["m3_slab", "m3_slab", "m3_brick", "m3_inner"][rng.randi() % 4]
		var bb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.5, 0.5))
		_tilted_box(key, c + Vector3(cos(a) * d, y + s.y * 0.4, sin(a) * d), s, bb, Color(0.8, 0.8, 0.8).darkened(rng.randf() * 0.25))
	var hull := PackedVector3Array()
	for si in seg:
		hull.append((pts[rings][si] as Vector3) - c)
		hull.append((pts[1][si] as Vector3) - c)
	hull.append(Vector3(0, h, 0))
	var body := StaticBody3D.new()
	body.set_meta("surf", "concrete")
	var cs := CollisionShape3D.new()
	var shp := ConvexPolygonShape3D.new()
	shp.points = hull
	cs.shape = shp
	body.add_child(cs)
	main.add_child(body)
	body.global_position = c
	if h > 0.6:
		main.extra_cover.append([c, r * 0.7])


func _tilted_box(key: String, c: Vector3, s: Vector3, b: Basis, col: Color) -> void:
	_ck(c)
	var x: Vector3 = b.x * s.x * 0.5
	var y: Vector3 = b.y * s.y * 0.5
	var z: Vector3 = b.z * s.z * 0.5
	city.face(key, c + z, x, y, col)
	city.face(key, c - z, -x, y, col)
	city.face(key, c + x, -z, y, col)
	city.face(key, c - x, z, y, col)
	city.face(key, c + y, x, -z, col)
	city.face(key, c - y, x, z, col)


## A shell crater in the road: a scorched ring of thrown earth and broken asphalt.
func crater(c: Vector3, r: float) -> void:
	city.decal("m3_scorch", c + Vector3(0, 0.06, 0), r * 3.2, rng.randf() * TAU)
	for i in int(r * 7.0):
		var a := rng.randf() * TAU
		var d := r * rng.randf_range(0.7, 1.5)
		var s := Vector3(rng.randf_range(0.2, 0.7), rng.randf_range(0.08, 0.22), rng.randf_range(0.2, 0.6))
		_tilted_box("g_asphalt", c + Vector3(cos(a) * d, s.y * 0.4, sin(a) * d), s, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.6, 0.6)), Color(0.5, 0.5, 0.5))
	city.face("m3_burnt", c + Vector3(0, 0.05, 0), Vector3(r * 0.9, 0, 0), Vector3(0, 0, -r * 0.9), Color(0.6, 0.6, 0.6))


## A dead street light: the pole leaning, its head hanging.
func dead_lamp(p: Vector3, lean := 0.0) -> void:
	var b := Basis(Vector3(0, 0, 1), lean)
	var top: Vector3 = p + b * Vector3(0, 7.2, 0)
	_tilted_box("frame", (p + top) * 0.5, Vector3(0.14, 7.2, 0.14), b, Color(0.3, 0.31, 0.33))
	_tilted_box("frame", top + b * Vector3(0.8, 0.0, 0), Vector3(1.8, 0.1, 0.2), b, Color(0.3, 0.31, 0.33))


## A line of power poles with sagging cables from a to b.
func poles(a: Vector3, b: Vector3, n: int) -> void:
	var prev := Vector3.ZERO
	for i in n:
		var p: Vector3 = a.lerp(b, float(i) / max(n - 1, 1))
		var lean: float = rng.randf_range(-0.08, 0.08)
		var bs := Basis(Vector3(0, 0, 1), lean)
		var top: Vector3 = p + bs * Vector3(0, 8.0, 0)
		_tilted_box("wood", (p + top) * 0.5, Vector3(0.22, 8.0, 0.22), bs, Color(0.3, 0.25, 0.2))
		_tilted_box("wood", top - Vector3(0, 0.5, 0), Vector3(0.12, 0.12, 2.2), bs, Color(0.3, 0.25, 0.2))
		if i > 0:
			for off in [-0.9, 0.0, 0.9]:
				var p0: Vector3 = prev + Vector3(0, -0.4, off)
				var p1: Vector3 = top + Vector3(0, -0.4, off)
				var sag: float = 0.9 + rng.randf() * 0.5
				var last := p0
				for k in range(1, 7):
					var u := k / 6.0
					var q: Vector3 = p0.lerp(p1, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)
					var d := q - last
					var bb := Basis.looking_at(d.normalized(), Vector3.UP) if abs(d.normalized().y) < 0.95 else Basis()
					_tilted_box("dark", (q + last) * 0.5, Vector3(0.03, 0.03, d.length()), bb, Color(0.05, 0.05, 0.05))
					last = q
		prev = top


# ---------------- blocks of buildings that cannot be entered ----------------
## Fill (x0, z0)-(x1, z1) with a row of buildings side by side along its long side; `shops`: the faces with shuttered
## shop fronts. Some have shell holes high up (a heap of rubble below each), smoke stains, broken glass.
func row(x0: float, z0: float, x1: float, z1: float, floors: Array, shops := [], towers := 0, harm := 0.6) -> void:
	var along_x := (x1 - x0) >= (z1 - z0)
	var length: float = (x1 - x0) if along_x else (z1 - z0)
	city.block_tones = [rng.randi() % city.PLASTER.size(), rng.randi() % city.PLASTER.size()]
	var s0 := 0.0
	var n_tower := towers
	while s0 < length - 0.5:
		var wdt: float = min(length - s0, float(rng.randi_range(4, 7)) * 3.0)
		if length - s0 - wdt < 9.0:
			wdt = length - s0
		var q: Array = [x0 + s0, z0, x0 + s0 + wdt, z1] if along_x else [x0, z0 + s0, x1, z0 + s0 + wdt]
		var blank := []
		if s0 > 0.1:
			blank.append("w" if along_x else "n")
		if wdt < length - s0 - 0.01:
			blank.append("e" if along_x else "s")
		var fl: int = rng.randi_range(floors[0], floors[1])
		if n_tower > 0 and wdt >= 12.0:
			city.office_tower(q[0] + 0.6, q[1] + 0.6, q[2] - 0.6, q[3] - 0.6, rng.randi_range(8, 12))
			n_tower -= 1
		else:
			var dm := []
			if rng.randf() < harm:
				for k in rng.randi_range(1, 2):
					# a hit high on one of the open faces
					var fx: float = [q[0], q[2]][rng.randi() % 2] if not along_x or rng.randf() < 0.3 else rng.randf_range(q[0], q[2])
					var fz: float = [q[1], q[3]][rng.randi() % 2]
					var hc := Vector3(fx, fl * 3.0 - rng.randf_range(0.0, 3.0), fz)
					dm.append([hc, rng.randf_range(4.0, 7.5)])
					var out := Vector3(0, 0, 1.0 if fz == q[3] else -1.0)
					rubble(Vector3(fx, 0, fz) + out * 2.2, rng.randf_range(2.5, 4.5), rng.randf_range(0.5, 1.4))
			city.apartment(q[0], q[1], q[2], q[3], fl, shops, blank, {"damage": dm})
		s0 += wdt
	for bx in city.occluders:
		shade((bx as AABB).get_center() + Vector3(0, 0.15, 0), (bx as AABB).size + Vector3(0.6, 0.3, 0.6))
	city.commit_kit(false, false)
	city.commit(false, 260.0)
	commit_shade()
	city.block_tones = []


## A block of the outer ring: two rows of buildings with a back lane between them.
func ring_block(r: Rect2, floors: Array, shop_n := false, shop_s := false, shop_w := false, shop_e := false, towers := 0) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x - 2.0        # 63 m: bays of 3 m
	var z1 := r.end.y
	row(x0, z0, x1, z0 + 27.0, floors, (["n"] if shop_n else []) + (["w"] if shop_w else []) + (["e"] if shop_e else []), towers)
	row(x0, z1 - 27.0, x1, z1, floors, (["s"] if shop_s else []) + (["w"] if shop_w else []) + (["e"] if shop_e else []))
	# the lane behind: bins, bags, a wreck, weeds of rubble
	var lz := (z0 + z1) * 0.5
	for i in 5:
		var px := x0 + 6.0 + i * 12.0 + rng.randf_range(-2, 2)
		var side: float = [-4.2, 4.2][rng.randi() % 2]
		if rng.randf() < 0.6:
			prop("metal_trash_can", Vector3(px, 0, lz + side), 0.0 if side < 0.0 else PI, Vector3(1.8, 0.9, 0.6))
		for k in rng.randi_range(0, 3):
			prop("trashbag", Vector3(px + rng.randf_range(-1.2, 1.2), 0, lz + side + rng.randf_range(-0.6, 0.6)), rng.randf() * TAU)
	if rng.randf() < 0.6:
		rubble(Vector3(rng.randf_range(x0 + 10, x1 - 10), 0, lz + rng.randf_range(-2, 2)), rng.randf_range(2.0, 3.5), rng.randf_range(0.4, 0.9))


# ---------------- buildings that can be entered ----------------
var body: StaticBody3D      # the walls and floors of the building being made


func _ck(c: Vector3) -> void:
	if chunker.is_valid():
		city.chunk = chunker.call(c)


func end_building() -> void:
	chunker = Callable()
	city.chunk = ""


func begin_building(surf := "concrete") -> void:
	body = StaticBody3D.new()
	body.set_meta("surf", surf)
	main.add_child(body)


func add_shape(c: Vector3, size: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = c
	cs.rotation.y = yaw
	body.add_child(cs)


## A straight wall from a to b (x, z), from y0 up h, with openings [from, to (metres along it), bottom, top (heights)].
func wall(a: Vector2, b: Vector2, y0: float, h: float, th: float, key: String, col: Color, holes := [], collide := true) -> void:
	var d := b - a
	var L := d.length()
	var u := d / L
	var yaw := atan2(-u.y, u.x)
	var segs := []
	var s := 0.0
	var hs: Array = holes.duplicate()
	hs.sort_custom(func(p, q): return p[0] < q[0])
	for hh in hs:
		if hh[0] > s + 0.01:
			segs.append([s, hh[0], y0, y0 + h])
		if hh[2] > y0 + 0.01:
			segs.append([hh[0], hh[1], y0, hh[2]])
		if hh[3] < y0 + h - 0.01:
			segs.append([hh[0], hh[1], hh[3], y0 + h])
		s = hh[1]
	if s < L - 0.01:
		segs.append([s, L, y0, y0 + h])
	for sg in segs:
		var m: Vector2 = a + u * ((sg[0] + sg[1]) * 0.5)
		var c := Vector3(m.x, (sg[2] + sg[3]) * 0.5, m.y)
		var size := Vector3(sg[1] - sg[0], sg[3] - sg[2], th)
		var parts: int = maxi(1, ceili(size.x / 10.0)) if chunker.is_valid() else 1
		for k in parts:
			var m2: Vector2 = a + u * (sg[0] + (k + 0.5) * size.x / parts)
			var c2 := Vector3(m2.x, c.y, m2.y)
			_ck(c2)
			city.box(key, c2, Vector3(size.x / parts, size.y, size.z), yaw, col)
		if collide:
			add_shape(c, size, yaw)


## A floor: its top at y (one material), its underside the ceiling of the room below (another); `hole`: left open.
func slab(x0: float, z0: float, x1: float, z1: float, y: float, top_key: String, top_col: Color, bot_key: String, bot_col: Color, hole := Rect2(), solid_ := true) -> void:
	var rects := []
	if hole.size.x <= 0.0:
		rects.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	else:
		rects.append(Rect2(x0, z0, hole.position.x - x0, z1 - z0))
		rects.append(Rect2(hole.end.x, z0, x1 - hole.end.x, z1 - z0))
		rects.append(Rect2(hole.position.x, z0, hole.size.x, hole.position.y - z0))
		rects.append(Rect2(hole.position.x, hole.end.y, hole.size.x, z1 - hole.end.y))
	for r in rects:
		if r.size.x < 0.02 or r.size.y < 0.02:
			continue
		var c := Vector3(r.position.x + r.size.x * 0.5, y, r.position.y + r.size.y * 0.5)
		var nx: int = maxi(1, ceili(r.size.x / 10.0))
		var nz: int = maxi(1, ceili(r.size.y / 10.0))
		var hx: float = r.size.x / nx * 0.5
		var hz: float = r.size.y / nz * 0.5
		for i in nx:
			for j in nz:
				var tc := Vector3(r.position.x + (i * 2 + 1) * hx, y, r.position.y + (j * 2 + 1) * hz)
				if top_key != "":
					_ck(tc + Vector3(0, 0.2, 0))
					city.face(top_key, tc, Vector3(hx, 0, 0), Vector3(0, 0, -hz), top_col)
				if bot_key != "":
					_ck(tc - Vector3(0, 0.5, 0))
					city.face(bot_key, tc - Vector3(0, 0.24, 0), Vector3(hx, 0, 0), Vector3(0, 0, hz), bot_col)
		if solid_:
			add_shape(c - Vector3(0, 0.12, 0), Vector3(r.size.x, 0.24, r.size.y))


## A straight flight of stairs from `base` rising `rise` over `run` along dir: treads and risers, a ramp to walk on,
## a rail each side. Returns the opening it needs in the floor above.
func stairs(base: Vector3, dir: Vector3, width: float, rise: float, run: float, key := "m3_stair", col := Color(0.7, 0.7, 0.7)) -> Rect2:
	_ck(base + Vector3(0, 0.5, 0))
	var n := int(round(rise / 0.2))
	var hs := rise / n
	var ds := run / n
	var side := dir.cross(Vector3.UP).normalized()
	for i in n:
		var p: Vector3 = base + dir * (i * ds)
		# riser (faces the foot of the stairs), tread
		city.face(key, p + Vector3(0, (i + 0.5) * hs, 0), side * (width * 0.5), Vector3.UP * (hs * 0.5), col.darkened(0.15))
		city.face(key, p + dir * (ds * 0.5) + Vector3(0, (i + 1) * hs, 0), side * (width * 0.5), dir * (ds * 0.5), col)
	var slope := (dir * run + Vector3.UP * rise)
	var len_ := slope.length()
	var sl := slope / len_
	var nrm := sl.cross(side).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var mid: Vector3 = base + dir * (run * 0.5) + Vector3(0, rise * 0.5, 0)
	var rb := StaticBody3D.new()
	rb.set_meta("surf", "concrete")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 0.2, len_ + 0.3)
	cs.shape = sh
	rb.add_child(cs)
	main.add_child(rb)
	rb.global_transform = Transform3D(Basis(nrm.cross(sl).normalized(), nrm, sl), mid - nrm * 0.1)
	# the underside, and a rail down each side
	_tilted_box(key, mid - nrm * 0.28, Vector3(width, 0.12, len_), Basis(nrm.cross(sl).normalized(), nrm, sl), col.darkened(0.3))
	for sg in [-1.0, 1.0]:
		_tilted_box("frame", mid + side * (sg * (width * 0.5 - 0.03)) + Vector3(0, 0.95, 0), Vector3(0.05, 0.05, len_), Basis(nrm.cross(sl).normalized(), nrm, sl), Color(0.35, 0.36, 0.38))
		for k in 4:
			var q: Vector3 = base + dir * (run * (k + 0.5) / 4.0) + Vector3(0, rise * (k + 0.5) / 4.0, 0) + side * (sg * (width * 0.5 - 0.03))
			city.box("frame", q + Vector3(0, 0.47, 0), Vector3(0.04, 0.95, 0.04), 0.0, Color(0.35, 0.36, 0.38))
	var e: Vector3 = base + dir * run
	var x0: float = min(base.x, e.x) - abs(side.x) * width * 0.5 - 0.05
	var x1: float = max(base.x, e.x) + abs(side.x) * width * 0.5 + 0.05
	var z0: float = min(base.z, e.z) - abs(side.z) * width * 0.5 - 0.05
	var z1: float = max(base.z, e.z) + abs(side.z) * width * 0.5 + 0.05
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## The outside of a building that can be entered: the scanned facade, bay by bay, and a plastered wall behind it.
## plan(side, bay, floor, bays) says what each bay is: "W" window, "B" window with its glass gone (open), "D" doorway,
## "S" plain wall, "X" blown out. Floors from `inner` up have no rooms behind them (a dark core instead).
func shell(x0: float, z0: float, x1: float, z1: float, floors: int, tone: int, plan: Callable, in_key: String, in_col: Color, inner := 99) -> void:
	var sides := {"s": [Vector3(0, 0, 1), Vector3(x0, 0, z1), x1 - x0], "n": [Vector3(0, 0, -1), Vector3(x1, 0, z0), x1 - x0],
		"e": [Vector3(1, 0, 0), Vector3(x1, 0, z1), z1 - z0], "w": [Vector3(-1, 0, 0), Vector3(x0, 0, z0), z1 - z0]}
	for side in sides:
		var sd: Array = sides[side]
		var n: Vector3 = sd[0]
		var X := Vector3.UP.cross(n)
		var A: Vector3 = sd[1]
		var L: float = sd[2]
		var k := maxi(1, roundi(L / 3.0))
		var w := L / k
		var b := Basis(X * (w / 3.0), Vector3.UP, n)
		var b1 := Basis(X, Vector3.UP, n)
		var top_gone := {}
		for f in floors:
			for i in k:
				var kind: String = plan.call(side, i, f, k)
				var o: Vector3 = A + X * (w * (i + 1)) + Vector3(0, f * 3.0, 0)
				var xf := Transform3D(b, o)
				if kind == "X":
					if f == floors - 1:
						top_gone[i] = true
					continue
				match kind:
					"D":
						city.piece("wall_door_centered_large_01", xf, tone)
					"S":
						city.piece("wall_standard_standard_01", xf, tone)
					_:
						city.piece("wall_window_centered_large_02", xf, tone)
						city.piece("window_centered_large_02", xf, tone, Color(0, 0, 0), kind == "W")
						if kind == "B" and rng.randf() < 0.3:
							city.soot(o - X * (w * 0.5) + Vector3(0, 3.1, 0), X, n, w * 0.8, 2.4)
				if f == 0:
					city.piece("dado_door_centered_large_01" if kind == "D" else "dado_standard_standard_01", xf, tone)
					city.piece("cornice_standard_standard_01", Transform3D(b, o + Vector3(0, 2.92, 0)), tone)
				if f >= inner:
					continue
				# the wall indoors
				var a2 := Vector2(o.x - X.x * w - n.x * 0.13, o.z - X.z * w - n.z * 0.13)
				var b2 := Vector2(o.x - n.x * 0.13, o.z - n.z * 0.13)
				var y := f * 3.0
				var holes := []
				if kind == "D":
					holes = [[0.6 * w / 3.0, 2.4 * w / 3.0, y, y + 2.7]]
				elif kind != "S":
					holes = [[0.55 * w / 3.0, 2.45 * w / 3.0, y + 0.42, y + 2.22]]
				wall(a2, b2, y, 3.0, 0.22, in_key, in_col, holes, kind != "W")
				if kind == "W":
					var mc: Vector3 = o - X * (w * 0.5) + Vector3(0, 1.5, 0) - n * 0.13
					add_shape(mc, Vector3(w, 3.0, 0.22), atan2(-X.z, X.x))
					_ck(mc)
					city.face("m3_daylight", o - X * (w * 0.5) + Vector3(0, 1.32, 0) - n * 0.04, -X * (0.95 * w / 3.0), Vector3.UP * 0.9)
		for i in k:
			if not top_gone.has(i):
				city.piece("crown_standard_standard_01", Transform3D(b, A + X * (w * (i + 1)) + Vector3(0, floors * 3.0, 0)), tone)
		var B := A + X * L
		for f in floors:
			city.piece("wall_pier_corner_01", Transform3D(b1, B + Vector3(0, f * 3.0, 0)), tone)
		city.piece("dado_pier_corner_01", Transform3D(b1, B), tone)
		city.piece("crown_pier_corner_01", Transform3D(b1, B + Vector3(0, floors * 3.0, 0)), tone)
	if inner < floors:
		city.box("m3_inner", Vector3((x0 + x1) * 0.5, (inner + floors) * 1.5, (z0 + z1) * 0.5), Vector3(x1 - x0 - 0.8, (floors - inner) * 3.0 - 0.3, z1 - z0 - 0.8), 0.0, Color(0.5, 0.48, 0.46))
	city.footprints.append(Rect2(x0, z0, x1 - x0, z1 - z0))


## A wall indoors from a to b with doorways centred at `doors` (metres along it).
func iwall(a: Vector2, b: Vector2, y: float, key: String, col: Color, doors := [], dw := 1.2, th := 0.14) -> void:
	var holes := []
	for dc in doors:
		holes.append([dc - dw * 0.5, dc + dw * 0.5, y, y + 2.1])
	wall(a, b, y, 2.76, th, key, col, holes)


## A strip light on the ceiling at p: lit (steady or failing) or dead.
func tube(p: Vector3, on := true, flicker := false, col := Color(0.86, 0.93, 1.0), energy := 1.1, reach := 8.0) -> void:
	prop("mounted_fluorescent_lights", p, 0.0)
	if not on:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.distance_fade_enabled = true
	l.distance_fade_begin = 30.0
	l.distance_fade_length = 8.0
	main.add_child(l)
	l.global_position = p - Vector3(0, 0.35, 0)
	if flicker:
		lights.append([l, rng.randf() * 10.0, energy])


## Litter on a floor: fallen ceiling panels, broken plaster, a dusty patch.
func litter(x0: float, z0: float, x1: float, z1: float, y: float, n: int) -> void:
	for i in n:
		var p := Vector3(rng.randf_range(x0, x1), y, rng.randf_range(z0, z1))
		if rng.randf() < 0.5:
			_tilted_box("m3_ceiling", p + Vector3(0, 0.03, 0), Vector3(0.6, 0.02, 0.6) * rng.randf_range(0.6, 1.0), Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.12, 0.12)), Color(0.75, 0.74, 0.72))
		else:
			var s := Vector3(rng.randf_range(0.12, 0.4), rng.randf_range(0.05, 0.14), rng.randf_range(0.12, 0.35))
			_tilted_box("m3_inner", p + Vector3(0, s.y * 0.5, 0), s, Basis(Vector3.UP, rng.randf() * TAU), Color(0.8, 0.78, 0.75))


var sign_n := 0
## A name board: white capitals on a painted ground, on the face looking along n.
func board(text: String, c: Vector3, n: Vector3, w: float, h: float, bg := Color(0.1, 0.25, 0.5), ink := Color(0.95, 0.95, 0.92)) -> void:
	var px := 6
	var W := text.length() * 6 * px + 40
	var H := 7 * px + 30
	var img := Image.create(W, H, true, Image.FORMAT_RGB8)
	img.fill(bg)
	city._glyphs(img, text, 20, 15, px, ink)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	q.mesh = qm
	q.material_override = m
	q.visibility_range_end = 150.0
	main.add_child(q)
	q.global_position = c + n * 0.09
	q.look_at(c - n, Vector3.UP)
	var X := Vector3.UP.cross(n)
	city.box("dark", c + n * 0.03, Vector3(w + 0.14, h + 0.14, 0.08), atan2(-X.z, X.x), Color(0.12, 0.12, 0.13))
	sign_n += 1


# ---------------- the hospital (north-west) ----------------
func _hospital() -> void:
	var x0 := -64.0
	var x1 := -16.0
	var z0 := -58.0
	var z1 := -31.0
	begin_building()
	var plan := func(side: String, i: int, f: int, k: int) -> String:
		if f == 0:
			if side == "s" and (i == 7 or i == 8):
				return "D"
			if side == "e" and (i == 1 or i == 2):
				return "D"
			if side == "n" and i == 14:
				return "D"
		if f == 1 and ((side == "s" and i >= 14) or (side == "e" and i <= 1)):
			return "X"
		var r := rng.randf()
		return "B" if r < (0.45 if f < 2 else 0.6) else "W"
	chunker = func(c: Vector3) -> String: return "h%d%d" % [int(c.y > 2.9), int(c.x > -40.0)]
	shell(x0, z0, x1, z1, 3, 6, plan, "m3_paint", Color(0.9, 0.9, 0.9), 2)
	var wc := Color(0.9, 0.9, 0.9)
	var fc := Color(0.85, 0.85, 0.85)
	var cc := Color(0.9, 0.9, 0.9)
	# floors: ground (laid on the town's floor), first (the stairs come up through it), second, roof
	city.face("m3_tiles", Vector3((x0 + x1) * 0.5, 0.03, (z0 + z1) * 0.5), Vector3((x1 - x0) * 0.5, 0, 0), Vector3(0, 0, -(z1 - z0) * 0.5), fc)
	var hole := stairs(Vector3(-62.8, 0.03, -47.6), Vector3(0, 0, -1), 1.5, 2.97, 4.6)
	slab(x0, z0, x1, z1, 3.0, "m3_tiles", fc, "m3_ceiling", cc, hole)
	slab(x0, z0, x1, z1, 6.0, "", fc, "m3_ceiling", cc)
	slab(x0, z0, x1, z1, 9.0, "k_roof", Color(1, 1, 1), "", cc)
	for f in 2:
		var y := f * 3.0 + (0.03 if f == 0 else 0.0)
		# the corridor's walls
		if f == 0:
			iwall(Vector2(x0, -46.0), Vector2(x1, -46.0), y, "m3_paint", wc, [3.0, 9.0, 15.0, 21.0, 27.0, 34.5, 43.5], 1.3)
			iwall(Vector2(x0, -43.6), Vector2(-49.0, -43.6), y, "m3_paint", wc, [3.75, 11.25])
			iwall(Vector2(-31.0, -43.6), Vector2(x1, -43.6), y, "m3_paint", wc, [4.0], 3.0)
			iwall(Vector2(-49.0, -43.6), Vector2(-49.0, z1), y, "m3_paint", wc)
			iwall(Vector2(-56.5, -43.6), Vector2(-56.5, z1), y, "m3_paint", wc)
			iwall(Vector2(-31.0, -43.6), Vector2(-31.0, -35.5), y, "m3_white_tiles", Color(0.8, 0.8, 0.8))
		else:
			iwall(Vector2(-58.0, -46.0), Vector2(x1, -46.0), y, "m3_paint", wc, [3.0, 9.0, 15.0, 21.0, 28.5, 37.5], 1.3)
			iwall(Vector2(x0, -43.6), Vector2(x1, -43.6), y, "m3_paint", wc, [3.75, 11.25, 18.75, 26.25, 33.75, 42.0])
			for px in [-56.5, -49.0, -41.5, -34.0, -26.5]:
				iwall(Vector2(px, -43.6), Vector2(px, z1), y, "m3_paint", wc)
			# a rail round the stair opening
			for rs in [[Vector2(hole.end.x, hole.position.y), Vector2(hole.end.x, hole.end.y)], [Vector2(hole.position.x, hole.end.y), Vector2(hole.end.x, hole.end.y)]]:
				var ra: Vector2 = rs[0]
				var rb2: Vector2 = rs[1]
				city.box("frame", Vector3((ra.x + rb2.x) * 0.5, y + 1.0, (ra.y + rb2.y) * 0.5), Vector3(abs(rb2.x - ra.x) + 0.05, 0.05, abs(rb2.y - ra.y) + 0.05), 0.0, Color(0.35, 0.36, 0.38))
				add_shape(Vector3((ra.x + rb2.x) * 0.5, y + 0.5, (ra.y + rb2.y) * 0.5), Vector3(abs(rb2.x - ra.x) + 0.05, 1.0, abs(rb2.y - ra.y) + 0.05))
		# the rooms north of the corridor
		var cuts := [-58.0, -52.0, -46.0, -40.0, -34.0, -25.0]
		for px in cuts:
			var key := "m3_white_tiles" if (px == -34.0 or px == -25.0) else "m3_paint"
			iwall(Vector2(px, z0), Vector2(px, -46.0), y, key, wc)
		# beds, cabinets, chairs
		var rooms := [[-58.0, -52.0], [-52.0, -46.0], [-46.0, -40.0], [-40.0, -34.0]]
		for r in rooms:
			_ward(r[0], z0 + 0.3, r[1], -46.2, y)
		if f == 1:
			for r in [[-64.0, -56.5], [-56.5, -49.0], [-49.0, -41.5], [-41.5, -34.0], [-34.0, -26.5]]:
				_ward(r[0], -43.4, r[1], z1 - 0.3, y)
			litter(-26.0, -43.0, -17.0, -32.0, y, 14)
		else:
			_ward(-64.0, -43.4, -56.5, z1 - 0.3, y)
			_ward(-56.5, -43.4, -49.0, z1 - 0.3, y)
		# operating room (white tiled) and the store beside it
		_theatre(-34.0, z0 + 0.3, -25.0, -46.2, y)
		for k in 3:
			prop("worn_metal_rack", Vector3(-24.2 + k * 1.1, y, z0 + 0.75), 0.0, Vector3(0.95, 1.9, 0.6))
			prop("steel_frame_shelves_01", Vector3(-17.0, y, -56.0 + k * 3.0), PI * 0.5, Vector3(1.1, 2.1, 0.5), 0.1)
		for k in 5:
			prop("cardboard_box_01", Vector3(rng.randf_range(-24, -18), y, rng.randf_range(-55, -48)), rng.randf() * TAU, Vector3(0.4, 0.34, 0.5))
			prop("medical_box", Vector3(rng.randf_range(-24, -18), y, rng.randf_range(-55, -48)), rng.randf() * TAU)
		# the corridor: trolleys, a wheelchair, lights (some failing, some dead), an emergency lamp at each end
		for k in 6:
			var lx := -60.0 + k * 8.0
			tube(Vector3(lx, y + 2.72, -44.8), (k + f) % 3 != 1, (k + f) % 3 == 2)
		for ex in [x0 + 0.6, x1 - 0.6]:
			var el := OmniLight3D.new()
			el.light_color = Color(1.0, 0.25, 0.15)
			el.light_energy = 0.7
			el.omni_range = 6.0
			el.distance_fade_enabled = true
			el.distance_fade_begin = 28.0
			main.add_child(el)
			el.global_position = Vector3(ex, y + 2.3, -44.8)
			city.box("sign", Vector3(ex, y + 2.45, -44.8), Vector3(0.12, 0.12, 0.3), 0.0, Color(1.0, 0.2, 0.1))
		prop("industrial_storage_cart", Vector3(-53.0, y, -44.9), PI * 0.5 + 0.1, Vector3(1.1, 1.3, 1.6), 0.8)
		prop("wheelchair_01", Vector3(-37.5, y, -44.5), 0.6, Vector3(0.7, 1.0, 0.9))
		prop("wheelchair_01", Vector3(-21.0, y, -45.2), 2.4, Vector3.ZERO, 1.0, 1.5 if f == 0 else 0.0)
		litter(x0 + 1, -45.8, x1 - 1, -43.8, y, 16)
	# ground floor: reception and waiting hall, the emergency department
	prop("metal_office_desk", Vector3(-42.0, 0.03, -41.0), PI, Vector3(2.0, 0.8, 0.95))
	prop("metal_office_desk", Vector3(-39.9, 0.03, -41.0), PI, Vector3(2.0, 0.8, 0.95))
	prop("modern_arm_chair_01", Vector3(-41.0, 0.03, -42.3), 0.3)
	for rw in 2:
		for k in 7:
			if rng.randf() < 0.85:
				prop("plastic_monobloc_chair_01", Vector3(-47.0 + k * 0.7, 0.03, -37.0 + rw * 2.4), PI if rw == 0 else 0.0, Vector3.ZERO, 1.0, 1.4 if rng.randf() < 0.15 else 0.0)
	prop("sofa_03", Vector3(-34.5, 0.03, -32.2), PI, Vector3(2.7, 0.9, 0.9))
	prop("WetFloorSign_01", Vector3(-38.5, 0.03, -34.0), 0.5)
	prop("wheelchair_01", Vector3(-45.5, 0.03, -33.0), 1.9, Vector3(0.7, 1.0, 0.9))
	for cx2 in [-45.0, -40.0, -35.0]:
		city.box("m3_paint", Vector3(cx2, 1.5, -37.6), Vector3(0.5, 2.94, 0.5), 0.0, Color(0.9, 0.9, 0.9))
		add_shape(Vector3(cx2, 1.5, -37.6), Vector3(0.5, 3.0, 0.5))
	tube(Vector3(-42.5, 2.75, -40.0), true, false)
	tube(Vector3(-37.5, 2.75, -34.5), true, true)
	tube(Vector3(-46.0, 2.75, -34.0), false)
	litter(-48.5, -43.0, -31.5, -31.6, 0.03, 18)
	for k in 4:
		var bx := -29.0 + k * 3.4
		bed(Vector3(bx, 0.03, -33.2), 0.0)
		prop("industrial_storage_cart", Vector3(bx + 1.4, 0.03, -33.0), rng.randf() * 0.4, Vector3.ZERO, 0.55)
	prop("industrial_storage_cart", Vector3(-22.0, 0.03, -39.0), 0.3, Vector3(1.1, 1.3, 1.6), 0.9)
	prop("tool_cart", Vector3(-27.5, 0.03, -41.5), 1.2, Vector3(1.2, 0.95, 0.75))
	tube(Vector3(-23.5, 2.75, -37.5), true, true)
	litter(-30.5, -43.0, -17.0, -31.6, 0.03, 14)
	city.commit_kit(false, false, 28.0)
	city.commit(false, 95.0)
	end_building()
	far_core(Vector3(-40.0, 3.0, -44.5), Vector3(47.0, 5.8, 26.0), 95.0)
	shade(Vector3(-40.0, 4.6, -44.5), Vector3(48.0, 9.2, 27.0))
	occ(Vector3(-40.0, 7.5, -44.5), Vector3(47.0, 2.6, 26.0))
	# outside: the name over the doors, the ambulance bay, sandbags, the wreck of an ambulance
	board("CITY HOSPITAL", Vector3(-40.0, 3.7, z1), Vector3(0, 0, 1), 9.0, 1.1, Color(0.08, 0.32, 0.28))
	board("EMERGENCY", Vector3(x1, 3.7, -36.5), Vector3(1, 0, 0), 5.5, 0.9, Color(0.6, 0.08, 0.06))
	rubble(Vector3(-17.5, 0, -29.5), 5.0, 1.5)
	rubble(Vector3(-13.5, 0, -33.0), 3.5, 1.0)
	car("ambulance", Vector3(-24.0, 0, -25.0), 1.35, Vector3(2.05, 2.5, 5.8))
	car("ambulance", Vector3(-12.6, 0, -40.0), 0.15, Vector3(2.05, 2.5, 5.8))
	car("car_burnt", Vector3(-52.0, 0, -20.0), 0.6, Vector3(1.8, 1.3, 4.6))
	car("police", Vector3(-58.0, 0, -14.5), 1.9)
	mis._sandbags(Vector3(-40.0, 0, -27.0), 5)
	mis._sandbags(Vector3(-31.0, 0, -24.0), 3)
	for k in 5:
		prop("concrete_road_barrier", Vector3(-66.0 + k * 1.7, 0, -10.5), 0.0, Vector3(1.55, 0.82, 0.6))
	prop("wheelchair_01", Vector3(-36.0, 0, -28.5), 2.2, Vector3.ZERO, 1.0, 1.5)
	prop("industrial_storage_cart", Vector3(-44.5, 0, -29.0), 0.4, Vector3(1.1, 1.3, 1.6), 0.8)
	city.commit(false, 200.0)
	commit_props()
	guard(Vector3(-40.0, 0.08, -29.0), PI)
	guard(Vector3(-41.0, 0.08, -37.0), PI)
	guard(Vector3(-22.0, 0.08, -36.0), -PI * 0.5)
	guard(Vector3(-50.0, 0.08, -44.8), PI * 0.5, "ak", [Vector3(-60.0, 0.08, -44.8), Vector3(-20.0, 0.08, -44.8)])
	guard(Vector3(-29.5, 0.08, -49.0), PI)
	guard(Vector3(-45.0, 3.05, -44.8), PI * 0.5)
	guard(Vector3(-21.0, 3.05, -38.0), 0.6)


## A hospital bed: the scanned iron frame, a mattress on it (some slipped off, some bare frames).
func bed(p: Vector3, yaw: float) -> void:
	prop("old_bed_frame", p, yaw, Vector3(0.95, 0.6, 2.0))
	var r := rng.randf()
	if r < 0.2:
		return
	var b := Basis(Vector3.UP, yaw)
	if r < 0.35:
		b = b * Basis(Vector3(0, 0, 1), 0.5)
		_tilted_box("m3_linen", p + b * Vector3(0.55, 0.42, 0.1), Vector3(0.86, 0.13, 1.85), b, Color(0.8, 0.78, 0.72))
	else:
		_tilted_box("m3_linen", p + Vector3(0, 0.5, 0), Vector3(0.86, 0.13, 1.85), b, Color(0.86, 0.85, 0.8))
		if rng.randf() < 0.6:
			_tilted_box("m3_linen", p + b * Vector3(0, 0.6, -0.72), Vector3(0.6, 0.1, 0.36), b, Color(0.92, 0.92, 0.9))


## A ward of two beds: bedside cabinets, a chair, things dropped when the place was left.
func _ward(x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	var cx := (x0 + x1) * 0.5
	var deep: bool = abs(z1 - z0) > 9.0
	var zb: float = min(z0, z1) + 1.3
	for sg in [-1.0, 1.0]:
		if rng.randf() < 0.85:
			bed(Vector3(cx + sg * 1.5, y, zb), 0.0)
		if deep and rng.randf() < 0.7:
			bed(Vector3(cx + sg * 1.5, y, zb + 4.6), PI)
	if rng.randf() < 0.7:
		prop("drawer_cabinet", Vector3(x0 + 0.5, y, (z0 + z1) * 0.5), PI * 0.5, Vector3(0.5, 1.9, 1.15))
	if rng.randf() < 0.6:
		prop("plastic_monobloc_chair_01", Vector3(cx + rng.randf_range(-0.6, 0.6), y, max(z0, z1) - 1.6), rng.randf() * TAU, Vector3.ZERO, 1.0, 1.45 if rng.randf() < 0.3 else 0.0)
	if rng.randf() < 0.35:
		prop("wheelchair_01", Vector3(x1 - 1.0, y, max(z0, z1) - 2.5), rng.randf() * TAU, Vector3(0.7, 1.0, 0.9))
	if rng.randf() < 0.5:
		prop("medical_box", Vector3(cx + rng.randf_range(-1.5, 1.5), y, (z0 + z1) * 0.5 + rng.randf_range(-1, 1)), rng.randf() * TAU)
	tube(Vector3(cx, y + 2.72, (z0 + z1) * 0.5), rng.randf() < 0.35, rng.randf() < 0.4, Color(0.86, 0.93, 1.0), 0.9, 6.5)
	litter(x0 + 0.5, min(z0, z1) + 0.5, x1 - 0.5, max(z0, z1) - 0.5, y, 5)


## The operating room: the table under its lamp, instrument trolleys, cabinets, white tiled walls.
func _theatre(x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	var c := Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	# the table: a pedestal, a padded top in three sections
	city.box("frame", c + Vector3(0, 0.4, 0), Vector3(0.45, 0.8, 0.6), 0.0, Color(0.55, 0.57, 0.6))
	city.box("frame", c + Vector3(0, 0.06, 0), Vector3(0.9, 0.12, 1.1), 0.0, Color(0.45, 0.47, 0.5))
	for k in 3:
		city.box("m3_paintwork", c + Vector3(0, 0.88, -0.7 + k * 0.7), Vector3(0.62, 0.1, 0.66), 0.0, Color(0.12, 0.2, 0.18))
	add_shape(c + Vector3(0, 0.47, 0), Vector3(0.7, 0.95, 2.1))
	# the lamp: an arm from the ceiling, a wide dish
	city.box("frame", c + Vector3(0, 2.45, 0.3), Vector3(0.08, 0.6, 0.08), 0.0, Color(0.7, 0.7, 0.72))
	city.cyl("frame", c + Vector3(0, 2.02, 0.0), 0.5, 0.12, 14, Color(0.8, 0.8, 0.82))
	city.cyl("m3_daylight", c + Vector3(0, 2.0, 0.0), 0.4, 0.02, 14)
	var l := OmniLight3D.new()
	l.light_color = Color(0.95, 0.98, 1.0)
	l.light_energy = 1.4
	l.omni_range = 7.0
	l.distance_fade_enabled = true
	l.distance_fade_begin = 30.0
	main.add_child(l)
	l.global_position = c + Vector3(0, 1.8, 0)
	lights.append([l, 2.0, 1.4])
	prop("tool_cart", c + Vector3(1.6, 0, -0.5), 0.2, Vector3(1.2, 0.95, 0.75))
	prop("tool_cart", c + Vector3(-1.7, 0, 0.8), 1.7, Vector3(1.2, 0.95, 0.75))
	prop("drawer_cabinet", Vector3(x0 + 0.5, y, c.z - 1.5), PI * 0.5, Vector3(0.5, 1.9, 1.15))
	prop("drawer_cabinet", Vector3(x0 + 0.5, y, c.z + 0.2), PI * 0.5, Vector3(0.5, 1.9, 1.15))
	prop("medical_box", c + Vector3(1.5, 0.96, -0.5), 0.4)
	if y < 1.0:
		codes_at = c + Vector3(1.75, 0.99, -0.42)
	litter(x0 + 0.5, min(z0, z1) + 0.5, x1 - 0.5, max(z0, z1) - 0.5, y, 4)


# ---------------- more helpers ----------------
func _holed(x: float, z: float, grow := 0.0) -> bool:
	for h in HOLES:
		if (h as Rect2).grow(grow).has_point(Vector2(x, z)):
			return true
	return false


## A sloping slab from a to b (the middle of its top surface at each end): drawn, and solid to walk on.
func ramp(a: Vector3, b: Vector3, width: float, key: String, col: Color, thick := 0.3) -> void:
	var d := b - a
	var len_ := d.length()
	var sl := d / len_
	var side := Vector3.UP.cross(sl).normalized()
	var nrm := sl.cross(side).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var bs := Basis(nrm.cross(sl).normalized(), nrm, sl)
	var mid: Vector3 = (a + b) * 0.5 - nrm * (thick * 0.5)
	_tilted_box(key, mid, Vector3(width, thick, len_), bs, col)
	var rb := StaticBody3D.new()
	rb.set_meta("surf", "concrete")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, thick, len_ + 0.4)
	cs.shape = sh
	rb.add_child(cs)
	main.add_child(rb)
	rb.global_transform = Transform3D(bs, mid)


## A light with no fitting (daylight coming down a stair, a fire's glow).
func glow_light(p: Vector3, col: Color, energy: float, reach: float, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.3
	l.distance_fade_enabled = true
	l.distance_fade_begin = 34.0
	l.distance_fade_length = 8.0
	main.add_child(l)
	l.global_position = p
	if flicker:
		lights.append([l, rng.randf() * 10.0, energy])
	return l


## Sunlight falling through a hole in a roof onto the floor at `p` from `h` above it.
func shaft(p: Vector3, h: float, width: float) -> void:
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.94, 0.82)
	l.light_energy = 5.0
	l.spot_range = h + 3.0
	l.spot_angle = rad_to_deg(atan(width * 0.5 / h)) + 6.0
	l.spot_attenuation = 0.4
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 8.0
	main.add_child(l)
	l.global_position = p + Vector3(0, h, 0)
	l.rotation.x = -PI * 0.5


## Paving over (x0, z0)-(x1, z1), left out over the openings to the car park.
func paving(x0: float, z0: float, x1: float, z1: float, key: String, col: Color) -> void:
	var z := z0
	while z < z1 - 0.01:
		var x := x0
		var run := -1.0e9
		while x < x1 + 0.01:
			var open_: bool = x >= x1 - 0.01 or _holed(x + 2.5, z + 2.5)
			if not open_ and run < -1.0e8:
				run = x
			if open_ and run > -1.0e8:
				city.face(key, Vector3((run + x) * 0.5, 0.02, z + 2.5), Vector3((x - run) * 0.5, 0, 0), Vector3(0, 0, -2.5), col)
				run = -1.0e9
			x += 5.0
		z += 5.0


## A shipping container (6 m): corrugated steel in a faded colour, door bars at one end.
func container(p: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var c := p + Vector3(0, 1.3, 0)
	_tilted_box("m3_iron", c, Vector3(2.44, 2.59, 6.06), b, col)
	# corner posts, top and bottom rails, the door bars
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_tilted_box("m3_paintwork", c + b * Vector3(sx * 1.2, 0, sz * 3.0), Vector3(0.14, 2.63, 0.14), b, col.darkened(0.25))
		for sy in [-1.0, 1.0]:
			_tilted_box("m3_paintwork", c + b * Vector3(sx * 1.2, sy * 1.26, 0), Vector3(0.12, 0.12, 6.1), b, col.darkened(0.25))
	for k in 4:
		_tilted_box("frame", c + b * Vector3(-0.9 + k * 0.6, 0, 3.06), Vector3(0.05, 2.3, 0.05), b, Color(0.5, 0.5, 0.5))
	_tilted_box("m3_paintwork", c + b * Vector3(0, 0, 3.045), Vector3(0.04, 2.5, 0.03), b, col.darkened(0.4))
	var cb: StaticBody3D = solid(c, Vector3(2.44, 2.59, 6.06), yaw, "metal")
	cb.set_meta("pierce", "sheet")
	shade(c, Vector3(2.44, 2.59, 6.06), yaw)
	if abs(sin(yaw)) < 0.1 or abs(cos(yaw)) < 0.1:
		occ(c, Vector3(2.2, 2.4, 5.8) if abs(sin(yaw)) < 0.1 else Vector3(5.8, 2.4, 2.2))
	if p.y < 0.5:
		main.extra_cover.append([p + b * Vector3(1.5, 0, 0), 0.7])
		main.extra_cover.append([p + b * Vector3(-1.5, 0, 0), 0.7])


## A guard: `kind` and gun by turn; route: points he walks round.
func guard(p: Vector3, yaw: float, gun := "ak", route := []) -> void:
	posts.append([p, yaw, ["olive", "blue", "gasmask"][posts.size() % 3], gun, route])


## A pile of something stacked from a scanned prop: n along x, m along z, k high.
func stack(id: String, p: Vector3, yaw: float, n: int, m: int, k: int, size: Vector3) -> void:
	var b := Basis(Vector3.UP, yaw)
	for i in n:
		for j in m:
			for l in k:
				if l == k - 1 and k > 1 and rng.randf() < 0.3:
					continue
				prop(id, p + b * Vector3((i - (n - 1) * 0.5) * size.x, l * size.y, (j - (m - 1) * 0.5) * size.z), yaw + rng.randf_range(-0.06, 0.06))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(n * size.x, k * size.y, m * size.z)
	cs.shape = sh
	cs.position = p + Vector3(0, k * size.y * 0.5, 0)
	cs.rotation.y = yaw
	prop_body.add_child(cs)
	if k * size.y > 0.7:
		main.extra_cover.append([p, 0.6])


# ---------------- the underground car park (under the south-west block) ----------------
func _parking() -> void:
	var x0 := -70.0
	var x1 := -10.0
	var z0 := 10.0
	var z1 := 70.0
	begin_building()
	chunker = func(c: Vector3) -> String: return "p%d%d" % [int(c.x > -40.0), int(c.z > 40.0)]
	var fc := Color(0.6, 0.6, 0.6)
	var wc := Color(0.55, 0.55, 0.55)
	for i in 6:
		for j in 6:
			var c := Vector3(x0 + i * 10.0 + 5.0, PY, z0 + j * 10.0 + 5.0)
			_ck(c)
			city.face("m3_dark_floor", c, Vector3(5, 0, 0), Vector3(0, 0, -5), fc)
	for i in 12:
		for j in 12:
			var c := Vector3(x0 + i * 5.0 + 2.5, -0.42, z0 + j * 5.0 + 2.5)
			if _holed(c.x, c.z):
				continue
			_ck(c)
			city.face("m3_dark_wall", c, Vector3(2.5, 0, 0), Vector3(0, 0, 2.5), Color(0.5, 0.5, 0.5))
			city.face("m3_dark_wall", c + Vector3(0, 0.03, 0), Vector3(2.5, 0, 0), Vector3(0, 0, -2.5), Color(0.5, 0.5, 0.5))   # (its top: this is what casts the ground's shadow)
	add_shape(Vector3(-40, PY - 0.2, 40), Vector3(60, 0.4, 60))
	wall(Vector2(x0, z0), Vector2(x1, z0), PY, 3.0, 0.4, "m3_dark_wall", wc)
	wall(Vector2(x1, z0), Vector2(x1, z1), PY, 3.0, 0.4, "m3_dark_wall", wc)
	wall(Vector2(x1, z1), Vector2(x0, z1), PY, 3.0, 0.4, "m3_dark_wall", wc)
	wall(Vector2(x0, z1), Vector2(x0, z0), PY, 3.0, 0.4, "m3_dark_wall", wc)
	# the ramp's inner wall, and the space under its top closed off
	wall(Vector2(-64.8, 20), Vector2(-64.8, 40), PY, 3.0, 0.4, "m3_dark_wall", wc)
	wall(Vector2(-70, 19.8), Vector2(-65, 19.8), PY, 3.0, 0.4, "m3_dark_wall", wc)
	# pillars (a yellow band round the foot of each), beams along every row
	var rows := [15.5, 22.5, 32.5, 39.5, 49.5, 56.5, 66.5]
	for iz in rows.size():
		var z: float = rows[iz]
		for ix in 7:
			var p := Vector3(-62.5 + ix * 7.5, PY, z)
			if _holed(p.x, p.z, 2.5):
				continue
			_ck(p)
			city.box("m3_dark_wall", p + Vector3(0, 1.5, 0), Vector3(0.6, 3.0, 0.6), 0.0, wc)
			city.box("m3_paintwork", p + Vector3(0, 0.5, 0), Vector3(0.63, 1.0, 0.63), 0.0, Color(0.6, 0.48, 0.08))
			city.box("m3_paintwork", p + Vector3(0, 0.75, 0), Vector3(0.64, 0.14, 0.64), 0.0, Color(0.08, 0.08, 0.08))
			add_shape(p + Vector3(0, 1.5, 0), Vector3(0.6, 3.0, 0.6))
			main.extra_cover.append([p, 0.6])
		for k in 5:
			var bc := Vector3(-65.0 + k * 11.0 + 5.5, -0.6, z)
			if _holed(bc.x, bc.z, 1.0):
				continue
			_ck(bc)
			city.box("m3_dark_wall", bc, Vector3(11.0, 0.4, 0.45), 0.0, wc.darkened(0.1))
	# bays: white lines; cars left where they stood (some under sheets, some burnt out)
	var bays := [[10.5, 15.5], [22.5, 27.5], [27.5, 32.5], [39.5, 44.5], [44.5, 49.5], [56.5, 61.5], [61.5, 66.5]]
	var kinds := ["car_burnt", "pickup", "car_burnt", "van_burnt"]
	var nk := 0
	for bz in bays:
		var zm: float = (bz[0] + bz[1]) * 0.5
		for k in 23:
			var x := -67.5 + k * 2.5
			if (x < -64.0 and bz[1] > 19.0 and bz[0] < 41.0) or _holed(x, zm, 2.6):
				continue
			_ck(Vector3(x, PY, zm))
			city.face("m3_paintwork", Vector3(x, PY + 0.012, zm), Vector3(0.05, 0, 0), Vector3(0, 0, -2.5), Color(0.62, 0.62, 0.58))
			if k < 22 and rng.randf() < 0.2 and not _holed(x + 1.25, zm, 3.2) and abs(fmod(x + 1.25 + 62.5 + 75.0, 7.5)) > 0.9:
				var cp := Vector3(x + 1.25, PY, zm)
				var yaw: float = (0.0 if rng.randf() < 0.5 else PI) + rng.randf_range(-0.06, 0.06)
				if rng.randf() < 0.72:
					prop("covered_car", cp + Vector3(0, 0.29, 0), yaw, Vector3(1.75, 1.4, 4.3))
				else:
					var kd: String = kinds[nk % kinds.size()]
					car(kd, cp, yaw, Vector3(2.05, 2.4, 5.0) if kd == "van_burnt" else (Vector3(1.9, 1.8, 5.0) if kd == "pickup" else Vector3(1.8, 1.3, 4.6)))
					nk += 1
	# oil on the floor, fallen concrete, things left behind
	for i in 26:
		var p := Vector3(rng.randf_range(x0 + 2, x1 - 2), PY, rng.randf_range(z0 + 2, z1 - 2))
		if _holed(p.x, p.z, 1.5) or (p.x < -64.0 and p.z > 19.0 and p.z < 41.0):
			continue
		_ck(p)
		city.decal("m3_scorch", p + Vector3(0, 0.015, 0), rng.randf_range(1.2, 3.2), rng.randf() * TAU)
		if i % 2 == 0:
			var sz := Vector3(rng.randf_range(0.3, 0.9), rng.randf_range(0.08, 0.2), rng.randf_range(0.3, 0.8))
			_tilted_box("m3_dark_wall", p + Vector3(1.0, sz.y * 0.5, 0.6), sz, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.2, 0.2)), Color(0.6, 0.6, 0.6))
	for i in 8:
		var p := Vector3(rng.randf_range(x0 + 3, x1 - 3), PY, [18.5, 35.5, 52.5][i % 3] + rng.randf_range(-2, 2))
		if _holed(p.x, p.z, 2.0) or p.x < -63.0:
			continue
		prop(["old_tyre", "Barrel_01", "trashbag", "cardboard_box_01", "WetFloorSign_01", "metal_jerrycan", "plastic_crate_01", "trashbag"][i], p + Vector3(0, 0.29 if i == 0 else 0.0, 0), rng.randf() * TAU, Vector3(0.5, 0.8, 0.5) if i == 1 else Vector3.ZERO, 1.0, 1.57 if i == 0 else 0.0)
	# strip lights down the aisles: about half still work, a few of them only just
	var n_l := 0
	for az in [19.0, 36.0, 53.0]:
		for k in 5:
			var lp := Vector3(-58.0 + k * 11.5, -0.44, az)
			if _holed(lp.x, lp.z, 1.0):
				continue
			n_l += 1
			tube(lp, n_l % 2 == 0 or n_l % 5 == 0, n_l % 4 == 0, Color(0.78, 0.95, 0.86), 1.7, 11.0)
	tube(Vector3(-40.0, -0.44, 67.0), true, true, Color(0.78, 0.95, 0.86), 1.5, 9.0)
	tube(Vector3(-14.0, -0.44, 28.0), true, false, Color(0.78, 0.95, 0.86), 1.5, 9.0)
	# under the hole a shell left in the plaza: its rubble, a way up for anyone who can climb
	rubble(Vector3(-37.5, PY, 52.5), 4.4, 2.7)
	city.commit(false, 120.0, 2)
	end_building()
	shade(Vector3(-40.0, -0.25, 40.0), Vector3(60.0, 0.2, 60.0))
	for w in [[Vector3(-40.0, -1.8, z0), Vector3(60.0, 3.4, 0.3)], [Vector3(-40.0, -1.8, z1), Vector3(60.0, 3.4, 0.3)], [Vector3(x0, -1.8, 40.0), Vector3(0.3, 3.4, 60.0)], [Vector3(x1, -1.8, 40.0), Vector3(0.3, 3.4, 60.0)]]:
		occ(w[0], w[1])
	# the ground over it hides it from above, and the town from below
	for j in 12:
		var run := -1
		for i in 13:
			var open_: bool = i == 12 or _holed(x0 + i * 5.0 + 2.5, z0 + j * 5.0 + 2.5)
			if not open_ and run < 0:
				run = i
			if open_ and run >= 0:
				occ(Vector3(x0 + (run + i) * 2.5, -0.2, z0 + j * 5.0 + 2.5), Vector3((i - run) * 5.0, 0.3, 5.0))
				run = -1
	# open to the sky (so drawn in the sun): the ramp, the two stairs, the rims of the openings
	begin_building()
	ramp(Vector3(-67.5, 0, 20), Vector3(-67.5, PY, 40), 4.9, "m3_dark_floor", Color(0.75, 0.75, 0.75))
	stairs(Vector3(-17.5, PY, 64.8), Vector3(0, 0, -1), 4.6, 3.4, 4.8)
	stairs(Vector3(-42.5, PY, 29.8), Vector3(0, 0, -1), 4.6, 3.4, 4.8)
	for h in HOLES:
		var r: Rect2 = h
		var cx := r.position.x + r.size.x * 0.5
		var cz := r.position.y + r.size.y * 0.5
		city.box("m3_slab", Vector3(cx, -0.2, r.position.y + 0.03), Vector3(r.size.x, 0.4, 0.06), 0.0, Color(0.6, 0.6, 0.6))
		city.box("m3_slab", Vector3(cx, -0.2, r.end.y - 0.03), Vector3(r.size.x, 0.4, 0.06), 0.0, Color(0.6, 0.6, 0.6))
		city.box("m3_slab", Vector3(r.position.x + 0.03, -0.2, cz), Vector3(0.06, 0.4, r.size.y), 0.0, Color(0.6, 0.6, 0.6))
		city.box("m3_slab", Vector3(r.end.x - 0.03, -0.2, cz), Vector3(0.06, 0.4, r.size.y), 0.0, Color(0.6, 0.6, 0.6))
	var pc := Color(0.8, 0.8, 0.8)
	# low walls round the ramp and the plaza stairs
	wall(Vector2(-70.15, 20), Vector2(-70.15, 40.15), 0.0, 0.95, 0.3, "m3_concrete", pc)
	wall(Vector2(-64.85, 20), Vector2(-64.85, 40.15), 0.0, 0.95, 0.3, "m3_concrete", pc)
	wall(Vector2(-70.3, 40.15), Vector2(-64.7, 40.15), 0.0, 0.95, 0.3, "m3_concrete", pc)
	wall(Vector2(-20.15, 60), Vector2(-20.15, 65.15), 0.0, 0.95, 0.3, "m3_concrete", pc)
	wall(Vector2(-14.85, 60), Vector2(-14.85, 65.15), 0.0, 0.95, 0.3, "m3_concrete", pc)
	wall(Vector2(-20.3, 65.15), Vector2(-14.7, 65.15), 0.0, 0.95, 0.3, "m3_concrete", pc)
	# a frame over the ramp's mouth with the sign on it
	for sx in [-70.15, -64.85]:
		city.box("m3_concrete", Vector3(sx, 1.6, 20.0), Vector3(0.4, 3.2, 0.4), 0.0, pc)
	city.box("m3_concrete", Vector3(-67.5, 3.0, 20.0), Vector3(5.7, 0.5, 0.4), 0.0, pc)
	city.commit(false, 160.0)
	end_building()
	board("PARKING", Vector3(-67.5, 3.0, 19.8), Vector3(0, 0, -1), 3.6, 0.42, Color(0.05, 0.2, 0.5))
	board("PARKING", Vector3(-17.5, 0.55, 65.3), Vector3(0, 0, 1), 3.0, 0.4, Color(0.05, 0.2, 0.5))
	# daylight coming down the ways in, the sun through the shell hole
	glow_light(Vector3(-67.5, -1.4, 37.0), Color(0.85, 0.9, 1.0), 1.3, 11.0)
	glow_light(Vector3(-17.5, -1.2, 64.0), Color(0.85, 0.9, 1.0), 1.2, 9.0)
	glow_light(Vector3(-42.5, -1.2, 29.0), Color(0.85, 0.9, 1.0), 0.9, 8.0)
	shaft(Vector3(-37.5, PY + 2.0, 52.5), 4.4, 5.0)
	glow_light(Vector3(-37.5, -1.0, 52.5), Color(1.0, 0.94, 0.82), 1.4, 10.0)
	guard(Vector3(-30.0, PY, 36.0), PI * 0.5, "ak", [Vector3(-30.0, PY, 36.0), Vector3(-58.0, PY, 36.0), Vector3(-58.0, PY, 53.0), Vector3(-26.0, PY, 53.0)])
	guard(Vector3(-22.0, PY, 19.0), -PI * 0.5)
	guard(Vector3(-50.0, PY, 60.0), 0.6)
	commit_props(90.0)


# ---------------- the mall and its plaza (south-west, over the car park) ----------------
func _mall() -> void:
	var x0 := -62.0
	var x1 := -26.0
	var z0 := 14.0
	var z1 := 38.0
	begin_building()
	chunker = func(c: Vector3) -> String: return "m%d" % int(c.x > -44.0)
	var plan := func(side: String, i: int, f: int, k: int) -> String:
		if f == 0:
			if (side == "s" or side == "n") and (i == 5 or i == 6):
				return "D"
			if (side == "e" or side == "w") and (i == 3 or i == 4):
				return "D"
			return "B" if rng.randf() < 0.65 else "W"
		return "B" if rng.randf() < 0.5 else "W"
	shell(x0, z0, x1, z1, 2, 2, plan, "m3_plaster", Color(0.9, 0.9, 0.9), 1)
	var wc := Color(0.9, 0.9, 0.9)
	var y := 0.03
	slab(x0, z0, x1, z1, y, "m3_brown_tiles", Color(0.85, 0.85, 0.85), "", wc, HOLES[2], false)
	slab(x0, z0, x1, z1, 3.0, "", wc, "m3_ceiling", wc)
	city.face("k_roof", Vector3((x0 + x1) * 0.5, 6.0, (z0 + z1) * 0.5), Vector3((x1 - x0) * 0.5, 0, 0), Vector3(0, 0, -(z1 - z0) * 0.5))
	# the concourse between the supermarket (north) and four shops (south)
	iwall(Vector2(x0, 22.0), Vector2(x1, 22.0), y, "m3_plaster", wc, [6.0, 18.0, 30.0], 4.0)
	iwall(Vector2(x0, 30.0), Vector2(x1, 30.0), y, "m3_plaster", wc, [4.5, 12.0, 24.0, 31.5], 3.0)
	for px in [-53.0, -44.0, -35.0]:
		iwall(Vector2(px, 30.0), Vector2(px, z1), y, "m3_plaster", wc)
	wall(Vector2(-45.15, 25.0), Vector2(-45.15, 30.0), y, 1.0, 0.12, "m3_plaster", wc)
	wall(Vector2(-39.85, 25.0), Vector2(-39.85, 30.0), y, 1.0, 0.12, "m3_plaster", wc)
	# supermarket: rows of shelving, some pushed over; boxes, the tills by the doors
	for rw in 2:
		for k in 15:
			var sx := -60.0 + k * 2.2
			if abs(sx + 44.0) < 2.4 or rng.randf() < 0.12:
				continue
			var fallen := rng.randf() < 0.12
			prop("steel_frame_shelves_01", Vector3(sx, y + (0.3 if fallen else 0.0), 16.6 + rw * 2.7), 0.0, Vector3(1.45, 0.7 if fallen else 2.7, 0.7), 0.13, 1.45 if fallen else 0.0)
			if rng.randf() < 0.6:
				prop(["cardboard_box_01", "plastic_crate_01", "industrial_pastic_container"][k % 3], Vector3(sx + rng.randf_range(-0.5, 0.5), y, 17.8 + rw * 2.7), rng.randf() * TAU)
	for k in 3:
		prop("metal_office_desk", Vector3(-56.0 + k * 12.0, y, 20.9), 0.0, Vector3(2.0, 0.8, 0.95))
	prop("industrial_storage_cart", Vector3(-30.0, y, 20.0), 0.7, Vector3(1.1, 1.3, 1.6), 0.8)
	prop("hand_truck", Vector3(-28.5, y, 15.5), 2.1)
	stack("cardboard_box_01", Vector3(-27.6, y, 17.5), 0.2, 2, 2, 2, Vector3(0.42, 0.33, 0.55))
	# cafe: the coffee cart, tables and stools; a shop of televisions; a chemist's; a furniture shop
	prop("CoffeeCart_01", Vector3(-58.0, y, 36.6), 0.0, Vector3(2.2, 1.7, 1.1))
	for k in 3:
		var tp := Vector3(-60.0 + k * 2.6, y, 32.6 + (k % 2) * 1.2)
		prop("round_wooden_table_01", tp, 0.0, Vector3(1.0, 0.74, 1.0), 0.74)
		for q in 3:
			var a := q * TAU / 3.0 + k
			prop("bar_chair_round_01", tp + Vector3(cos(a), 0, sin(a)) * 0.95, a, Vector3.ZERO, 0.65, 1.5 if rng.randf() < 0.25 else 0.0)
	for k in 4:
		prop("worn_metal_rack", Vector3(-52.2 + k * 1.05, y, 37.5), 0.0, Vector3(0.95, 1.9, 0.6))
		if k < 3:
			prop("Television_01", Vector3(-51.5 + k * 2.2, y + 0.79, 33.0), PI + rng.randf_range(-0.3, 0.3))
	prop("metal_office_desk", Vector3(-50.5, y, 33.0), 0.0, Vector3(2.0, 0.8, 0.95))
	prop("metal_office_desk", Vector3(-47.4, y, 33.0), 0.0, Vector3(2.0, 0.8, 0.95))
	prop("Television_01", Vector3(-46.0, y, 36.0), 2.0, Vector3.ZERO, 1.0, 1.3)
	for k in 5:
		prop("worn_metal_rack", Vector3(-43.2 + k * 1.05, y, 37.5), 0.0, Vector3(0.95, 1.9, 0.6))
		prop("medical_box", Vector3(-43.0 + k * 1.3, y, rng.randf_range(32.0, 36.0)), rng.randf() * TAU)
	prop("drawer_cabinet", Vector3(-35.6, y, 34.0), -PI * 0.5, Vector3(0.5, 1.9, 1.15))
	prop("metal_office_desk", Vector3(-40.5, y, 32.2), 0.0, Vector3(2.0, 0.8, 0.95))
	prop("sofa_03", Vector3(-30.5, y, 37.2), PI, Vector3(2.7, 0.9, 0.9))
	prop("sofa_03", Vector3(-33.9, y, 34.0), PI * 0.5, Vector3(0.9, 0.9, 2.7))
	prop("modern_arm_chair_01", Vector3(-28.0, y, 33.5), -0.9, Vector3(0.8, 1.0, 0.9))
	prop("modern_arm_chair_01", Vector3(-30.0, y, 32.0), 2.6, Vector3.ZERO, 1.0, 1.4)
	prop("round_wooden_table_01", Vector3(-30.6, y, 34.6), 0.0, Vector3(1.0, 0.5, 1.0), 0.6)
	# the concourse
	for k in 4:
		prop("painted_wooden_bench", Vector3(-58.0 + k * 9.5, y, 26.0), PI * 0.5 * (k % 2), Vector3(1.2, 0.9, 0.5) if k % 2 == 0 else Vector3(0.5, 0.9, 1.2))
		prop("planter_box_01", Vector3(-55.0 + k * 9.0, y, 23.0), 0.0, Vector3(0.9, 0.42, 0.42))
		prop("trashbag", Vector3(-52.0 + k * 8.0, y, 29.4), rng.randf() * TAU)
		prop("trashbag", Vector3(-51.5 + k * 8.0, y, 29.2), rng.randf() * TAU)
	prop("WetFloorSign_01", Vector3(-36.0, y, 26.5), 0.4)
	prop("korean_fire_extinguisher_01", Vector3(-26.5, y, 22.6), 0.0)
	for k in 5:
		tube(Vector3(-58.0 + k * 7.5, 2.72, 26.0), k % 2 == 0, k == 2)
	tube(Vector3(-50.0, 2.72, 18.0), true, false)
	tube(Vector3(-32.0, 2.72, 18.0), false)
	tube(Vector3(-39.5, 2.72, 34.0), true, true)
	litter(x0 + 1, 22.5, x1 - 1, 29.5, y, 26)
	litter(x0 + 1, 14.5, x1 - 1, 21.5, y, 22)
	litter(x0 + 1, 30.5, x1 - 1, 37.5, y, 20)
	city.commit_kit(false, false, 22.0)
	city.commit(false, 90.0)
	end_building()
	far_core(Vector3(-44.0, 1.5, 26.0), Vector3(35.0, 2.9, 23.0), 90.0)
	shade(Vector3(-44.0, 3.1, 26.0), Vector3(36.0, 6.2, 24.0))
	occ(Vector3(-44.0, 4.6, 26.0), Vector3(35.0, 2.6, 23.0))
	board("CENTRAL MALL", Vector3(-44.0, 3.7, z1), Vector3(0, 0, 1), 8.0, 1.0, Color(0.5, 0.08, 0.1))
	board("CENTRAL MALL", Vector3(-44.0, 3.7, z0), Vector3(0, 0, -1), 8.0, 1.0, Color(0.5, 0.08, 0.1))
	board("SUPERMARKET", Vector3(-31.5, 3.7, z0), Vector3(0, 0, -1), 6.5, 0.9, Color(0.1, 0.36, 0.14))
	board("CAFE", Vector3(-57.0, 3.6, z1), Vector3(0, 0, 1), 2.8, 0.8, Color(0.25, 0.14, 0.08))
	# the plaza: paving, benches and planters, cafe tables outside, wrecks, the shell hole
	paving(-65.0, 40.0, -10.0, 70.0, "m3_cracked", Color(0.8, 0.8, 0.8))
	paving(-65.0, 10.0, -10.0, 15.0, "m3_cracked", Color(0.8, 0.8, 0.8))
	paving(-25.0, 15.0, -10.0, 40.0, "m3_cracked", Color(0.8, 0.8, 0.8))
	for k in 5:
		prop("outdoor_table_chair_set_01", Vector3(-60.0 + k * 2.4, 0.02, 41.5 + (k % 2) * 1.6), rng.randf() * TAU, Vector3(0.8, 0.8, 1.6), 1.0, 1.45 if k == 3 else 0.0)
	for k in 6:
		prop("painted_wooden_bench", Vector3(-56.0 + k * 8.0, 0.02, 57.0 + (k % 2) * 9.0), rng.randf_range(-0.2, 0.2), Vector3(1.2, 0.9, 0.5))
		prop("planter_box_01", Vector3(-58.0 + k * 9.0, 0.02, 46.0), 0.0, Vector3(1.8, 0.84, 0.84), 2.0)
		main.extra_cover.append([Vector3(-58.0 + k * 9.0, 0, 46.0), 0.7])
	for k in 4:
		dead_lamp(Vector3(-55.0 + k * 13.0, 0.0, 68.0), rng.randf_range(-0.15, 0.15))
	car("car_burnt", Vector3(-30.0, 0, 62.0), 0.9, Vector3(1.8, 1.3, 4.6))
	car("police", Vector3(-24.0, 0, 44.0), 2.5)
	car("van_burnt", Vector3(-52.0, 0, 63.5), 1.6, Vector3(2.05, 2.4, 5.8))
	city.decal("m3_scorch", Vector3(-37.5, 0.05, 52.5), 13.0)
	for i in 22:
		var a := rng.randf() * TAU
		var d := rng.randf_range(3.2, 6.0)
		var s := Vector3(rng.randf_range(0.3, 1.1), rng.randf_range(0.1, 0.3), rng.randf_range(0.3, 0.9))
		_tilted_box("m3_cracked", Vector3(-37.5 + cos(a) * d, s.y * 0.4, 52.5 + sin(a) * d), s, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.5, 0.5)), Color(0.7, 0.7, 0.7))
	mis._sandbags(Vector3(-20.0, 0, 56.5), 4)
	rubble(Vector3(-27.0, 0, 40.5), 4.0, 1.3)
	city.commit(false, 200.0)
	commit_props()
	guard(Vector3(-52.0, 0.05, 23.6), PI * 0.5, "ak", [Vector3(-58.0, 0.05, 23.6), Vector3(-30.0, 0.05, 23.6)])
	guard(Vector3(-48.0, 0.05, 18.5), 0.0)
	guard(Vector3(-22.0, 0.05, 54.0), 0.4)
	guard(Vector3(-50.0, 0.05, 50.0), 2.0, "ak", [Vector3(-50.0, 0.05, 50.0), Vector3(-60.0, 0.05, 66.0), Vector3(-28.0, 0.05, 66.0)])


# ---------------- the enemy headquarters (north-east) ----------------
var radio_set: StaticBody3D
var plans_at := Vector3.ZERO
var codes_at := Vector3.ZERO


func _hq() -> void:
	var gc := Color(0.82, 0.82, 0.8)
	# the compound wall: gates south (the checkpoint) and west, a breach in the north side
	begin_building()
	wall(Vector2(14, -14), Vector2(68, -14), 0.0, 2.7, 0.35, "m3_concrete", gc, [[24.0, 30.0, 0.0, 2.7]])
	wall(Vector2(68, -14), Vector2(68, -68), 0.0, 2.7, 0.35, "m3_concrete", gc)
	wall(Vector2(68, -68), Vector2(14, -68), 0.0, 2.7, 0.35, "m3_concrete", gc, [[14.0, 19.0, 0.0, 2.7]])
	wall(Vector2(14, -68), Vector2(14, -14), 0.0, 2.7, 0.35, "m3_concrete", gc, [[24.0, 28.0, 0.0, 2.7]])
	for k in 27:
		# coiled wire along the top
		if k * 2.0 < 24.0 or k * 2.0 >= 30.0:
			city.cyl("frame", Vector3(14.5 + k * 2.0, 2.7, -14.0), 0.22, 0.04, 8, Color(0.25, 0.25, 0.25))
	rubble(Vector3(51.5, 0, -68.0), 4.5, 1.2)
	rubble(Vector3(49.0, 0, -65.5), 2.5, 0.7)
	# the checkpoint at the south gate: a hut, a pole across, sandbags, blocks to weave through
	wall(Vector2(32.0, -17.5), Vector2(34.4, -17.5), 0.0, 2.3, 0.12, "m3_iron", gc, [[0.7, 1.7, 0.9, 1.9]])
	wall(Vector2(32.0, -19.9), Vector2(34.4, -19.9), 0.0, 2.3, 0.12, "m3_iron", gc)
	wall(Vector2(34.4, -17.5), Vector2(34.4, -19.9), 0.0, 2.3, 0.12, "m3_iron", gc)
	wall(Vector2(32.0, -19.9), Vector2(32.0, -17.5), 0.0, 2.3, 0.12, "m3_iron", gc, [[0.7, 1.7, 0.0, 2.0]])
	city.box("m3_rusty", Vector3(33.2, 2.36, -18.7), Vector3(2.9, 0.08, 2.9), 0.0, Color(0.8, 0.8, 0.8))
	city.box("frame", Vector3(37.4, 0.55, -14.6), Vector3(0.2, 1.1, 0.2), 0.0, Color(0.3, 0.3, 0.3))
	# (the pole stands raised: the gate is open)
	var pb := Basis(Vector3(0, 0, 1), 1.05)
	for k in 6:
		_tilted_box("m3_paintwork", Vector3(37.4, 1.05, -14.6) + pb * Vector3(0.5 + k * 1.0, 0, 0), Vector3(1.0, 0.1, 0.1), pb, Color(0.75, 0.1, 0.08) if k % 2 == 0 else Color(0.85, 0.85, 0.82))
	city.commit(false, 200.0)
	end_building()
	for w in [[Vector3(26.0, 1.35, -14.0), Vector3(24.0, 2.7, 0.35)], [Vector3(56.0, 1.35, -14.0), Vector3(24.0, 2.7, 0.35)], [Vector3(68.0, 1.35, -41.0), Vector3(0.35, 2.7, 54.0)],
			[Vector3(61.0, 1.35, -68.0), Vector3(14.0, 2.7, 0.35)], [Vector3(31.5, 1.35, -68.0), Vector3(35.0, 2.7, 0.35)], [Vector3(14.0, 1.35, -56.0), Vector3(0.35, 2.7, 24.0)],
			[Vector3(14.0, 1.35, -27.0), Vector3(0.35, 2.7, 26.0)]]:
		shade(w[0], w[1])
		occ(w[0], w[1])
	shade(Vector3(33.2, 1.2, -18.7), Vector3(2.6, 2.4, 2.6))
	board("RESTRICTED AREA", Vector3(47.5, 1.9, -13.8), Vector3(0, 0, 1), 4.6, 0.6, Color(0.6, 0.08, 0.06))
	mis._sandbags(Vector3(36.0, 0, -11.0), 5)
	mis._sandbags(Vector3(45.5, 0, -11.5), 5)
	mis._sandbags(Vector3(41.0, 0, -22.0), 6)
	for k in 4:
		prop("concrete_road_barrier", Vector3(38.5 + (k % 2) * 3.2, 0, -9.0 + k * 1.0 - 2.0 * (k / 2)), 0.1, Vector3(1.55, 0.82, 0.6))
		main.extra_cover.append([Vector3(38.5 + (k % 2) * 3.2, 0, -9.0 + k * 1.0 - 2.0 * (k / 2)), 0.6])
	prop("portable_searchlight", Vector3(34.6, 2.42, -17.3), 0.6, Vector3.ZERO, 3.0)
	# the yard: lorries, an armoured carrier, fuel, crates, a generator, a watchtower in the corner
	car("truck_mil", Vector3(20.0, 0, -26.0), 0.05, Vector3(2.5, 3.0, 7.2))
	car("truck_mil", Vector3(24.0, 0, -27.0), -0.05, Vector3(2.5, 3.0, 7.2))
	car("apc", Vector3(52.0, 0, -24.0), 1.3, Vector3(2.9, 2.5, 6.6))
	car("pickup", Vector3(60.0, 0, -32.0), 0.3, Vector3(1.9, 1.8, 5.2))
	car("land_rover", Vector3(47.0, 0, -30.0), 0.6, Vector3(1.55, 2.0, 3.95))
	stack("old_military_crate", Vector3(63.5, 0, -44.0), PI * 0.5, 1, 2, 3, Vector3(1.82, 0.28, 0.97))
	stack("wooden_military_crate", Vector3(63.8, 0, -49.0), 0.0, 2, 2, 2, Vector3(1.25, 0.46, 0.53))
	stack("wooden_crate_02", Vector3(19.0, 0, -52.0), 0.3, 2, 1, 2, Vector3(0.53, 0.45, 1.17))
	for k in 5:
		prop("Barrel_01", Vector3(17.0 + (k % 3) * 0.7, 0, -58.0 - (k / 3) * 0.7), rng.randf() * TAU, Vector3(0.56, 0.87, 0.56))
		prop("metal_jerrycan", Vector3(18.8 + k * 0.3, 0, -60.5), rng.randf() * TAU)
	prop("portable_generator", Vector3(21.5, 0, -40.0), 0.4, Vector3(0.8, 0.56, 0.56))
	prop("propane_tank", Vector3(22.6, 0, -40.6), 0.0, Vector3(0.34, 0.55, 0.34))
	var plat: Vector3 = mis._tower(Vector3(65.0, 0, -18.5))
	guard(plat, PI * 0.8, "svd")
	# the building: three storeys, the two lower ones open; windows on the ground floor bricked up
	var x0 := 24.0
	var x1 := 60.0
	var z0 := -62.0
	var z1 := -38.0
	begin_building()
	chunker = func(c: Vector3) -> String: return "q%d%d" % [int(c.y > 2.9), int(c.x > 42.0)]
	var plan := func(side: String, i: int, f: int, k: int) -> String:
		if f == 0:
			if side == "s" and (i == 5 or i == 6):
				return "D"
			if side == "n" and i == 9:
				return "D"
			return "S" if rng.randf() < 0.45 else ("B" if rng.randf() < 0.3 else "W")
		return "B" if rng.randf() < 0.35 else "W"
	shell(x0, z0, x1, z1, 3, 3, plan, "m3_green", Color(0.9, 0.9, 0.9), 2)
	var wc := Color(0.9, 0.9, 0.9)
	var fc := Color(0.9, 0.9, 0.9)
	city.face("m3_floor", Vector3((x0 + x1) * 0.5, 0.03, (z0 + z1) * 0.5), Vector3((x1 - x0) * 0.5, 0, 0), Vector3(0, 0, -(z1 - z0) * 0.5), fc)
	var hole := stairs(Vector3(25.3, 0.03, -52.6), Vector3(0, 0, -1), 1.5, 2.97, 4.6)
	slab(x0, z0, x1, z1, 3.0, "m3_floor", fc, "m3_ceiling", wc, hole)
	slab(x0, z0, x1, z1, 6.0, "", fc, "m3_ceiling", wc)
	slab(x0, z0, x1, z1, 9.0, "k_roof", Color(1, 1, 1), "", wc)
	var zn := -51.2
	var zs := -48.8
	# ground floor
	var y := 0.03
	iwall(Vector2(x0, zn), Vector2(x1, zn), y, "m3_green", wc, [3.0, 12.0, 24.0, 33.0])
	iwall(Vector2(x0, zs), Vector2(x1, zs), y, "m3_green", wc, [6.0, 18.0, 30.0], 1.4)
	for px in [30.0, 42.0, 54.0]:
		iwall(Vector2(px, z0), Vector2(px, zn), y, "m3_green", wc)
	for px in [36.0, 48.0]:
		iwall(Vector2(px, zs), Vector2(px, z1), y, "m3_green", wc)
	# guard room: desks, screens, lockers
	prop("metal_office_desk", Vector3(27.0, y, -39.0), 0.0, Vector3(2.0, 0.8, 0.95))
	prop("metal_office_desk", Vector3(30.2, y, -39.0), 0.0, Vector3(2.0, 0.8, 0.95))
	prop("Television_01", Vector3(26.6, y + 0.79, -38.9), PI)
	prop("Television_01", Vector3(27.5, y + 0.79, -38.9), PI + 0.2)
	prop("vintage_radio_transceiver", Vector3(30.3, y + 0.79, -39.0), PI)
	prop("modern_arm_chair_01", Vector3(27.2, y, -40.6), 0.2, Vector3(0.8, 1.0, 0.9))
	prop("plastic_monobloc_chair_01", Vector3(30.4, y, -40.5), -0.3)
	for k in 3:
		prop("drawer_cabinet", Vector3(24.5, y, -47.5 + k * 1.2), PI * 0.5, Vector3(0.5, 1.9, 1.15))
	prop("korean_fire_extinguisher_01", Vector3(35.4, y, -48.3), 0.0)
	# the entrance hall: a wall of sandbags facing the door
	mis._sandbags(Vector3(42.0, 0, -44.5), 5)
	prop("metal_office_desk", Vector3(46.4, y, -46.0), PI * 0.5, Vector3(0.95, 0.8, 2.0))
	# mess room
	for k in 2:
		var tp := Vector3(51.5 + k * 5.0, y, -43.5)
		prop("metal_office_desk", tp, PI * 0.5, Vector3(0.95, 0.8, 2.0))
		for q in 4:
			prop("plastic_monobloc_chair_01", tp + Vector3(-0.9 if q < 2 else 0.9, 0, -0.5 + (q % 2) * 1.0), PI * 0.5 if q < 2 else -PI * 0.5, Vector3.ZERO, 1.0, 1.45 if rng.randf() < 0.2 else 0.0)
	prop("Television_01", Vector3(58.6, y, -47.0), -2.2)
	prop("industrial_pastic_container", Vector3(49.0, y, -39.0), 0.3)
	# armoury: crates, racks of ammunition
	stack("old_military_crate", Vector3(33.0, y, -60.5), 0.0, 1, 1, 4, Vector3(1.82, 0.28, 0.97))
	stack("old_military_crate", Vector3(36.0, y, -60.5), 0.0, 1, 1, 2, Vector3(1.82, 0.28, 0.97))
	stack("wooden_military_crate", Vector3(40.6, y, -56.0), PI * 0.5, 1, 2, 3, Vector3(1.25, 0.46, 0.53))
	for k in 4:
		prop("worn_metal_rack", Vector3(30.5, y, -60.0 + k * 1.05), PI * 0.5, Vector3(0.6, 1.9, 0.95))
		for q in 3:
			prop("ammo_box", Vector3(30.5, y + 0.52 + q * 0.47, -60.0 + k * 1.05 + rng.randf_range(-0.2, 0.2)), PI * 0.5, Vector3.ZERO, 1.6)
	# barracks, the store with the generator
	for k in 3:
		bed(Vector3(43.6 + k * 4.2, y, -60.6), 0.0)
		bed(Vector3(43.6 + k * 4.2, y, -53.0), PI)
	prop("drawer_cabinet", Vector3(53.5, y, -56.5), -PI * 0.5, Vector3(0.5, 1.9, 1.15))
	prop("portable_generator", Vector3(56.5, y, -60.5), 0.0, Vector3(0.8, 0.56, 0.56))
	for k in 5:
		prop("metal_jerrycan", Vector3(55.0 + k * 0.35, y, -57.0), rng.randf() * TAU)
		prop("Barrel_01", Vector3(58.9, y, -60.8 + k * 0.62), 0.0, Vector3(0.56, 0.87, 0.56))
	prop("propane_tank", Vector3(55.2, y, -60.8), 0.0, Vector3(0.34, 0.55, 0.34))
	prop("metal_tool_chest", Vector3(57.5, y, -52.2), PI)
	# a desk thrown across the corridor
	prop("metal_office_desk", Vector3(50.5, y + 0.45, -50.0), PI * 0.5, Vector3(0.9, 1.0, 2.0), 1.0, 1.45)
	for k in 5:
		tube(Vector3(27.0 + k * 7.5, y + 2.72, -50.0), k != 3, k == 1, Color(0.95, 0.92, 0.82))
	tube(Vector3(30.0, y + 2.72, -43.5), true, false, Color(0.95, 0.92, 0.82), 0.9, 7.0)
	tube(Vector3(42.0, y + 2.72, -42.5), true, false, Color(0.95, 0.92, 0.82), 0.9, 7.0)
	tube(Vector3(36.0, y + 2.72, -57.0), true, true, Color(0.95, 0.92, 0.82), 0.9, 7.0)
	tube(Vector3(54.0, y + 2.72, -43.5), false)
	litter(x0 + 1, zn + 0.2, x1 - 1, zs - 0.2, y, 10)
	# first floor
	y = 3.0
	iwall(Vector2(30.0, zn), Vector2(x1, zn), y, "m3_green", wc, [7.5, 22.5])
	iwall(Vector2(x0, zs), Vector2(x1, zs), y, "m3_green", wc, [5.0, 13.0, 23.0, 32.0])
	iwall(Vector2(45.0, z0), Vector2(45.0, zn), y, "m3_green", wc)
	iwall(Vector2(30.0, z0), Vector2(30.0, -57.6), y, "m3_green", wc)
	for px in [42.0, 52.0]:
		iwall(Vector2(px, zs), Vector2(px, z1), y, "m3_green", wc)
	for rs in [[Vector2(hole.end.x, hole.position.y), Vector2(hole.end.x, hole.end.y)], [Vector2(hole.position.x, hole.end.y), Vector2(hole.end.x, hole.end.y)]]:
		var ra: Vector2 = rs[0]
		var rb2: Vector2 = rs[1]
		city.box("frame", Vector3((ra.x + rb2.x) * 0.5, y + 1.0, (ra.y + rb2.y) * 0.5), Vector3(abs(rb2.x - ra.x) + 0.05, 0.05, abs(rb2.y - ra.y) + 0.05), 0.0, Color(0.35, 0.36, 0.38))
		add_shape(Vector3((ra.x + rb2.x) * 0.5, y + 0.5, (ra.y + rb2.y) * 0.5), Vector3(abs(rb2.x - ra.x) + 0.05, 1.0, abs(rb2.y - ra.y) + 0.05))
	# command centre: the map table, desks with sets and screens round the walls
	prop("metal_office_desk", Vector3(32.0, y, -43.4), 0.0, Vector3(2.0, 0.8, 1.9))
	prop("metal_office_desk", Vector3(32.0, y, -42.45), PI)
	for k in 4:
		var dp := Vector3(26.0 + k * 4.2, y, -38.9)
		prop("metal_office_desk", dp, 0.0, Vector3(2.0, 0.8, 0.95))
		prop("Television_01" if k % 2 == 0 else "vintage_radio_transceiver", dp + Vector3(0.3, 0.79, 0.05), PI)
		prop("plastic_monobloc_chair_01", dp + Vector3(0.0, 0, -1.3), rng.randf_range(-0.4, 0.4), Vector3.ZERO, 1.0, 1.45 if k == 2 else 0.0)
	for k in 4:
		prop("modern_arm_chair_01", Vector3(30.2 + (k % 2) * 3.6, y, -44.6 + (k / 2) * 2.8), PI * 0.5 * (1 - 2 * (k % 2)))
	prop("steel_frame_shelves_02", Vector3(24.6, y, -45.0), PI * 0.5, Vector3(0.5, 2.1, 0.6))
	prop("steel_frame_shelves_02", Vector3(24.6, y, -44.2), PI * 0.5, Vector3(0.5, 2.1, 0.6))
	prop("Television_01", Vector3(41.2, y + 0.79, -44.0), -PI * 0.5)
	prop("metal_office_desk", Vector3(41.2, y, -44.0), PI * 0.5, Vector3(0.95, 0.8, 2.0))
	# the commander's office
	prop("metal_office_desk", Vector3(56.0, y, -42.0), PI, Vector3(2.0, 0.8, 0.95))
	prop("modern_arm_chair_01", Vector3(56.0, y, -40.6), PI, Vector3(0.8, 1.0, 0.9))
	prop("sofa_03", Vector3(53.0, y, -45.5), PI * 0.5, Vector3(0.9, 0.9, 2.7))
	prop("drawer_cabinet", Vector3(59.5, y, -46.0), -PI * 0.5, Vector3(0.5, 1.9, 1.15))
	prop("vintage_radio_transceiver", Vector3(56.7, y + 0.79, -42.1), 0.3)
	plans_at = Vector3(55.6, y + 0.8, -42.0)
	# briefing room: rows of chairs facing a screen; the dormitory
	for rw in 3:
		for k in 5:
			if rng.randf() < 0.85:
				prop("plastic_monobloc_chair_01", Vector3(33.0 + k * 0.8, y, -59.0 + rw * 1.3), PI * 0.5 + PI * 0.5, Vector3.ZERO, 1.0, 1.45 if rng.randf() < 0.12 else 0.0)
	prop("metal_office_desk", Vector3(35.0, y, -53.2), 0.0, Vector3(2.0, 0.8, 0.95))
	prop("Television_01", Vector3(35.0, y + 0.79, -53.2), PI)
	for k in 3:
		bed(Vector3(47.0 + k * 4.2, y, -60.6), 0.0)
	stack("wooden_military_crate", Vector3(58.0, y, -53.0), 0.0, 1, 2, 2, Vector3(1.25, 0.46, 0.53))
	for k in 5:
		tube(Vector3(27.0 + k * 7.5, y + 2.72, -50.0), k % 2 == 0, k == 4, Color(0.95, 0.92, 0.82))
	tube(Vector3(32.0, y + 2.72, -43.0), true, false, Color(0.95, 0.92, 0.82), 1.1, 8.0)
	tube(Vector3(47.0, y + 2.72, -43.0), true, true, Color(0.95, 0.92, 0.82), 1.0, 7.0)
	tube(Vector3(56.0, y + 2.72, -43.0), true, false, Color(1.0, 0.85, 0.65), 0.9, 6.5)
	tube(Vector3(38.0, y + 2.72, -57.0), false)
	litter(x0 + 1, zn + 0.2, x1 - 1, zs - 0.2, y, 8)
	city.commit_kit(false, false, 22.0)
	city.commit(false, 90.0)
	end_building()
	far_core(Vector3(42.0, 3.0, -50.0), Vector3(35.0, 5.8, 23.0), 90.0)
	shade(Vector3(42.0, 4.6, -50.0), Vector3(36.0, 9.2, 24.0))
	occ(Vector3(42.0, 7.5, -50.0), Vector3(35.0, 2.6, 23.0))
	board("COMMAND", Vector3(33.0, 5.3, zs + 0.08), Vector3(0, 0, 1), 2.2, 0.36, Color(0.12, 0.2, 0.12))
	# the radio set in the signals room (to be destroyed): racks of sets on a bench, an aerial lead up the wall
	radio_set = StaticBody3D.new()
	radio_set.set_meta("surf", "metal")
	radio_set.set_meta("kind", "machine")
	radio_set.set_meta("hp", 520.0)
	var desk: Node3D = load(prop_path % ["metal_office_desk", "metal_office_desk"]).instantiate()
	radio_set.add_child(desk)
	for k in 5:
		var rs2: Node3D = load(prop_path % ["vintage_radio_transceiver", "vintage_radio_transceiver"]).instantiate()
		radio_set.add_child(rs2)
		rs2.position = Vector3(-0.66 + (k % 3) * 0.62, 0.79 + (k / 3) * 0.34, 0.0)
		rs2.scale = Vector3(1.15, 1.0, 1.15)
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = Vector3(2.0, 1.5, 0.95)
	rcs.shape = rsh
	rcs.position.y = 0.75
	radio_set.add_child(rcs)
	main.add_child(radio_set)
	radio_set.global_position = Vector3(47.0, 3.0, -39.0)
	main.machines.append(radio_set)
	prop("portable_generator", Vector3(50.6, 3.0, -39.2), 0.0, Vector3(0.8, 0.56, 0.56))
	prop("plastic_monobloc_chair_01", Vector3(47.0, 3.0, -40.4), 0.2)
	prop("steel_frame_shelves_02", Vector3(42.6, 3.0, -41.0), PI * 0.5, Vector3(0.5, 2.1, 0.6))
	city.commit(false, 120.0)
	commit_props()
	# the garrison
	guard(Vector3(39.0, 0.05, -11.5), 0.0)
	guard(Vector3(43.5, 0.05, -12.0), 0.2)
	guard(Vector3(33.2, 0.05, -21.5), PI)
	guard(Vector3(30.0, 0.05, -30.0), 0.0, "ak", [Vector3(30.0, 0.05, -30.0), Vector3(62.0, 0.05, -30.0), Vector3(64.0, 0.05, -64.0), Vector3(20.0, 0.05, -64.0), Vector3(18.0, 0.05, -34.0)])
	guard(Vector3(17.5, 0.05, -41.0), -PI * 0.5)
	guard(Vector3(56.0, 0.05, -34.5), 0.5)
	guard(Vector3(42.0, 0.08, -46.2), 0.0)
	guard(Vector3(29.0, 0.08, -44.0), 1.2)
	guard(Vector3(47.0, 0.08, -50.0), PI * 0.5, "ak", [Vector3(32.0, 0.08, -50.0), Vector3(57.0, 0.08, -50.0)])
	guard(Vector3(54.0, 0.08, -45.0), -0.6)
	guard(Vector3(36.0, 3.05, -45.5), 0.3)
	guard(Vector3(49.0, 3.05, -43.5), 0.0)
	guard(Vector3(57.5, 3.05, -45.0), 0.4)
	guard(Vector3(40.0, 3.05, -50.0), -PI * 0.5)


# ---------------- the industrial yard (south-east) ----------------
func _industrial() -> void:
	var bc := Color(0.9, 0.9, 0.9)
	# --- warehouse A: brick, a tin roof on steel trusses; goods on racking; stairs up the outside to the roof
	begin_building()
	chunker = func(c: Vector3) -> String: return "w%d" % int(c.x > 26.0)
	var ax0 := 12.0
	var ax1 := 40.0
	var az0 := 14.0
	var az1 := 38.0
	wall(Vector2(ax0, az0), Vector2(ax1, az0), 0.0, 7.0, 0.35, "m3_brick", bc)
	wall(Vector2(ax0, az1), Vector2(ax0, az0), 0.0, 7.0, 0.35, "m3_brick", bc, [[11.0, 16.0, 0.0, 4.6]])
	wall(Vector2(ax1, az1), Vector2(ax0, az1), 0.0, 7.0, 0.35, "m3_brick", bc, [[11.0, 16.0, 0.0, 4.6], [3.0, 4.2, 0.0, 2.1]])
	wall(Vector2(ax1, az0), Vector2(ax1, az1), 0.0, 7.0, 0.35, "m3_brick", bc, [[16.0, 17.2, 0.0, 2.1]])
	city.face("m3_floor", Vector3(26.0, 0.03, 26.0), Vector3(14.0, 0, 0), Vector3(0, 0, -12.0), Color(0.9, 0.9, 0.9))
	slab(ax0 - 0.4, az0 - 0.4, ax1 + 0.4, az1 + 0.4, 7.24, "m3_rusty", Color(0.9, 0.9, 0.9), "m3_iron", Color(0.7, 0.7, 0.7), Rect2(30.0, 18.0, 5.0, 4.0))
	for k in 6:
		var tx := 14.5 + k * 4.6
		city.box("frame", Vector3(tx, 6.75, 26.0), Vector3(0.14, 0.3, 23.6), 0.0, Color(0.32, 0.3, 0.28))
		city.box("frame", Vector3(tx, 6.2, 26.0), Vector3(0.1, 0.12, 23.6), 0.0, Color(0.32, 0.3, 0.28))
		for q in 8:
			_tilted_box("frame", Vector3(tx, 6.47, 15.5 + q * 3.0), Vector3(0.06, 0.06, 0.7), Basis(Vector3(1, 0, 0), 0.9 * (1 if q % 2 == 0 else -1)), Color(0.32, 0.3, 0.28))
	for k in 3:
		city.box("frame", Vector3(19.0 + k * 7.0, 3.5, 26.0), Vector3(0.24, 7.0, 0.24), 0.0, Color(0.35, 0.3, 0.26))
		add_shape(Vector3(19.0 + k * 7.0, 3.5, 26.0), Vector3(0.24, 7.0, 0.24))
	for rw in 3:
		for k in 5:
			if (rw == 1 and k >= 3) or rng.randf() < 0.12:
				continue
			var rp := Vector3(15.5 + k * 2.4, 0.03, 17.0 + rw * 6.0 + (4.0 if rw == 2 else 0.0))
			prop("steel_frame_shelves_01", rp, 0.0, Vector3(2.2, 4.3, 1.0), 0.2)
			main.extra_cover.append([rp + Vector3(0, 0, 0.9), 0.6])
			for q in 2:
				if rng.randf() < 0.7:
					prop(["wooden_crate_02", "cardboard_box_01", "old_military_crate", "plastic_crate_01"][(k + q + rw) % 4], rp + Vector3(rng.randf_range(-0.5, 0.5), 0.1 + q * 1.32, 0.0), rng.randf_range(-0.2, 0.2) + PI * 0.5)
	stack("wooden_crate_02", Vector3(30.0, 0.03, 30.5), 0.2, 3, 1, 2, Vector3(0.55, 0.45, 1.17))
	stack("cement_bag", Vector3(36.5, 0.03, 34.5), 0.0, 2, 2, 4, Vector3(0.48, 0.18, 0.72))
	stack("old_military_crate", Vector3(34.0, 0.03, 25.5), 1.2, 1, 1, 3, Vector3(1.82, 0.28, 0.97))
	for k in 4:
		prop("Barrel_01", Vector3(37.8, 0.03, 15.4 + k * 0.65), rng.randf() * TAU, Vector3(0.56, 0.87, 0.56))
	prop("hand_truck", Vector3(28.0, 0.03, 35.5), 1.0)
	prop("tool_cart", Vector3(21.0, 0.03, 36.2), 0.1, Vector3(1.2, 0.95, 0.75))
	prop("metal_tool_chest", Vector3(23.0, 0.03, 36.8), PI)
	car("forklift", Vector3(27.5, 0.03, 23.5), 0.8, Vector3(1.3, 2.1, 2.7))
	rubble(Vector3(32.5, 0.03, 20.0), 2.6, 0.7)
	shaft(Vector3(32.5, 1.0, 20.0), 6.4, 5.0)
	glow_light(Vector3(32.5, 3.0, 20.0), Color(1.0, 0.94, 0.82), 1.3, 12.0)
	glow_light(Vector3(13.5, 2.4, 26.5), Color(0.85, 0.9, 1.0), 1.3, 11.0)
	glow_light(Vector3(25.5, 2.4, 36.5), Color(0.85, 0.9, 1.0), 1.3, 11.0)
	tube(Vector3(20.0, 6.1, 20.0), true, true, Color(1.0, 0.9, 0.7), 1.6, 12.0)
	tube(Vector3(20.0, 6.1, 32.0), false)
	tube(Vector3(34.0, 6.1, 31.0), true, false, Color(1.0, 0.9, 0.7), 1.6, 12.0)
	city.commit(false, 220.0)
	end_building()
	shade(Vector3(26.0, 3.7, 26.0), Vector3(28.6, 7.4, 24.6))
	occ(Vector3(26.0, 3.5, 14.0), Vector3(28.0, 7.0, 0.3))
	occ(Vector3(40.0, 3.5, 21.5), Vector3(0.3, 7.0, 15.0))
	occ(Vector3(12.0, 3.5, 19.5), Vector3(0.3, 7.0, 11.0))
	# the stairs up its east side, a rail round the roof on that side
	begin_building()
	stairs(Vector3(41.0, 0.0, 37.6), Vector3(0, 0, -1), 1.3, 7.25, 12.0, "m3_plate", Color(0.6, 0.6, 0.6))
	city.box("m3_plate", Vector3(41.0, 7.2, 24.6), Vector3(1.4, 0.08, 2.0), 0.0, Color(0.6, 0.6, 0.6))
	add_shape(Vector3(41.0, 7.2, 24.6), Vector3(1.4, 0.1, 2.0))
	for k in 6:
		city.box("frame", Vector3(41.6, 3.6, 37.0 - k * 2.6), Vector3(0.1, 7.2, 0.1), 0.0, Color(0.3, 0.3, 0.3))
	# things on the roof: ducts, a tank, a parapet to hide behind
	wall(Vector2(ax0 - 0.2, az0 - 0.2), Vector2(ax1 + 0.2, az0 - 0.2), 7.24, 0.8, 0.25, "m3_brick", bc)
	wall(Vector2(ax0 - 0.2, az1 + 0.2), Vector2(ax1 + 0.2, az1 + 0.2), 7.24, 0.8, 0.25, "m3_brick", bc)
	wall(Vector2(ax0 - 0.2, az0 - 0.2), Vector2(ax0 - 0.2, az1 + 0.2), 7.24, 0.8, 0.25, "m3_brick", bc)
	prop("modular_airduct_rectangular_01", Vector3(20.0, 7.95, 22.0), 0.0, Vector3(7.6, 1.2, 2.6))
	prop("exterior_aircon_unit", Vector3(34.0, 7.55, 34.0), 0.4, Vector3(0.8, 0.9, 0.4))
	city.cyl("m3_rust", Vector3(17.0, 7.24, 33.0), 1.2, 2.2, 14, Color(0.8, 0.8, 0.8))
	add_shape(Vector3(17.0, 8.3, 33.0), Vector3(2.2, 2.2, 2.2))
	city.commit(false, 220.0)
	end_building()
	board("NORTHGATE STORAGE", Vector3(11.8, 5.6, 26.5), Vector3(-1, 0, 0), 9.0, 0.9, Color(0.1, 0.16, 0.3))
	# --- the factory: corrugated walls on a brick plinth, presses, tanks, a conveyor; part of the roof is down
	begin_building()
	chunker = func(c: Vector3) -> String: return "f%d" % int(c.x > 57.0)
	var fx0 := 44.0
	var fx1 := 70.0
	var fz0 := 14.0
	var fz1 := 36.0
	var ic := Color(0.85, 0.85, 0.85)
	wall(Vector2(fx0, fz0), Vector2(fx1, fz0), 0.0, 8.0, 0.3, "m3_iron", ic)
	wall(Vector2(fx1, fz0), Vector2(fx1, fz1), 0.0, 8.0, 0.3, "m3_iron", ic)
	wall(Vector2(fx1, fz1), Vector2(fx0, fz1), 0.0, 8.0, 0.3, "m3_iron", ic, [[10.0, 16.0, 0.0, 5.0]])
	wall(Vector2(fx0, fz1), Vector2(fx0, fz0), 0.0, 8.0, 0.3, "m3_iron", ic, [[14.8, 16.0, 0.0, 2.1]])
	for sd in [[Vector2(fx0, fz0 - 0.05), Vector2(fx1, fz0 - 0.05)], [Vector2(fx1 + 0.05, fz0), Vector2(fx1 + 0.05, fz1)]]:
		wall(sd[0], sd[1], 0.0, 1.1, 0.42, "m3_brick", bc, [], false)
	city.face("m3_floor", Vector3(57.0, 0.03, 25.0), Vector3(13.0, 0, 0), Vector3(0, 0, -11.0), Color(0.85, 0.85, 0.85))
	slab(fx0 - 0.3, fz0 - 0.3, fx1 + 0.3, fz1 + 0.3, 8.24, "m3_rusty", Color(0.85, 0.85, 0.85), "m3_iron", Color(0.65, 0.65, 0.65), Rect2(58.0, 19.0, 6.0, 6.0))
	for k in 5:
		var tx := 46.5 + k * 5.2
		city.box("frame", Vector3(tx, 7.75, 25.0), Vector3(0.16, 0.34, 21.6), 0.0, Color(0.3, 0.28, 0.26))
	# presses along the north wall
	for k in 3:
		var mp := Vector3(47.5 + k * 4.2, 0.03, 16.6)
		city.box("m3_plate", mp + Vector3(0, 0.5, 0), Vector3(2.2, 1.0, 1.6), 0.0, Color(0.5, 0.56, 0.52))
		city.box("m3_plate", mp + Vector3(0, 2.6, -0.45), Vector3(2.0, 3.2, 0.6), 0.0, Color(0.5, 0.56, 0.52))
		city.box("m3_plate", mp + Vector3(0, 3.7, 0.1), Vector3(2.2, 1.0, 1.5), 0.0, Color(0.45, 0.5, 0.47))
		city.cyl("frame", mp + Vector3(0, 1.0, 0.25), 0.22, 2.2, 10, Color(0.7, 0.7, 0.72))
		city.box("m3_paintwork", mp + Vector3(0, 1.08, 0.25), Vector3(1.4, 0.16, 1.0), 0.0, Color(0.6, 0.48, 0.08))
		add_shape(mp + Vector3(0, 2.1, 0), Vector3(2.2, 4.2, 1.6))
		main.extra_cover.append([mp + Vector3(0, 0, 1.4), 0.7])
	# two tanks with their pipes in the north-east corner
	for k in 2:
		var tp := Vector3(63.5 + k * 3.6, 0.03, 16.8)
		city.cyl("m3_rust", tp, 1.3, 4.6, 16, Color(0.85, 0.85, 0.85))
		city.cyl("m3_plate", tp + Vector3(0, 4.6, 0), 1.0, 0.3, 16, Color(0.6, 0.6, 0.6))
		city.cyl("frame", tp + Vector3(1.0, 0, 1.1), 0.09, 6.5, 8, Color(0.45, 0.42, 0.4))
		add_shape(tp + Vector3(0, 2.3, 0), Vector3(2.4, 4.6, 2.4))
	_tilted_box("frame", Vector3(64.5, 6.5, 22.0), Vector3(0.18, 0.18, 9.0), Basis(), Color(0.45, 0.42, 0.4))
	# the conveyor down the middle, its rollers; a control desk
	city.box("m3_plate", Vector3(52.0, 0.75, 27.5), Vector3(11.0, 0.14, 1.1), 0.0, Color(0.45, 0.45, 0.45))
	for k in 6:
		city.box("frame", Vector3(47.0 + k * 2.0, 0.37, 27.5), Vector3(0.12, 0.7, 0.9), 0.0, Color(0.3, 0.3, 0.3))
	for k in 18:
		city.cyl("frame", Vector3(46.8 + k * 0.6, 0.82, 27.5), 0.07, 0.02, 6, Color(0.6, 0.6, 0.62))
	add_shape(Vector3(52.0, 0.45, 27.5), Vector3(11.0, 0.9, 1.1))
	main.extra_cover.append([Vector3(50.0, 0, 28.6), 0.7])
	main.extra_cover.append([Vector3(54.0, 0, 26.4), 0.7])
	for k in 3:
		prop("utility_box_02", Vector3(45.0, 0.03, 29.0 + k * 1.1), PI * 0.5, Vector3(0.45, 1.1, 0.95))
		prop("power_box_01", Vector3(69.6, 1.6, 27.0 + k * 1.2), -PI * 0.5, Vector3.ZERO, 1.6)
	prop("tool_cart", Vector3(56.0, 0.03, 31.5), 0.5, Vector3(1.2, 0.95, 0.75))
	prop("metal_tool_chest", Vector3(57.6, 0.03, 31.0), 2.6)
	prop("metal_tool_chest", Vector3(48.0, 0.03, 22.0), 0.6)
	prop("korean_fire_extinguisher_01", Vector3(44.5, 0.03, 31.9), PI * 0.5)
	prop("modular_airduct_rectangular_01", Vector3(51.0, 6.6, 31.5), 0.0)
	prop("modular_airduct_rectangular_01", Vector3(60.0, 6.6, 31.5), 0.0)
	for k in 4:
		prop("Barrel_01", Vector3(68.6, 0.03, 30.5 + k * 0.63), rng.randf() * TAU, Vector3(0.56, 0.87, 0.56))
	stack("plastic_crate_01", Vector3(66.5, 0.03, 33.8), 0.1, 2, 2, 3, Vector3(0.32, 0.26, 0.42))
	rubble(Vector3(61.0, 0.03, 22.0), 3.4, 1.0)
	for i in 6:
		_tilted_box("m3_rusty", Vector3(61.0 + rng.randf_range(-2.5, 2.5), rng.randf_range(0.4, 1.4), 22.0 + rng.randf_range(-2.5, 2.5)), Vector3(rng.randf_range(1.0, 2.2), 0.04, rng.randf_range(0.8, 1.6)), Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.9, 0.9)), Color(0.8, 0.8, 0.8))
	shaft(Vector3(61.0, 1.2, 22.0), 7.2, 6.0)
	glow_light(Vector3(61.0, 3.4, 22.0), Color(1.0, 0.94, 0.82), 1.5, 13.0)
	glow_light(Vector3(57.0, 2.6, 34.5), Color(0.85, 0.9, 1.0), 1.4, 12.0)
	tube(Vector3(50.0, 7.5, 22.0), true, true, Color(1.0, 0.9, 0.7), 1.7, 13.0)
	tube(Vector3(66.0, 7.5, 31.0), true, false, Color(1.0, 0.9, 0.7), 1.5, 12.0)
	tube(Vector3(50.0, 7.5, 32.0), false)
	city.commit(false, 220.0)
	end_building()
	shade(Vector3(57.0, 4.2, 25.0), Vector3(26.5, 8.4, 22.5))
	occ(Vector3(57.0, 4.0, 14.0), Vector3(26.0, 8.0, 0.3))
	occ(Vector3(70.0, 4.0, 25.0), Vector3(0.3, 8.0, 22.0))
	occ(Vector3(44.0, 4.0, 21.0), Vector3(0.3, 8.0, 14.0))
	board("HALDEN MACHINE WORKS", Vector3(57.0, 6.4, 36.25), Vector3(0, 0, 1), 11.0, 0.9, Color(0.32, 0.14, 0.06))
	# --- the yard: containers, a loading dock under a canopy, lorries, the fence
	begin_building()
	paving(10.0, 40.0, 75.0, 75.0, "m3_cracked", Color(0.72, 0.72, 0.72))
	var cols := [Color(0.5, 0.16, 0.12), Color(0.14, 0.26, 0.42), Color(0.2, 0.36, 0.24), Color(0.62, 0.5, 0.16), Color(0.5, 0.5, 0.5), Color(0.45, 0.25, 0.12)]
	var spots := [[Vector3(16.0, 0, 46.0), 0.0], [Vector3(18.7, 0, 46.0), 0.0], [Vector3(16.0, 2.62, 46.0), 0.03], [Vector3(27.0, 0, 44.5), PI * 0.5], [Vector3(27.0, 0, 47.2), PI * 0.5],
		[Vector3(27.3, 2.62, 45.8), PI * 0.5 + 0.06], [Vector3(38.0, 0, 52.0), 0.4], [Vector3(46.0, 0, 44.0), PI * 0.5], [Vector3(46.0, 2.62, 44.0), PI * 0.5], [Vector3(53.5, 0, 44.0), PI * 0.5],
		[Vector3(36.0, 0, 66.0), PI * 0.5], [Vector3(43.0, 0, 66.0), PI * 0.5], [Vector3(43.0, 2.62, 66.0), PI * 0.5 - 0.04], [Vector3(15.0, 0, 64.0), 0.15]]
	for i in spots.size():
		container(spots[i][0], spots[i][1], cols[i % cols.size()])
	# the dock: a platform with steps and a ramp, a tin canopy on posts
	city.box("m3_concrete", Vector3(66.0, 0.55, 54.0), Vector3(8.0, 1.1, 18.0), 0.0, Color(0.8, 0.8, 0.8))
	add_shape(Vector3(66.0, 0.55, 54.0), Vector3(8.0, 1.1, 18.0))
	ramp(Vector3(66.0, 1.1, 45.0), Vector3(66.0, 0.0, 40.6), 3.0, "m3_concrete", Color(0.8, 0.8, 0.8))
	stairs(Vector3(61.2, 0.0, 61.0), Vector3(1, 0, 0), 1.6, 1.1, 0.9, "m3_concrete", Color(0.8, 0.8, 0.8))
	for k in 4:
		for sx in [62.3, 69.7]:
			city.box("frame", Vector3(sx, 3.1, 46.0 + k * 5.3), Vector3(0.16, 4.0, 0.16), 0.0, Color(0.3, 0.3, 0.3))
	_tilted_box("m3_rusty", Vector3(66.0, 5.15, 54.0), Vector3(9.4, 0.06, 19.0), Basis(Vector3(0, 0, 1), 0.06), Color(0.85, 0.85, 0.85))
	stack("wooden_crate_02", Vector3(67.5, 1.1, 50.0), 0.0, 2, 2, 2, Vector3(0.55, 0.45, 1.17))
	stack("old_military_crate", Vector3(64.5, 1.1, 57.0), PI * 0.5, 1, 1, 3, Vector3(1.82, 0.28, 0.97))
	stack("cement_bag", Vector3(68.0, 1.1, 60.5), 0.0, 2, 2, 3, Vector3(0.48, 0.18, 0.72))
	prop("hand_truck", Vector3(64.0, 1.1, 48.0), 2.2)
	city.commit(false, 220.0)
	end_building()
	shade(Vector3(66.0, 5.15, 54.0), Vector3(9.4, 0.1, 19.0))
	shade(Vector3(66.0, 0.55, 54.0), Vector3(8.0, 1.1, 18.0))
	car("truck_mil", Vector3(59.0, 0, 52.0), PI * 0.5 + 0.03, Vector3(2.5, 3.0, 7.2))
	car("van_burnt", Vector3(24.0, 0, 56.0), 2.0, Vector3(2.05, 2.4, 5.8))
	car("pickup", Vector3(50.0, 0, 58.0), 0.9, Vector3(1.9, 1.8, 5.2))
	car("forklift", Vector3(33.0, 0, 46.5), 2.4, Vector3(1.3, 2.1, 2.7))
	car("forklift", Vector3(56.5, 0, 63.0), 0.3, Vector3(1.3, 2.1, 2.7))
	for k in 7:
		prop("old_tyre", Vector3(21.0 + (k % 3) * 0.62, 0.08 + (k / 3) * 0.17, 68.5), 0.0, Vector3.ZERO, 1.0, 1.57)
	for k in 6:
		prop("Barrel_01", Vector3(48.0 + (k % 3) * 0.62, 0, 70.0 + (k / 3) * 0.62), rng.randf() * TAU, Vector3(0.56, 0.87, 0.56))
	prop("portable_generator", Vector3(31.0, 0, 63.5), 0.6, Vector3(0.8, 0.56, 0.56))
	stack("cement_bag", Vector3(13.5, 0, 55.0), 0.3, 2, 3, 3, Vector3(0.48, 0.18, 0.72))
	mis._sandbags(Vector3(12.0, 0, 48.5), 4)
	fence(Vector2(10.0, 72.0), Vector2(72.0, 72.0), [[14.0, 20.0]])
	fence(Vector2(72.0, 40.0), Vector2(72.0, 72.0))
	fence(Vector2(10.0, 40.0), Vector2(10.0, 72.0), [[10.0, 16.0]])
	city.commit(false, 180.0)
	guard(Vector3(26.0, 0.05, 26.0), PI * 0.5, "ak", [Vector3(20.0, 0.05, 27.5), Vector3(36.0, 0.05, 27.5)])
	guard(Vector3(60.0, 0.05, 29.5), PI)
	guard(Vector3(42.0, 0.05, 30.0), 0.0, "ak", [Vector3(42.0, 0.05, 16.0), Vector3(42.0, 0.05, 38.5)])
	guard(Vector3(33.0, 0.05, 58.0), 0.4, "ak", [Vector3(33.0, 0.05, 58.0), Vector3(55.0, 0.05, 50.0), Vector3(55.0, 0.05, 68.0), Vector3(22.0, 0.05, 62.0)])
	guard(Vector3(64.0, 1.15, 52.0), PI * 0.5)
	guard(Vector3(30.0, 7.3, 34.0), PI * 0.2, "svd")
	commit_props()


# ---------------- the crossroads checkpoint, road blocks ----------------
func _checkpoints() -> void:
	for k in 6:
		var a := k * TAU / 6.0
		prop("concrete_road_barrier_02", Vector3(cos(a) * 5.5, 0.03, sin(a) * 5.5 - 10.0 * 0.0), a + PI * 0.5, Vector3(1.57, 1.1, 0.44))
		main.extra_cover.append([Vector3(cos(a) * 5.5, 0, sin(a) * 5.5), 0.6])
	mis._sandbags(Vector3(-3.0, 0.03, 8.5), 5)
	mis._sandbags(Vector3(3.5, 0.03, -8.5), 5)
	mis._sandbags(Vector3(8.5, 0.03, 3.0), 4)
	car("apc", Vector3(-1.5, 0.03, -1.0), 0.5, Vector3(2.9, 2.5, 6.6))
	car("police", Vector3(9.0, 0.03, -3.4), 1.4)
	prop("portable_generator", Vector3(4.0, 0.03, 4.5), 0.3, Vector3(0.8, 0.56, 0.56))
	prop("portable_searchlight", Vector3(4.6, 0.59, 4.5), 2.4, Vector3.ZERO, 3.0)
	stack("wooden_military_crate", Vector3(-5.0, 0.03, -4.5), 0.4, 1, 2, 2, Vector3(1.25, 0.46, 0.53))
	guard(Vector3(-2.0, 0.08, 7.0), 0.0)
	guard(Vector3(3.0, 0.08, -7.0), PI)
	guard(Vector3(6.5, 0.08, 2.0), -PI * 0.5)
	guard(Vector3(0.0, 0.08, 14.0), 0.0, "ak", [Vector3(0.0, 0.08, 14.0), Vector3(0.0, 0.08, 60.0)])
	# a road block on the south avenue (the way in), a burnt-out bus across the east one
	for k in 4:
		prop("concrete_road_barrier", Vector3(-3.6 + k * 2.4, 0.03, 84.0 + (k % 2) * 1.4), 0.08, Vector3(1.55, 0.82, 0.6))
		main.extra_cover.append([Vector3(-3.6 + k * 2.4, 0, 84.0 + (k % 2) * 1.4), 0.6])
	guard(Vector3(-1.0, 0.08, 80.0), 0.0)
	guard(Vector3(2.5, 0.08, 78.5), 0.2)
	guard(Vector3(-78.0, 0.08, 20.0), 0.0, "ak", [Vector3(-78.0, 0.08, 50.0), Vector3(-78.0, 0.08, -50.0)])
	guard(Vector3(78.0, 0.08, 0.0), 0.0, "ak", [Vector3(78.0, 0.08, 60.0), Vector3(78.0, 0.08, -60.0)])


# ---------------- the whole map ----------------
func build() -> Vector3:
	rng.seed = 303
	city.make_mats3()
	city.night = false
	city.lit_share = 0.0
	city.ac_share = 0.08
	city.broken_share = 0.55
	city.soot_share = 0.12
	prop_body = StaticBody3D.new()
	prop_body.set_meta("surf", "metal")
	main.add_child(prop_body)
	_ground()
	_streets()
	await tick()
	# the outer ring
	var ring := [[-2, -2, [4, 7]], [-1, -2, [4, 6]], [1, -2, [5, 8]], [2, -2, [4, 6]], [-2, -1, [4, 6]], [2, -1, [5, 8]],
		[-2, 1, [3, 5]], [2, 1, [3, 5]], [-2, 2, [4, 6]], [-1, 2, [3, 5]], [1, 2, [3, 5]], [2, 2, [3, 5]]]
	for rb in ring:
		var r := rect(rb[0], rb[1])
		ring_block(r, rb[2], rb[1] == 2 or rb[1] == -1, rb[1] == -2 or rb[1] == 1, rb[0] == 2, rb[0] == -2, 1 if (rb[0] == 1 and rb[1] == -2) or (rb[0] == 2 and rb[1] == -1) else 0)
		await tick()
	_hospital()
	await tick()
	_parking()
	await tick()
	_mall()
	await tick()
	_hq()
	await tick()
	_industrial()
	await tick()
	_checkpoints()
	_street_dressing()
	city.commit(false, 220.0)
	commit_props(150.0)
	return Vector3(0, 0.3, 140)


## A set of traffic lights on the corner at p, its arm reaching out over the road along `yaw`: dead, some knocked askew.
func traffic_light(p: Vector3, yaw: float, lean := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), lean)
	var grey := Color(0.24, 0.25, 0.26)
	_tilted_box("frame", p + b * Vector3(0, 2.7, 0), Vector3(0.16, 5.4, 0.16), b, grey)
	_tilted_box("frame", p + b * Vector3(1.9, 5.3, 0), Vector3(3.8, 0.1, 0.1), b, grey)
	for hd in [Vector3(3.5, 4.75, 0), Vector3(0.0, 3.0, 0.22)]:
		_tilted_box("m3_paintwork", p + b * hd, Vector3(0.34, 1.0, 0.3), b, Color(0.1, 0.1, 0.1))
		for k in 3:
			_tilted_box("m3_paintwork", p + b * (hd + Vector3(0, 0.3 - k * 0.3, 0.16)), Vector3(0.2, 0.2, 0.03), b, [Color(0.25, 0.04, 0.03), Color(0.3, 0.2, 0.03), Color(0.04, 0.2, 0.08)][k])
	solid(p + Vector3(0, 1.5, 0), Vector3(0.2, 3.0, 0.2))


## The stripes of a pedestrian crossing over a road `half` wide, centred at c, the road running along `along`.
func crossing(c: Vector3, along: Vector3, half: float) -> void:
	var across := Vector3.UP.cross(along)
	var k := -half + 0.6
	while k < half - 0.3:
		if rng.randf() < 0.88:
			city.face("panel", c + across * k + Vector3(0, 0.055, 0), across * 0.24, -along * 1.3, Color(0.72, 0.72, 0.68))
		k += 1.0


func _street_dressing() -> void:
	# traffic lights and crossings where the avenues meet each other and the side streets; hoardings and street names
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			traffic_light(Vector3(sx * 5.9, 0.16, sz * 5.9), atan2(sz, sx) + PI * 0.75 + (0.0 if sx * sz > 0.0 else PI * 0.5), rng.randf_range(-0.05, 0.12))
	for q in [Vector3(0, 0, SX), Vector3(0, 0, -SX), Vector3(SX, 0, 0), Vector3(-SX, 0, 0)]:
		var on_z: bool = abs(q.z) > 1.0
		traffic_light(q + (Vector3(5.9, 0.16, 3.9) if on_z else Vector3(3.9, 0.16, 5.9)), PI if on_z else PI * 0.5, rng.randf_range(-0.08, 0.2))
		traffic_light(q - (Vector3(5.9, -0.16, 3.9) if on_z else Vector3(3.9, -0.16, 5.9)), 0.0 if on_z else -PI * 0.5, rng.randf_range(-0.08, 0.1))
		crossing(q + (Vector3(0, 0, 5.0) if on_z else Vector3(5.0, 0, 0)) * (1.0 if (q.z + q.x) < 0.0 else -1.0), Vector3(0, 0, 1) if on_z else Vector3(1, 0, 0), 5.0)
	for d in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		crossing(d * 10.5, d, 5.0)
	board("ORBIT MOBILE", Vector3(8.0, 7.4, 104.0), Vector3(-1, 0, 0), 8.0, 1.5, Color(0.1, 0.3, 0.55))
	board("SUNRISE BANK", Vector3(-10.0, 7.2, 118.0), Vector3(1, 0, 0), 8.0, 1.5, Color(0.6, 0.38, 0.05))
	board("MERIDIAN AVENUE", Vector3(-7.6, 3.2, 9.0), Vector3(0, 0, 1), 2.6, 0.34, Color(0.05, 0.22, 0.12))
	board("HARLOW STREET", Vector3(9.0, 3.2, -7.6), Vector3(-1, 0, 0), 2.4, 0.34, Color(0.05, 0.22, 0.12))
	for sp in [Vector3(-7.6, 0.16, 8.9), Vector3(8.9, 0.16, -7.6)]:
		city.box("frame", sp + Vector3(0, 1.6, 0), Vector3(0.08, 3.2, 0.08), 0.0, Color(0.3, 0.3, 0.3))
	# craters, heaps and wrecks along the avenues; dead lamps; poles down the side streets
	for c in [Vector3(2, 0, 96), Vector3(-3, 0, 40), Vector3(3.5, 0, -30), Vector3(-2, 0, -110), Vector3(60, 0, 2), Vector3(-45, 0, -3), Vector3(118, 0, -2), Vector3(-112, 0, 3),
			Vector3(78, 0, 50), Vector3(-78, 0, -40), Vector3(40, 0, 78), Vector3(-30, 0, -78)]:
		crater(c, rng.randf_range(1.6, 2.8))
	for i in 14:
		var z := -140.0 + i * 21.0
		if abs(z) > 12.0 and abs(abs(z) - SX) > 8.0:
			dead_lamp(Vector3(-6.3 if i % 2 == 0 else 6.3, 0.16, z), rng.randf_range(-0.12, 0.2) * (1 if i % 2 == 0 else -1))
			dead_lamp(Vector3(z, 0.16, -6.3 if i % 2 == 1 else 6.3), rng.randf_range(-0.1, 0.1))
	poles(Vector3(-SX - 4.2, 0, -140), Vector3(-SX - 4.2, 0, 140), 9)
	poles(Vector3(SX + 4.2, 0, -140), Vector3(SX + 4.2, 0, 140), 9)
	for w in [["car_burnt", Vector3(3.2, 0, 112), 0.4], ["car_burnt", Vector3(-2.5, 0, 62), 2.9], ["bus_burnt", Vector3(2.0, 0, 26), 0.25], ["van_burnt", Vector3(-3.0, 0, -52), 3.4],
			["car_burnt", Vector3(34, 0, 3), 1.2], ["car_burnt", Vector3(-58, 0, -2.5), 1.9], ["bus_burnt", Vector3(100, 0, 2.5), 1.45], ["van_burnt", Vector3(-104, 0, -2), 1.7],
			["car_burnt", Vector3(SX + 1, 0, -44), 0.1], ["car_burnt", Vector3(-SX - 1, 0, 30), 3.0], ["van_burnt", Vector3(44, 0, SX + 1), 1.5], ["car_burnt", Vector3(-40, 0, -SX), 1.7]]:
		var kind: String = w[0]
		car(kind, w[1], w[2], Vector3(2.5, 3.0, 10.1) if kind.begins_with("bus") else (Vector3(2.05, 2.4, 5.8) if kind.begins_with("van") else Vector3(1.8, 1.3, 4.6)))
		city.decal("m3_scorch", (w[1] as Vector3) + Vector3(0, 0.07, 0), 9.0 if kind.begins_with("bus") else 6.0)
