extends Node3D
## Mission 2 at night: the militia wear head lamps and the tower posts have a lamp, so they can be seen in the dark;
## and the weather turns: a few clouds at first, more and more, then rain, with lightning and thunder.

var main: Node
var t := 0.0

# ---- weather timeline (seconds from the start of the mission) ----
const CLOUD_START := 0.36       # how much of the sky is cloud at the start
const CLOUD_FULL := 0.92        # and when it is about to rain
const THICKEN_T := 75.0         # clouds grow over this long
const RAIN_T := 70.0            # then the rain begins
const RAIN_RAMP := 25.0         # and gets heavy over this long

var sky_mat: ShaderMaterial
var rain_mi: MultiMeshInstance3D
var rain_mat: ShaderMaterial
var rain_snd: AudioStreamPlayer
var thunders: Array = []
var thunder_snd: AudioStreamPlayer
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
	for i in SPOTS:
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
	next_bolt = RAIN_T - 12.0


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
		vec3 cc = mix(vec3(0.07, 0.075, 0.095), vec3(0.2, 0.155, 0.125), low) * (0.7 + 0.6 * n);
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
const RAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords, blend_mix;
uniform float amount = 0.0;
uniform vec3 box = vec3(26.0, 16.0, 26.0);
uniform float speed = 12.0;
uniform float flash = 0.0;
uniform vec2 wind = vec2(0.6, 0.25);
varying float vis;
varying float along;

void vertex() {
	vec4 r = INSTANCE_CUSTOM;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 base = r.xyz * box;
	float fall = TIME * speed * (0.85 + 0.3 * r.w);
	vec3 w;
	w.y = cam.y - box.y * 0.45 + mod(base.y - fall, box.y);
	vec2 sway = wind * (fall / speed);
	w.x = cam.x + mod(base.x + sway.x - cam.x, box.x) - box.x * 0.5;
	w.z = cam.z + mod(base.z + sway.y - cam.z, box.z) - box.z * 0.5;
	vec3 to = vec3(cam.x - w.x, 0.0, cam.z - w.z);
	float dist = length(to);
	to = to / max(dist, 0.001);
	vec3 side = vec3(to.z, 0.0, -to.x);
	float len = 0.55;
	vec3 down = normalize(vec3(-wind.x * 0.06, -1.0, -wind.y * 0.06));
	VERTEX = w + side * VERTEX.x * (0.010 + dist * 0.0012) - down * VERTEX.y * len;
	along = UV.y;
	vis = step(r.w, amount) * (1.0 - smoothstep(box.x * 0.3, box.x * 0.5, dist)) * smoothstep(0.4, 1.4, dist);
}

void fragment() {
	float a = vis * (1.0 - abs(along * 2.0 - 1.0));
	ALBEDO = vec3(0.62, 0.66, 0.74) + flash * vec3(0.6);
	ALPHA = a * (0.16 + flash * 0.25);
}
"""


func _make_rain() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	var n := 1800
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var sh := Shader.new()
	sh.code = RAIN_SHADER
	rain_mat = ShaderMaterial.new()
	rain_mat.shader = sh
	rain_mat.set_shader_parameter("amount", 0.0)
	rain_mi = MultiMeshInstance3D.new()
	rain_mi.multimesh = mm
	rain_mi.material_override = rain_mat
	rain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_mi.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	rain_mi.visible = false
	add_child(rain_mi)


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
	float grow = clamp(distance(centre, cam) * 0.045, 1.0, 3.5);
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
		cm.bottom_radius = 1.5
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
		l.add_child(b)
	return l


func _lamp_all() -> void:
	for e in main.enemies:
		if lamped.has(e) or e.dead:
			continue
		var at := BoneAttachment3D.new()
		at.bone_name = "mixamorigHead"
		e.skel.add_child(at)
		# on the forehead, looking where he looks and a little down
		# (the bone carries the model's scale: the lamp keeps its own size and is placed from the bone each frame)
		var l := _lamp(at, true, 0.42)
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
		_lamp(holder, false, 0.9)
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.78, 0.5)
		o.light_energy = 2.2
		o.omni_range = 8.0
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		holder.add_child(o)


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
	var near := []
	for e in lamped:
		var l: Node3D = lamped[e]
		if not is_instance_valid(l):
			continue
		if e.dead:
			l.visible = false
			continue
		# on his forehead, looking the way he faces and a little down (the head bone's own axes are not the same in
		# every model)
		var head: Vector3 = (l.get_parent() as Node3D).global_position
		var f: Vector3 = -(e.global_transform.basis.z as Vector3)
		f.y = 0.0
		f = f.normalized()
		var look := (f + Vector3(0, -0.17, 0)).normalized()
		l.global_transform = Transform3D(Basis.looking_at(-look), head + Vector3(0, 0.12, 0) + f * 0.12)
		var d: float = e.global_position.distance_to(me)
		if d < 45.0:
			near.append([d, l])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in spots.size():
		var s: SpotLight3D = spots[i]
		if i < near.size():
			var l: Node3D = near[i][1]
			s.visible = true
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
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + Vector3(0, 25, 0))
			q.collision_mask = 1
			indoors = 1.0 if not get_world_3d().direct_space_state.intersect_ray(q).is_empty() else 0.0
	# lightning: now and then once the clouds are thick, more often in the rain
	if mt > next_bolt and cover > 0.6:
		_bolt()
		next_bolt = mt + (randf_range(14.0, 30.0) if rain > 0.3 else randf_range(22.0, 40.0))
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
	rain_mi.visible = rain > 0.0 and indoors < 0.5
	rain_mat.set_shader_parameter("amount", rain)
	rain_mat.set_shader_parameter("flash", flash)
	# the town lit up by the stroke
	main.sun.light_energy = sun_e + flash * 1.8
	main.world_env.ambient_light_energy = amb_e * (1.0 - 0.15 * cover) + flash * 0.6
	# rain heard: fades in with the rain (quieter indoors)
	if rain > 0.0 and not rain_snd.playing:
		rain_snd.play(randf() * 60.0)
	if rain_snd.playing:
		var lin: float = rain * (0.55 if indoors > 0.5 else 1.0)
		rain_snd.volume_db = lerp(rain_snd.volume_db, linear_to_db(max(lin, 0.0005)) + 2.0, min(1.0, dt * 2.0))


## A stroke: two or three quick flickers, and its thunder a moment later (later the further off it fell).
func _bolt() -> void:
	var s: float = randf_range(0.6, 1.0)
	flash_seq.append([t, s])
	flash_seq.append([t + randf_range(0.09, 0.14), s * randf_range(0.5, 0.9)])
	if randf() < 0.6:
		flash_seq.append([t + randf_range(0.25, 0.4), s * randf_range(0.3, 0.7)])
	var delay: float = randf_range(0.4, 2.8)
	get_tree().create_timer(delay).timeout.connect(func():
		thunder_snd.stream = thunders[randi() % thunders.size()]
		thunder_snd.volume_db = -4.0 - delay * 2.5
		thunder_snd.play())
