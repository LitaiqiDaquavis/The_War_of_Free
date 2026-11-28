extends Node3D

# A death-only, eleven-body ragdoll. Visual bindings retain the current pose
# and equipment, while native rigid bodies and limited joints solve the fall.
const CORPSE_LIFETIME: float = 20.0
var age_real: float = 0
var keep_for_death_view: bool = false
var bodies: Dictionary = {}
var bindings: Array[Dictionary] = []
var model: Node3D
var settled: bool = false
var elapsed: float = 0
var quiet_time: float = 0

func build(source: Node3D, inherited_velocity: Vector3, impact: Vector3 = Vector3.ZERO) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("ragdolls")
	model = source.duplicate() as Node3D
	model.name = "CorpseVisual"
	add_child(model)
	model.global_transform = source.global_transform
	model.show()
	for geometry: Node in model.find_children("*", "GeometryInstance3D", true, false):
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var upper: Node3D = model.get_node("Upper")
	var pelvis: RigidBody3D = _box_body("Pelvis", model.to_global(Vector3(0, 0.84, 0)), model.global_basis, Vector3(0.36, 0.23, 0.26), 9)
	var torso: RigidBody3D = _box_body("Torso", upper.to_global(Vector3(0, 0.28, 0)), upper.global_basis, Vector3(0.47, 0.5, 0.3), 18)
	_bind(upper, torso)
	_cone(pelvis, torso, model.to_global(Vector3(0, 0.95, 0)), 0.35, 0.25)
	var helmet: Node3D = upper.get_node("Helmet")
	var head: RigidBody3D = _box_body("Head", helmet.global_position, helmet.global_basis, Vector3(0.31, 0.4, 0.3), 4)
	_bind(helmet, head)
	_cone(torso, head, upper.to_global(Vector3(0, 0.62, 0)), 0.5, 0.35)
	for side: String in ["Left", "Right"]:
		var leg: Node3D = model.get_node(side + "Leg")
		var knee: Node3D = leg.get_node("Knee")
		var hip_position: Vector3 = leg.global_position
		var knee_position: Vector3 = knee.global_position
		var ankle_position: Vector3 = knee.to_global(Vector3(0, -0.35, 0))
		var thigh: RigidBody3D = _limb_body(side + "Thigh", hip_position, knee_position, 0.09, 6)
		var shin: RigidBody3D = _limb_body(side + "Shin", knee_position, ankle_position, 0.09, 4)
		_bind(leg, thigh)
		_bind(knee, shin)
		_cone(pelvis, thigh, hip_position, 0.7, 0.35)
		_hinge(thigh, shin, knee_position, model.global_basis.x, -0.1, 1.6)
		var arm: Node3D = upper.get_node(side + "Arm")
		var shoulder_position: Vector3 = arm.global_position
		var elbow_position: Vector3 = arm.get_node("Elbow").global_position
		var wrist_position: Vector3 = arm.get_node("Hand").global_position
		var upper_arm: RigidBody3D = _limb_body(side + "UpperArm", shoulder_position, elbow_position, 0.075, 3)
		var forearm: RigidBody3D = _limb_body(side + "Forearm", elbow_position, wrist_position, 0.065, 2)
		for part: String in ["Sleeve", "Pauldron", "Elbow"]:
			_bind(arm.get_node(part), upper_arm)
		for part: String in ["Bracer", "Palm", "Hand"]:
			_bind(arm.get_node(part), forearm)
		if arm.has_node("BodyBow"):
			_bind(arm.get_node("BodyBow"), forearm)
		_cone(torso, upper_arm, shoulder_position, 1.0, 0.6)
		var bend_axis: Vector3 = (shoulder_position - elbow_position).cross(wrist_position - elbow_position).normalized()
		if bend_axis.length_squared() < 0.01:
			bend_axis = model.global_basis.x
		_hinge(upper_arm, forearm, elbow_position, bend_axis, -0.65, 0.85)
	# Disable intra-ragdoll collisions; joints constrain anatomy without initial
	# armor overlap generating explosive impulses. Terrain and other corpses collide.
	var fall := Vector3(impact.x, 0, impact.z).normalized()
	if fall.is_zero_approx():
		fall = source.global_basis.z
	for body: RigidBody3D in bodies.values():
		for other: RigidBody3D in bodies.values():
			if body != other:
				body.add_collision_exception_with(other)
		body.linear_velocity = inherited_velocity + fall * 0.15
	torso.apply_central_impulse(fall * 5)
	torso.apply_torque_impulse(Vector3.UP.cross(fall) * 1.25 + fall * 0.12)
	source.hide()

