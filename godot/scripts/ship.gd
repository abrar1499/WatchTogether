extends Node3D
## Mission 4's world: a freighter at anchor in a bay at night, the sea round her, patrol launches circling, rocky
## islets beyond. Built from the game's scanned surfaces. The ship lies along x, her bow toward +x; the water is y = 0.

var main: Node
var mis: Node
var city
var posts := []            # soldiers: [pos, face, kind, gun, route]
var t := 0.0

const D := 5.0             # the main deck
const FD := 7.2            # the forecastle deck
const BREAK := 31.0        # where the forecastle begins
const BUL := 1.1           # the bulwark's height
const HX0 := -41.0         # the deckhouse
const HX1 := -29.0
const HZ := 5.4
const TIER := 2.8
const BD := D + TIER * 3.0 # the bridge deck
const ROOF := BD + TIER
const WX0 := -37.0         # the wheelhouse (on the bridge deck)
const WX1 := -29.4
const WZ := 5.0
const GATE := [-9.3, -7.5] # the opening in the starboard bulwark at the head of the ladder
const STATIONS := [[-46.0, 6.0], [-44.0, 6.9], [-40.0, 7.5], [22.0, 7.5], [27.0, 7.2], [31.0, 6.6], [35.0, 5.6], [39.0, 4.2],
	[42.0, 3.0], [44.5, 1.7], [46.2, 0.7], [47.0, 0.08]]

var boat_at := Vector3(3.4, 0.55, 9.7)     # where the hero's boat lies (he stands in it)
var manifest_at := Vector3.ZERO
var marked := []           # the containers to destroy
var launches := []         # [node, phase, speed, light, beam, glow]
var water: MeshInstance3D
var radar: Node3D
var gray := Color(0.33, 0.35, 0.38)
const SPEED := 7.0         # she is under way: the sea and the land go by at this (metres a second)
var run := 0.0             # how far she has come
var isles := []            # [node, x at the start, scale]
var skiffs := []           # the fast boats: {n, body, a, w, side, cd, burst, sunk}
var sea_mat: ShaderMaterial
var foam_mat: ShaderMaterial


# ---------------- materials ----------------
func _tri(key: String, path: String, tint: Color, per_m: float, rough := 0.85, metal := 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path + "_diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(path + "_nor.jpg")
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * per_m
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	city.mats[key] = m


func _flat(key: String, col: Color, rough := 0.6, emit := 0.0, alpha := false) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(col.r, col.g, col.b)
		m.emission_energy_multiplier = emit
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.metallic_specular = 0.9
	city.mats[key] = m


func _mats() -> void:
	var hd := "res://assets/hd/tex/"
	var t3 := "res://assets/city/tex3/"
	var pt := "res://assets/ship/paint"
	_tri("sh_hull", pt, Color(0.2, 0.28, 0.42), 0.12, 0.6, 0.1)
	_tri("sh_boot", hd + "rusty_painted_metal", Color(0.8, 0.62, 0.6), 0.22, 0.8)
	_tri("sh_deck", hd + "green_metal_rust", Color(0.75, 0.82, 0.78), 0.3, 0.75, 0.1)
	_tri("sh_plate", t3 + "metal_plate", Color(0.9, 0.9, 0.9), 0.7, 0.6, 0.3)
	_tri("sh_grate", hd + "metal_grate_rusty", Color(0.8, 0.8, 0.8), 0.8, 0.7, 0.3)
	_tri("sh_white", pt, Color(1.0, 1.0, 0.98), 0.14, 0.55)
	_tri("sh_cream", pt, Color(0.92, 0.9, 0.84), 0.2, 0.65)
	_tri("sh_hatch", hd + "box_profile_metal_sheet", Color(0.62, 0.66, 0.6), 0.35, 0.7, 0.15)
	_tri("sh_coam", hd + "painted_metal_shutter", Color(0.5, 0.54, 0.56), 0.5, 0.7, 0.1)
	_tri("sh_yellow", pt, Color(0.95, 0.68, 0.12), 0.3, 0.6)
	_tri("sh_funnel", hd + "rusty_painted_metal", Color(0.95, 0.7, 0.65), 0.25, 0.7)
	_tri("sh_black", pt, Color(0.11, 0.11, 0.13), 0.3, 0.7)
	_tri("sh_orange", t3 + "pale_paint", Color(1.0, 0.42, 0.08), 0.5, 0.55)
	_tri("sh_wood", hd + "plywood", Color(0.8, 0.7, 0.6), 0.6, 0.7)
	_tri("sh_floor", hd + "green_metal_rust", Color(0.55, 0.6, 0.7), 0.5, 0.5)
	_tri("sh_grey", hd + "painted_metal_shutter", Color(0.62, 0.66, 0.7), 0.4, 0.6, 0.2)
	_tri("sh_rubber", t3 + "rough_linen", Color(0.07, 0.07, 0.08), 1.5, 0.85)
	_flat("sh_steel", Color(1, 1, 1), 0.5)
	_flat("sh_gloss", Color(1, 1, 1), 0.25)
	_flat("sh_lit", Color(1.0, 0.8, 0.5), 0.3, 1.3)
	_flat("sh_screen", Color(0.3, 0.9, 0.7), 0.3, 1.6)
	_flat("sh_red", Color(1.0, 0.15, 0.1), 0.3, 3.0)
	_flat("sh_green", Color(0.15, 1.0, 0.3), 0.3, 3.0)
	_flat("sh_dark", Color(0.03, 0.04, 0.05), 0.2)
	_flat("sh_glass", Color(0.35, 0.5, 0.6, 0.22), 0.05, 0.0, true)


# ---------------- drawing helpers ----------------
func ck(x: float) -> void:
	city.chunk = "s%d" % int(floor((x + 48.0) / 16.0))


## A four-cornered face a-b-c-d, turned to face `out`.
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, col := Color(1, 1, 1)) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.dot(out) < 0.0:
		n = -n
		var s := b
		b = d
		d = s
	var st: SurfaceTool = city._st(key)
	var uv := {a: Vector2(0, 0), b: Vector2(1, 0), c: Vector2(1, 1), d: Vector2(0, 1)}
	for p in [a, c, b, a, d, c]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uv.get(p, Vector2.ZERO))
		st.add_vertex(p)


## A box turned any way: centre, size, basis.
func tbox(key: String, c: Vector3, s: Vector3, b: Basis, col := Color(1, 1, 1)) -> void:
	var x: Vector3 = b.x * s.x * 0.5
	var y: Vector3 = b.y * s.y * 0.5
	var z: Vector3 = b.z * s.z * 0.5
	city.face(key, c + z, x, y, col)
	city.face(key, c - z, -x, y, col)
	city.face(key, c + x, -z, y, col)
	city.face(key, c - x, z, y, col)
	city.face(key, c + y, x, -z, col)
	city.face(key, c - y, x, z, col)


## A round bar from a to b.
func bar(key: String, a: Vector3, b: Vector3, r: float, seg := 6, col := Color(1, 1, 1), r2 := -1.0) -> void:
	if r2 < 0.0:
		r2 = r
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP)
	if u.length() < 0.01:
		u = Vector3.RIGHT
	u = u.normalized()
	var v := ax.cross(u)
	var st: SurfaceTool = city._st(key)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var q := [a + d0 * r, a + d1 * r, b + d1 * r2, b + d0 * r2]
		var ns := [d0, d1, d1, d0]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(ns[k])
			st.set_uv(Vector2(float(i) / seg, 0))
			st.add_vertex(q[k])
		if r > 0.08:
			for e in [[a, -ax, r, false], [b, ax, r2, true]]:
				var c: Vector3 = e[0]
				var tri := [c, c + d0 * e[2], c + d1 * e[2]] if e[3] else [c, c + d1 * e[2], c + d0 * e[2]]
				for p in tri:
					st.set_color(col)
					st.set_normal(e[1])
					st.set_uv(Vector2.ZERO)
					st.add_vertex(p)


func solid(c: Vector3, s: Vector3, yaw := 0.0) -> StaticBody3D:
	return city.collider(c, s, yaw, "metal")


## A box drawn and solid.
func block(key: String, c: Vector3, s: Vector3, yaw := 0.0, col := Color(1, 1, 1)) -> void:
	city.box(key, c, s, yaw, col)
	solid(c, s, yaw)


## A rail along the edge of a deck from a to b (at deck height): posts, three bars, a thin wall to stop feet.
func rail(a: Vector3, b: Vector3, h := 1.05, col := Color(0.82, 0.83, 0.82)) -> void:
	var len_ := a.distance_to(b)
	var n := maxi(1, int(round(len_ / 1.5)))
	for i in n + 1:
		var p: Vector3 = a.lerp(b, float(i) / n)
		bar("sh_steel", p, p + Vector3(0, h, 0), 0.022, 5, col)
	for k in [1.0, 0.66, 0.33]:
		bar("sh_steel", a + Vector3(0, h * k, 0), b + Vector3(0, h * k, 0), 0.02 if k < 1.0 else 0.028, 5, col)
	var d := b - a
	var mid := (a + b) * 0.5
	solid(Vector3(mid.x, (a.y + b.y) * 0.5 + h * 0.5, mid.z), Vector3(Vector2(d.x, d.z).length(), h + abs(d.y), 0.06), atan2(-d.z, d.x))


func lamp(p: Vector3, col: Color, energy: float, reach: float, halo := 1.6) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	add_child(l)
	l.position = p
	var parts: Array = [l]
	if halo > 0.0:
		parts.append(city.glow(p, Color(col.r, col.g, col.b, 0.75), halo))
		main.lamp_can_break(p, parts, 0.45, Vector3(0.5, 0.2, 0.5))
	return l


## A flight of steps from `base` (its foot) rising `rise` over `run` along dir: treads, a ramp to walk on, rails.
func flight(base: Vector3, dir: Vector3, width: float, rise: float, run: float, rails := [true, true]) -> void:
	var n := int(round(rise / 0.22))
	var hs := rise / n
	var ds := run / n
	var side := dir.cross(Vector3.UP).normalized()
	for i in n:
		var p: Vector3 = base + dir * ((i + 0.5) * ds) + Vector3(0, (i + 1) * hs - 0.02, 0)
		tbox("sh_plate", p, Vector3(width, 0.04, ds + 0.04), Basis(-side, Vector3.UP, dir), Color(0.85, 0.85, 0.85))
	var slope := dir * run + Vector3.UP * rise
	var len_ := slope.length()
	var sl := slope / len_
	var nrm := sl.cross(side).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var b := Basis(nrm.cross(sl).normalized(), nrm, sl)
	var mid: Vector3 = base + dir * (run * 0.5) + Vector3(0, rise * 0.5, 0)
	var rb := StaticBody3D.new()
	rb.set_meta("surf", "metal")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 0.2, len_ + 0.3)
	cs.shape = sh
	rb.add_child(cs)
	main.add_child(rb)
	rb.global_transform = Transform3D(b, mid - nrm * 0.1)
	for i in 2:
		var sg := -1.0 if i == 0 else 1.0
		var off: Vector3 = side * (sg * (width * 0.5 + 0.03))
		tbox("sh_grey", mid + off - nrm * 0.06, Vector3(0.05, 0.26, len_ + 0.1), b, Color(0.6, 0.6, 0.6))
		if rails[i]:
			rail(base + off, base + off + dir * run + Vector3(0, rise, 0), 1.0)


# ---------------- the hull ----------------
func hw(x: float) -> float:
	for i in STATIONS.size() - 1:
		if x <= STATIONS[i + 1][0]:
			return lerp(STATIONS[i][1], STATIONS[i + 1][1], clamp((x - STATIONS[i][0]) / (STATIONS[i + 1][0] - STATIONS[i][0]), 0.0, 1.0))
	return 0.08


func deck_y(x: float) -> float:
	return FD if x >= BREAK else D


## The starboard side at x, keel to rail: [point, ..] (the port side is its mirror).
func _ring(x: float, top: float) -> Array:
	var w := hw(x)
	var b: float = clamp((x - 22.0) / 25.0, 0.0, 1.0)
	var s: float = clamp((-40.0 - x) / 6.0, 0.0, 1.0)
	var b2 := b * b
	return [Vector3(x - 3.6 * b2 + 2.6 * s, -1.6, w * lerp(0.9, 0.3, b) * lerp(1.0, 0.7, s)),
		Vector3(x - 2.4 * b2 + 1.7 * s, 0.9, w * lerp(0.975, 0.55, b) * lerp(1.0, 0.86, s)),
		Vector3(x - 1.1 * b2 + 0.6 * s, 3.2, w * lerp(1.0, 0.82, b) * lerp(1.0, 0.96, s)),
		Vector3(x, top, w)]


