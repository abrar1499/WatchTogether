extends CharacterBody3D
## Practice-yard soldier. Stands guard or walks a short beat; spots the player by sight (in front of him, in the
## open, quicker up close, slower if the player is crouched) or by gunfire; then turns, aims and fires bursts,
## closing in when far and hunting the last place he saw the player when he loses him. Headshots kill at once.
## Dies with one of the Mixamo death clips.

const STATES := {"idle": "idle", "walk": "walk", "run": "run", "aim": "aim", "kneel_aim": "crouchFire", "hit": "hit",
	"die": "die", "dieFront": "dieFront", "dieLeft": "dieLeft", "dieBackHS": "dieBackHS"}
const WALK := 1.15
const RUN := 3.0
const FOV_COS := 0.34          # about 70 degrees either side
const SIGHT_RANGE := 38.0
const COMBAT_RANGE := 60.0

var main: Node
var player: Node
var rig := {}
var skel: Skeleton3D
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var muzzle: Node3D
var body: CollisionShape3D
var cap: CapsuleShape3D
var head_b := -1
var hp := 100.0
var dead := false
var dead_t := 0.0
var home := Vector3.ZERO
var beat := Vector3.ZERO       # the other end of his beat (same as home: stands guard)
var to_beat := true
var wait_t := 2.0
var mode := "guard"            # guard, combat
var alert := 0.0               # 0..1, combat at 1
var sees := false
var last_seen := Vector3.ZERO
var lost_t := 0.0
var seen_t := 0.0              # how long the player has been in sight (his aim settles)
var think_t := 0.0
var grace := 3.0               # no looking for the first seconds of a wave
var shots_left := 0
var shot_t := 0.0
var pause_t := 1.0
var kneels := false
var yaw := 0.0
var state := "idle"
var aim_w := 0.0
var hit_t := 0.0
var vel := Vector3.ZERO
var stuck_t := 0.0
var detour_t := 0.0
var detour_sign := 1.0
var shot_n := 0


func setup(m: Node, pos: Vector3, face: float, beat_pos: Vector3) -> void:
	main = m
	player = m.player
	body = CollisionShape3D.new()
	cap = CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	body.shape = cap
	body.position.y = 0.875
	add_child(body)
	set_meta("surf", "flesh")
	floor_snap_length = 0.3
	global_position = pos
	home = pos
	beat = beat_pos
	yaw = face
	rotation.y = yaw
	kneels = randf() < 0.4
	rig = player.make_rig(Color(0.86, 0.74, 0.58), ["ak"])   # desert-tinted uniform
	add_child(rig["root"])
	skel = rig["skel"]
	muzzle = rig["muzzles"]["ak"]
	head_b = skel.find_bone("mixamorigHead")
	player.start_rig(rig, "ak")
	_build_tree()


func _build_tree() -> void:
	tree = AnimationTree.new()
	rig["root"].add_child(tree)
	tree.anim_player = tree.get_path_to(rig["ap"])
	var sm := AnimationNodeStateMachine.new()
	for st in STATES:
		var an := AnimationNodeAnimation.new()
		an.animation = STATES[st]
		sm.add_node(st, an)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", "idle", start)
	for a in STATES:
		if a.begins_with("die"):
			continue
		for b in STATES:
			if a == b:
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = 0.15 if b.begins_with("die") else 0.25
			tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			sm.add_transition(a, b, tr)
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("loco", sm)
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("speed", ts)
	bt.connect_node("speed", 0, "loco")
	bt.connect_node("output", 0, "speed")
	tree.tree_root = bt
	tree.active = true
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	playback = tree.get("parameters/loco/playback")


