extends SceneTree

const Soldier = preload("res://scripts/soldier.gd")
const Timing = preload("res://scripts/attack_timing.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func sync_collision() -> void:
	await physics_frame
	await physics_frame

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.training_mode = true
	world.settings_path = "user://death-replay-smoke.cfg"
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	var dummy: Node = world.get_node("TrainingEnemy")
	dummy.position = Vector3(20, 0.1, 0)
	var archer := Soldier.new()
	archer.role = "archer"
	archer.ai_enabled = false
	archer.position = Vector3(0, 0.1, 0)
	world.add_child(archer)
	archer.set_physics_process(false)
	archer.model.rotation = Vector3.ZERO
	archer.rng.seed = 84
	player.position = Vector3(-1, 0.1, -8)
	for index: int in range(12):
		await physics_frame
		player.position.x += 1.0 / 12.0
	await sync_collision()
	player.set_physics_process(false)
	player.health = 20
	archer.target = player
	archer.bow_elapsed = 1.7
	archer._animate_fighter(0.2)
	check(archer._fire_arrow(), "Actual archer fires a recorded arrow.")
	var arrows: Array[Node] = get_nodes_in_group("arrows")
	check(arrows.size() == 1 and not arrows[0].shot_pose.is_empty(), "Arrow begins its trace at launch.")
	for index: int in range(30):
		if not player.is_alive:
			break
		await physics_frame
	check(not player.is_alive and is_instance_valid(world.death_replay), "A lethal actual arrow starts the archer replay.")
	if not is_instance_valid(world.death_replay):
		quit(1)
		return
	var replay: Node3D = world.death_replay
	check(replay.kind == "arrow" and replay.points.size() > 3 and replay.history.front().body.origin.x < -0.4, "Replay keeps the actual flight and player movement before the launch.")
	check(root.get_camera_3d() == replay.camera and not player.ragdoll.model.visible and not archer.model.visible, "Replay uses its own camera and visual replicas.")
	replay.advance(maxf(0, replay.BEFORE_SHOT + replay.MOVE_TO_ARCHER + 0.18 - replay.elapsed))
	check(not replay.replay_arrow.visible, "The close-up precedes the arrow release.")
	replay.advance(maxf(0, replay.duration - replay.HIT_HOLD - replay.elapsed + 0.01))
	check(replay.replay_arrow.visible and replay.replay_arrow.to_global(Vector3(0, 0, -0.61)).distance_to(replay.points[-1]) < 0.01, "Tracked arrowhead ends on the recorded impact.")
	world.respawn_player()
	player.set_physics_process(false)
	check(not is_instance_valid(world.death_replay) and root.get_camera_3d() == player.camera and archer.model.visible and Engine.time_scale == 1.0, "Skipping restores gameplay camera, model visibility and speed.")

	archer.position = Vector3(5, 0.1, -6)
	var swordsman := Soldier.new()
	swordsman.ai_enabled = false
	swordsman.position = Vector3(0, 0.1, 2.0)
	world.add_child(swordsman)
	swordsman.set_physics_process(false)
	swordsman.model.rotation = Vector3.ZERO
	player.position = Vector3(0, 0.1, 0)
	player.health = 40
	await sync_collision()
	swordsman.target = player
	swordsman.attack_pending = true
	swordsman.attack_elapsed = Timing.durations("longsword").x
	swordsman._animate_fighter(0.0)
	swordsman._strike(2.5, false)
	check(not player.is_alive and is_instance_valid(world.death_replay) and world.death_replay.kind == "melee", "An actual melee strike opens the rear camera.")
	if is_instance_valid(world.death_replay):
		replay = world.death_replay
		var killer_pixel: Vector2 = replay.camera.unproject_position(swordsman.get_combat_aim_point())
		check(replay.camera.global_position.z > swordsman.global_position.z and killer_pixel.x < root.get_visible_rect().size.x * 0.45, "The camera stays behind the attacker and frames them on the left.")
		check(player.ragdoll.model.visible, "The melee camera shows the real collapsing ragdoll.")
		world._process(world.death_real_remaining * Engine.time_scale + 0.01)
		check(world.screen == "dead" and Engine.time_scale == 1.0 and root.get_camera_3d() == player.camera, "Finishing the cinematic opens the normal corpse orbit.")
	world.end_match()
	if failures.is_empty():
		print("DEATH_REPLAY_SMOKE: PASS")
	quit(0 if failures.is_empty() else 1)
