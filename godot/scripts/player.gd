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
	"c_walk": "crouchWalk2", "c_back": "crouchBack", "c_run": "crouchWalk2", "c_r": "crouchWalk2", "c_l": "crouchWalk2",
	"dead": "dieFront"}
# (the "crouchRun" clip has its hips 1.8 m behind the body, which put the soldier behind the camera: crouch-running
# plays the crouch walk faster instead)
const UPPER := ["mixamorigSpine", "mixamorigSpine1", "mixamorigSpine2", "mixamorigNeck", "mixamorigHead",
	"mixamorigLeftShoulder", "mixamorigLeftArm", "mixamorigLeftForeArm", "mixamorigLeftHand",
	"mixamorigRightShoulder", "mixamorigRightArm", "mixamorigRightForeArm", "mixamorigRightHand"]

# the gun models are built to real size (metres)
const GUN_SCALE := {"pistol": 1.0, "m4": 1.0, "ak": 1.0}
# left hand, in the gun's own units (x left, y up, z along the barrel): the way the palm faces (n), the way the
# fingers point (d), and either the knuckle joints (k) or where the palm presses (p). Rifles: palm up under the
# handguard, knuckles under its middle so the fingers wrap up round the far side. Pistol: palm over the right
# hand's fingers from the left, fingers forward and down.
const LEFT_HOLD := {
	"pistol": {"p": Vector3(0.04, -0.05, -0.005), "n": Vector3(-1.0, 0.35, 0.0), "d": Vector3(0.0, -0.5, 0.85)},
	"m4": {"k": Vector3(-0.006, 0.008, 0.24), "n": Vector3(-0.15, 1.0, 0.0), "d": Vector3(-1.0, 0.0, 0.3), "c": 0.86},
	"ak": {"k": Vector3(-0.01, -0.018, 0.26), "n": Vector3(-0.15, 1.0, 0.0), "d": Vector3(-1.0, 0.0, 0.3), "c": 0.9}}
const GRIP_DOWN := Vector3(0, -0.94, -0.34)   # down the pistol grip (same rake on all three)
# first person, aiming: eye on the sight line (AK irons, M4 through the red dot, pistol irons)
# first person: the point on each gun the eye looks along (gun units), and how far behind it the eye sits
const SIGHT := {"pistol": Vector3(0, 0.066, 0.0), "m4": Vector3(0, 0.127, 0.0), "ak": Vector3(0, 0.077, 0.19)}
const EYE_BACK := {"pistol": 0.24, "m4": 0.14, "ak": 0.4}
# finger curl (degrees) of segments 1..3: right hand round the pistol grip with the index on the trigger,
# left hand round the handguard
# (spread over the three joints: the glove mesh creases into spikes if one joint bends too far)
const CURL_R := {"Thumb": [14, 24, 20], "Index": [34, 34, 20], "Middle": [74, 62, 34], "Ring": [77, 64, 34], "Pinky": [80, 66, 34]}
const CURL_L := {"Thumb": [6, 12, 10], "Index": [50, 55, 32], "Middle": [52, 56, 34], "Ring": [54, 58, 34], "Pinky": [56, 60, 36]}
const CLOSE_FINGERS := 0.6   # how much of the rest pose's finger spread to take out

