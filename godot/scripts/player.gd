extends CharacterBody3D
## Kestrel: third-person soldier. Mixamo clips from soldier.glb drive the body through an AnimationTree
## (one direction clip at a time with a short crossfade, aim/reload on the upper body while moving).
## The rifle sits in the right hand exactly as in the aim pose; the left hand is pinned to the handguard by IK.

const WALK := 1.2
const WALK_BACK := 1.1
const RUN := 3.1
const RUN_SIDE := 2.6
const RUN_BACK := 2.1
const CROUCH := 1.1
const CROUCH_RUN := 1.6
const AIM_WALK := 1.2
const JUMP_V := 4.6
const GRAVITY := 12.0

# natural speed (m/s) of each clip, measured from its root motion
# the ground speed each clip's feet really walk at (measured: the planted foot must not slide)
const NAT := {"walk": 0.8, "walkBack": 0.95, "walkR": 1.75, "walkL": 1.78, "run": 2.45, "runBack": 1.8,
	"runStrafeR": 2.2, "runStrafeL": 1.7, "crouchWalk2": 1.06, "crouchBack": 1.17, "crouchRun": 1.3}
const STATES := {"idle": "idle", "aim": "aim", "kneel": "kneel", "kneel_aim": "crouchFire", "jump": "jump",
	"walk": "walk", "walk_b": "walkBack", "walk_r": "walkR", "walk_l": "walkL",
	"run": "run", "run_b": "runBack", "run_r": "runStrafeR", "run_l": "runStrafeL",
	"c_walk": "crouchWalk2", "c_back": "crouchBack", "c_run": "crouchWalk2", "c_r": "crouchWalk2", "c_l": "crouchWalk2",
	"dead": "dieFront", "kick": "kick"}
# (the "crouchRun" clip has its hips 1.8 m behind the body, which put the soldier behind the camera: crouch-running
# plays the crouch walk faster instead)
const UPPER := ["mixamorigSpine", "mixamorigSpine1", "mixamorigSpine2", "mixamorigNeck", "mixamorigHead",
	"mixamorigLeftShoulder", "mixamorigLeftArm", "mixamorigLeftForeArm", "mixamorigLeftHand",
	"mixamorigRightShoulder", "mixamorigRightArm", "mixamorigRightForeArm", "mixamorigRightHand"]

# the gun models are built to real size (metres)
const GUN_SCALE := {"pistol": 1.0, "m4": 1.0, "ak": 1.0, "svd": 1.0, "shotgun": 1.0, "rpg": 1.0}
const GUNS := ["pistol", "m4", "ak", "svd", "shotgun", "rpg"]
# left hand, in the gun's own units (x left, y up, z along the barrel): the way the palm faces (n), the way the
# fingers point (d), and either the knuckle joints (k) or where the palm presses (p). Rifles: palm up under the
# handguard, knuckles under its middle so the fingers wrap up round the far side. Pistol: palm over the right
# hand's fingers from the left, fingers forward and down.
const LEFT_HOLD := {
	"pistol": {"p": Vector3(0.04, -0.05, -0.005), "n": Vector3(-1.0, 0.35, 0.0), "d": Vector3(0.0, -0.5, 0.85)},
	"m4": {"k": Vector3(-0.006, 0.008, 0.24), "n": Vector3(-0.15, 1.0, 0.0), "d": Vector3(-1.0, 0.0, 0.3), "c": 0.86},
	"ak": {"k": Vector3(-0.01, -0.018, 0.26), "n": Vector3(-0.15, 1.0, 0.0), "d": Vector3(-1.0, 0.0, 0.3), "c": 0.9},
	"svd": {"k": Vector3(-0.01, -0.024, 0.3), "n": Vector3(-0.15, 1.0, 0.0), "d": Vector3(-1.0, 0.0, 0.3), "c": 0.9},
	"shotgun": {"k": Vector3(-0.008, -0.016, 0.35), "n": Vector3(-0.15, 1.0, 0.0), "d": Vector3(-1.0, 0.0, 0.3), "c": 0.84},
	"rpg": {"k": Vector3(-0.008, 0.038, 0.25), "n": Vector3(-0.15, 1.0, 0.0), "d": Vector3(-1.0, 0.0, 0.3), "c": 0.84}}
const GRIP_DOWN := Vector3(0, -0.94, -0.34)   # down the pistol grip (same rake on all three)
# first person, aiming: eye on the sight line (AK irons, M4 through the red dot, pistol irons)
# first person: the point on each gun the eye looks along (gun units), and how far behind it the eye sits
const SIGHT := {"pistol": Vector3(0, 0.066, 0.0), "m4": Vector3(0, 0.127, 0.0), "ak": Vector3(0, 0.077, 0.19),
	"svd": Vector3(0.018, 0.112, 0.0), "shotgun": Vector3(0, 0.074, 0.0), "rpg": Vector3(0.046, 0.13, 0.0)}
const EYE_BACK := {"pistol": 0.24, "m4": 0.14, "ak": 0.4, "svd": 0.24, "shotgun": 0.32, "rpg": 0.2}
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
	# Dragunov: one heavy round, 4x PSO-1 scope
	{"name": "DRAGUNOV SVD", "gun": "svd", "res0": 30, "mag": 10, "size": 10, "res": 30, "dmg": 140, "rate": 0.42, "spread": 0.003, "auto": false, "kick": 2.6, "scope": 13.0, "power": 1.6, "reload": 2.0},
	# 12 gauge pump: nine pellets, pumped after every shot
	{"name": "PUMP SHOTGUN", "gun": "shotgun", "res0": 28, "mag": 7, "size": 7, "res": 28, "dmg": 20, "rate": 0.85, "spread": 0.01, "auto": false, "kick": 2.8, "pellets": 9, "cone": 0.055, "power": 2.2, "reload": 2.3},
	# RPG-7: a rocket that flies and blows up on whatever it hits
	{"name": "RPG-7", "gun": "rpg", "res0": 4, "mag": 1, "size": 1, "res": 4, "dmg": 0, "rate": 1.0, "spread": 0.002, "auto": false, "kick": 3.2, "rocket": true, "scope": 34.0, "reload": 2.6},
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
var groan_t := 0.0                  # the player's pain groan: not more than one at a time
var infinite := true                # practice yard: the reserve never runs dry (missions: what you carry)
var act_kind := ""                  # what the ACTION button would do here: "kick" a door, "take" a dead man's gun, "item"
var act_node: Node = null
var act_label := ""
# cover: back to a wall (or crouched behind something low), sliding along it, leaning out at its end to shoot
var cover := false
var cover_n := Vector3.ZERO      # out of the wall
var cover_low := false
var cover_edge := 0              # the wall ends here: -1 / +1 along the wall, 0 not at an end
var cover_peek := 0.0            # how far out of the end he has stepped to shoot
var cover_hit := {}
var cover_cool := 0.0           # after leaving cover: no automatic cover for a moment
var touch_t := 0.0              # how long he has been walking into a wall
var end_t := 0.0                # how long the stick has pushed past the end of the wall
var cover_reach := 0.0          # how far he steps to clear the end of the wall
var act_doing := ""
var act_obj: Node = null
var act_t := -1.0                   # doing it: time into it
var act_check := 0.0
var do_w := 0.0
var leg_t := 0.0                    # wounded in the leg: limping for a while
var arm_t := 0.0                    # wounded in the arm: shakier aim for a while
var grenades := 4
var throw_t := -1.0                 # grenade throw: time into it (-1: not throwing)
var thrown := false
var nade_hand: Node3D               # the grenade in the right hand until it is thrown
var knife_hand: Node3D              # the combat knife, in the hand while it is used
var knife_t := -1.0                 # a knife stroke: time into it
var knife_hit := false
const KNIFE_FROM := 0.85            # the grenade clip's overarm swing, used for a downward stab
var holstered := false              # the gun is on the back (the pistol in its thigh holster)
var hol_t := -1.0                   # putting the gun away (hol_dir 1) or drawing it (-1): time into it
var hol_dir := 0
var back_guns := {}                 # per gun: the copy on the back / thigh
var parts := {}                     # per gun: moving parts (shotgun pump, RPG rocket), for both rigs
var pump_t := 9.0                   # time since the last shotgun shot (the pump slides back and forward)
var climb_t := -1.0                 # climbing onto / over something: time into it
var climb_a := Vector3.ZERO
var climb_b := Vector3.ZERO
var climb_top := 0.0
var climb_dur := 0.6
var climb_vault := false
var can_climb := false              # something climbable just ahead (the JUMP button says CLIMB)
var climb_check_t := 0.0
var scope_k := 0.0                  # 0..1: looking through the SVD / RPG sight
var act_w := 0.0                    # upper body: grenade / holster clips over everything else
const HOL_SPEED := 1.9              # putBack clip played this much faster
const DRAW_SPEED := 1.6
const NADE_FROM := 0.25             # grenade clip: start (s), release, end; played 1.5x
const NADE_RELEASE := 1.12
const NADE_END := 2.0


