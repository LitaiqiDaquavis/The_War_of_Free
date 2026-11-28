extends SceneTree

const Timing = preload("res://scripts/attack_timing.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame

func mouse(player: Node, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	player._unhandled_input(event)

func reset(world: Node, kind: String = "longsword") -> void:
	world.game_started = false
	world.start_game()
	world.player.equip(kind, "shield")
	world.player.position = Vector3(0, 0, 1.4)
	world.player.set_physics_process(true)
	world.get_node("TrainingEnemy").invulnerable = false
	await frames(5)
	world.player.set_physics_process(false)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "res://tests/hit-window-settings.cfg"
	world.training_mode = true
	world.battle_mode = false
	root.add_child(world)
	var player: Node = world.player
	var enemy: Node = world.get_node("TrainingEnemy")
	for kind: String in player.WEAPONS:
		await reset(world, kind)
		var times: Vector3 = Timing.durations(kind)
		check(not player._resolve_melee() and enemy.health == 100, "Idle melee resolution must never deal damage: " + kind)
		mouse(player, true)
		check(enemy.health == 100, "Mouse-down must not immediately damage an in-range enemy: " + kind)
		player._tick_melee(times.x + 0.05)
		check(enemy.health == 100 and player.melee_held, "Sub-critical holding must not cause damage: " + kind)
		mouse(player, false)
		check(player.attack_elapsed == 0 and not player.attack_heavy, "A light release must start its full wind-up without crediting held time: " + kind)
		check(not player._resolve_melee() and enemy.health == 100, "Damage entry must reject a new attack's wind-up: " + kind)
		player._tick_melee(times.x - 0.001)
		check(enemy.health == 100 and not player._resolve_melee(), "The entire specified wind-up must be harmless: " + kind)
		player._tick_melee(0.001)
		check(enemy.health == 60 and enemy.hit_count == 1, "Active contact must deal one normal hit: " + kind)
		check(not player._resolve_melee() and enemy.health == 60, "Repeated resolution in one attack must not deal another hit: " + kind)
		player._tick_melee(times.y)
		check(not player._resolve_melee() and enemy.health == 60, "Cooldown must reject damage even in range: " + kind)
		player._tick_melee(times.z)
		check(not player._resolve_melee() and enemy.health == 60, "Completed attacks must not resolve again: " + kind)
	await reset(world)
	enemy.position.z = -5
	await frames(2)
	mouse(player, true)
	mouse(player, false)
	player._tick_melee(0.4)
	check(enemy.health == 100 and player.attack_pending, "An active miss must not count as a hit.")
	enemy.position.z = 0
	await frames(2)
	player._tick_melee(0.1)
	check(enemy.health == 60 and enemy.hit_count == 1, "A target entering reach within the active interval must be hittable.")
	await reset(world)
	enemy.position.z = -5
	await frames(2)
	player.attack()
	player._tick_melee(0.84)
	enemy.position.z = 0
	await frames(2)
	player._tick_melee(0.05)
	check(enemy.health == 100 and not player._resolve_melee(), "Entering reach only in cooldown must remain a miss.")
	for action: String in ["kick", "shield"]:
		await reset(world)
		if action == "shield":
			player.select_slot(2)
			player.shield_requested = true
			player._physics_process(0.16)
			player.shield_attack()
		else:
			player.kick()
		var wind_contact: bool = player._resolve_shield() if action == "shield" else player._resolve_kick()
		check(not wind_contact and enemy.health == 100, "Special damage entry must reject preparation: " + action)
		var times: Vector3 = Timing.durations(action)
		player._physics_process(times.x)
		check(enemy.health == 80 and enemy.hit_count == 1, "Special contact must resolve once inside its active window: " + action)
		var duplicate: bool = player._resolve_shield() if action == "shield" else player._resolve_kick()
		check(not duplicate and enemy.health == 80, "Special damage entry must reject duplicate contacts: " + action)
		player._physics_process(times.y)
		player.special_pending = true
		var recovery_contact: bool = player._resolve_shield() if action == "shield" else player._resolve_kick()
		check(not recovery_contact and enemy.health == 80, "Special cooldown must reject stale contact requests: " + action)
	await reset(world)
	enemy.rotation.y = PI
	enemy.attack_elapsed = 0.1
	enemy.attack_pending = true
	check(not enemy._strike_target() and player.health == 100, "Bot damage entry must reject wind-up.")
	enemy.attack_elapsed = 0.36
	check(enemy._strike_target() and player.health == 60, "Bot contact must resolve during the active window.")
	check(not enemy._strike_target() and player.health == 60, "Bot attack must consume its contact before signals can repeat it.")
	enemy.attack_elapsed = 0.9
	enemy.attack_pending = true
	check(not enemy._strike_target() and player.health == 60, "Bot cooldown must reject stale contact requests.")
	world.queue_free()
	paused = false
	await process_frame
	print("HIT_WINDOW_SMOKE: ", "PASS" if failures.is_empty() else "FAIL")
	print("ASSERTION_TOTAL: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
