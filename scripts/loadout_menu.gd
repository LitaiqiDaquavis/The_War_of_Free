extends MarginContainer

signal main_selected(id: String)
signal off_selected(id: String)
signal start_requested
signal back_requested

const Visuals = preload("res://scripts/visuals.gd")
const PlayerScript = preload("res://scripts/player.gd")
const MAIN_IDS: Array[String] = ["fists", "dagger", "longsword", "spear", "mace"]
const OFF_IDS: Array[String] = ["bow", "shield"]
const INFO: Dictionary = {
	"fists": ["Fists", "UNARMED", "Close the distance and punch straight toward your aim. Your armored gloves stay on."],
	"dagger": ["Dagger", "TWO GRIPS", "A quick slash in normal grip. Press {grip} to flip into a downward stab. Best used at close range."],
	"longsword": ["Longsword", "SWEEPING BLADE", "A balanced blade with more reach than a dagger. Sweep across the target from right to left."],
	"spear": ["Spear", "LONG REACH", "Keep your distance. Lower the spear from its upright stance into a forward thrust."],
	"mace": ["Mace", "OVERHEAD STRIKE", "A spiked head on a short haft. Bring it down in a deliberate overhead strike."],
	"bow": ["Bow", "RANGED OFF HAND", "Automatically nock and draw in 0.3 seconds. Click to release. Carry the bow with both hands while sprinting."],
	"shield": ["Shield", "GUARD & BASH", "Hold RMB to guard. While guarding, tap LMB for a 20-damage shield bash. The strike and recovery leave you exposed."]
}
const GOLD := Color("e5ba7c")
const MUTED := Color("99aebd")
const INK := Color("101b25")

var main_hand: String = "longsword"
var off_hand: String = "shield"
var grip_key: String = "E"
var main_cards: Dictionary = {}
var off_cards: Dictionary = {}
var icons: Dictionary = {}
var selected_tags: Dictionary = {}
var detail_icon: TextureRect
var detail_name: Label
var detail_role: Label
var detail_description: Label
var detail_stats: Label
var summary: Label
var standard_kit: Label
var start_button: Button
var back_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right"]:
		add_theme_constant_override("margin_" + edge, 28)
	for edge: String in ["top", "bottom"]:
		add_theme_constant_override("margin_" + edge, 22)
	for id: String in MAIN_IDS + OFF_IDS:
		icons[id] = _render_icon(id)
	_build()

func _style(color: Color, border: Color, padding: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _label(parent: Node, text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build() -> void:
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", _style(INK, Color("3f5360"), 24))
	add_child(board)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	board.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_constant_override("separation", 2)
	heading.add_child(title)
	_label(title, "THE WAR OF FREE  /  FIELD ARMORY", 12, GOLD)
	_label(title, "Choose your kit", 32)
	_label(title, "Pick a main weapon and an off-hand item before entering the field.", 15, MUTED)
	var availability := VBoxContainer.new()
	availability.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_child(availability)
	_label(availability, "PROVING GROUND", 12, Color("9bcbb7"))
	_label(availability, "All equipment available", 13, MUTED)
	column.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	column.add_child(body)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_stretch_ratio = 1.7
	choices.add_theme_constant_override("separation", 10)
	body.add_child(choices)
	_label(choices, "01   MAIN HAND", 13, GOLD)
	var grid := GridContainer.new()
	grid.name = "MainWeapons"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	choices.add_child(grid)
	for id: String in MAIN_IDS:
		main_cards[id] = _card(grid, id)
	_label(choices, "02   OFF HAND", 13, Color("9bcbb7"))
	var off_row := HBoxContainer.new()
	off_row.name = "OffHandItems"
	off_row.add_theme_constant_override("separation", 10)
	choices.add_child(off_row)
	for id: String in OFF_IDS:
		off_cards[id] = _card(off_row, id)
	standard_kit = _label(choices, "", 12, MUTED)
	standard_kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var details := PanelContainer.new()
	details.name = "EquipmentDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.custom_minimum_size.x = 280
	details.add_theme_stylebox_override("panel", _style(Color("182733"), Color("314553"), 20))
	body.add_child(details)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 10)
	details.add_child(detail_column)
	detail_role = _label(detail_column, "", 12, GOLD)
	detail_icon = TextureRect.new()
	detail_icon.custom_minimum_size.y = 120
	detail_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_column.add_child(detail_icon)
	detail_name = _label(detail_column, "", 28)
	detail_description = _label(detail_column, "", 15, Color("bdcbd4"))
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description.custom_minimum_size.y = 78
	detail_column.add_child(HSeparator.new())
	detail_stats = _label(detail_column, "", 14, Color("a8cbbb"))
	detail_stats.custom_minimum_size.y = 42
	column.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	column.add_child(footer)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(110, 52)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back_button)
	var readiness := VBoxContainer.new()
	readiness.alignment = BoxContainer.ALIGNMENT_CENTER
	readiness.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(readiness)
	_label(readiness, "YOUR LOADOUT", 11, MUTED)
	summary = _label(readiness, "", 18)
	start_button = Button.new()
	start_button.text = "Start game  >"
	start_button.custom_minimum_size = Vector2(190, 52)
	start_button.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 14))
	start_button.add_theme_stylebox_override("hover", _style(GOLD.lightened(0.13), GOLD.lightened(0.13), 14))
	start_button.add_theme_stylebox_override("pressed", _style(GOLD.darkened(0.12), GOLD, 14))
	start_button.add_theme_color_override("font_color", INK)
	start_button.add_theme_color_override("font_hover_color", INK)
	start_button.add_theme_color_override("font_pressed_color", INK)
	start_button.pressed.connect(func() -> void: start_requested.emit())
	footer.add_child(start_button)