func _xs() -> Array:
	var xs := []
	for i in STATIONS.size() - 1:
		var a: float = STATIONS[i][0]
		var b: float = STATIONS[i + 1][0]
		var n := int(ceil((b - a) / 8.0))
		for k in n:
			xs.append(a + (b - a) * k / n)
	xs.append(STATIONS[STATIONS.size() - 1][0])
	for g in GATE:
		xs.append(g)
	xs.sort()
	return xs


func _hull() -> void:
	var xs := _xs()
	var keys := ["sh_boot", "sh_hull", "sh_hull"]
	for i in xs.size() - 1:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		var xm := (x0 + x1) * 0.5
		ck(xm)
		var dy := deck_y(xm)
		for sg in [1.0, -1.0]:
			var gate: bool = sg > 0.0 and xm > GATE[0] and xm < GATE[1]
			var top: float = dy + (0.0 if gate else BUL)
			var r0 := _ring(x0, top)
			var r1 := _ring(x1, top)
			var m := Vector3(1, 1, sg)
			var out := Vector3(0, 0, sg) + Vector3(0.3 if x0 > 22.0 else 0.0, 0, 0)
			for k in 3:
				quad(keys[k], r0[k] * m, r1[k] * m, r1[k + 1] * m, r0[k + 1] * m, out)
			# a pale line along the waterline's top, and the bulwark from inboard: its inner face, its cap
			var a := Vector3(x0, dy, sg * (hw(x0) - 0.12))
			var b := Vector3(x1, dy, sg * (hw(x1) - 0.12))
			if not gate:
				quad("sh_hull", a, b, b + Vector3(0, BUL, 0), a + Vector3(0, BUL, 0), -out, Color(0.8, 0.8, 0.8))
				quad("sh_hull", a + Vector3(0, BUL, 0), b + Vector3(0, BUL, 0), r1[3] * m, r0[3] * m, Vector3.UP, Color(0.9, 0.9, 0.9))
				var d := b - a
				solid((a + b) * 0.5 + Vector3(0, BUL * 0.5, sg * 0.06), Vector3(d.length() + 0.05, BUL, 0.16), atan2(-d.z, d.x))
				# stays holding the bulwark up, every couple of metres
				if x1 - x0 > 3.0:
					for q in int((x1 - x0) / 2.0):
						var px: float = x0 + 1.0 + q * 2.0
						tbox("sh_hull", Vector3(px, dy + 0.5, sg * (hw(px) - 0.26)), Vector3(0.05, 1.0, 0.26), Basis.IDENTITY, Color(0.75, 0.75, 0.75))
			# the deck out to the side
			quad("sh_deck", Vector3(x0, dy, 0), Vector3(x1, dy, 0), b, a, Vector3.UP)
	# the stern's flat end, and under the stem
	ck(-46.0)
	var rs := _ring(-46.0, D + BUL)
	for k in 3:
		var p0: Vector3 = rs[k]
		var p1: Vector3 = rs[k + 1]
		quad(keys[k], p0, p0 * Vector3(1, 1, -1), p1 * Vector3(1, 1, -1), p1, Vector3(-1, 0, 0))
	quad("sh_hull", Vector3(-45.88, D, -5.9), Vector3(-45.88, D, 5.9), Vector3(-45.88, D + BUL, 5.9), Vector3(-45.88, D + BUL, -5.9), Vector3(1, 0, 0), Color(0.8, 0.8, 0.8))
	solid(Vector3(-45.95, D + BUL * 0.5, 0), Vector3(0.16, BUL, 12.0))
	# what holds things up: the hull under the main deck, the forecastle in pieces
	solid(Vector3((-46.0 + BREAK) * 0.5, (D - 1.6) * 0.5, 0), Vector3(BREAK + 46.0, D + 1.6, 15.0))
	for i in STATIONS.size() - 1:
		var x0: float = STATIONS[i][0]
		var x1: float = STATIONS[i + 1][0]
		if x0 >= BREAK:
			solid(Vector3((x0 + x1) * 0.5, (FD - 1.6) * 0.5, 0), Vector3(x1 - x0, FD + 1.6, hw(x0) + hw(x1)))
	# the break of the forecastle: its wall, a door in it, the two flights up
	ck(BREAK - 1.0)
	var bw := hw(BREAK) - 0.12
	quad("sh_white", Vector3(BREAK, D, -bw), Vector3(BREAK, D, bw), Vector3(BREAK, FD, bw), Vector3(BREAK, FD, -bw), Vector3(-1, 0, 0))
	_door(Vector3(BREAK - 0.03, D, 0), Vector3(-1, 0, 0))
	for sg in [-1.0, 1.0]:
		flight(Vector3(BREAK - 3.4, D, sg * 4.6), Vector3(1, 0, 0), 1.1, FD - D, 3.4)
	rail(Vector3(BREAK + 0.05, FD, -4.0), Vector3(BREAK + 0.05, FD, 4.0))
	for sg in [-1.0, 1.0]:
		rail(Vector3(BREAK + 0.05, FD, sg * 5.2), Vector3(BREAK + 0.05, FD, sg * (bw - 0.1)))
	# her name on the bows and across the stern
	_name_plate(Vector3(38.6, 6.3, hw(38.6) + 0.03), Vector3(1, 0, 0.36).normalized(), 5.2)
	_name_plate(Vector3(38.6, 6.3, -hw(38.6) - 0.03), Vector3(-1, 0, 0.36).normalized(), 5.2)
	_name_plate(Vector3(-46.04, 4.1, 0), Vector3(0, 0, -1), 4.6)
	# hawse pipes with the anchors hove up in them
	for sg in [-1.0, 1.0]:
		var hp := Vector3(41.6, 5.6, sg * (hw(41.6) + 0.02))
		ck(41.0)
		tbox("sh_dark", hp, Vector3(0.9, 0.9, 0.08), Basis(Vector3.UP, -sg * 0.42), Color(1, 1, 1))
		tbox("sh_black", hp + Vector3(0.05, -0.9, sg * 0.14), Vector3(0.22, 1.9, 0.2), Basis(Vector3.UP, -sg * 0.42))
		tbox("sh_black", hp + Vector3(0.05, -1.8, sg * 0.16), Vector3(1.5, 0.26, 0.24), Basis(Vector3.UP, -sg * 0.42))