func setup(fx_node: Node, snd_node: Node) -> void:
	fx = fx_node
	snd = snd_node
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
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
	_cut_clip("knockout", "knockback", 2.05, 0.25)    # about 1 m back
	_cut_clip("knockout", "fallback", 2.05, 0.12)     # half a metre: shot from further off
	_cut_clip("knockout", "blastback", 2.05, 0.55)    # thrown by an explosion
	for n in ["idle", "aim", "kneel", "crouchFire", "walk", "walkBack", "walkR", "walkL", "run", "runBack", "runStrafeR", "runStrafeL", "crouchWalk2", "crouchBack", "reload"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_calibrate_and_attach()
	_build_tree()


## A shorter copy of a clip for a powerful hit: starts at `from` and the hips travel only k of the way (the
## "knockout" clip throws the soldier 4 m back; a close shot should put him down a little way off).
func _cut_clip(src: String, dst: String, from: float, k: float) -> void:
	var lib: AnimationLibrary = ap.get_animation_library("")
	if lib.has_animation(dst) or not lib.has_animation(src):
		return
	var a: Animation = lib.get_animation(src).duplicate(true)
	for i in a.get_track_count():
		var ty := a.track_get_type(i)
		var hips := str(a.track_get_path(i)).ends_with(":mixamorigHips")
		var v0 = null
		if ty == Animation.TYPE_POSITION_3D:
			v0 = a.position_track_interpolate(i, from)
		elif ty == Animation.TYPE_ROTATION_3D:
			v0 = a.rotation_track_interpolate(i, from)
		elif ty == Animation.TYPE_SCALE_3D:
			v0 = a.scale_track_interpolate(i, from)
		for key in range(a.track_get_key_count(i) - 1, -1, -1):
			if a.track_get_key_time(i, key) <= from + 0.0001:
				a.track_remove_key(i, key)
		for key in a.track_get_key_count(i):
			var tk: float = a.track_get_key_time(i, key) - from
			a.track_set_key_time(i, key, tk)
			if hips and ty == Animation.TYPE_POSITION_3D:
				var v: Vector3 = a.track_get_key_value(i, key)
				a.track_set_key_value(i, key, Vector3(v0.x + (v.x - v0.x) * k, v.y, v0.z + (v.z - v0.z) * k))
		if v0 != null:
			if ty == Animation.TYPE_POSITION_3D:
				a.position_track_insert_key(i, 0.0, v0)
			elif ty == Animation.TYPE_ROTATION_3D:
				a.rotation_track_insert_key(i, 0.0, v0)
			else:
				a.scale_track_insert_key(i, 0.0, v0)
	a.length = a.length - from
	a.loop_mode = Animation.LOOP_NONE
	lib.add_animation(dst, a)


## Soldier materials. They cast soft shadows (on themselves and lightly on the ground), except the first-person
## arms, which also leave out whatever is within a hand's breadth of the eye (head, helmet) with a clean cut.
func _skin(sc: Node3D, tint: Color, fade_near := false) -> void:
	for m in sc.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # no shadows from people
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
	var r := {"root": sc, "skel": sk, "ap": cap, "guns": {}, "muzzles": {}, "parts": {}, "data": d, "kind": kind}
	var att := BoneAttachment3D.new()
	att.bone_name = "mixamorigRightHand"
	sk.add_child(att)
	for k in keys:
		var holder := Node3D.new()
		holder.name = k
		holder.transform = d["holder"][k]
		att.add_child(holder)
		var g := _load_gun(k)
		holder.add_child(g)
		var tgt := Marker3D.new()
		tgt.name = "LeftGrip"
		tgt.transform = d["left"][k]
		holder.add_child(tgt)
		r["guns"][k] = holder
		r["muzzles"][k] = g.find_child("muzzle", true, false)
		r["parts"][k] = {"pump": g.find_child("pump", true, false), "warhead": g.find_child("warhead", true, false)}
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


func _load_gun(k: String, shadows := false) -> Node3D:
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
	for k in GUNS:
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
	for k in GUNS:
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
		parts[k] = [{"pump": g.find_child("pump", true, false), "warhead": g.find_child("warhead", true, false)}]
	# the grenade in the hand (in the palm, where the pistol grip sits)
	nade_hand = fx.grenade_mesh()
	nade_hand.position = holder_xf["pistol"] * (GRIP_DOWN.normalized() * 0.05)
	nade_hand.scale = Vector3.ONE / skel.global_transform.basis.get_scale().x
	att.add_child(nade_hand)
	nade_hand.visible = false
	knife_hand = _knife_mesh()
	# held point-down out of the little-finger side of the fist (along the line a pistol grip would take)
	knife_hand.transform = Transform3D(Basis(holder_xf["pistol"].basis.orthonormalized()) * Basis.looking_at(-GRIP_DOWN.normalized(), Vector3(0, 0, 1)), holder_xf["pistol"] * (GRIP_DOWN.normalized() * 0.05))
	knife_hand.scale = Vector3.ONE / skel.global_transform.basis.get_scale().x
	att.add_child(knife_hand)
	knife_hand.visible = false
	_build_back_guns()
	ik = SkeletonIK3D.new()
	ik.root_bone = "mixamorigLeftArm"
	ik.tip_bone = "mixamorigLeftHand"
	ik.override_tip_basis = true
	ik.use_magnet = true
	ik.magnet = ik_magnet
	skel.add_child(ik)
	_select_gun()
	ik.start()


## The guns slung on the back (diagonal, muzzle up over the left shoulder, flat against the back) and the pistol in a
## holster on the right thigh, worked out on the rest pose with the soldier facing -Z.
func _build_back_guns() -> void:
	var back := BoneAttachment3D.new()
	back.bone_name = "mixamorigSpine2"
	skel.add_child(back)
	var leg := BoneAttachment3D.new()
	leg.bone_name = "mixamorigRightUpLeg"
	skel.add_child(leg)
	var w_back: Transform3D = skel.global_transform * skel.get_bone_global_rest(skel.find_bone("mixamorigSpine2"))
	var w_leg: Transform3D = skel.global_transform * skel.get_bone_global_rest(skel.find_bone("mixamorigRightUpLeg"))
	var mid := {"m4": 0.07, "ak": 0.02, "svd": 0.22, "shotgun": 0.15, "rpg": 0.12}
	for k in GUNS:
		var d: Transform3D
		var att: Node3D = back
		var w := w_back
		if k == "pistol":
			var z := Vector3(0, -1, 0)
			var y := Vector3(0, 0, -1)
			d = Transform3D(Basis(y.cross(z), y, z), w_leg.origin + Vector3(0.13, -0.1, 0.0))
			att = leg
			w = w_leg
		else:
			var b := Vector3(-0.5 if k != "rpg" else -0.35, 1.0, 0.0).normalized()
			var x := Vector3(0, 0, 1)
			var c: Vector3 = w_back.origin + Vector3(0, -0.02, 0.19 if k != "rpg" else 0.21)
			d = Transform3D(Basis(x, b.cross(x), b), c - b * float(mid[k]))
		var holder := Node3D.new()
		holder.name = "back_" + k
		holder.transform = w.affine_inverse() * d
		att.add_child(holder)
		var g := _load_gun(k)
		holder.add_child(g)
		holder.visible = false
		back_guns[k] = holder


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
	if holstered or (hol_t >= 0.0 and hol_dir == 1 and hol_t * HOL_SPEED > 2.3):
		return
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
func place_left_target(sk: Skeleton3D, tgt: Node3D, gun: String, d := {}, slide := 0.0) -> void:
	var dd: Dictionary = main_data if d.is_empty() else d
	var hand: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorigRightHand"))
	tgt.global_transform = hand * Transform3D(dd["holder"][gun]) * Transform3D(Basis(), Vector3(0, 0, -slide)) * Transform3D(dd["left"][gun])


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
	# grenade throw (-1), putting the gun away / holstered (0), drawing it (+1): each clip held at a time set
	# every frame (seek, then time scale 0)
	var acts := AnimationNodeBlend3.new()
	bt.add_node("acts", acts)
	var port := 0
	for c in [["nade", "grenade"], ["hol", "putBack"], ["draw", "pullOut"]]:
		var an := AnimationNodeAnimation.new()
		an.animation = c[1]
		bt.add_node(c[0] + "_a", an)
		var sk_ := AnimationNodeTimeSeek.new()
		bt.add_node(c[0] + "_seek", sk_)
		bt.connect_node(c[0] + "_seek", 0, c[0] + "_a")
		var hold := AnimationNodeTimeScale.new()
		bt.add_node(c[0] + "_hold", hold)
		bt.connect_node(c[0] + "_hold", 0, c[0] + "_seek")
		bt.connect_node("acts", port, c[0] + "_hold")
		port += 1
	var act := AnimationNodeBlend2.new()
	bt.add_node("act", act)
	bt.connect_node("act", 0, "pick")
	bt.connect_node("act", 1, "acts")
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	var sp: String = str(model.get_path_to(skel))
	for b in UPPER:
		upper.set_filter_path(NodePath(sp + ":" + b), true)
	bt.add_node("upper", upper)
	bt.connect_node("upper", 0, "speed")
	bt.connect_node("upper", 1, "act")
	bt.connect_node("output", 0, "upper")
	tree.tree_root = bt
	tree.active = true
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	playback = tree.get("parameters/loco/playback")
	tree.set("parameters/rspeed/scale", 1.4)
	for c in ["nade", "hol", "draw"]:
		tree.set("parameters/%s_hold/scale" % c, 0.0)


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
	vm_rig = make_rig(Color(1, 1, 1), GUNS, true)
	vm.add_child(vm_rig["root"])
	vm_muzzles = vm_rig["muzzles"]
	for k in GUNS:
		parts[k].append(vm_rig["parts"][k])
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
	if scope_k > 0.5:
		s *= cam.fov / 50.0    # through a scope the view turns no faster on screen than without
	yaw -= dx * s
	pitch = clamp(pitch - dy * s, -1.2, 1.1)


func toggle_crouch() -> void:
	crouch = not crouch


## JUMP: climbs onto (or over) whatever is just ahead if it can be climbed, else an ordinary jump.
func jump() -> void:
	if dead or climb_t >= 0.0:
		return
	if cover:
		leave_cover()
	if _climb_probe(true):
		return
	if is_on_floor() and not crouch:
		vel.y = JUMP_V


func busy() -> bool:
	return dead or climb_t >= 0.0 or throw_t >= 0.0 or hol_t >= 0.0 or act_t >= 0.0 or knife_t >= 0.0


## A combat knife: steel blade, black grip, guard (metres; the blade along +z of the hand's grip).
func _knife_mesh() -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.7, 0.68)
	steel.metallic = 0.9
	steel.roughness = 0.25
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.06, 0.06, 0.06)
	black.roughness = 0.7
	for pt in [[Vector3(0, 0, 0.11), Vector3(0.004, 0.028, 0.17), steel], [Vector3(0, 0.006, 0.2), Vector3(0.004, 0.016, 0.02), steel],
			[Vector3(0, 0, 0.0), Vector3(0.024, 0.03, 0.12), black], [Vector3(0, 0, 0.065), Vector3(0.012, 0.06, 0.01), steel]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[1]
		mi.mesh = bm
		mi.material_override = pt[2]
		mi.position = pt[0]
		root.add_child(mi)
	return root


## KNIFE: an overarm stab at whoever is within reach in front. A soldier who has not seen it coming (on guard,
## searching, or turned away) dies silently; one in a fight facing the player takes a deep wound.
func knife() -> void:
	if busy():
		return
	knife_t = 0.0
	knife_hit = false
	reloading = 0.0
	firing = false
	snd.stop_auto()
	snd.holster()


func _knife_step(dt: float) -> void:
	knife_t += dt
	if knife_t >= 0.24 and not knife_hit:
		knife_hit = true
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var best = null
		var bd := 1.9
		for e in fx.get_parent().enemies:
			if e.dead:
				continue
			var to: Vector3 = e.global_position - global_position
			to.y = 0.0
			var d := to.length()
			if d < bd and (d < 0.6 or fwd.dot(to.normalized()) > 0.45) and abs(e.global_position.y - global_position.y) < 1.2:
				bd = d
				best = e
		if best:
			var efwd := Vector3(-sin(best.yaw), 0, -cos(best.yaw))
			var unaware: bool = best.mode != "combat" or efwd.dot(fwd) > 0.3
			best.stab(fwd, unaware)
			shake = max(shake, 0.15)
	if knife_t >= 0.7:
		knife_t = -1.0


func swap() -> void:
	for k in range(1, weapons.size()):
		var i := (wi + k) % weapons.size()
		if weapons[i].get("own", true):
			select_weapon(i)
			return


func select_weapon(i: int) -> void:
	if reloading > 0 or switching > 0 or busy() or i == wi or not weapons[i].get("own", true):
		return
	wi = i
	switching = 0.4
	snd.stop_auto()
	_select_gun()
	if holstered:
		_start_draw()


func reload() -> void:
	var w: Dictionary = weapons[wi]
	if reloading > 0 or w["mag"] == w["size"] or w["res"] <= 0 or busy() or holstered:
		return
	reloading = float(w.get("reload", 1.6))
	snd.stop_auto()
	snd.reload(w["gun"])
	tree.set("parameters/rseek/seek_request", 0.0)
	tree.set("parameters/rspeed/scale", 1.4 * 1.6 / reloading)


## HOLSTER: the gun goes onto the back (the pistol into its thigh holster) and the arms hang free; again, or FIRE,
## draws it.
func toggle_holster() -> void:
	if busy():
		return
	if holstered:
		_start_draw()
	else:
		reloading = 0.0
		firing = false
		snd.stop_auto()
		hol_dir = 1
		hol_t = 0.0
		snd.holster()


func _start_draw() -> void:
	hol_dir = -1
	hol_t = 0.0
	snd.holster()


## GRENADE: the gun goes out of the hand, the grenade comes out, the arm swings it, it flies (bouncing) and goes
## off 2.4 s later.
func throw_grenade() -> void:
	if grenades <= 0 or busy():
		return
	grenades -= 1
	throw_t = 0.0
	thrown = false
	reloading = 0.0
	snd.stop_auto()


func _release_grenade() -> void:
	thrown = true
	var d := aim_dir()
	var from: Vector3
	if view == 2:
		from = cam.global_position + d * 0.4 + cam.global_transform.basis.x * 0.15
	else:
		from = nade_hand.global_position
	var v := d * 15.0 + Vector3.UP * (3.2 - d.y * 2.0) + Vector3(vel.x, 0, vel.z) * 0.5
	fx.get_parent().spawn_grenade(from, v, self)


## Something to climb straight ahead: a wall face at knee to chest height whose top (0.45-2.75 m up) has room to
## stand on (climb up), or which is thin with ground behind it (vault over). start: begin climbing.
func _climb_probe(start: bool) -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var base := global_position
	var face := Vector3.ZERO
	var n := Vector3.ZERO
	for h in [0.45, 0.9, 1.4, 1.9]:
		var q := PhysicsRayQueryParameters3D.create(base + Vector3(0, h, 0), base + Vector3(0, h, 0) + fwd * 1.3)
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var r := space.intersect_ray(q)
		if not r.is_empty() and abs(r.normal.y) < 0.35 and not r.collider.has_method("take_hit"):
			face = r.position
			n = Vector3(r.normal.x, 0, r.normal.z).normalized()
			break
	if n == Vector3.ZERO or n.dot(fwd) > -0.5:
		return false
	var inward := -n
	# the top: 0.4 m in from the face, or just behind it for a thin wall
	var probe := Vector3.ZERO
	var top := {}
	var h_top := 0.0
	var thin := false
	for depth in [0.4, 0.12]:
		thin = depth < 0.2
		probe = face + inward * depth
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(probe.x, base.y + 3.0, probe.z), Vector3(probe.x, base.y + 0.2, probe.z))
		q2.exclude = [get_rid()]
		q2.collision_mask = 1
		top = space.intersect_ray(q2)
		if top.is_empty() or top.normal.y < 0.7:
			continue
		h_top = top.position.y - base.y
		if h_top >= 0.45 and h_top <= 2.75:
			break
		top = {}
	if top.is_empty():
		return false
	var cap: CapsuleShape3D = $Body.shape
	var fits := func(p: Vector3) -> bool:
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = cap
		sq.collision_mask = 1
		sq.transform = Transform3D(Basis(), p + Vector3(0, 0.92, 0))
		sq.exclude = [get_rid()]
		return space.intersect_shape(sq, 1).is_empty()
	var stand: Vector3 = Vector3(probe.x, top.position.y + 0.03, probe.z) + inward * 0.12
	var vault := false
	if thin or not fits.call(stand):
		# too narrow to stand on: is there ground just behind it to drop onto?
		var over: Vector3 = face + inward * 1.25
		var q3 := PhysicsRayQueryParameters3D.create(Vector3(over.x, top.position.y + 0.3, over.z), Vector3(over.x, base.y - 1.5, over.z))
		q3.exclude = [get_rid()]
		q3.collision_mask = 1
		var g := space.intersect_ray(q3)
		if g.is_empty() or top.position.y - g.position.y < 0.4:
			return false
		stand = Vector3(over.x, top.position.y + 0.08, over.z)
		if not fits.call(stand + Vector3(0, 0.05, 0)):
			return false
		vault = true
	if not start:
		return true
	climb_a = global_position
	climb_b = stand
	climb_top = top.position.y + (0.08 if vault else 0.03)
	climb_vault = vault
	climb_dur = 0.42 + h_top * 0.28
	climb_t = 0.0
	vel = Vector3.ZERO
	reloading = 0.0
	snd.stop_auto()
	snd.climb()
	return true


