extends SceneTree
## Offline: turn Poly Haven's modular facade kit (CC0) into light game pieces.
## kit_lod.py has already simplified the pieces (hi = near, lo = far); this drops the unused
## vertices and saves res://assets/city/kit/<name>.res and <name>_lo.res, surfaces named by material (no materials
## kept, so the game needs only these files and the textures; city.gd makes the materials).
const SRC := "res://assets/city/facade/modular_urban_apartments_facade_%s.gltf"
const OUT := "res://assets/city/kit/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for level in ["hi", "lo"]:
		_bake(level)
	quit()

func _bake(level: String) -> void:
	var root: Node = (load(SRC % level) as PackedScene).instantiate()
	var tot_in := 0
	var tot_out := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var name: String = mi.name
		var mesh: ArrayMesh = mi.mesh
		var out := ArrayMesh.new()
		var line := name + ":"
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var mat: Material = mesh.surface_get_material(s)
			var mname := mat.resource_name if mat else "x"
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var best := idx
			var tris_in := idx.size() / 3
			tot_in += tris_in
			tot_out += best.size() / 3
			line += " %s %d->%d" % [mname.replace("modular_urban_apartments_facade_", ""), tris_in, best.size() / 3]
			# compact vertices to the ones still used
			var remap := {}
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var uvs := PackedVector2Array()
			var tans := PackedFloat32Array()
			var V: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var N: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var U: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var T = arrays[Mesh.ARRAY_TANGENT]
			var ni := PackedInt32Array()
			for i in best:
				if not remap.has(i):
					remap[i] = verts.size()
					verts.append(V[i])
					norms.append(N[i])
					uvs.append(U[i])
					if T != null and T.size() > 0:
						tans.append_array([T[i * 4], T[i * 4 + 1], T[i * 4 + 2], T[i * 4 + 3]])
				ni.append(remap[i])
			var a := []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = verts
			a[Mesh.ARRAY_NORMAL] = norms
			a[Mesh.ARRAY_TEX_UV] = uvs
			if tans.size() > 0:
				a[Mesh.ARRAY_TANGENT] = tans
			a[Mesh.ARRAY_INDEX] = ni
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			out.surface_set_name(s, mname.replace("modular_urban_apartments_facade_", ""))
		ResourceSaver.save(out, OUT + name + ("_lo" if level == "lo" else "") + ".res", ResourceSaver.FLAG_COMPRESS)
		if level == "hi" or name.begins_with("window_c"):
			print(level, " ", line)
	print("TOTAL ", level, " ", tot_out)
	root.free()
