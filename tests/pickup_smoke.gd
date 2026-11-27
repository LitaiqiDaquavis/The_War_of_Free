extends SceneTree

const Thrown = preload("res://scripts/thrown_item.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame

func press_e(player: Node) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	player._unhandled_input(event)

func reset(world: Node, kind: String = "dagger", off: String = "shield") -> void:
	world.game_started = false
	world.start_game()
	world.player.set_physics_process(false)
	world.player.position = Vector3(0, 0, 8)
	world.player.equip(kind, off)
	await frames(2)

func spawn_item(world: Node, kind: String, point: Vector3 = Vector3(0, 1.2, 6.1)) -> Node:
	var item := Thrown.new()
	item.kind = kind
	item.shooter = world.player
	world.add_child(item)
	item.global_position = point
	item.previous_position = point
	item.freeze = true
	return item

func aim(player: Node, item: Node) -> void:
	for index in range(12):
		player._update_camera()
		var target: Vector3 = item.find_children("*", "CollisionShape3D", true, false)[0].global_position
		var direction: Vector3 = target - player.camera.global_position
		player.rotation.y = atan2(-direction.x, -direction.z)
		player.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	player._update_camera()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "res://tests/pickup-settings.cfg"
	world.training_mode = true
	root.add_child(world)
	var player: Node = world.player
	for kind: String in ["dagger", "longsword", "spear", "mace"]:
		await reset(world)
		player.select_slot(2)
		player.shield_requested = true
		player.blocking = true
		player.shield_blend = 1
		var item: Node = spawn_item(world, kind)
		aim(player, item)
		await frames(2)
		check(player.get_pickup_target() == item, "The crosshair must identify thrown equipment: " + kind)
		world._process(0)
		check("Pick up" in world.attack_status.text and not "Flip grip" in world.attack_status.text, "Pickup hint must take priority over dagger grip.")
		press_e(player)
		check(player.main_hand == kind and not player.dagger_reverse, "E must equip the aimed main weapon instead of flipping: " + kind)
		check(player.off_hand == "shield" and not player.off_dropped and player.active_slot == 2 and player.blocking, "Main pickup must preserve the other hand and held guard.")
		check(get_nodes_in_group("thrown_items").is_empty() and not item.is_inside_tree(), "Pickup must remove the physical item without dropping a replacement.")
		check(not item.claim(), "An item must not be claimable twice.")
		await frames(1)
	await reset(world, "dagger", "bow")
	player.dagger_reverse = true
	player.dagger_grip_blend = 1
	var shield: Node = spawn_item(world, "shield")
	aim(player, shield)
	await frames(2)
	press_e(player)
	check(player.main_hand == "dagger" and player.dagger_reverse and player.dagger_grip_blend == 1, "Picking a shield must preserve a reverse-grip dagger.")
	check(player.off_hand == "shield" and player.active_slot == 2 and not player.off_dropped and player.off_mount.visible, "A shield pickup must replace a bow in the off-hand slot and show it.")
	await reset(world, "longsword", "shield")
	player.off_dropped = true
	player.select_slot(2)
	var mace: Node = spawn_item(world, "mace")
	aim(player, mace)
	await frames(2)
	press_e(player)
	check(player.main_hand == "mace" and player.off_dropped and not player.off_mount.visible, "Picking a main weapon must not regenerate an already-thrown shield.")
	await reset(world, "longsword", "bow")
	player.select_slot(2)
	player._tick_bow(0.12)
	var dagger: Node = spawn_item(world, "dagger")
	aim(player, dagger)
	await frames(2)
	press_e(player)
	check(player.main_hand == "dagger" and player.off_hand == "bow" and player.active_slot == 1 and player.bow_prepare_elapsed == 0, "Picking a right-hand weapon must put the bow away without deleting it.")
	await reset(world)
	var blocked: Node = spawn_item(world, "mace")
	aim(player, blocked)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 1.4, 7)
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2, 2, 0.1)
	var collision := CollisionShape3D.new()
	collision.shape = wall_shape
	wall.add_child(collision)
	world.add_child(wall)
	await frames(2)
	check(player.get_pickup_target() == null, "Walls must stop pickup targeting.")
	press_e(player)
	check(player.main_hand == "dagger" and player.dagger_reverse and blocked.is_inside_tree(), "When no pickup is visible, E must retain dagger flip behavior.")
	wall.queue_free()
	await reset(world)
	var far_item: Node = spawn_item(world, "mace", Vector3(0, 1.2, 1))
	aim(player, far_item)
	await frames(2)
	check(player.get_pickup_target() == null, "Distant gear must not be picked up across the map.")
	await reset(world)
	var busy_item: Node = spawn_item(world, "mace")
	aim(player, busy_item)
	await frames(2)
	player.attack()
	var duration: float = player.attack_duration
	press_e(player)
	check(player.main_hand == "dagger" and player.attack_duration == duration and not player.dagger_flip_queued and busy_item.is_inside_tree(), "A busy pickup must consume E without skipping recovery or queuing a flip.")
	player._tick_melee(duration)
	press_e(player)
	check(player.main_hand == "mace", "The same aimed pickup must work after recovery.")
	await reset(world)
	player.third_person = true
	player._update_camera()
	var rear_item: Node = spawn_item(world, "longsword")
	aim(player, rear_item)
	await frames(2)
	check(player.get_pickup_target() == rear_item, "Rear third-person targeting must use character reach, not camera distance.")
	press_e(player)
	check(player.main_hand == "longsword" and player.third_person, "Pickup must preserve the camera mode.")
	await reset(world)
	var flying: Node = spawn_item(world, "longsword")
	flying.freeze = false
	flying.linear_velocity = Vector3.RIGHT
	aim(player, flying)
	await frames(2)
	check(player.get_pickup_target() == flying, "In-flight gear can be caught when it is aimed at within reach.")
	flying._on_contact(world.get_node("TrainingEnemy"))
	press_e(player)
	await frames(2)
	check(player.main_hand == "longsword" and world.get_node("TrainingEnemy").hit_count == 0, "A caught item's queued impact must not damage anything after pickup.")
	await reset(world, "longsword")
	player.rotation.y = PI / 2
	player._update_camera()
	player.throw_held_item()
	player._physics_process(player.ITEM_THROW_RELEASE)
	player._physics_process(player.ITEM_THROW_DURATION - player.ITEM_THROW_RELEASE)
	await frames(90)
	var dropped: Node = get_nodes_in_group("thrown_items")[0]
	check(player.main_hand == "fists" and dropped.global_position.y < 0.8, "The original G-thrown weapon must actually leave the hand and land.")
	dropped.freeze = true
	player.position = Vector3(dropped.global_position.x, 0, dropped.global_position.z + 2)
	aim(player, dropped)
	await frames(2)
	press_e(player)
	check(player.main_hand == "longsword" and get_nodes_in_group("thrown_items").is_empty(), "The original G-thrown and landed weapon must be recoverable with E.")
	await reset(world, "fists")
	player.prone = true
	player.prone_blend = 1
	player._set_prone_collision(true)
	player._animate_locomotion(0)
	player.health = 60
	player._update_camera()
	var low_item: Node = spawn_item(world, "dagger", Vector3(0, 0.2, 6))
	aim(player, low_item)
	await frames(2)
	press_e(player)
	check(player.main_hand == "dagger" and player.prone and player.health == 60, "Prone pickup must keep the character's stance and health.")
	await reset(world, "fists")
	var recovered: Node = spawn_item(world, "spear")
	aim(player, recovered)
	await frames(2)
	press_e(player)
	player.throw_held_item()
	player._physics_process(player.ITEM_THROW_RELEASE)
	check(player.main_hand == "fists" and get_nodes_in_group("thrown_items").size() == 1 and get_nodes_in_group("thrown_items")[0].kind == "spear", "Recovered equipment must be throwable again without duplication.")
	world.end_match()
	check(get_nodes_in_group("thrown_items").is_empty(), "Round cleanup must include recovered and rethrown gear.")
	world.queue_free()
	paused = false
	await process_frame
	print("PICKUP_SMOKE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