func _climb_step(dt: float) -> void:
	climb_t += dt
	var k: float = clamp(climb_t / climb_dur, 0.0, 1.0)
	var up_k: float = smoothstep(0.0, 0.62, k)
	var over_k: float = smoothstep(0.45, 1.0, k)
	var flat := Vector3(climb_a.x, 0, climb_a.z).lerp(Vector3(climb_b.x, 0, climb_b.z), 0.12 * up_k + 0.88 * over_k)
	var y: float = lerp(climb_a.y, climb_top, up_k)
	global_position = Vector3(flat.x, y, flat.z)
	if k >= 1.0:
		climb_t = -1.0
		global_position = climb_b
		vel = Vector3.ZERO
		velocity = Vector3.ZERO


func cycle_view() -> void:
	view = (view + 1) % 3


func _physics_process(dt: float) -> void:
	t += dt
	cover_cool = max(0.0, cover_cool - dt)
	hurt_t = max(0.0, hurt_t - dt)
	groan_t = max(0.0, groan_t - dt)
	pump_t += dt
	quiet_t += dt
	if not dead and quiet_t > 5.0 and hp < 100.0:
		hp = min(100.0, hp + dt * 6.0)
	if dead:
		move_in = Vector2.ZERO
		run_in = false
		firing = false
		aiming = false
		dead_t += dt
		if dead_t > 4.0 and fx.get_parent().mission == null:
			_respawn()
	var w: Dictionary = weapons[wi]
	# ---- movement: camera-relative, speeds that match the clips ----
	if climb_t >= 0.0:
		_climb_step(dt)
	elif cover and not dead:
		_cover_step(dt)
	else:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var m := move_in
		var mag: float = min(1.0, m.length())
		var target := Vector3.ZERO
		if mag > 0.12:
			var md := (fwd * m.y + right * m.x).normalized()
			var fw := m.normalized().y
			# the stick is analogue: a little push is a slow walk, more is faster, all the way is a run,
			# and every speed between (the clip, and how fast it plays, follow the speed)
			var push: float = 1.0 if run_in else clamp((mag - 0.12) / 0.83, 0.0, 1.0)
			var top: float
			if crouch:
				top = CROUCH_RUN
			elif aiming:
				top = AIM_WALK
			else:
				top = RUN_BACK if fw < -0.3 else (RUN_SIDE if fw < 0.5 else RUN)
				if holstered:
					top *= 1.2    # nothing in the hands: a little quicker
			var spd: float = lerp(0.55, top, pow(push, 2.0))     # most of the stick is walking; the run is at its edge
			if leg_t > 0.0:
				spd = min(spd, 1.9)      # a leg wound: no sprinting
			if act_t >= 0.0:
				spd = 0.0
			target = md * spd
			# walking into a wall (or something solid and low) for a moment: take cover against it
			var ch := {}
			if cover_cool <= 0.0 and is_on_floor() and not (aiming or firing) and act_t < 0.0 and not busy():
				var cq := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.55, 0), global_position + Vector3(0, 0.55, 0) + md * 0.85)
				cq.collision_mask = 1
				cq.exclude = [get_rid()]
				ch = get_world_3d().direct_space_state.intersect_ray(cq)
			if not ch.is_empty() and abs(ch["normal"].y) < 0.3 and ch["collider"] is StaticBody3D and ch["collider"].get_meta("kind", "") != "door" \
					and md.dot(-(ch["normal"] as Vector3)) > 0.75:
				touch_t += dt
				if touch_t > 0.28:
					_enter_cover(ch)
			else:
				touch_t = 0.0
		else:
			touch_t = 0.0
		var accel := 9.0 if target.length() > Vector2(vel.x, vel.z).length() else 14.0
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
		_step_up(target, dt)
	speed = Vector2(vel.x, vel.z).length()
	if cover and not (aiming or firing or t - last_shot < 0.6):
		rotation.y = lerp_angle(rotation.y, atan2(-cover_n.x, -cover_n.z), min(1.0, dt * 12.0))    # back to the wall
	elif cover:
		rotation.y = lerp_angle(rotation.y, yaw, min(1.0, dt * 16.0))
	else:
		rotation.y = yaw
	climb_check_t -= dt
	if climb_check_t <= 0.0:
		climb_check_t = 0.25
		can_climb = not busy() and is_on_floor() and _climb_probe(false)
		_probe_action()
	leg_t = max(0.0, leg_t - dt)
	arm_t = max(0.0, arm_t - dt)
	if act_t >= 0.0:
		_act_step(dt)

	# ---- holster, grenade ----
	if hol_t >= 0.0:
		hol_t += dt
		if hol_dir == 1:
			if hol_t * HOL_SPEED >= 2.1:
				holstered = true
			if hol_t * HOL_SPEED >= 3.4:
				hol_t = -1.0
		else:
			if hol_t * DRAW_SPEED >= 0.6:
				holstered = false
			if hol_t * DRAW_SPEED >= 1.5:
				hol_t = -1.0
	if knife_t >= 0.0:
		_knife_step(dt)
	if throw_t >= 0.0:
		throw_t += dt
		var ct := NADE_FROM + throw_t * 1.5
		if ct >= NADE_RELEASE and not thrown:
			_release_grenade()
		if ct >= NADE_END:
			throw_t = -1.0

	# ---- weapons ----
	switching = max(0.0, switching - dt)
	if reloading > 0:
		reloading -= dt
		if reloading <= 0:
			var n: int = min(w["size"] - w["mag"], w["res"])
			w["mag"] += n
			w["res"] -= n
			if infinite and w["res"] < w["size"]:
				w["res"] = w["res0"]   # practice yard: the reserve never runs dry
	if firing and holstered and not busy():
		_start_draw()
	if firing and not busy() and not holstered and (w["auto"] or t - last_shot > 0.35):
		_fire()
	if not firing or reloading > 0 or switching > 0 or w["mag"] <= 0 or busy():
		snd.stop_auto()
	recoil = max(0.0, recoil - dt * 7.0)
	kick_p *= exp(-dt * 13.0)
	shake = max(0.0, shake - dt * 0.8)
	_parts()

	_animate(dt)
	tree.advance(dt)
	_pose_hands()
	_bend_spine(dt)
	place_left_target(skel, ik_tgt, weapons[wi]["gun"], {}, pump_slide())
	_update_camera(dt)
	_footsteps(dt)


