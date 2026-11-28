extends Node3D
## Original, collision-free battlefield dressing. The existing 120 x 120 floor
## supplies the only terrain collision. Call build() once after adding this node.
## Deterministic geometry / placement; no textures, packages or per-blade nodes.

const BLUE_FLAG := Vector3(-38.0, 0.0, -38.0)
const RED_FLAG := Vector3(38.0, 0.0, 38.0)
const GRASS_COUNT := 9000
const FLOWER_COUNT := 324
const CHUNKS_PER_AXIS := 6
const CHUNK_SIZE := 20.0
const SEED := 27112026

var _built := false
var _rng := RandomNumberGenerator.new()

func build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = SEED
	var grass_mesh := _make_grass_mesh()
	var flower_mesh := _make_flower_mesh()
	for z in range(CHUNKS_PER_AXIS):
		for x in range(CHUNKS_PER_AXIS):
			var center := Vector3(-50.0 + x * CHUNK_SIZE, 0.0, -50.0 + z * CHUNK_SIZE)
			_add_patch("Grass_%d_%d" % [x, z], center, grass_mesh, GRASS_COUNT / 36, false)
			_add_patch("Flowers_%d_%d" % [x, z], center, flower_mesh, FLOWER_COUNT / 36, true)
	_make_flag("BlueFlag", BLUE_FLAG, Color(0.045, 0.25, 0.92), 0.3)
	_make_flag("RedFlag", RED_FLAG, Color(0.88, 0.055, 0.075), -0.5)

## Slots use an expanding square spiral, not random respawn positions.
## At 2.8 m spacing, adjacent actors do not overlap. Slots 0..120 stay near
## their flag, inside the existing arena; team_id 0 = blue, 1 = red.
## Returns a transform in this battlefield's parent coordinate system.
## Keep this dressing node at identity, matching the existing floor.
func get_spawn_transform(team_id: int, slot: int) -> Transform3D:
	var anchor := BLUE_FLAG if team_id == 0 else RED_FLAG
	var inward := Vector3(-anchor.x, 0.0, -anchor.z).normalized()
	var side := Vector3(-inward.z, 0.0, inward.x)
	var index := maxi(slot, 0)
	var cell := Vector2i.ZERO
	if index > 0:
		var ring := int(ceil((sqrt(float(index + 1)) - 1.0) * 0.5))
		var edge := ring * 2
		var distance := (ring * 2 + 1) * (ring * 2 + 1) - 1 - index
		if distance < edge:
			cell = Vector2i(ring - distance, -ring)
		elif distance < edge * 2:
			cell = Vector2i(-ring, -ring + distance - edge)
		elif distance < edge * 3:
			cell = Vector2i(-ring + distance - edge * 2, ring)
		else:
			cell = Vector2i(ring, ring - (distance - edge * 3))
	var point := anchor + inward * (3.5 + cell.y * 2.8) + side * (cell.x * 2.8)
	point.y = 0.1
	return Transform3D(Basis.looking_at(Vector3(-point.x, 0.0, -point.z).normalized(), Vector3.UP), point)

func _plant_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.96
	return material

func _add_patch(label: String, center: Vector3, mesh: ArrayMesh, count: int, flower: bool) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = mesh
	instances.instance_count = count
	var colors: Array[Color] = [Color(1.0, 0.91, 0.59), Color(0.86, 0.73, 1.0), Color(1.0, 0.77, 0.83), Color(0.98, 0.98, 0.91)]
	for i in range(count):
		var point := Vector3(_rng.randf_range(-9.85, 9.85), 0.012, _rng.randf_range(-9.85, 9.85))
		# Leave a narrow clear circle around the pole, but never reduce counts.
		for anchor in [BLUE_FLAG, RED_FLAG]:
			var world_point: Vector3 = center + point
			if Vector2(world_point.x - anchor.x, world_point.z - anchor.z).length() < 1.15:
				point.x += 1.8 if point.x < 7.5 else -1.8
		var scale_y := _rng.randf_range(0.65, 1.45)
		var scale_xz := _rng.randf_range(0.7, 1.35)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(scale_xz, scale_y, scale_xz))
		instances.set_instance_transform(i, Transform3D(basis, point))
		if flower:
			instances.set_instance_color(i, colors[_rng.randi_range(0, colors.size() - 1)])
		else:
			instances.set_instance_color(i, Color(_rng.randf_range(0.67, 0.96), _rng.randf_range(0.8, 1.0), _rng.randf_range(0.57, 0.85)))
	var patch := MultiMeshInstance3D.new()
	patch.name = label
	patch.position = center
	patch.multimesh = instances
	# Explicit bounds avoid costly instance-bound updates, and allow patch culling.
	patch.custom_aabb = AABB(Vector3(-10.2, -0.05, -10.2), Vector3(20.4, 1.3, 20.4))
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for vertex in [a, b, c]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(vertex)

