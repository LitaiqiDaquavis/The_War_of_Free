extends Node3D

const ACTIONS: Dictionary = {
	"move_forward": "Move forward", "move_back": "Move backward",
	"move_left": "Move left", "move_right": "Move right",
	"jump": "Jump", "sprint": "Sprint (hold)", "toggle_view": "Switch camera",
	"main_slot": "Main hand only", "off_slot": "Use off hand",
	"throw_knife": "Throw knife", "kick": "Kick", "flip_dagger": "Pick up / flip dagger",
	"throw_item": "Throw held item", "prone": "Toggle prone"
}
const DEFAULT_KEYS: Dictionary = {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A,
	"move_right": KEY_D, "jump": KEY_SPACE, "sprint": KEY_SHIFT, "toggle_view": KEY_P,
	"main_slot": KEY_1, "off_slot": KEY_2,
	"throw_knife": KEY_Q, "kick": KEY_F, "flip_dagger": KEY_E,
	"throw_item": KEY_G, "prone": KEY_Z
}
const MAIN_WEAPONS: Dictionary = {"fists": "Fists", "dagger": "Dagger", "longsword": "Longsword", "spear": "Spear", "mace": "Mace"}
const OFF_WEAPONS: Dictionary = {"bow": "Bow", "shield": "Shield"}
const Dummy = preload("res://scripts/dummy.gd")
const LoadoutMenu = preload("res://scripts/loadout_menu.gd")

var settings_path: String = "user://settings.cfg"
var vsync_enabled: bool = true
var render_distance: float = 100.0
var shadow_quality: int = 1
var pending_action: String = ""
var game_started: bool = false
var screen: String = "main"
var overlay: Control
var content: VBoxContainer
var menu_center: CenterContainer
var loadout_menu: MarginContainer
var binding_buttons: Dictionary = {}
var notice: Label
var distance_value: Label
var play_button: Button
var main_hand: String = "longsword"
var off_hand: String = "shield"
var hit_timer: float = 0
var hit_total: int = 0
var match_number: int = 0
var attack_status: Label
var health_text: Label
var blocked_timer: float = 0
var training_mode: bool = false
var round_generation: int = 0
var enemy_respawn_generation: int = -1
var enemy_respawn_remaining: float = -1
var death_real_remaining: float = 0
var respawn_click_ready: bool = false

@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 60
	_load_settings()
	player.equip(main_hand, off_hand)
	player.hit_confirmed.connect(_on_hit)
	player.equipment_changed.connect(_update_hud)
	player.death_finished.connect(show_death_menu)
	player.death_started.connect(_on_death_started)
	player.health_changed.connect(_update_health)
	player.shield_blocked.connect(func() -> void: blocked_timer = 0.3)
	var enemy := Dummy.new()
	enemy.name = "TrainingEnemy"
	enemy.ai_enabled = not training_mode
	enemy.invulnerable = training_mode
	enemy.target = player
	add_child(enemy)
	enemy.defeated_started.connect(_on_enemy_defeated)
	apply_graphics()
	_build_shell()
	show_main_menu()
	_update_health()

func key_for(action: String) -> int:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return events[0].physical_keycode if not events.is_empty() else DEFAULT_KEYS[action]

func set_binding(action: String, code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)

func key_name(action: String) -> String:
	return OS.get_keycode_string(key_for(action))

func _load_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	vsync_enabled = bool(config.get_value("graphics", "vsync", true))
	render_distance = clampf(float(config.get_value("graphics", "distance", 100.0)), 50.0, 300.0)
	shadow_quality = clampi(int(config.get_value("graphics", "shadows", 1)), 0, 2)
	main_hand = str(config.get_value("loadout", "main", "longsword"))
	off_hand = str(config.get_value("loadout", "off", "shield"))
	if not MAIN_WEAPONS.has(main_hand):
		main_hand = "longsword"
	if not OFF_WEAPONS.has(off_hand):
		off_hand = "shield"
	for action: String in ACTIONS:
		var code: int = int(config.get_value("controls", action, DEFAULT_KEYS[action]))
		set_binding(action, code if code > 0 and code != KEY_ESCAPE else DEFAULT_KEYS[action])

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "vsync", vsync_enabled)
	config.set_value("graphics", "distance", render_distance)
	config.set_value("graphics", "shadows", shadow_quality)
	config.set_value("loadout", "main", main_hand)
	config.set_value("loadout", "off", off_hand)
	for action: String in ACTIONS:
		config.set_value("controls", action, key_for(action))
	if config.save(settings_path) != OK and is_instance_valid(notice):
		notice.text = "Settings could not be saved."