func _name_plate(c: Vector3, along: Vector3, w: float) -> void:
	var img := Image.create(160, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	city._glyphs(img, "NORTHERN GANNET", 4, 4, 1, Color(0.92, 0.92, 0.9))
	if not city.mats.has("sh_name"):
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.roughness = 0.7
		city.mats["sh_name"] = m
	var st: SurfaceTool = city._st("sh_name")
	var u := along * (w * 0.5)
	var v := Vector3.UP * (w * 0.05)
	var n := u.cross(v).normalized()
	var p := [c - u - v, c + u - v, c + u + v, c - u + v]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(Color(1, 1, 1))
		st.set_normal(n)
		st.set_uv(uv[i])
		st.add_vertex(p[i])


## A steel door (shut) on a wall: the foot of its middle, the way it faces.
func _door(p: Vector3, n: Vector3, lit := false) -> void:
	var side := Vector3.UP.cross(n).normalized()
	var b := Basis(side, Vector3.UP, n)
	tbox("sh_grey", p + Vector3(0, 1.05, 0) + n * 0.03, Vector3(0.86, 2.0, 0.06), b, Color(0.8, 0.8, 0.8))
	tbox("sh_white", p + Vector3(0, 1.05, 0) + n * 0.01, Vector3(1.0, 2.14, 0.05), b, Color(0.7, 0.7, 0.7))
	tbox("sh_dark" if not lit else "sh_lit", p + Vector3(0, 1.55, 0) + n * 0.065, Vector3(0.26, 0.26, 0.02), b)
	for hy in [0.5, 1.6]:
		tbox("sh_steel", p + Vector3(0, hy, 0) + n * 0.08 + side * 0.36, Vector3(0.05, 0.16, 0.05), b, Color(0.3, 0.3, 0.3))
	bar("sh_steel", p + Vector3(0, 1.0, 0) + n * 0.1 - side * 0.3, p + Vector3(0, 1.15, 0) + n * 0.1 - side * 0.3, 0.02, 5, Color(0.5, 0.5, 0.5))


## A window or porthole on a wall, lit from inside or dark.
func _window(p: Vector3, n: Vector3, w: float, h: float, lit: bool) -> void:
	var side := Vector3.UP.cross(n).normalized()
	var b := Basis(side, Vector3.UP, n)
	tbox("sh_grey", p + n * 0.01, Vector3(w + 0.12, h + 0.12, 0.05), b, Color(0.55, 0.55, 0.55))
	tbox("sh_lit" if lit else "sh_dark", p + n * 0.02, Vector3(w, h, 0.05), b, Color(1, 1, 1) if lit else Color(0.5, 0.6, 0.7))


# ---------------- the deckhouse, the bridge ----------------
func _house() -> void:
	ck(-36.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var hc := Vector3((HX0 + HX1) * 0.5, 0, 0)
	var hl := HX1 - HX0
	city.box("sh_white", hc + Vector3(0, D + TIER * 1.5, 0), Vector3(hl, TIER * 3.0, HZ * 2.0))
	solid(hc + Vector3(0, D + TIER * 1.5, 0), Vector3(hl, TIER * 3.0, HZ * 2.0))
	for lv in 3:
		var y: float = D + TIER * lv
		# a ledge round each deck's edge, windows, doors
		city.box("sh_white", hc + Vector3(0, y + TIER - 0.06, 0), Vector3(hl + 0.3, 0.12, HZ * 2.0 + 0.3), 0.0, Color(0.8, 0.8, 0.8))
		for i in 5:
			var z := -4.0 + i * 2.0
			if lv == 0 and i == 1:
				_door(Vector3(HX1, y, z), Vector3(1, 0, 0), true)
			else:
				_window(Vector3(HX1, y + 1.6, z), Vector3(1, 0, 0), 0.8, 0.7, rng.randf() < 0.55)
		for sg in [-1.0, 1.0]:
			for i in 5:
				var x := HX0 + 1.6 + i * 2.2
				if lv == 0 and i == 2:
					_door(Vector3(x, y, sg * HZ), Vector3(0, 0, sg), sg > 0.0)
				else:
					_window(Vector3(x, y + 1.6, sg * HZ), Vector3(0, 0, sg), 0.6, 0.6, rng.randf() < 0.45)
		_door(Vector3(HX0, y, 2.7 if lv == 1 else -2.7), Vector3(-1, 0, 0), lv == 1)
	# lamps over the doors
	for p in [Vector3(HX1 + 0.25, D + 2.35, -2.0), Vector3(-35.0, D + 2.35, HZ + 0.25), Vector3(-35.0, D + 2.35, -HZ - 0.25)]:
		city.box("sh_lit", p, Vector3(0.16, 0.12, 0.16))
		lamp(p - Vector3(0, 0.15, 0), Color(1.0, 0.8, 0.55), 2.2, 9.0, 0.9)
	# the bridge deck: a slab over the house, wings out to the ship's sides
	var by := BD
	city.box("sh_white", Vector3(hc.x, by - 0.1, 0), Vector3(hl + 0.5, 0.2, HZ * 2.0 + 0.5), 0.0, Color(0.85, 0.85, 0.85))
	city.face("sh_deck", Vector3(hc.x, by + 0.005, 0), Vector3(hl * 0.5 + 0.25, 0, 0), Vector3(0, 0, -HZ - 0.25))
	for sg in [-1.0, 1.0]:
		var wc := Vector3(-33.5, by - 0.1, sg * (HZ + 1.15))
		city.box("sh_white", wc, Vector3(5.0, 0.2, 2.3), 0.0, Color(0.85, 0.85, 0.85))
		city.face("sh_grate", wc + Vector3(0, 0.105, 0), Vector3(2.5, 0, 0), Vector3(0, 0, -1.15))
		solid(wc, Vector3(5.0, 0.2, 2.3))
		# the wing's bulwark: solid white plate, a lamp at its end
		for e in [[Vector3(-33.5, 0, sg * (HZ + 2.27)), Vector3(5.0, 1.1, 0.06)], [Vector3(-36.0, 0, sg * (HZ + 1.15)), Vector3(0.06, 1.1, 2.3)],
				[Vector3(-31.0, 0, sg * (HZ + 1.15)), Vector3(0.06, 1.1, 2.3)]]:
			block("sh_white", e[0] + Vector3(0, by + 0.55, 0), e[1])
		bar("sh_steel", Vector3(-31.2, by - 0.2, sg * (HZ + 2.0)), Vector3(-31.2, D + TIER * 2.0 - 1.4, sg * HZ), 0.05, 6, gray)
		bar("sh_steel", Vector3(-35.8, by - 0.2, sg * (HZ + 2.0)), Vector3(-35.8, D + TIER * 2.0 - 1.4, sg * HZ), 0.05, 6, gray)
		city.box("sh_green" if sg > 0.0 else "sh_red", Vector3(-31.0, by + 0.7, sg * (HZ + 2.34)), Vector3(0.3, 0.22, 0.08))
		city.glow(Vector3(-31.0, by + 0.7, sg * (HZ + 2.5)), Color(0.2, 1.0, 0.35, 0.7) if sg > 0.0 else Color(1.0, 0.2, 0.15, 0.7), 1.1)
		# rails along the rest of the bridge deck's sides
		rail(Vector3(HX0, by, sg * (HZ + 0.15)), Vector3(-36.05, by, sg * (HZ + 0.15)))
		rail(Vector3(-30.95, by, sg * (HZ + 0.15)), Vector3(HX1 + 0.2, by, sg * (HZ + 0.15)))
	rail(Vector3(HX1 + 0.2, by, -HZ - 0.15), Vector3(HX1 + 0.2, by, HZ + 0.15))
	rail(Vector3(HX0, by, -HZ - 0.15), Vector3(HX0, by, 2.1))
	rail(Vector3(HX0, by, 3.3), Vector3(HX0, by, HZ + 0.15))
	_wheelhouse()
	_funnel()
	_stair_tower()
	_lifeboats()


func _wheelhouse() -> void:
	ck(-33.0)
	city.chunk = "bridge"
	var y0 := BD
	var wl := WX1 - WX0
	var wc := Vector3((WX0 + WX1) * 0.5, 0, 0)
	var sill := 1.0
	var head := 2.05
	# walls with a band of windows forward and down both sides; a door aft, a door to each wing
	# [from, to, the way it faces, door openings along it [centre, width]]
	var walls := [[Vector3(WX1, 0, -WZ), Vector3(WX1, 0, WZ), Vector3(1, 0, 0), [], true],
		[Vector3(WX0, 0, -WZ), Vector3(WX0, 0, WZ), Vector3(-1, 0, 0), [[8.5, 1.0]], false],
		[Vector3(WX0, 0, WZ), Vector3(WX1, 0, WZ), Vector3(0, 0, 1), [[3.5, 1.0]], true],
		[Vector3(WX0, 0, -WZ), Vector3(WX1, 0, -WZ), Vector3(0, 0, -1), [[3.5, 1.0]], true]]
	for w in walls:
		var a: Vector3 = w[0]
		var b: Vector3 = w[1]
		var n: Vector3 = w[2]
		var d := (b - a).normalized()
		var len_ := a.distance_to(b)
		var yaw := atan2(-d.z, d.x)
		# runs of wall between the door openings
		var cuts := [0.0]
		for dr in w[3]:
			cuts.append(dr[0] - dr[1] * 0.5)
			cuts.append(dr[0] + dr[1] * 0.5)
		cuts.append(len_)
		for i in range(0, cuts.size(), 2):
			var s0: float = cuts[i]
			var s1: float = cuts[i + 1]
			if s1 - s0 < 0.05:
				continue
			var m: Vector3 = a + d * ((s0 + s1) * 0.5)
			if w[4]:
				block("sh_white", m + Vector3(0, y0 + sill * 0.5, 0), Vector3(s1 - s0, sill, 0.12), yaw)
				block("sh_white", m + Vector3(0, y0 + (head + TIER) * 0.5, 0), Vector3(s1 - s0, TIER - head, 0.12), yaw)
				city.box("sh_glass", m + Vector3(0, y0 + (sill + head) * 0.5, 0), Vector3(s1 - s0, head - sill, 0.02), yaw)
				var nm := int(round((s1 - s0) / 1.25))
				for k in nm + 1:
					var q: Vector3 = a + d * (s0 + (s1 - s0) * k / maxi(nm, 1))
					city.box("sh_white", q + Vector3(0, y0 + (sill + head) * 0.5, 0), Vector3(0.09, head - sill, 0.13), yaw, Color(0.85, 0.85, 0.85))
			else:
				block("sh_white", m + Vector3(0, y0 + TIER * 0.5, 0), Vector3(s1 - s0, TIER, 0.12), yaw)
		for dr in w[3]:
			var m: Vector3 = a + d * dr[0]
			block("sh_white", m + Vector3(0, y0 + (2.1 + TIER) * 0.5, 0), Vector3(dr[1], TIER - 2.1, 0.12), yaw)
			# the door stands open, back against the wall outside
			tbox("sh_grey", m + d * (dr[1] * 0.5 + 0.42) + n * 0.12 + Vector3(0, y0 + 1.05, 0), Vector3(0.84, 2.0, 0.05), Basis(d, Vector3.UP, d.cross(Vector3.UP)), Color(0.8, 0.8, 0.8))
	# floor, ceiling, roof
	city.face("sh_floor", wc + Vector3(0, y0 + 0.012, 0), Vector3(wl * 0.5, 0, 0), Vector3(0, 0, -WZ))
	city.face("sh_white", wc + Vector3(0, ROOF - 0.11, 0), Vector3(wl * 0.5, 0, 0), Vector3(0, 0, WZ), Color(0.55, 0.55, 0.55))
	city.chunk = "roof"
	city.box("sh_white", wc + Vector3(0, ROOF, 0), Vector3(wl + 0.9, 0.2, WZ * 2.0 + 0.9), 0.0, Color(0.85, 0.85, 0.85))
	solid(wc + Vector3(0, ROOF, 0), Vector3(wl + 0.9, 0.2, WZ * 2.0 + 0.9))
	solid(Vector3((HX0 + HX1) * 0.5, BD - 0.1, 0), Vector3(HX1 - HX0 + 0.5, 0.2, HZ * 2.0 + 0.5))
	for e in [[Vector3(WX0 - 0.4, ROOF + 0.1, -WZ - 0.4), Vector3(WX1 + 0.4, ROOF + 0.1, -WZ - 0.4)], [Vector3(WX0 - 0.4, ROOF + 0.1, WZ + 0.4), Vector3(WX1 + 0.4, ROOF + 0.1, WZ + 0.4)],
			[Vector3(WX1 + 0.4, ROOF + 0.1, -WZ - 0.4), Vector3(WX1 + 0.4, ROOF + 0.1, WZ + 0.4)], [Vector3(WX0 - 0.4, ROOF + 0.1, -WZ - 0.4), Vector3(WX0 - 0.4, ROOF + 0.1, WZ + 0.4)]]:
		rail(e[0], e[1], 1.0)
	# the mast on the roof: yards, lamps, the radar turning
	var mp := Vector3(-33.6, ROOF + 0.1, 0)
	bar("sh_white", mp, mp + Vector3(0, 6.0, 0), 0.16, 8, Color(1, 1, 1), 0.09)
	bar("sh_white", mp + Vector3(0, 3.4, -2.2), mp + Vector3(0, 3.4, 2.2), 0.05, 6)
	bar("sh_white", mp + Vector3(0, 4.6, -1.3), mp + Vector3(0, 4.6, 1.3), 0.04, 6)
	bar("sh_white", mp + Vector3(1.4, 0, 0), mp + Vector3(0, 3.2, 0), 0.05, 6)
	bar("sh_white", mp + Vector3(-1.4, 0, 0), mp + Vector3(0, 3.2, 0), 0.05, 6)
	city.box("sh_lit", mp + Vector3(0.2, 5.9, 0), Vector3(0.14, 0.18, 0.14))
	city.glow(mp + Vector3(0.3, 5.9, 0), Color(1.0, 0.95, 0.85, 0.9), 1.6)
	city.box("sh_white", mp + Vector3(1.6, 0.5, 2.6), Vector3(0.7, 1.0, 0.7))
	bar("sh_white", mp + Vector3(1.6, 1.0, 2.6), mp + Vector3(1.6, 1.5, 2.6), 0.5, 10, Color(1, 1, 1), 0.3)
	radar = Node3D.new()
	add_child(radar)
	radar.position = mp + Vector3(0, 2.3, 0.0)
	var rm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 0.18, 0.12)
	rm.mesh = bm
	rm.material_override = city.mats["sh_white"]
	rm.position = Vector3(0.6, 0, 0)
	radar.add_child(rm)
	bar("sh_white", mp + Vector3(0, 2.2, 0), mp + Vector3(0.6, 2.2, 0), 0.06, 6)
	# inside: the console under the forward windows, the wheel, a chart table aft with the manifest on it
	city.chunk = "bridge"
	var cx := WX1 - 0.5
	block("sh_grey", Vector3(cx, y0 + 0.48, 0), Vector3(0.75, 0.96, 6.4), 0.0, Color(0.55, 0.55, 0.55))
	for i in 7:
		var z := -2.7 + i * 0.9
		tbox("sh_screen" if i % 3 != 1 else "sh_lit", Vector3(cx - 0.12, y0 + 1.0, z), Vector3(0.6, 0.02, 0.5), Basis(Vector3(0, 0, 1), 0.35), Color(1, 1, 1) if i % 3 != 1 else Color(0.6, 0.3, 0.1))
	block("sh_grey", Vector3(cx - 1.2, y0 + 0.55, 0), Vector3(0.4, 1.1, 0.5), 0.0, Color(0.5, 0.5, 0.5))
	for k in 8:
		var a := TAU * k / 8.0
		bar("sh_wood", Vector3(cx - 1.42, y0 + 1.0, 0), Vector3(cx - 1.42, y0 + 1.0 + cos(a) * 0.36, sin(a) * 0.36), 0.018, 5)
	for sg in [-1.0, 1.0]:
		block("sh_black", Vector3(cx - 1.5, y0 + 0.3, sg * 1.5), Vector3(0.5, 0.6, 0.5))
		city.box("sh_black", Vector3(cx - 1.72, y0 + 0.85, sg * 1.5), Vector3(0.08, 0.6, 0.5))
	var tb := Vector3(WX0 + 0.75, y0, -2.2)
	block("sh_wood", tb + Vector3(0, 0.45, 0), Vector3(1.1, 0.9, 2.4))
	city.box("sh_white", tb + Vector3(0, 0.905, 0.2), Vector3(0.8, 0.008, 1.2), 0.0, Color(0.9, 0.88, 0.8))
	manifest_at = tb + Vector3(0.05, 0.93, -0.7)
	block("sh_grey", Vector3(WX0 + 0.45, y0 + 0.95, 1.2), Vector3(0.6, 1.9, 1.4), 0.0, Color(0.5, 0.55, 0.5))
	var l := lamp(Vector3(wc.x, ROOF - 0.35, 0), Color(1.0, 0.8, 0.6), 1.2, 9.0, 0.0)
	l.omni_attenuation = 0.8
	city.chunk = ""


func _funnel() -> void:
	city.chunk = "roof"
	var fp := Vector3(-39.2, BD, 0)
	block("sh_white", fp + Vector3(0, 0.7, 0), Vector3(3.2, 1.4, 3.4))
	var st := 1.4
	bar("sh_funnel", fp + Vector3(0, st, 0), fp + Vector3(-0.5, st + 4.6, 0), 1.5, 14, Color(1, 1, 1), 1.3)
	bar("sh_white", fp + Vector3(-0.3, st + 2.6, 0), fp + Vector3(-0.38, st + 3.4, 0), 1.43, 14, Color(1, 1, 1), 1.4)
	bar("sh_black", fp + Vector3(-0.5, st + 4.6, 0), fp + Vector3(-0.6, st + 5.6, 0), 1.32, 14, Color(1, 1, 1), 1.26)
	for sg in [-0.5, 0.5]:
		bar("sh_black", fp + Vector3(-0.6, st + 5.4, sg), fp + Vector3(-0.7, st + 6.3, sg), 0.28, 8)
	solid(fp + Vector3(-0.3, st + 2.8, 0), Vector3(2.6, 5.6, 2.6))
	city.chunk = ""


## The outside stairs up the after end of the house: three flights in two lanes, landings between.
func _stair_tower() -> void:
	city.chunk = "stair"
	var xa := HX0 - 0.65       # lane next the house
	var xb := HX0 - 1.85       # the outer lane
	for k in 3:
		var y: float = D + TIER * k
		var up := k % 2 == 0     # toward +z
		var x := xa if k % 2 == 0 else xb
		flight(Vector3(x, y, -2.1 if up else 2.1), Vector3(0, 0, 1.0 if up else -1.0), 1.1, TIER, 4.2, [false, true] if k % 2 == 0 else [true, true])
		# the landing at its head (both lanes wide)
		var lz := 2.7 if up else -2.7
		var lc := Vector3(HX0 - 1.25, y + TIER - 0.05, lz)
		block("sh_grate", lc, Vector3(2.5, 0.1, 1.2))
		var end_z := lz + (0.6 if up else -0.6)
		rail(Vector3(HX0 - 2.5, y + TIER, end_z), Vector3(HX0, y + TIER, end_z))
		rail(Vector3(HX0 - 2.5, y + TIER, lz - 0.6), Vector3(HX0 - 2.5, y + TIER, lz + 0.6))
		# posts holding the landing
		for px in [HX0 - 2.4, HX0 - 0.1]:
			bar("sh_steel", Vector3(px, D, end_z), Vector3(px, y + TIER - 0.1, end_z), 0.05, 6, gray)
	lamp(Vector3(HX0 - 0.3, D + TIER + 2.3, 0), Color(1.0, 0.82, 0.6), 2.0, 10.0, 0.9)
	lamp(Vector3(HX0 - 0.3, BD + 0.2 + 2.0, 3.4), Color(1.0, 0.82, 0.6), 1.6, 8.0, 0.9)
	city.chunk = ""


func _lifeboats() -> void:
	var y: float = D + TIER * 2.0 - 0.5
	for sg in [-1.0, 1.0]:
		var c := Vector3(-37.0, y, sg * (HZ + 1.25))
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 14
		sm.rings = 7
		mi.mesh = sm
		mi.material_override = city.mats["sh_orange"]
		add_child(mi)
		mi.position = c
		mi.scale = Vector3(6.4, 2.0, 2.1)
		city.chunk = "stair"
		city.box("sh_orange", c + Vector3(0.3, 0.85, 0), Vector3(2.4, 0.7, 1.3), 0.0, Color(0.95, 0.95, 0.95))
		for dx in [-2.2, 2.2]:
			var foot := Vector3(c.x + dx, y - 0.9, sg * HZ)
			bar("sh_white", foot, foot + Vector3(0, 2.6, 0), 0.07, 6)
			bar("sh_white", foot + Vector3(0, 2.6, 0), Vector3(c.x + dx, y + 1.7, c.z), 0.07, 6)
			bar("sh_steel", Vector3(c.x + dx, y + 1.7, c.z), Vector3(c.x + dx, y + 0.9, c.z), 0.015, 4, Color(0.2, 0.2, 0.2))
			bar("sh_white", foot + Vector3(0, 0.1, 0), foot + Vector3(0, 0.1, sg * 1.3), 0.06, 6)
		city.chunk = ""


# ---------------- the cargo deck ----------------
func _cargo() -> void:
	var cols := ["red", "blue", "green"]
	var k := 0
	var hatches := [[-26.0, -12.0], [-8.0, 6.0], [10.0, 24.0]]
	for hi in hatches.size():
		var x0: float = hatches[hi][0]
		var x1: float = hatches[hi][1]
		var xm := (x0 + x1) * 0.5
		ck(xm)
		# the coaming, its stiffeners, the covers in panels (their ends a little proud)
		block("sh_coam", Vector3(xm, D + 0.6, 0), Vector3(x1 - x0, 1.2, 8.4))
		var np := 4
		for i in np:
			var px: float = x0 + (x1 - x0) * (i + 0.5) / np
			city.box("sh_hatch", Vector3(px, D + 1.3, 0), Vector3((x1 - x0) / np - 0.06, 0.22, 8.7))
		solid(Vector3(xm, D + 1.3, 0), Vector3(x1 - x0, 0.22, 8.7))
		for i in 8:
			var px: float = x0 + (x1 - x0) * (i + 0.5) / 8.0
			for sg in [-1.0, 1.0]:
				tbox("sh_coam", Vector3(px, D + 0.55, sg * 4.28), Vector3(0.06, 1.1, 0.16), Basis.IDENTITY, Color(0.8, 0.8, 0.8))
		# containers lashed on the covers, two long by three across, some two high
		for cx in [xm - 3.3, xm + 3.3]:
			for cz in [-2.75, 0.0, 2.75]:
				k += 1
				if k % 7 == 3:
					continue
				var top: float = D + 1.41
				main._prop("res://assets/env/container_%s.glb" % cols[(k * 2 + hi) % 3], Vector3(cx, top, cz), PI * 0.5, Vector3(2.44, 2.59, 6.06), "metal")
				if k % 3 != 1:
					main._prop("res://assets/env/container_%s.glb" % cols[(k + hi) % 3], Vector3(cx, top + 2.59, cz), PI * 0.5, Vector3(2.44, 2.59, 6.06), "metal")
	# the two cranes between the hatches
	for cx in [-10.0, 8.0]:
		_crane(Vector3(cx, D, 0))
	# things standing along the side decks and aft: drums, crates, vents, bollards
	for p in [[-20.0, 6.3, "drum_red"], [-19.2, 6.5, "drum_blue"], [-2.0, -6.4, "crate"], [-1.0, -6.3, "crate"], [14.0, 6.4, "crate"], [15.3, -6.4, "drum_blue"],
			[-27.4, -6.2, "crate"], [-27.6, 6.3, "drum_red"], [22.6, 6.3, "crate"], [29.6, 1.2, "crate"], [29.8, -1.6, "drum_blue"], [-44.0, 3.2, "crate"],
			[-44.2, -1.0, "drum_red"]]:
		var id: String = p[2]
		if id == "crate":
			main._prop("res://assets/env/crate.glb", Vector3(p[0], D, p[1]), p[0] * 0.7, Vector3(1.0, 1.0, 1.0), "wood")
		else:
			main._prop("res://assets/env/%s.glb" % id, Vector3(p[0], D, p[1]), 0.0, Vector3(0.3, 0.9, 0), "metal", true)
	for vx in [-27.5, 7.9, 25.6]:
		for sg in [-1.0, 1.0]:
			ck(vx)
			var vp := Vector3(vx, D, sg * 5.6)
			bar("sh_white", vp, vp + Vector3(0, 1.1, 0), 0.15, 10)
			bar("sh_white", vp + Vector3(0, 1.1, 0), vp + Vector3(0.3, 1.36, 0), 0.15, 10, Color(1, 1, 1), 0.24)
			solid(vp + Vector3(0, 0.65, 0), Vector3(0.32, 1.3, 0.32))
	for bp in [Vector3(-44.6, D, 4.6), Vector3(-44.6, D, -4.6), Vector3(20.0, D, 6.9), Vector3(20.0, D, -6.9), Vector3(-24.0, D, 6.9), Vector3(-24.0, D, -6.9),
			Vector3(41.0, FD, 2.0), Vector3(41.0, FD, -2.0), Vector3(34.0, FD, 4.9), Vector3(34.0, FD, -4.9)]:
		ck(bp.x)
		for dx in [-0.3, 0.3]:
			bar("sh_black", bp + Vector3(dx, 0, 0), bp + Vector3(dx, 0.5, 0), 0.13, 8)
			bar("sh_black", bp + Vector3(dx, 0.5, 0), bp + Vector3(dx, 0.56, 0), 0.17, 8)
		city.box("sh_black", bp + Vector3(0, 0.03, 0), Vector3(1.1, 0.06, 0.45))
		solid(bp + Vector3(0, 0.28, 0), Vector3(0.9, 0.56, 0.3))
	# lamps on the coamings' sides, lighting the side decks
	for i in 6:
		var lx: float = [-19.0, -19.0, -1.0, -1.0, 17.0, 17.0][i]
		var sg := 1.0 if i % 2 == 0 else -1.0
		ck(lx)
		city.box("sh_lit", Vector3(lx, D + 1.0, sg * 4.3), Vector3(0.3, 0.12, 0.1))
		lamp(Vector3(lx, D + 1.1, sg * 4.9), Color(1.0, 0.84, 0.6), 1.5, 9.0, 0.7)
	# flood lamps on posts down the deck (the light the guards work by)
	for lp in [Vector3(-28.6, D, 4.2), Vector3(23.2, D, -6.6)]:
		ck(lp.x)
		bar("sh_white", lp, lp + Vector3(0, 6.0, 0), 0.09, 6)
		city.box("sh_lit", lp + Vector3(0, 6.0, 0), Vector3(0.4, 0.14, 0.4))
		lamp(lp + Vector3(0, 5.8, 0), Color(1.0, 0.86, 0.62), 3.4, 20.0, 1.8)
		solid(lp + Vector3(0, 3.0, 0), Vector3(0.2, 6.0, 0.2))


func _crane(p: Vector3) -> void:
	ck(p.x)
	bar("sh_yellow", p, p + Vector3(0, 8.5, 0), 0.95, 12, Color(1, 1, 1), 0.8)
	solid(p + Vector3(0, 4.25, 0), Vector3(1.7, 8.5, 1.7))
	bar("sh_black", p + Vector3(0, 8.5, 0), p + Vector3(0, 8.8, 0), 1.25, 12)
	var cab := p + Vector3(0.2, 10.0, 0)
	city.box("sh_yellow", cab, Vector3(2.8, 2.4, 2.4))
	_window(cab + Vector3(1.4, 0.2, 0), Vector3(1, 0, 0), 1.6, 1.0, false)
	_window(cab + Vector3(0.3, 0.2, 1.2), Vector3(0, 0, 1), 1.2, 0.9, false)
	city.box("sh_black", cab + Vector3(-1.9, -0.3, 0), Vector3(1.0, 1.6, 2.0))
	# the jib: two chords and ties between them, reaching forward over the hatch; its hook hanging
	var foot := cab + Vector3(1.3, -0.9, 0)
	var head := foot + Vector3(12.5, 5.2, 0)
	for sg in [-1.0, 1.0]:
		bar("sh_yellow", foot + Vector3(0, 0, sg * 0.75), head + Vector3(0, 0, sg * 0.22), 0.11, 6)
		bar("sh_yellow", foot + Vector3(0, 0.9, sg * 0.6), head + Vector3(0, 0.25, sg * 0.2), 0.08, 6)
	for i in 9:
		var f := (i + 0.5) / 9.0
		var a: Vector3 = foot.lerp(head, f)
		var wz: float = lerp(0.75, 0.22, f)
		bar("sh_yellow", a + Vector3(0, 0, -wz), a + Vector3(0, 0, wz), 0.05, 5)
		bar("sh_yellow", a + Vector3(0, 0, -wz), a + Vector3(0.6, lerp(0.9, 0.25, f), wz * 0.8), 0.04, 5)
	bar("sh_steel", cab + Vector3(-0.6, 1.9, 0), head + Vector3(0, 0.3, 0), 0.02, 4, Color(0.15, 0.15, 0.15))
	bar("sh_yellow", cab + Vector3(-0.6, 1.2, 0), cab + Vector3(-0.6, 1.9, 0), 0.1, 6)
	bar("sh_steel", head, head + Vector3(0, -4.5, 0), 0.02, 4, Color(0.15, 0.15, 0.15))
	city.box("sh_yellow", head + Vector3(0, -4.7, 0), Vector3(0.3, 0.5, 0.2))
	city.box("sh_lit", cab + Vector3(1.0, -1.25, 0), Vector3(0.5, 0.1, 0.5))
	lamp(cab + Vector3(1.2, -1.5, 0), Color(1.0, 0.88, 0.66), 4.2, 24.0, 2.2)


func _forecastle() -> void:
	ck(38.0)
	# the windlass: a bed, two drums on a shaft, the chains running to the hawse pipes
	var w := Vector3(38.0, FD, 0)
	block("sh_grey", w + Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 3.6), 0.0, Color(0.5, 0.5, 0.5))
	bar("sh_black", w + Vector3(0, 0.85, -2.1), w + Vector3(0, 0.85, 2.1), 0.14, 8)
	for sg in [-1.0, 1.0]:
		bar("sh_black", w + Vector3(0, 0.85, sg * 0.7), w + Vector3(0, 0.85, sg * 1.5), 0.55, 12)
		bar("sh_black", w + Vector3(0.4, 0.5, sg * 1.1), Vector3(41.5, FD + 0.08, sg * 1.5), 0.07, 5)
		bar("sh_black", Vector3(41.5, FD + 0.08, sg * 1.5), Vector3(42.3, FD + 0.02, sg * 2.0), 0.07, 5)
		block("sh_grey", w + Vector3(0, 0.6, sg * 1.95), Vector3(0.9, 1.2, 0.3), 0.0, Color(0.55, 0.55, 0.55))
	# the foremast with its lamp, a locker
	var fm := Vector3(34.4, FD, 0)
	bar("sh_white", fm, fm + Vector3(0, 7.5, 0), 0.18, 8, Color(1, 1, 1), 0.1)
	bar("sh_white", fm + Vector3(0, 5.2, -1.4), fm + Vector3(0, 5.2, 1.4), 0.05, 6)
	solid(fm + Vector3(0, 3.7, 0), Vector3(0.36, 7.4, 0.36))
	city.box("sh_lit", fm + Vector3(0.25, 4.6, 0), Vector3(0.3, 0.14, 0.3))
	lamp(fm + Vector3(0.3, 4.4, 0), Color(0.85, 0.92, 1.0), 3.0, 18.0, 1.6)
	city.box("sh_lit", fm + Vector3(0.12, 7.3, 0), Vector3(0.12, 0.16, 0.12))
	city.glow(fm + Vector3(0.2, 7.3, 0), Color(1.0, 0.95, 0.85, 0.9), 1.4)
	block("sh_white", Vector3(33.0, FD + 0.5, -3.6), Vector3(1.4, 1.0, 0.9))
	# the jackstaff right forward
	bar("sh_white", Vector3(45.6, FD, 0), Vector3(45.6, FD + 2.4, 0), 0.04, 5)


