extends Node3D
## Mission 2 at night: the militia wear head lamps and the tower posts have a lamp, so they can be seen in the dark;
## and the weather turns: a few clouds at first, more and more, then rain, with lightning and thunder.

var main: Node
var t := 0.0

# ---- weather timeline (seconds from the start of the mission) ----
const CLOUD_START := 0.3        # how much of the sky is cloud at the start
const CLOUD_FULL := 0.92        # and when it is about to rain
const THICKEN_T := 90.0         # clouds grow over this long
const RAIN_T := 100.0           # then the rain begins (clouds first, thunder far off, then rain)
const RAIN_RAMP := 25.0         # and gets heavy over this long

var sky_mat: ShaderMaterial
var rain_snd: AudioStreamPlayer
var thunders: Array = []
var thunder_snd: AudioStreamPlayer
var thunders_far: Array = []     # the same claps with the rain filtered out of them: heard before it rains
var cover := CLOUD_START
var rain := 0.0
var flash := 0.0
var flash_seq: Array = []        # [time, strength] pulses of the stroke now under way
var next_bolt := 0.0
var drift := Vector2.ZERO
var sun_e := 0.2
var amb_e := 0.38
var indoors := 0.0               # rain hidden under a roof
var roof_t := 0.0

# ---- lamps ----
const SPOTS := 3                 # real lights for the nearest lamps (the rest only glow)
var spots: Array = []
var lamped := {}
var reach_of := {}
var beam_mat: ShaderMaterial
var glow_mat: ShaderMaterial
var bulb_mat: StandardMaterial3D
var check_t := 0.0


func start(m: Node) -> void:
	main = m
	sun_e = main.sun.light_energy
	amb_e = main.world_env.ambient_light_energy
	_make_sky()
	_make_rain()
	_make_sound()
	_make_lamp_parts()
	for i in (6 if main.ultra else SPOTS):      # (the HD app: twice as many real lights)
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.93, 0.78)
		s.light_energy = 3.5
		s.spot_range = 17.0
		s.spot_angle = 22.0
		s.spot_angle_attenuation = 1.4
		s.shadow_enabled = false
		s.visible = false
		add_child(s)
		spots.append(s)
	_lamp_all()
	_tower_lamps()
	next_bolt = 40.0               # the first stroke far off, well before the rain


# =============== sky: the night picture with clouds over it ===============
const SKY_SHADER := """
shader_type sky;
uniform sampler2D pano : source_color, filter_linear;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float energy = 0.08;
uniform float cover = 0.2;
uniform float flash = 0.0;
uniform vec2 drift = vec2(0.0);

void sky() {
	vec3 col = texture(pano, SKY_COORDS).rgb * energy;
	vec3 d = EYEDIR;
	if (!AT_CUBEMAP_PASS && d.y > -0.02) {
		vec2 p = d.xz / (d.y + 0.15) * 0.18;
		float n = texture(clouds, p + drift).r * 0.62 + texture(clouds, p * 2.7 - drift * 1.6).r * 0.38;
		float c = smoothstep(1.0 - cover, 1.0 - cover + 0.32, n + 0.12);
		c *= smoothstep(-0.02, 0.12, d.y);
		// lit a little from below by the town, darker on top; the stroke lights them up
		float low = 1.0 - smoothstep(0.0, 0.45, d.y);
		vec3 cc = mix(vec3(0.12, 0.125, 0.15), vec3(0.32, 0.25, 0.2), low) * (0.6 + 0.8 * n);
		cc += flash * vec3(0.55, 0.6, 0.75) * (0.35 + 0.65 * n);
		col = mix(col, cc, c);
		col += flash * 0.06 * vec3(0.7, 0.75, 0.9);
	}
	COLOR = col;
}
"""


func _make_sky() -> void:
	var old: Sky = main.world_env.sky
	var pano: Texture2D = null
	var energy := 0.08
	if old and old.sky_material is PanoramaSkyMaterial:
		pano = (old.sky_material as PanoramaSkyMaterial).panorama
		energy = (old.sky_material as PanoramaSkyMaterial).energy_multiplier
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("pano", pano)
	sky_mat.set_shader_parameter("energy", energy)
	sky_mat.set_shader_parameter("clouds", load("res://assets/sky/clouds.png"))
	sky_mat.set_shader_parameter("cover", cover)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	main.world_env.sky = sky


