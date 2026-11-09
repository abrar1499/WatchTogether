extends CharacterBody3D
## Practice-yard soldier. Stands guard or walks a short beat; spots the player by sight (in front of him, in the
## open, quicker up close, slower if the player is crouched) or by gunfire. In a fight he does not stand still:
## a burst or two from one spot, then he moves to another (cover he can shoot over if there is some, working
## round to one side), ducks behind cover between bursts and pops up to fire, and moves at once when hit.
## Closes in when far, hunts the last place he saw the player when he loses him. Headshots kill at once.
## A shot from close up (or a heavy round) throws him back off his feet; an explosion throws him further. He runs
## from a grenade that lands near him, and some carry one to throw where they last saw the player hiding.

const STATES := {"idle": "idle", "walk": "walk", "run": "run", "aim": "aim", "kneel_aim": "crouchFire", "kneel": "kneel", "hit": "hit",
	"react": "reactBig", "nade": "grenade",
	"die": "die", "dieFront": "dieFront", "dieLeft": "dieLeft", "dieBackHS": "dieBackHS", "dieKnock": "knockback", "dieBlast": "blastback"}
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
var moving := false            # relocating to `spot`
var spot := Vector3.ZERO
var move_t := 0.0
var hold_t := 2.0              # time left at the current spot
var spot_cover := false        # the spot has cover he can shoot over
var peek_up := true            # standing up to fire (else ducked behind the cover)
var peek_t := 0.0
var flank := 1.0               # which way he works round the player
var perch := false             # posted on the roof: holds his place behind the parapet
var react_t := 0.0             # staggered by a heavy hit
var grunt_t := 0.0
var flee_t := 0.0              # running from a grenade
var has_nade := false
var nade_t := -1.0             # throwing his grenade: time into it
var nade_at := Vector3.ZERO
var nade_out := false


