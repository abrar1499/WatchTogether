extends Node3D
## Snow for a mission: flakes falling round the camera (moved on the graphics chip, as the rain is), and a layer of
## snow lying on top of everything flat and still (walls, roofs, containers, crates), all of it one mesh.

var main: Node
var flakes: MultiMeshInstance3D
var mat: ShaderMaterial

const FLAKE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords, blend_mix;
uniform vec3 box = vec3(22.0, 12.0, 22.0);
uniform float speed = 0.6;      // (a flake falls at about half a metre to a metre a second)
uniform vec2 wind = vec2(0.22, 0.09);
varying float vis;
varying vec2 uv;

void vertex() {
	vec4 r = INSTANCE_CUSTOM;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 base = r.xyz * box;
	// flakes of every size: most of them small, a few big ones (clumps), the big ones falling a little faster
	float big = pow(fract(r.w * 9.1), 3.0);
	float sp = speed * (0.75 + 0.45 * big + 0.25 * r.w);
	// each flake drifts its own way as it falls
	vec2 sway = vec2(sin(TIME * (0.35 + 0.5 * r.w) + r.x * 40.0), cos(TIME * (0.3 + 0.5 * r.y) + r.z * 40.0)) * (0.22 + 0.2 * r.x);
	vec3 w;
	w.y = cam.y - box.y * 0.45 + mod(base.y - TIME * sp, box.y);
	w.x = cam.x + mod(base.x + wind.x * TIME + sway.x - cam.x, box.x) - box.x * 0.5;
	w.z = cam.z + mod(base.z + wind.y * TIME + sway.y - cam.z, box.z) - box.z * 0.5;
	float dist = distance(cam, w);
	float size = (0.005 + 0.026 * big) + dist * 0.0007;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	VERTEX = w + (right * VERTEX.x + up * VERTEX.y) * size * 2.0;
	uv = UV;
	vis = (1.0 - smoothstep(box.x * 0.32, box.x * 0.5, dist)) * smoothstep(0.5, 1.4, dist);
}