var weapons := [
	{"name": "SD-9 PISTOL", "gun": "pistol", "res0": 48, "mag": 12, "size": 12, "res": 48, "dmg": 42, "rate": 0.26, "spread": 0.006, "auto": false, "kick": 0.9},
	{"name": "M4A1 CARBINE", "gun": "m4", "res0": 90, "mag": 30, "size": 30, "res": 90, "dmg": 34, "rate": 0.085, "spread": 0.014, "auto": true, "kick": 1.0},
	{"name": "AK-47", "gun": "ak", "res0": 90, "mag": 30, "size": 30, "res": 90, "dmg": 41, "rate": 0.105, "spread": 0.021, "auto": true, "kick": 1.45},
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
var r_corr := Quaternion.IDENTITY   # right wrist turn that puts the grip square in the palm
var gun_in_hand_b := Basis()        # gun axes in the right hand's frame
var finger_set := []                # [bone, rest rotation, curl axis (bone space), angle]
var vm: Node3D                      # first person: a second soldier on the camera, arms and gun in view
var vm_rig := {}
var vm_muzzles := {}
var vm_ads := {}                    # per gun: rig offset that puts the sight on the eye line
var ads_k := 0.0
var holder_xf := {}                 # per gun: gun pose on the right hand bone
var left_xf := {}                   # per gun: left hand target on the gun
var ik_magnet := Vector3.ZERO
var model_scale := 1.0
var spawn := Vector3(0, 0.05, 6)
var main_data := {}                 # grip data of the player's soldier
var rig_data := {}                  # per character kind: grip data, size, animation library
# the other soldiers (enemies): the player's own clips are copied onto them
const KINDS := {"soldier": "res://assets/soldier.glb", "gasmask": "res://assets/chars/gasmask.glb",
	"olive": "res://assets/chars/olive.glb", "blue": "res://assets/chars/blue.glb"}
var ik_tgt: Node3D
var hp := 100.0
var dead := false
var dead_t := 0.0
var hurt_t := 0.0                   # red flash on the screen when hit
var quiet_t := 0.0                  # time since the last hit (health comes back after 5 s)
var hurt_dir := 0.0                 # where the last hit came from (screen angle)


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
	model_scale = s
	sc.scale = Vector3.ONE * s
	sc.rotation.y = PI
	_skin(sc, Color(1, 1, 1))
	head_bone = skel.find_bone("mixamorigHead")
	for n in ["idle", "aim", "kneel", "crouchFire", "walk", "walkBack", "walkR", "walkL", "run", "runBack", "runStrafeR", "runStrafeL", "crouchWalk2", "crouchBack", "reload"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_calibrate_and_attach()
	_build_tree()


## Soldier materials. They cast soft shadows (on themselves and lightly on the ground), except the first-person
## arms, which also leave out whatever is within a hand's breadth of the eye (head, helmet) with a clean cut.
func _skin(sc: Node3D, tint: Color, fade_near := false) -> void:
	for m in sc.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if fade_near else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mat = m.get_active_material(0)
		if mat is StandardMaterial3D:
			var mm: StandardMaterial3D = mat.duplicate()
			mm.albedo_color = tint
			mm.roughness = 0.85
			mm.metallic = 0.0
			mm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if fade_near:
				mm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				mm.distance_fade_min_distance = 0.2
				mm.distance_fade_max_distance = 0.2005
			m.material_override = mm


## Another soldier with the same grip on the given guns (first-person arms, enemies). Add r.root to the tree,
## then call start_rig(r).
func make_rig(tint: Color, keys: Array, fade_near := false, kind := "soldier") -> Dictionary:
	var info := _kind(kind)
	var sc: Node3D = load(KINDS[kind]).instantiate()
	sc.scale = Vector3.ONE * float(info["scale"])
	sc.rotation.y = PI
	_skin(sc, tint, fade_near)
	var sk: Skeleton3D = sc.find_children("*", "Skeleton3D", true, false)[0]
	var cap: AnimationPlayer = _rig_player(sc, kind)
	var d: Dictionary = info["data"]
	var r := {"root": sc, "skel": sk, "ap": cap, "guns": {}, "muzzles": {}, "data": d, "kind": kind}
	var att := BoneAttachment3D.new()
	att.bone_name = "mixamorigRightHand"
	sk.add_child(att)
	for k in keys:
		var holder := Node3D.new()
		holder.name = k
		holder.transform = d["holder"][k]
		att.add_child(holder)
		var g := _load_gun(k, not fade_near)
		holder.add_child(g)
		var tgt := Marker3D.new()
		tgt.name = "LeftGrip"
		tgt.transform = d["left"][k]
		holder.add_child(tgt)
		r["guns"][k] = holder
		r["muzzles"][k] = g.find_child("muzzle", true, false)
	var k_ik := SkeletonIK3D.new()
	k_ik.root_bone = "mixamorigLeftArm"
	k_ik.tip_bone = "mixamorigLeftHand"
	k_ik.override_tip_basis = true
	k_ik.use_magnet = true
	k_ik.magnet = d["magnet"]
	sk.add_child(k_ik)
	r["ik"] = k_ik
	var tgt := Node3D.new()
	tgt.top_level = true
	sk.add_child(tgt)
	r["ik_target"] = tgt
	return r


## The animation player of another soldier: the soldier's own, or (other characters) a new one carrying the
## player's clips with their bone paths pointed at this skeleton and the hips moves scaled to its size.
func _rig_player(sc: Node3D, kind: String) -> AnimationPlayer:
	if kind == "soldier":
		return sc.find_child("AnimationPlayer", true, false)
	var cap := AnimationPlayer.new()
	sc.add_child(cap)
	cap.add_animation_library("", _kind(kind)["lib"])
	return cap


## Size, grip data and clips of a character kind, worked out once on a spare copy.
func _kind(kind: String) -> Dictionary:
	if rig_data.has(kind) and rig_data[kind].has("scale"):
		return rig_data[kind]
	if kind == "soldier":
		rig_data[kind] = {"scale": model_scale, "data": main_data}
		return rig_data[kind]
	var sc: Node3D = load(KINDS[kind]).instantiate()
	var sk: Skeleton3D = sc.find_children("*", "Skeleton3D", true, false)[0]
	var info := {"lib": _retarget(sc, sk)}
	var holder := Node3D.new()
	get_parent().add_child(holder)
	holder.add_child(sc)
	var lo := INF
	var hi := -INF
	for m in sc.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = m.global_transform * m.get_aabb()
		lo = min(lo, bb.position.y)
		hi = max(hi, bb.end.y)
	info["scale"] = 1.8 / max(0.01, hi - lo)
	sc.scale = Vector3.ONE * float(info["scale"])
	sc.rotation.y = PI
	var cap := AnimationPlayer.new()
	sc.add_child(cap)
	cap.add_animation_library("", info["lib"])
	info["data"] = calibrate(sk, cap, Vector3(0, 0, -1))
	holder.queue_free()
	rig_data[kind] = info
	return info


func _retarget(sc: Node3D, sk: Skeleton3D) -> AnimationLibrary:
	var src: AnimationLibrary = ap.get_animation_library("")
	var lib := AnimationLibrary.new()
	var path := str(sc.get_path_to(sk))
	var k: float = sk.get_bone_rest(sk.find_bone("mixamorigHips")).origin.y / skel.get_bone_rest(skel.find_bone("mixamorigHips")).origin.y
	for name in src.get_animation_list():
		var a: Animation = src.get_animation(name).duplicate()
		for i in range(a.get_track_count() - 1, -1, -1):
			var bone := str(a.track_get_path(i)).get_slice(":", 1)
			if sk.find_bone(bone) < 0:
				a.remove_track(i)
				continue
			a.track_set_path(i, NodePath(path + ":" + bone))
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D:
				for key in a.track_get_key_count(i):
					a.track_set_key_value(i, key, a.track_get_key_value(i, key) * k)
		lib.add_animation(name, a)
	return lib


func start_rig(r: Dictionary, gun: String) -> void:
	for k in r["guns"]:
		r["guns"][k].visible = k == gun
	r["ik"].target_node = r["ik"].get_path_to(r["ik_target"])
	r["ik"].start()


## Wrist turn and closed fingers on any of the soldiers (after its clips have been applied).
func pose_rig_hands(sk: Skeleton3D, gun: String, d := {}) -> void:
	var dd: Dictionary = main_data if d.is_empty() else d
	var b := sk.find_bone("mixamorigRightHand")
	sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * dd["r_corr"])
	var lc: float = LEFT_HOLD[gun].get("c", 1.0)
	for f in dd["fingers"]:
		sk.set_bone_pose_rotation(f[0], f[1] * Quaternion(f[2], f[3] * (lc if f[4] else 1.0)))


## Turn a soldier's chest (shared over the three spine bones) so its rifle points along want (world), weight w.
func aim_chest(sk: Skeleton3D, want: Vector3, w: float, d := {}) -> void:
	if w < 0.01:
		return
	var dd: Dictionary = main_data if d.is_empty() else d
	var sk_inv: Basis = sk.global_transform.basis.orthonormalized().inverse()
	var hb: Basis = sk.get_bone_global_pose(sk.find_bone("mixamorigRightHand")).basis.orthonormalized()
	var gun_dir: Vector3 = (hb * Basis(dd["gib"])).z.normalized()
	var want_s: Vector3 = (sk_inv * want).normalized()
	if gun_dir.dot(want_s) > 0.99999:
		return
	turn_chest(sk, Quaternion.IDENTITY.slerp(Quaternion(gun_dir, want_s), w))


func turn_chest(sk: Skeleton3D, q: Quaternion) -> void:
	var ang := q.get_angle()
	if ang < 0.0005:
		return
	var axis := q.get_axis().normalized()
	for n in ["mixamorigSpine", "mixamorigSpine1", "mixamorigSpine2"]:
		var b := sk.find_bone(n)
		var pg: Basis = sk.get_bone_global_pose(sk.get_bone_parent(b)).basis.orthonormalized()
		sk.set_bone_pose_rotation(b, Quaternion((pg.inverse() * axis).normalized(), ang / 3.0) * sk.get_bone_pose_rotation(b))


## Hand axes in skeleton space: d along the back of the hand to the knuckles, n out of the palm.
func _hand_axes(sk: Skeleton3D, side: String, rest: bool) -> Dictionary:
	var pos := {}
	for b in ["Hand", "HandIndex1", "HandMiddle1", "HandPinky1"]:
		var id := sk.find_bone("mixamorig%s%s" % [side, b])
		var tr: Transform3D = sk.get_bone_global_rest(id) if rest else sk.get_bone_global_pose(id)
		pos[b] = tr.origin
	var d: Vector3 = (pos["HandMiddle1"] - pos["Hand"]).normalized()
	var a: Vector3 = (pos["HandIndex1"] - pos["HandPinky1"]).normalized()   # toward the thumb side
	var n: Vector3 = (a.cross(d) if side == "Right" else d.cross(a)).normalized()
	return {"d": d, "n": n, "len": (pos["HandMiddle1"] - pos["Hand"]).length()}


func _frame(d: Vector3, n: Vector3) -> Basis:
	var dd := d.normalized()
	var nn := (n - dd * n.dot(dd)).normalized()
	return Basis(dd, nn, dd.cross(nn))


func _load_gun(k: String, shadows := true) -> Node3D:
	var g: Node3D = load("res://assets/guns/%s.glb" % k).instantiate()
	g.scale = Vector3.ONE * GUN_SCALE[k]
	for m in g.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in mi.mesh.get_surface_count():
			var mat = mi.mesh.surface_get_material(si)
			if mat is StandardMaterial3D:
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return g


## Put each gun's pistol grip inside the curled right hand and the left palm under the handguard.
## The Mixamo clips hold an invisible rifle; the right wrist gets the small fixed turn (r_corr) that lines a
## properly gripped gun up with it, so the barrel still points where the clips (and the crosshair) point.
## Works on any Mixamo-rigged soldier (sk, with its own animation player in the aim clip), facing `ahead`.
func calibrate(sk: Skeleton3D, cap: AnimationPlayer, ahead: Vector3) -> Dictionary:
	var sg := sk.global_transform
	var sc: float = sg.basis.get_scale().x
	var rh := sk.find_bone("mixamorigRightHand")
	var lh := sk.find_bone("mixamorigLeftHand")
	var le := sk.find_bone("mixamorigLeftForeArm")
	var hr := _hand_axes(sk, "Right", true)
	var hl := _hand_axes(sk, "Left", true)
	var rbr: Basis = sk.get_bone_global_rest(rh).basis.orthonormalized().inverse()
	var lbr: Basis = sk.get_bone_global_rest(lh).basis.orthonormalized().inverse()
	var r_loc := _frame(rbr * hr["d"], rbr * hr["n"])
	var l_loc := _frame(lbr * hl["d"], lbr * hl["n"])
	var r_len: float = hr["len"] * sc
	var l_len: float = hl["len"] * sc

	cap.play("aim")
	cap.seek(0.6, true)
	sk.force_update_all_bone_transforms()
	var hand_w: Transform3D = sg * sk.get_bone_global_pose(rh)
	var hn_w := Transform3D(hand_w.basis.orthonormalized(), hand_w.origin)
	var elbow_skel: Vector3 = sk.get_bone_global_pose(le).origin
	var want := Basis.looking_at(ahead, Vector3.UP, true)   # +Z of the gun along the barrel
	cap.stop()

	# right hand round the grip: index side up the grip, palm against its right side. The hand may roll round
	# the grip; take the roll that needs the least wrist turn.
	var up_grip := -GRIP_DOWN.normalized()
	var fwd_sq := (Vector3(0, 0, 1) - up_grip * up_grip.z).normalized()
	var best := INF
	var r_basis_g := Basis()
	var d_best := fwd_sq
	var n_best := Vector3.ZERO
	for i in 17:
		var roll := deg_to_rad(-40.0 + i * 5.0)
		var d_t := fwd_sq.rotated(up_grip, roll)
		var n_t := up_grip.cross(d_t)
		var bg := _frame(d_t, n_t) * r_loc.inverse()         # hand axes -> gun axes
		var corr := want * (hn_w.basis * bg.inverse()).inverse()
		var ang := corr.get_rotation_quaternion().get_angle()
		if ang < best:
			best = ang
			r_basis_g = bg
			d_best = d_t
			n_best = n_t
	var gun_b := hn_w.basis * r_basis_g.inverse()            # gun axes (world) with the hand as it is in the clip
	var d := {"r_corr": (hn_w.basis.inverse() * (want * gun_b.inverse()) * hn_w.basis).get_rotation_quaternion(),
		"holder": {}, "left": {}, "gib": Basis(), "fingers": _finger_set(sk),
		"magnet": elbow_skel + Vector3(0, -sk.get_bone_rest(sk.find_bone("mixamorigHips")).origin.y * 0.16, 0)}
	print("grip: wrist turn %.1f deg" % rad_to_deg(best))
	for k in ["pistol", "m4", "ak"]:
		var gs: float = GUN_SCALE[k]
		var grip_c := GRIP_DOWN.normalized() * 0.05 * gs
		var wrist_g := grip_c - d_best * (r_len * 0.78) - n_best * 0.03
		var gun_in_hand := Transform3D(r_basis_g, wrist_g).affine_inverse()
		d["gib"] = gun_in_hand.basis
		# relative to the hand bone (which carries the wrist turn at run time); the bone's scale cancels out
		d["holder"][k] = hand_w.affine_inverse() * hn_w * gun_in_hand
		var hold: Dictionary = LEFT_HOLD[k]
		var lf := _frame(hold["d"], hold["n"])
		var wrist_l: Vector3
		if hold.has("k"):
			wrist_l = hold["k"] * gs - lf.x * l_len
		else:
			wrist_l = hold["p"] * gs - lf.x * (l_len * 0.55) - lf.y * 0.025
		d["left"][k] = Transform3D(lf * l_loc.inverse(), wrist_l)
	return d


func _calibrate_and_attach() -> void:
	main_data = calibrate(skel, ap, -global_transform.basis.z)
	rig_data["soldier"] = main_data
	r_corr = main_data["r_corr"]
	gun_in_hand_b = main_data["gib"]
	finger_set = main_data["fingers"]
	holder_xf = main_data["holder"]
	left_xf = main_data["left"]
	ik_magnet = main_data["magnet"]
	var att := BoneAttachment3D.new()
	att.bone_name = "mixamorigRightHand"
	skel.add_child(att)
	for k in ["pistol", "m4", "ak"]:
		var holder := Node3D.new()
		holder.name = k
		holder.transform = holder_xf[k]
		att.add_child(holder)
		var g := _load_gun(k)
		holder.add_child(g)
		var mz: Node3D = g.find_child("muzzle", true, false)
		guns[k] = holder
		muzzles[k] = mz
		holder.visible = false
	ik = SkeletonIK3D.new()
	ik.root_bone = "mixamorigLeftArm"
	ik.tip_bone = "mixamorigLeftHand"
	ik.override_tip_basis = true
	ik.use_magnet = true
	ik.magnet = ik_magnet
	skel.add_child(ik)
	_select_gun()
	ik.start()


## Finger curls, measured once from the rest pose: each joint turns about the line square to the finger and the palm.
## The rest pose has the fingers fanned out; the first joint also turns them in, side by side.
func _finger_set(sk: Skeleton3D) -> Array:
	var out := []
	for side in ["Right", "Left"]:
		var hx := _hand_axes(sk, side, true)
		var n_s: Vector3 = hx["n"]
		var d_s: Vector3 = hx["d"]
		var table: Dictionary = CURL_R if side == "Right" else CURL_L
		for f in table:
			for seg in 3:
				var b := sk.find_bone("mixamorig%sHand%s%d" % [side, f, seg + 1])
				var c := sk.find_bone("mixamorig%sHand%s%d" % [side, f, seg + 2])
				if b < 0 or c < 0:
					continue
				var gb: Transform3D = sk.get_bone_global_rest(b)
				var along: Vector3 = (sk.get_bone_global_rest(c).origin - gb.origin).normalized()
				var ax: Vector3 = along.cross(n_s)
				if ax.length() < 0.05:
					continue
				var inv: Basis = gb.basis.orthonormalized().inverse()
				var ax_l: Vector3 = (inv * ax.normalized()).normalized()
				var q := sk.get_bone_rest(b).basis.get_rotation_quaternion()
				if seg == 0 and f != "Thumb":
					var flat: Vector3 = (along - n_s * along.dot(n_s)).normalized()
					var spread: float = atan2(d_s.cross(flat).dot(n_s), d_s.dot(flat))
					q = q * Quaternion((inv * n_s).normalized(), -spread * CLOSE_FINGERS)
				out.append([b, q, ax_l, deg_to_rad(table[f][seg]), side == "Left"])
	return out


## After the clips: the right wrist turn and the closed fingers.
var rh_bone := -1
func _pose_hands() -> void:
	if rh_bone < 0:
		rh_bone = skel.find_bone("mixamorigRightHand")
	pose_rig_hands(skel, weapons[wi]["gun"])


func _select_gun() -> void:
	var k: String = weapons[wi]["gun"]
	for g in guns:
		guns[g].visible = g == k
	if ik_tgt == null:
		ik_tgt = Node3D.new()
		ik_tgt.top_level = true
		skel.add_child(ik_tgt)
	ik.target_node = ik.get_path_to(ik_tgt)


## Where the left hand goes this frame: the gun's handguard as the right hand holds it now. (The gun's own
## marker only moves after the skeleton has been drawn, a frame late, which made the left hand shake.)
func place_left_target(sk: Skeleton3D, tgt: Node3D, gun: String, d := {}) -> void:
	var dd: Dictionary = main_data if d.is_empty() else d
	var hand: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorigRightHand"))
	tgt.global_transform = hand * Transform3D(dd["holder"][gun]) * Transform3D(dd["left"][gun])


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
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
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
	cam.far = 1400
	cam_arm.add_child(cam)
	cam.current = true
	# first person: a second soldier in the aim pose on the camera; only the arms and the gun come into view
	vm = Node3D.new()
	cam.add_child(vm)
	vm_rig = make_rig(Color(1, 1, 1), ["pistol", "m4", "ak"], true)
	vm.add_child(vm_rig["root"])
	vm_muzzles = vm_rig["muzzles"]
	var vap: AnimationPlayer = vm_rig["ap"]
	vap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	vap.play("aim")
	vap.seek(0.6, true)
	var vsk: Skeleton3D = vm_rig["skel"]
	pose_rig_hands(vsk, "ak")
	vsk.force_update_all_bone_transforms()
	var hand: Transform3D = vsk.global_transform * vsk.get_bone_global_pose(vsk.find_bone("mixamorigRightHand"))
	var inv := vm.global_transform.affine_inverse()
	for k in SIGHT:
		var sight_vm: Vector3 = inv * (hand * holder_xf[k] * SIGHT[k])
		vm_ads[k] = Vector3(0, 0, -EYE_BACK[k]) - sight_vm
	start_rig(vm_rig, weapons[wi]["gun"])
	vm.visible = false


func look(dx: float, dy: float) -> void:
	var s := 0.0042 * (0.55 if aiming else 1.0)
	yaw -= dx * s
	pitch = clamp(pitch - dy * s, -1.2, 1.1)


func toggle_crouch() -> void:
	crouch = not crouch


func jump() -> void:
	if is_on_floor() and not crouch and not dead:
		vel.y = JUMP_V


func swap() -> void:
	if reloading > 0 or switching > 0 or dead:
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
	hurt_t = max(0.0, hurt_t - dt)
	quiet_t += dt
	if not dead and quiet_t > 5.0 and hp < 100.0:
		hp = min(100.0, hp + dt * 6.0)
	if dead:
		move_in = Vector2.ZERO
		run_in = false
		firing = false
		aiming = false
		dead_t += dt
		if dead_t > 4.0:
			_respawn()
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
			if w["res"] < w["size"]:
				w["res"] = w["res0"]   # practice yard: the reserve never runs dry
	if firing and (w["auto"] or t - last_shot > 0.35):
		_fire()
	if not firing or reloading > 0 or switching > 0 or w["mag"] <= 0:
		snd.stop_auto()
	recoil = max(0.0, recoil - dt * 7.0)
	kick_p *= exp(-dt * 13.0)
	shake = max(0.0, shake - dt * 0.8)

	_animate(dt)
	tree.advance(dt)
	_pose_hands()
	_bend_spine(dt)
	place_left_target(skel, ik_tgt, weapons[wi]["gun"])
	_update_camera(dt)
	_footsteps(dt)


func _fire() -> void:
	var w: Dictionary = weapons[wi]
	if reloading > 0 or switching > 0 or dead:
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
	yaw += randf_range(-0.003, 0.003) * kk
	kick_p += 0.006 * kk
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
	var mz: Node3D = vm_muzzles[w["gun"]] if view == 2 else muzzles[w["gun"]]
	var mp := mz.global_position
	fx.muzzle_flash(mp, mz.global_transform.basis.z, w["gun"])
	if fx.get_parent().has_method("noise"):
		fx.get_parent().noise(global_position, 10.0 if w["gun"] == "pistol" else 32.0)   # the SD-9 is suppressed
	if hit:
		if hit.collider and hit.collider.has_method("take_hit"):
			hit.collider.take_hit(float(w["dmg"]), hit.position, d)
		else:
			fx.impact(hit.position, hit.normal, hit.collider)
		if int(w["mag"]) % 2 == 0 or not w["auto"]:
			fx.tracer(mp, hit.position, true)
	elif int(w["mag"]) % 2 == 0 or not w["auto"]:
		fx.tracer(mp, from + d * 120.0, true)


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
	if dead:
		st = "dead"
	elif not is_on_floor() and vel.y > 0.5:
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
	var want_up := 1.0 if (moving and (aim_now or reloading > 0) and st != "jump" and not dead) else 0.0
	if reloading > 0 and not moving:
		want_up = 1.0
	up_w = lerp(up_w, want_up, min(1.0, dt * 9.0))
	rl_w = lerp(rl_w, 1.0 if reloading > 0 else 0.0, min(1.0, dt * 9.0))
	tree.set("parameters/upper/blend_amount", up_w)
	tree.set("parameters/pick/blend_amount", rl_w)
	# left hand on the gun except while reloading or switching
	var free = reloading > 0 or switching > 0 or dead
	ik_w = lerp(ik_w, 0.0 if free else 1.0, min(1.0, dt * 10.0))
	ik.interpolation = ik_w
	for g in guns:
		guns[g].visible = g == w["gun"] and switching < 0.2 and view != 2


var aim_k := 0.0
## Chest. Relaxed: lean a little with the camera pitch. Aiming or firing: turn the chest so the barrel lies on the
## crosshair line whatever the legs are doing (the strafe and run clips twist and tip the hips, which used to
## carry the rifle off to the side and down).
func _bend_spine(dt: float) -> void:
	var aim_now: bool = (aiming or firing or t - last_shot < 2.5) and not dead
	aim_k = lerp(aim_k, 1.0 if aim_now else 0.0, min(1.0, dt * 10.0))
	var sk_inv: Basis = skel.global_transform.basis.orthonormalized().inverse()
	var lean: float = clamp(pitch, -0.9, 0.9) * 0.35 * (1.0 - aim_k)
	if abs(lean) > 0.001 and not dead:
		turn_chest(skel, Quaternion((sk_inv * global_transform.basis.x).normalized(), lean))
	aim_chest(skel, aim_dir_now(), aim_k * (1.0 - rl_w))


func aim_dir_now() -> Vector3:
	var p := pitch + kick_p
	return Vector3(-sin(yaw) * cos(p), sin(p), -cos(yaw) * cos(p))


func _update_camera(dt: float) -> void:
	var lens := [[2.0, 0.55, 1.6], [1.35, 0.45, 1.62], [0.0, 0.0, 1.62]]
	var cfg: Array = lens[view]
	var tl: float = cfg[0]
	var ts: float = cfg[1]
	var th: float = cfg[2]
	if crouch:
		th -= 0.32
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
	var fp := view == 2 and not dead
	model.visible = not fp
	vm.visible = fp
	if fp:
		_update_arms(dt)


var vm_gun := ""
## First person: the arms rig holds the aim pose (with its slight breathing), the current gun, closed hands;
## lower and to the right from the hip, sights on the eye line when aiming.
func _update_arms(dt: float) -> void:
	var cur: String = weapons[wi]["gun"]
	if cur != vm_gun:
		vm_gun = cur
		start_rig(vm_rig, cur)
	vm_rig["guns"][cur].visible = switching < 0.2
	var vap: AnimationPlayer = vm_rig["ap"]
	vap.seek(0.6, true)                 # the aim pose held still: its breathing looks like shaking this close
	var vsk: Skeleton3D = vm_rig["skel"]
	pose_rig_hands(vsk, cur)
	vsk.set_bone_pose_scale(vsk.find_bone("mixamorigHead"), Vector3.ONE * 0.001)   # no head or helmet in view
	vm_rig["ik"].interpolation = ik_w
	ads_k = lerp(ads_k, 1.0 if aiming else 0.0, min(1.0, dt * 12.0))
	var mv: float = clamp(speed / 3.0, 0.0, 1.0) * (1.0 - ads_k * 0.85)
	var bob := Vector3(sin(t * 7.0) * 0.008, -abs(cos(t * 7.0)) * 0.01, 0.0) * mv
	var ads: Vector3 = vm_ads[cur]
	var hip: Vector3 = ads + (Vector3(0.07, -0.045, 0.0) if cur == "pistol" else Vector3(0.11, -0.085, 0.05))
	vm.position = hip.lerp(ads, ads_k) + bob + Vector3(0, -0.12 * rl_w, recoil * 0.03 * (1.0 - ads_k * 0.5))
	vm.rotation = Vector3(recoil * 0.035 - 0.45 * rl_w, 0.07 * (1.0 - ads_k), 0.03 * (1.0 - ads_k))
	place_left_target(vsk, vm_rig["ik_target"], cur)


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


## Hit by an enemy round.
func hit(dmg: float, from: Vector3) -> void:
	if dead:
		return
	hp -= dmg
	hurt_t = 0.6
	quiet_t = 0.0
	shake = max(shake, 0.2)
	var to := from - global_position
	hurt_dir = atan2(to.dot(Vector3(cos(yaw), 0, -sin(yaw))), to.dot(Vector3(-sin(yaw), 0, -cos(yaw))))
	if hp <= 0:
		_die()


var view_before := 0
func _die() -> void:
	dead = true
	dead_t = 0.0
	hp = 0.0
	snd.stop_auto()
	snd.death(global_position, "player")
	view_before = view
	if view == 2:
		view = 0
	if fx.get_parent().has_method("on_player_dead"):
		fx.get_parent().on_player_dead()


func _respawn() -> void:
	dead = false
	hp = 100.0
	vel = Vector3.ZERO
	velocity = Vector3.ZERO
	global_position = spawn
	yaw = 0.0
	pitch = -0.05
	crouch = false
	reloading = 0.0
	view = view_before
	for w in weapons:
		w["mag"] = w["size"]
		w["res"] = w["res0"]
	if fx.get_parent().has_method("on_player_respawn"):
		fx.get_parent().on_player_respawn()


func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z