# ---------------- the ladder down the side, the hero's boat ----------------
func _ladder() -> void:
	ck(-3.0)
	city.chunk = "ladder"
	var z := hw(0.0) + 0.75
	# the platform at its head (outboard of the gate), the flight down toward the bow, the platform at its foot
	var top := Vector3((GATE[0] + GATE[1]) * 0.5, D - 0.05, z)
	block("sh_grate", top, Vector3(GATE[1] - GATE[0], 0.1, 1.3))
	rail(Vector3(GATE[0], D, z - 0.65), Vector3(GATE[0], D, z + 0.65))
	rail(Vector3(GATE[0], D, z + 0.65), Vector3(GATE[1], D, z + 0.65))
	var foot_y := 0.75
	var run := 9.6
	flight(Vector3(GATE[1] + run, foot_y, z), Vector3(-1, 0, 0), 1.1, D - foot_y, run, [true, false])
	var bot := Vector3(GATE[1] + run + 1.0, foot_y - 0.05, z)
	block("sh_grate", bot, Vector3(2.0, 0.1, 1.3))
	rail(Vector3(GATE[1] + run + 2.0, foot_y, z - 0.65), Vector3(GATE[1] + run + 2.0, foot_y, z + 0.65))
	# wires holding it from a davit at the rail
	var dv := Vector3(GATE[1] + run * 0.5, D + BUL + 1.6, z - 0.3)
	bar("sh_white", Vector3(dv.x, D, hw(0.0) - 0.3), dv, 0.07, 6)
	bar("sh_steel", dv, Vector3(GATE[1] + run, foot_y + 0.1, z + 0.5), 0.015, 4, Color(0.15, 0.15, 0.15))
	bar("sh_steel", dv, Vector3(GATE[1] + run, foot_y + 0.1, z - 0.5), 0.015, 4, Color(0.15, 0.15, 0.15))
	lamp(Vector3(GATE[1] + 0.6, D + 2.6, z - 0.9), Color(1.0, 0.82, 0.6), 1.6, 9.0, 0.8)
	city.chunk = ""
	city.commit(false)
	# the boat: a rigid inflatable made fast at the foot of the ladder
	_rib(boat_at - Vector3(0, 0.35, 0), 0.06)


