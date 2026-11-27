extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/%s.png" % name)
	print("SHIELD_BASH_CAPTURE: ", name)

func capture() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "res://tests/capture-settings.cfg"
	world.training_mode = true
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	player.equip("longsword", "shield")
	player.select_slot(2)
	await create_timer(0.12).timeout
	player.set_physics_process(false)
	player.shield_requested = true
	player._physics_process(0.16)
	await snap("shield_bash_ready")
	player.shield_attack()
	player._physics_process(0.15)
	await snap("shield_bash_pull")
	player._physics_process(0.28)
	await snap("shield_bash_push")
	player._physics_process(0.4)
	await snap("shield_bash_recover")
	player._physics_process(0.37)
	await snap("shield_bash_raised")
	player.third_person = true
	player._update_camera()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = player.position + Vector3(2.1, 1.9, -3.0)
	camera.fov = 44
	camera.look_at(player.position + Vector3(0, 1.15, 0))
	camera.current = true
	world.hud.hide()
	player.shield_attack()
	player._physics_process(0.43)
	await snap("shield_bash_third_person")
	quit()
