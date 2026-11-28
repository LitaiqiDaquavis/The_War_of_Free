extends Control

const LIFETIME: float = 0.95
const RADIUS: float = 44.0
const MAX_HITS: int = 5

var camera: Camera3D
var hits: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func add_block(amount: float, bearing: Vector3) -> void:
	add_hit(amount, bearing, true)

func add_hit(amount: float, bearing: Vector3, blocked: bool = false) -> void:
	if bearing.is_zero_approx() or amount <= 0:
		return
	for index: int in range(hits.size() - 1, -1, -1):
		if bearing.dot(hits[index].bearing) > 0.96:
			hits.remove_at(index)
			break
	if hits.size() >= MAX_HITS:
		hits.pop_front()
	hits.append({"bearing": bearing, "amount": amount, "remaining": LIFETIME, "blocked": blocked})
	set_process(true)
	queue_redraw()

func clear() -> void:
	hits.clear()
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	for index: int in range(hits.size() - 1, -1, -1):
		hits[index].remaining -= delta
		if hits[index].remaining <= 0:
			hits.remove_at(index)
	if hits.is_empty():
		set_process(false)
	queue_redraw()

static func angle_for(bearing: Vector3, camera_right: Vector3) -> float:
	var right := Vector3(camera_right.x, 0, camera_right.z).normalized()
	var forward := Vector3(right.z, 0, -right.x)
	return atan2(-forward.dot(bearing), right.dot(bearing))

static func span_for(amount: float) -> float:
	return deg_to_rad(lerpf(10.0, 120.0, clampf(amount / 100.0, 0, 1)))

func _draw() -> void:
	if not is_instance_valid(camera):
		return
	for hit: Dictionary in hits:
		var angle: float = angle_for(hit.bearing, camera.global_basis.x)
		var half_span: float = span_for(hit.amount) * 0.5
		var alpha: float = smoothstep(0, 0.4, hit.remaining)
		var outline := Color(0.08, 0.09, 0.10, alpha * 0.9) if hit.blocked else Color(0.17, 0.02, 0.02, alpha * 0.9)
		var fill := Color(0.69, 0.73, 0.77, alpha) if hit.blocked else Color(1.0, 0.22, 0.14, alpha)
		draw_arc(size * 0.5, RADIUS, angle - half_span, angle + half_span, 32, outline, 7.0, true)
		draw_arc(size * 0.5, RADIUS, angle - half_span, angle + half_span, 32, fill, 4.0, true)