func _rib(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, p)
	var pts := [Vector3(-2.2, 0.42, 0.85), Vector3(1.2, 0.42, 0.85), Vector3(2.1, 0.46, 0.5), Vector3(2.5, 0.52, 0.0)]
	for sg in [-1.0, 1.0]:
		for i in pts.size() - 1:
			bar("sh_rubber", xf * (pts[i] * Vector3(1, 1, sg)), xf * (pts[i + 1] * Vector3(1, 1, sg)), 0.27, 9)
	quad("sh_grey", xf * Vector3(-2.2, 0.3, -0.75), xf * Vector3(1.6, 0.3, -0.75), xf * Vector3(1.6, 0.3, 0.75), xf * Vector3(-2.2, 0.3, 0.75), Vector3.UP, Color(0.5, 0.5, 0.5))
	quad("sh_grey", xf * Vector3(1.6, 0.3, -0.75), xf * Vector3(2.4, 0.4, 0), xf * Vector3(2.4, 0.4, 0), xf * Vector3(1.6, 0.3, 0.75), Vector3.UP, Color(0.5, 0.5, 0.5))
	tbox("sh_grey", xf * Vector3(-2.25, 0.4, 0), Vector3(0.1, 0.6, 1.6), b, Color(0.45, 0.45, 0.45))
	tbox("sh_black", xf * Vector3(-2.5, 0.75, 0), Vector3(0.36, 0.5, 0.4), b)
	tbox("sh_black", xf * Vector3(-2.5, 0.2, 0), Vector3(0.14, 0.9, 0.14), b)
	tbox("sh_wood", xf * Vector3(0.2, 0.5, 0), Vector3(0.3, 0.06, 1.4), b)
	bar("sh_steel", xf * Vector3(2.4, 0.6, 0.0), Vector3(GATE[1] + 9.6 + 1.9, 0.8, hw(0.0) + 0.75), 0.012, 4, Color(0.6, 0.55, 0.4))
	foam([[xf * Vector3(2.2, -0.35, 0), 0.4, 0.8], [xf * Vector3(-2.4, -0.35, 0), 1.3, 0.9], [xf * Vector3(-14.0, -0.35, 0), 2.6, 0.0]])
	city.commit(false)
	solid(p + b * Vector3(-0.2, 0.2, 0), Vector3(4.2, 0.2, 1.6), yaw)
	for sg in [-1.0, 1.0]:
		solid(p + b * Vector3(-0.3, 0.45, sg * 0.95), Vector3(4.4, 0.5, 0.3), yaw)
	solid(p + b * Vector3(-2.4, 0.5, 0), Vector3(0.3, 0.7, 1.8), yaw)


# ---------------- the sea, the islets, the launches ----------------
const WATER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep : source_color = vec3(0.014, 0.03, 0.038);
uniform vec3 sky : source_color = vec3(0.11, 0.15, 0.19);
uniform float drift = 0.0;
uniform float tm = 0.0;
uniform sampler2D frames : filter_linear, repeat_enable;     // 20 frames one under another, 0.5 + v / 0.08
uniform vec4 boats[6];        // x, z, heading x, heading z
uniform float boat_w[6];      // half width of each boat's wake where it starts (0: none)
varying vec3 wp;
varying float crest;
varying float thrown;

// the swell at a place: frames of a simulated sea, laid over the water twice at two sizes; returns the
// displacement (sideways, up, sideways) in metres
vec3 swell(vec2 p, float size, float t) {
	float f = fract(t / 4.0) * 20.0;
	float k = floor(f);
	vec2 uv = p / size;
	float v = clamp(fract(uv.y), 0.5 / 128.0, 1.0 - 0.5 / 128.0);
	vec3 a = textureLod(frames, vec2(uv.x, (k + v) / 20.0), 0.0).rgb;
	vec3 b = textureLod(frames, vec2(uv.x, (mod(k + 1.0, 20.0) + v) / 20.0), 0.0).rgb;
	return (mix(a, b, f - k) - 0.5) * 0.08 * size;
}

float hull_w(float x) {
	return 7.5 * (1.0 - pow(smoothstep(20.0, 47.5, x), 1.6)) * (1.0 - 0.2 * smoothstep(-40.0, -46.0, x));
}

// the water the ship herself throws up (q: a place by the ship, who lies along x with her bow at +47): the wave
// piled against her stem and rolling off down both sides in a V, the wash slapping along her plating in pulses
// that run aft, the boil under her stern
float wash(vec2 q, float t) {
	float az = abs(q.y);
	float al = 46.5 - q.x;
	float mid = 0.6 + al * 0.36;
	float wd = 1.1 + al * 0.05;
	float h = exp(-pow((az - mid) / wd, 2.0)) * 1.05 * exp(-max(al, 0.0) / 20.0) * smoothstep(-1.5, 1.0, al);
	float d = az - hull_w(q.x);
	float along = step(-46.5, q.x) * step(q.x, 47.5);
	h += along * exp(-max(d, 0.0) / 1.3) * step(-0.6, d) * (0.2 + 0.24 * max(0.0, sin(q.x * 0.42 + t * 2.6)) + 0.14 * sin(q.x * 1.1 + t * 4.1));
	float as_ = -44.5 - q.x;
	h += smoothstep(0.0, 2.0, as_) * exp(-max(as_, 0.0) / 9.0) * (1.0 - smoothstep(3.0, 6.5, az)) * (0.22 + 0.2 * sin(q.x * 1.3 + t * 5.0) * sin(q.y * 1.7 + t * 3.1));
	return h;
}

vec3 sea(vec2 p, float t, float longf, float shortf) {
	return swell(p, 260.0, t * 0.42) * longf * 0.2 + swell(p.yx + vec2(31.0, 7.0), 70.0, t * 0.8).zyx * shortf * 0.22;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	// (the sea lies quieter in the ship's lee, close under her sides)
	vec2 off = max(abs(wp.xz) - vec2(48.0, 7.5), vec2(0.0));
	float lee = mix(0.2, 1.0, smoothstep(0.0, 30.0, length(off)));
	vec2 q = wp.xz;
	wp.x += drift;
	float longf = (1.0 - smoothstep(250.0, 700.0, dist)) * lee;
	float shortf = (1.0 - smoothstep(60.0, 220.0, dist)) * lee;
	vec3 w = sea(wp.xz, tm, longf, shortf);
	thrown = wash(q, tm);
	w.y += thrown;
	// the slope, from the heights a step away each way
	float e = 0.9;
	float hx = sea(wp.xz + vec2(e, 0.0), tm, longf, shortf).y + wash(q + vec2(e, 0.0), tm);
	float hz = sea(wp.xz + vec2(0.0, e), tm, longf, shortf).y + wash(q + vec2(0.0, e), tm);
	vec2 sl = vec2(hx - w.y, hz - w.y) / e;
	VERTEX += vec3(w.x, w.y, w.z) * vec3(0.6, 1.0, 0.6);
	NORMAL = normalize(vec3(-sl.x, 1.0, -sl.y));
	TANGENT = normalize(vec3(1.0, sl.x, 0.0));
	BINORMAL = normalize(vec3(0.0, sl.y, 1.0));
	crest = w.y - thrown;
}

float band(float x, float a, float b) {
	return smoothstep(a, a + (b - a) * 0.35, x) * (1.0 - smoothstep(a + (b - a) * 0.65, b, x));
}

