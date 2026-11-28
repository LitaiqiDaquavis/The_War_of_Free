extends MarginContainer

signal main_selected(id: String)
signal off_selected(id: String)
signal start_requested
signal back_requested

const Visuals = preload("res://scripts/visuals.gd")
const MAIN_IDS: Array[String] = ["fists", "dagger", "longsword", "spear", "mace"]
const OFF_IDS: Array[String] = ["bow", "shield"]
const NAMES: Dictionary = {"fists": "Fists", "dagger": "Dagger", "longsword": "Longsword", "spear": "Spear", "mace": "Mace", "bow": "Bow", "shield": "Shield"}
const GOLD := Color("e5ba7c")
const INK := Color("101b25")

var main_hand: String = "longsword"
var off_hand: String = "shield"
var main_cards: Dictionary = {}
var off_cards: Dictionary = {}
var icons: Dictionary = {}
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
	style.set_border_width_all(2)
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
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 10)
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(choices)
	_label(choices, "01   MAIN HAND", 13, GOLD)
	var grid := GridContainer.new()
	grid.name = "MainWeapons"
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	choices.add_child(grid)
	for id: String in MAIN_IDS:
		main_cards[id] = _card(grid, id)
	_label(choices, "02   OFF HAND", 13, Color("9bcbb7"))
	var off_row := HBoxContainer.new()
	off_row.name = "OffHandItems"
	off_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	off_row.add_theme_constant_override("separation", 10)
	choices.add_child(off_row)
	for id: String in OFF_IDS:
		off_cards[id] = _card(off_row, id)
	column.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	column.add_child(footer)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(110, 52)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
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
	card.custom_minimum_size = Vector2(120, 180)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.toggle_mode = true
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
	var name_label := _label(top, str(NAMES[id]), 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.texture = icons[id]
	icon.custom_minimum_size.y = 58
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(icon)
	card.pressed.connect(_choose.bind(id))
	return card

func present(primary: String, secondary: String) -> void:
	main_hand = primary
	off_hand = secondary
	_refresh_selection()
	show()
	main_cards[main_hand].grab_focus()

func _choose(id: String) -> void:
	if id in MAIN_IDS:
		main_hand = id
		main_selected.emit(id)
	else:
		off_hand = id
		off_selected.emit(id)
	_refresh_selection()

func _refresh_selection() -> void:
	for id: String in main_cards:
		main_cards[id].set_pressed_no_signal(id == main_hand)
	for id: String in off_cards:
		off_cards[id].set_pressed_no_signal(id == off_hand)

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