func setup(m: Node, pos: Vector3, face: float, beat_pos: Vector3, kind := "gasmask") -> void:
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
	perch = pos.y > 1.5
	if perch:
		kneels = true
	has_nade = randf() < 0.5
	flank = 1.0 if randf() < 0.5 else -1.0
	hold_t = randf_range(1.5, 3.0)
	rig = player.make_rig(Color(0.86, 0.74, 0.58) if kind == "soldier" else Color(1, 1, 1), ["ak"], false, kind)
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
			if b == "dieKnock" or b == "dieBlast":
				tr.xfade_time = 0.08
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
			player.pose_rig_hands(skel, "ak", rig["data"])
		return
	grace = max(0.0, grace - dt)
	hit_t = max(0.0, hit_t - dt)
	react_t = max(0.0, react_t - dt)
	grunt_t = max(0.0, grunt_t - dt)
	flee_t = max(0.0, flee_t - dt)
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
		var dist := to_p.length()
		if sees and dist > 30.0:
			moving = false
			target_v = to_p.normalized() * RUN
			face = atan2(-to_p.x, -to_p.z)
		elif sees or (moving and lost_t < 2.5):
			if moving:
				var to_s := spot - global_position
				to_s.y = 0.0
				move_t += dt
				if to_s.length() < 0.45 or move_t > 5.0:
					moving = false
					hold_t = randf_range(2.0, 4.0)
					peek_up = true
					peek_t = randf_range(1.4, 2.4)
				else:
					target_v = to_s.normalized() * (RUN if to_s.length() > 1.8 else WALK * 1.3)
					face = atan2(-target_v.x, -target_v.z)
			else:
				face = atan2(-to_p.x, -to_p.z)
				hold_t -= dt
				if spot_cover:
					peek_t -= dt
					if peek_t <= 0.0 and shots_left == 0:
						peek_up = not peek_up
						peek_t = randf_range(1.4, 2.6) if peek_up else randf_range(0.7, 1.4)
				want_aim = peek_up or not spot_cover
				if hold_t <= 0.0 and shots_left == 0:
					_relocate()
		else:
			moving = false
			spot_cover = false
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

	if flee_t > 0.0:
		var to_f := spot - global_position
		to_f.y = 0.0
		if to_f.length() > 0.4:
			target_v = to_f.normalized() * RUN
			face = atan2(-to_f.x, -to_f.z)
		want_aim = false
	elif mode == "combat" and nade_t < 0.0 and has_nade and not sees and not moving and lost_t > 2.0 and lost_t < 9.0 and not player.dead:
		var dl := last_seen.distance_to(global_position)
		if dl > 6.0 and dl < 24.0 and randf() < dt * 0.6:
			nade_t = 0.0
			nade_out = false
			has_nade = false
			nade_at = last_seen + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	if nade_t >= 0.0:
		nade_t += dt
		var to_n := nade_at - global_position
		face = atan2(-to_n.x, -to_n.z)
		target_v = Vector3.ZERO
		want_aim = false
		if nade_t >= 0.85 and not nade_out:
			nade_out = true
			_throw_nade()
		if nade_t >= 1.7:
			nade_t = -1.0
			rig["guns"]["ak"].visible = true
	if perch or react_t > 0.0:
		target_v = Vector3.ZERO
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
					pause_t = randf_range(0.7, 1.6)
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
	if nade_t >= 0.0:
		st = "nade"
	elif react_t > 0.0:
		st = "react"
	elif hit_t > 0.0 and hs < 0.5:
		st = "hit"
	elif hs > 2.0:
		st = "run"
	elif hs > 0.3:
		st = "walk"
	elif mode == "combat" and spot_cover and not peek_up:
		st = "kneel"
	elif want_aim or mode == "combat":
		st = "kneel_aim" if (kneels and not spot_cover) else "aim"
	if st != state:
		playback.travel(st)
		state = st
		var low := st == "kneel_aim" or st == "kneel"
		cap.height = 1.2 if low else 1.75
		body.position.y = cap.height * 0.5
	var scale := 1.0
	if st == "walk":
		scale = clamp(hs / 1.0, 0.6, 1.5)
	elif st == "run":
		scale = clamp(hs / 3.16, 0.6, 1.5)
	elif st == "nade":
		scale = 1.3
	elif st == "react":
		scale = 1.4
	tree.set("parameters/speed/scale", scale)
	tree.advance(dt)
	rig["ik"].interpolation = 0.0 if (nade_t >= 0.0 or react_t > 0.0) else 1.0
	if nade_t < 0.0:
		player.pose_rig_hands(skel, "ak", rig["data"])
	if aim_w > 0.01:
		var chest: Vector3 = player.global_position + Vector3(0, 0.85 if player.crouch else 1.25, 0)
		if not sees:
			chest = last_seen + Vector3(0, 1.2, 0)
		player.aim_chest(skel, (chest - muzzle.global_position).normalized(), aim_w, rig["data"])
	player.place_left_target(skel, rig["ik_target"], "ak", rig["data"])


func _eye() -> Vector3:
	return global_position + Vector3(0, 1.0 if (state == "kneel_aim" or state == "kneel") else 1.6, 0)