void fragment() {
	float dist = length(wp.xz - vec2(drift, 0.0) - CAMERA_POSITION_WORLD.xz);
	vec3 a = texture(ripples, wp.xz * 0.05 + vec2(TIME * 0.013, TIME * 0.02)).rgb;
	vec3 b = texture(ripples, wp.xz * 0.09 + vec2(-TIME * 0.026, TIME * 0.012)).rgb;
	vec3 c = texture(ripples, wp.xz * 0.011 + vec2(TIME * 0.004, -TIME * 0.003)).rgb;
	NORMAL_MAP = normalize(a + b + c - 1.5) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(1.0, 0.3, smoothstep(30.0, 260.0, dist));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// (darker in the troughs, a little paler on the backs of the waves: it is this that shows the swell)
	vec3 col = mix(deep, sky, fres * 0.85) * (0.85 + clamp(crest, -0.7, 0.7) * 0.3);

	// foam, worked out where it lies (so it rides the swell): the wash along the ship's sides, the wave off her
	// bows, her wake, and the wake of each boat
	vec2 p = wp.xz - vec2(drift, 0.0);           // (the ship's own place: she lies along x, her bow at +47)
	float az = abs(p.y);
	float hw = hull_w(p.x);
	// the wash: it surges out from the plating and falls back, in pulses running aft
	float surge = 1.6 + 1.3 * sin(p.x * 0.42 + tm * 2.6) + 0.7 * sin(p.x * 1.1 + tm * 4.1);
	float m = (1.0 - smoothstep(0.0, max(surge, 0.5) + 1.2, az - hw)) * step(-46.5, p.x) * step(p.x, 47.5);
	float al = 46.0 - p.x;                       // the wave off the bows: a V opening aft
	float mid = 0.8 + al * 0.36;
	m = max(m, band(az, mid - 1.0 - al * 0.03, mid + 1.6 + al * 0.07) * smoothstep(-1.0, 2.0, al) * (1.0 - smoothstep(20.0, 95.0, al)));
	float as_ = -44.0 - p.x;                     // the wake astern: broad, churned, dying away
	m = max(m, (1.0 - smoothstep(4.5 + as_ * 0.07, 7.0 + as_ * 0.11, az)) * smoothstep(-2.0, 3.0, as_) * (1.0 - smoothstep(30.0, 230.0, as_)) * 0.9);
	for (int i = 0; i < 6; i++) {
		if (boat_w[i] <= 0.0) {
			continue;
		}
		vec2 r = p - boats[i].xy;
		float back = -dot(r, boats[i].zw);
		float lat = abs(r.x * boats[i].w - r.y * boats[i].z);
		float len = boat_w[i] * 22.0;
		m = max(m, (1.0 - smoothstep(boat_w[i] * 0.5 + back * 0.1, boat_w[i] + back * 0.16, lat)) * smoothstep(-boat_w[i] * 2.5, 0.0, back) * (1.0 - smoothstep(len * 0.15, len, back)));
	}
	m = max(m, smoothstep(0.14, 0.55, thrown) * 0.95);  // (what she throws up is broken water on top)
	vec2 fp = wp.xz;
	float n1 = texture(ripples, fp * vec2(0.035, 0.09) + vec2(0.0, TIME * 0.02)).r;
	float n2 = texture(ripples, fp * 0.21 + vec2(TIME * 0.03, 0.0)).g;
	float lace = smoothstep(0.5, 0.72, n1 * 0.55 + n2 * 0.45 + (m - 0.5) * 0.42);
	float foam = clamp(m * lace + smoothstep(0.85, 1.0, m) * 0.12, 0.0, 1.0);
	// a little white where the tops of the bigger waves break
	foam = max(foam, smoothstep(0.55, 0.95, crest) * smoothstep(0.55, 0.68, n2) * 0.25);
	col = mix(col, vec3(0.36, 0.41, 0.45), foam * 0.72);
	ALBEDO = col;
	EMISSION = vec3(0.2, 0.27, 0.36) * foam * 0.5;      // (broken water catches what light there is)
	ROUGHNESS = mix(0.22, 0.8, foam);
	SPECULAR = mix(0.85, 0.3, foam);
	METALLIC = 0.0;
}
"""


## The height of the sea at a place (as the water's shader has it), for boats to ride.
var swell_img: Image
func _swell_h(p: Vector2, size: float, tt: float, comp: int) -> float:
	var f: float = fposmod(tt / 4.0, 1.0) * 20.0
	var k := int(f)
	var u: int = posmod(int(floor(p.x / size * 128.0)), 128)
	var v: int = posmod(int(floor(p.y / size * 128.0)), 128)
	var a: Color = swell_img.get_pixel(u, k * 128 + v)
	var b: Color = swell_img.get_pixel(u, ((k + 1) % 20) * 128 + v)
	return (lerp(a[comp], b[comp], f - k) - 0.5) * 0.08 * size


func sea_h(x: float, z: float) -> float:
	if swell_img == null:
		return 0.0
	var p := Vector2(x + run, z)
	var off := Vector2(max(abs(x) - 48.0, 0.0), max(abs(z) - 7.5, 0.0))
	var lee: float = lerp(0.2, 1.0, smoothstep(0.0, 30.0, off.length()))
	return (_swell_h(p, 260.0, t * 0.42, 1) * 0.2 + _swell_h(Vector2(p.y + 31.0, p.x + 7.0), 70.0, t * 0.8, 1) * 0.22) * lee


func _sea() -> void:
	var sh := Shader.new()
	sh.code = WATER
	var wm := ShaderMaterial.new()
	wm.shader = sh
	wm.set_shader_parameter("ripples", load("res://assets/fx/rain_ripples.png"))
	sea_mat = wm
	# the simulated sea's frames (assets/ship/swell.png: twenty frames one under another, 8 bits a value)
	var sw: Texture2D = load("res://assets/ship/swell.png")
	swell_img = sw.get_image()
	if swell_img.is_compressed():
		swell_img.decompress()
	wm.set_shader_parameter("frames", sw)
	# a sheet of water finely cut near the eye (to rise and fall in the swell) and coarsely far out
	var n := 140
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n + 1:
		for i in n + 1:
			var u := float(i) / n * 2.0 - 1.0
			var v := float(j) / n * 2.0 - 1.0
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(u * 70.0 + sign(u) * pow(abs(u), 4.0) * 830.0, 0, v * 70.0 + sign(v) * pow(abs(v), 4.0) * 830.0))
	for j in n:
		for i in n:
			var k := j * (n + 1) + i
			for q in [k, k + 1, k + n + 1, k + 1, k + n + 2, k + n + 1]:
				st.add_index(q)
	water = MeshInstance3D.new()
	water.mesh = st.commit()
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.extra_cull_margin = 4.0
	add_child(water)
	# spray: thrown up where the stem cuts the sea, boiling up under her stern
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true          # (without this every drop is drawn a metre across)
	sm.albedo_texture = main.fx.soft_tex
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.5, 0.58, 0.68, 0.22)
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	qm.material = sm
	# [where, the way it is thrown, how many, how fast, how big, how solid, the box it comes from]
	var jets := []
	for sg in [-1.0, 1.0]:
		# at the stem: fine drops flung up and out, and a thin mist hanging over them
		jets.append([Vector3(44.6, 0.5, sg * 1.1), Vector3(-0.55, 0.85, sg * 0.85), 170, 8.5, 0.75, 0.34, Vector3(1.6, 0.3, 0.7), 1.0])
		jets.append([Vector3(44.2, 0.5, sg * 1.3), Vector3(-0.6, 0.6, sg * 0.8), 14, 4.5, 3.0, 0.09, Vector3(1.6, 0.25, 0.7), 1.4])
		# down her shoulders, where the bow wave rolls off
		jets.append([Vector3(34.0, 0.35, sg * 5.6), Vector3(-0.75, 0.6, sg * 0.6), 110, 6.0, 0.65, 0.3, Vector3(7.0, 0.2, 1.4), 0.9])
		# all along her sides: drops off the wash slapping the plating
		jets.append([Vector3(-8.0, 0.3, sg * 7.75), Vector3(-0.75, 0.7, sg * 0.4), 190, 5.0, 0.55, 0.28, Vector3(34.0, 0.15, 0.3), 0.8])
	# under her stern: the screw's water boiling up
	jets.append([Vector3(-46.5, 0.2, 0.0), Vector3(-1.0, 0.45, 0.0), 90, 5.5, 0.7, 0.3, Vector3(1.0, 0.2, 4.5), 0.9])
	for e in jets:
		var ps := CPUParticles3D.new()
		var solid: float = e[5]
		var pm := sm.duplicate() as StandardMaterial3D
		# (drops: small, the colour of moonlit water, not white; the mist: wide and barely there)
		pm.albedo_color = Color(0.5, 0.62, 0.78, solid) if solid > 0.2 else Color(0.4, 0.5, 0.64, solid)
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		q.material = pm
		ps.mesh = q
		ps.amount = e[2] if main.ultra else int(e[2] * 0.5)      # (half as many drops on the ordinary app)
		ps.lifetime = e[7]
		ps.randomness = 0.7
		ps.explosiveness = 0.0
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		ps.emission_box_extents = e[6]
		ps.direction = (e[1] as Vector3).normalized()
		ps.spread = 22.0
		ps.initial_velocity_min = e[3] * 0.45
		ps.initial_velocity_max = e[3]
		ps.gravity = Vector3(-1.5, -9.8, 0)
		ps.scale_amount_min = e[4] * 0.45
		ps.scale_amount_max = e[4]
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.45))
		sc.add_point(Vector2(1, 1.5 if solid < 0.2 else 0.8))
		ps.scale_amount_curve = sc
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 0.0))
		gr.add_point(0.12, Color(1, 1, 1, 1.0))
		gr.set_color(2, Color(1, 1, 1, 0.0))
		ps.color_ramp = gr
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ps.visibility_aabb = AABB(Vector3(-60, -2, -20), Vector3(120, 12, 40))
		add_child(ps)
		ps.position = e[0]


## (Foam is drawn by the water itself now; these are kept so the places that asked for it need not change.)
func foam(_line: Array) -> void:
	pass


func _islets() -> void:
	var rock: StandardMaterial3D = main._tex_mat("res://assets/env/rock_albedo.jpg", "res://assets/env/rock_normal.png", 0.07, 0.95, true)
	rock.albedo_color = Color(0.5, 0.52, 0.56)
	var meshes := [main._rock_mesh(41), main._rock_mesh(42), main._rock_mesh(43)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var spots := [[Vector3(-95, -2, 70), Vector3(40, 17, 30)], [Vector3(-150, -3, -20), Vector3(64, 30, 48)], [Vector3(110, -2, 95), Vector3(52, 22, 40)],
		[Vector3(175, -3, -30), Vector3(80, 40, 64)], [Vector3(30, -3, -150), Vector3(96, 36, 50)], [Vector3(-60, -3, -120), Vector3(50, 24, 40)],
		[Vector3(40, -1, 120), Vector3(26, 10, 18)], [Vector3(-190, -4, 130), Vector3(100, 50, 80)], [Vector3(230, -4, 150), Vector3(110, 54, 90)],
		[Vector3(-30, -1, 150), Vector3(18, 7, 14)], [Vector3(120, -2, -140), Vector3(40, 20, 34)], [Vector3(-250, -5, -150), Vector3(130, 70, 100)]]
	for i in spots.size():
		var s: Array = spots[i]
		# each islet: a big mass and a few smaller ones leaning on it, stacks standing off in the water
		for k in 4:
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[(i + k) % 3]
			mi.material_override = rock
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var sc: Vector3 = s[1] * (1.0 if k == 0 else rng.randf_range(0.25, 0.55))
			var off := Vector3.ZERO if k == 0 else Vector3(rng.randf_range(-0.6, 0.6) * s[1].x, 0, rng.randf_range(-0.6, 0.6) * s[1].z)
			mi.position = s[0] + off
			mi.scale = sc * Vector3(1, rng.randf_range(0.8, 1.3), 1)
			isles.append([mi, mi.position.x, mi.scale])
			mi.rotation.y = rng.randf() * TAU


## A patrol launch, built round the origin (bow toward +x), on a node that is moved about.
func _launch() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var box := _boat_model(root, "res://assets/boats/fisher_boat.glb", FISHER_BOW, 9.0, 0.8)
	var roof: float = box.position.y + box.size.y * FISHER_ROOF
	var body := StaticBody3D.new()
	body.set_meta("surf", "metal")
	for e in [[Vector3(0, 0.5, 0), Vector3(9.0, 1.9, 3.2)], [Vector3(FISHER_CABIN, 2.0, 0), Vector3(2.6, 2.0, 2.4)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		cs.position = e[0]
		body.add_child(cs)
	root.add_child(body)
	# the searchlight: its lamp, its beam in the haze, the pool it throws
	var sl := SpotLight3D.new()
	sl.light_color = Color(0.86, 0.93, 1.0)
	sl.light_energy = 16.0
	sl.spot_range = 90.0
	sl.spot_angle = 9.0
	sl.spot_attenuation = 0.4
	sl.shadow_enabled = main.ultra
	root.add_child(sl)
	sl.position = Vector3(FISHER_CABIN, roof + 0.35, 0)
	root.set_meta("light", sl)
	root.set_meta("lamp_parts", [sl])
	bar("sh_black", Vector3(FISHER_CABIN, roof, 0), Vector3(FISHER_CABIN, roof + 0.3, 0), 0.06, 6)
	city.box("sh_black", Vector3(FISHER_CABIN, roof + 0.36, 0), Vector3(0.4, 0.36, 0.36))
	var lm: MeshInstance3D = city.commit(false)
	main.remove_child(lm)
	root.add_child(lm)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 5.5
	cm.height = 70.0
	cm.radial_segments = 14
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := ShaderMaterial.new()
	var bs2 := Shader.new()
	bs2.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.6);
	ALBEDO = vec3(0.6, 0.72, 0.9);
	ALPHA = edge * 0.11 * (1.0 - UV.y * 0.75);
}
"""
	bm.shader = bs2
	beam.material_override = bm
	beam.rotation.x = PI * 0.5
	beam.position = Vector3(0, 0, -35.0)
	sl.add_child(beam)
	var g: MeshInstance3D = city.glow(Vector3.ZERO, Color(0.86, 0.93, 1.0, 1.0), 2.6)
	g.get_parent().remove_child(g)
	root.add_child(g)
	g.position = sl.position
	main.lamp_can_break(Vector3.ZERO, [sl, g], 0.7, Vector3.ZERO, 0.0, sl)      # (the searchlight can be shot out)
	return root