var stuck_t := 0.0
## Walking into a low edge (a step, a kerb, the lip of a ramp) and not moving: lift over it if there is room.
func _step_up(target: Vector3, dt: float) -> void:
	var want := Vector2(target.x, target.z).length()
	if want < 0.5 or Vector2(vel.x, vel.z).length() > want * 0.35 or not (is_on_floor() or is_on_wall()):
		stuck_t = 0.0
		return
	stuck_t += dt
	if stuck_t < 0.12:
		return
	stuck_t = 0.0
	var fwd := Vector3(target.x, 0, target.z).normalized() * 0.18
	for h in [0.22, 0.38]:
		var up := Vector3(0, h, 0)
		if not test_move(global_transform, up) and not test_move(global_transform.translated(up), fwd):
			global_position += up + fwd
			return


## Where a round along `dir` through `p` (a point on the body capsule) really hits this skeleton: "head", "torso",
## "limb", or "" when it only passes close by. Bones as capsules round the limbs, chest and head.
const HITBOX := [["Hips", "Spine2", 0.17, "torso"], ["Spine2", "Neck", 0.16, "torso"], ["Neck", "Head", 0.065, "torso"],
	["Head", "HeadTop_End", 0.105, "head"],
	["LeftArm", "LeftForeArm", 0.065, "arm_l"], ["LeftForeArm", "LeftHand", 0.055, "arm_l"],
	["RightArm", "RightForeArm", 0.065, "arm_r"], ["RightForeArm", "RightHand", 0.055, "arm_r"],
	["LeftUpLeg", "LeftLeg", 0.095, "leg_l"], ["LeftLeg", "LeftFoot", 0.07, "leg_l"],
	["RightUpLeg", "RightLeg", 0.095, "leg_r"], ["RightLeg", "RightFoot", 0.07, "leg_r"]]