func _card(parent: Node, id: String) -> Button:
	var card := Button.new()
	card.name = id.capitalize().replace(" ", "") + "Card"
	card.custom_minimum_size = Vector2(120, 108)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.toggle_mode = true
	card.tooltip_text = str(INFO[id][0]) + ": " + str(INFO[id][2])
	card.add_theme_stylebox_override("normal", _style(Color("1c2c39"), Color("354b5a"), 10))
	card.add_theme_stylebox_override("hover", _style(Color("293c49"), Color("7e938e"), 10))
	card.add_theme_stylebox_override("pressed", _style(Color("344039"), GOLD, 10))
	card.add_theme_stylebox_override("hover_pressed", _style(Color("405045"), GOLD, 10))
	card.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color("cbe4dc"), 0))
	parent.add_child(card)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 12)
	inset.add_theme_constant_override("margin_right", 12)
	inset.add_theme_constant_override("margin_top", 8)
	inset.add_theme_constant_override("margin_bottom", 8)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inset)
	var contents := VBoxContainer.new()
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_theme_constant_override("separation", 2)
	inset.add_child(contents)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(top)
	var name_label := _label(top, str(INFO[id][0]), 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_tags[id] = _label(top, "", 10, GOLD)
	var icon := TextureRect.new()
	icon.texture = icons[id]
	icon.custom_minimum_size.y = 58
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(icon)
	card.pressed.connect(_choose.bind(id))
	card.mouse_entered.connect(inspect.bind(id))
	card.focus_entered.connect(inspect.bind(id))
	return card

func present(primary: String, secondary: String, throw_key: String, kick_key: String, flip_key: String = "E") -> void:
	main_hand = primary
	off_hand = secondary
	grip_key = flip_key
	for id: String in MAIN_IDS + OFF_IDS:
		var cards: Dictionary = main_cards if id in MAIN_IDS else off_cards
		cards[id].tooltip_text = str(INFO[id][0]) + ": " + str(INFO[id][2]).replace("{grip}", grip_key)
	standard_kit.text = "INCLUDED   Starter armor  /  %s Throw knife  /  %s Kick" % [throw_key, kick_key]
	_refresh_selection()
	show()
	main_cards[main_hand].grab_focus()
	inspect(main_hand)

func _choose(id: String) -> void:
	if id in MAIN_IDS:
		main_hand = id
		main_selected.emit(id)
	else:
		off_hand = id
		off_selected.emit(id)
	_refresh_selection()
	inspect(id)

func _refresh_selection() -> void:
	for id: String in main_cards:
		main_cards[id].set_pressed_no_signal(id == main_hand)
		selected_tags[id].text = "READY" if id == main_hand else ""
	for id: String in off_cards:
		off_cards[id].set_pressed_no_signal(id == off_hand)
		selected_tags[id].text = "READY" if id == off_hand else ""
	summary.text = "%s  +  %s" % [INFO[main_hand][0], INFO[off_hand][0]]

func inspect(id: String) -> void:
	detail_icon.texture = icons[id]
	detail_role.text = INFO[id][1]
	detail_name.text = INFO[id][0]
	detail_description.text = str(INFO[id][2]).replace("{grip}", grip_key)
	if id in MAIN_IDS:
		var weapon: Dictionary = PlayerScript.WEAPONS[id]
		detail_stats.text = "Reach %.1f m  /  Attack %.2f s\nHold LMB: automatic heavy strike" % [weapon.reach, weapon.duration]
	elif id == "bow":
		detail_stats.text = "Arrow speed  45 m/s\nDraw  0.75 s"
	else:
		detail_stats.text = "Raise  0.16 s\nUse alongside your main weapon"

func _render_icon(id: String) -> Texture2D:
	# Render each original model once. No preview keeps a live 3D render loop.
	var viewport := SubViewport.new()
	viewport.name = id.capitalize() + "Preview"
	viewport.size = Vector2i(256, 192) if id in ["fists", "bow", "shield"] else Vector2i(512, 160)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.handle_input_locally = false
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.75
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.3
	viewport.add_child(sun)
	var model: Node3D = Visuals.weapon(id)
	viewport.add_child(model)
	model.basis = Basis(Vector3.BACK, deg_to_rad(-12)) * Basis(Vector3.UP, deg_to_rad(68))
	if id == "shield":
		model.rotation_degrees = Vector3(8, -20, -8)
	elif id == "bow":
		model.rotation_degrees = Vector3(0, -32, -25)
	elif id == "fists":
		model.rotation_degrees = Vector3(-12, -25, 10)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree():
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aspect: float = float(viewport.size.x) / viewport.size.y
	camera.size = maxf(bounds.size.y, bounds.size.x / aspect) * 1.18
	camera.near = 0.01
	camera.far = 12
	viewport.add_child(camera)
	camera.position = bounds.get_center() + Vector3(0, 0, -5)
	camera.look_at(bounds.get_center())
	camera.current = true
	return viewport.get_texture()
