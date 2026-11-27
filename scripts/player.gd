extends CharacterBody3D

signal hit_confirmed
signal equipment_changed
signal death_finished
signal death_started
signal health_changed
signal shield_blocked
const Visuals = preload("res://scripts/visuals.gd")
const Arrow = preload("res://scripts/arrow.gd")
const WeaponPoses = preload("res://scripts/weapon_poses.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const Combat = preload("res://scripts/combat.gd")
const ThrownItem = preload("res://scripts/thrown_item.gd")
const Timing = preload("res://scripts/attack_timing.gd")
const WEAPONS: Dictionary = {
	"fists": {"reach": 1.6, "duration": 0.8, "damage": 40.0},
	"dagger": {"reach": 1.9, "duration": 1.2, "damage": 40.0},
	"longsword": {"reach": 2.7, "duration": 1.0, "damage": 40.0},
	"spear": {"reach": 3.8, "duration": 0.85, "damage": 40.0},
	"mace": {"reach": 2.3, "duration": 1.52, "damage": 40.0}
}
const WALK_SPEED: float = 3.0
const SPRINT_SPEED: float = 5.0
const JUMP_SPEED: float = 6.0
const GRAVITY: float = 18.0
const MOUSE_SENSITIVITY: float = 0.0025
const SPAWN_POSITION: Vector3 = Vector3(0.0, 0.1, 8.0)
const THROW_DURATION: float = 0.6
const THROW_RELEASE: float = 0.25
const KICK_DURATION: float = 0.8
const KICK_HIT_TIME: float = 0.15
const KICK_REACH: float = 1.65
const GRIP_FLIP_TIME: float = 0.3
const ITEM_THROW_RELEASE: float = 0.34
const ITEM_THROW_DURATION: float = 0.85
const PICKUP_REACH: float = 3.0
const SPEAR_SWITCH_TIME: float = 0.3
const BOW_EQUIP_TIME: float = 0.45
const BOW_PREPARE_TIME: float = 0.4
const BOW_RELEASE_TIME: float = 0.1
const BOW_STRING_TIME: float = 0.15
const BOW_COOLDOWN_TIME: float = 0.5
enum BowPhase { INACTIVE, EQUIP, NOCK, READY, RELEASE, STRING, COOLDOWN }
const BOW_NOCK_TIME: float = 0.10
const BOW_BODY_LATERAL_PULL: float = 0.27
const BOW_BODY_DEPTH: float = 1.42
const ARM_LENGTHS := Vector2(0.3, 0.31)

var controls_active: bool = false
var third_person: bool = false
var front_view: bool = false
var prone: bool = false
var prone_blend: float = 0
var health: int = Combat.MAX_HEALTH
var off_dropped: bool = false
var item_throw_kind: String = ""
var item_throw_left: bool = false
var look_pitch: float = 0.0
var main_hand: String = "longsword"
var off_hand: String = "shield"
var body_model: Node3D
var view_model: Node3D
var main_mount: Node3D
var off_mount: Node3D
var view_right_arm: Node3D
var view_left_arm: Node3D
var view_kick_leg: Node3D
var view_knife: Node3D
var body_knife: Node3D
var special_action: String = ""
var special_elapsed: float = 0
var special_pending: bool = false
var body_view_mode: int = -1
var body_bow: Node3D
var attack_elapsed: float = 0.0
var attack_duration: float = 0.0
var attack_pending: bool = false
var melee_held: bool = false
var charge_elapsed: float = 0
var charge_start_pose: Dictionary = {}
var attack_pose_start_elapsed: float = 0
var attack_heavy: bool = false
var attack_chained: bool = false
var attack_start_pose: Dictionary = {}
var attack_buffered: bool = false
var buffered_heavy: bool = false
var swing_direction: int = 1
var combo_window: float = 0
var dagger_reverse: bool = false
var dagger_grip_blend: float = 0
var dagger_flip_from: float = 0
var dagger_flip_elapsed: float = GRIP_FLIP_TIME
var dagger_flip_queued: bool = false
var last_hit_critical: bool = false
var blocking: bool = false
var shield_requested: bool = false
var shield_blend: float = 0
var shield_start_pose: Dictionary = {}
var active_slot: int = 1
var is_alive: bool = true
var gait_phase: float = 0
var gait_blend: float = 0
var sprinting: bool = false
var spear_carry: float = 0
var spear_switch_remaining: float = 0
var spear_switch_from: Dictionary = {}
var bow_phase: BowPhase = BowPhase.INACTIVE
var bow_phase_elapsed: float = 0
# Compatibility value for draw progress; never used as permission to fire.
var bow_prepare_elapsed: float = 0
var bow_stance: float = 0
var zooming: bool = false
var base_fov: float = 80
var death_elapsed: float = 0
var death_reported: bool = false
var ragdoll: Node3D
var death_focus: Vector3
var death_yaw: float = 0
var death_pitch: float = -0.35
var death_closeup: bool = false
var look_motion: Vector2 = Vector2.ZERO
var view_sway: Vector2 = Vector2.ZERO

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("combat_actors")
	look_pitch = camera.rotation.x
	base_fov = camera.fov
	body_model = Visuals.humanoid(Color("2455d8"))
	add_child(body_model)
	view_model = Node3D.new()
	camera.add_child(view_model)
	main_mount = Node3D.new()
	off_mount = Node3D.new()
	view_model.add_child(main_mount)
	view_model.add_child(off_mount)
	view_right_arm = body_model.get_node("Upper/RightArm").duplicate() as Node3D
	view_left_arm = body_model.get_node("Upper/LeftArm").duplicate() as Node3D
	view_right_arm.name = "RightViewArm"
	view_left_arm.name = "LeftViewArm"
	# View shoulders sit beside/behind the camera, rather than in front of it.
	view_right_arm.position = Vector3(0.58, -0.25, -0.05)
	view_left_arm.position = Vector3(-0.58, -0.25, -0.05)
	view_right_arm.get_node("Pauldron").hide()
	view_left_arm.get_node("Pauldron").hide()
	view_model.add_child(view_right_arm)
	view_model.add_child(view_left_arm)
	view_kick_leg = body_model.get_node("RightLeg").duplicate() as Node3D
	view_kick_leg.name = "KickLeg"
	view_kick_leg.position = Vector3(0.22, -0.6, 0.02)
	view_kick_leg.scale = Vector3.ONE * 0.82
	view_model.add_child(view_kick_leg)
	view_kick_leg.hide()
	equip(main_hand, off_hand)
	_update_camera()

func equip(primary: String, secondary: String) -> void:
	cancel_special()
	_reset_melee(true)
	off_dropped = false
	main_hand = primary if WEAPONS.has(primary) else "fists"
	off_hand = secondary if secondary in ["shield", "bow"] else "shield"
	attack_duration = 0
	attack_pending = false
	blocking = false
	shield_requested = false
	shield_blend = 0
	cancel_bow()
	active_slot = 1
	if not is_instance_valid(main_mount):
		return
	var primary_hand: Node3D = body_model.get_node("Upper/RightArm/Hand")
	var secondary_hand: Node3D = body_model.get_node("Upper/LeftArm/Hand")
	if is_instance_valid(body_bow):
		body_bow.get_parent().remove_child(body_bow)
		body_bow.queue_free()
	for mount: Node3D in [main_mount, off_mount, primary_hand, secondary_hand]:
		for child: Node in mount.get_children():
			mount.remove_child(child)
			child.queue_free()
	main_mount.add_child(Visuals.weapon(main_hand))
	off_mount.add_child(Visuals.weapon(off_hand))
	primary_hand.add_child(Visuals.weapon(main_hand))
	view_knife = Visuals.weapon("throwing_knife")
	body_knife = Visuals.weapon("throwing_knife")
	main_mount.add_child(view_knife)
	primary_hand.add_child(body_knife)
	body_bow = Visuals.weapon(off_hand)
	if off_hand == "bow":
		body_bow.name = "BodyBow"
	secondary_hand.add_child(body_bow)
	body_view_mode = -1
	_set_shadow_mode(view_model, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_update_camera()
	_update_weapon_pose()
	equipment_changed.emit()

func bow_active() -> bool:
	return active_slot == 2 and off_hand == "bow"

func get_pickup_target() -> Node:
	if not controls_active or not is_alive:
		return null
	var origin: Vector3 = camera.global_position
	var distance: float = origin.distance_to(_combat_eye()) + PICKUP_REACH + 1.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin - camera.global_basis.z * distance, 15, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider.is_in_group("thrown_items"):
		return null
	if not hit.collider.has_method("is_pickup_available") or not hit.collider.is_pickup_available():
		return null
	if hit.position.distance_to(_combat_eye()) > PICKUP_REACH:
		return null
	return hit.collider

func can_pickup() -> bool:
	return controls_active and is_alive and attack_duration <= 0 and special_action.is_empty() and dagger_flip_elapsed >= GRIP_FLIP_TIME

func interact_pickup_or_flip() -> void:
	var item: Node = get_pickup_target()
	if is_instance_valid(item):
		# A busy pickup consumes E too, avoiding a queued flip or cooldown skip.
		if can_pickup():
			_pickup_item(item)
		return
	request_dagger_flip()

func _pickup_item(item: Node) -> bool:
	if not can_pickup() or not is_instance_valid(item) or not item.is_inside_tree():
		return false
	var kind: String = item.kind
	if kind not in ["dagger", "longsword", "spear", "mace", "shield"] or not item.claim():
		return false
	var previous_main: String = main_hand
	var previous_off: String = off_hand
	var previous_dropped: bool = off_dropped
	var previous_slot: int = active_slot
	var previous_reverse: bool = dagger_reverse
	var previous_guard: bool = shield_requested
	var previous_blend: float = shield_blend
	if kind == "shield":
		equip(previous_main, "shield")
		active_slot = 2
		if previous_main == "dagger":
			dagger_reverse = previous_reverse
			dagger_grip_blend = 1.0 if dagger_reverse else 0.0
	else:
		equip(kind, previous_off)
		off_dropped = previous_dropped
		active_slot = 1 if previous_off == "bow" and previous_slot == 2 else previous_slot
	if off_hand == "shield" and not off_dropped and active_slot == 2:
		shield_requested = previous_guard
		shield_blend = previous_blend
		blocking = _can_block()
	item.get_parent().remove_child(item)
	item.queue_free()
	_update_weapon_pose()
	equipment_changed.emit()
	return true

func select_slot(slot: int) -> void:
	if slot == active_slot:
		return
	if attack_duration > 0 or special_action in ["kick", "shield"]:
		return
	cancel_special()
	_reset_melee()
	active_slot = clampi(slot, 1, 2)
	attack_duration = 0
	attack_pending = false
	blocking = false
	shield_requested = false
	shield_blend = 0
	cancel_bow()
	_update_weapon_pose()
	equipment_changed.emit()

func reset_for_match() -> void:
	cancel_special()
	_reset_melee(true)
	health = Combat.MAX_HEALTH
	health_changed.emit()
	prone = false
	prone_blend = 0
	front_view = false
	off_dropped = false
	_set_prone_collision(false)
	if is_instance_valid(ragdoll):
		ragdoll.dispose()
		ragdoll = null
	collision_layer = 1
	position = SPAWN_POSITION
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	look_pitch = deg_to_rad(-3)
	third_person = false
	is_alive = true
	death_elapsed = 0
	death_reported = false
	death_closeup = false
	camera.fov = base_fov
	body_model.rotation = Vector3.ZERO
	body_model.position = Vector3.ZERO
	body_model.get_node("Upper").rotation = Vector3.ZERO
	for leg_name: String in ["LeftLeg", "RightLeg"]:
		body_model.get_node(leg_name).rotation = Vector3.ZERO
		body_model.get_node(leg_name + "/Knee").rotation = Vector3.ZERO
	gait_blend = 0
	gait_phase = 0
	sprinting = false
	bow_stance = 0
	view_model.position = Vector3.ZERO
	_reset_sway()
	attack_duration = 0
	attack_pending = false
	blocking = false
	shield_requested = false
	shield_blend = 0
	cancel_bow()
	active_slot = 1
	_update_camera()
	_update_weapon_pose()

func toggle_view() -> void:
	if not third_person:
		third_person = true
		front_view = false
	elif not front_view:
		front_view = true
	else:
		third_person = false
		front_view = false
	_reset_sway()
	_update_camera()

func _update_camera() -> void:
	if not is_alive:
		if is_instance_valid(ragdoll):
			death_focus = death_focus.lerp(ragdoll.focus_position(), 0.15)
			var distance: float = 2.0 if death_closeup else 4.2
			var orbit: Basis = Basis(Vector3.UP, death_yaw) * Basis(Vector3.RIGHT, death_pitch)
			var desired: Vector3 = death_focus + orbit * Vector3(0, 0, distance)
			var query := PhysicsRayQueryParameters3D.create(death_focus, desired, 3, [get_rid()])
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			camera.global_position = hit.position + hit.normal * 0.15 if not hit.is_empty() else desired
			camera.look_at(death_focus)
		body_model.hide()
		view_model.visible = false
		return
	camera.rotation = Vector3(look_pitch, 0, 0)
	var eye := Vector3(0, lerpf(1.65, 0.5, prone_blend), lerpf(0, -0.9, prone_blend))
	if third_person:
		var desired: Vector3 = eye + Basis(Vector3.RIGHT, look_pitch) * Vector3(0.55, 0.35, 3.6)
		if front_view:
			desired = eye + Basis(Vector3.RIGHT, -look_pitch) * Vector3(-0.45, 0.35, -3.6)
		var query := PhysicsRayQueryParameters3D.create(to_global(eye), to_global(desired), 3, [get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		camera.position = to_local(hit.position) + (eye - to_local(hit.position)).normalized() * 0.15 if not hit.is_empty() else desired
		if front_view:
			camera.look_at(to_global(eye + Vector3(0, -0.35, 0)))
	else:
		camera.position = eye + Vector3(0, 0, -0.38)
	body_model.show()
	view_model.visible = not third_person
	_apply_body_visibility()

func toggle_prone() -> void:
	if not controls_active or not is_alive or not is_on_floor() or not special_action.is_empty():
		return
	if prone:
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.35
		shape.height = 1.95
		query.shape = shape
		query.transform = Transform3D(global_basis, to_global(Vector3(0, 1.005, 0)))
		query.collision_mask = 3
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return
	prone = not prone
	_set_prone_collision(prone)
	_cancel_melee_input()
	equipment_changed.emit()

func _set_prone_collision(value: bool) -> void:
	var collision: CollisionShape3D = $CollisionShape3D
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28 if value else 0.35
	shape.height = 1.9 if value else 1.95
	collision.shape = shape
	collision.rotation.x = PI / 2 if value else 0
	collision.position = Vector3(0, 0.3, -0.3) if value else Vector3(0, 0.975, 0)

func get_head_position() -> Vector3:
	return body_model.get_node("Upper/Helmet").global_position

func get_combat_aim_point() -> Vector3:
	return global_position + Vector3(0, 0.35 if prone else 1.15, -0.35 if prone else 0)

func _combat_eye() -> Vector3:
	return to_global(Vector3(0, 0.5 if prone else 1.65, -0.9 if prone else 0))

func take_melee_hit(point: Vector3, direction: Vector3, damage: float, _critical: bool) -> bool:
	return _take_damage(damage, direction)

func take_projectile_hit(point: Vector3, direction: Vector3, kind: String) -> bool:
	return _take_damage(Combat.projectile_damage(kind, Combat.is_head_hit(self, point)), direction)

func take_kick(_point: Vector3, direction: Vector3) -> bool:
	return _take_damage(Combat.KICK, direction)

func take_shield_hit(_point: Vector3, direction: Vector3) -> bool:
	return _take_damage(Combat.SHIELD, direction)

func take_hit(_point: Vector3, direction: Vector3) -> bool:
	return _take_damage(Combat.MELEE, direction)

func _take_damage(amount: float, direction: Vector3) -> bool:
	if not is_alive:
		return false
	var incoming := Vector3(-direction.x, 0, -direction.z).normalized()
	if blocking and _can_block() and (-global_basis.z).dot(incoming) > 0.4:
		shield_blocked.emit()
		return false
	health = maxi(0, health - int(amount))
	health_changed.emit()
	if health == 0:
		die()
	return true

func _set_shadow_mode(node: Node, mode: int) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = mode
	for child: Node in node.get_children():
		_set_shadow_mode(child, mode)

func _apply_body_visibility() -> void:
	var mode: int = 1 if third_person else (2 if special_action == "kick" else 0)
	if body_view_mode == mode:
		return
	body_view_mode = mode
	_set_shadow_mode(body_model, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	if not third_person:
		# Keep legs and torso visible when looking down. Head and real arms
		# still cast full-body shadows while the view arms handle close-up poses.
		for path: String in ["Upper/Helmet", "Upper/Neck", "Upper/Scarf", "Upper/ScarfFront", "Upper/RightArm", "Upper/LeftArm"]:
			_set_shadow_mode(body_model.get_node(path), GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		if special_action == "kick":
			_set_shadow_mode(body_model.get_node("RightLeg"), GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)

func _reset_sway() -> void:
	look_motion = Vector2.ZERO
	view_sway = Vector2.ZERO
	if is_instance_valid(view_model):
		view_model.rotation = Vector3.ZERO

func _update_sway(delta: float) -> void:
	var angular_velocity: Vector2 = look_motion / maxf(delta, 0.001)
	look_motion = Vector2.ZERO
	var target := Vector2(clampf(-angular_velocity.x * 0.007, -0.075, 0.075), clampf(angular_velocity.y * 0.005, -0.05, 0.05))
	view_sway = view_sway.lerp(target, 1 - exp(-18 * delta))
	view_model.rotation = Vector3(view_sway.y * 0.6, -view_sway.x * 0.7, 0)

func _update_weapon_pose() -> void:
	var pose: Dictionary = _melee_pose()
	var throwing: bool = special_action == "throw"
	var throwing_item: bool = special_action == "item"
	if throwing:
		pose = _throw_pose(pose)
	elif throwing_item and not item_throw_left:
		pose = _item_throw_pose(pose)
	main_mount.position = pose.position
	main_mount.rotation = pose.rotation
	match main_hand:
		"longsword": main_mount.scale = Vector3(0.8, 0.8, 0.62)
		"spear": main_mount.scale = Vector3(0.75, 0.75, 0.32)
		"mace": main_mount.scale = Vector3.ONE * 0.75
		_: main_mount.scale = Vector3.ONE
	if throwing:
		main_mount.scale = Vector3.ONE
	var raised: float = smoothstep(0.0, 1.0, shield_blend)
	off_mount.scale = Vector3.ONE * 0.9
	off_mount.position = Vector3(-0.68, -0.43, -0.85).lerp(Vector3(-0.28, -0.12, -0.75), raised)
	off_mount.rotation = Vector3(0.15, -0.18, -0.1).lerp(Vector3(0, 0.05, 0), raised)
	if throwing_item and item_throw_left:
		var shield_pose: Dictionary = _shield_throw_pose()
		off_mount.position = shield_pose.position
		off_mount.rotation = shield_pose.rotation
	if special_action == "shield":
		var bash_pose: Dictionary = WeaponPoses.shield_bash(special_elapsed, shield_start_pose)
		off_mount.position = bash_pose.position
		off_mount.rotation = bash_pose.rotation
	var right_arm: Node3D = body_model.get_node("Upper/RightArm")
	var left_arm: Node3D = body_model.get_node("Upper/LeftArm")
	var right_hand: Node3D = right_arm.get_node("Hand")
	var left_hand: Node3D = left_arm.get_node("Hand")
	var right_target: Vector3 = pose.hand
	var left_target := Vector3(-0.31, -0.08, -0.10)
	var arm_swing: float = sin(gait_phase) * gait_blend
	if attack_duration == 0 and special_action.is_empty() and not melee_held:
		right_target.z += arm_swing * (0.15 if main_hand == "fists" else 0.08) * (1 - spear_carry)
		right_target.y += absf(arm_swing) * 0.045 * (1 - spear_carry)
	if not blocking:
		left_target.z -= arm_swing * (0.10 if active_slot == 2 and not off_dropped else 0.16)
		left_target.y += absf(arm_swing) * 0.04
	if active_slot == 2 and off_hand == "shield":
		left_target = left_target.lerp(Vector3(-0.22, 0.43, -0.35), raised)
	if throwing_item and item_throw_left:
		left_target = _shield_throw_pose().hand
	if special_action == "shield":
		left_target = WeaponPoses.shield_bash(special_elapsed, shield_start_pose).hand
	Visuals.pose_arm(right_arm, right_target, pose.wrist, 1.0, ARM_LENGTHS, Vector3(0.12, -1, 0.65))
	var elbow_attack: bool = main_hand == "fists" and ((attack_heavy and attack_duration > 0) or melee_held)
	var elbow_weight: float = 0
	if elbow_attack:
		elbow_weight = sin(Timing.pose_phase(main_hand, attack_elapsed, attack_heavy) * PI) if attack_duration > 0 else smoothstep(0, _charge_limit(), charge_elapsed) * sin(0.42 * PI)
		var body_pole: Vector3 = Vector3(0.8, -0.2, 0.65).lerp(Vector3(-0.7, 0.15, -1), elbow_weight)
		Visuals.pose_arm(right_arm, right_target, pose.wrist, 1.0, Vector2(0.3, 0.31), body_pole)
	Visuals.pose_arm(left_arm, left_target, off_mount.rotation, -1.0, ARM_LENGTHS, Vector3(-0.12, -1, 0.65))
	main_mount.visible = not bow_active() or throwing
	off_mount.visible = active_slot == 2 and not off_dropped
	right_hand.visible = not bow_active() or throwing
	left_hand.visible = active_slot == 2 and not off_dropped
	right_arm.get_node("Palm").show()
	left_arm.get_node("Palm").show()
	main_mount.get_child(0).visible = main_hand != "fists" and not throwing
	right_hand.get_child(0).visible = main_hand != "fists" and not throwing
	view_knife.visible = throwing and special_pending
	body_knife.visible = throwing and special_pending
	view_right_arm.show()
	view_left_arm.visible = active_slot == 2
	_pose_view_arm(view_right_arm, main_mount.position, main_mount.rotation, 1.0)
	if elbow_attack:
		var sweep: float = 0
		if attack_duration > 0:
			var elbow_phase: float = Timing.pose_phase(main_hand, attack_elapsed, attack_heavy)
			sweep = smoothstep(0.42, 0.64, elbow_phase) * (1 - smoothstep(0.68, 1.0, elbow_phase))
		view_right_arm.position = Vector3(0.58, -0.25, -0.05).lerp(Vector3(0.42, -0.27, -0.15), elbow_weight) + Vector3(-0.6, 0, -0.18) * sweep
		var view_pole: Vector3 = Vector3(0.1, -1, 0.15).lerp(Vector3(-1, 0.15, -1), elbow_weight)
		Visuals.pose_arm(view_right_arm, main_mount.position, main_mount.rotation, 1.0, Vector2(0.46, 0.36), view_pole, 0.55)
		view_right_arm.get_node("Palm").scale = Vector3.ONE * 0.55
	_pose_view_arm(view_left_arm, off_mount.position, off_mount.rotation, -1.0)
	if bow_active():
		_pose_archery(left_arm, right_arm, throwing)
	else:
		body_bow.visible = active_slot == 2 and not off_dropped
	view_left_arm.visible = active_slot == 2 and (not off_dropped or (throwing_item and item_throw_left))
	view_kick_leg.visible = special_action == "kick"
	if special_action == "kick":
		_pose_kick()
	view_model.position = Vector3(view_sway.x, view_sway.y, 0) + Vector3(sin(gait_phase) * 0.008, abs(cos(gait_phase)) * 0.012, 0) * gait_blend * (0.2 if zooming else 1.0)

func _throw_pose(rest: Dictionary) -> Dictionary:
	var wind := {"position": Vector3(0.5, -0.03, -0.45), "rotation": Vector3(1.1, -0.1, -0.1), "hand": Vector3(0.4, 0.6, -0.12), "wrist": Vector3(1.1, -0.1, -0.1)}
	var release := {"position": Vector3(0.15, -0.06, -0.88), "rotation": Vector3.ZERO, "hand": Vector3(0.14, 0.43, -0.48), "wrist": Vector3.ZERO}
	if special_elapsed < 0.12:
		return WeaponPoses.blend(rest, wind, smoothstep(0, 0.12, special_elapsed))
	if special_elapsed < THROW_RELEASE:
		return WeaponPoses.blend(wind, release, smoothstep(0.12, THROW_RELEASE, special_elapsed))
	return WeaponPoses.blend(release, rest, smoothstep(THROW_RELEASE, THROW_DURATION, special_elapsed))

func _item_throw_pose(rest: Dictionary) -> Dictionary:
	var wind := {"position": Vector3(0.55, 0.16, -0.4), "rotation": Vector3(1.95, 0, -0.2), "hand": Vector3(0.42, 0.66, -0.12), "wrist": Vector3(1.95, 0, -0.2)}
	var release := {"position": Vector3(0.1, -0.1, -1.02), "rotation": Vector3(-0.15, 0, -0.1), "hand": Vector3(0.14, 0.33, -0.5), "wrist": Vector3(-0.15, 0, -0.1)}
	if item_throw_kind == "spear":
		wind.rotation = Vector3(-0.15, 0, 0.12)
		wind.wrist = wind.rotation
		release.rotation = Vector3.ZERO
		release.wrist = Vector3.ZERO
	if special_elapsed < 0.2:
		return WeaponPoses.blend(rest, wind, smoothstep(0, 0.2, special_elapsed))
	if special_elapsed < ITEM_THROW_RELEASE:
		return WeaponPoses.blend(wind, release, smoothstep(0.2, ITEM_THROW_RELEASE, special_elapsed))
	return WeaponPoses.blend(release, rest, smoothstep(ITEM_THROW_RELEASE, ITEM_THROW_DURATION, special_elapsed))

func _shield_throw_pose() -> Dictionary:
	var rest := {"position": Vector3(-0.68, -0.43, -0.85), "rotation": Vector3(0.15, -0.18, -0.1), "hand": Vector3(-0.36, 0.07, -0.14), "wrist": Vector3.ZERO}
	var wind := {"position": Vector3(-0.55, -0.14, -0.62), "rotation": Vector3(PI / 2, 0, -0.2), "hand": Vector3(-0.43, 0.38, -0.17), "wrist": Vector3(PI / 2, 0, -0.2)}
	var release := {"position": Vector3(0.2, -0.06, -0.9), "rotation": Vector3(PI / 2, 0.25, 0), "hand": Vector3(0.07, 0.35, -0.45), "wrist": Vector3(PI / 2, 0.25, 0)}
	if special_elapsed < 0.2:
		return WeaponPoses.blend(rest, wind, smoothstep(0, 0.2, special_elapsed))
	if special_elapsed < ITEM_THROW_RELEASE:
		return WeaponPoses.blend(wind, release, smoothstep(0.2, ITEM_THROW_RELEASE, special_elapsed))
	return WeaponPoses.blend(release, rest, smoothstep(ITEM_THROW_RELEASE, ITEM_THROW_DURATION, special_elapsed))

func throw_held_item() -> void:
	if not controls_active or not is_alive or bow_active() or _melee_busy() or not special_action.is_empty() or get_tree().get_nodes_in_group("thrown_items").size() >= 32:
		return
	item_throw_left = main_hand == "fists"
	if item_throw_left:
		if active_slot != 2 or off_hand != "shield" or off_dropped:
			return
		item_throw_kind = "shield"
	else:
		item_throw_kind = main_hand
	_begin_special("item")

func _release_held_item() -> void:
	var item := ThrownItem.new()
	item.kind = item_throw_kind
	item.shooter = self
	var origin: Vector3 = _combat_eye()
	var direction: Vector3 = (aim_point() - origin).normalized()
	get_parent().add_child(item)
	item.launch(origin + direction * 0.25, direction)
	if item_throw_left:
		off_dropped = true
		shield_requested = false
	else:
		main_hand = "fists"
		_reset_melee(true)
		for mount: Node3D in [main_mount, body_model.get_node("Upper/RightArm/Hand")]:
			var old: Node = mount.get_child(0)
			mount.remove_child(old)
			old.queue_free()
			var fists: Node3D = Visuals.weapon("fists")
			mount.add_child(fists)
			mount.move_child(fists, 0)
		_set_shadow_mode(view_model, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		body_view_mode = -1
	equipment_changed.emit()

func _pose_kick() -> void:
	var times: Vector3 = Timing.durations("kick")
	var lift: float = smoothstep(0, times.x, special_elapsed)
	var strike: float = smoothstep(times.x, times.x + times.y, special_elapsed)
	var recover: float = 1 - smoothstep(times.x + times.y, Timing.total("kick"), special_elapsed)
	var hip: float = lerpf(0.95 * lift, 1.65, strike) * recover
	var knee: float = lerpf(-1.5 * lift, -0.15, strike) * recover
	var leg: Node3D = body_model.get_node("RightLeg")
	leg.rotation.x = hip
	leg.get_node("Knee").rotation.x = knee
	body_model.get_node("Upper").rotation.x = 0.12 * lift * recover
	view_kick_leg.rotation.x = lerpf(0.7 * lift, 2.15, strike) * recover
	view_kick_leg.get_node("Knee").rotation.x = knee

func cancel_special() -> void:
	special_action = ""
	special_elapsed = 0
	special_pending = false
	if is_instance_valid(view_kick_leg):
		view_kick_leg.hide()
	if is_instance_valid(view_knife) and is_instance_valid(body_knife):
		view_knife.hide()
		body_knife.hide()
		main_mount.visible = not bow_active()
		main_mount.get_child(0).visible = main_hand != "fists"
		var hand: Node3D = body_model.get_node("Upper/RightArm/Hand")
		hand.visible = not bow_active()
		hand.get_child(0).visible = main_hand != "fists"
	if is_instance_valid(body_model):
		body_model.get_node("Upper").rotation.x = 0
		body_model.get_node("RightLeg").rotation.x = 0
		body_model.get_node("RightLeg/Knee").rotation.x = 0

func throw_knife() -> void:
	if not controls_active or not is_alive or _melee_busy() or not special_action.is_empty() or get_tree().get_nodes_in_group("throwing_knives").size() >= 16:
		return
	_begin_special("throw")

func kick() -> void:
	if not controls_active or not is_alive or prone or not is_on_floor() or _melee_busy() or not special_action.is_empty():
		return
	_begin_special("kick")

func _can_block() -> bool:
	if not shield_requested or active_slot != 2 or off_hand != "shield" or off_dropped:
		return false
	if special_action == "shield":
		return Timing.stage("shield", special_elapsed) == "windup"
	return not _melee_busy() and special_action.is_empty()

func shield_attack() -> void:
	if not controls_active or not is_alive or not blocking or not _can_block() or _melee_busy() or not special_action.is_empty():
		return
	var arm: Node3D = body_model.get_node("Upper/LeftArm")
	shield_start_pose = {"position": off_mount.position, "rotation": off_mount.rotation, "hand": arm.get_parent().to_local(arm.get_node("Hand").global_position), "wrist": off_mount.rotation}
	_begin_special("shield")
	shield_blend = 1
	blocking = _can_block()

func _resolve_shield() -> bool:
	if special_action != "shield" or not special_pending or Timing.stage("shield", special_elapsed) != "active":
		return false
	var origin: Vector3 = get_combat_aim_point()
	var direction: Vector3 = (aim_point() - origin).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1.65, 3, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	special_pending = false
	if hit.collider.has_method("take_shield_hit"):
		if hit.collider.take_shield_hit(hit.position, direction):
			last_hit_critical = false
			hit_confirmed.emit()
	elif hit.collider.has_method("take_melee_hit"):
		if hit.collider.take_melee_hit(hit.position, direction, Combat.SHIELD, false):
			last_hit_critical = false
			hit_confirmed.emit()
	return true

func _begin_special(action: String) -> void:
	cancel_bow()
	special_action = action
	special_elapsed = 0
	special_pending = true
	blocking = false
	_update_weapon_pose()

func _release_knife() -> void:
	if get_tree().get_nodes_in_group("throwing_knives").size() >= 16:
		return
	var knife := Arrow.new()
	knife.projectile_kind = "throwing_knife"
	knife.exclusions = [get_rid()]
	knife.shooter = self
	var origin: Vector3 = _combat_eye()
	knife.velocity = (aim_point() - origin).normalized() * 38.0
	get_parent().add_child(knife)
	knife.global_position = origin
	knife.look_at(origin + knife.velocity.normalized())

func _resolve_kick() -> bool:
	if special_action != "kick" or not special_pending or Timing.stage("kick", special_elapsed) != "active":
		return false
	var origin: Vector3 = to_global(Vector3(0, 0.9, 0))
	var direction: Vector3 = -global_basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * KICK_REACH, 3, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	special_pending = false
	if not hit.is_empty() and hit.collider.has_method("take_hit"):
		if hit.collider.has_method("take_kick"):
			hit.collider.take_kick(hit.position, direction)
		else:
			hit.collider.take_hit(hit.position, direction)
		last_hit_critical = false
		hit_confirmed.emit()
	return true

func _pose_view_arm(arm: Node3D, wrist: Vector3, rotation: Vector3, side: float) -> void:
	# A downward elbow keeps the arm beside the body, with a relaxed idle bend.
	# Extend only for the farthest attack poses so the glove stays on the grip.
	arm.position = Vector3(side * 0.58, -0.25, -0.05)
	var lengths := Vector2(0.46, 0.36)
	var extension: float = maxf(1.0, arm.position.distance_to(wrist) / ((lengths.x + lengths.y) * 0.98))
	Visuals.pose_arm(arm, wrist, rotation, side, lengths * extension, Vector3(side * 0.1, -1, 0.15), 0.55)
	arm.get_node("Palm").scale = Vector3.ONE * 0.55

func _pose_archery(left_arm: Node3D, right_arm: Node3D, throwing: bool) -> void:
	var nock_progress: float = smoothstep(0, BOW_NOCK_TIME, bow_prepare_elapsed)
	var draw: float = bow_visual_draw()
	var arrow_visible: bool = bow_phase in [BowPhase.NOCK, BowPhase.READY] and not sprinting and special_action.is_empty() and is_alive
	# No new arrow during feedback/recovery. Both rigs follow the same string.
	if bow_phase in [BowPhase.RELEASE, BowPhase.STRING, BowPhase.COOLDOWN]:
		nock_progress = 1.0
	var view_bow: Node3D = off_mount.get_child(0)
	var zoom_ratio: float = tan(deg_to_rad(camera.fov) / 2) / tan(deg_to_rad(base_fov) / 2)
	var grip_x: float = 0.38 * zoom_ratio
	off_mount.position = Vector3(0.15, -0.51, -0.68).lerp(Vector3(grip_x, -0.11, -0.91), bow_stance)
	off_mount.rotation = Vector3(0.12, 0.03, -1.12).lerp(Vector3(0, 0, 0.06), bow_stance)
	off_mount.scale = Vector3(0.7 * zoom_ratio, 0.7 * zoom_ratio, 0.7)
	Visuals.pose_bow(view_bow, draw, arrow_visible, nock_progress, 0.0)
	view_bow.get_node("DrawHand").hide()
	_pose_view_arm(view_left_arm, off_mount.position, off_mount.rotation, -1.0)

	# Solve the grips in model space while the torso turns side-on.
	var upper: Node3D = left_arm.get_parent()
	var pitch: float = clampf(look_pitch, -0.92, 0.92)
	var aim_pivot := Vector3(-0.10, 0.52, -0.22)
	var aim_grip: Vector3 = aim_pivot + Basis(Vector3.RIGHT, pitch) * (Vector3(-0.088, 0.75, -0.84) - aim_pivot)
	var carry_grip := Vector3(-0.17, 0.22, -0.29)
	var grip: Vector3 = carry_grip.lerp(aim_grip, bow_stance)
	var carry_rotation := Vector3(0.16, 0.05, -1.08)
	var rotation_model: Vector3 = carry_rotation.lerp(Vector3(pitch, 0, 0), bow_stance)
	var upper_inverse: Basis = upper.basis.inverse()
	var wrist: Vector3 = (upper_inverse * Basis.from_euler(rotation_model)).get_euler()
	var left_target: Vector3 = upper_inverse * grip
	var reach_fraction: float = lerpf(0.985, 0.9999, bow_stance)
	var arm_extension: float = maxf(1.0, left_arm.position.distance_to(left_target) / ((ARM_LENGTHS.x + ARM_LENGTHS.y) * reach_fraction))
	Visuals.pose_arm(left_arm, left_target, wrist, -1.0, ARM_LENGTHS * arm_extension, upper_inverse * Vector3(-0.25, -1, 0.35), 1.0, reach_fraction)
	body_bow.position = Vector3.ZERO
	body_bow.rotation = Vector3.ZERO
	body_bow.scale = Vector3(1, 1, BOW_BODY_DEPTH)
	body_bow.show()
	Visuals.pose_bow(body_bow, draw, arrow_visible, nock_progress, BOW_BODY_LATERAL_PULL)
	body_bow.get_node("DrawHand").hide()
	if throwing:
		return

	var carry_hold := Vector3(0, 0.36, 0.014)
	var nock_offset: Vector3 = Vector3(0.10, -0.25, 0.20) * (1 - nock_progress)
	var bow_fingers: Vector3 = Visuals.bow_nock(draw, BOW_BODY_LATERAL_PULL) + nock_offset + Vector3(0.025, 0.012, 0.028)
	var draw_grip: Vector3 = upper.to_local(body_bow.to_global(carry_hold.lerp(bow_fingers, bow_stance)))
	var draw_elbow: Vector3 = Vector3(0.36, -1.0, 0.42).lerp(Vector3(0.75, 0.22, 1.0), draw * bow_stance)
	var draw_wrist: Vector3 = wrist.lerp(Vector3(0, 1.15, -0.18), draw * bow_stance)
	Visuals.pose_arm(right_arm, draw_grip, draw_wrist, 1.0, ARM_LENGTHS, upper_inverse * draw_elbow)
	var view_fingers: Vector3 = Visuals.bow_nock(draw, 0.0) + nock_offset + Vector3(0.07, 0.015, 0.055)
	var view_grip: Vector3 = view_model.to_local(view_bow.to_global(carry_hold.lerp(view_fingers, bow_stance)))
	_pose_view_arm(view_right_arm, view_grip, Vector3(0, 0, -0.15), 1.0)
	right_arm.get_node("Hand").hide()

func _set_bow_phase(phase: BowPhase) -> void:
	bow_phase = phase
	bow_phase_elapsed = 0
	bow_prepare_elapsed = BOW_PREPARE_TIME if phase == BowPhase.READY else 0.0

func cancel_bow() -> void:
	# All interruptions restart equipment, including sprint: no preserved shot,
	# unfinished equip, or recovery can be used to skip the next 0.85 seconds.
	_set_bow_phase(BowPhase.EQUIP if bow_active() else BowPhase.INACTIVE)
	bow_stance = 0
	zooming = false
	if is_instance_valid(camera):
		camera.fov = base_fov

func bow_ready() -> bool:
	return controls_active and is_alive and bow_active() and not sprinting and special_action.is_empty() and bow_phase == BowPhase.READY

func bow_visual_draw() -> float:
	match bow_phase:
		BowPhase.NOCK:
			return smoothstep(BOW_NOCK_TIME, BOW_PREPARE_TIME, bow_prepare_elapsed)
		BowPhase.READY:
			return 1.0
		BowPhase.RELEASE:
			# Cosmetic overpull then release only: the projectile already exists.
			var t: float = bow_phase_elapsed / BOW_RELEASE_TIME
			return lerpf(1.0, 1.12, t / 0.4) if t < 0.4 else lerpf(1.12, 0.0, smoothstep(0.4, 1.0, t))
		BowPhase.STRING:
			var t: float = bow_phase_elapsed / BOW_STRING_TIME
			return sin(t * TAU * 2.0) * 0.12 * (1.0 - t)
	return 0.0

func bow_status() -> String:
	match bow_phase:
		BowPhase.EQUIP: return "Taking out bow"
		BowPhase.NOCK: return "Nocking and drawing arrow"
		BowPhase.RELEASE: return "Arrow released"
		BowPhase.STRING: return "Bowstring settling"
		BowPhase.COOLDOWN: return "Bow recovery"
	return ""

func _tick_bow(delta: float) -> void:
	var aiming: bool = controls_active and is_alive and bow_active() and not sprinting and special_action.is_empty()
	if not aiming:
		_set_bow_phase(BowPhase.EQUIP if bow_active() else BowPhase.INACTIVE)
		bow_stance = move_toward(bow_stance, 0.0, delta / 0.16)
		return
	if bow_phase == BowPhase.INACTIVE:
		_set_bow_phase(BowPhase.EQUIP)
	# Consume overflow across explicit stages, including large/variable frames.
	var remaining: float = maxf(delta, 0.0)
	while bow_phase != BowPhase.READY:
		var duration: float
		var next: BowPhase
		match bow_phase:
			BowPhase.EQUIP:
				duration = BOW_EQUIP_TIME
				next = BowPhase.NOCK
			BowPhase.NOCK:
				duration = BOW_PREPARE_TIME
				next = BowPhase.READY
			BowPhase.RELEASE:
				duration = BOW_RELEASE_TIME
				next = BowPhase.STRING
			BowPhase.STRING:
				duration = BOW_STRING_TIME
				next = BowPhase.COOLDOWN
			_:
				duration = BOW_COOLDOWN_TIME
				next = BowPhase.NOCK
		var step: float = minf(remaining, duration - bow_phase_elapsed)
		bow_phase_elapsed += step
		remaining -= step
		if bow_phase == BowPhase.NOCK:
			bow_prepare_elapsed = bow_phase_elapsed
		if bow_phase_elapsed + 0.0000001 < duration:
			break
		_set_bow_phase(next)
		if remaining <= 0:
			break
	bow_stance = smoothstep(0, BOW_EQUIP_TIME, bow_phase_elapsed) if bow_phase == BowPhase.EQUIP else 1.0

func _animate_locomotion(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var target: float = minf(speed / WALK_SPEED, 1.5) if is_on_floor() else 0.0
	gait_blend = lerpf(gait_blend, target, 1 - exp(-12 * delta))
	gait_phase += speed * 1.9 * delta
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = body_model.get_node("RightLeg" if side > 0 else "LeftLeg")
		var step: float = sin(gait_phase) * side
		leg.rotation.x = step * gait_blend * 0.44
		leg.get_node("Knee").rotation.x = maxf(0, -step) * gait_blend * 0.5
		if not is_on_floor():
			leg.rotation.x = 0.18 * side
			leg.get_node("Knee").rotation.x = 0.3
	body_model.position = Vector3(0, abs(sin(gait_phase * 2)) * gait_blend * 0.018, 0)
	var upper: Node3D = body_model.get_node("Upper")
	var archery: float = bow_stance if bow_active() else 0.0
	upper.rotation.y = -0.98 * archery
	upper.rotation.z = sin(gait_phase) * gait_blend * 0.025 * (1 - archery)
	if archery > 0 and is_on_floor() and not prone:
		var footing: float = archery * lerpf(1.0, 0.75, smoothstep(0.05, WALK_SPEED, speed))
		var left_leg: Node3D = body_model.get_node("LeftLeg")
		var right_leg: Node3D = body_model.get_node("RightLeg")
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.28, footing)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, -0.25, footing)
		left_leg.get_node("Knee").rotation.x = lerpf(left_leg.get_node("Knee").rotation.x, 0.08, footing)
		right_leg.get_node("Knee").rotation.x = lerpf(right_leg.get_node("Knee").rotation.x, 0.04, footing)
		body_model.position.y -= 0.026 * footing
	body_model.rotation.x = -PI / 2 * prone_blend
	body_model.position += Vector3(0, 0.34, 0.55) * prone_blend
	var helmet: Node3D = upper.get_node("Helmet")
	helmet.rotation.y = -upper.rotation.y
	helmet.rotation.x = PI / 2 * prone_blend + clampf(look_pitch, -0.92, 0.92) * archery * (1 - prone_blend)
	if prone_blend > 0.01:
		for side: float in [-1.0, 1.0]:
			var leg: Node3D = body_model.get_node("RightLeg" if side > 0 else "LeftLeg")
			leg.rotation.x *= 0.2
			leg.rotation.y = side * sin(gait_phase) * gait_blend * 0.12
	else:
		body_model.get_node("RightLeg").rotation.y = 0
		body_model.get_node("LeftLeg").rotation.y = 0

func die() -> void:
	if not is_alive:
		return
	health = 0
	health_changed.emit()
	var inherited_velocity: Vector3 = velocity * 0.45
	is_alive = false
	set_controls_active(false)
	attack_duration = 0
	attack_pending = false
	death_elapsed = 0
	death_reported = false
	velocity.x = 0
	velocity.z = 0
	body_model.get_node("Upper").rotation = Vector3.ZERO
	collision_layer = 0
	ragdoll = Ragdoll.new()
	get_parent().add_child(ragdoll)
	ragdoll.build(body_model, inherited_velocity)
	ragdoll.keep_for_death_view = true
	death_yaw = rotation.y + 0.55
	death_pitch = -0.35
	death_closeup = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	death_focus = ragdoll.focus_position()
	_update_camera()
	death_started.emit()

func _melee_busy() -> bool:
	return attack_duration > 0 or melee_held or (main_hand == "dagger" and dagger_flip_elapsed < GRIP_FLIP_TIME)

func _can_alternate() -> bool:
	return main_hand in ["dagger", "longsword", "mace"] and not (main_hand == "dagger" and dagger_reverse)

func _charge_limit() -> float:
	return Timing.durations(main_hand, true).x

func _spear_ready_pose() -> Dictionary:
	return WeaponPoses.sample("spear", Timing.ready_pose("spear"), true)

func _begin_spear_switch() -> void:
	if main_hand == "spear" and (spear_carry > 0.01 or sprinting):
		spear_switch_from = _melee_pose()
		spear_switch_remaining = SPEAR_SWITCH_TIME

func _melee_pose() -> Dictionary:
	if spear_switch_remaining > 0:
		return WeaponPoses.blend(spear_switch_from, _spear_ready_pose(), smoothstep(0, SPEAR_SWITCH_TIME, SPEAR_SWITCH_TIME - spear_switch_remaining))
	var phase: float = Timing.pose_phase(main_hand, attack_elapsed, attack_heavy) if attack_duration > 0 else 0.0
	var stage: String = Timing.stage(main_hand, attack_elapsed, attack_heavy) if attack_duration > 0 else "idle"
	if stage in ["cooldown", "done"] and (attack_buffered or melee_held) and _can_alternate() and not attack_heavy:
		phase = minf(phase, 0.7)
	var pose: Dictionary = WeaponPoses.sample(main_hand, phase, attack_duration > 0, dagger_reverse, swing_direction, attack_heavy, attack_chained)
	if melee_held and attack_duration <= 0:
		var wind: Dictionary = WeaponPoses.sample(main_hand, Timing.ready_pose(main_hand, true), true, dagger_reverse, 1, true)
		var initial: Dictionary = charge_start_pose if not charge_start_pose.is_empty() else WeaponPoses.sample(main_hand, 0, false, dagger_reverse)
		var ready_at: float = _charge_limit() * (0.8 if main_hand == "spear" else 1.0)
		pose = WeaponPoses.blend(initial, wind, smoothstep(0, ready_at, charge_elapsed))
	if main_hand == "dagger" and attack_duration <= 0 and not melee_held:
		var flipping: float = sin(dagger_grip_blend * PI)
		pose.rotation = Vector3(lerpf(1.5, -1.5, dagger_grip_blend), 0, flipping * 0.55)
		pose.wrist = pose.rotation
		pose.position += Vector3(-0.08, 0.08, 0.02) * flipping
	if stage == "windup" and not attack_start_pose.is_empty():
		var ready: float = Timing.ready_pose(main_hand, attack_heavy)
		var wind_end: float = Timing.durations(main_hand, attack_heavy).x * (0.8 if main_hand == "spear" else 1.0)
		var prepared: Dictionary = WeaponPoses.sample(main_hand, ready, true, dagger_reverse, swing_direction, attack_heavy, attack_chained)
		pose = WeaponPoses.blend(attack_start_pose, prepared, smoothstep(attack_pose_start_elapsed, maxf(wind_end, attack_pose_start_elapsed + 0.001), attack_elapsed))
	if main_hand == "spear" and attack_duration <= 0 and not melee_held:
		pose = WeaponPoses.blend(pose, WeaponPoses.spear_carry(), spear_carry)
	return pose

func _cancel_melee_input() -> void:
	if attack_duration <= 0:
		spear_switch_remaining = 0
		spear_switch_from.clear()
	melee_held = false
	charge_elapsed = 0
	charge_start_pose.clear()
	attack_buffered = false
	buffered_heavy = false
	dagger_flip_queued = false

func _reset_melee(reset_grip: bool = false) -> void:
	spear_switch_remaining = 0
	spear_switch_from.clear()
	spear_carry = 0
	_cancel_melee_input()
	attack_duration = 0
	attack_elapsed = 0
	attack_pending = false
	attack_heavy = false
	attack_chained = false
	attack_start_pose.clear()
	combo_window = 0
	swing_direction = 1
	if reset_grip:
		dagger_reverse = false
	dagger_grip_blend = 1.0 if dagger_reverse else 0.0
	dagger_flip_elapsed = GRIP_FLIP_TIME
	last_hit_critical = false

func request_dagger_flip() -> void:
	if not controls_active or not is_alive or main_hand != "dagger" or bow_active() or not special_action.is_empty() or dagger_flip_elapsed < GRIP_FLIP_TIME:
		return
	if attack_duration > 0:
		dagger_flip_queued = not dagger_flip_queued
		melee_held = false
		attack_buffered = false
		return
	_cancel_melee_input()
	dagger_reverse = not dagger_reverse
	dagger_flip_from = dagger_grip_blend
	dagger_flip_elapsed = 0
	combo_window = 0
	blocking = false
	equipment_changed.emit()

func begin_melee_charge() -> void:
	if not controls_active or not is_alive or blocking or bow_active() or not special_action.is_empty() or melee_held or dagger_flip_elapsed < GRIP_FLIP_TIME:
		return
	if attack_duration > 0 and (not _can_alternate() or attack_heavy or Timing.stage(main_hand, attack_elapsed, attack_heavy) == "windup" or attack_buffered):
		return
	_begin_spear_switch()
	charge_start_pose = _spear_ready_pose() if spear_switch_remaining > 0 else _melee_pose()
	melee_held = true
	charge_elapsed = 0

func release_melee_charge() -> void:
	if not melee_held:
		return
	if attack_duration > 0:
		melee_held = false
		attack_buffered = true
		buffered_heavy = false
	else:
		var held_time: float = charge_elapsed
		var heavy: bool = held_time >= _charge_limit()
		_start_attack(heavy, combo_window > 0 and _can_alternate() and not heavy, heavy)

func attack() -> void:
	if blocking:
		shield_attack()
		return
	if not controls_active or not is_alive or _melee_busy() or bow_active() or not special_action.is_empty():
		return
	_begin_spear_switch()
	_start_attack(false, combo_window > 0 and _can_alternate())

func _start_attack(heavy: bool, chained: bool, prepared: bool = false) -> void:
	var from: Dictionary = _spear_ready_pose() if spear_switch_remaining > 0 else _melee_pose()
	swing_direction = -swing_direction if chained and not heavy else 1
	attack_heavy = heavy
	attack_chained = chained and not heavy
	attack_duration = Timing.total(main_hand, heavy)
	attack_elapsed = Timing.durations(main_hand, heavy).x if heavy and prepared else 0.0
	attack_pose_start_elapsed = attack_elapsed
	attack_pending = true
	attack_start_pose = from
	combo_window = 0
	melee_held = false
	charge_elapsed = 0
	charge_start_pose.clear()
	attack_buffered = false
	buffered_heavy = false

func _tick_melee(delta: float) -> void:
	if spear_switch_remaining > 0:
		var switched: float = minf(delta, spear_switch_remaining)
		spear_switch_remaining -= switched
		delta -= switched
		if spear_switch_remaining > 0.000001:
			return
		spear_switch_remaining = 0
		spear_switch_from.clear()
		spear_carry = 0
	var started: bool = false
	if melee_held and attack_duration <= 0:
		var elapsed_hold: float = charge_elapsed + delta
		charge_elapsed = minf(_charge_limit(), elapsed_hold)
		if elapsed_hold + 0.000001 >= _charge_limit():
			var overflow: float = maxf(0, elapsed_hold - _charge_limit())
			_start_attack(true, false, true)
			attack_elapsed += overflow
			started = true
	if dagger_flip_elapsed < GRIP_FLIP_TIME:
		dagger_flip_elapsed = minf(GRIP_FLIP_TIME, dagger_flip_elapsed + delta)
		dagger_grip_blend = lerpf(dagger_flip_from, 1.0 if dagger_reverse else 0.0, smoothstep(0, GRIP_FLIP_TIME, dagger_flip_elapsed))
	if attack_duration > 0:
		if not started:
			attack_elapsed += delta
		if attack_pending and Timing.stage(main_hand, attack_elapsed, attack_heavy) == "active":
			if _resolve_melee():
				attack_pending = false
		if Timing.stage(main_hand, attack_elapsed, attack_heavy) == "done":
			var continued_pose: Dictionary = _melee_pose()
			var queued: bool = attack_buffered
			var overflow: float = maxf(0, attack_elapsed - attack_duration)
			combo_window = 0.24 if _can_alternate() and not attack_heavy else 0
			if queued:
				_start_attack(false, true)
				attack_elapsed += overflow
			else:
				attack_duration = 0
				attack_heavy = false
				attack_pending = false
				attack_start_pose.clear()
				if melee_held:
					charge_start_pose = continued_pose
					charge_elapsed = 0
	else:
		combo_window = maxf(0, combo_window - delta)
		if combo_window == 0 and not melee_held:
			swing_direction = 1
	if dagger_flip_queued and attack_duration <= 0:
		dagger_flip_queued = false
		request_dagger_flip()

func aim_point() -> Vector3:
	var origin: Vector3 = camera.global_position
	var end: Vector3 = origin - camera.global_basis.z * 200.0
	if third_person and front_view:
		origin = _combat_eye()
		end = origin + global_basis * Basis(Vector3.RIGHT, look_pitch) * Vector3.FORWARD * 200
	var query := PhysicsRayQueryParameters3D.create(origin, end, 3, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else end

func _resolve_melee() -> bool:
	if spear_switch_remaining > 0 or attack_duration <= 0 or not attack_pending or Timing.stage(main_hand, attack_elapsed, attack_heavy) != "active":
		return false
	var eye: Vector3 = _combat_eye()
	var direction: Vector3 = (aim_point() - eye).normalized()
	var query := PhysicsRayQueryParameters3D.create(eye, eye + direction * float(WEAPONS[main_hand].reach), 3, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	attack_pending = false
	if not hit.is_empty() and hit.collider.has_method("take_hit"):
		var damage: float = float(WEAPONS[main_hand].damage) * (2.0 if attack_heavy and main_hand != "fists" else 1.0)
		if hit.collider.has_method("take_melee_hit"):
			if not hit.collider.take_melee_hit(hit.position, direction, damage, attack_heavy):
				return true
		else:
			hit.collider.take_hit(hit.position, direction)
		last_hit_critical = attack_heavy
		hit_confirmed.emit()

	return not hit.is_empty()

func shoot_bow() -> void:
	if not controls_active or not is_alive or not bow_ready() or get_tree().get_nodes_in_group("arrows").size() >= 16:
		return
	_set_bow_phase(BowPhase.RELEASE)
	var arrow := Arrow.new()
	arrow.exclusions = [get_rid()]
	arrow.shooter = self
	var eye: Vector3 = _combat_eye()
	arrow.velocity = (aim_point() - eye).normalized() * 45.0
	get_parent().add_child(arrow)
	arrow.global_position = eye
	arrow.look_at(eye + arrow.velocity.normalized())
	_update_weapon_pose()

func set_controls_active(active: bool) -> void:
	controls_active = active and is_alive
	if not active:
		cancel_bow()
		_cancel_melee_input()
		if special_action not in ["kick", "shield"]:
			cancel_special()
		blocking = false
		shield_requested = false
		_reset_sway()
		sprinting = false
		zooming = false
		camera.fov = base_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if controls_active else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if not is_alive:
		if event is InputEventMouseMotion and not get_tree().paused:
			death_yaw -= event.relative.x * MOUSE_SENSITIVITY
			death_pitch = clampf(death_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.25, 0.5)
			_update_camera()
		return
	if not controls_active:
		return
	if event.is_action_pressed("toggle_view"):
		toggle_view()
	if event.is_action_pressed("main_slot"):
		select_slot(1)
	if event.is_action_pressed("off_slot"):
		select_slot(2)
	if event.is_action_pressed("throw_knife"):
		throw_knife()
	if event.is_action_pressed("kick"):
		kick()
	if event.is_action_pressed("flip_dagger"):
		interact_pickup_or_flip()
	if event.is_action_pressed("throw_item"):
		throw_held_item()
	if event.is_action_pressed("prone"):
		toggle_prone()
	if event is InputEventMouseMotion and controls_active:
		var sensitivity: float = MOUSE_SENSITIVITY * (0.5 if zooming else 1.0)
		look_motion += event.relative * sensitivity
		rotate_y(-event.relative.x * sensitivity)
		look_pitch = clampf(look_pitch - event.relative.y * sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		_update_camera()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if bow_active():
				if event.pressed:
					shoot_bow()
			elif event.pressed:
				if blocking:
					shield_attack()
				else:
					begin_melee_charge()
			else:
				release_melee_charge()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if bow_active():
				zooming = event.pressed and not sprinting
			else:
				shield_requested = event.pressed and active_slot == 2 and off_hand == "shield" and not off_dropped
				blocking = _can_block()

func _physics_process(delta: float) -> void:
	if not is_alive:
		death_elapsed += delta
		_update_camera()
		if is_instance_valid(ragdoll) and ragdoll.settled and death_elapsed >= 1.05 and not death_reported:
			death_reported = true
			death_finished.emit()
		return
	prone_blend = move_toward(prone_blend, 1.0 if prone else 0.0, delta / 0.28)
	if not special_action.is_empty():
		special_elapsed += delta
		if special_action in ["kick", "shield"]:
			if special_pending and Timing.stage(special_action, special_elapsed) == "active":
				var contact: bool = _resolve_kick() if special_action == "kick" else _resolve_shield()
				if contact:
					special_pending = false
			if Timing.stage(special_action, special_elapsed) == "done":
				cancel_special()
		else:
			var hit_time: float = THROW_RELEASE if special_action == "throw" else ITEM_THROW_RELEASE
			if special_pending and special_elapsed >= hit_time:
				special_pending = false
				if special_action == "throw":
					_release_knife()
				else:
					_release_held_item()
			var duration: float = THROW_DURATION if special_action == "throw" else ITEM_THROW_DURATION
			if special_elapsed >= duration:
				cancel_special()
	_update_sway(delta)
	var zoom_fov: float = rad_to_deg(2 * atan(tan(deg_to_rad(base_fov) * 0.5) / 2))
	camera.fov = lerpf(camera.fov, zoom_fov if zooming and bow_active() else base_fov, 1 - exp(-16 * delta))
	_tick_melee(delta)
	blocking = _can_block()
	if special_action == "shield":
		shield_blend = 1
	else:
		shield_blend = move_toward(shield_blend, 1.0 if blocking else 0.0, delta / (0.16 if blocking else 0.2))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	# Horizontal velocity is selected on the ground only. The full takeoff
	# momentum survives key releases, camera turns and sprint changes in midair.
	if controls_active and is_on_floor():
		var movement_input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction: Vector3 = global_transform.basis * Vector3(movement_input.x, 0.0, movement_input.y)
		sprinting = Input.is_action_pressed("sprint") and movement_input.y < -0.1 and not prone
		var speed: float = 1.5 if prone else (SPRINT_SPEED if sprinting else WALK_SPEED)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if Input.is_action_just_pressed("jump") and is_on_floor() and not prone:
			velocity.y = JUMP_SPEED
	elif is_on_floor():
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	if sprinting:
		zooming = false
	_tick_bow(delta)
	if spear_switch_remaining <= 0:
		var carrying: bool = main_hand == "spear" and sprinting and not bow_active() and not _melee_busy() and not blocking and special_action.is_empty()
		spear_carry = move_toward(spear_carry, 1.0 if carrying else 0.0, delta / 0.18)
	_animate_locomotion(delta)
	_update_camera()
	_update_weapon_pose()
	# The map has an edge. Falling off returns the player to the starting point.
	if global_position.y < -20.0:
		global_position = SPAWN_POSITION
		velocity = Vector3.ZERO
