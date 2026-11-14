extends SceneTree
## Pack swell_bake.py's frames into the texture the water reads: godot --headless -s swell_pack.gd -- in.bin out.res


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var raw := FileAccess.get_file_as_bytes(args[0]).to_float32_array()
	var n := 128
	# (one tall picture, the frames one under another: a picture keeps its numbers when saved; the game cuts it
	# into the layers of a texture array when the mission is built)
	var img := Image.create_from_data(n, n * 20, false, Image.FORMAT_RGBF, raw.to_byte_array())
	img.convert(Image.FORMAT_RGBH)
	print("saved ", ResourceSaver.save(img, args[1], ResourceSaver.FLAG_COMPRESS), " ", args[1])
	quit()