func _physics_process(dt: float) -> void:
	if dead:
		dead_t += dt
		if dead_t < 6.0:
			tree.advance(dt)
			player.pose_rig_hands(skel, "ak")
		return
	grace = max(0.0, grace - dt)
	hit_t = max(0.0, hit_t - dt)
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.15
		_perceive(0.15)

	var target_v := Vector3.ZERO
	var face := yaw
	var want_aim := false
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	if mode == "guard":
		if wait_t > 0.0:
			wait_t -= dt
		elif beat.distance_to(home) > 0.5:
			var goal := beat if to_beat else home
			var to := goal - global_position
			to.y = 0.0
			if to.length() < 0.4:
				to_beat = not to_beat
				wait_t = randf_range(2.5, 5.0)
			else:
				target_v = to.normalized() * WALK
				face = atan2(-to.x, -to.z)
	else:
		if sees:
			face = atan2(-to_p.x, -to_p.z)
			if to_p.length() > 28.0:
				target_v = to_p.normalized() * RUN
			else:
				want_aim = true
		else:
			var to_l := last_seen - global_position
			to_l.y = 0.0
			if lost_t > 1.5 and to_l.length() > 1.2:
				target_v = to_l.normalized() * RUN
				face = atan2(-to_l.x, -to_l.z)
			elif lost_t > 10.0:
				mode = "guard"
				alert = 0.5
				wait_t = 1.0
			else:
				want_aim = to_l.length() > 0.5
				if want_aim:
					face = atan2(-to_l.x, -to_l.z)

	# walk round whatever he bumps into
	if detour_t > 0.0:
		detour_t -= dt
		target_v = target_v.rotated(Vector3.UP, detour_sign * PI * 0.5)
		if target_v.length() > 0.1:
			face = atan2(-target_v.x, -target_v.z)
	yaw = lerp_angle(yaw, face, min(1.0, dt * 6.0))
	rotation.y = yaw
	var hv := Vector3(vel.x, 0, vel.z).lerp(target_v, min(1.0, dt * 6.0))
	vel.x = hv.x
	vel.z = hv.z
	if is_on_floor():
		vel.y = 0.0
	else:
		vel.y -= 12.0 * dt
	velocity = vel
	move_and_slide()
	vel = velocity
	var hs := Vector2(vel.x, vel.z).length()
	if target_v.length() > 0.5 and hs < 0.25:
		stuck_t += dt
		if stuck_t > 0.4:
			stuck_t = 0.0
			detour_t = 1.0
			detour_sign = 1.0 if randf() < 0.5 else -1.0
	else:
		stuck_t = 0.0

	# aim and shoot
	var facing_ok: bool = abs(wrapf(face - yaw, -PI, PI)) < 0.35
	aim_w = lerp(aim_w, 1.0 if (want_aim and facing_ok) else 0.0, min(1.0, dt * 5.0))
	if want_aim and sees and aim_w > 0.85 and not player.dead:
		if shots_left > 0:
			shot_t -= dt
			if shot_t <= 0.0:
				_shoot()
				shots_left -= 1
				shot_t = 0.11
				if shots_left == 0:
					pause_t = randf_range(1.0, 2.2)
		else:
			pause_t -= dt
			if pause_t <= 0.0:
				shots_left = randi_range(3, 6)
				shot_t = 0.0
				main.snd.enemy_burst(muzzle.global_position, shots_left)
	else:
		shots_left = 0

	# body
	var st := "idle"
	if hit_t > 0.0 and hs < 0.5:
		st = "hit"
	elif hs > 2.0:
		st = "run"
	elif hs > 0.3:
		st = "walk"
	elif want_aim or mode == "combat":
		st = "kneel_aim" if kneels else "aim"
	if st != state:
		playback.travel(st)
		state = st
		var low := st == "kneel_aim"
		cap.height = 1.2 if low else 1.75
		body.position.y = cap.height * 0.5
	var scale := 1.0
	if st == "walk":
		scale = clamp(hs / 1.0, 0.6, 1.5)
	elif st == "run":
		scale = clamp(hs / 3.16, 0.6, 1.5)
	tree.set("parameters/speed/scale", scale)
	tree.advance(dt)
	player.pose_rig_hands(skel, "ak")
	if aim_w > 0.01:
		var chest: Vector3 = player.global_position + Vector3(0, 0.85 if player.crouch else 1.25, 0)
		if not sees:
			chest = last_seen + Vector3(0, 1.2, 0)
		player.aim_chest(skel, (chest - muzzle.global_position).normalized(), aim_w)
	player.place_left_target(skel, rig["ik_target"], "ak")


func _eye() -> Vector3:
	return global_position + Vector3(0, 1.0 if state == "kneel_aim" else 1.6, 0)


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return h.is_empty() or h.collider == player


