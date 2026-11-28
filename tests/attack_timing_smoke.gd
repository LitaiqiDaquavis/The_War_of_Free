extends SceneTree

const Timing = preload("res://scripts/attack_timing.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func mouse(player: Node, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	player._unhandled_input(event)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame

func reset(world: Node, kind: String = "longsword") -> void:
	world.game_started = false
	world.start_game()
	world.player.position = Vector3(0, 0, 1.4)
	world.player.equip(kind, "shield")
	world.player.set_physics_process(true)
	var enemy: Node = world.get_node("TrainingEnemy")
	enemy.invulnerable = false
	enemy.set_physics_process(false)
	await frames(5)
	world.player.set_physics_process(false)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "res://tests/timing-settings.cfg"
	world.training_mode = true
	world.battle_mode = false
	root.add_child(world)
	var player: Node = world.player
	var enemy: Node = world.get_node("TrainingEnemy")
	var rows: Array = [
		["longsword", false, Vector3(0.36, 0.47, 0.17)], ["longsword", true, Vector3(0.65, 0.25, 0.5)],
		["kick", false, Vector3(0.15, 0.3, 0.35)],
		["spear", false, Vector3(0.25, 0.3, 0.3)], ["spear", true, Vector3(0.6, 0.2, 0.6)],
		["dagger", false, Vector3(0.3, 0.35, 0.55)], ["dagger", true, Vector3(0.6, 0.7, 0.3)],
		["mace", false, Vector3(0.32, 0.65, 0.55)], ["mace", true, Vector3(0.55, 0.28, 0.2)],
		["fists", false, Vector3(0.2, 0.3, 0.3)], ["fists", true, Vector3(0.55, 0.4, 0.4)],
		["shield", false, Vector3(0.3, 0.15, 0.75)]
	]
	for row: Array in rows:
		var kind: String = row[0]
		var heavy: bool = row[1]
		var times: Vector3 = row[2]
		check(Timing.durations(kind, heavy).is_equal_approx(times), "Table mismatch: " + kind + str(heavy))
		if kind in player.WEAPONS and not heavy:
			check(is_equal_approx(player.WEAPONS[kind].duration, Timing.total(kind)), "Armory duration must match the actual attack timing.")
		await reset(world, kind if kind not in ["kick", "shield"] else "longsword")
		if kind in ["kick", "shield"]:
			if kind == "shield":
				player.select_slot(2)
				mouse(player, MOUSE_BUTTON_RIGHT, true)
				player._physics_process(0.16)
				mouse(player, MOUSE_BUTTON_LEFT, true)
				mouse(player, MOUSE_BUTTON_LEFT, false)
				check(player.special_action == "shield", "Guarding LMB must select a shield attack.")
				player.take_melee_hit(player.get_combat_aim_point(), Vector3.BACK, 40, false)
				check(player.health == 100, "Shield wind-up must retain frontal blocking.")
			else:
				player.kick()
			player._physics_process(times.x - 0.001)
			check(enemy.health == 100, "Special attack must not hit during wind-up: " + kind)
			player._physics_process(0.001)
			check(enemy.health == 80, "Special attack must deal exactly 20 at the active boundary: " + kind)
			if kind == "shield":
				check(not player.blocking, "Shield must stop blocking while striking.")
				player.take_melee_hit(player.get_combat_aim_point(), Vector3.BACK, 40, false)
				check(player.health == 60, "A frontal hit must damage the player during the shield strike.")
			player._physics_process(times.y)
			check(player.special_action == kind and enemy.health == 80, "Special active phase must hit only once: " + kind)
			if kind == "shield":
				check(not player.blocking, "Shield must remain vulnerable during recovery.")
				player.take_melee_hit(player.get_combat_aim_point(), Vector3.BACK, 40, false)
				check(player.health == 20, "A frontal hit must damage the player during shield recovery.")
			player._physics_process(times.z - 0.001)
			check(player.special_action == kind, "Special cooldown must not end early: " + kind)
			player.select_slot(1)
			check(player.special_action == kind, "Slot switching must not cancel a committed timed action.")
			player._physics_process(0.001)
			check(player.special_action.is_empty(), "Special attack must end at the exact total time: " + kind)
			if kind == "shield":
				check(player.blocking and player.shield_blend > 0.99, "Shield must finish recovery already raised.")
				player.take_melee_hit(player.get_combat_aim_point(), Vector3.BACK, 40, false)
				check(player.health == 20, "Frontal blocking must resume after recovery completes.")
			continue
		if heavy:
			mouse(player, MOUSE_BUTTON_LEFT, true)
			player._tick_melee(times.x - 0.001)
		else:
			player.attack()
			player._tick_melee(times.x - 0.001)
		check(enemy.health == 100, "No melee damage during wind-up: " + kind + str(heavy))
		player._tick_melee(0.001)
		check(enemy.health == (20 if heavy and kind != "fists" else 60), "Melee damage at active boundary: " + kind + str(heavy))
		check(is_equal_approx(player.attack_duration, times.x + times.y + times.z), "Melee total duration must use all three table phases.")
		mouse(player, MOUSE_BUTTON_LEFT, false)
		player._tick_melee(times.y)
		check(Timing.stage(kind, player.attack_elapsed, heavy) == "cooldown", "Melee must enter recovery at the active boundary.")
		player.attack()
		player.select_slot(2)
		check(player.active_slot == 1 and player.attack_duration > 0, "Cooldown must reject attacks and slot-cancel exploits.")
		player._tick_melee(times.z - 0.001)
		check(player.attack_duration > 0, "Melee cooldown must not finish early.")
		player._tick_melee(0.001)
		check(player.attack_duration == 0 and enemy.hit_count == 1, "Melee must finish on time with exactly one contact.")
		player._tick_melee(1)
		check(enemy.hit_count == 1, "Holding/releasing after an automatic heavy must not repeat it.")
	await reset(world)
	player.attack()
	player._tick_melee(0.4)
	mouse(player, MOUSE_BUTTON_LEFT, true)
	mouse(player, MOUSE_BUTTON_LEFT, false)
	player._tick_melee(0.599)
	check(player.swing_direction == 1 and player.attack_chained == false, "Buffered combos must wait for all of the current cooldown.")
	player._tick_melee(0.001)
	check(player.swing_direction == -1 and is_equal_approx(player.attack_duration, 1.0), "Chained longsword attacks must alternate without shortening the table duration.")
	check(player.attack_start_pose.position.x < 0, "A queued swing must continue from the prior follow-through.")
	await reset(world)
	enemy.position.z = -5
	await frames(2)
	player.attack()
	player._tick_melee(0.4)
	check(enemy.hit_count == 0 and player.attack_pending, "An active miss must leave the contact window available.")
	enemy.position.z = 0
	await frames(2)
	player._tick_melee(0.1)
	check(enemy.hit_count == 1, "Entering reach during the active window must allow a hit.")
	await reset(world)
	player.select_slot(2)
	mouse(player, MOUSE_BUTTON_RIGHT, true)
	player._physics_process(0.16)
	mouse(player, MOUSE_BUTTON_LEFT, true)
	player._physics_process(0.4)
	var before_pause: float = player.special_elapsed
	world.show_pause_menu()
	world.start_game()
	check(player.special_action == "shield" and player.special_elapsed == before_pause, "Pause/resume must freeze committed shield recovery rather than erase it.")
	await reset(world)
	enemy.ai_enabled = true
	enemy.attack_elapsed = 0
	enemy.attack_pending = true
	enemy.attack_cooldown = 0
	enemy._physics_process(0.359)
	check(player.health == 100, "Bot longsword wind-up must last 0.36 seconds.")
	enemy._physics_process(0.001)
	check(player.health == 60, "Bot active window must use the same start time.")
	enemy._physics_process(0.47)
	check(player.health == 60 and enemy.attack_elapsed >= 0, "Bot must hit once and complete its 0.47-second active window.")
	enemy._physics_process(0.17)
	check(enemy.attack_elapsed < 0 and enemy.attack_cooldown == 0, "Bot recovery must last 0.17 seconds without an extra random delay.")
	enemy.attack_elapsed = 0.36
	player.die()
	enemy._physics_process(0.64)
	check(enemy.attack_elapsed < 0, "An enemy must finish its strike/recovery even when its target dies.")
	world.queue_free()
	paused = false
	await process_frame
	print("ATTACK_TIMING_SMOKE: ", "PASS" if failures.is_empty() else "FAIL")
	print("ASSERTION_TOTAL: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
