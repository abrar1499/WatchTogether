extends SceneTree
## Turn Mixamo animation files (FBX, "without skin") into one library of clips for the game's soldier.
##
## To run: in an empty Godot 4.3 project put the FBX files and the game's soldier.glb in src/, import
## (godot --headless --path . --import), then godot --headless --path . -s anim_take.gd. Writes out/extra.res,
## which goes to godot/assets/anims/extra.res. Each clip's tracks are pointed at the soldier's skeleton, its hips'
## travel is put in the soldier's units (centimetres), and a clip that walks away from where it began is held in
## place (the game moves the body itself): [file, clip name, loops, hold in place sideways/forward, and upward].
const CLIPS := [
	["Stabbing", "stab", false, false, false],
	["Stabbing_1", "stab2", false, false, false],
	["Throw_Grenade", "proneNade", false, false, false],
]


func _init() -> void:
	var soldier: Node3D = load("res://src/soldier.glb").instantiate()
	var ssk: Skeleton3D = soldier.find_children("*", "Skeleton3D", true, false)[0]
	var sap: AnimationPlayer = soldier.find_child("AnimationPlayer", true, false)
	var base := str(sap.get_animation("idle").track_get_path(0)).get_slice(":", 0)
	var lib := AnimationLibrary.new()
	for c in CLIPS:
		var sc: Node3D = load("res://src/%s.fbx" % c[0]).instantiate()
		var sk: Skeleton3D = sc.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = sc.find_child("AnimationPlayer", true, false)
		var src: Animation = ap.get_animation(ap.get_animation_list()[0])
		var k: float = ssk.get_bone_rest(ssk.find_bone("mixamorigHips")).origin.y / sk.get_bone_rest(sk.find_bone("mixamorig_Hips")).origin.y
		# how far the two skeletons' resting poses differ (they should not: both are the same Mixamo character)
		var worst := 0.0
		for b in sk.get_bone_count():
			var sb := ssk.find_bone(sk.get_bone_name(b).replace("mixamorig_", "mixamorig"))
			if sb >= 0:
				worst = max(worst, sk.get_bone_rest(b).basis.get_rotation_quaternion().angle_to(ssk.get_bone_rest(sb).basis.get_rotation_quaternion()))
		var a := Animation.new()
		a.length = src.length
		a.loop_mode = Animation.LOOP_LINEAR if c[2] else Animation.LOOP_NONE
		for i in src.get_track_count():
			var bone := str(src.track_get_path(i)).get_slice(":", 1).replace("mixamorig_", "mixamorig")
			var ty := src.track_get_type(i)
			if ssk.find_bone(bone) < 0 or ty == Animation.TYPE_SCALE_3D:
				continue
			if ty == Animation.TYPE_POSITION_3D and bone != "mixamorigHips":
				continue
			var t := a.add_track(ty)
			a.track_set_path(t, NodePath(base + ":" + bone))
			var n := src.track_get_key_count(i)
			var first = src.track_get_key_value(i, 0)
			var last = src.track_get_key_value(i, n - 1)
			for key in n:
				var tm := src.track_get_key_time(i, key)
				var v = src.track_get_key_value(i, key)
				if ty == Animation.TYPE_POSITION_3D:
					var p: Vector3 = v
					var f: float = tm / src.length
					if c[3]:
						p.x -= (last.x - first.x) * f
						p.z -= (last.z - first.z) * f
					if c[4]:
						p.y -= (last.y - first.y) * f
					a.position_track_insert_key(t, tm, p * k)
				else:
					a.rotation_track_insert_key(t, tm, v)
		lib.add_animation(c[1], a)
		# when the right hand is furthest forward of the hips and when it moves fastest (to time a stab or a
		# throw by): the chain from hips to hand worked out from the clip's own keys
		var chain := ["Hips", "Spine", "Spine1", "Spine2", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
		var tr := {}
		for i in src.get_track_count():
			if src.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				tr[str(src.track_get_path(i)).get_slice(":", 1)] = i
		var best_t := 0.0
		var best_z := -INF
		var fast_t := 0.0
		var fast := 0.0
		var prev := Vector3.ZERO
		for s in int(src.length * 30.0):
			var x := Transform3D.IDENTITY
			for bn in chain:
				var b := sk.find_bone("mixamorig_" + bn)
				var rot: Quaternion = src.rotation_track_interpolate(tr["mixamorig_" + bn], s / 30.0) if tr.has("mixamorig_" + bn) else sk.get_bone_rest(b).basis.get_rotation_quaternion()
				x = x * Transform3D(Basis(rot), sk.get_bone_rest(b).origin if bn != "Hips" else Vector3.ZERO)
			var hp := x.origin
			if hp.z > best_z:
				best_z = hp.z
				best_t = s / 30.0
			if s > 0 and hp.distance_to(prev) * 30.0 > fast:
				fast = hp.distance_to(prev) * 30.0
				fast_t = s / 30.0
			prev = hp
		var diff := []
		for b in sk.get_bone_count():
			var sb := ssk.find_bone(sk.get_bone_name(b).replace("mixamorig_", "mixamorig"))
			if sb >= 0 and sk.get_bone_rest(b).basis.get_rotation_quaternion().angle_to(ssk.get_bone_rest(sb).basis.get_rotation_quaternion()) > 0.02:
				diff.append(sk.get_bone_name(b).replace("mixamorig_", ""))
		print("%-22s -> %-10s %.2f s; right hand furthest forward at %.2f s (%.2f m), fastest at %.2f s (%.1f m/s); rests differ: %s" % [c[0], c[1], src.length, best_t, best_z, fast_t, fast, str(diff) if c[1] == "stab" else str(diff.size())])
		sc.queue_free()
	DirAccess.make_dir_recursive_absolute("res://out")
	print("saved ", ResourceSaver.save(lib, "res://out/extra.res", ResourceSaver.FLAG_COMPRESS))
	quit()