func apply_graphics() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	player.get_node("Camera3D").far = render_distance
	var sun: DirectionalLight3D = $Sun
	sun.shadow_enabled = shadow_quality > 0
	sun.directional_shadow_max_distance = minf(render_distance, 35.0 if shadow_quality == 1 else 70.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if shadow_quality < 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(2048 if shadow_quality == 2 else 1024, true)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

func _build_shell() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	var tint := ColorRect.new()
	tint.color = Color(0.025, 0.045, 0.065, 0.88)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(tint)
	var center := CenterContainer.new()
	menu_center = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(590, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14212c")
	style.border_color = Color("38505c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var theme := Theme.new()
	theme.default_font_size = 19
	overlay.theme = theme
	loadout_menu = LoadoutMenu.new()
	loadout_menu.name = "LoadoutMenu"
	overlay.add_child(loadout_menu)
	loadout_menu.hide()
	loadout_menu.main_selected.connect(func(id: String) -> void:
		main_hand = id
		save_settings())
	loadout_menu.off_selected.connect(func(id: String) -> void:
		off_hand = id
		save_settings())
	loadout_menu.start_requested.connect(start_game)
	loadout_menu.back_requested.connect(show_main_menu)
	attack_status = Label.new()
	attack_status.name = "AttackStatus"
	attack_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	attack_status.offset_left = -320
	attack_status.offset_right = 320
	attack_status.offset_top = -82
	attack_status.offset_bottom = -38
	attack_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attack_status.add_theme_font_size_override("font_size", 17)
	attack_status.add_theme_color_override("font_color", Color("e5ba7c"))
	attack_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	attack_status.add_theme_constant_override("shadow_offset_x", 1)
	attack_status.add_theme_constant_override("shadow_offset_y", 2)
	attack_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(attack_status)
	health_text = Label.new()
	health_text.name = "Health"
	health_text.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	health_text.offset_left = 24
	health_text.offset_right = 300
	health_text.offset_top = -64
	health_text.offset_bottom = -20
	health_text.add_theme_font_size_override("font_size", 24)
	health_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	health_text.add_theme_constant_override("shadow_offset_x", 1)
	health_text.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(health_text)

func _update_health() -> void:
	if is_instance_valid(health_text):
		health_text.text = "HEALTH  %d / 100" % player.health
		health_text.modulate = Color("ff8686") if player.health <= 40 else Color.WHITE

func _clear(title: String, subtitle: String) -> void:
	loadout_menu.hide()
	menu_center.show()
	pending_action = ""
	content.add_theme_constant_override("separation", 10)
	binding_buttons.clear()
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_label("THE WAR OF FREE", 15, Color("8ec8b0"))
	_label(title, 36)
	_label(subtitle, 16, Color("a7bbc6"))
	content.add_child(HSeparator.new())

func _label(text: String, size: int = 19, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	content.add_child(label)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 43
	button.pressed.connect(callback)
	content.add_child(button)
	return button

func show_main_menu() -> void:
	if not is_instance_valid(overlay):
		return
	_restore_time()
	screen = "main"
	player.set_controls_active(false)
	get_tree().paused = true
	hud.hide()
	overlay.show()
	_clear("The proving ground", "Choose your weapons. Face an enemy soldier.")
	play_button = _button("Play", show_loadout)
	_button("Controls", show_controls)
	_button("Graphics", show_graphics)
	_button("Quit", func() -> void: get_tree().quit())
	_label("%s %s %s %s  Move  /  %s  Sprint  /  %s  Jump" % [key_name("move_forward"), key_name("move_left"), key_name("move_back"), key_name("move_right"), key_name("sprint"), key_name("jump")], 15, Color("a7bbc6"))
	play_button.grab_focus()

func show_pause_menu() -> void:
	if not game_started or not player.is_alive:
		return
	screen = "pause"
	player.set_controls_active(false)
	get_tree().paused = true
	hud.hide()
	overlay.show()
	_clear("Paused", "The match is paused.")
	var resume := _button("Resume", start_game)
	_button("Suicide", suicide)
	_button("Graphics", show_graphics)
	_button("Exit to main menu", end_match)
	resume.grab_focus()

func menu_back() -> void:
	if game_started:
		show_pause_menu()
	else:
		show_main_menu()

func _restore_time() -> void:
	Engine.time_scale = 1.0
	death_real_remaining = 0
	player.death_closeup = false

func _on_enemy_defeated() -> void:
	if training_mode or not game_started:
		return
	enemy_respawn_generation = round_generation
	enemy_respawn_remaining = 2.0

func _respawn_enemy() -> void:
	if enemy_respawn_generation != round_generation or not game_started or training_mode:
		return
	var enemy: Node = get_node("TrainingEnemy")
	if not enemy.defeated:
		return
	# Corpse owns itself from here; actor reset must not dispose it.
	enemy.ragdoll = null
	enemy.reset_for_match()

func respawn_player() -> void:
	if player.is_alive or not game_started:
		return
	_restore_time()
	if is_instance_valid(player.ragdoll):
		# Keep old corpse until its original real-time deadline (not another 20s).
		player.ragdoll.keep_for_death_view = false
		player.ragdoll = null
	player.reset_for_match()
	player.equip(main_hand, off_hand)
	respawn_click_ready = false
	start_game()

func reset_round() -> void:
	round_generation += 1
	enemy_respawn_remaining = -1
	enemy_respawn_generation = -1
	respawn_click_ready = false
	_restore_time()
	player.set_controls_active(false)
	player.reset_for_match()
	for projectile: Node in get_tree().get_nodes_in_group("projectiles"):
		projectile.get_parent().remove_child(projectile)
		projectile.queue_free()
	for item: Node in get_tree().get_nodes_in_group("thrown_items"):
		item.get_parent().remove_child(item)
		item.queue_free()
	get_node("TrainingEnemy").reset_for_match()
	for corpse: Node in get_tree().get_nodes_in_group("ragdolls"):
		corpse.dispose()
	hit_total = 0
	hit_timer = 0
	blocked_timer = 0
	$HUD/Crosshair.text = "+"
	$HUD/Crosshair.modulate = Color.WHITE

func end_match() -> void:
	game_started = false
	reset_round()
	show_main_menu()

func suicide() -> void:
	if not game_started or not player.is_alive:
		return
	player.die()

func _on_death_started() -> void:
	screen = "dying"
	hud.hide()
	overlay.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# A held attack cannot become a respawn. Require release then a fresh press.
	respawn_click_ready = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	death_real_remaining = 1.2
	Engine.time_scale = 0.2

func show_death_menu() -> void:
	# Kept for the existing signal API, deliberately no blocking menu or pause.
	if screen == "dying" and death_real_remaining <= 0:
		screen = "dead"

func show_loadout() -> void:
	screen = "loadout"
	pending_action = ""
	player.set_controls_active(false)
	get_tree().paused = true
	hud.hide()
	overlay.show()
	menu_center.hide()
	loadout_menu.present(main_hand, off_hand, key_name("throw_knife"), key_name("kick"), key_name("flip_dagger"))

func start_game() -> void:
	if not game_started:
		reset_round()
		player.equip(main_hand, off_hand)
		match_number += 1
	elif not player.is_alive:
		return
	game_started = true
	screen = "game"
	pending_action = ""
	overlay.hide()
	hud.show()
	get_tree().paused = false
	player.set_controls_active(true)
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	var equipped: String = MAIN_WEAPONS[player.main_hand]
	if player.main_hand == "dagger" and player.dagger_reverse:
		equipped += " (Reverse grip)"
	if player.active_slot == 2 and not player.off_dropped:
		equipped = "Bow" if player.off_hand == "bow" else equipped + " + Shield"
	$HUD/Instructions.text = "THE WAR OF FREE  |  %s\n%s %s %s %s Move  |  %s Sprint  |  %s Jump  |  %s Camera\n%s Main hand  |  %s Off hand  |  LMB Melee / Shield bash / Shoot\nRMB Shield / 2x zoom  |  %s Knife  |  %s Kick  |  %s Throw item  |  %s Prone  |  Esc Pause" % [equipped, key_name("move_forward"), key_name("move_left"), key_name("move_back"), key_name("move_right"), key_name("sprint"), key_name("jump"), key_name("toggle_view"), key_name("main_slot"), key_name("off_slot"), key_name("throw_knife"), key_name("kick"), key_name("throw_item"), key_name("prone")]

func _on_hit() -> void:
	hit_timer = 0.35 if player.last_hit_critical else 0.2
	hit_total += 1
	$HUD/Crosshair.text = "x"
	$HUD/Crosshair.modulate = Color("e5ba7c") if player.last_hit_critical else Color("ff7777")

func _process(delta: float) -> void:
	if game_started and not get_tree().paused:
		var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
		if enemy_respawn_remaining >= 0:
			enemy_respawn_remaining -= real_delta
			if enemy_respawn_remaining <= 0:
				enemy_respawn_remaining = -1
				_respawn_enemy()
		if death_real_remaining > 0:
			death_real_remaining = maxf(0, death_real_remaining - real_delta)
			if death_real_remaining <= 0:
				_restore_time()
				screen = "dead"
	if screen != "game":
		return
	hit_timer = maxf(0, hit_timer - delta)
	blocked_timer = maxf(0, blocked_timer - delta)
	attack_status.text = ""
	var pickup: Node = player.get_pickup_target()
	if is_instance_valid(pickup):
		var item_name: String = "Shield" if pickup.kind == "shield" else MAIN_WEAPONS[pickup.kind]
		var slot_name: String = "off hand" if pickup.kind == "shield" else "main hand"
		attack_status.text = "%s  Pick up %s  |  Replace %s" % [key_name("flip_dagger"), item_name, slot_name] if player.can_pickup() else "Finish action to pick up " + item_name
	elif blocked_timer > 0:
		attack_status.text = "BLOCKED"
	elif get_node("TrainingEnemy").defeated:
		attack_status.text = "ENEMY DEFEATED"
	elif hit_timer > 0 and player.last_hit_critical:
		attack_status.text = "CRITICAL HIT"
	elif player.bow_active() and player.sprinting:
		attack_status.text = "Stop sprinting to ready the bow"
	elif player.bow_active() and not player.bow_ready() and player.special_action.is_empty():
		attack_status.text = player.bow_status()
	elif player.main_hand == "dagger" and not player.bow_active():
		attack_status.text = "%s  Flip grip  |  %s" % [key_name("flip_dagger"), "Reverse: downward stab" if player.dagger_reverse else "Normal: slash"]
	if hit_timer == 0:
		$HUD/Crosshair.text = "+"
		$HUD/Crosshair.modulate = Color.WHITE

func show_controls() -> void:
	screen = "controls"
	_clear("Controls", "Select an action, then press a key. Esc cancels.")
	content.add_theme_constant_override("separation", 4)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 390
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	for action: String in ACTIONS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = ACTIONS[action]
		label.add_theme_font_size_override("font_size", 18)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.text = key_name(action)
		button.add_theme_font_size_override("font_size", 18)
		button.custom_minimum_size = Vector2(180, 30)
		button.pressed.connect(_begin_rebind.bind(action))
		row.add_child(button)
		binding_buttons[action] = button
		rows.add_child(row)
	notice = _label("Scroll for more bindings. Escape is reserved for the menu.", 15, Color("a7bbc6"))
	_button("Reset controls", func() -> void:
		for action: String in DEFAULT_KEYS:
			set_binding(action, DEFAULT_KEYS[action])
		save_settings()
		show_controls())
	_button("Back", menu_back)

func _begin_rebind(action: String) -> void:
	for previous: String in binding_buttons:
		binding_buttons[previous].text = key_name(previous)
	pending_action = action
	binding_buttons[action].text = "Press a key..."
	notice.text = "Listening for a key. Esc cancels."

func show_graphics() -> void:
	screen = "graphics"
	_clear("Graphics", "Changes apply immediately and are saved automatically.")
	var vsync := CheckButton.new()
	vsync.text = "Vertical sync"
	vsync.button_pressed = vsync_enabled
	vsync.toggled.connect(func(enabled: bool) -> void:
		vsync_enabled = enabled
		apply_graphics()
		save_settings())
	content.add_child(vsync)
	distance_value = _label("Render distance: %d m" % render_distance)
	var distance := HSlider.new()
	distance.min_value = 50
	distance.max_value = 300
	distance.step = 10
	distance.value = render_distance
	distance.custom_minimum_size.y = 30
	distance.value_changed.connect(func(value: float) -> void:
		render_distance = value
		distance_value.text = "Render distance: %d m" % value
		apply_graphics()
		save_settings())
	content.add_child(distance)
	_label("Shadows")
	var shadows := OptionButton.new()
	shadows.custom_minimum_size.y = 42
	shadows.add_item("Off")
	shadows.add_item("Low (default)")
	shadows.add_item("High")
	shadows.select(shadow_quality)
	shadows.item_selected.connect(func(index: int) -> void:
		shadow_quality = index
		apply_graphics()
		save_settings())
	content.add_child(shadows)
	notice = _label("Default: 100 m, low shadows. Frame limit: 60 FPS.", 16, Color("a7bbc6"))
	_button("Reset graphics", func() -> void:
		vsync_enabled = true
		render_distance = 100
		shadow_quality = 1
		apply_graphics()
		save_settings()
		show_graphics())
	_button("Back", menu_back)

func _input(event: InputEvent) -> void:
	if screen in ["dying", "dead"] and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if not event.pressed:
			respawn_click_ready = true
		elif respawn_click_ready:
			respawn_player()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not pending_action.is_empty():
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE:
			show_controls()
			return
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		for action: String in ACTIONS:
			if action != pending_action and key_for(action) == code:
				notice.text = "Already used by %s. Choose another key." % ACTIONS[action]
				return
		set_binding(pending_action, code)
		save_settings()
		show_controls()
	elif event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if screen in ["dying", "dead"]:
			end_match()
			return
		if screen == "game":
			show_pause_menu()
		elif screen == "pause":
			start_game()
		elif screen == "dead":
			end_match()
		elif screen != "main":
			menu_back()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and screen == "game":
		show_pause_menu()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
