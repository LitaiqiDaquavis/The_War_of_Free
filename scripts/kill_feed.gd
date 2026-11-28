extends Control

const WeaponIcon = preload("res://scripts/kill_weapon_icon.gd")
const MAX_ENTRIES: int = 6
const LIFETIME: float = 8.0
const TEAM_COLORS := [Color("66b8ff"), Color("ff707b")]
var entries: Array[Dictionary] = []
var rows: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -336
	offset_right = -18
	offset_top = 18
	offset_bottom = 250
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 5)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)

func clear() -> void:
	entries.clear()
	_rebuild()

func add_kill(source: Dictionary, victim: Dictionary) -> void:
	if source.is_empty() or victim.is_empty():
		return
	entries.append({"killer": source.duplicate(true), "victim": victim.duplicate(true), "remaining": LIFETIME})
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	_rebuild()

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	var changed: bool = false
	for entry: Dictionary in entries:
		entry.remaining -= delta
	while not entries.is_empty() and entries[0].remaining <= 0:
		entries.pop_front()
		changed = true
	if changed:
		_rebuild()

func _actor_label(identity: Dictionary) -> Label:
	var label := Label.new()
	label.text = identity.get("class", "Knight")
	label.custom_minimum_size.x = 88
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", TEAM_COLORS[clampi(int(identity.get("team", 1)), 0, 1)])
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _rebuild() -> void:
	if not is_instance_valid(rows):
		return
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	# Chronological stacking: first retained kill at top, new kills below.
	for entry: Dictionary in entries:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.025, 0.035, 0.055, 0.82)
		style.set_corner_radius_all(4)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 6)
		panel.add_child(line)
		line.add_child(_actor_label(entry.killer))
		var icon := WeaponIcon.new()
		icon.kind = entry.killer.get("weapon", "fists")
		line.add_child(icon)
		line.add_child(_actor_label(entry.victim))
		rows.add_child(panel)
