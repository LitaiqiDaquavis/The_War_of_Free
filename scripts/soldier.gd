extends "res://scripts/dummy.gd"

const Arrow = preload("res://scripts/arrow.gd")
const ARCHER_PROBE_INTERVAL: float = 0.13
const ARCHER_SIDE_SPEED: float = 2.1
const ARROW_SPEED: float = 32.0
var team_id: int = 1
var slot: int = 0
var role: String = "melee"
var weapon: String = "longsword"
var has_shield: bool = false
var blocking: bool = false
var sprinting: bool = false
var scan_remaining: float = 0
var threat_remaining: float = 0
var retaliation_remaining: float = 0
var damage_bearing: Vector3 = Vector3.ZERO
var damage_turn_remaining: float = 0
var firing_step: Vector3 = Vector3.ZERO
var firing_probe_remaining: float = 0
var bow_elapsed: float = 0
var bow_stance: float = 0
var bow_recovery_elapsed: float = INF
var shield_blend: float = 0
var spear_carry: float = 0
var spear_switch_remaining: float = 0
var spear_switch_from: float = 0
var kick_elapsed: float = -1
var kick_pending: bool = false
var shots_fired: int = 0
var blocks: int = 0
var rear_reactions: int = 0
var bow: Node3D
var shield: Node3D
var separation: Vector3 = Vector3.ZERO
var separation_remaining: float = 0

func _ready() -> void:
	super._ready()
	# Replace training red armor with team-colored armor, keep the same rig.
	model.queue_free()
	remove_child(model)
	model = Visuals.humanoid(Color("277cce") if team_id == 0 else Color("ce3543"))
	add_child(model)
	upper = model.get_node("Upper")
	if role == "archer":
		bow = Visuals.weapon("bow")
		upper.get_node("LeftArm/Hand").add_child(bow)
	else:
		upper.get_node("RightArm/Hand").add_child(Visuals.weapon(weapon))
	if has_shield:
		shield = Visuals.weapon("shield")
		upper.get_node("LeftArm/Hand").add_child(shield)
	scan_remaining = float(slot % 7) * 0.09
	bow_elapsed = float(slot % 5) * 0.17
	floor_snap_length = 0.3

func _choose_target() -> void:
	# 2 Hz, no rays: choose one of the four nearest valid opponents. Keep a
	# valid lock until it dies or becomes substantially farther than alternatives.
	var candidates: Array[Node3D] = []
	for actor: Node in get_tree().get_nodes_in_group("combat_actors"):
		if actor != self and actor.get("team_id") != null and actor.team_id != team_id and Combat.alive(actor):
			candidates.append(actor)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	if candidates.is_empty():
		target = null
		return
	if Combat.alive(target) and global_position.distance_squared_to(target.global_position) < global_position.distance_squared_to(candidates[0].global_position) + 100:
		return
	target = candidates[(slot + team_id) % mini(4, candidates.size())]

