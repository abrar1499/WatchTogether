extends SkeletonModifier3D
## Feet on steps: going up or down stairs or a slope the body rides a smooth ramp, so a walking clip made on the flat
## would put the leading foot through a step and leave the other hanging over the one below. After the clip is
## applied each frame, this looks down under each foot for what it would stand on, lets the hips down as far as
## the lower foot needs, and bends each leg (two-bone, the knee kept on its side) to put the foot there.

var body: CharacterBody3D        # the man (his floor, his capsule, and what to leave out of the rays)
var legs := []                   # [up leg, lower leg, foot] bone numbers, left then right
var hips := -1
var on := 0.0                    # how much of this is applied (eased in on slopes and steps, out on the flat)
var floor_y := 0.0


func setup(b: CharacterBody3D, sk: Skeleton3D) -> void:
	body = b
	hips = sk.find_bone("mixamorigHips")
	for sd in ["Left", "Right"]:
		legs.append([sk.find_bone("mixamorig%sUpLeg" % sd), sk.find_bone("mixamorig%sLeg" % sd), sk.find_bone("mixamorig%sFoot" % sd)])


func _ground(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.6, 0), at - Vector3(0, 0.8, 0))
	q.collision_mask = 1
	q.exclude = [body.get_rid()]
	var h := body.get_world_3d().direct_space_state.intersect_ray(q)
	return h["position"].y if h else floor_y


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or body == null or hips < 0:
		return
	floor_y = body.global_position.y
	var want := 0.0
	if body.is_on_floor() and not body.get("dead") and not body.get("prone") and body.get("climb_t") < 0.0:
		want = 1.0 if body.get_floor_normal().y < 0.985 else 0.0
	on = move_toward(on, want, 0.08)
	if on <= 0.001:
		return
	var xf := sk.global_transform
	var inv := xf.affine_inverse()
	# where each foot's floor is, against the floor under the man himself (up a step: more; down one: less)
	# (a flight of steps is walked on as a smooth slope through the middle of its risers: the treads stand about
	# half a riser above it, so on anything that steep the feet are put that much higher)
	var lift := 0.09 if body.get_floor_normal().y < 0.94 else 0.0
	var off := []
	for L in legs:
		var f: Vector3 = xf * sk.get_bone_global_pose(L[2]).origin
		off.append(clamp(_ground(f) + lift - floor_y, -0.45, 0.45) * on)
	# the hips go down as far as the lower foot needs (never up: the clip's own height is the most he stands)
	var drop: float = min(0.0, min(off[0], off[1]))
	var hp := sk.get_bone_global_pose(hips)
	var down_local: Vector3 = inv.basis * Vector3(0, drop, 0)
	hp.origin += down_local
	sk.set_bone_global_pose(hips, hp)
	for i in 2:
		var L: Array = legs[i]
		# the leg as the clip has it, the hips now let down (each bone's global pose follows its parent's)
		var up_g := sk.get_bone_global_pose(L[0])
		var lo_g := sk.get_bone_global_pose(L[1])
		var ft_g := sk.get_bone_global_pose(L[2])
		var a := up_g.origin + down_local
		var b := lo_g.origin + down_local
		var c := ft_g.origin + down_local
		var target: Vector3 = c + inv.basis * Vector3(0, off[i] - drop, 0)
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var d: float = clamp(a.distance_to(target), abs(l1 - l2) + 0.001, l1 + l2 - 0.001)
		var to_t := (target - a).normalized()
		# the knee: in the plane of the leg and the way the knee already points
		var bend := (b - a) - to_t * (b - a).dot(to_t)
		if bend.length() < 0.0001:
			bend = inv.basis * Vector3(0, 0, -1)
		bend = bend.normalized()
		var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(max(l1 * l1 - x * x, 0.0))
		var knee := a + to_t * x + bend * h
		var tgt := a + to_t * d
		# turn the upper leg so its knee comes to the new place, then the lower leg so the foot does
		var r1 := Quaternion((b - a).normalized(), (knee - a).normalized())
		var up_new := Transform3D(Basis(r1) * up_g.basis, a)
		sk.set_bone_global_pose(L[0], up_new)
		var r2 := Quaternion((c - b).normalized(), (tgt - knee).normalized())
		var lo_new := Transform3D(Basis(r2) * Basis(r1) * lo_g.basis, knee)
		sk.set_bone_global_pose(L[1], lo_new)
		# the foot keeps the way it was turned by the clip
		sk.set_bone_global_pose(L[2], Transform3D(ft_g.basis, tgt))