var hit_point := Vector3.ZERO           # where the last hit_part round entered the body
func hit_part(sk: Skeleton3D, p: Vector3, dir: Vector3) -> String:
	var o := p - dir * 1.0
	var best := ""
	var best_t := INF
	var gt := sk.global_transform
	for hb in HITBOX:
		var ia := sk.find_bone("mixamorig" + hb[0])
		var ib := sk.find_bone("mixamorig" + hb[1])
		if ia < 0:
			continue
		var a: Vector3 = gt * sk.get_bone_global_pose(ia).origin
		var b: Vector3
		if ib >= 0:
			b = gt * sk.get_bone_global_pose(ib).origin
		else:
			b = a + (a - gt * sk.get_bone_global_pose(sk.get_bone_parent(ia)).origin).normalized() * 0.18
		if hb[0] == "Spine2":
			b = a + (b - a) * 0.6      # the upper chest stops short of the neck, so it does not bulge round the chin
		var r := _ray_seg(o, dir, a, b)
		var rad: float = hb[2]
		if r[0] < rad:
			var t_in: float = r[1] - sqrt(rad * rad - r[0] * r[0])    # where the round enters this part
			if t_in < best_t:
				best_t = t_in
				best = hb[3]
	if best != "":
		hit_point = o + dir * best_t
	return best


## Closest approach of the ray o + t*d (t >= 0, d unit) to the segment ab: [distance, t].
func _ray_seg(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Array:
	var u := b - a
	var c := u.dot(u)
	var w := o - a
	var bd := d.dot(u)
	var dd := d.dot(w)
	var s := 0.0
	if c > 1e-8:
		var den := c - bd * bd
		var e := u.dot(w)
		s = clamp((e - bd * dd) / den, 0.0, 1.0) if den > 1e-8 else clamp(e / c, 0.0, 1.0)
	var t: float = max(0.0, (a + u * s - o).dot(d))
	if c > 1e-8:
		s = clamp((o + d * t - a).dot(u) / c, 0.0, 1.0)
		t = max(0.0, (a + u * s - o).dot(d))
	return [(o + d * t - (a + u * s)).length(), t]


## What the ACTION button does here: kick a closed door just ahead, pick up a mission item, or take the gun from a
## dead soldier.
func _probe_action() -> void:
	act_kind = ""
	act_node = null
	act_label = ""
	if busy() or dead:
		return
	var world: Node = fx.get_parent()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	for d in world.doors:
		if is_instance_valid(d) and not d.get_meta("gone", false) and not d.get_meta("open", false):
			var to: Vector3 = d.global_position - global_position
			to.y = 0.0
			if to.length() < 2.0 and fwd.dot(to.normalized()) > 0.45:
				act_kind = "kick"
				act_node = d
				act_label = "KICK"
				return
	# a mission item before a dead man's gun (the Courier's laptop lies by his body)
	if world.mission:
		var it = world.mission.item_near(global_position)
		if it:
			act_kind = "item"
			act_node = it
			act_label = it.get_meta("label", "TAKE")
			return
	for e in world.enemies:
		if e.dead and not e.taken:
			var body: Vector3 = e.skel.global_transform * e.skel.get_bone_global_pose(e.hips_b).origin
			if Vector2(body.x - global_position.x, body.z - global_position.z).length() < 1.6 and abs(body.y - global_position.y) < 1.5:
				act_kind = "take"
				act_node = e
				act_label = "TAKE " + {"ak": "AK", "svd": "SVD", "shotgun": "SHOTGUN", "m4": "M4", "pistol": "PISTOL", "rpg": "RPG"}.get(e.gun, "GUN")
				return
	if cover:
		act_kind = "uncover"
		act_label = "LEAVE"
		return
	# a wall (or something solid and low) just ahead: take cover against it
	if is_on_floor():
		for hy in [1.0, 0.55]:
			var cq := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, hy, 0), global_position + Vector3(0, hy, 0) + fwd * 1.3)
			cq.collision_mask = 1
			cq.exclude = [get_rid()]
			var ch := get_world_3d().direct_space_state.intersect_ray(cq)
			if ch and abs(ch["normal"].y) < 0.3 and ch["collider"] is StaticBody3D and ch["collider"].get_meta("kind", "") != "door":
				act_kind = "cover"
				act_label = "COVER"
				cover_hit = ch
				return