func _observe_arrow() -> bool:
	if not has_shield or role == "archer" or not Combat.alive(target):
		return false
	# A tangible arrow from our locked opponent must be heading through our
	# capsule's vicinity and be visible. No access to the opponent's target.
	for arrow: Node in get_tree().get_nodes_in_group("arrows"):
		if arrow.shooter != target or arrow.velocity.length_squared() < 1:
			continue
		var offset: Vector3 = get_combat_aim_point() - arrow.global_position
		var time: float = offset.dot(arrow.velocity) / arrow.velocity.length_squared()
		if time < 0 or time > 0.9 or offset.length() > 30:
			continue
		if (arrow.global_position + arrow.velocity * time).distance_to(get_combat_aim_point()) > 1.6:
			continue
		if (-global_basis.z).dot(offset.normalized()) > -0.15:
			continue
		var query := PhysicsRayQueryParameters3D.create(get_combat_aim_point(), arrow.global_position, 1, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return true
	return false

func _physics_process(delta: float) -> void:
	Combat.regen_tick(self, delta)
	if defeated:
		return
	if not ai_enabled:
		return
	scan_remaining -= delta
	threat_remaining = maxf(0, threat_remaining - delta)
	retaliation_remaining = maxf(0, retaliation_remaining - delta)
	damage_turn_remaining = maxf(0, damage_turn_remaining - delta)
	if scan_remaining <= 0:
		scan_remaining = 0.45 + float(slot % 4) * 0.035
		if retaliation_remaining <= 0 or not Combat.alive(target):
			_choose_target()
		if _observe_arrow():
			threat_remaining = 0.9
	blocking = has_shield and threat_remaining > 0 and attack_elapsed < 0
	stagger_timer = maxf(0, stagger_timer - delta)
	attack_cooldown = maxf(0, attack_cooldown - delta)
	velocity.x = 0
	velocity.z = 0
	sprinting = false
	var target_direction := Vector3.ZERO
	if damage_turn_remaining > 0:
		_face_direction(damage_bearing, delta)
	elif Combat.alive(target):
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0
		var distance: float = offset.length()
		target_direction = offset.normalized()
		_face_direction(target_direction, delta)
		if stagger_timer <= 0:
			if role == "archer":
				_archer_tick(delta, target_direction, distance)
			else:
				_melee_tick(delta, target_direction, distance)
	elif role == "melee" and attack_elapsed >= 0:
		# Let an already committed swing finish after defeating its target.
		_melee_tick(delta, Vector3.ZERO, 0.0)
	if not is_on_floor():
		velocity.y -= 18 * delta
	separation_remaining -= delta
	if separation_remaining <= 0:
		separation_remaining = 0.16 + float(slot % 3) * 0.02
		separation = Vector3.ZERO
		for actor: Node in get_tree().get_nodes_in_group("combat_actors"):
			if actor == self or not Combat.alive(actor):
				continue
			var away: Vector3 = global_position - actor.global_position
			away.y = 0
			var distance: float = away.length()
			if distance < 1.5 and distance > 0.001:
				separation += away / distance * (1.5 - distance)
		separation = separation.limit_length(1.25)
	var spacing: Vector3 = separation
	if role == "archer":
		spacing -= target_direction * minf(0, spacing.dot(target_direction))
	velocity += spacing
	move_and_slide()
	if attack_elapsed < 0:
		spear_switch_remaining = 0
		spear_switch_from = 0
	var carrying: bool = weapon == "spear" and sprinting and role == "melee"
	spear_carry = move_toward(spear_carry, 1.0 if carrying else 0.0, delta / 0.18)
	shield_blend = move_toward(shield_blend, 1.0 if blocking else 0.0, delta / (0.16 if blocking else 0.20))
	bow_recovery_elapsed += delta
	_animate_fighter(delta)
	if global_position.y < -20:
		defeat()

func _face_direction(direction: Vector3, delta: float) -> void:
	if not direction.is_zero_approx():
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1, delta * 9))

func _melee_tick(delta: float, direction: Vector3, distance: float) -> void:
	var reach: float = 3.6 if weapon == "spear" else (1.9 if weapon == "dagger" else 2.5)
	if attack_elapsed >= 0:
		var switch_step: float = minf(delta, spear_switch_remaining)
		spear_switch_remaining -= switch_step
		attack_elapsed += delta - switch_step
		if attack_pending and Timing.stage(weapon, attack_elapsed) == "active":
			_strike(reach, false)
		if Timing.stage(weapon, attack_elapsed) == "done":
			attack_elapsed = -1
			attack_cooldown = 0.22 + float(slot % 3) * 0.1
	elif distance < reach - 0.2 and attack_cooldown <= 0 and not blocking:
		attack_elapsed = 0
		if weapon == "spear" and spear_carry > 0.01:
			spear_switch_from = spear_carry
			spear_switch_remaining = Poses.SPEAR_SWITCH_TIME
		struck_ids.clear()
		attack_pending = true
	if distance > reach - 0.5:
		sprinting = distance > 9 and not blocking and attack_elapsed < 0
		velocity += direction * (5.0 if sprinting else (1.1 if blocking else 2.6))
		# Deterministic lane offset prevents all 39 combatants occupying one point.
		velocity += Vector3(-direction.z, 0, direction.x) * sin(float(slot) * 2.3) * minf(0.7, distance * 0.04)

