extends Node3D

const ReplayPose = preload("res://scripts/replay_pose.gd")
const Visuals = preload("res://scripts/visuals.gd")
const MELEE_LENGTH: float = 2.2
const BEFORE_SHOT: float = 0.65
const MOVE_TO_ARCHER: float = 0.60
const BOW_CLOSEUP: float = 0.38
const HIT_HOLD: float = 0.24

var camera: Camera3D
var player: Node
var attacker_model: Node3D
var attacker_ref: Node
var attacker_was_visible: bool
var corpse_model: Node3D
var victim: Node3D
var archer: Node3D
var replay_arrow: Node3D
var record: Dictionary
var kind: String
var duration: float = 0
var elapsed: float = 0
var flight_length: float = 0
var before_length: float = 0
var frames := PackedInt64Array()
var points := PackedVector3Array()
var history: Array[Dictionary] = []

func begin(subject: Node, attacker: Node, data: Dictionary) -> float:
	player = subject
	record = data
	kind = record.get("kind", "")
	if kind != "melee" and kind != "arrow":
		return 0.0
	camera = Camera3D.new()
	add_child(camera)
	camera.far = player.camera.far
	camera.fov = 58
	if kind == "melee":
		duration = MELEE_LENGTH
	else:
		_setup_arrow(attacker)
	camera.make_current()
	advance(0.0)
	return duration

func _setup_arrow(attacker: Node) -> void:
	var trace: Dictionary = record.trace
	frames = trace.frames
	points = trace.points
	flight_length = clampf(float(trace.flight) * 2.7, 0.65, 2.5)
	history.assign(record.history)
	if not history.is_empty() and int(history.front().frame) < frames[0]:
		before_length = BEFORE_SHOT
	duration = before_length + MOVE_TO_ARCHER + BOW_CLOSEUP + flight_length + HIT_HOLD
	history.append(record.victim)
	victim = ReplayPose.new()
	add_child(victim)
	victim.build(history.front())
	archer = ReplayPose.new()
	add_child(archer)
	archer.build(trace.shooter)
	replay_arrow = Visuals.weapon("arrow")
	add_child(replay_arrow)
	replay_arrow.hide()
	if is_instance_valid(player.ragdoll):
		corpse_model = player.ragdoll.model
		corpse_model.hide()
	if is_instance_valid(attacker):
		attacker_ref = attacker
		attacker_model = attacker.get("model")
		if is_instance_valid(attacker_model):
			attacker_was_visible = attacker_model.visible
			attacker_model.hide()

func advance(delta: float) -> void:
	elapsed = minf(duration, elapsed + delta)
	if kind == "melee":
		_show_melee()
	else:
		_show_arrow()

func _show_melee() -> void:
	var attacker_pose: Transform3D = record.attacker
	var fall: Vector3 = player.ragdoll.focus_position()
	var strike: Vector3 = fall - attacker_pose.origin
	strike.y = 0
	if strike.length_squared() < 0.12:
		strike = -attacker_pose.basis.z
	strike = strike.normalized()
	var right: Vector3 = strike.cross(Vector3.UP)
	var pull: float = smoothstep(0, MELEE_LENGTH, elapsed)
	var from: Vector3 = attacker_pose.origin - strike * lerpf(1.15, 1.48, pull) + right * 1.12 + Vector3.UP * 1.14
	_set_camera(from, fall + right * 0.26 + Vector3.UP * 0.05, 63)

