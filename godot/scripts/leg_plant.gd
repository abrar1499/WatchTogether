extends SkeletonModifier3D
## Feet where feet can be. A walking clip is made on the flat: up stairs or a slope the body rides a smooth ramp,
## so the leading foot would go through a step and the other hang over the one below; on a boat's floor or by a
## wall a foot could go into a seat or the wall. After the clip is applied each frame this looks under each foot
## for what it would stand on, lets the hips down as far as the lower foot needs, keeps each foot out of any wall
## between it and the hips, and bends each leg (two-bone, the knee kept on its side) to put the foot there.

var body: CharacterBody3D        # the man (his floor, his capsule, and what to leave out of the rays)
var legs := []                   # [up leg, lower leg, foot] bone numbers, left then right
var hips := -1
var on := 0.0                    # how much of this is applied (eased in and out)
var floor_y := 0.0


func setup(b: CharacterBody3D, sk: Skeleton3D) -> void:
	body = b
	hips = sk.find_bone("mixamorigHips")
	for sd in ["Left", "Right"]:
		legs.append([sk.find_bone("mixamorig%sUpLeg" % sd), sk.find_bone("mixamorig%sLeg" % sd), sk.find_bone("mixamorig%sFoot" % sd)])


func _flag(n: String) -> bool:
	var v = body.get(n)
	return v != null and bool(v)


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	q.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_ray(q)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or body == null or hips < 0 or not body.is_inside_tree():
		return
	floor_y = body.global_position.y
	var want := 0.0
	var ct = body.get("climb_t")
	if body.is_on_floor() and not _flag("dead") and not _flag("prone") and not _flag("down") and (ct == null or float(ct) < 0.0):
		want = 1.0
		# (a man far from the eye: not worth the rays)
		var cam := body.get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(body.global_position) > 28.0:
			want = 0.0
	on = move_toward(on, want, 0.08)
	if on <= 0.001:
		return
	var xf := sk.global_transform
	var inv := xf.affine_inverse()
	var steep := body.get_floor_normal().y < 0.94
	# (a flight of steps is walked on as a smooth slope through the middle of its risers: the treads stand about
	# half a riser above it, so on anything that steep the feet are put that much higher)
	var lift := 0.09 if steep else 0.0
	var hips_w: Vector3 = xf * sk.get_bone_global_pose(hips).origin
	var off := []
	var back := []
	for L in legs:
		var f: Vector3 = xf * sk.get_bone_global_pose(L[2]).origin
		var h := _ray(f + Vector3(0, 0.6, 0), f - Vector3(0, 0.8, 0))
		var g: float = h["position"].y if h else floor_y
		var o: float = clamp(g + lift - floor_y, -0.45, 0.45)
		if abs(o) < 0.03:
			o = 0.0                  # (the flat: leave the clip alone)
		off.append(o * on)
		# a wall between the hips and the foot (at the foot's height): the foot is drawn back out of it
		var from := Vector3(hips_w.x, f.y + 0.06, hips_w.z)
		var to := Vector3(f.x, f.y + 0.06, f.z)
		var dv := to - from
		var pull := Vector3.ZERO
		if dv.length() > 0.08:
			var w := _ray(from, to + dv.normalized() * 0.1)
			if w:
				pull = (w["position"] - dv.normalized() * 0.1) - to
				pull.y = 0.0
		back.append(pull * on)
	# the hips go down as far as the lower foot needs (never up: the clip's own height is the most he stands)
	var drop: float = min(0.0, min(off[0], off[1]))
	var down_local: Vector3 = inv.basis * Vector3(0, drop, 0)
	if drop < 0.0:
		var hp := sk.get_bone_global_pose(hips)
		hp.origin += down_local
		sk.set_bone_global_pose(hips, hp)
	for i in 2:
		if off[i] == 0.0 and drop == 0.0 and back[i] == Vector3.ZERO:
			continue
		var L: Array = legs[i]
		# the leg as the clip has it, the hips now let down (each bone's global pose follows its parent's)
		var up_g := sk.get_bone_global_pose(L[0])
		var lo_g := sk.get_bone_global_pose(L[1])
		var ft_g := sk.get_bone_global_pose(L[2])
		var a := up_g.origin + down_local
		var b := lo_g.origin + down_local
		var c := ft_g.origin + down_local
		var target: Vector3 = c + inv.basis * (Vector3(0, off[i] - drop, 0) + back[i])
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
		sk.set_bone_global_pose(L[0], Transform3D(Basis(r1) * up_g.basis, a))
		var r2 := Quaternion((c - b).normalized(), (tgt - knee).normalized())
		sk.set_bone_global_pose(L[1], Transform3D(Basis(r2) * Basis(r1) * lo_g.basis, knee))
		# the foot keeps the way it was turned by the clip
		sk.set_bone_global_pose(L[2], Transform3D(ft_g.basis, tgt))