func _archer_tick(delta: float, direction: Vector3, distance: float) -> void:
	if kick_elapsed >= 0:
		kick_elapsed += delta
		if kick_pending and Timing.stage("kick", kick_elapsed) == "active":
			_strike(1.8, true)
		if Timing.stage("kick", kick_elapsed) == "done":
			kick_elapsed = -1
			attack_cooldown = 0.65
	elif distance < 1.7 and attack_cooldown <= 0:
		kick_elapsed = 0
		kick_pending = true
	if kick_elapsed >= 0:
		bow_elapsed = 0
		firing_step = Vector3.ZERO
		firing_probe_remaining = 0
		return
	var ready_time: float = 1.7 + float(slot % 3) * 0.13
	bow_elapsed = minf(ready_time, bow_elapsed + delta)
	if distance > 23 and firing_step.is_zero_approx():
		sprinting = distance > 30
		velocity += direction * (5.0 if sprinting else 2.6)
	if distance <= 2.0 or distance >= 32.0 or bow_elapsed < ready_time:
		firing_step = Vector3.ZERO
		firing_probe_remaining = 0
		return

	firing_probe_remaining -= delta
	if firing_probe_remaining <= 0:
		firing_probe_remaining = ARCHER_PROBE_INTERVAL
		var first := _shot_blocker(get_combat_aim_point() + Vector3.UP * 0.35)
		if Combat.friendly(self, first):
			firing_step = _choose_firing_step(direction)
		else:
			if first == target and Combat.can_shoot(get_tree(), self) and (-global_basis.z).dot(direction) > 0.8:
				if _fire_arrow():
					bow_elapsed = 0
					firing_step = Vector3.ZERO
				else:
					firing_step = _choose_firing_step(direction)
			else:
				firing_step = Vector3.ZERO
	velocity += firing_step * ARCHER_SIDE_SPEED

func _shot_blocker(origin: Vector3) -> Node:
	var query := PhysicsRayQueryParameters3D.create(origin, target.get_combat_aim_point(), 3, [get_rid()])
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider")

func _choose_firing_step(direction: Vector3) -> Vector3:
	var side := Vector3(-direction.z, 0, direction.x)
	if firing_step.dot(side) < -0.1 or (firing_step.is_zero_approx() and (slot + team_id) % 2 == 1):
		side = -side
	var fallback := Vector3.ZERO
	for step: Vector3 in [side, -side]:
		if test_move(global_transform, step * 0.8):
			continue
		var peek: Vector3 = step * 2.2
		var feet: Vector3 = global_position + peek
		var floor_ray := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.6, feet - Vector3.UP * 1.4, 1)
		var space := get_world_3d().direct_space_state
		if space.intersect_ray(floor_ray).is_empty():
			continue
		if _shot_blocker(get_combat_aim_point() + Vector3.UP * 0.35 + peek) == target:
			return step
		if fallback.is_zero_approx():
			fallback = step
	return fallback

func _fire_arrow() -> bool:
	var origin: Vector3 = get_combat_aim_point() + (-global_basis.z) * 0.6 + Vector3.UP * 0.35
	var aim: Vector3 = target.get_combat_aim_point()
	var flight: float = origin.distance_to(aim) / ARROW_SPEED
	# Predict modest movement; the sweep uses the actual randomized launch.
	aim += target.velocity * flight * 0.65
	aim += Vector3(rng.randf_range(-0.3, 0.3), 4.9 * flight * flight, rng.randf_range(-0.3, 0.3))
	var launch_velocity: Vector3 = (aim - origin).normalized() * ARROW_SPEED
	if _ally_on_arrow_path(origin, launch_velocity, flight):
		return false
	var arrow := Arrow.new()
	arrow.shooter = self
	arrow.exclusions = [get_rid()]
	arrow.velocity = launch_velocity
	get_parent().add_child(arrow)
	arrow.global_position = origin
	arrow.look_at(origin + arrow.velocity)
	arrow.record_launch()
	shots_fired += 1
	bow_recovery_elapsed = 0
	return true

