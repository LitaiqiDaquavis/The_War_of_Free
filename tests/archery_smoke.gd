extends SceneTree

const Timing = preload("res://scripts/attack_timing.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func left_click(player: Node, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	player._unhandled_input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "res://tests/archery-smoke-settings.cfg"
	world.training_mode = true
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	var enemy: Node = world.get_node("TrainingEnemy")
	player.position = Vector3(0, 0, 2.7)
	for index in range(5):
		await physics_frame
	player.set_physics_process(false)
	player.look_pitch = 0
	player._update_camera()
	player.equip("spear", "bow")
	player.select_slot(2)
	check(not player.bow_ready(), "A newly selected bow must prepare its first arrow.")
	player._tick_bow(0.849)
	left_click(player, true)
	left_click(player, false)
	check(get_nodes_in_group("arrows").is_empty(), "A click before full draw must not fire.")
	player._tick_bow(0.001)
	check(player.bow_ready() and get_nodes_in_group("arrows").is_empty(), "The bow must be ready at 0.85s without queuing early clicks.")
	player._animate_locomotion(0.1)
	player._update_weapon_pose()
	var upper: Node3D = player.body_model.get_node("Upper")
	var left: Node3D = upper.get_node("LeftArm")
	var right: Node3D = upper.get_node("RightArm")
	var left_upper: Vector3 = left.get_node("Elbow").position
	var left_lower: Vector3 = left.get_node("Hand").position - left_upper
	check(left_upper.normalized().dot(left_lower.normalized()) > 0.99, "The bow arm must be straight at full draw.")
	var temple: Vector3 = upper.get_node("Helmet").global_position + Vector3(0.15, -0.08, 0)
	check(right.get_node("Palm").global_position.distance_to(temple) < 0.11, "The string hand must anchor near the temple.")
	check(player.body_model.get_node("LeftLeg").rotation.x > 0 and player.body_model.get_node("RightLeg").rotation.x < 0, "The left foot must lead in the standing archery stance.")
	left_click(player, true)
	check(get_nodes_in_group("arrows").size() == 1 and not player.bow_ready(), "A ready bow must fire on press and immediately start the next preparation.")
	player._tick_bow(1.15)
	check(player.bow_ready() and get_nodes_in_group("arrows").size() == 1, "A held mouse button must not repeat shots.")
	left_click(player, false)
	left_click(player, true)
	check(get_nodes_in_group("arrows").size() == 2, "The second click must fire as soon as the 1.15s reload ends.")
	left_click(player, false)
	player._tick_bow(1.15)

	Input.action_press("move_forward")
	Input.action_press("sprint")
	for index in range(12):
		player._physics_process(1.0 / 60.0)
	check(player.sprinting and not player.bow_ready(), "Forward sprint must put the bow into two-handed carry.")
	left_click(player, true)
	left_click(player, false)
	check(get_nodes_in_group("arrows").size() == 2, "Sprinting with a carried bow must not fire.")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	player._physics_process(0.425)
	check(not player.sprinting and not player.bow_ready(), "Leaving sprint must start a fresh draw.")
	player._physics_process(0.425)
	check(player.bow_ready(), "The bow must be ready 0.85s after leaving sprint.")

	player.select_slot(1)
	player.position = Vector3(0, 0, 2.7)
	enemy.invulnerable = false
	await physics_frame
	player.sprinting = true
	player.spear_carry = 1.0
	left_click(player, true)
	left_click(player, false)
	var windup: float = Timing.durations("spear").x
	player._tick_melee(0.299)
	check(player.attack_elapsed == 0 and enemy.health == 100, "A sprint spear tap must finish the carry transition before its wind-up clock starts.")
	player._tick_melee(0.001)
	player._tick_melee(windup - 0.001)
	check(enemy.health == 100, "Spear transition must be added to the full light wind-up.")
	player._tick_melee(0.001)
	check(enemy.health == 60, "Spear light attack must hit at the end of transition plus wind-up.")
	player._tick_melee(1.0)
	enemy.health = 100
	player.spear_carry = 1.0
	left_click(player, true)
	var heavy_windup: float = Timing.durations("spear", true).x
	player._tick_melee(0.30 + heavy_windup - 0.001)
	check(player.melee_held and enemy.health == 100, "A held sprint spear attack must finish transition and heavy wind-up.")
	player._tick_melee(0.001)
	check(player.attack_heavy and enemy.health == 20, "The heavy spear must auto-release when both timers finish.")
	left_click(player, false)

	if failures.is_empty():
		print("ARCHERY_SMOKE: PASS")
	quit(0 if failures.is_empty() else 1)