## Nothing solid between a and b (people do not count).
func _sight(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [get_rid(), player.get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return h.is_empty() or h.collider.has_method("take_hit")


## Pick the next spot to fight from: a few metres away, reachable in a straight line, 7-32 m from the player.
## Best is cover he can shoot over (hidden crouched, sees the player standing), then somewhere off to his chosen
## side of the player, at a middling range.
func _relocate() -> void:
	if perch:
		hold_t = randf_range(2.0, 4.0)
		return
	var pe: Vector3 = player.global_position + Vector3(0, 1.5, 0)
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var side := Vector3(-to_p.z, 0, to_p.x).normalized() * flank
	var best := Vector3.ZERO
	var best_s := -INF
	var best_cover := false
	var cands := []
	for i in 10:
		var ang := randf() * TAU
		cands.append(global_position + Vector3(cos(ang), 0, sin(ang)) * randf_range(2.5, 6.5))
	# the far side (from the player) of low cover nearby
	for cv in main.cover_list():
		var o: Vector3 = cv[0]
		if o.distance_to(global_position) > 14.0:
			continue
		var away: Vector3 = o - player.global_position
		away.y = 0.0
		var cp: Vector3 = o + away.normalized() * (float(cv[1]) + 0.55)
		cp.y = global_position.y
		cands.append(cp)
	for c in cands:
		if abs(c.x) > 42.0 or c.z > 26.0 or c.z < -45.0:
			continue
		var dp = c.distance_to(player.global_position)
		if dp < 7.0 or dp > 32.0:
			continue
		if not _sight(global_position + Vector3(0, 0.5, 0), c + Vector3(0, 0.5, 0)):
			continue
		var covered := not _sight(pe, c + Vector3(0, 0.85, 0))
		var can_peek := _sight(pe, c + Vector3(0, 1.55, 0))
		var score := (2.5 if covered and can_peek else (0.6 if covered else 0.0)) + (1.0 if can_peek else 0.0)
		score += (c - global_position).normalized().dot(side) * 0.8
		score += 0.6 - abs(dp - 16.0) / 20.0 + randf() * 0.6
		score -= c.distance_to(global_position) * 0.05
		if score > best_s:
			best_s = score
			best = c
			best_cover = covered and can_peek
	if best_s > -INF:
		spot = best
		spot_cover = best_cover
		moving = true
		move_t = 0.0
	else:
		hold_t = randf_range(1.0, 2.0)
	if randf() < 0.25:
		flank = -flank


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return h.is_empty() or h.collider == player


func _perceive(dt: float) -> void:
	# a live grenade close by: run
	var near: Array = main.grenades_near(global_position, 6.0)
	if not near.is_empty() and flee_t <= 0.0 and not perch and nade_t < 0.0:
		var away: Vector3 = global_position - near[0]
		away.y = 0.0
		if away.length() < 0.2:
			away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		spot = global_position + away.normalized() * 7.5
		flee_t = 2.2
		moving = false
		shots_left = 0
		if mode != "combat":
			alarm(near[0], true)
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
	var from: Vector3 = muzzle.global_position + muzzle.global_transform.basis.z * 0.05
	var chest: Vector3 = player.global_position + Vector3(0, 0.85 if player.crouch else 1.25, 0)
	var dir := (chest - from).normalized()
	var d := from.distance_to(chest)
	var sp: float = 0.075 * clamp(1.4 - seen_t * 0.2, 0.5, 1.4)
	sp *= 1.5 if player.speed > 2.5 else 1.0
	sp *= 0.65 if player.crouch else 1.0
	sp *= 0.7 + d / 40.0
	dir = (dir + Vector3(randf_range(-sp, sp), randf_range(-sp, sp) * 0.7, randf_range(-sp, sp))).normalized()
	main.fx.muzzle_flash(from, muzzle.global_transform.basis.z, "ak")
	shot_n += 1
	var end: Vector3 = main.shoot_ray(from, dir, randf_range(4.0, 7.0), self)
	if shot_n % 2 == 0:
		main.fx.tracer(from, end)


## Hit by the player. A round whose line passes the head kills at once. power: how hard the round hits (shotgun,
## SVD more); close up it knocks him back off his feet if it kills him, or staggers him if it does not.
func take_hit(dmg: float, pos: Vector3, dir: Vector3, power := 1.0) -> void:
	if dead:
		return
	var head: Vector3 = (skel.global_transform * skel.get_bone_global_pose(head_b)).origin + Vector3(0, 0.07, 0)
	var rel := head - pos
	var along := rel.dot(dir)
	var headshot := along > -0.15 and (rel - dir * along).length() < 0.13
	main.fx.blood(pos, -dir)
	hp -= 999.0 if headshot else dmg
	var d: float = player.global_position.distance_to(global_position)
	var force: float = power * clamp(1.0 - (d - 3.0) / 9.0, 0.0, 1.0)
	if hp <= 0.0:
		_die(headshot, false, dir, force)
		return
	hit_t = 0.3
	if force > 0.9 and nade_t < 0.0:
		react_t = 0.7
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		vel += flat * 1.6 * min(force, 2.0)
	if grunt_t <= 0.0:
		grunt_t = randf_range(0.5, 0.9)
		main.snd.grunt(global_position + Vector3(0, 1.5, 0))
	alarm(player.global_position, true)
	# hit: get out of there
	if not moving:
		shots_left = 0
		hold_t = 0.0


## Caught by an explosion.
func blast(dmg: float, from: Vector3) -> void:
	if dead:
		return
	main.fx.blood(global_position + Vector3(0, 1.1, 0), (global_position - from).normalized())
	hp -= dmg
	if hp <= 0.0:
		_die(false, true, global_position - from, 1.0)
		return
	hit_t = 0.5
	react_t = 0.8
	alarm(player.global_position, true)
	shots_left = 0
	hold_t = 0.0
	if grunt_t <= 0.0:
		grunt_t = 0.8
		main.snd.grunt(global_position + Vector3(0, 1.5, 0))


## Is there room to be thrown dist metres along d: nothing in the way at waist and chest height, and ground to land
## on (not off the edge of the roof)?
func _room_behind(d: Vector3, dist: float) -> bool:
	var space := get_world_3d().direct_space_state
	for h in [0.5, 1.2]:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, h, 0), global_position + Vector3(0, h, 0) + d * (dist + 0.4))
		q.exclude = [get_rid(), player.get_rid()]
		q.collision_mask = 1
		var r := space.intersect_ray(q)
		if not r.is_empty() and not r.collider.has_method("take_hit"):
			return false
	var land: Vector3 = global_position + d * dist
	var q2 := PhysicsRayQueryParameters3D.create(land + Vector3(0, 0.8, 0), land + Vector3(0, -0.6, 0))
	q2.exclude = [get_rid(), player.get_rid()]
	q2.collision_mask = 1
	var g := space.intersect_ray(q2)
	return not g.is_empty() or (global_position.y < 0.5 and land.y > main.ground_height(land.x, land.z) - 0.5)


