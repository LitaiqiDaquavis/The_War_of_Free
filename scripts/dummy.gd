extends CharacterBody3D

signal defeated_started(attacker: Node)

const Visuals = preload("res://scripts/visuals.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const Combat = preload("res://scripts/combat.gd")
const Poses = preload("res://scripts/weapon_poses.gd")
const Timing = preload("res://scripts/attack_timing.gd")
var spawn_transform: Transform3D
var lethal_source: Dictionary = {}
var health: float = Combat.MAX_HEALTH
var regen_elapsed: float = 0
var struck_ids: Dictionary = {}
var ai_enabled: bool = true
var invulnerable: bool = false
var target: Node3D
var health_label: Label3D
var attack_elapsed: float = -1
var attack_pending: bool = false
var attack_cooldown: float = 0.6
var stagger_timer: float = 0
var walk_phase: float = 0
var strafe_timer: float = 0
var strafe_side: float = 1
var rng := RandomNumberGenerator.new()
var hit_count: int = 0
var reaction: Tween
var upper: Node3D
var active_bursts: int = 0
var generation: int = 0
var model: Node3D
var defeated: bool = false
var death_elapsed: float = 0
var ragdoll: Node3D
var last_melee_damage: float = 0
var last_melee_critical: bool = false

func defeat(attacker: Node = null) -> void:
	if defeated:
		return
	defeated = true
	struck_ids.clear()
	health = 0
	health_label.text = "ENEMY DEFEATED"
	health_label.modulate = Color("b7c2c6")
	death_elapsed = 0
	collision_layer = 0
	if reaction and reaction.is_valid():
		reaction.kill()
	upper.rotation = Vector3.ZERO
	ragdoll = Ragdoll.new()
	get_parent().add_child(ragdoll)
	ragdoll.build(model, velocity * 0.35)
	velocity = Vector3.ZERO
	set_physics_process(true)
	defeated_started.emit(attacker)

func _physics_process(delta: float) -> void:
	Combat.regen_tick(self, delta)
	if defeated:
		death_elapsed += delta
		if is_instance_valid(ragdoll) and ragdoll.settled:
			set_physics_process(false)
		return
	if not ai_enabled:
		return
	if not is_instance_valid(target) or not target.is_alive:
		velocity.x = 0
		velocity.z = 0
		if attack_elapsed >= 0:
			attack_elapsed += delta
			attack_pending = false
			if Timing.stage("longsword", attack_elapsed) == "done":
				attack_elapsed = -1
				attack_cooldown = 0
		_animate_fighter(delta)
		return
	stagger_timer = maxf(0, stagger_timer - delta)
	attack_cooldown = maxf(0, attack_cooldown - delta)
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0
	var distance: float = offset.length()
	var direction: Vector3 = offset.normalized()
	if distance > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1, delta * 8))
	velocity.x = 0
	velocity.z = 0
	if stagger_timer == 0:
		if attack_elapsed >= 0:
			attack_elapsed += delta
			if attack_pending and Timing.stage("longsword", attack_elapsed) == "active":
				if _strike_target() and not Combat.uses_aoe("longsword"):
					attack_pending = false
			if Timing.stage("longsword", attack_elapsed) == "done":
				attack_elapsed = -1
				attack_cooldown = 0
		elif distance < 1.85 and attack_cooldown == 0 and _can_see_target():
			attack_elapsed = 0
			struck_ids.clear()
			attack_pending = true
		elif distance < 45:
			if distance > 1.55:
				velocity += direction * 3.0
			elif attack_cooldown > 0:
				strafe_timer -= delta
				if strafe_timer <= 0:
					strafe_timer = rng.randf_range(0.6, 1.2)
					strafe_side = -1 if rng.randf() < 0.5 else 1
				velocity += Vector3(-direction.z, 0, direction.x) * strafe_side * 0.75
	if not is_on_floor():
		velocity.y -= 18 * delta
	move_and_slide()
	_animate_fighter(delta)
	if global_position.y < -20:
		defeat()

func _can_see_target() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.25, target.get_combat_aim_point(), 3, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == target

func _strike_target() -> bool:
	if attack_elapsed < 0 or not attack_pending or Timing.stage("longsword", attack_elapsed) != "active":
		return false
	return Combat.sweep(self, get_combat_aim_point(), -global_basis.z, 2.1, Combat.MELEE, false, struck_ids) > 0