func _body(id: String, transform: Transform3D, shape: Shape3D, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = id
	body.mass = mass
	body.collision_layer = 4
	body.collision_mask = 13 # terrain + corpses + thrown items; never enemy layer 2
	# Explicit exceptions also protect actor/corpse lifecycle transitions.
	for actor: Node in get_tree().get_nodes_in_group("combat_actors"):
		body.add_collision_exception_with(actor)
	body.contact_monitor = true
	body.max_contacts_reported = 4
	body.linear_damp = 0.8
	body.angular_damp = 1.7
	body.continuous_cd = true
	body.can_sleep = true
	var contact := PhysicsMaterial.new()
	contact.friction = 0.85
	contact.bounce = 0
	body.physics_material_override = contact
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.global_transform = transform
	bodies[id] = body
	return body

func _box_body(id: String, position: Vector3, basis: Basis, size: Vector3, mass: float) -> RigidBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _body(id, Transform3D(basis.orthonormalized(), position), shape, mass)

func _limb_body(id: String, from: Vector3, to: Vector3, radius: float, mass: float) -> RigidBody3D:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(radius * 2.1, from.distance_to(to))
	var basis := Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	return _body(id, Transform3D(basis, (from + to) * 0.5), shape, mass)

func _bind(visual: Node3D, body: RigidBody3D) -> void:
	bindings.append({"visual": visual, "body": body, "offset": body.global_transform.affine_inverse() * visual.global_transform})

func _cone(a: RigidBody3D, b: RigidBody3D, pivot: Vector3, swing: float, twist: float) -> void:
	var joint := ConeTwistJoint3D.new()
	add_child(joint)
	joint.global_position = pivot
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, swing)
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, twist)

func _hinge(a: RigidBody3D, b: RigidBody3D, pivot: Vector3, axis: Vector3, lower: float, upper: float) -> void:
	var joint := HingeJoint3D.new()
	add_child(joint)
	joint.global_transform = Transform3D(Basis(Quaternion(Vector3.BACK, axis.normalized())), pivot)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, lower)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, upper)

func focus_position() -> Vector3:
	return bodies["Torso"].global_position

func _sync_visuals() -> void:
	for binding: Dictionary in bindings:
		binding.visual.global_transform = binding.body.global_transform * binding.offset

# Pausable node, unscaled elapsed time: slow motion never extends corpse lifetime.
# A currently watched player corpse is pinned until the player respawns/exits.
func _process(delta: float) -> void:
	age_real += delta / maxf(Engine.time_scale, 0.001)
	if age_real >= CORPSE_LIFETIME and not keep_for_death_view:
		dispose()

func _physics_process(delta: float) -> void:
	if bodies.is_empty():
		return
	elapsed += delta
	# Sleeping corpses still exist for the full lifetime and remain wakeable.
	# Avoid rewriting eleven rig transforms every tick once all native bodies sleep.
	var all_asleep: bool = settled
	if settled:
		for body: RigidBody3D in bodies.values():
			all_asleep = all_asleep and body.sleeping
	if all_asleep:
		return
	_sync_visuals()
	var quiet: bool = true
	var supported: bool = false
	for body: RigidBody3D in bodies.values():
		quiet = quiet and body.linear_velocity.length_squared() < 0.04 and body.angular_velocity.length_squared() < 0.25
		supported = supported or body.get_contact_count() > 0
	quiet_time = quiet_time + delta if quiet and supported else 0.0
	# Do not freeze or stop visual syncing: native sleep is stable and external
	# rigid-body collisions/impulses can wake the corpse again, including on slopes.
	var was_settled: bool = settled
	settled = quiet_time > 0.8
	if settled and not was_settled:
		freeze_corpse()

func freeze_corpse() -> void:
	# Compatibility helper: sleep only a supported, genuinely settled corpse.
	if not settled:
		return
	for body: RigidBody3D in bodies.values():
		body.sleeping = true

func dispose() -> void:
	for body: RigidBody3D in bodies.values():
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze = true
	get_parent().remove_child(self)
	queue_free()