func action() -> void:
	if act_kind == "" or busy():
		return
	if act_kind == "uncover":
		leave_cover()
		return
	if act_kind == "cover":
		_enter_cover(cover_hit)
		return
	act_doing = act_kind
	act_obj = act_node
	act_t = 0.0
	reloading = 0.0
	firing = false
	snd.stop_auto()
	if act_doing == "kick" and is_instance_valid(act_obj):
		var to: Vector3 = act_obj.global_position - global_position
		yaw = atan2(-to.x, -to.z)


func _act_step(dt: float) -> void:
	var t0 := act_t
	act_t += dt
	var at := func(x: float) -> bool: return t0 < x and act_t >= x
	match act_doing:
		"kick":
			if at.call(0.42) and is_instance_valid(act_obj):
				fx.get_parent().kick_door(act_obj, global_position)
				shake = max(shake, 0.25)
			if act_t >= 1.0:
				act_t = -1.0
		"take":
			if at.call(0.45) and is_instance_valid(act_obj):
				act_obj.set_meta("got", act_obj.give_gun())
			if at.call(0.9) and is_instance_valid(act_obj):
				_gain(str(act_obj.get_meta("got", "")))
			if act_t >= 1.25:
				act_t = -1.0
		"item":
			if at.call(0.5) and is_instance_valid(act_obj):
				fx.get_parent().mission.take_item(act_obj)
			if act_t >= 1.0:
				act_t = -1.0


## A gun taken from a dead soldier: a new gun with what is in it and a spare magazine, or two more magazines for one
## already carried.
func _gain(gun: String) -> void:
	for w in weapons:
		if w["gun"] != gun:
			continue
		var ui: Node = fx.get_parent().ui
		if not w.get("own", true):
			w["own"] = true
			w["mag"] = w["size"]
			w["res"] = w["size"]
			ui.pickup_note("+ " + str(w["name"]))
		else:
			w["res"] += int(w["size"]) * 2
			ui.pickup_note("+%d %s ROUNDS" % [int(w["size"]) * 2, str(w["name"])])
		snd.reload(gun)
		return


## The shotgun's pump: back and forward again just after each shot.
func pump_slide() -> float:
	if weapons[wi]["gun"] != "shotgun":
		return 0.0
	return sin(clamp((pump_t - 0.22) / 0.38, 0.0, 1.0) * PI) * 0.075


## Moving parts on both rigs: the pump, and the rocket in the RPG (gone once fired, back after the reload).
func _parts() -> void:
	var slide := pump_slide()
	var loaded: bool = weapons[5]["mag"] > 0
	for set in parts["shotgun"]:
		if set["pump"]:
			set["pump"].position.z = 0.27 - slide
	for set in parts["rpg"]:
		if set["warhead"]:
			set["warhead"].visible = loaded


func _fire() -> void:
	var w: Dictionary = weapons[wi]
	if reloading > 0 or switching > 0 or dead:
		return
	if w.has("last") and t - w["last"] < w["rate"]:
		return
	if w["mag"] <= 0:
		reload()
		return
	var gun: String = w["gun"]
	w["last"] = t
	w["mag"] -= 1
	last_shot = t
	var kk: float = w["kick"] * (0.65 if aiming else 1.0) * (0.75 if crouch else 1.0)
	recoil = min(recoil + (0.45 if w["auto"] else 0.8) * kk, 1.6)
	yaw += randf_range(-0.003, 0.003) * kk
	kick_p += 0.006 * kk
	shake = max(shake, 0.05 * kk if not w["auto"] else 0.0)
	if w["auto"]:
		snd.start_auto(gun)
	elif gun == "pistol":
		snd.pistol()
	else:
		snd.shot(gun)
	# the shot goes through the crosshair (centre of the camera)
	var sp: float = w["spread"] * (1.5 if speed > 2.6 else (1.2 if speed > 0.5 else 1.0)) * (0.6 if crouch else 1.0) * (0.35 if aiming else 1.0) * (1.0 + recoil * 0.6)
	if scope_k > 0.5:
		sp = w["spread"] * (1.0 + recoil * 0.3)
	if arm_t > 0.0:
		sp *= 1.7
	var from := cam.global_position
	var d0 := -cam.global_transform.basis.z
	var mz: Node3D = vm_muzzles[gun] if view == 2 else muzzles[gun]
	var mp := mz.global_position
	fx.muzzle_flash(mp, mz.global_transform.basis.z, gun)
	var world: Node = fx.get_parent()
	world.noise(global_position, 10.0 if gun == "pistol" else (18.0 if w["auto"] else 24.0))   # the SD-9 is suppressed
	if w.has("rocket"):
		# the rocket leaves the tube toward whatever is under the crosshair
		var q := PhysicsRayQueryParameters3D.create(from, from + d0 * 300.0)
		q.exclude = [get_rid()]
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		var aim_at: Vector3 = h.position if not h.is_empty() else from + d0 * 300.0
		var rd: Vector3 = (aim_at - mp).normalized()
		if rd.dot(d0) < 0.8:
			rd = d0
		world.fire_rocket(mp + rd * 0.1, rd, self)
		fx.backblast(mp - mz.global_transform.basis.z * 1.5, -mz.global_transform.basis.z)
		return
	var n: int = w.get("pellets", 1)
	var cone: float = w.get("cone", 0.0)
	for i in n:
		var d := (d0 + Vector3(randf_range(-sp, sp), randf_range(-sp, sp), randf_range(-sp, sp))).normalized()
		if cone > 0.0:
			d = (d + Vector3(randf_range(-cone, cone), randf_range(-cone, cone) * 0.8, randf_range(-cone, cone))).normalized()
		var end: Vector3 = world.shoot_ray(from, d, float(w["dmg"]), self, float(w.get("power", 1.0)))
		if n == 1:
			if int(w["mag"]) % 2 == 0 or not w["auto"]:
				fx.tracer(mp, end, true)
		elif i < 3:
			fx.tracer(mp, end, true)
	if gun == "shotgun":
		pump_t = 0.0
		get_tree().create_timer(0.24).timeout.connect(func(): snd.pump())
		get_tree().create_timer(0.36).timeout.connect(func(): _eject("shotgun"))
	else:
		_eject(gun)


## A spent case out of the ejection port on the right of the receiver (a red shell from the shotgun's pump).
func _eject(gun: String) -> void:
	var g: Node3D = vm_rig["guns"][gun] if view == 2 else guns[gun]
	if not g.is_visible_in_tree():
		return
	var gt := g.global_transform
	var port: Vector3 = gt * (Vector3(-0.02, 0.05, 0.04) if gun != "pistol" else Vector3(-0.01, 0.045, -0.02))
	var right: Vector3 = -gt.basis.x.normalized()
	var v: Vector3 = right * randf_range(2.2, 3.2) + Vector3.UP * randf_range(1.2, 2.0) - gt.basis.z.normalized() * 0.4 + Vector3(vel.x, 0, vel.z)
	fx.casing(port, v, gun)


