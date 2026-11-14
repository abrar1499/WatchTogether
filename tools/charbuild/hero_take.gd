extends SceneTree
## The hero (Mixamo "Ch15") in full detail for the game: each of its two surfaces as a mesh of its own (the game
## gives each its own material), in the soldier's units (centimetres), with the names of the bones its vertices
## follow (the game binds them to the soldier's own skeleton). Writes out/hero_<surface>.res.
func _init() -> void:
	var sc: Node3D = load("res://src/Ch15_nonPBR.fbx").instantiate()
	root.add_child(sc)
	var sk: Skeleton3D = sc.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = sc.find_children("*", "MeshInstance3D", true, false)[0]
	var skin: Skin = mi.skin
	print("mesh xf ", mi.transform, " skel xf ", sk.transform, " binds ", skin.get_bind_count(), " named ", skin.get_bind_name(0))
	var hb := -1
	for i in skin.get_bind_count():
		if str(skin.get_bind_name(i)).ends_with("Hips") or skin.get_bind_bone(i) == 0:
			hb = i
			break
	if hb >= 0:
		var bi := skin.get_bind_bone(hb) if skin.get_bind_bone(hb) >= 0 else sk.find_bone(skin.get_bind_name(hb))
		print("hips bind ", skin.get_bind_pose(hb).origin, " vs inverse rest ", sk.get_bone_global_rest(bi).affine_inverse().origin)
	var names := PackedStringArray()
	var poses := []
	for i in skin.get_bind_count():
		var bp: Transform3D = skin.get_bind_pose(i)
		poses.append(Transform3D(bp.basis, bp.origin * 100.0))     # (in centimetres, as the mesh)
		var n := str(skin.get_bind_name(i))
		if n == "":
			n = sk.get_bone_name(skin.get_bind_bone(i))
		names.append(n.replace("mixamorig_", "mixamorig"))
	var K := 100.0
	var m: ArrayMesh = mi.mesh
	DirAccess.make_dir_recursive_absolute("res://out")
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = v[i] * K
		a[Mesh.ARRAY_VERTEX] = v
		# (the game's textures for him are stored upside down, as the soldier's own model has them: so are his UVs)
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		for i in uv.size():
			uv[i] = Vector2(uv[i].x, 1.0 - uv[i].y)
		a[Mesh.ARRAY_TEX_UV] = uv
		var flags := m.surface_get_format(s)
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags & ~Mesh.ARRAY_FORMAT_VERTEX & ~Mesh.ARRAY_FORMAT_NORMAL & ~Mesh.ARRAY_FORMAT_TANGENT & ~Mesh.ARRAY_FORMAT_TEX_UV & ~Mesh.ARRAY_FORMAT_INDEX & ~Mesh.ARRAY_FORMAT_BONES & ~Mesh.ARRAY_FORMAT_WEIGHTS & ~Mesh.ARRAY_FORMAT_COLOR & ~Mesh.ARRAY_FORMAT_TEX_UV2 & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS))
		var nm := str(m.surface_get_material(s).resource_name)
		am.set_meta("binds", names)
		am.set_meta("poses", poses)
		am.resource_name = nm
		print("surface ", s, " ", nm, " verts ", v.size(), " tris ", (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, " 8 weights ", (flags & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0, " aabb ", am.get_aabb())
		print("saved ", ResourceSaver.save(am, "res://out/hero_%s.res" % nm, ResourceSaver.FLAG_COMPRESS))
	quit()