# =============== rain: streaks round the camera, moved on the graphics chip ===============
## Two layers: close drops (seen as thin streaks, a few to a metre) and the far rain, a fine grey haze of hair-thin
## lines; both lean with the wind. Splashes on the ground round the player: a bright fleck and a ring spreading.
const RAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords, blend_mix;
uniform float amount = 0.0;
uniform vec3 box = vec3(26.0, 16.0, 26.0);
uniform float speed = 9.0;
uniform float flash = 0.0;
uniform vec2 wind = vec2(0.6, 0.25);
uniform float len = 0.6;
uniform float width = 0.005;
uniform float strength = 0.2;
uniform float near_cut = 0.5;
uniform vec4 lights[8];             // xyz: a lamp near the camera, w: how far its light reaches
uniform vec3 amb = vec3(0.075, 0.082, 0.1);
varying float vis;
varying float along;
varying vec3 lit;
varying float glint;

void vertex() {
	vec4 r = INSTANCE_CUSTOM;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 base = r.xyz * box;
	float sp = speed * (0.8 + 0.4 * r.w);
	float fall = TIME * sp;
	vec3 w;
	w.y = cam.y - box.y * 0.4 + mod(base.y - fall, box.y);
	vec2 drift = wind * TIME;
	w.x = cam.x + mod(base.x + drift.x - cam.x, box.x) - box.x * 0.5;
	w.z = cam.z + mod(base.z + drift.y - cam.z, box.z) - box.z * 0.5;
	vec3 to = cam - w;
	float dist = length(to);
	vec3 down = normalize(vec3(wind.x, -sp, wind.y));
	vec3 side = normalize(cross(down, to));
	// as long as the drop falls in a sixtieth of a second or so (it is seen smeared), thin as a hair
	float l = len * (0.5 + 1.1 * fract(r.w * 7.13));
	glint = 0.35 + 1.05 * fract(r.w * 11.7 + r.x);      // (each drop catches the light its own way)
	VERTEX = w + side * VERTEX.x * (width + dist * 0.00045) + down * VERTEX.y * l;
	along = UV.y;
	// water has no colour of its own: a drop is seen by the light it catches (dim grey in the dark, warm by a lamp)
	lit = amb;
	for (int i = 0; i < 8; i++) {
		float f = clamp(1.0 - distance(w, lights[i].xyz) / max(lights[i].w, 0.01), 0.0, 1.0);
		lit += vec3(1.0, 0.82, 0.6) * f * f * 2.2;
	}
	lit += flash * vec3(0.85, 0.9, 1.0);
	vis = step(fract(r.w * 3.71), amount) * (1.0 - smoothstep(box.x * 0.3, box.x * 0.5, dist)) * smoothstep(near_cut, near_cut + 1.0, dist);
}