func _boat_foam(_root: Node3D, _line: Array) -> void:
	pass


func _launches() -> void:
	for i in 2:
		var n := _launch()
		_boat_foam(n, [[Vector3(4.2, 0, 0), 0.6, 0.9], [Vector3(-4.2, 0, 0), 2.2, 0.9], [Vector3(-14.0, 0, 0), 3.2, 0.6], [Vector3(-38.0, 0, 0), 5.5, 0.0]])
		launches.append([n, i * 2.4 + 0.4, 37.0 if i == 0 else -34.0, n.get_meta("light")])
	_move_launches(0.0)
	for i in 3:
		_skiff(i)


func _move_launches(_dt: float) -> void:
	for l in launches:
		var a: float = l[1]
		var n: Node3D = l[0]
		# keeping station off her side, ranging up and dropping back
		var p := Vector3(sin(t * 0.07 + a) * 34.0, 0.0, l[2] + sin(t * 0.11 + a) * 5.0)
		var v := Vector3(cos(t * 0.07 + a) * 34.0 * 0.07 + SPEED, 0, cos(t * 0.11 + a) * 5.0 * 0.11)
		n.position = p + Vector3(0, 0.05 + sea_h(p.x, p.z) * 0.8, 0)
		n.rotation = Vector3(sin(t * 1.9 + a) * 0.04, atan2(-v.z, v.x), 0.05 + (sea_h(p.x + 3.0, p.z) - sea_h(p.x - 3.0, p.z)) * 0.14)
		# the light sweeps the ship's deck end to end and back
		var sl: SpotLight3D = l[3]
		var aim := Vector3(sin(t * 0.21 + a * 2.0) * 40.0, D + 1.0, sin(t * 0.33 + a) * 5.0)
		sl.look_at(aim, Vector3.UP)


## A downloaded boat model set on a node the way the game wants it: its bow toward +x, `length` long, centred, its
## keel `draft` under the node. bow: which way its bow points in the model's own scene. paint: [old colour, new].
func _boat_model(parent: Node3D, path: String, bow: Vector3, length: float, draft: float, paint := []) -> AABB:
	var inner: Node3D = load(path).instantiate()
	var hold := Node3D.new()
	parent.add_child(hold)
	hold.add_child(inner)
	inner.rotation.y = atan2(bow.z, bow.x)
	var box := AABB()
	var first := true
	var to_hold := hold.global_transform.affine_inverse()
	for mi in inner.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b: AABB = (to_hold * m.global_transform) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si) as BaseMaterial3D
			if mat != null and not paint.is_empty():
				var c: Color = mat.albedo_color
				if abs(c.r - paint[0].r) + abs(c.g - paint[0].g) + abs(c.b - paint[0].b) < 0.25:
					var nm: BaseMaterial3D = mat.duplicate()
					nm.albedo_color = paint[1]
					m.set_surface_override_material(si, nm)
	var k := length / box.size.x
	hold.scale = Vector3.ONE * k
	hold.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k - Vector3(0, draft, 0)
	return AABB((box.position - Vector3(box.get_center().x, box.position.y, box.get_center().z)) * k - Vector3(0, draft, 0), box.size * k)


## A jet ski with two men on it: one rides, the one behind him shoots. They come in ones, twos and threes all
## through the mission, race round the ship and fall away again. They can be shot to pieces.
const SKI_TINT := [Color(0.75, 0.06, 0.05), Color(0.08, 0.16, 0.42), Color(0.16, 0.2, 0.14)]
var SPRINT_BOW := Vector3(0.906, 0, 0.423)
var FISHER_BOW := Vector3(0, 0, 1)
var FISHER_ROOF := 0.62      # the cabin roof, as a share of the model's height (its masts stand above it)
var FISHER_CABIN := 1.2      # where along her the cabin is
var wave_cd := 14.0
var wave_n := 0


func _rider(parent: Node3D, kind: String, at: Vector3, armed: bool) -> Dictionary:
	var hold := Node3D.new()
	parent.add_child(hold)
	hold.position = at
	hold.rotation.y = -PI * 0.5        # (the models look along -z; the ski's bow is +x)
	var r: Dictionary = main.player.make_rig(Color(1, 1, 1), ["ak"], false, kind)
	var root: Node3D = r["root"]
	hold.add_child(root)
	root.rotation.y = PI
	(r["guns"]["ak"] as Node3D).visible = armed
	var ap: AnimationPlayer = r["ap"]
	ap.play("aim")
	ap.advance(0.2)
	ap.pause()
	ap.active = false
	# astride the seat: thighs forward and a little out, knees bent
	var sk: Skeleton3D = r["skel"]
	for sd in ["Left", "Right"]:
		var sgn := 1.0 if sd == "Left" else -1.0
		_point_bone(sk, sk.find_bone("mixamorig%sUpLeg" % sd), Vector3(sgn * 0.42, -0.22, LEG_FWD).normalized())
		_point_bone(sk, sk.find_bone("mixamorig%sLeg" % sd), Vector3(sgn * 0.12, -1.0, -0.1 * LEG_FWD).normalized())
		_point_bone(sk, sk.find_bone("mixamorig%sFoot" % sd), Vector3(sgn * 0.1, -0.25, LEG_FWD).normalized())
	if not armed:
		# his hands down on the bars
		for sd in ["Left", "Right"]:
			var sgn := 1.0 if sd == "Left" else -1.0
			_point_bone(sk, sk.find_bone("mixamorig%sArm" % sd), Vector3(sgn * 0.3, -0.55, LEG_FWD).normalized())
			_point_bone(sk, sk.find_bone("mixamorig%sForeArm" % sd), Vector3(-sgn * 0.12, -0.12, LEG_FWD).normalized())
	r["hold"] = hold
	return r


var LEG_FWD := 1.0


## Turn a bone so that it points along `dir` (in the skeleton's own space), by the shortest way.
func _point_bone(sk: Skeleton3D, b: int, dir: Vector3) -> void:
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b).basis.orthonormalized()
	var turned := Basis(Quaternion(g.y.normalized(), dir)) * g
	var par := sk.get_bone_parent(b)
	var pb := sk.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(b, (pb.inverse() * turned).get_rotation_quaternion())


func _skiff(i: int) -> void:
	var root := Node3D.new()
	add_child(root)
	var box := _boat_model(root, "res://assets/boats/sprint_boat.glb", SPRINT_BOW, 5.6, 0.26, [Color(1, 0, 0), SKI_TINT[i % 3]])
	if i == 0:
		pass
	_boat_foam(root, [[Vector3(1.8, 0, 0), 0.4, 0.9], [Vector3(-2.1, 0, 0), 1.4, 1.0], [Vector3(-8.0, 0, 0), 2.2, 0.7], [Vector3(-26.0, 0, 0), 3.4, 0.0]])
	var body := StaticBody3D.new()
	body.set_meta("surf", "metal")
	body.set_meta("kind", "machine")
	body.set_meta("hp", 170.0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(5.6, 1.9, 1.9)
	cs.shape = bs
	cs.position = Vector3(0, 0.8, 0)
	body.add_child(cs)
	root.add_child(body)
	main.machines.append(body)
	root.visible = false
	root.position = Vector3(-400, 0, 0)
	skiffs.append({"n": root, "body": body, "gun": {}, "st": "away", "a": 0.0, "w": 0.2, "side": 1.0, "off": -260.0, "life": 0.0,
		"cd": 2.0, "burst": 0, "sunk": 0.0, "last": root.position, "ring": i})


## The men on the skis (made once the player's own rig exists to copy from).
var riders_made := false
func _make_riders() -> void:
	riders_made = true
	var kinds := ["olive", "blue", "gasmask"]
	for i in skiffs.size():
		var root: Node3D = skiffs[i]["n"]
		_rider(root, kinds[i % 3], Vector3(0.3, RIDE_Y, 0), false)
		skiffs[i]["gun"] = _rider(root, kinds[(i + 1) % 3], Vector3(-1.2, RIDE_Y + 0.14, 0), true)


var RIDE_Y := -0.5
## Send the next few in from astern.
func _wave() -> void:
	var n: int = [2, 3, 1, 2, 1, 3, 2][wave_n % 7]
	wave_n += 1
	var sent := 0
	for s in skiffs:
		if sent >= n or s["st"] != "away":
			continue
		var body: StaticBody3D = s["body"]
		for c in body.get_children():
			if not (c is CollisionShape3D):
				c.queue_free()            # (what was left burning on it the last time)
		body.set_meta("gone", false)
		body.set_meta("hp", 170.0)
		s["st"] = "in"
		s["side"] = 1.0 if (wave_n + sent) % 2 == 0 else -1.0
		s["a"] = PI + sent * 1.3
		s["w"] = randf_range(0.19, 0.25)
		s["off"] = -240.0 - sent * 25.0
		s["life"] = randf_range(38.0, 55.0)
		s["sunk"] = 0.0
		s["cd"] = randf_range(1.5, 3.5)
		var nd: Node3D = s["n"]
		nd.visible = true
		nd.rotation = Vector3.ZERO
		sent += 1


func _move_skiffs(dt: float) -> void:
	var pl = main.player
	if pl == null:
		return
	if not riders_made:
		_make_riders()
	var busy := false
	for s in skiffs:
		var n: Node3D = s["n"]
		var st: String = s["st"]
		if st == "away":
			continue
		busy = true
		if s["body"].get_meta("gone", false):
			# hit and burning: it drops astern and goes down
			s["sunk"] += dt
			n.position += Vector3(-SPEED * 0.8 * dt, -0.1 * dt if s["sunk"] > 2.0 else 0.0, 0)
			n.rotation.z = lerp(n.rotation.z, 0.6, dt * 0.3)
			if s["sunk"] > 14.0:
				n.visible = false
				s["st"] = "away"
			continue
		if st == "in":
			s["off"] = move_toward(s["off"], 0.0, 26.0 * dt)
			if s["off"] == 0.0:
				s["st"] = "orbit"
		elif st == "orbit":
			s["life"] -= dt
			if s["life"] <= 0.0:
				s["st"] = "out"
		else:
			s["off"] -= 22.0 * dt
			if s["off"] < -260.0:
				n.visible = false
				s["st"] = "away"
				continue
		if st != "in":
			s["a"] += s["w"] * dt * s["side"]
		var a: float = s["a"]
		var p := Vector3(cos(a) * (72.0 + s["ring"] * 10.0) + s["off"], 0, sin(a) * (16.0 + s["ring"] * 4.5) + (0.0 if st == "orbit" else sin(t * 0.7 + a) * 2.0))
		var v: Vector3 = (p - s["last"]) / max(dt, 0.001) + Vector3(SPEED, 0, 0)
		s["last"] = p
		var sp: float = v.length()
		var hop: float = abs(sin(t * 6.0 + a * 9.0)) * 0.12 * clamp(sp / 12.0, 0.3, 1.2)
		n.position = p + Vector3(0, 0.1 + hop + sea_h(p.x, p.z) * 0.9, 0)
		var yaw := atan2(-v.z, v.x)
		var lean: float = clamp(angle_difference(n.rotation.y, yaw) * 4.0, -0.4, 0.4)
		n.rotation = Vector3(lerp(n.rotation.x, -lean, min(1.0, dt * 4.0)), lerp_angle(n.rotation.y, yaw, min(1.0, dt * 6.0)), 0.03 + clamp(sp / 20.0, 0.0, 1.0) * 0.07 + hop * 0.3)
		if pl == null or pl.dead:
			continue
		# the man behind turns to keep his rifle on the player, and fires when he has seen him
		var g: Dictionary = s["gun"]
		var hold: Node3D = g["hold"]
		var chest: Vector3 = pl.global_position + Vector3(0, 0.3 if pl.prone else 1.1, 0)
		var loc: Vector3 = n.global_transform.affine_inverse() * chest
		var want: float = clamp(atan2(-loc.z, loc.x), -2.0, 2.0)
		hold.rotation.y = lerp_angle(hold.rotation.y, -PI * 0.5 + want, min(1.0, dt * 5.0))
		var from: Vector3 = hold.global_position + Vector3(0, 1.25, 0)
		var dist := from.distance_to(chest)
		s["cd"] -= dt
		if s["cd"] > 0.0 or dist > 65.0:
			continue
		if not (mis != null and mis.alarm) and (dist > 40.0 or pl.prone or pl.crouch) and s["burst"] <= 0:
			s["cd"] = 0.4
			continue
		if s["burst"] <= 0:
			s["burst"] = 6
		s["burst"] -= 1
		s["cd"] = 0.12 if s["burst"] > 0 else randf_range(2.0, 4.0)
		var dir := (chest - from).normalized()
		from += dir * 0.9
		dir = (dir + Vector3(randf_range(-0.06, 0.06), randf_range(-0.04, 0.04), randf_range(-0.06, 0.06))).normalized()
		main.fx.muzzle_flash(from, dir, "ak")
		main.snd.enemy_shot(from)
		var end: Vector3 = main.shoot_ray(from, dir, 7.0, s["body"])
		main.fx.tracer(from, end)
	if not busy:
		wave_cd -= dt
		if wave_cd <= 0.0:
			wave_cd = randf_range(16.0, 30.0)
			_wave()


# ---------------- putting it together ----------------
func build() -> Vector3:
	_mats()
	_hull()
	_house()
	_cargo()
	_forecastle()
	city.chunk = ""
	city.commit(true)
	await get_tree().process_frame
	_ladder()
	_sea()
	_islets()
	_launches()
	_marked()
	_posts()
	_sounds()
	return boat_at


## The two containers the manifest names: red tags on them, and they can be destroyed.
func _marked() -> void:
	for i in 2:
		var p: Vector3 = [Vector3(25.8, D, 0.0), Vector3(-27.5, D, 0.0)][i]
		var c: StaticBody3D = main._prop("res://assets/env/container_%s.glb" % ["green", "blue"][i], p, 0.0, Vector3(2.44, 2.59, 6.06), "metal")
		c.set_meta("kind", "machine")
		c.set_meta("hp", 900.0)
		c.set_meta("obj", 1 + i)
		main.machines.append(c)
		marked.append(c)
		for sx in [-1.0, 1.0]:
			var tag := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.02, 0.5, 0.9)
			tag.mesh = bm
			tag.material_override = city.mats["sh_red"]
			c.add_child(tag)
			tag.position = Vector3(sx * 1.235, 1.6, 0)