func _animate(dt: float) -> void:
	var w: Dictionary = weapons[wi]
	var acting := throw_t >= 0.0 or hol_t >= 0.0 or holstered or knife_t >= 0.0
	var doing := act_t >= 0.0
	var aim_now := (aiming or firing or t - last_shot < (0.6 if cover else 2.5)) and not acting and climb_t < 0.0 and not doing
	var moving := speed > 0.25
	var ry := rotation.y
	var local := Vector2(vel.dot(Vector3(cos(ry), 0, -sin(ry))), vel.dot(Vector3(-sin(ry), 0, -cos(ry))))  # x right, y forward
	if moving:
		var fwd_axis := dir == "F" or dir == "B"
		var use_f = abs(local.y) >= abs(local.x) * 0.75 if fwd_axis else abs(local.y) > abs(local.x) * 1.35
		dir = (("F" if local.y >= 0 else "B") if use_f else ("R" if local.x >= 0 else "L"))
	var st := "idle"
	var nat := 0.0
	if dead:
		st = "dead"
	elif doing:
		st = "kick" if act_doing == "kick" else "kneel"
		moving = false
	elif climb_t >= 0.0:
		st = "jump" if climb_t < climb_dur * 0.5 else "kneel"
		moving = false
	elif not is_on_floor() and vel.y > 0.5:
		st = "jump"
	elif moving:
		# (a little hysteresis, so a speed held near the change does not flick between the clips)
		var was_run: bool = state in ["run", "run_b", "run_r", "run_l", "c_run"]
		var run := (speed > (1.25 if was_run else 1.4)) if crouch else (speed > (1.7 if was_run else 1.95))
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
		scale = clamp(speed / nat, 0.5, 1.6)
	elif st == "kneel_aim":
		scale = 1.0 if (firing or t - last_shot < 0.3) else 0.0
	tree.set("parameters/speed/scale", scale)
	# arms and chest: aim pose (or reload) while the legs keep walking; grenade and holster clips over all of it
	var want_up := 1.0 if (moving and (aim_now or reloading > 0) and st != "jump" and not dead) else 0.0
	if reloading > 0 and not moving:
		want_up = 1.0
	if acting and not dead and climb_t < 0.0:
		want_up = 1.0
	if doing:
		want_up = 0.0
	up_w = lerp(up_w, want_up, min(1.0, dt * 9.0))
	rl_w = lerp(rl_w, 1.0 if reloading > 0 else 0.0, min(1.0, dt * 9.0))
	act_w = lerp(act_w, 1.0 if acting else 0.0, min(1.0, dt * 12.0))
	tree.set("parameters/upper/blend_amount", up_w)
	tree.set("parameters/pick/blend_amount", rl_w)
	tree.set("parameters/act/blend_amount", act_w)
	if knife_t >= 0.0:
		tree.set("parameters/acts/blend_amount", -1.0)
		tree.set("parameters/nade_seek/seek_request", KNIFE_FROM + min(knife_t, 0.42) * 1.2)
	elif throw_t >= 0.0:
		tree.set("parameters/acts/blend_amount", -1.0)
		tree.set("parameters/nade_seek/seek_request", NADE_FROM + throw_t * 1.5)
	elif hol_t >= 0.0 and hol_dir == -1:
		tree.set("parameters/acts/blend_amount", 1.0)
		tree.set("parameters/draw_seek/seek_request", min(hol_t * DRAW_SPEED, 1.95))
	elif acting or act_w > 0.01:
		tree.set("parameters/acts/blend_amount", 0.0)
		tree.set("parameters/hol_seek/seek_request", min(hol_t * HOL_SPEED, 3.9) if hol_t >= 0.0 else 3.9)
	# left hand on the gun except while reloading, switching, throwing, slinging or climbing
	var free = reloading > 0 or switching > 0 or dead or acting or climb_t >= 0.0 or doing
	do_w = lerp(do_w, 1.0 if doing else 0.0, min(1.0, dt * 10.0))
	ik_w = lerp(ik_w, 0.0 if free else 1.0, min(1.0, dt * 10.0))
	ik.interpolation = ik_w
	var in_hand := not holstered and throw_t < 0.0 and knife_t < 0.0
	for g in guns:
		guns[g].visible = g == w["gun"] and switching < 0.2 and view != 2 and in_hand
		back_guns[g].visible = g == w["gun"] and holstered
	nade_hand.visible = throw_t >= 0.0 and not thrown and view != 2
	knife_hand.visible = knife_t >= 0.0 and view != 2


var aim_k := 0.0
## Chest. Relaxed: lean a little with the camera pitch. Aiming or firing: turn the chest so the barrel lies on the
## crosshair line whatever the legs are doing (the strafe and run clips twist and tip the hips, which used to
## carry the rifle off to the side and down).
func _bend_spine(dt: float) -> void:
	var aim_now: bool = (aiming or firing or t - last_shot < 2.5) and not dead and not holstered and throw_t < 0.0 and hol_t < 0.0 and climb_t < 0.0 and act_t < 0.0
	aim_k = lerp(aim_k, 1.0 if aim_now else 0.0, min(1.0, dt * 10.0))
	var sk_inv: Basis = skel.global_transform.basis.orthonormalized().inverse()
	var lean: float = clamp(pitch, -0.9, 0.9) * 0.35 * (1.0 - aim_k)
	if abs(lean) > 0.001 and not dead:
		turn_chest(skel, Quaternion((sk_inv * global_transform.basis.x).normalized(), lean))
	aim_chest(skel, aim_dir_now(), aim_k * (1.0 - rl_w) * (1.0 - act_w))


func aim_dir_now() -> Vector3:
	var p := pitch + kick_p
	return Vector3(-sin(yaw) * cos(p), sin(p), -cos(yaw) * cos(p))


func _update_camera(dt: float) -> void:
	var lens := [[2.0, 0.55, 1.6], [1.35, 0.45, 1.62], [0.0, 0.0, 1.62]]
	var cfg: Array = lens[view]
	var tl: float = cfg[0]
	var ts: float = cfg[1]
	var th: float = cfg[2]
	var w: Dictionary = weapons[wi]
	# SVD / RPG: aiming brings the eye to the sight (scope view, any camera)
	var want_scope: bool = aiming and w.has("scope") and not busy() and not holstered and reloading <= 0.0 and switching <= 0.0
	scope_k = move_toward(scope_k, 1.0 if want_scope else 0.0, dt * 5.0)
	var scoped := scope_k > 0.6
	if crouch:
		th -= 0.32
	if aiming and view != 2:
		tl = 0.95
		ts = 0.42
		th += 0.02
	if cover and cover_edge != 0:
		# at the end of a wall the camera goes to the open side, so the corner is not in the way
		var out_dir: Vector3 = Vector3(cover_n.z, 0, -cover_n.x) * cover_edge
		ts = abs(ts) * (1.0 if (out_dir + cover_n).dot(Vector3(cos(yaw), 0, -sin(yaw))) >= 0.0 else -1.0)
	cam_len = lerp(cam_len, tl, min(1.0, dt * 10.0))
	cam_side = lerp(cam_side, ts, min(1.0, dt * 10.0))
	cam_h = lerp(cam_h, th, min(1.0, dt * (14.0 if climb_t >= 0.0 else 8.0)))
	if scoped:
		cam_len = 0.0
		cam_side = 0.0
		cam_h = 1.62 - (0.32 if crouch else 0.0)
	cam_pivot.global_position = global_position + Vector3(0, cam_h, 0)
	var shk := Vector2(sin(t * 37.0), sin(t * 53.0)) * shake * 0.05
	cam_pivot.rotation = Vector3(pitch + kick_p + shk.y, yaw + shk.x, 0)
	# the shoulder offset must not put the camera's arm through a wall beside him
	var side_now := cam_side
	if abs(cam_side) > 0.02:
		var sq := PhysicsRayQueryParameters3D.create(cam_pivot.global_position, cam_pivot.global_position + cam_pivot.global_transform.basis.x * (cam_side + 0.3 * sign(cam_side)))
		sq.collision_mask = 1
		sq.exclude = [get_rid()]
		var sh := get_world_3d().direct_space_state.intersect_ray(sq)
		if sh:
			side_now = sign(cam_side) * max(0.0, cam_pivot.global_position.distance_to(sh["position"]) - 0.3)
	cam_pivot.get_node("Side").position = Vector3(side_now, 0, 0)
	cam_arm.spring_length = cam_len
	var fov := 62.0
	if aiming:
		fov = 50.0
	elif speed > 3.0:
		fov = 66.0
	cam.fov = lerp(cam.fov, fov, min(1.0, dt * 10.0))
	if scoped:
		cam.fov = float(w["scope"])
	var fp := (view == 2 or scoped) and not dead
	# (pressed against a wall the camera can end up right behind his head: do not fill the screen with him)
	model.visible = not fp and not (cam_len > 0.6 and cam_arm.get_hit_length() < 0.45)
	vm.visible = fp and not scoped and not (holstered and act_w > 0.9)
	if vm.visible:
		_update_arms(dt)


