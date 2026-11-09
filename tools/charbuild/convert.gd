extends SceneTree
## Shrinks a Mixamo character for the game: about half the triangles (Godot's own simplifier, skin weights kept),
## 1024 px textures, eyelash cards dropped, bones renamed mixamorig_X -> mixamorigX, no animations; written as GLB.
const TARGET := {"Ch35_nonPBR": 0.5, "Ch49_nonPBR": 0.45, "Swat": 1.0}
const OUTNAME := {"Ch35_nonPBR": "gasmask", "Ch49_nonPBR": "olive", "Swat": "blue"}

func tex(t: Texture2D, size: int) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path(t.resource_path))
	if img.get_width() > size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	return ImageTexture.create_from_image(img)

func compact(arrays: Array, idx: PackedInt32Array, wpv: int) -> Array:
	var vc: int = arrays[Mesh.ARRAY_VERTEX].size()
	var remap := PackedInt32Array()
	remap.resize(vc)
	remap.fill(-1)
	var order := PackedInt32Array()
	for i in idx:
		if remap[i] < 0:
			remap[i] = order.size()
			order.append(i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var src = arrays[a]
		if src == null or a == Mesh.ARRAY_INDEX or (a >= Mesh.ARRAY_CUSTOM0 and a <= Mesh.ARRAY_CUSTOM3):
			continue
		var per := 1
		if a == Mesh.ARRAY_TANGENT:
			per = 4
		elif a == Mesh.ARRAY_BONES or a == Mesh.ARRAY_WEIGHTS:
			per = wpv
		var dst = src.duplicate()
		dst.resize(order.size() * per)
		for n in order.size():
			for k in per:
				dst[n * per + k] = src[order[n] * per + k]
		out[a] = dst
	var ni := PackedInt32Array()
	ni.resize(idx.size())
	for i in idx.size():
		ni[i] = remap[idx[i]]
	out[Mesh.ARRAY_INDEX] = ni
	return out

func _init() -> void:
	for f in TARGET:
		var sc: Node3D = load("res://src/%s.fbx" % f).instantiate()
		root.add_child(sc)
		for ap in sc.find_children("*", "AnimationPlayer", true, false):
			ap.get_parent().remove_child(ap)
			ap.free()
		var sk: Skeleton3D = sc.find_children("*", "Skeleton3D", true, false)[0]
		for b in sk.get_bone_count():
			sk.set_bone_name(b, sk.get_bone_name(b).replace("mixamorig_", "mixamorig"))
		var tris := 0
		for m in sc.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m
			if mi.skin:
				for bi in mi.skin.get_bind_count():
					mi.skin.set_bind_name(bi, mi.skin.get_bind_name(bi).replace("mixamorig_", "mixamorig"))
			var old: Mesh = mi.mesh
			var nm := ArrayMesh.new()
			for si in old.get_surface_count():
				var mat = old.surface_get_material(si)
				if mat and str(mat.resource_name).to_lower().contains("eyelash"):
					continue
				var arrays := old.surface_get_arrays(si)
				var fmt: int = old.surface_get_format(si)
				var wpv := 8 if (fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var want: int = int(idx.size() * TARGET[f])
				if TARGET[f] < 1.0:
					var im := ImporterMesh.new()
					im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
					im.generate_lods(25.0, 60.0, [])
					var best := idx
					for l in im.get_surface_lod_count(0):
						var li: PackedInt32Array = im.get_surface_lod_indices(0, l)
						if abs(li.size() - want) < abs(best.size() - want):
							best = li
					idx = best
				arrays = compact(arrays, idx, wpv)
				var nmat := StandardMaterial3D.new()
				nmat.resource_name = mat.resource_name if mat else "skin"
				if mat is StandardMaterial3D:
					if mat.albedo_texture:
						nmat.albedo_texture = tex(mat.albedo_texture, 1024)
					if mat.normal_texture:
						nmat.normal_enabled = true
						nmat.normal_texture = tex(mat.normal_texture, 1024)
				nmat.roughness = 0.85
				nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
				nm.surface_set_material(nm.get_surface_count() - 1, nmat)
				tris += idx.size() / 3
			mi.mesh = nm
		for n in sc.find_children("*", "", true, false):
			n.owner = sc
		var doc := GLTFDocument.new()
		doc.image_format = "JPEG"
		doc.lossy_quality = 0.82
		var st := GLTFState.new()
		var err: int = doc.append_from_scene(sc, st)
		var path := "res://out/%s.glb" % OUTNAME[f]
		err = doc.write_to_filesystem(st, path)
		print("%s -> %s  triangles=%d  err=%d  size=%d KB" % [f, path, tris, err, FileAccess.get_file_as_bytes(path).size() / 1024])
	quit()