void fragment() {
	float k = 1.0 - abs(along * 2.0 - 1.0);
	float bright = clamp(max(lit.r, max(lit.g, lit.b)), 0.0, 1.0);
	ALBEDO = clamp(vec3(0.36, 0.39, 0.46) + (lit - amb) * 1.4, 0.0, 1.0);     // (water has no colour: grey-blue in the dark, warm by a lamp, never white of itself)
	ALPHA = vis * k * strength * glint * clamp(0.5 + bright * 1.8, 0.0, 2.2);
}
"""

const SPLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords, blend_mix;
uniform float amount = 0.0;
uniform float floor_y = 0.0;
uniform vec2 box = vec2(16.0, 16.0);
uniform float flash = 0.0;
uniform vec4 lights[8];
uniform vec3 amb = vec3(0.075, 0.082, 0.1);
varying float ph;
varying float vis;
varying vec2 uv;
varying vec3 lit;

void vertex() {
	vec4 r = INSTANCE_CUSTOM;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float tt = TIME * (1.3 + r.w * 1.2) + r.z * 13.0;
	float cyc = floor(tt);
	ph = fract(tt);
	vec2 h = fract(sin(vec2(cyc * 12.9898 + r.x * 78.233, cyc * 39.346 + r.y * 11.135)) * 43758.5453);
	vec2 base = fract(r.xy + h) * box;
	vec2 p;
	p.x = cam.x + mod(base.x - cam.x, box.x) - box.x * 0.5;
	p.y = cam.z + mod(base.y - cam.z, box.y) - box.y * 0.5;
	float size = 0.012 + 0.045 * ph;
	VERTEX = vec3(p.x + VERTEX.x * size * 2.0, floor_y, p.y + VERTEX.y * size * 2.0);
	float dist = distance(vec2(cam.x, cam.z), p);
	vis = step(fract(r.w * 5.3), amount) * (1.0 - smoothstep(box.x * 0.3, box.x * 0.5, dist));
	uv = UV;
	lit = amb;
	for (int i = 0; i < 8; i++) {
		float f = clamp(1.0 - distance(vec3(p.x, floor_y, p.y), lights[i].xyz) / max(lights[i].w, 0.01), 0.0, 1.0);
		lit += vec3(1.0, 0.82, 0.6) * f * f * 1.4;
	}
	lit += flash * vec3(0.7);
}

void fragment() {
	float d = length(uv - vec2(0.5)) * 2.0;
	float ring = smoothstep(0.78, 0.9, d) * (1.0 - smoothstep(0.9, 1.0, d)) * (1.0 - ph) * (1.0 - ph);
	float fleck = (1.0 - smoothstep(0.0, 0.3, d)) * (1.0 - smoothstep(0.0, 0.18, ph));
	float bright = clamp(max(lit.r, max(lit.g, lit.b)), 0.0, 1.0);
	ALBEDO = clamp(vec3(0.36, 0.39, 0.46) + (lit - amb) * 1.4, 0.0, 1.0);     // (water has no colour: grey-blue in the dark, warm by a lamp, never white of itself)
	ALPHA = vis * (ring * 0.3 + fleck * 0.45) * clamp(0.25 + bright * 2.0, 0.0, 1.5);
}
"""

var rain_layers: Array = []      # [MultiMeshInstance3D, ShaderMaterial]
var splash_mi: MultiMeshInstance3D
var splash_mat: ShaderMaterial
var wet_mats: Array = []         # [material, roughness, colour, specular]
var fog_d := 0.006
var fog_c := Color()
var wind := Vector2(0.6, 0.25)
var last_wet := 0.0
var sat0 := 1.0
var con0 := 1.0
var sky_fog0 := 0.35
var light_t := 0.0
var tower_spots: Array = []      # the tower lamps' places


## The lamps nearest the camera (street lamps, tower lamps, head lamps) for the rain to catch their light.
func _rain_lights() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var cand := []
	var c = main.mission.get("city") if main.mission else null
	if c != null:
		for lp in c.lamps:
			var ol: Node3D = lp[1]
			if is_instance_valid(ol):
				cand.append([ol.global_position - Vector3(0, 3.2, 0), 8.5])     # (its light falls in a cone below it)
	for tp in tower_spots:
		cand.append([tp - Vector3(0, 1.2, 0), 6.5])
	for e in lamped:
		var l: Node3D = lamped[e]
		if is_instance_valid(l) and l.visible:
			# the drops lit are those in his beam, out in front of him
			var r: float = float(reach_of.get(l, 7.0))
			if r < 0.2:
				continue
			# (a ball of lit drops that ends short of the wall the beam stops at: none lit on the far side of it)
			var rad: float = min(2.6, r * 0.42)
			cand.append([l.global_position + l.global_transform.basis.z * rad, rad])
	cand.sort_custom(func(a, b): return (a[0] as Vector3).distance_squared_to(cp) < (b[0] as Vector3).distance_squared_to(cp))
	var arr := PackedVector4Array()
	for i in 8:
		if i < cand.size():
			var v: Vector3 = cand[i][0]
			arr.append(Vector4(v.x, v.y, v.z, float(cand[i][1])))
		else:
			arr.append(Vector4(0, -9999, 0, 0.01))
	for ly in rain_layers:
		(ly[1] as ShaderMaterial).set_shader_parameter("lights", arr)
	splash_mat.set_shader_parameter("lights", arr)