void fragment() {
	float d = length(uv - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.97, 0.98, 1.0);
	ALPHA = vis * (1.0 - smoothstep(0.35, 1.0, d)) * 0.85;
}
"""


func start(m: Node) -> void:
	main = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	var n := 7000
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var sh := Shader.new()
	sh.code = FLAKE_SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	flakes = MultiMeshInstance3D.new()
	flakes.multimesh = mm
	flakes.material_override = mat
	flakes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flakes.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	add_child(flakes)
	_caps()


## Snow lying on what is flat and still: for every solid box and every standing thing with a box for its shape, a
## thin white slab on its top, a little smaller than the top and rounded off by its own shading. One mesh for all.
func _caps() -> void:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var ix := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for b in main.get_children():
		if not (b is StaticBody3D) or not b.is_visible_in_tree():
			continue
		if str(b.get_meta("kind", "")) in ["door", "crate", "drum", "machine"] or b.has_meta("hp"):
			continue          # (things that break or open: their snow would be left hanging)
		for cs in b.get_children():
			if not (cs is CollisionShape3D) or not (cs.shape is BoxShape3D):
				continue
			var xf: Transform3D = cs.global_transform
			if abs(xf.basis.y.normalized().y) < 0.98:
				continue      # (not standing upright)
			var sz: Vector3 = (cs.shape as BoxShape3D).size * xf.basis.get_scale()
			if sz.x * sz.z < 0.25 or sz.x < 0.25 or sz.z < 0.25 or sz.y > 40.0:
				continue
			var top: float = xf.origin.y + sz.y * 0.5
			if top < 0.3:
				continue      # (lying in the ground: the ground's own snow covers it)
			var th: float = clamp(min(sz.x, sz.z) * 0.12, 0.03, 0.09)
			var hx: float = sz.x * 0.5 + 0.015
			var hz: float = sz.z * 0.5 + 0.015
			var ax: Vector3 = xf.basis.x.normalized()
			var az: Vector3 = xf.basis.z.normalized()
			var c := Vector3(xf.origin.x, top, xf.origin.z)
			var base: int = v.size()
			# a low mound: the rim at the top of the box, the middle raised
			for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				v.append(c + ax * hx * k[0] + az * hz * k[1] - Vector3(0, 0.02, 0))
				nr.append((Vector3.UP * 0.5 + ax * k[0] * 0.5 + az * k[1] * 0.5).normalized())
			for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				v.append(c + ax * (hx - min(0.08, hx * 0.5)) * k[0] + az * (hz - min(0.08, hz * 0.5)) * k[1] + Vector3(0, th, 0))
				nr.append((Vector3.UP + ax * k[0] * 0.12 + az * k[1] * 0.12).normalized())
			for k in 4:
				var a: int = base + k
				var b2: int = base + (k + 1) % 4
				ix.append_array(PackedInt32Array([a, b2, b2 + 4, a, b2 + 4, a + 4]))
			ix.append_array(PackedInt32Array([base + 4, base + 5, base + 6, base + 4, base + 6, base + 7]))
			# a little on its sides too: snow clinging below the top edge, uneven, and a low drift blown against its
			# foot where it stands on the ground
			var bottom: float = xf.origin.y - sz.y * 0.5
			for side in [[ax, az, hx, hz], [-ax, az, hx, hz], [az, ax, hz, hx], [-az, ax, hz, hx]]:
				var out: Vector3 = side[0]
				var along: Vector3 = side[1]
				var d_out: float = float(side[2]) - 0.015
				var half: float = float(side[3]) - 0.015
				var steps: int = int(clamp(ceil(half * 2.0 / 0.2), 2.0, 80.0))
				var prev_drop := rng.randf_range(0.03, 0.14)
				var prev_h := rng.randf_range(0.08, 0.16)
				var prev_r := rng.randf_range(0.24, 0.34)
				for k in steps:
					var u0: float = -half + (half * 2.0) * k / steps
					var u1: float = -half + (half * 2.0) * (k + 1) / steps
					# (each step a little more or less than the last: an uneven edge, not a saw's)
					var drop: float = clamp(prev_drop + rng.randf_range(-0.05, 0.05), 0.02, 0.26)
					if rng.randf() < 0.06:
						drop = rng.randf_range(0.18, 0.34)
					if sz.y > 0.5:
						var b0: int = v.size()
						var face: Vector3 = c + out * (d_out + 0.012)
						v.append(face + along * u0); v.append(face + along * u1)
						v.append(face + along * u1 - Vector3(0, drop, 0)); v.append(face + along * u0 - Vector3(0, prev_drop, 0))
						for q in 4:
							nr.append((out + Vector3(0, 0.35, 0)).normalized())
						ix.append_array(PackedInt32Array([b0, b0 + 1, b0 + 2, b0, b0 + 2, b0 + 3]))
					prev_drop = drop
					if bottom < 0.2 and sz.y > 0.35:
						var b1: int = v.size()
						var foot: Vector3 = Vector3(c.x, bottom, c.z) + out * d_out
						# (one unbroken bank: each step starts where the last one ended)
						var hgt: float = clamp(prev_h + rng.randf_range(-0.03, 0.03), 0.06, 0.2)
						var reach: float = clamp(prev_r + rng.randf_range(-0.05, 0.05), 0.2, 0.42)
						v.append(foot + along * u0 + Vector3(0, prev_h, 0)); v.append(foot + along * u1 + Vector3(0, hgt, 0))
						v.append(foot + along * u1 + out * reach + Vector3(0, 0.01, 0)); v.append(foot + along * u0 + out * prev_r + Vector3(0, 0.01, 0))
						prev_h = hgt
						prev_r = reach
						for q in 4:
							nr.append((Vector3.UP + out * 0.5).normalized())
						ix.append_array(PackedInt32Array([b1, b1 + 1, b1 + 2, b1, b1 + 2, b1 + 3]))
	if v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_INDEX] = ix
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.95, 0.97, 1.0)
	sm.roughness = 0.7
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