func _ally_on_arrow_path(origin: Vector3, launch_velocity: Vector3, flight: float) -> bool:
	var start: Vector3 = origin
	var space := get_world_3d().direct_space_state
	for segment: int in range(1, 5):
		var time: float = (flight + 0.05) * segment / 4.0
		var end: Vector3 = origin + launch_velocity * time + Vector3.DOWN * 4.9 * time * time
		var query := PhysicsRayQueryParameters3D.create(start, end, 3, [get_rid()])
		query.hit_from_inside = true
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			return Combat.friendly(self, hit.collider)
		start = end
	return false

func _strike(reach: float, kicking: bool) -> void:
	var origin: Vector3 = get_combat_aim_point()
	if not kicking and Combat.uses_aoe(weapon):
		Combat.sweep(self, origin, -global_basis.z, reach, Combat.MELEE, false, struck_ids)
		return
	if not Combat.alive(target):
		return
	var direction: Vector3 = (target.get_combat_aim_point() - origin).normalized()
	if (-global_basis.z).dot(direction) < 0.55:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, 3, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	if kicking:
		kick_pending = false
	else:
		attack_pending = false
	if hit.collider.has_method("take_melee_hit"):
		if kicking:
			hit.collider.take_kick(hit.position, direction, self)
		else:
			hit.collider.take_melee_hit(hit.position, direction, Combat.MELEE, false, self)