func _wet(wet: float) -> void:
	for w in wet_mats:
		var m: StandardMaterial3D = w[0]
		m.roughness = lerp(float(w[1]), float(w[1]) * 0.32, wet)
		m.albedo_color = (w[2] as Color) * lerp(1.0, 0.68, wet)
		m.albedo_color.a = (w[2] as Color).a
		m.metallic_specular = lerp(float(w[3]), 0.85, wet)


func _drops(n: int, seed_: int) -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for i in n:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	return mm


func _layer(code: String, mm: MultiMesh, params: Dictionary) -> Array:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	mi.visible = false
	add_child(mi)
	return [mi, m]


func _make_rain() -> void:
	# close: thin streaks; far: hair-thin, fainter, longer (further off they blur together into a grey veil)
	rain_layers.append(_layer(RAIN_SHADER, _drops(12000 if main.ultra else 6000, 7), {"box": Vector3(12, 10, 12), "len": 0.07, "width": 0.0005, "strength": 0.3, "near_cut": 1.5}))
	rain_layers.append(_layer(RAIN_SHADER, _drops(7000 if main.ultra else 3500, 11), {"box": Vector3(36, 20, 36), "len": 0.14, "width": 0.0008, "strength": 0.17, "near_cut": 5.0}))
	_make_puddles()
	var sl := _layer(SPLASH_SHADER, _drops(2000 if main.ultra else 1000, 13), {"box": Vector2(14, 14)})
	splash_mi = sl[0]
	splash_mat = sl[1]
	fog_d = main.world_env.fog_density
	fog_c = main.world_env.fog_light_color
	sat0 = main.world_env.adjustment_saturation
	con0 = main.world_env.adjustment_contrast
	sky_fog0 = main.world_env.fog_sky_affect
	# the streets and pavements get wet: darker and shinier, the lamps glinting in them
	var c = main.mission.get("city") if main.mission else null
	if c != null:
		for k in c.mats:
			var m = c.mats[k]
			if m is StandardMaterial3D and (str(k).begins_with("g_") or str(k) in ["k_base", "dark", "panel"]):
				wet_mats.append([m, m.roughness, m.albedo_color, m.metallic_specular])


# ---- ripples on the puddles (the ripple picture: VRA, CC BY 4.0) ----
const PUDDLE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D patches : filter_linear_mipmap, repeat_enable;
uniform float wet = 0.0;
uniform float rain = 0.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wp.xz;
	// pools where the road dips: patches from a noise, growing as it gets wetter
	float n = texture(patches, p * 0.045).r * 0.7 + texture(patches, p * 0.13 + 0.37).r * 0.3;
	float mask = smoothstep(0.66 - wet * 0.08, 0.71 - wet * 0.08, n) * wet;
	// the rain stirring them: the ripple picture twice, drifting different ways
	vec3 a = texture(ripples, p * 0.55 + vec2(TIME * 0.031, TIME * 0.047)).rgb;
	vec3 b = texture(ripples, p * 0.41 + vec2(-TIME * 0.043, TIME * 0.022) + 0.5).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), normalize(a + b - 1.0) * 0.5 + 0.5, 0.35 + 0.65 * rain);
	NORMAL_MAP_DEPTH = 1.0;
	// still water: a little darker than the wet road round it, a sharp shine where a lamp is caught
	ALBEDO = vec3(0.03, 0.032, 0.038);
	ROUGHNESS = 0.16;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = mask * 0.5;
}
"""


var puddle: MeshInstance3D
var puddle_mat: ShaderMaterial


func _make_puddles() -> void:
	var sh := Shader.new()
	sh.code = PUDDLE_SHADER
	puddle_mat = ShaderMaterial.new()
	puddle_mat.shader = sh
	puddle_mat.set_shader_parameter("ripples", load("res://assets/fx/rain_ripples.png"))
	puddle_mat.set_shader_parameter("patches", load("res://assets/sky/clouds.png"))
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	puddle = MeshInstance3D.new()
	puddle.mesh = pm
	puddle.material_override = puddle_mat
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.visible = false
	add_child(puddle)


func _make_sound() -> void:
	rain_snd = AudioStreamPlayer.new()
	var rs: AudioStream = load("res://assets/sfx/rain_loop.ogg")
	if rs is AudioStreamOggVorbis:
		(rs as AudioStreamOggVorbis).loop = true
	rain_snd.stream = rs
	rain_snd.volume_db = -60.0
	add_child(rain_snd)
	for i in 4:
		thunders.append(load("res://assets/sfx/thunder_%d.ogg" % i))
		thunders_far.append(load("res://assets/sfx/thunder_far_%d.ogg" % i))
	thunder_snd = AudioStreamPlayer.new()
	add_child(thunder_snd)


# =============== the lamps ===============
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;
uniform float strength = 0.16;
void fragment() {
	float edge = pow(clamp(abs(dot(normalize(NORMAL), VIEW)), 0.0, 1.0), 1.6);
	float fade = pow(1.0 - UV.y, 2.2);
	ALBEDO = vec3(1.0, 0.92, 0.75) * strength * edge * fade;
}
"""