func _throw_nade() -> void:
	rig["guns"]["ak"].visible = false
	var hand: Vector3 = (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("mixamorigRightHand"))).origin
	var from := hand + Vector3(0, 0.15, 0)
	var dist := from.distance_to(nade_at)
	var tt: float = clamp(dist / 11.0, 0.9, 1.7)
	var v: Vector3 = (nade_at + Vector3(0, 0.1, 0) - from) / tt + Vector3(0, 4.9 * tt, 0)
	main.spawn_grenade(from, v, self)


func _die(headshot: bool, blasted := false, push := Vector3.ZERO, force := 0.0) -> void:
	dead = true
	hp = 0.0
	collision_layer = 0
	shots_left = 0
	var clip: String = "dieBackHS" if (headshot or blasted) else ["die", "dieFront", "dieLeft"][randi() % 3]
	var flat := Vector3(push.x, 0, push.z)
	if force > 0.45 and flat.length() > 0.01:
		flat = flat.normalized()
		if _room_behind(flat, 3.4 if blasted else 1.6):
			# thrown back along the shot: the clip turns him to face where it came from and throws him along +z
			clip = "dieBlast" if blasted else "dieKnock"
			yaw = atan2(-flat.x, -flat.z)
			rotation.y = yaw
	if nade_t >= 0.0:
		nade_t = -1.0
		rig["guns"]["ak"].visible = true
	playback.travel(clip)
	tree.set("parameters/speed/scale", 1.15 if clip.begins_with("dieK") else 1.0)
	rig["ik"].interpolation = 0.0
	main.snd.death(global_position, "blast" if blasted else ("head" if headshot else "body"))
	main.on_enemy_killed(self, headshot)
