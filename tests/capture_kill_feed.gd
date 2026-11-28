extends SceneTree
const Icon = preload("res://scripts/kill_weapon_icon.gd")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://capture-kill-feed.cfg"
	root.add_child(world)
	world.start_game()
	world.player.set_physics_process(false)
	for soldier: Node in world.soldiers:
		soldier.set_physics_process(false)
	# Real death callbacks: red Archer -> blue Archer, blue Knight -> red Knight.
	var blue_archer: Node = world.soldiers[0]
	var red_archer: Node = world.soldiers[19]
	blue_archer.health = 20
	blue_archer.blocking = false
	blue_archer.take_projectile_hit(blue_archer.get_combat_aim_point(), Vector3.FORWARD, "arrow", red_archer)
	world.player.equip("mace", "shield")
	var red_knight: Node = world.soldiers[30]
	red_knight.health = 40
	red_knight.blocking = false
	red_knight.take_melee_hit(red_knight.get_combat_aim_point(), Vector3.FORWARD, 40, false, world.player)
	world.player.third_person = true
	world.player._update_camera()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/root/.openclaw/workspace/output/war-kill-feed-1128/kill-feed-gameplay.png")
	# Separate visual review sheet includes every supported weapon silhouette.
	var gallery := VBoxContainer.new()
	gallery.position = Vector2(220, 90)
	world.kill_feed_layer.add_child(gallery)
	var title := Label.new()
	title.text = "WEAPON ICON REVIEW - BUSINESS END RIGHT"
	title.add_theme_font_size_override("font_size", 22)
	gallery.add_child(title)
	for kind: String in Icon.SUPPORTED:
		var panel := PanelContainer.new()
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = kind.capitalize().replace("_", " ")
		label.custom_minimum_size.x = 210
		line.add_child(label)
		var icon := Icon.new()
		icon.kind = kind
		line.add_child(icon)
		panel.add_child(line)
		gallery.add_child(panel)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/root/.openclaw/workspace/output/war-kill-feed-1128/weapon-icons-review.png")
	print("KILL_FEED_CAPTURE: PASS")
	quit()
