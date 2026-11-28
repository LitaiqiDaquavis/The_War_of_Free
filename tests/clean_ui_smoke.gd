extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var capture_dir: String = ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		capture_dir = OS.get_cmdline_user_args()[0]
	call_deferred("run")

func frames() -> void:
	for i in range(4):
		await process_frame

func visible_text(node: Node) -> Array[String]:
	var result: Array[String] = []
	if (node is Label or node is Label3D or node is Button) and node.is_visible_in_tree() and not node.text.is_empty():
		result.append(node.text)
	for child in node.get_children():
		result.append_array(visible_text(child))
	return result

func snap(filename: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png(capture_dir.path_join(filename)) == OK, "Screenshot: " + filename)

func escape(world: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	world._input(event)

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://clean-ui-smoke.cfg"
	world.training_mode = true
	world.battle_mode = false
	root.add_child(world)
	world.play_button.pressed.emit()
	await frames()
	var menu: Node = world.loadout_menu
	check(world.screen == "loadout" and menu.visible, "Play opens equipment")
	check(not menu.has_node("EquipmentDetails") and menu.find_children("*", "TextureRect", true, false).size() == 7, "Only seven card thumbnails, no detail preview")
	var allowed: Array[String] = ["01   MAIN HAND", "02   OFF HAND", "Fists", "Dagger", "Longsword", "Spear", "Mace", "Bow", "Shield", "Back", "Start game  >"]
	for text in visible_text(menu):
		check(text in allowed, "No extra equipment text: " + text)
	check(visible_text(menu).size() == allowed.size(), "Minimal equipment text complete")
	check(menu.icons.size() == 7, "Every thumbnail still generated")
	for primary: String in menu.MAIN_IDS:
		for secondary: String in menu.OFF_IDS:
			menu.main_cards[primary].pressed.emit()
			menu.off_cards[secondary].pressed.emit()
			check(world.main_hand == primary and world.off_hand == secondary, "Selection signals: " + primary + "/" + secondary)
			for id: String in menu.MAIN_IDS:
				check(menu.main_cards[id].button_pressed == (id == primary), "Exclusive main highlight: " + id)
			for id: String in menu.OFF_IDS:
				check(menu.off_cards[id].button_pressed == (id == secondary), "Exclusive off highlight: " + id)
			menu.start_button.pressed.emit()
			check(world.screen == "game" and not paused and world.player.main_hand == primary and world.player.off_hand == secondary, "Start selected combination")
			check(visible_text(world) == ["+"], "Only crosshair label; HP drawn by health ring")
			escape(world)
			check(world.screen == "pause" and paused and "Resume" in visible_text(world), "Escape pauses; pause text retained")
			escape(world)
			check(world.screen == "game" and not paused, "Escape resumes")
			world.end_match()
			check(world.screen == "main" and "Play" in visible_text(world), "Return to main")
			world.show_loadout()
	for card: Button in menu.main_cards.values() + menu.off_cards.values():
		check(card.tooltip_text.is_empty(), "No long hover description")
		check(card.get_theme_stylebox("pressed").border_color != card.get_theme_stylebox("normal").border_color, "Selection has distinct border")
	menu.back_button.pressed.emit()
	check(world.screen == "main", "Equipment Back works")
	world.show_controls()
	check("Controls" in visible_text(world), "Controls retained")
	world.menu_back()
	world.show_graphics()
	check("Graphics" in visible_text(world), "Graphics retained")
	world.menu_back()
	world.show_loadout()
	menu.main_cards["longsword"].pressed.emit()
	menu.off_cards["shield"].pressed.emit()
	await frames()
	await snap("loadout_clean.png")
	world.start_game()
	await frames()
	check(visible_text(world) == ["+"] and world.health_ring.visible and world.health_ring.health == world.player.health, "Ring plus crosshair, no other HUD text")
	await snap("battle_clean.png")
	world.player.last_hit_critical = true
	world._on_hit()
	check(visible_text(world) == ["x"] and world.hud.get_node("Crosshair").modulate == Color("e5ba7c"), "Critical hit only changes crosshair symbol/color")
	world._process(0.4)
	check(visible_text(world) == ["+"], "Crosshair resets without status text")
	world.get_node("TrainingEnemy").health_label.text = "ENEMY DEFEATED"
	check(not world.get_node("TrainingEnemy").health_label.is_visible_in_tree(), "Enemy lifecycle diagnostic label stays hidden")
	world.end_match()
	world.queue_free()
	await process_frame
	print("CLEAN_UI_SMOKE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