# A solid tetrahedral blade, not a crossed textured quad. Four real faces.
func _blade(surface: SurfaceTool, base: Vector3, tip: Vector3, width: float, angle: float, color: Color) -> void:
	var across := Vector3(cos(angle), 0.0, sin(angle)) * width
	var depth := Vector3(-sin(angle), 0.0, cos(angle)) * width * 0.48
	var a := base - across
	var b := base + across
	var c := base + depth
	_triangle(surface, a, tip, b, color)
	_triangle(surface, b, tip, c, color.lightened(0.07))
	_triangle(surface, c, tip, a, color.darkened(0.13))
	_triangle(surface, a, b, c, color.darkened(0.25))

func _make_grass_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var angle := float(i) * 2.39996
		var base := Vector3(cos(angle), 0.0, sin(angle)) * (0.045 + 0.012 * i)
		var tip := base + Vector3(cos(angle) * 0.10, 0.22 + i * 0.035, sin(angle) * 0.10)
		_blade(surface, base, tip, 0.028, angle, Color(0.31, 0.56, 0.13))
	surface.set_material(_plant_material())
	return surface.commit()

func _petal(surface: SurfaceTool, center: Vector3, radial: Vector3) -> void:
	var across := Vector3(-radial.z, 0.0, radial.x).normalized() * 0.043
	var a := center + radial * 0.22
	var b := center + radial * 0.62 + across
	var c := center + radial
	var d := center + radial * 0.62 - across
	var top := center + radial * 0.6 + Vector3.UP * 0.036
	var bottom := center + radial * 0.6 - Vector3.UP * 0.018
	for edge in [[a, b], [b, c], [c, d], [d, a]]:
		_triangle(surface, edge[0], top, edge[1], Color(1.0, 0.98, 0.95))
		_triangle(surface, edge[1], bottom, edge[0], Color(0.83, 0.81, 0.77))

func _make_flower_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A thin solid stem and two genuinely volumetric leaves.
	_blade(surface, Vector3.ZERO, Vector3(0.015, 0.55, 0.0), 0.016, 0.2, Color(0.22, 0.52, 0.17))
	_blade(surface, Vector3(0, 0.14, 0), Vector3(0.15, 0.26, 0.05), 0.033, 1.2, Color(0.27, 0.60, 0.20))
	_blade(surface, Vector3(0, 0.25, 0), Vector3(-0.13, 0.36, -0.04), 0.032, 1.5, Color(0.24, 0.55, 0.17))
	var head := Vector3(0.015, 0.55, 0.0)
	for i in range(5):
		var angle := i * TAU / 5.0
		_petal(surface, head, Vector3(cos(angle), 0.10, sin(angle)) * 0.14)
	# Golden raised heart, also a solid low-poly shape.
	_blade(surface, head - Vector3.UP * 0.005, head + Vector3.UP * 0.06, 0.046, 0.0, Color(0.98, 0.66, 0.12))
	surface.set_material(_plant_material())
	return surface.commit()

func _make_flag(label: String, location: Vector3, color: Color, yaw: float) -> void:
	var root := Node3D.new()
	root.name = label
	root.position = location
	root.rotation.y = yaw
	add_child(root)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.052
	cylinder.bottom_radius = 0.085
	cylinder.height = 5.3
	cylinder.radial_segments = 8
	pole.mesh = cylinder
	pole.position.y = 2.65
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.30, 0.24, 0.15)
	metal.metallic = 0.35
	metal.roughness = 0.65
	pole.material_override = metal
	root.add_child(pole)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(5):
		for column in range(12):
			var a := _flag_vertex(column, row)
			var b := _flag_vertex(column + 1, row)
			var c := _flag_vertex(column + 1, row + 1)
			var d := _flag_vertex(column, row + 1)
			_triangle(surface, a, b, c, color)
			_triangle(surface, a, c, d, color)
	var cloth := _plant_material()
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(cloth)
	var banner := MeshInstance3D.new()
	banner.name = "Cloth"
	banner.mesh = surface.commit()
	root.add_child(banner)
	# Intentionally no physics bodies or collision shapes, including the pole.

func _flag_vertex(column: int, row: int) -> Vector3:
	var u := column / 12.0
	var v := row / 5.0
	return Vector3(0.06 + u * 2.5, 5.1 - v * 1.5 - 0.16 * u * u, sin(u * TAU * 1.5 + v * 0.7) * 0.21 * u)
