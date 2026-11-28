extends Node3D

const Combat = preload("res://scripts/combat.gd")
var damage_source: Dictionary = {}

const Visuals = preload("res://scripts/visuals.gd")
const ReplayPose = preload("res://scripts/replay_pose.gd")
var velocity: Vector3
var exclusions: Array[RID] = []
var lifetime: float = 0.0
var shooter: Node
var projectile_kind: String = "arrow"
var shot_pose: Dictionary = {}
var replay_points := PackedVector3Array()
var replay_frames := PackedInt64Array()

func _ready() -> void:
	damage_source = Combat.damage_source(shooter, projectile_kind)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("projectiles")
	add_to_group("throwing_knives" if projectile_kind == "throwing_knife" else "arrows")
	add_child(Visuals.weapon(projectile_kind))

func record_launch() -> void:
	var viewer: Node = get_tree().get_first_node_in_group("death_replay_subject")
	if projectile_kind != "arrow" or not is_instance_valid(shooter) or not is_instance_valid(viewer):
		return
	shot_pose = ReplayPose.capture(shooter)
	_record_point(global_position)

func _record_point(point: Vector3) -> void:
	if shot_pose.is_empty():
		return
	replay_points.append(point)
	replay_frames.append(Engine.get_physics_frames())

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
			if hit.collider.has_method("take_projectile_contact"):
				var trace: Dictionary = {}
				if not shot_pose.is_empty():
					_record_point(hit.position)
					trace = {"shooter": shot_pose, "points": replay_points, "frames": replay_frames, "flight": lifetime}
				applied = hit.collider.take_projectile_contact(hit.position, velocity.normalized(), projectile_kind, shooter, trace, damage_source)
			elif hit.collider.has_method("take_projectile_hit"):
				applied = hit.collider.take_projectile_hit(hit.position, velocity.normalized(), projectile_kind, shooter, damage_source)
			else:
				hit.collider.take_hit(hit.position, velocity.normalized())
			if applied and is_instance_valid(shooter) and shooter.has_signal("hit_confirmed"):
				shooter.last_hit_critical = false
				shooter.hit_confirmed.emit()
		queue_free()
		return
	global_position = next_position
	_record_point(next_position)
	look_at(global_position + velocity.normalized())
