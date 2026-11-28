extends Control
# All silhouettes share a left grip / right business end convention.
const SUPPORTED := ["arrow", "bow", "throwing_knife", "dagger", "longsword", "spear", "mace", "fists", "kick", "shield"]
const BUSINESS_END := Vector2.RIGHT
var kind: String = "longsword"
const STEEL := Color("e3edf3")
const WOOD := Color("c69b66")

func _ready() -> void:
	custom_minimum_size = Vector2(68, 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = kind.capitalize().replace("_", " ")

func poly(points: Array, color: Color = STEEL) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)

func _draw() -> void:
	match kind:
		"arrow", "bow":
			draw_arc(Vector2(18, 14), 11, -PI / 2, PI / 2, 20, WOOD, 2, true)
			draw_line(Vector2(18, 3), Vector2(18, 25), STEEL, 1, true)
			draw_line(Vector2(5, 14), Vector2(55, 14), WOOD, 2, true)
			poly(business_shape(kind))
			poly([Vector2(5, 8), Vector2(14, 13), Vector2(5, 13)], WOOD)
		"spear":
			draw_line(Vector2(5, 14), Vector2(48, 14), WOOD, 4, true)
			poly(business_shape(kind))
		"longsword", "dagger", "throwing_knife":
			draw_line(Vector2(7, 14), Vector2(22, 14), WOOD, 5, true)
			draw_line(Vector2(23, 5), Vector2(23, 23), WOOD, 3, true)
			var tip: float = 64 if kind == "longsword" else 52
			poly(business_shape(kind))
			draw_line(Vector2(26, 14), Vector2(tip - 7, 14), Color("8299ad"), 1, true)
		"mace":
			draw_line(Vector2(6, 14), Vector2(49, 14), WOOD, 5, true)
			poly(business_shape(kind))
		"fists":
			draw_style_box(_wrist(), Rect2(8, 10, 30, 12))
			poly(business_shape(kind))
			for y: int in [10, 14, 18]:
				draw_line(Vector2(56, y), Vector2(63, y), Color("8299ad"), 1, true)
		"kick":
			poly(business_shape(kind), WOOD)
			draw_line(Vector2(18, 25), Vector2(64, 25), STEEL, 2, true)
		"shield":
			# Side-on shield bash: forearm left, convex steel face / boss right.
			draw_line(Vector2(9, 14), Vector2(41, 14), WOOD, 6, true)
			poly([Vector2(43, 2), Vector2(55, 6), Vector2(61, 14), Vector2(55, 22), Vector2(43, 26)], Color("91a8bb"))
			poly(business_shape(kind))

func _wrist() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WOOD
	return style

# Shared by the actual renderer and orientation tests (not just a direction flag).
static func business_shape(weapon: String) -> Array:
	match weapon:
		"arrow", "bow": return [Vector2(53, 9), Vector2(64, 14), Vector2(53, 19)]
		"spear": return [Vector2(43, 9), Vector2(65, 14), Vector2(43, 19), Vector2(47, 14)]
		"longsword", "dagger", "throwing_knife":
			var tip: float = 64 if weapon == "longsword" else 52
			return [Vector2(25, 10), Vector2(tip - 10, 10), Vector2(tip, 14), Vector2(tip - 10, 18), Vector2(25, 18)]
		"mace": return [Vector2(43, 7), Vector2(48, 3), Vector2(53, 7), Vector2(58, 4), Vector2(61, 10), Vector2(66, 14), Vector2(61, 18), Vector2(58, 24), Vector2(53, 21), Vector2(48, 25), Vector2(43, 21)]
		"fists": return [Vector2(33, 8), Vector2(46, 5), Vector2(59, 7), Vector2(63, 11), Vector2(63, 20), Vector2(48, 23), Vector2(35, 20)]
		"kick": return [Vector2(19, 3), Vector2(33, 3), Vector2(33, 15), Vector2(56, 15), Vector2(64, 20), Vector2(64, 25), Vector2(17, 25)]
		"shield": return [Vector2(53, 10), Vector2(65, 14), Vector2(53, 18)]
	return []
