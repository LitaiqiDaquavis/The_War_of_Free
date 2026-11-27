extends Node3D

const Visuals = preload("res://scripts/visuals.gd")
var velocity: Vector3
var exclusions: Array[RID] = []
var lifetime: float = 0.0
var shooter: Node
var projectile_kind: String = "arrow"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("projectiles")
	add_to_group("throwing_knives" if projectile_kind == "throwing_knife" else "arrows")
	add_child(Visuals.weapon(projectile_kind))

func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime > 8:
		queue_free()
		return
	velocity.y -= 9.8 * delta
	var next_position: Vector3 = global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position, 7, exclusions)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		if hit.collider is RigidBody3D:
			hit.collider.apply_impulse(velocity.normalized() * 3.0, hit.position - hit.collider.global_position)
		if hit.collider.has_method("take_hit"):
			var applied: bool = true
			if hit.collider.has_method("take_projectile_hit"):
				applied = hit.collider.take_projectile_hit(hit.position, velocity.normalized(), projectile_kind)
			else:
				hit.collider.take_hit(hit.position, velocity.normalized())
			if applied and is_instance_valid(shooter) and shooter.has_signal("hit_confirmed"):
				shooter.last_hit_critical = false
				shooter.hit_confirmed.emit()
		queue_free()
		return
	global_position = next_position
	look_at(global_position + velocity.normalized())