func _show_arrow() -> void:
	var shooter_pose: Transform3D = record.trace.shooter.body
	var launch: Vector3 = points[0]
	var path_direction: Vector3 = (points[1] - launch).normalized()
	var right: Vector3 = path_direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = shooter_pose.basis.x
	var archer_focus: Vector3 = shooter_pose.origin + Vector3.UP * 1.31
	var archer_camera: Vector3 = archer_focus - path_direction * 1.45 + right * 1.85 + Vector3.UP * 0.30
	var close_camera: Vector3 = launch - path_direction * 0.82 + right * 0.63 + Vector3.UP * 0.24
	var bow_focus: Vector3 = archer.left_prop.get_node("NockedArrow").global_position if archer.left_kind == "bow" else launch
	var move_end: float = before_length + MOVE_TO_ARCHER
	var bow_end: float = move_end + BOW_CLOSEUP
	if elapsed < before_length:
		var pre_frame: float = lerpf(float(frames[0]) - 26.0, float(frames[0]), elapsed / before_length)
		_apply_player_frame(pre_frame)
		var overview: Array[Vector3] = _victim_camera()
		_set_camera(overview[0], overview[1], 54)
	elif elapsed < move_end:
		_apply_player_frame(frames[0])
		var overview: Array[Vector3] = _victim_camera()
		var t: float = smoothstep(before_length, move_end, elapsed)
		_set_camera(overview[0].lerp(archer_camera, t), overview[1].lerp(archer_focus, t), 54)
	elif elapsed < bow_end:
		var t: float = smoothstep(move_end, bow_end, elapsed)
		_set_camera(archer_camera.lerp(close_camera, t), archer_focus.lerp(bow_focus, t), lerpf(54, 43, t))
	else:
		var progress: float = clampf((elapsed - bow_end) / flight_length, 0, 1)
		var sample: float = progress * (points.size() - 1)
		var index: int = mini(int(sample), points.size() - 2)
		var weight: float = sample - index
		var point: Vector3 = points[index].lerp(points[index + 1], weight)
		var forward: Vector3 = (points[index + 1] - points[index]).normalized()
		if forward.is_zero_approx():
			forward = path_direction
		var victim_frame: float = lerpf(float(frames[index]), float(frames[index + 1]), weight)
		_apply_player_frame(victim_frame)
		archer.show_bow(1 - smoothstep(0, 0.18, elapsed - bow_end), false)
		replay_arrow.show()
		# The collision point matches the arrowhead at impact.
		replay_arrow.global_position = point - forward * 0.61
		replay_arrow.look_at(replay_arrow.global_position + forward)
		var tracking: Vector3 = point - forward * 1.25 + right * 0.55 + Vector3.UP * 0.30
		var snap: float = smoothstep(0, 0.14, elapsed - bow_end)
		_set_camera(close_camera.lerp(tracking, snap), bow_focus.lerp(point + forward * 0.20, snap), lerpf(43, 55, snap))

func _victim_camera() -> Array[Vector3]:
	var pose: Transform3D = victim.model.global_transform
	var focus: Vector3 = pose.origin + Vector3.UP * 0.95
	var from: Vector3 = focus + pose.basis.x * 2.05 + pose.basis.z * 1.95 + Vector3.UP * 0.67
	return [from, focus]

func _apply_player_frame(frame: float) -> void:
	var earlier: Dictionary = history.front()
	for index: int in range(1, history.size()):
		var next: Dictionary = history[index]
		if float(next.frame) >= frame:
			var weight: float = clampf((frame - float(earlier.frame)) / maxf(1, float(next.frame - earlier.frame)), 0, 1)
			victim.apply(earlier, next, weight)
			return
		earlier = next
	victim.apply(earlier, earlier, 0)

func _set_camera(from: Vector3, focus: Vector3, fov: float) -> void:
	var ray := PhysicsRayQueryParameters3D.create(focus, from, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	camera.global_position = hit.position + hit.normal * 0.14 if not hit.is_empty() else from
	if camera.global_position.distance_squared_to(focus) > 0.0001:
		camera.look_at(focus)
	camera.fov = fov

func close() -> void:
	if is_instance_valid(corpse_model):
		corpse_model.show()
	if is_instance_valid(attacker_model) and is_instance_valid(attacker_ref) and not attacker_ref.get("defeated"):
		attacker_model.visible = attacker_was_visible
	if is_instance_valid(player) and is_instance_valid(player.camera):
		player._update_camera()
		player.camera.make_current()
	hide()
