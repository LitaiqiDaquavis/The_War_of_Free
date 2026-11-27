extends RigidBody3D

const Visuals = preload("res://scripts/visuals.gd")
const Combat = preload("res://scripts/combat.gd")
var kind: String = "longsword"
var shooter: PhysicsBody3D
var armed: bool = true
var elapsed: float = 0
var quiet_time: float = 0
var previous_position: Vector3
var impact_direction: Vector3 = Vector3.FORWARD
var claimed: bool = false

func is_pickup_available() -> bool:
	return not claimed and kind in ["dagger", "longsword", "spear", "mace", "shield"]

func claim() -> bool:
	if not is_pickup_available():
		return false
	claimed = true
	armed = false
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	remove_from_group("thrown_items")
	hide()
	return true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("thrown_items")
	collision_layer = 8
	collision_mask = 7
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	mass = 2 if kind == "shield" else (1.8 if kind == "mace" else 1)
	angular_damp = 0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.02
	var material := PhysicsMaterial.new()
	material.friction = 0.8
	material.bounce = 0.12
	physics_material_override = material
	add_child(Visuals.weapon(kind))
	var collision := CollisionShape3D.new()
	if kind == "shield":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.41
		cylinder.height = 0.16
		collision.shape = cylinder
		collision.rotation.x = PI / 2
	else:
		var shape := BoxShape3D.new()
		var length: float = 2.95 if kind == "spear" else (0.76 if kind == "dagger" else 1.35)
		shape.size = Vector3(0.13 if kind != "mace" else 0.35, 0.13 if kind != "mace" else 0.35, length)
		collision.shape = shape
		collision.position.z = -0.825 if kind == "spear" else -0.4
	add_child(collision)
	if is_instance_valid(shooter):
		add_collision_exception_with(shooter)
	body_entered.connect(_on_contact)
	previous_position = global_position

func launch(origin: Vector3, direction: Vector3) -> void:
	global_position = origin
	impact_direction = direction
	look_at(origin + direction)
	if kind == "shield":
		rotation.x = PI / 2
		angular_velocity = Vector3.UP * 18
		linear_velocity = direction * 17 + Vector3.UP * 1.2
	elif kind == "spear":
		angular_velocity = direction * 9
		linear_velocity = direction * 24 + Vector3.UP
	else:
		angular_velocity = global_basis.x * 18
		linear_velocity = direction * 20 + Vector3.UP * 1.5
	previous_position = global_position

func _on_contact(body: Node) -> void:
	if claimed or not armed or body == shooter:
		return
	armed = false
	angular_damp = 2
	linear_damp = 0.6
	if body.has_method("take_melee_hit"):
		# Contact signals arrive during physics query flushing. Death can create
		# a ragdoll, so apply damage after this contact callback has finished.
		_apply_impact.call_deferred(body, impact_direction)

func _apply_impact(body: Node, direction: Vector3) -> void:
	if claimed or not is_inside_tree() or not is_instance_valid(body) or not body.is_inside_tree():
		return
	var point: Vector3 = body.get_combat_aim_point()
	var applied: bool = body.take_melee_hit(point, direction, Combat.MELEE, false)
	if applied and is_instance_valid(shooter) and shooter.has_signal("hit_confirmed"):
		shooter.last_hit_critical = false
		shooter.hit_confirmed.emit()

func _physics_process(delta: float) -> void:
	if freeze or claimed:
		return
	elapsed += delta
	if linear_velocity.length_squared() > 0.01:
		impact_direction = linear_velocity.normalized()
	if armed and previous_position.distance_squared_to(global_position) > 0.0001:
		var exclusions: Array[RID] = [get_rid()]
		if is_instance_valid(shooter):
			exclusions.append(shooter.get_rid())
		var query := PhysicsRayQueryParameters3D.create(previous_position, global_position, 7, exclusions)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_on_contact(hit.collider)
	previous_position = global_position
	quiet_time = quiet_time + delta if linear_velocity.length() < 0.15 and angular_velocity.length() < 0.3 else 0
	if quiet_time > 0.8 or elapsed > 12 or global_position.y < -20:
		armed = false
		freeze = true
		set_physics_process(false)
