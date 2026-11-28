extends Control

var health: float = 100.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_health(value: float) -> void:
	health = clampf(value, 0, 100)
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size / 2
	var radius: float = minf(size.x, size.y) * 0.46
	var width: float = radius * 0.16
	draw_circle(center, radius + width * 0.6, Color("080e17"))
	draw_arc(center, radius - width / 2, 0, TAU, 128, Color("344152"), width, true)
	if health > 0:
		draw_arc(center, radius - width / 2, -PI / 2, -PI / 2 + TAU * health / 100.0, 128, Color("ff4356") if health <= 30 else Color("45f394"), width, true)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(12, int(radius * 0.66))
	var text: String = str(int(ceil(health)))
	var extent: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center + Vector2(-extent.x / 2, (font.get_ascent(font_size) - font.get_descent(font_size)) / 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