func _animate_fighter(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	walk_phase += speed * delta * 2
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = model.get_node("RightLeg" if side > 0 else "LeftLeg")
		var step: float = sin(walk_phase) * side * minf(1, speed / 3)
		leg.rotation.x = step * (0.65 if sprinting else 0.42)
		leg.get_node("Knee").rotation.x = maxf(0, -step) * 0.5
	if kick_elapsed >= 0:
		var phase: float = Timing.pose_phase("kick", kick_elapsed)
		model.get_node("RightLeg").rotation.x = -sin(phase * PI) * 1.6
	var arm_swing: float = sin(walk_phase) * minf(speed / 3.0, 1.5)
	if role == "archer":
		_animate_archer(delta, speed, arm_swing)
		return
	var attacking: bool = attack_elapsed >= 0
	var pose: Dictionary = Poses.sample(weapon, Timing.pose_phase(weapon, maxf(0, attack_elapsed)), attacking)
	if not attacking:
		if weapon == "spear":
			pose = Poses.blend(pose, Poses.spear_carry(), spear_carry)
		pose.hand = Poses.idle_weapon_hand(pose.hand, arm_swing, weapon, spear_carry)
	elif spear_switch_from > 0 and Timing.stage(weapon, attack_elapsed) == "windup":
		var ready: Dictionary = Poses.sample("spear", Timing.ready_pose("spear"), true)
		var carry: Dictionary = Poses.blend(Poses.sample("spear", 0, false), Poses.spear_carry(), spear_switch_from)
		var weight: float = 1 - smoothstep(0, Poses.SPEAR_SWITCH_TIME, spear_switch_remaining)
		pose = Poses.blend(carry, ready, weight)
	Visuals.pose_weapon_arm(upper.get_node("RightArm"), pose.hand, pose.wrist, 1)
	var raised: float = smoothstep(0.0, 1.0, shield_blend)
	var left_hand: Vector3 = Poses.off_hand(0 if blocking else arm_swing, has_shield, raised)
	var shield_wrist: Vector3 = Vector3(0.15, -0.18, -0.1).lerp(Vector3(0, 0.05, 0), raised) if has_shield else Vector3.ZERO
	Visuals.pose_weapon_arm(upper.get_node("LeftArm"), left_hand, shield_wrist, -1)

func _animate_archer(delta: float, speed: float, arm_swing: float) -> void:
	var aiming: bool = kick_elapsed < 0 and Combat.alive(target) and stagger_timer <= 0 and damage_turn_remaining <= 0
	bow_stance = move_toward(bow_stance, 1.0 if aiming else 0.0, delta / 0.16)
	var pitch: float = 0
	if aiming:
		var offset: Vector3 = target.get_combat_aim_point() - get_combat_aim_point()
		pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	var nock_progress: float = smoothstep(0.0, 0.4, bow_elapsed)
	var draw: float = smoothstep(0.4, 1.2, bow_elapsed)
	var arrow_visible: bool = aiming and bow_elapsed > 0.0
	if bow_recovery_elapsed < Visuals.BOW_RELEASE_TIME + Visuals.BOW_STRING_TIME:
		arrow_visible = false
		nock_progress = 1.0
		if bow_recovery_elapsed < Visuals.BOW_RELEASE_TIME:
			draw = Visuals.bow_release_draw(bow_recovery_elapsed / Visuals.BOW_RELEASE_TIME)
		else:
			draw = Visuals.bow_string_draw((bow_recovery_elapsed - Visuals.BOW_RELEASE_TIME) / Visuals.BOW_STRING_TIME)
	if not aiming:
		draw = 0
	var footing: float = Visuals.bow_footing(bow_stance, speed, draw, bow_recovery_elapsed) if is_on_floor() and kick_elapsed < 0 else 0.0
	model.position.y = 0
	Visuals.pose_bow_stance(model, bow_stance, pitch, footing)
	Visuals.pose_body_bow(bow, bow_stance, pitch, draw, arrow_visible, nock_progress, arm_swing)

func _incoming(direction: Vector3, attacker: Node) -> bool:
	if defeated:
		return false
	var incoming := Vector3(-direction.x, 0, -direction.z).normalized()
	if blocking and has_shield and (-global_basis.z).dot(incoming) > 0.35:
		blocks += 1
		return false
	return true

func _notice_damage(direction: Vector3, attacker: Node) -> void:
	damage_bearing = Combat.damage_bearing(self, direction, attacker)
	if not damage_bearing.is_zero_approx():
		damage_turn_remaining = 0.25
	if not Combat.alive(attacker) or Combat.friendly(self, attacker) or attacker == self:
		return
	if (-global_basis.z).dot(damage_bearing) < -0.15:
		rear_reactions += 1
	target = attacker
	retaliation_remaining = 3
	firing_step = Vector3.ZERO
	firing_probe_remaining = 0

func take_melee_hit(point: Vector3, direction: Vector3, damage: float, critical: bool, attacker: Node = null, source: Dictionary = {}) -> bool:
	if not _incoming(direction, attacker):
		return false
	_notice_damage(direction, attacker)
	return super.take_melee_hit(point, direction, damage, critical, attacker, source)

func take_projectile_hit(point: Vector3, direction: Vector3, kind: String, attacker: Node = null, source: Dictionary = {}) -> bool:
	if not _incoming(direction, attacker):
		return false
	_notice_damage(direction, attacker)
	return super.take_projectile_hit(point, direction, kind, attacker, source)

func take_kick(point: Vector3, direction: Vector3, attacker: Node = null) -> bool:
	return take_melee_hit(point, direction, Combat.KICK, false, attacker, Combat.damage_source(attacker, "kick"))

func take_shield_hit(point: Vector3, direction: Vector3, attacker: Node = null) -> bool:
	return take_melee_hit(point, direction, Combat.SHIELD, false, attacker, Combat.damage_source(attacker, "shield"))

func reset_for_match() -> void:
	super.reset_for_match()
	target = null
	blocking = false
	threat_remaining = 0
	retaliation_remaining = 0
	damage_bearing = Vector3.ZERO
	damage_turn_remaining = 0
	firing_step = Vector3.ZERO
	firing_probe_remaining = 0
	bow_elapsed = float(slot % 5) * 0.17
	bow_stance = 0
	bow_recovery_elapsed = INF
	shield_blend = 0
	sprinting = false
	spear_carry = 0
	spear_switch_remaining = 0
	spear_switch_from = 0
	kick_elapsed = -1
	kick_pending = false
	separation = Vector3.ZERO
	separation_remaining = 0
