extends CharacterBody3D
## Kestrel: third-person soldier. Mixamo clips from soldier.glb drive the body through an AnimationTree
## (one direction clip at a time with a short crossfade, aim/reload on the upper body while moving).
## The rifle sits in the right hand exactly as in the aim pose; the left hand is pinned to the handguard by IK.

const WALK := 1.2
const WALK_BACK := 1.1
const RUN := 3.6
const RUN_SIDE := 3.2
const RUN_BACK := 2.6
const CROUCH := 1.1
const CROUCH_RUN := 1.6
const AIM_WALK := 1.2
const JUMP_V := 4.6
const GRAVITY := 12.0

# natural speed (m/s) of each clip, measured from its root motion
const NAT := {"walk": 1.0, "walkBack": 1.1, "walkR": 1.92, "walkL": 1.9, "run": 3.16, "runBack": 2.59,
	"runStrafeR": 3.31, "runStrafeL": 2.83, "crouchWalk2": 1.22, "crouchBack": 1.23, "crouchRun": 1.3}
const STATES := {"idle": "idle", "aim": "aim", "kneel": "kneel", "kneel_aim": "crouchFire", "jump": "jump",
	"walk": "walk", "walk_b": "walkBack", "walk_r": "walkR", "walk_l": "walkL",
	"run": "run", "run_b": "runBack", "run_r": "runStrafeR", "run_l": "runStrafeL",
	"c_walk": "crouchWalk2", "c_back": "crouchBack", "c_run": "crouchRun", "c_r": "crouchWalk2", "c_l": "crouchWalk2"}
const UPPER := ["mixamorigSpine", "mixamorigSpine1", "mixamorigSpine2", "mixamorigNeck", "mixamorigHead",
	"mixamorigLeftShoulder", "mixamorigLeftArm", "mixamorigLeftForeArm", "mixamorigLeftHand",
	"mixamorigRightShoulder", "mixamorigRightArm", "mixamorigRightForeArm", "mixamorigRightHand"]

var weapons := [
	{"name": "SD-9 PISTOL", "gun": "pistol", "mag": 12, "size": 12, "res": 48, "dmg": 42, "rate": 0.26, "spread": 0.006, "auto": false, "kick": 0.9},
	{"name": "M4A1 CARBINE", "gun": "m4", "mag": 30, "size": 30, "res": 90, "dmg": 34, "rate": 0.085, "spread": 0.014, "auto": true, "kick": 1.0},
	{"name": "AK-47", "gun": "ak", "mag": 30, "size": 30, "res": 90, "dmg": 41, "rate": 0.105, "spread": 0.021, "auto": true, "kick": 1.45},
]
var wi := 2

# input (set by the touch UI or the keyboard)
var move_in := Vector2.ZERO        # x right, y forward, length 0..1
var run_in := false
var firing := false
var aiming := false
var crouch := false
var view := 0                      # 0 close, 1 closer, 2 first person

var yaw := 0.0
var pitch := -0.05
var vel := Vector3.ZERO
var speed := 0.0
var last_shot := -99.0
var reloading := 0.0
var switching := 0.0
var t := 0.0
var recoil := 0.0
var kick_p := 0.0
var shake := 0.0

var model: Node3D
var skel: Skeleton3D
var ap: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var guns := {}
var muzzles := {}
var ik: SkeletonIK3D
var ik_w := 1.0
var up_w := 0.0
var rl_w := 0.0
var state := "idle"
var dir := "F"
var head_bone := -1

var cam_pivot: Node3D
var cam_arm: SpringArm3D
var cam: Camera3D
var cam_len := 2.0
var cam_side := 0.5
var cam_h := 1.55
var fx: Node        # effects/world helper (main.gd)
var snd: Node       # sound helper (main.gd)

var stride_t := 0.0


func setup(fx_node: Node, snd_node: Node) -> void:
	fx = fx_node
	snd = snd_node
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	cs.name = "Body"
	add_child(cs)
	floor_snap_length = 0.3
	_build_model()
	_build_camera()


