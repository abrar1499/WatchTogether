extends Node
## Diagnostics: gun direction in the aim pose, body/camera drift while crouch-walking and firing.
var main: Node
func run() -> void:
	var p = main.player
	await get_tree().create_timer(0.5).timeout
	p.aiming = true
	await get_tree().create_timer(1.0).timeout
	for k in ["ak", "m4", "pistol"]:
		while p.weapons[p.wi]["gun"] != k:
			p.switching = 0
			p.swap()
		await get_tree().create_timer(0.8).timeout
		var g: Node3D = p.guns[k]
		var gz: Vector3 = g.global_transform.basis.z.normalized()
		var cf: Vector3 = -p.cam.global_transform.basis.z
		print("AIM %s gun+Z=%s camfwd=%s angle=%.1f deg  gunpos-rel=%s" % [k, gz, cf, rad_to_deg(gz.angle_to(cf)), p.to_local(g.global_position)])
		var sk: Skeleton3D = p.skel
		var rh: int = sk.find_bone("mixamorigRightHand")
		var lh: int = sk.find_bone("mixamorigLeftHand")
		var rp: Vector3 = (sk.global_transform * sk.get_bone_global_pose(rh)).origin
		var lp: Vector3 = (sk.global_transform * sk.get_bone_global_pose(lh)).origin
		print("   right->left hand dir=%s" % [(lp - rp).normalized()])
	for pt in [0.4, -0.4, 0.0]:
		p.pitch = pt
		await get_tree().create_timer(0.6).timeout
		var g2: Node3D = p.guns[p.weapons[p.wi]["gun"]]
		var gz2: Vector3 = g2.global_transform.basis.z.normalized()
		var cf2: Vector3 = -p.cam.global_transform.basis.z
		print("PITCH %.1f gun+Z=%s camfwd=%s angle=%.1f" % [pt, gz2, cf2, rad_to_deg(gz2.angle_to(cf2))])
	while p.weapons[p.wi]["gun"] != "ak":
		p.switching = 0
		p.swap()
	await get_tree().create_timer(0.8).timeout
	# side and front views of the aim pose
	var c: Camera3D = Camera3D.new()
	main.add_child(c)
	c.global_position = p.global_position + Vector3(2.2, 1.4, -0.6)
	c.look_at(p.global_position + Vector3(0, 1.3, -0.3))
	c.current = true
	await get_tree().create_timer(0.2).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-WatchTogether/40bcd566-ec1f-5bf7-ab9b-57c38d046531/scratchpad/aim_side.png")
	c.global_position = p.global_position + Vector3(-1.2, 1.5, -2.4)
	c.look_at(p.global_position + Vector3(0, 1.3, 0))
	await get_tree().create_timer(0.2).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-WatchTogether/40bcd566-ec1f-5bf7-ab9b-57c38d046531/scratchpad/aim_front.png")
	p.aiming = false
	await get_tree().create_timer(2.8).timeout
	c.global_position = p.global_position + Vector3(2.2, 1.4, -0.6)
	c.look_at(p.global_position + Vector3(0, 1.1, -0.3))
	await get_tree().create_timer(0.2).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-WatchTogether/40bcd566-ec1f-5bf7-ab9b-57c38d046531/scratchpad/idle_side.png")
	c.current = false
	p.cam.current = true
	p.toggle_crouch()
	await get_tree().create_timer(1.0).timeout
	p.move_in = Vector2(0, 0.6)
	var hips: int = p.skel.find_bone("mixamorigHips")
	for i in 30:
		if i == 15:
			p.firing = true
		await get_tree().create_timer(0.1).timeout
		var hp: Vector3 = p.to_local((p.skel.global_transform * p.skel.get_bone_global_pose(hips)).origin)
		var cl: Vector3 = p.to_local(p.cam.global_position)
		print("t=%.1f state=%s pos=%s hips_local=(%.2f,%.2f,%.2f) cam_local=(%.2f,%.2f,%.2f) arm=%.2f pitch=%.3f vel=%.2f" % [i * 0.1, p.state, p.global_position.snapped(Vector3.ONE * 0.01), hp.x, hp.y, hp.z, cl.x, cl.y, cl.z, p.cam_arm.get_hit_length(), p.pitch, p.speed])
	p.firing = false
	get_tree().quit()