func _animate_fighter(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	walk_phase += speed * delta * 2
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = model.get_node("RightLeg" if side > 0 else "LeftLeg")
		var step: float = sin(walk_phase) * side * minf(1, speed / 3)
		leg.rotation.x = step * 0.42
		leg.get_node("Knee").rotation.x = maxf(0, -step) * 0.5
	var pose: Dictionary = Poses.sample("longsword", Timing.pose_phase("longsword", maxf(0, attack_elapsed)), attack_elapsed >= 0)
	Visuals.pose_arm(upper.get_node("RightArm"), pose.hand, pose.wrist, 1.0)
	Visuals.pose_arm(upper.get_node("LeftArm"), Vector3(-0.36, 0.07, -0.14), Vector3.ZERO, -1.0)

func reset_for_match() -> void:
	lethal_source.clear()
	if is_instance_valid(ragdoll):
		ragdoll.dispose()
		ragdoll = null
	model.show()
	generation += 1
	hit_count = 0
	last_melee_damage = 0
	last_melee_critical = false
	active_bursts = 0
	defeated = false
	health = Combat.MAX_HEALTH
	regen_elapsed = 0
	struck_ids.clear()
	transform = Combat.free_spawn(self, spawn_transform)
	velocity = Vector3.ZERO
	attack_elapsed = -1
	attack_pending = false
	attack_cooldown = 0.6
	stagger_timer = 0
	collision_layer = 2
	model.position = Vector3.ZERO
	model.rotation = Vector3(0, 0 if ai_enabled else PI, 0)
	for name: String in ["LeftLeg", "RightLeg"]:
		model.get_node(name).rotation = Vector3.ZERO
		model.get_node(name + "/Knee").rotation = Vector3.ZERO
	set_physics_process(true)
	if reaction and reaction.is_valid():
		reaction.kill()
	upper.rotation = Vector3.ZERO
	_update_health_label()
	for arm_name: String in ["LeftArm", "RightArm"]:
		upper.get_node(arm_name).rotation = Vector3.ZERO
	for child: Node in get_children():
		if child is CPUParticles3D:
			remove_child(child)
			child.queue_free()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("combat_actors")
	set_physics_process(true)
	rng.randomize()
	collision_layer = 2
	collision_mask = 3
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.95
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.975
	add_child(collision)
	model = Visuals.humanoid(Color("d62b36"))
	model.rotation.y = 0 if ai_enabled else PI
	rotation.y = PI if ai_enabled else 0
	spawn_transform = transform
	add_child(model)
	upper = model.get_node("Upper")
	if ai_enabled:
		upper.get_node("RightArm/Hand").add_child(Visuals.weapon("longsword"))
	var label := Label3D.new()
	# Retain diagnostic state for lifecycle tests, never render combat text.
	label.visible = false
	health_label = label
	label.position.y = 2.15
	label.font_size = 24
	label.pixel_size = 0.001
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	_update_health_label()

func _update_health_label() -> void:
	health_label.text = "TRAINING ENEMY\nInvulnerable" if invulnerable else "ENEMY SOLDIER\n%d / 100 HP" % health
	health_label.modulate = Color.WHITE

func get_head_position() -> Vector3:
	return model.get_node("Upper/Helmet").global_position

func get_combat_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.15

func take_projectile_hit(point: Vector3, direction: Vector3, kind: String, attacker: Node = null, source: Dictionary = {}) -> bool:
	return _receive_hit(Combat.projectile_damage(kind, Combat.is_head_hit(self, point)), point, direction, 1.0, true, attacker, source if not source.is_empty() else Combat.damage_source(attacker, kind))

func take_kick(point: Vector3, direction: Vector3, attacker: Node = null) -> bool:
	return _receive_hit(Combat.KICK, point, direction, 1.65, false, attacker, Combat.damage_source(attacker, "kick"))

func take_shield_hit(point: Vector3, direction: Vector3, attacker: Node = null) -> bool:
	last_melee_damage = Combat.SHIELD
	last_melee_critical = false
	return _receive_hit(Combat.SHIELD, point, direction, 1.4, false, attacker, Combat.damage_source(attacker, "shield"))

func take_melee_hit(point: Vector3, direction: Vector3, damage: float, critical: bool, attacker: Node = null, source: Dictionary = {}) -> bool:
	if defeated:
		return false
	last_melee_damage = damage
	last_melee_critical = critical
	return _receive_hit(damage, point, direction, 1.7 if critical else 1.0, true, attacker, source)

func take_hit(point: Vector3, direction: Vector3, strength: float = 1.0, bleed: bool = true) -> bool:
	return _receive_hit(Combat.MELEE, point, direction, strength, bleed)

func _receive_hit(damage: float, point: Vector3, direction: Vector3, strength: float = 1.0, bleed: bool = true, attacker: Node = null, source: Dictionary = {}) -> bool:
	if defeated:
		return false
	hit_count += 1
	if not invulnerable:
		health = maxf(0, health - damage)
		if damage > 0:
			regen_elapsed = 0
	stagger_timer = 0.2
	attack_elapsed = -1
	attack_pending = false
	struck_ids.clear()
	attack_cooldown = maxf(0.45, attack_cooldown)
	if reaction and reaction.is_valid():
		reaction.kill()
	var local_direction: Vector3 = upper.get_parent().global_basis.inverse() * direction
	var lean := Vector3(local_direction.z * 0.28, 0, -local_direction.x * 0.28) * strength
	reaction = create_tween()
	reaction.tween_property(upper, "rotation", lean, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reaction.tween_property(upper, "rotation", Vector3.ZERO, 0.38).set_trans(Tween.TRANS_SINE)
	if bleed and active_bursts < 6:
		_blood(point, direction)
	_update_health_label()
	if health <= 0:
		lethal_source = source.duplicate(true) if not source.is_empty() else Combat.damage_source(attacker)
		defeat(attacker)
	return true

func _blood(point: Vector3, direction: Vector3) -> void:
	active_bursts += 1
	var burst := CPUParticles3D.new()
	burst.emitting = false
	burst.amount = 14
	burst.lifetime = 0.45
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.direction = -direction.normalized() + Vector3.UP * 0.3
	burst.spread = 48
	burst.initial_velocity_min = 1
	burst.initial_velocity_max = 2.5
	burst.gravity = Vector3(0, -6, 0)
	var droplet := SphereMesh.new()
	droplet.radius = 0.024
	droplet.height = 0.048
	droplet.radial_segments = 4
	droplet.rings = 2
	droplet.material = Visuals.material(Color("9e1823"))
	burst.mesh = droplet
	add_child(burst)
	burst.global_position = point
	burst.restart()
	burst.emitting = true
	var burst_generation: int = generation
	var burst_ref: WeakRef = weakref(burst)
	get_tree().create_timer(0.6, false).timeout.connect(func() -> void:
		var remaining: Object = burst_ref.get_ref()
		if is_instance_valid(remaining):
			remaining.queue_free()
		if burst_generation == generation:
			active_bursts -= 1)