func _build_model() -> void:
	var sc: Node3D = load("res://assets/soldier.glb").instantiate()
	model = sc
	add_child(sc)
	ap = sc.find_child("AnimationPlayer", true, false)
	for n in sc.find_children("*", "Skeleton3D", true, false):
		skel = n
	# size to 1.80 m and face -Z (Mixamo characters face +Z)
	var lo := INF
	var hi := -INF
	for m in sc.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = m.global_transform * m.get_aabb()
		lo = min(lo, bb.position.y)
		hi = max(hi, bb.end.y)
	var s = 1.8 / max(0.01, hi - lo)
	sc.scale = Vector3.ONE * s
	sc.rotation.y = PI
	for m in sc.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat = m.get_active_material(0)
		if mat is StandardMaterial3D:
			var mm: StandardMaterial3D = mat.duplicate()
			mm.albedo_color = Color(1, 1, 1)
			mm.roughness = 0.9
			mm.metallic = 0.0
			m.material_override = mm
	head_bone = skel.find_bone("mixamorigHead")
	_fix_fingers()
	for n in ["idle", "aim", "kneel", "crouchFire", "walk", "walkBack", "walkR", "walkL", "run", "runBack", "runStrafeR", "runStrafeL", "crouchWalk2", "crouchBack", "crouchRun", "reload"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_calibrate_and_attach()
	_build_tree()


## The clips leave the fingers out; take the finger pose from the "fingers" clip and add it to every clip.
func _fix_fingers() -> void:
	if not ap.has_animation("fingers"):
		return
	var fa: Animation = ap.get_animation("fingers")
	for name in ap.get_animation_list():
		if name == "fingers":
			continue
		var a: Animation = ap.get_animation(name)
		for i in fa.get_track_count():
			if fa.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var p: NodePath = fa.track_get_path(i)
			if a.find_track(p, Animation.TYPE_ROTATION_3D) != -1:
				continue
			var k := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(k, p)
			a.rotation_track_insert_key(k, 0.0, fa.rotation_track_interpolate(i, 0.0))


## Measure the grip in the aim pose: gun along right hand -> left hand, left hand target on the handguard.
func _calibrate_and_attach() -> void:
	ap.play("aim")
	ap.seek(0.6, true)
	skel.force_update_all_bone_transforms()
	var rh := skel.find_bone("mixamorigRightHand")
	var lh := skel.find_bone("mixamorigLeftHand")
	var le := skel.find_bone("mixamorigLeftForeArm")
	var sg := skel.global_transform
	var hand_w: Transform3D = sg * skel.get_bone_global_pose(rh)
	var lhand_w: Transform3D = sg * skel.get_bone_global_pose(lh)
	var pr := hand_w.origin
	var pl := lhand_w.origin
	var barrel := (pl - pr).normalized()
	var gun_basis := Basis.looking_at(barrel, Vector3.UP, true)   # +Z of the gun along the barrel
	var gp := pr - barrel * 0.02 - Vector3.UP * 0.025
	var gun_w := Transform3D(gun_basis, gp)
	var local_in_hand := hand_w.affine_inverse() * gun_w
	var lh_in_gun := gun_w.affine_inverse() * lhand_w
	var elbow_skel: Vector3 = skel.get_bone_global_pose(le).origin
	ap.stop()

	var att := BoneAttachment3D.new()
	att.bone_name = "mixamorigRightHand"
	skel.add_child(att)
	for k in ["pistol", "m4", "ak"]:
		var g: Node3D = load("res://assets/guns/%s.glb" % k).instantiate()
		g.transform = local_in_hand
		att.add_child(g)
		for m in g.find_children("*", "MeshInstance3D", true, false):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mz := g.find_child("muzzle", true, false)
		if mz == null:
			mz = Node3D.new()
			g.add_child(mz)
			mz.position = Vector3(0, 0.03, 0.7 if k != "pistol" else 0.3)
		var tgt := Marker3D.new()
		tgt.name = "LeftGrip"
		tgt.transform = lh_in_gun
		g.add_child(tgt)
		guns[k] = g
		muzzles[k] = mz
		g.visible = false

	ik = SkeletonIK3D.new()
	ik.root_bone = "mixamorigLeftArm"
	ik.tip_bone = "mixamorigLeftHand"
	ik.override_tip_basis = true
	ik.use_magnet = true
	ik.magnet = elbow_skel + Vector3(0, -15, 0)
	skel.add_child(ik)
	_select_gun()
	ik.start()


func _select_gun() -> void:
	var k: String = weapons[wi]["gun"]
	for g in guns:
		guns[g].visible = g == k
	ik.target_node = ik.get_path_to(guns[k].get_node("LeftGrip"))


func _build_tree() -> void:
	tree = AnimationTree.new()
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	var bt := AnimationNodeBlendTree.new()
	var sm := AnimationNodeStateMachine.new()
	for st in STATES:
		var an := AnimationNodeAnimation.new()
		an.animation = STATES[st]
		sm.add_node(st, an)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", "idle", start)
	for a in STATES:
		for b in STATES:
			if a == b:
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = 0.12 if b == "jump" else 0.22
			tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			sm.add_transition(a, b, tr)
	bt.add_node("loco", sm)
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("speed", ts)
	bt.connect_node("speed", 0, "loco")
	var aim := AnimationNodeAnimation.new()
	aim.animation = "aim"
	bt.add_node("aim_up", aim)
	var rl := AnimationNodeAnimation.new()
	rl.animation = "reload"
	bt.add_node("reload_up", rl)
	var seek := AnimationNodeTimeSeek.new()
	bt.add_node("rseek", seek)
	bt.connect_node("rseek", 0, "reload_up")
	var rts := AnimationNodeTimeScale.new()
	bt.add_node("rspeed", rts)
	bt.connect_node("rspeed", 0, "rseek")
	var pick := AnimationNodeBlend2.new()
	bt.add_node("pick", pick)
	bt.connect_node("pick", 0, "aim_up")
	bt.connect_node("pick", 1, "rspeed")
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	var sp: String = str(model.get_path_to(skel))
	for b in UPPER:
		upper.set_filter_path(NodePath(sp + ":" + b), true)
	bt.add_node("upper", upper)
	bt.connect_node("upper", 0, "speed")
	bt.connect_node("upper", 1, "pick")
	bt.connect_node("output", 0, "upper")
	tree.tree_root = bt
	tree.active = true
	playback = tree.get("parameters/loco/playback")
	tree.set("parameters/rspeed/scale", 1.4)


func _build_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	var side := Node3D.new()
	side.name = "Side"
	cam_pivot.add_child(side)
	cam_arm = SpringArm3D.new()
	cam_arm.margin = 0.2
	cam_arm.collision_mask = 1
	var sph := SphereShape3D.new()
	sph.radius = 0.15
	cam_arm.shape = sph
	cam_arm.add_excluded_object(get_rid())
	side.add_child(cam_arm)
	cam = Camera3D.new()
	cam.fov = 62
	cam.near = 0.05
	cam.far = 900
	cam_arm.add_child(cam)
	cam.current = true


func look(dx: float, dy: float) -> void:
	var s := 0.0042 * (0.55 if aiming else 1.0)
	yaw -= dx * s
	pitch = clamp(pitch - dy * s, -1.2, 1.1)


func toggle_crouch() -> void:
	crouch = not crouch


func jump() -> void:
	if is_on_floor() and not crouch:
		vel.y = JUMP_V


func swap() -> void:
	if reloading > 0 or switching > 0:
		return
	wi = (wi + 1) % weapons.size()
	switching = 0.4
	snd.stop_auto()
	_select_gun()


func reload() -> void:
	var w: Dictionary = weapons[wi]
	if reloading > 0 or w["mag"] == w["size"] or w["res"] <= 0:
		return
	reloading = 1.6
	snd.stop_auto()
	snd.reload(w["gun"])
	tree.set("parameters/rseek/seek_request", 0.0)


func cycle_view() -> void:
	view = (view + 1) % 3


func _physics_process(dt: float) -> void:
	t += dt
	var w: Dictionary = weapons[wi]
	# ---- movement: camera-relative, speeds that match the clips ----
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var m := move_in
	var mag: float = min(1.0, m.length())
	var target := Vector3.ZERO
	if mag > 0.12:
		var md := (fwd * m.y + right * m.x).normalized()
		var fw := m.normalized().y
		var running := (run_in or mag > 0.88) and not crouch and not aiming
		var spd: float
		if crouch:
			spd = CROUCH_RUN if mag > 0.88 else CROUCH
		elif running:
			spd = RUN_BACK if fw < -0.3 else (RUN_SIDE if fw < 0.5 else RUN)
		else:
			spd = WALK_BACK if fw < -0.3 else WALK
		if aiming:
			spd = min(spd, AIM_WALK)
		target = md * spd
	var accel := 5.0 if target.length() > Vector2(vel.x, vel.z).length() else 9.0
	var hv := Vector3(vel.x, 0, vel.z).lerp(target, min(1.0, dt * accel))
	if hv.length() < 0.02:
		hv = Vector3.ZERO
	vel.x = hv.x
	vel.z = hv.z
	if is_on_floor():
		if vel.y < 0:
			vel.y = 0
	else:
		vel.y -= GRAVITY * dt
	velocity = vel
	move_and_slide()
	vel = velocity
	speed = Vector2(vel.x, vel.z).length()
	rotation.y = yaw

	# ---- weapons ----
	switching = max(0.0, switching - dt)
	if reloading > 0:
		reloading -= dt
		if reloading <= 0:
			var n: int = min(w["size"] - w["mag"], w["res"])
			w["mag"] += n
			w["res"] -= n
	if firing and (w["auto"] or t - last_shot > 0.35):
		_fire()
	if not firing or reloading > 0 or switching > 0 or w["mag"] <= 0:
		snd.stop_auto()
	recoil = max(0.0, recoil - dt * 7.0)
	kick_p *= exp(-dt * 13.0)
	shake = max(0.0, shake - dt * 0.8)

	_animate(dt)
	_update_camera(dt)
	_footsteps(dt)


func _fire() -> void:
	var w: Dictionary = weapons[wi]
	if reloading > 0 or switching > 0:
		return
	if w.has("last") and t - w["last"] < w["rate"]:
		return
	if w["mag"] <= 0:
		reload()
		return
	w["last"] = t
	w["mag"] -= 1
	last_shot = t
	var kk: float = w["kick"] * (0.65 if aiming else 1.0) * (0.75 if crouch else 1.0)
	recoil = min(recoil + (0.45 if w["auto"] else 0.8) * kk, 1.6)
	pitch = clamp(pitch + (0.006 if w["auto"] else 0.012) * kk, -1.2, 1.1)
	yaw += randf_range(-0.003, 0.003) * kk
	kick_p += 0.007 * kk
	if w["auto"]:
		snd.start_auto(w["gun"])
	else:
		snd.pistol()
	# the shot goes through the crosshair (centre of the camera)
	var sp: float = w["spread"] * (1.5 if speed > 2.6 else (1.2 if speed > 0.5 else 1.0)) * (0.6 if crouch else 1.0) * (0.35 if aiming else 1.0) * (1.0 + recoil * 0.6)
	var from := cam.global_position
	var d := -cam.global_transform.basis.z
	d = (d + Vector3(randf_range(-sp, sp), randf_range(-sp, sp), randf_range(-sp, sp))).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + d * 400.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var mz: Node3D = muzzles[w["gun"]]
	var mp := mz.global_position
	fx.muzzle_flash(mp, d, w["gun"])
	if hit:
		fx.impact(hit.position, hit.normal, hit.collider)
		if w["auto"] and int(w["mag"]) % 3 == 0:
			fx.tracer(mp, hit.position)
	elif w["auto"] and int(w["mag"]) % 3 == 0:
		fx.tracer(mp, from + d * 120.0)


func _animate(dt: float) -> void:
	var w: Dictionary = weapons[wi]
	var aim_now := aiming or firing or t - last_shot < 2.5
	var moving := speed > 0.25
	var local := Vector2(vel.dot(Vector3(cos(yaw), 0, -sin(yaw))), vel.dot(Vector3(-sin(yaw), 0, -cos(yaw))))  # x right, y forward
	if moving:
		var fwd_axis := dir == "F" or dir == "B"
		var use_f = abs(local.y) >= abs(local.x) * 0.75 if fwd_axis else abs(local.y) > abs(local.x) * 1.35
		dir = (("F" if local.y >= 0 else "B") if use_f else ("R" if local.x >= 0 else "L"))
	var st := "idle"
	var nat := 0.0
	if not is_on_floor() and vel.y > 0.5:
		st = "jump"
	elif moving:
		var run := (speed > 1.35) if crouch else (speed > 2.4)
		if crouch:
			st = {"F": "c_run" if run else "c_walk", "B": "c_back", "R": "c_r", "L": "c_l"}[dir]
		else:
			st = {"F": "run" if run else "walk", "B": "run_b" if run else "walk_b", "R": "run_r" if run else "walk_r", "L": "run_l" if run else "walk_l"}[dir]
		nat = NAT.get(STATES[st], 1.0)
	elif crouch:
		st = "kneel_aim" if aim_now else "kneel"
	else:
		st = "aim" if aim_now else "idle"
	if st != state:
		playback.travel(st)
		state = st
	var scale := 1.0
	if nat > 0:
		scale = clamp(speed / nat, 0.6, 1.5)
	elif st == "kneel_aim":
		scale = 1.0 if (firing or t - last_shot < 0.3) else 0.0
	tree.set("parameters/speed/scale", scale)
	# arms and chest: aim pose (or reload) while the legs keep walking
	var want_up := 1.0 if (moving and (aim_now or reloading > 0) and st != "jump") else 0.0
	if reloading > 0 and not moving:
		want_up = 1.0
	up_w = lerp(up_w, want_up, min(1.0, dt * 9.0))
	rl_w = lerp(rl_w, 1.0 if reloading > 0 else 0.0, min(1.0, dt * 9.0))
	tree.set("parameters/upper/blend_amount", up_w)
	tree.set("parameters/pick/blend_amount", rl_w)
	# left hand on the handguard except while reloading or switching (and never for the one-handed pistol)
	var free = reloading > 0 or switching > 0 or w["gun"] == "pistol"
	ik_w = lerp(ik_w, 0.0 if free else 1.0, min(1.0, dt * 10.0))
	ik.interpolation = ik_w
	for g in guns:
		guns[g].visible = g == w["gun"] and switching < 0.2 and view != 2


func _update_camera(dt: float) -> void:
	var lens := [[2.0, 0.55, 1.6], [1.35, 0.45, 1.62], [0.0, 0.0, 1.62]]
	var cfg: Array = lens[view]
	var tl: float = cfg[0]
	var ts: float = cfg[1]
	var th: float = cfg[2]
	if crouch:
		th -= 0.5
	if aiming and view != 2:
		tl = 0.95
		ts = 0.42
		th += 0.02
	cam_len = lerp(cam_len, tl, min(1.0, dt * 10.0))
	cam_side = lerp(cam_side, ts, min(1.0, dt * 10.0))
	cam_h = lerp(cam_h, th, min(1.0, dt * 8.0))
	cam_pivot.global_position = global_position + Vector3(0, cam_h, 0)
	var shk := Vector2(sin(t * 37.0), sin(t * 53.0)) * shake * 0.05
	cam_pivot.rotation = Vector3(pitch + kick_p + shk.y, yaw + shk.x, 0)
	cam_pivot.get_node("Side").position = Vector3(cam_side, 0, 0)
	cam_arm.spring_length = cam_len
	var fov := 62.0
	if aiming:
		fov = 50.0
	elif speed > 3.0:
		fov = 66.0
	cam.fov = lerp(cam.fov, fov, min(1.0, dt * 10.0))
	model.visible = view != 2


func _footsteps(dt: float) -> void:
	if not is_on_floor() or speed < 0.3:
		return
	# two footfalls per clip cycle, at the speed the clip is playing
	var clip: String = STATES.get(state, "walk")
	var nat: float = NAT.get(clip, 1.0)
	var length := 1.0
	if ap.has_animation(clip):
		length = max(0.3, ap.get_animation(clip).length)
	stride_t += dt * 2.0 * clamp(speed / nat, 0.6, 1.5) / length
	if stride_t >= 1.0:
		stride_t -= 1.0
		snd.step(speed > 2.4, crouch)


func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z