func _perceive(dt: float) -> void:
	sees = false
	if player.dead:
		if mode == "combat":
			mode = "guard"
			alert = 0.0
			wait_t = 2.0
		return
	if grace > 0.0:
		return
	var eye := _eye()
	var target: Vector3 = player.global_position + Vector3(0, 0.9 if player.crouch else 1.35, 0)
	var to := target - eye
	var d := to.length()
	if d < (COMBAT_RANGE if mode == "combat" else SIGHT_RANGE):
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var flat := Vector3(to.x, 0, to.z).normalized()
		if (mode == "combat" or fwd.dot(flat) > FOV_COS) and _clear(eye, target):
			sees = true
	if sees:
		lost_t = 0.0
		seen_t += dt
		last_seen = player.global_position
		if mode != "combat":
			var gain := (2.0 if d < 12.0 else 1.0) * (0.55 if player.crouch else 1.0) * (1.4 if player.speed > 2.5 else 1.0)
			alert += dt * gain
			if alert >= 1.0:
				alarm(player.global_position, true)
				main.music.spotted()
	else:
		seen_t = max(0.0, seen_t - dt * 2.0)
		lost_t += dt
		if mode != "combat":
			alert = max(0.0, alert - dt * 0.2)


## Into combat, looking toward pos. Tells the soldiers near him unless they told him.
func alarm(pos: Vector3, spread := false) -> void:
	if dead:
		return
	var was := mode
	mode = "combat"
	alert = 1.0
	last_seen = pos
	lost_t = 0.0 if sees else max(lost_t, 0.5)
	if was != "combat":
		pause_t = max(pause_t, randf_range(1.0, 1.8))
		if spread:
			main.enemy_alarm(self)


func hear(pos: Vector3, radius: float) -> void:
	if dead or grace > 0.0:
		return
	if global_position.distance_to(pos) < radius:
		alarm(pos, true)


func _shoot() -> void:
	var from: Vector3 = muzzle.global_position
	var chest: Vector3 = player.global_position + Vector3(0, 0.85 if player.crouch else 1.25, 0)
	var dir := (chest - from).normalized()
	var d := from.distance_to(chest)
	var sp: float = 0.075 * clamp(1.4 - seen_t * 0.2, 0.5, 1.4)
	sp *= 1.5 if player.speed > 2.5 else 1.0
	sp *= 0.65 if player.crouch else 1.0
	sp *= 0.7 + d / 40.0
	dir = (dir + Vector3(randf_range(-sp, sp), randf_range(-sp, sp) * 0.7, randf_range(-sp, sp))).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 150.0)
	q.exclude = [get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	main.fx.muzzle_flash(from, muzzle.global_transform.basis.z, "ak")
	shot_n += 1
	var end := from + dir * 120.0
	if not h.is_empty():
		end = h.position
		if h.collider == player:
			player.hit(randf_range(4.0, 7.0), global_position)
		elif h.collider and h.collider.has_method("take_hit"):
			pass   # does not shoot his own side
		else:
			main.fx.impact(h.position, h.normal, h.collider)
	if shot_n % 2 == 0:
		main.fx.tracer(from, end)


## Hit by the player. A round whose line passes the head kills at once.
func take_hit(dmg: float, pos: Vector3, dir: Vector3) -> void:
	if dead:
		return
	var head: Vector3 = (skel.global_transform * skel.get_bone_global_pose(head_b)).origin + Vector3(0, 0.07, 0)
	var rel := head - pos
	var along := rel.dot(dir)
	var headshot := along > -0.15 and (rel - dir * along).length() < 0.13
	main.fx.blood(pos, -dir)
	hp -= 999.0 if headshot else dmg
	if hp <= 0.0:
		_die(headshot)
		return
	hit_t = 0.3
	alarm(player.global_position, true)


func _die(headshot: bool) -> void:
	dead = true
	hp = 0.0
	collision_layer = 0
	shots_left = 0
	var clip: String = "dieBackHS" if headshot else ["die", "dieFront", "dieLeft"][randi() % 3]
	playback.travel(clip)
	tree.set("parameters/speed/scale", 1.0)
	rig["ik"].interpolation = 0.0
	main.snd.death(global_position, "head" if headshot else "body")
	main.on_enemy_killed(self, headshot)