func _posts() -> void:
	var k := ["olive", "blue", "gasmask"]
	var e := PI * 0.5       # facing +x
	for q in [
			[Vector3(-12.0, D, 6.2), 0.0, "ak", [Vector3(-12.0, D, 6.2), Vector3(-24.0, D, 6.2)]],
			[Vector3(0.0, D, -6.2), 0.0, "ak", [Vector3(-20.0, D, -6.2), Vector3(20.0, D, -6.2)]],
			[Vector3(21.5, D, 6.0), -e, "ak", [Vector3(21.5, D, 6.0), Vector3(8.0, D, 6.2)]],
			[Vector3(28.6, D, -3.6), 0.0, "ak", []],
			[Vector3(40.0, FD, 0.5), -e, "ak", [Vector3(40.0, FD, 0.5), Vector3(35.5, FD, 3.0), Vector3(35.5, FD, -3.0)]],
			[Vector3(-44.2, D, 1.5), e, "ak", [Vector3(-44.2, D, 3.5), Vector3(-44.2, D, -3.5)]],
			[Vector3(-28.0, D, -3.5), -e, "ak", []],
			[Vector3(-34.0, D, 6.4), -e, "ak", [Vector3(-40.0, D, 6.4), Vector3(-30.0, D, 6.4)]],
			[Vector3(-8.0, D, 5.2), PI, "ak", []],
			[Vector3(-39.8, BD, 4.2), e, "ak", []],
			[Vector3(-33.5, BD, -6.4), PI, "svd", []],
			[Vector3(-33.0, BD, 1.8), -e, "ak", []]]:
		posts.append([q[0], q[1], k[posts.size() % 3], q[2], q[3]])


var seen_t := 0.0
var under_t := -1.0             # under the water after going over the side: time into it (-1: not)
var sea_snd: AudioStreamPlayer
var under_snd: AudioStreamPlayer


## The sea round the ship, and the deep (the user's own two sounds, cut to loops).
func _sounds() -> void:
	sea_snd = AudioStreamPlayer.new()
	under_snd = AudioStreamPlayer.new()
	for e in [[sea_snd, "ocean_loop", -40.0], [under_snd, "underwater", -60.0]]:
		var st: AudioStream = load("res://assets/sfx/%s.ogg" % e[1])
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		(e[0] as AudioStreamPlayer).stream = st
		(e[0] as AudioStreamPlayer).volume_db = e[2]
		add_child(e[0])
	sea_snd.play()


func _physics_process(dt: float) -> void:
	var pl = main.player
	if pl == null or pl.dead:
		return
	# over the side: a moment under the water (the sea's noise gone, the deep in his ears), then hauled back into
	# the boat, the worse for it
	if under_t < 0.0 and pl.global_position.y < -0.7:
		under_t = 0.0
		under_snd.play()
	if under_t >= 0.0:
		under_t += dt
		pl.vel.x *= 0.9
		pl.vel.z *= 0.9
		pl.vel.y = max(pl.vel.y, -1.2)          # (he sinks slowly)
		if under_t > 1.7:
			under_t = -1.0
			pl.global_position = boat_at + Vector3(0, 0.1, 0)
			pl.vel = Vector3.ZERO
			pl.hit(30.0, pl.global_position + Vector3(0, 0, 1))
			main.ui.message("OVERBOARD", "You drag yourself back into the boat.", 2.5)
	# the sea's sound: louder down by the water, less up on the bridge; under water only the deep is heard
	var down: float = clamp(1.0 - (pl.global_position.y - 1.0) / 14.0, 0.0, 1.0)
	var want_sea: float = -60.0 if under_t >= 0.0 else lerp(-24.0, -15.0, down)
	sea_snd.volume_db = move_toward(sea_snd.volume_db, want_sea, dt * (90.0 if under_t >= 0.0 else 30.0))
	under_snd.volume_db = move_toward(under_snd.volume_db, -2.0 if under_t >= 0.0 else -60.0, dt * 80.0)
	if under_t < 0.0 and under_snd.playing and under_snd.volume_db <= -59.0:
		under_snd.stop()
	for en in main.enemies:
		if not en.dead and en.global_position.y < -0.5:
			en.take_hit(999.0, en.global_position, Vector3.DOWN)
	# caught in a launch's light: the nearest man aboard comes to look
	seen_t = max(0.0, seen_t - dt)
	for l in launches:
		var sl: SpotLight3D = l[3]
		var to: Vector3 = pl.global_position + Vector3(0, 1.0, 0) - sl.global_position
		if not sl.visible or seen_t > 0.0 or pl.prone or to.length() > 85.0 or (-sl.global_transform.basis.z).dot(to.normalized()) < cos(deg_to_rad(8.0)):
			continue
		var q := PhysicsRayQueryParameters3D.create(sl.global_position, pl.global_position + Vector3(0, 1.0, 0))
		q.exclude = [pl.get_rid()]
		q.collision_mask = 1
		var h: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
		if not h.is_empty():
			continue
		seen_t = 6.0
		var best = null
		for en in main.enemies:
			if not en.dead and en.mode == "guard" and (best == null or en.global_position.distance_to(pl.global_position) < best.global_position.distance_to(pl.global_position)):
				best = en
		if best != null:
			best.investigate(pl.global_position)
			main.ui.message("IN THE LIGHT", "A launch's light has found you. Someone is coming to look.", 2.5)


func _process(dt: float) -> void:
	t += dt
	if radar != null:
		radar.rotation.y += dt * 2.2
	run += SPEED * dt
	_move_launches(dt)
	_move_skiffs(dt)
	if sea_mat != null:
		sea_mat.set_shader_parameter("drift", run)
		sea_mat.set_shader_parameter("tm", t)
		var bs := []
		var bw := []
		for l in launches:
			var n: Node3D = l[0]
			var f := n.global_transform.basis.x
			bs.append(Vector4(n.position.x - 2.0, n.position.z, f.x, f.z))
			bw.append(2.2)
		for sk in skiffs:
			var n: Node3D = sk["n"]
			var f := n.global_transform.basis.x
			bs.append(Vector4(n.position.x, n.position.z, f.x, f.z))
			bw.append(1.5 if sk["st"] != "away" and not sk["body"].get_meta("gone", false) else 0.0)
		bs.append(Vector4(boat_at.x - 2.0, boat_at.z, 1, 0))
		bw.append(0.9)
		sea_mat.set_shader_parameter("boats", bs)
		sea_mat.set_shader_parameter("boat_w", bw)
	for il in isles:
		var x: float = wrapf(il[1] - run, -620.0, 620.0)
		var mi: MeshInstance3D = il[0]
		mi.position.x = x
		mi.scale = il[2] * Vector3(1, smoothstep(620.0, 520.0, abs(x)), 1)
	var cam := get_viewport().get_camera_3d()
	if cam != null and water != null:
		var c := cam.global_position
		water.position = Vector3(c.x, 0.0, c.z)


# ---------------- the night over the bay ----------------
const SKY := """
shader_type sky;
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(vec3(0.05, 0.085, 0.16), vec3(0.008, 0.014, 0.035), pow(clamp(h, 0.0, 1.0), 0.45));
	col = mix(col, vec3(0.02, 0.035, 0.07), smoothstep(0.0, -0.2, h));
	// stars: one in a few cells of a fine grid, twinkling a little, thinning toward the haze of the horizon
	vec3 g = d * 150.0;
	vec3 c = floor(g);
	float s = hash(c);
	float star = step(0.9965, s) * smoothstep(0.45, 0.0, length(fract(g) - 0.5));
	col += vec3(0.9, 0.95, 1.0) * star * (0.5 + 0.5 * fract(s * 91.7)) * smoothstep(0.03, 0.3, h) * 1.4;
	// the moon and the glow round it
	float m = dot(d, LIGHT0_DIRECTION);
	col += vec3(0.95, 0.97, 1.0) * smoothstep(0.99988, 0.99994, m) * 2.2;
	col += vec3(0.25, 0.33, 0.5) * (pow(max(m, 0.0), 180.0) * 0.5 + pow(max(m, 0.0), 12.0) * 0.12);
	COLOR = col;
}
"""


func night_look() -> void:
	var env: Environment = main.world_env
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY
	sm.shader = sh
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.46, 0.72)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.08, 0.14)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.tonemap_exposure = 1.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.95
	env.adjustment_contrast = 1.05
	main.sun.rotation_degrees = Vector3(-24, 205, 0)
	main.sun.light_color = Color(0.62, 0.74, 1.0)
	main.sun.light_energy = 0.55
	main.sun.shadow_opacity = 0.8