func scoped() -> bool:
	return scope_k > 0.6 and not dead


var vm_gun := ""
## First person: the arms rig holds the aim pose (with its slight breathing), the current gun, closed hands;
## lower and to the right from the hip, sights on the eye line when aiming.
func _update_arms(dt: float) -> void:
	var cur: String = weapons[wi]["gun"]
	if cur != vm_gun:
		vm_gun = cur
		start_rig(vm_rig, cur)
	vm_rig["guns"][cur].visible = switching < 0.2 and not holstered and throw_t < 0.0 and knife_t < 0.0
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
	var low: float = max(max(rl_w, act_w), do_w)
	vm.position = hip.lerp(ads, ads_k) + bob + Vector3(0, -0.12 * low - 0.2 * act_w, recoil * 0.03 * (1.0 - ads_k * 0.5))
	vm.rotation = Vector3(recoil * 0.035 - 0.45 * low, 0.07 * (1.0 - ads_k), 0.03 * (1.0 - ads_k))
	place_left_target(vsk, vm_rig["ik_target"], cur, {}, pump_slide())


func _footsteps(dt: float) -> void:
	if not is_on_floor() or speed < 0.3:
		return
	# two footfalls per clip cycle, at the speed the clip is playing
	var clip: String = STATES.get(state, "walk")
	var nat: float = NAT.get(clip, 1.0)
	var length := 1.0
	if ap.has_animation(clip):
		length = max(0.3, ap.get_animation(clip).length)
	stride_t += dt * 2.0 * clamp(speed / nat, 0.5, 1.6) / length
	if stride_t >= 1.0:
		stride_t -= 1.0
		snd.step(speed > 2.4, crouch)
		# boots are heard: a run from some way off, a walk only close by, a slow or crouched walk not at all
		var loud: float = (speed - 1.0) * 3.2 * (0.45 if crouch else 1.0)
		if loud > 1.5:
			fx.get_parent().noise(global_position, loud)


## Hit by an enemy round.
func hit(dmg: float, from: Vector3, part := "") -> void:
	if dead:
		return
	if part.begins_with("leg"):
		leg_t = 12.0
	elif part.begins_with("arm"):
		arm_t = 12.0
	hp -= dmg
	hurt_t = 0.6
	quiet_t = 0.0
	shake = max(shake, 0.2 if dmg < 30.0 else 0.6)
	if groan_t <= 0.0 and hp > 0.0:
		groan_t = 0.12
		snd.hurt(dmg >= 30.0)
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
	grenades = 4
	holstered = false
	act_t = -1.0
	knife_t = -1.0
	leg_t = 0.0
	arm_t = 0.0
	hol_t = -1.0
	throw_t = -1.0
	climb_t = -1.0
	for w in weapons:
		w["mag"] = w["size"]
		w["res"] = w["res0"]
	if fx.get_parent().has_method("on_player_respawn"):
		fx.get_parent().on_player_respawn()


func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z


func _enter_cover(hit: Dictionary) -> void:
	cover = true
	var cn: Vector3 = hit["normal"]
	cover_n = Vector3(cn.x, 0, cn.z).normalized()
	cover_edge = 0
	cover_peek = 0.0
	touch_t = 0.0
	end_t = 0.0
	firing = false


func leave_cover() -> void:
	if cover and cover_low:
		crouch = false
	cover = false
	cover_peek = 0.0
	cover_edge = 0
	cover_cool = 0.7
	touch_t = 0.0


## In cover: held against the wall, sidestepping along it, crouched behind anything lower than his head. To shoot he
## leans out of the nearer end (standing or crouched as he is), the camera on that side; in the middle of something
## low he stands up over it. Pulling the stick away, or pushing on past the end of the wall, leaves cover.
func _cover_step(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var n := cover_n
	var tan := Vector3(n.z, 0, -n.x)
	var ray := func(from: Vector3, to: Vector3) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		return space.intersect_ray(q)
	var base := global_position + n * 0.1
	var wall: Dictionary = ray.call(base + Vector3(0, 0.55, 0), base + Vector3(0, 0.55, 0) - n * 1.7)
	if wall.is_empty() and cover_peek < 0.05:
		leave_cover()
		return
	cover_low = (ray.call(base + Vector3(0, 1.5, 0), base + Vector3(0, 1.5, 0) - n * 1.7) as Dictionary).is_empty()
	var shooting := aiming or firing or throw_t >= 0.0
	# behind something low he stays down; he only stands to shoot when there is no end near to lean round
	if cover_low:
		crouch = not (shooting and cover_edge == 0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var want := fwd * move_in.y + right * move_in.x
	var mag: float = min(1.0, move_in.length())
	if mag > 0.3 and want.normalized().dot(n) > 0.4:
		leave_cover()          # the stick pulled away from the wall
		return
	var along := want.dot(tan)
	# where the wall ends (he can lean out there) and where something stands in the way, each side
	var ends := {}
	var blocked := {}
	var gap := {}        # how far along the wall to its end, each side (99: further than he would lean)
	for sgn in [-1, 1]:
		var ahead: Vector3 = base + tan * (sgn * 0.55) + Vector3(0, 0.55, 0)
		ends[sgn] = (ray.call(ahead, ahead - n * 1.7) as Dictionary).is_empty()
		blocked[sgn] = not (ray.call(base + Vector3(0, 0.55, 0), ahead + n * 0.2) as Dictionary).is_empty()
		gap[sgn] = 99.0
		for st in [0.3, 0.55, 0.8, 1.05, 1.3]:
			var q2: Vector3 = base + tan * (sgn * st) + Vector3(0, 0.55, 0)
			if (ray.call(q2, q2 - n * 1.7) as Dictionary).is_empty():
				gap[sgn] = st
				break
	if cover_peek <= 0.0:
		if gap[-1] < 99.0 and gap[1] < 99.0:
			cover_edge = 1 if fwd.dot(tan) > 0.0 else -1      # a narrow pillar: the side he is looking past
		else:
			cover_edge = -1 if gap[-1] < 99.0 else (1 if gap[1] < 99.0 else 0)
		cover_reach = (float(gap[cover_edge]) + 0.3) if cover_edge != 0 else 0.0
	var v_t := 0.0
	if not shooting:
		if cover_peek > 0.0:       # back in from the lean
			v_t = -float(cover_edge) * 3.0
			cover_peek = max(0.0, cover_peek - 3.0 * dt)
		elif abs(along) > 0.2:
			var sg := 1 if along > 0 else -1
			if not ends[sg] and not blocked[sg]:
				v_t = sg * lerp(0.5, 1.5, clamp((abs(along) - 0.2) / 0.8, 0.0, 1.0))
				end_t = 0.0
			elif ends[sg] and abs(along) > 0.5:
				end_t += dt          # still pushing past the end of the wall: walk on round it
				if end_t > 0.35:
					leave_cover()
					return
		else:
			end_t = 0.0
	elif cover_edge != 0 and cover_peek < cover_reach:
		v_t = float(cover_edge) * 3.5      # step out of the end to shoot
		cover_peek += 3.5 * dt
	var v_n := 0.0
	if not wall.is_empty():
		var off: float = (global_position - (wall["position"] as Vector3)).dot(n)
		v_n = clamp((0.54 - off) * 10.0, -3.0, 3.0)
	vel.x = tan.x * v_t + n.x * v_n
	vel.z = tan.z * v_t + n.z * v_n
	vel.y = 0.0 if is_on_floor() else vel.y - GRAVITY * dt
	velocity = vel
	move_and_slide()
	vel = velocity
