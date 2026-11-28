extends SceneTree

var output_dir: String = "user://bow-captures"
var world: Node
var player: Node
var observer: Camera3D
var captures: int = 0

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	call_deferred("capture")

func snap(label: String) -> void:
	for third in [false, true]:
		player.third_person = third
		player._update_camera()
		player._animate_locomotion(0)
		player._update_weapon_pose()
		if third:
			observer.current = true
		else:
			player.camera.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = output_dir.path_join("bow_%s_%s.png" % [label, "third" if third else "first"])
		if image.is_empty() or image.save_png(path) != OK:
			push_error("Capture failed: " + path)
			quit(1)
			return
		captures += 1
		print("BOW_CAPTURE: ", path)

func capture() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://capture-bow-settings.cfg"
	world.training_mode = true
	world.battle_mode = false
	root.add_child(world)
	world.start_game()
	player = world.player
	world.get_node("TrainingEnemy").set_physics_process(false)
	for index in range(5):
		await physics_frame
	player.set_physics_process(false)
	player.equip("spear", "bow")
	player.select_slot(2)
	player.look_pitch = 0
	observer = Camera3D.new()
	world.add_child(observer)
	observer.position = player.position + Vector3(2.1, 1.9, -3.0)
	observer.fov = 44
	observer.look_at(player.position + Vector3(0, 1.15, 0))
	world.hud.hide()
	player._tick_bow(0.225)
	await snap("equip")
	player._tick_bow(0.425)
	await snap("nock")
	player._tick_bow(0.2)
	await snap("ready")
	player.shoot_bow()
	# Keep the freshly spawned arrow visible for capture, without simulation.
	for arrow in get_nodes_in_group("arrows"):
		arrow.set_physics_process(false)
	player._tick_bow(0.04)
	await snap("overpull")
	player._tick_bow(0.035)
	await snap("release")
	player._tick_bow(0.08125)
	await snap("string")
	player._tick_bow(0.2)
	await snap("cooldown")
	player._tick_bow(0.59375)
	await snap("renock")
	print("BOW_GRAPHICS: PASS (", captures, " captures)")
	quit(0)