## A soft glow facing the camera; it grows with distance so a lamp is still seen far off.
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;
uniform vec3 tint : source_color = vec3(1.0, 0.86, 0.62);
uniform float strength = 1.0;
void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float grow = clamp(distance(centre, cam) * 0.04, 1.0, 2.6);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * grow, INV_VIEW_MATRIX[1] * grow, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float k = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = tint * strength * (k * 1.4 + pow(clamp(1.0 - d * 3.0, 0.0, 1.0), 2.0) * 2.0);
}
"""


func _make_lamp_parts() -> void:
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = sh
	bulb_mat = StandardMaterial3D.new()
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb_mat.albedo_color = Color(1.0, 0.96, 0.85)
	var gs := Shader.new()
	gs.code = GLOW_SHADER
	glow_mat = ShaderMaterial.new()
	glow_mat.shader = gs


## A lamp: a bright bulb, a soft glow round it seen from afar, and (beam) a faint cone of light in the damp air.
func _lamp(parent: Node3D, beam: bool, glow_size := 0.32) -> Node3D:
	var l := Node3D.new()
	parent.add_child(l)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	sm.radial_segments = 6
	sm.rings = 3
	bulb.mesh = sm
	bulb.material_override = bulb_mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.add_child(bulb)
	var g := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(glow_size, glow_size)
	g.mesh = gq
	g.material_override = glow_mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position = Vector3(0, 0, 0.07)        # (in front of the lamp, not inside his head)
	l.add_child(g)
	if beam:
		var b := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 1.1
		cm.height = 7.0
		cm.radial_segments = 10
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		b.mesh = cm
		b.material_override = beam_mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the cone's axis along the lamp's +z (forward of the head), its narrow end at the lamp
		b.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 3.5))
		b.visibility_range_end = 90.0
		# (in a holder at the lamp: shortened, as a whole, to stop at the first wall in its way)
		var bp := Node3D.new()
		bp.name = "beam"
		l.add_child(bp)
		bp.add_child(b)
	return l


func _lamp_all() -> void:
	for e in main.enemies:
		if lamped.has(e) or e.dead:
			continue
		# a light on his rifle, under the muzzle: it shines where the barrel points (down at the ground with the
		# rifle lowered, at what he aims at with it raised); placed from the muzzle each frame
		var l := _lamp(e, true, 0.34)
		l.top_level = true
		lamped[e] = l


## A lamp hung over each guard up on a tower or a roof.
func _tower_lamps() -> void:
	for e in main.enemies:
		if not e.perch:
			continue
		var back := Vector3(sin(e.home_yaw), 0, cos(e.home_yaw))      # behind him (he faces -z turned by yaw)
		var at: Vector3 = e.home + back * 0.9 + Vector3(0, 2.5, 0)
		var holder := Node3D.new()
		add_child(holder)
		holder.global_position = at
		tower_spots.append(at)
		_lamp(holder, false, 0.9)
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.78, 0.5)
		o.light_energy = 2.2
		o.omni_range = 8.0
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		holder.add_child(o)
		main.lamp_can_break(at, [holder], 0.5)


func _process(dt: float) -> void:
	if main == null:
		return
	t += dt
	_weather(dt)
	_lamps(dt)


func _lamps(dt: float) -> void:
	check_t -= dt
	if check_t <= 0.0:
		check_t = 1.0
		_lamp_all()
	var me: Vector3 = main.player.global_position
	var space := get_world_3d().direct_space_state
	var near := []
	for e in lamped:
		var l: Node3D = lamped[e]
		if not is_instance_valid(l):
			continue
		if e.dead:
			l.visible = false
			continue
		var gun_on: bool = e.rig["guns"][e.gun].visible
		l.visible = gun_on
		if not gun_on:
			reach_of[l] = 0.0
			continue
		var mz: Node3D = e.muzzle
		var look: Vector3 = (mz.global_transform.basis.z as Vector3).normalized()
		var lp: Vector3 = mz.global_position - look * 0.28 + Vector3(0, -0.035, 0)
		l.global_transform = Transform3D(Basis.looking_at(-look), lp)
		var d: float = e.global_position.distance_to(me)
		# the light stops at the first wall: the beam no further, and (spot) nothing lit on the far side of it
		var reach := 7.0
		if d < 70.0:
			var q := PhysicsRayQueryParameters3D.create(lp, lp + look * 7.0)
			q.collision_mask = 1
			q.exclude = [e.get_rid()]
			var h := space.intersect_ray(q)
			if not h.is_empty():
				reach = max(0.15, lp.distance_to(h["position"]))
			(l.get_node("beam") as Node3D).scale = Vector3.ONE * (reach / 7.0)
		reach_of[l] = reach
		if d < 45.0:
			near.append([d, l])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in spots.size():
		var s: SpotLight3D = spots[i]
		if i < near.size():
			var l: Node3D = near[i][1]
			s.visible = true
			s.spot_range = float(reach_of.get(l, 7.0)) + 0.12 if float(reach_of.get(l, 7.0)) < 6.9 else 17.0
			# the light shines down its -z; the lamp looks along its +z
			s.global_transform = l.global_transform.orthonormalized() * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		else:
			s.visible = false


# =============== the weather ===============
func _weather(dt: float) -> void:
	var mt: float = t
	cover = lerp(CLOUD_START, CLOUD_FULL, clamp(mt / THICKEN_T, 0.0, 1.0))
	var want_rain: float = clamp((mt - RAIN_T) / RAIN_RAMP, 0.0, 1.0)
	rain = want_rain
	drift += Vector2(0.004, 0.0015) * dt * (1.0 + cover)
	# under a roof the rain is not seen falling (it is still heard)
	roof_t -= dt
	if roof_t <= 0.0 and rain > 0.0:
		roof_t = 0.4
		var cam := get_viewport().get_camera_3d()
		if cam:
			# a roof: something overhead here and a little way off each side (not just a sign or an awning)
			var hits := 0
			for off in [Vector3.ZERO, Vector3(1.6, 0, 0.9), Vector3(-1.4, 0, -1.2)]:
				var from: Vector3 = cam.global_position + off
				var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 25, 0))
				q.collision_mask = 1
				if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					hits += 1
			indoors = 1.0 if hits == 3 else 0.0
	# lightning: now and then once the clouds are thick, more often in the rain
	if mt > next_bolt and cover > 0.5:
		_bolt()
		next_bolt = mt + (randf_range(14.0, 30.0) if rain > 0.3 else randf_range(18.0, 28.0))
	flash = 0.0
	var keep := []
	for p in flash_seq:
		var age: float = mt - float(p[0])
		if age < 0.0:
			keep.append(p)
		elif age < 0.22:
			flash = max(flash, float(p[1]) * (1.0 - age / 0.22))
			keep.append(p)
	flash_seq = keep
	sky_mat.set_shader_parameter("cover", cover)
	sky_mat.set_shader_parameter("flash", flash)
	sky_mat.set_shader_parameter("drift", drift)
	# the wind comes in gusts
	wind = Vector2(0.35, 0.15) * (0.7 + 0.45 * sin(mt * 0.37) + 0.25 * sin(mt * 1.31 + 1.0))
	var show_rain: bool = rain > 0.0 and indoors < 0.5
	for ly in rain_layers:
		(ly[0] as Node3D).visible = show_rain
		(ly[1] as ShaderMaterial).set_shader_parameter("amount", rain)
		(ly[1] as ShaderMaterial).set_shader_parameter("flash", flash)
		(ly[1] as ShaderMaterial).set_shader_parameter("wind", wind)
	splash_mi.visible = show_rain
	var camn := get_viewport().get_camera_3d()
	if camn:
		var cp := camn.global_position
		# the puddles lie in the road (the town's paving, a few centimetres up): pavements and kerbs stand out of them
		var gh: float = main.ground_height(cp.x, cp.z)
		puddle.visible = last_wet > 0.02 and indoors < 0.5 and abs(gh) < 0.1
		puddle.global_position = Vector3(snappedf(cp.x, 1.0), 0.03, snappedf(cp.z, 1.0))
		puddle_mat.set_shader_parameter("wet", last_wet)
		puddle_mat.set_shader_parameter("rain", rain)
	light_t -= dt
	if show_rain and light_t <= 0.0:
		light_t = 0.2
		_rain_lights()
	splash_mat.set_shader_parameter("amount", rain)
	splash_mat.set_shader_parameter("flash", flash)
	splash_mat.set_shader_parameter("floor_y", main.player.global_position.y + 0.025)
	# wet ground, and the rain's haze hiding what is far off
	var wet: float = clamp((mt - RAIN_T - 5.0) / 40.0, 0.0, 1.0)
	if abs(wet - last_wet) > 0.02 or (wet == 1.0 and last_wet != 1.0):
		last_wet = wet
		_wet(wet)
	# the look of a wet night: as the clouds close in and the rain comes the colours go dull and cold, the far
	# streets sink into a dark blue-grey haze (not a white one) and the sky hazes over
	# (it follows the clouds: a little duller with every cloud, the full rainy look by the time the rain falls)
	var mood: float = max(rain, clamp((cover - CLOUD_START) / (CLOUD_FULL - CLOUD_START), 0.0, 1.0))
	main.world_env.fog_density = fog_d + 0.02 * mood
	main.world_env.fog_light_color = fog_c.lerp(Color(0.075, 0.085, 0.105), mood) + Color(0.5, 0.55, 0.65) * flash * 0.12
	main.world_env.fog_sky_affect = lerp(sky_fog0, 0.85, mood)
	main.world_env.adjustment_saturation = sat0 * (1.0 - 0.4 * mood)
	main.world_env.adjustment_contrast = con0 * (1.0 - 0.1 * mood)
	# the town lit up by the stroke
	main.sun.light_energy = sun_e + flash * 1.1
	main.world_env.ambient_light_energy = amb_e * (1.0 - 0.15 * cover) + flash * 0.35
	# rain heard: fades in with the rain (quieter indoors)
	if rain > 0.0 and not rain_snd.playing:
		rain_snd.play(randf() * 60.0)
	if rain_snd.playing:
		# heard as it is seen: the same amount drives the drops falling and the sound (a few drops, a whisper;
		# a downpour, the full recording)
		var lin: float = rain * 0.6 * (0.55 if indoors > 0.5 else 1.0)    # (a light rain)
		rain_snd.volume_db = lerp(rain_snd.volume_db, linear_to_db(max(lin, 0.0005)) + 2.0, min(1.0, dt * 2.0))


## A stroke: two or three quick flickers, and its thunder a moment later (later the further off it fell).
func _bolt() -> void:
	# before the rain the storm is still far off: a weaker glow in the clouds, a long wait, a low rumble with no
	# rain in it; once it rains, close strokes, bright, the clap soon after
	var near := rain > 0.3
	var s: float = randf_range(0.6, 1.0) if near else randf_range(0.3, 0.5)
	flash_seq.append([t, s])
	flash_seq.append([t + randf_range(0.09, 0.14), s * randf_range(0.5, 0.9)])
	if randf() < 0.6:
		flash_seq.append([t + randf_range(0.25, 0.4), s * randf_range(0.3, 0.7)])
	var delay: float = randf_range(0.4, 2.8) if near else randf_range(3.0, 5.5)
	get_tree().create_timer(delay).timeout.connect(func():
		thunder_snd.stream = thunders[randi() % thunders.size()] if near else thunders_far[randi() % thunders_far.size()]
		thunder_snd.volume_db = (-4.0 - delay * 2.5) if near else -9.0
		thunder_snd.play())
