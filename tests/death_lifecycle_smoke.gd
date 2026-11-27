extends SceneTree

const Arrow = preload("res://scripts/arrow.gd")
const ThrownItem = preload("res://scripts/thrown_item.gd")
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

func click(world: Node, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	world._input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://death-lifecycle-test.cfg"
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	var enemy: Node = world.get_node("TrainingEnemy")
	enemy.ai_enabled = false
	enemy.set_physics_process(false)
	await frames(5)

	# Timer / generation / ownership contract: enemy returns without deleting corpse.
	var original_spawn: Transform3D = enemy.spawn_transform
	enemy.position = Vector3(4, 0, 2)
	enemy.defeat()
	var enemy_corpse: Node = enemy.ragdoll
	check(world.enemy_respawn_remaining == 2.0, "Enemy defeat schedules exactly two real seconds.")
	world._process(1.99)
	check(enemy.defeated, "Enemy cannot respawn early.")
	world._process(0.02)
	check(not enemy.defeated and enemy.health == 100, "Enemy automatically respawns at full health.")
	check(enemy.transform.is_equal_approx(original_spawn), "Enemy returns to original spawn, not death location.")
	check(is_instance_valid(enemy_corpse) and enemy_corpse.is_inside_tree() and enemy.ragdoll == null, "Old enemy corpse is detached, preserved and independently owned.")
	var real_age: float = enemy_corpse.age_real
	Engine.time_scale = 0.2
	enemy_corpse._process(0.2)
	check(is_equal_approx(enemy_corpse.age_real - real_age, 1.0), "Corpse deadline uses real time during slow motion.")
	Engine.time_scale = 1.0
	enemy_corpse.age_real = 19.99
	enemy_corpse._process(0.02)
	check(not enemy_corpse.is_inside_tree(), "Enemy corpse is removed at twenty seconds.")
	await process_frame

	# No old timer may fire after resetting/exiting a round.
	enemy.defeat()
	var old_generation: int = world.enemy_respawn_generation
	world.reset_round()
	check(world.round_generation != old_generation and world.enemy_respawn_remaining == -1, "Round reset invalidates all pending enemy respawns.")
	world.enemy_respawn_generation = old_generation
	enemy.defeated = true
	world._respawn_enemy()
	check(enemy.defeated, "A stale generation cannot respawn an enemy in a new round.")
	enemy.reset_for_match()
	check(get_nodes_in_group("ragdolls").is_empty(), "Reset removes every corpse, including detached corpses.")
	world.training_mode = true
	enemy.defeat()
	check(world.enemy_respawn_remaining == -1, "Training mode does not acquire enemy respawn logic.")
	world.training_mode = false
	world.reset_round()
	player.set_controls_active(true)

	# Death is immediately nonblocking and the captured mouse still orbits.
	player.die()
	check(not paused and not world.overlay.visible and not player.controls_active, "Death leaves physics running without an overlay or living controls.")
	check(Engine.time_scale == 0.2 and player.death_closeup, "Death starts slow-motion close-up immediately.")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Death retains captured mouse for orbit.")
	var yaw: float = player.death_yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(120, 60)
	player._unhandled_input(motion)
	check(player.death_yaw != yaw, "Mouse motion rotates the death camera despite disabled combat controls.")
	var corpse: Node = player.ragdoll
	corpse.age_real = 25
	corpse._process(0.01)
	check(corpse.is_inside_tree(), "Current player corpse survives beyond twenty seconds until respawn.")
	world.respawn_click_ready = false # Simulate the left button already held at death.
	click(world, true)
	check(not player.is_alive, "Pre-death held/duplicate button press cannot respawn.")
	click(world, false)
	click(world, true)
	check(player.is_alive and world.screen == "game" and Engine.time_scale == 1.0, "Release and fresh click can skip the close-up and restore normal time.")
	check(corpse.is_inside_tree() and not corpse.keep_for_death_view and player.ragdoll == null, "Player respawn releases, rather than destroys, the old corpse.")
	check(not player.melee_held and not player.attack_pending, "Respawn click cannot leak into a new attack.")
	corpse._process(0.01)
	check(not corpse.is_inside_tree(), "An expired player corpse cleans up once no longer being watched.")
	await process_frame

	player.die()
	var began: int = Time.get_ticks_msec()
	await create_timer(1.32, true, false, true).timeout
	var duration: float = (Time.get_ticks_msec() - began) / 1000.0
	check(world.screen == "dead" and Engine.time_scale == 1.0 and not player.death_closeup, "Close-up restores normal time after 1.2 real seconds without a click.")
	check(not paused and not world.overlay.visible and not player.is_alive, "Finishing close-up never pauses, shows a menu, or auto-respawns.")
	print("DEATH_REAL_TIME_WAIT: ", duration, "s")
	click(world, true)
	check(player.is_alive, "Fresh click also respawns after the close-up ends.")
	check(get_nodes_in_group("ragdolls").size() == 1, "Respawning before twenty seconds preserves the player's old corpse.")

	player.die()
	enemy.defeat()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	world._input(escape)
	check(world.screen == "main" and not world.game_started and Engine.time_scale == 1.0, "Escape during close-up exits to menu and restores normal time.")
	check(get_nodes_in_group("ragdolls").is_empty() and world.enemy_respawn_remaining == -1, "Exit clears all corpses and respawn work.")
	world.start_game()
	enemy.ai_enabled = false
	enemy.set_physics_process(false)

	# Falling from high up must keep simulating after the old 2.8 second cutoff.
	enemy.position = Vector3(10, 90, 0)
	enemy.defeat()
	world.enemy_respawn_remaining = -1
	var falling: Node = enemy.ragdoll
	falling.keep_for_death_view = true
	await create_timer(3.0).timeout
	check(falling.elapsed > 2.8 and falling.bodies.Torso.global_position.y > 5, "High falling corpse still exists in mid-air after 2.8 seconds.")
	check(not falling.bodies.Torso.freeze and falling.bodies.Torso.linear_velocity.y < -1, "Airborne corpse is never forcibly frozen.")
	for body: RigidBody3D in falling.bodies.values():
		check(body.get_collision_exceptions().has(player), "Ragdoll excludes player without excluding terrain.")
		check(body.get_collision_exceptions().has(enemy), "Ragdoll excludes live enemy actor.")
		check(body.collision_mask == 13 and body.collision_layer == 4, "Corpse layers include terrain/corpses/thrown items only.")
	world.reset_round()

	# Flat-ground stability + native wakeability.
	enemy.defeat()
	world.enemy_respawn_remaining = -1
	var resting: Node = enemy.ragdoll
	resting.keep_for_death_view = true
	await create_timer(8.0).timeout
	var torso: RigidBody3D = resting.bodies.Torso
	print("CORPSE_REST: settled=", resting.settled, " sleeping=", torso.sleeping, " linear=", torso.linear_velocity.length(), " angular=", torso.angular_velocity.length())
	for body: RigidBody3D in resting.bodies.values():
		print("BODY_REST: ", body.name, " v=", body.linear_velocity.length(), " w=", body.angular_velocity.length(), " contacts=", body.get_contact_count())
	check(resting.settled and torso.sleeping, "Grounded corpse reaches stable native sleep.")
	check(not torso.freeze and resting.is_physics_processing(), "Rest keeps live physics and visual syncing for external wake-up.")
	torso.apply_central_impulse(Vector3(30, 25, 0))
	await frames(4)
	check(not torso.sleeping and torso.linear_velocity.length() > 0.1, "External impulse wakes a sleeping corpse.")
	world.reset_round()

	# A moving corpse on a long slope cannot be put to sleep by elapsed time.
	var ramp := StaticBody3D.new()
	var ramp_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.3, 80)
	ramp_shape.shape = box
	ramp.add_child(ramp_shape)
	world.add_child(ramp)
	ramp.position = Vector3(25, 16, 0)
	ramp.rotation.x = 0.4
	enemy.position = Vector3(25, 18, -12)
	enemy.defeat()
	world.enemy_respawn_remaining = -1
	var sliding: Node = enemy.ragdoll
	for body: RigidBody3D in sliding.bodies.values():
		body.physics_material_override.friction = 0.02
		body.linear_damp = 0.02
	await create_timer(3.2).timeout
	check(not sliding.settled and not sliding.bodies.Torso.freeze and sliding.bodies.Torso.linear_velocity.length() > 0.3, "Moving slope corpse remains dynamic after the old timeout.")
	ramp.queue_free()
	world.reset_round()

	# Arrow ray physically hits corpse; thrown objects participate in solver collisions.
	enemy.defeat()
	world.enemy_respawn_remaining = -1
	var target_body: RigidBody3D = enemy.ragdoll.bodies.Torso
	var arrow := Arrow.new()
	world.add_child(arrow)
	arrow.position = target_body.global_position + Vector3(0, 0, 1)
	arrow.velocity = Vector3(0, 0, -45)
	await frames(5)
	check(not is_instance_valid(arrow), "Arrow ray terminates on corpse collision layer.")
	var item := ThrownItem.new()
	world.add_child(item)
	item.position = target_body.global_position + Vector3(0, 0, 1.5)
	item.linear_velocity = Vector3(0, 0, -20)
	check(item.collision_mask == 7, "Thrown item solver and sweep include corpse layer without dropping combat layers.")
	await frames(12)
	check(not item.armed, "A real thrown weapon contact/sweep stops its damage on the corpse.")
	world.reset_round()
	check(get_nodes_in_group("projectiles").is_empty() and get_nodes_in_group("thrown_items").is_empty() and get_nodes_in_group("ragdolls").is_empty(), "Full reset removes projectiles, thrown items and all corpses.")
	world.queue_free()
	paused = false
	await process_frame
	check(Engine.time_scale == 1.0, "World disposal restores normal time.")
	print("DEATH_LIFECYCLE_SMOKE: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)
