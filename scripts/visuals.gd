extends RefCounted

const ARM_LENGTHS := Vector2(0.3, 0.31)
const BOW_BODY_LATERAL_PULL: float = 0.27
const BOW_BODY_DEPTH: float = 1.42
const BOW_RELEASE_TIME: float = 0.1
const BOW_STRING_TIME: float = 0.15

# Original, low-poly geometry shared by both camera views.
static func material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metal
	result.roughness = 0.65
	return result

static func box(parent: Node3D, size: Vector3, position: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = position
	parent.add_child(node)
	return node

static func rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: Material, tip: bool = false) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0 if tip else radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 8
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = (from + to) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	parent.add_child(node)
	return node

static func weapon(kind: String) -> Node3D:
	var root := Node3D.new()
	var steel := material(Color("c2cbd1"), 0.4)
	var wood := material(Color("624734"))
	var leather := material(Color("2f2823"))
	var skin := material(Color("c49370"))
	match kind:
		"fists":
			root.add_child(gauntlet())
		"dagger", "longsword":
			var length: float = 0.42 if kind == "dagger" else 0.98
			rod(root, Vector3(0, 0, 0.12), Vector3(0, 0, -0.13), 0.035, leather)
			round_shape(root, Vector3(0.055, 0.055, 0.055), Vector3(0, 0, 0.14), steel)
			box(root, Vector3(0.28, 0.045, 0.05), Vector3(0, 0, -0.13), steel)
			blade(root, length, steel)
		"spear":
			rod(root, Vector3(0, 0, 0.65), Vector3(0, 0, -1.95), 0.025, wood)
			rod(root, Vector3(0, 0, -1.95), Vector3(0, 0, -2.3), 0.065, steel, true)
		"mace":
			rod(root, Vector3(0, 0, 0.12), Vector3(0, 0, -0.65), 0.035, wood)
			round_shape(root, Vector3.ONE * 0.13, Vector3(0, 0, -0.65), steel)
			for index in range(8):
				var angle: float = TAU * index / 8
				var direction := Vector3(cos(angle), sin(angle), 0)
				rod(root, Vector3(0, 0, -0.65) + direction * 0.1, Vector3(0, 0, -0.65) + direction * 0.24, 0.043, steel, true)
			rod(root, Vector3(0, 0, -0.74), Vector3(0, 0, -0.91), 0.045, steel, true)
		"shield":
			root.scale = Vector3.ONE * 1.25
			rod(root, Vector3(0, 0, -0.04), Vector3(0, 0, 0.04), 0.32, steel)
			rod(root, Vector3(0, 0, -0.055), Vector3(0, 0, -0.065), 0.285, wood)
			rod(root, Vector3(0, 0, 0.045), Vector3(0, 0, 0.055), 0.285, wood)
			rod(root, Vector3(0, -0.12, 0.1), Vector3(0, 0.12, 0.1), 0.025, leather)
			box(root, Vector3(0.045, 0.52, 0.025), Vector3(0, 0, -0.075), steel)
			box(root, Vector3(0.52, 0.045, 0.025), Vector3(0, 0, -0.075), steel)
		"bow":
			for id: String in ["Upper0", "Upper1", "Lower0", "Lower1", "String0", "String1"]:
				var segment: MeshInstance3D = rod(root, Vector3.ZERO, Vector3.UP, 0.004 if id.begins_with("String") else 0.025, leather if id.begins_with("String") else wood)
				segment.name = id
			var nocked: Node3D = weapon("arrow")
			nocked.name = "NockedArrow"
			root.add_child(nocked)
			var draw_hand: Node3D = gauntlet()
			draw_hand.name = "DrawHand"
			view_forearm(draw_hand, Vector3(-0.06, -0.04, 0.09), Vector3(-0.3, -0.18, 0.22))
			root.add_child(draw_hand)
			pose_bow(root, 0, true)
		"arrow":
			rod(root, Vector3(0, 0, 0.22), Vector3(0, 0, -0.5), 0.009, wood)
			rod(root, Vector3(0, 0, -0.5), Vector3(0, 0, -0.62), 0.025, steel, true)
			box(root, Vector3(0.08, 0.006, 0.12), Vector3(0, 0, 0.15), leather)
		"throwing_knife":
			# A short metal point: no arrow shaft or fletching.
			rod(root, Vector3(0, 0, 0.035), Vector3(0, 0, -0.205), 0.045, steel, true)
	return root

static func pose_rod(segment: Node3D, from: Vector3, to: Vector3) -> void:
	segment.position = (from + to) * 0.5
	segment.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	segment.scale = Vector3(1, from.distance_to(to), 1)

static func pose_bow(bow: Node3D, draw: float, arrow_visible: bool, nock_progress: float = 1.0, lateral_pull: float = 1.0) -> void:
	# Keep signed oscillation and >1 overpull, bounded only for mesh safety.
	draw = clampf(draw, -0.15, 1.15)
	var flex: float = draw
	var upper := Vector3(0, 0.55 - flex * 0.07, 0.13 + flex * 0.12)
	var lower := Vector3(0, -upper.y, upper.z)
	var nock: Vector3 = bow_nock(draw, lateral_pull)
	pose_rod(bow.get_node("Upper0"), Vector3.ZERO, Vector3(0, 0.3, -0.03 + flex * 0.06))
	pose_rod(bow.get_node("Upper1"), Vector3(0, 0.3, -0.03 + flex * 0.06), upper)
	pose_rod(bow.get_node("Lower0"), Vector3.ZERO, Vector3(0, -0.3, -0.03 + flex * 0.06))
	pose_rod(bow.get_node("Lower1"), Vector3(0, -0.3, -0.03 + flex * 0.06), lower)
	pose_rod(bow.get_node("String0"), upper, nock)
	pose_rod(bow.get_node("String1"), lower, nock)
	var arrow: Node3D = bow.get_node("NockedArrow")
	arrow.visible = arrow_visible
	var direction: Vector3 = -nock.normalized()
	arrow.quaternion = Quaternion(Vector3.FORWARD, direction)
	arrow.position = nock + direction * 0.22 + Vector3(0.1, -0.25, 0.2) * (1 - nock_progress)
	bow.get_node("DrawHand").position = nock + Vector3(0.1, 0.025, 0.06)
	bow.get_node("DrawHand").visible = arrow_visible and draw > 0.06

static func bow_nock(draw: float, lateral_pull: float = 1.0) -> Vector3:
	return Vector3((0.2 + draw * 0.6) * lateral_pull, 0, 0.14 + draw * 0.42)

static func bow_release_draw(t: float) -> float:
	return lerpf(1.0, 1.12, t / 0.4) if t < 0.4 else lerpf(1.12, 0.0, smoothstep(0.4, 1.0, t))

static func bow_string_draw(t: float) -> float:
	return sin(t * TAU * 2.0) * 0.12 * (1.0 - t)

static func bow_footing(stance: float, speed: float, draw: float, release_elapsed: float) -> float:
	var steady: float = clampf(draw, 0.0, 1.0)
	if release_elapsed < BOW_RELEASE_TIME + BOW_STRING_TIME:
		steady = 1 - smoothstep(BOW_RELEASE_TIME, BOW_RELEASE_TIME + BOW_STRING_TIME, release_elapsed)
	# Keep the left foot leading at full draw while retaining a short moving step.
	return stance * lerpf(1.0, 0.8 * steady, smoothstep(0.08, 3.0, speed))

static func pose_bow_stance(model: Node3D, stance: float, aim_pitch: float, footing: float, prone_blend: float = 0.0) -> void:
	var upper: Node3D = model.get_node("Upper")
	upper.rotation.y = -0.98 * stance
	var helmet: Node3D = upper.get_node("Helmet")
	helmet.rotation.y = -upper.rotation.y
	helmet.rotation.x = PI / 2 * prone_blend + clampf(aim_pitch, -0.92, 0.92) * stance * (1 - prone_blend)
	if footing <= 0:
		return
	var left_leg: Node3D = model.get_node("LeftLeg")
	var right_leg: Node3D = model.get_node("RightLeg")
	left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.28, footing)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, -0.25, footing)
	left_leg.get_node("Knee").rotation.x = lerpf(left_leg.get_node("Knee").rotation.x, 0.08, footing)
	right_leg.get_node("Knee").rotation.x = lerpf(right_leg.get_node("Knee").rotation.x, 0.04, footing)
	model.position.y -= 0.026 * footing

static func pose_body_bow(bow: Node3D, stance: float, aim_pitch: float, draw: float, arrow_visible: bool, nock_progress: float, arm_swing: float, use_draw_hand: bool = true) -> void:
	# One hand carries the lowered bow. The other only moves to the string on raising it.
	var left_arm: Node3D = bow.get_parent().get_parent()
	var upper: Node3D = left_arm.get_parent()
	var pitch: float = clampf(aim_pitch, -0.92, 0.92)
	var aim_pivot := Vector3(-0.10, 0.52, -0.22)
	var aim_grip: Vector3 = aim_pivot + Basis(Vector3.RIGHT, pitch) * (Vector3(-0.088, 0.75, -0.84) - aim_pivot)
	var lowered_grip := Vector3(-0.40, -0.05 + absf(arm_swing) * 0.035, -0.17 - arm_swing * 0.10)
	var grip: Vector3 = lowered_grip.lerp(aim_grip, stance)
	var rotation_model: Vector3 = Vector3(0.32 + arm_swing * 0.11, 0.05, 0.12).lerp(Vector3(pitch, 0, 0), stance)
	var upper_inverse: Basis = upper.basis.inverse()
	var wrist: Vector3 = (upper_inverse * Basis.from_euler(rotation_model)).get_euler()
	var left_target: Vector3 = upper_inverse * grip
	var reach_fraction: float = lerpf(0.985, 0.9999, stance)
	var arm_extension: float = maxf(1.0, left_arm.position.distance_to(left_target) / ((ARM_LENGTHS.x + ARM_LENGTHS.y) * reach_fraction))
	pose_arm(left_arm, left_target, wrist, -1.0, ARM_LENGTHS * arm_extension, upper_inverse * Vector3(-0.25, -1, 0.35), 1.0, reach_fraction)
	bow.scale = Vector3(1, 1, BOW_BODY_DEPTH)
	pose_bow(bow, draw, arrow_visible, nock_progress, BOW_BODY_LATERAL_PULL)
	bow.get_node("DrawHand").hide()
	if not use_draw_hand:
		return
	var right_arm: Node3D = upper.get_node("RightArm")
	var nock_offset: Vector3 = Vector3(0.10, -0.25, 0.20) * (1 - nock_progress)
	var fingers: Vector3 = bow_nock(draw, BOW_BODY_LATERAL_PULL) + nock_offset + Vector3(0.025, 0.012, 0.028)
	var string_hand: Vector3 = upper.to_local(bow.to_global(fingers))
	var free_hand := Vector3(0.31, -0.08 + absf(arm_swing) * 0.04, -0.10 + arm_swing * 0.16)
	var draw_grip: Vector3 = (upper_inverse * free_hand).lerp(string_hand, stance)
	var draw_elbow: Vector3 = Vector3(0.12, -1.0, 0.65).lerp(Vector3(0.82, 0.43, 1.0), clampf(draw, 0, 1) * stance)
	var draw_wrist: Vector3 = Vector3.ZERO.lerp(wrist.lerp(Vector3(0, 1.15, -0.18), draw), stance)
	pose_arm(right_arm, draw_grip, draw_wrist, 1.0, ARM_LENGTHS, upper_inverse * draw_elbow)

static func gauntlet() -> Node3D:
	var root := Node3D.new()
	var leather := material(Color("604030"))
	var steel := material(Color("c2cbd1"), 0.4)
	round_shape(root, Vector3(0.075, 0.06, 0.11), Vector3(0, 0, -0.035), leather)
	shell(root, Vector3(0.135, 0.045, 0.16), Vector3(0, 0.05, -0.035), steel)
	for index in range(3):
		shell(root, Vector3(0.035, 0.035, 0.065), Vector3((index - 1) * 0.04, 0.04, -0.12), steel)
	return root

static func view_forearm(parent: Node3D, from: Vector3, to: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Forearm"
	parent.add_child(root)
	var steel := material(Color("c2cbd1"), 0.4)
	var cloth := material(Color("2455d8"))
	rod(root, Vector3.ZERO, Vector3.UP, 0.045, material(Color("604030"))).name = "WristLink"
	rod(root, Vector3.ZERO, Vector3.UP, 0.055, cloth).name = "Sleeve"
	shell(root, Vector3(0.13, 0.18, 0.13), Vector3.ZERO, steel).name = "Bracer"
	pose_view_forearm(root, from, to)
	return root

static func pose_view_forearm(arm: Node3D, from: Vector3, to: Vector3) -> void:
	pose_rod(arm.get_node("WristLink"), Vector3(signf(from.x) * 0.015, -0.015, 0.03), from + Vector3(0, 0, 0.025))
	pose_rod(arm.get_node("Sleeve"), from, to)
	var plate: Node3D = arm.get_node("Bracer")
	plate.position = from.lerp(to, minf(0.35, 0.14 / from.distance_to(to)))
	plate.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	plate.scale = Vector3(1, minf(from.distance_to(to) * 0.62, 0.28) / 0.18, 1)
	arm.set_meta("entry", to)

static func pose_weapon_arm(arm: Node3D, target: Vector3, wrist: Vector3, side: float) -> void:
	pose_arm(arm, target, wrist, side, ARM_LENGTHS, Vector3(side * 0.12, -1, 0.65))

static func pose_arm(arm: Node3D, target: Vector3, wrist: Vector3, side: float, lengths: Vector2 = Vector2(0.3, 0.31), pole_hint: Vector3 = Vector3.ZERO, width: float = 1.0, reach_fraction: float = 0.985) -> void:
	# Analytic two-link elbow. The wrist is specified in torso coordinates.
	arm.rotation = Vector3.ZERO
	var reach: Vector3 = target - arm.position
	var distance: float = clampf(reach.length(), 0.08, (lengths.x + lengths.y) * reach_fraction)
	var axis: Vector3 = reach.normalized()
	var pole: Vector3 = Vector3(side * 0.8, -0.2, 0.65) if pole_hint == Vector3.ZERO else pole_hint
	var bend: Vector3 = (pole - axis * pole.dot(axis)).normalized()
	var upper_length: float = lengths.x
	var lower_length: float = lengths.y
	var along: float = (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2 * distance)
	var elbow: Vector3 = axis * along + bend * sqrt(maxf(0, upper_length * upper_length - along * along))
	var hand: Vector3 = axis * distance
	var sleeve: Node3D = arm.get_node("Sleeve")
	sleeve.position = elbow * 0.5
	sleeve.quaternion = Quaternion(Vector3.UP, elbow.normalized())
	sleeve.scale = Vector3(width, elbow.length() / 0.4, width)
	var bracer: Node3D = arm.get_node("Bracer")
	bracer.position = (elbow + hand) * 0.5
	bracer.quaternion = Quaternion(Vector3.UP, (hand - elbow).normalized())
	bracer.scale = Vector3(width, hand.distance_to(elbow) / 0.22, width)
	arm.get_node("Pauldron").scale = Vector3.ONE * width
	arm.get_node("Elbow").scale = Vector3.ONE * 0.075 * width
	arm.get_node("Palm").scale = Vector3.ONE * width
	arm.get_node("Elbow").position = elbow
	arm.get_node("Palm").position = hand
	arm.get_node("Palm").rotation = wrist
	arm.get_node("Hand").position = hand
	arm.get_node("Hand").rotation = wrist

static func round_shape(parent: Node3D, radii: Vector3, position: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.scale = radii
	node.position = position
	node.material_override = mat
	parent.add_child(node)
	return node

static func capsule(parent: Node3D, radius: float, height: float, position: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.material_override = mat
	parent.add_child(node)
	return node

static func face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outside: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.dot(outside) < 0:
		var swap: Vector3 = b
		b = c
		c = swap
		normal = -normal
	# Godot uses clockwise front faces. Keep an explicit outward flat normal.
	for vertex: Vector3 in [c, b, a]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)

static func finish_mesh(parent: Node3D, surface: SurfaceTool, position: Vector3, mat: Material) -> MeshInstance3D:
	surface.index()
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	node.material_override = mat
	node.position = position
	parent.add_child(node)
	return node

static func shell(parent: Node3D, size: Vector3, position: Vector3, mat: Material, bottom: float = 0.8, top: float = 0.8) -> MeshInstance3D:
	# Bevelled octagonal plate, built as one flat-shaded mesh rather than a sphere.
	var outline: Array[Vector2] = [Vector2(-0.65, -1), Vector2(0.65, -1), Vector2(1, -0.55), Vector2(1, 0.55), Vector2(0.65, 1), Vector2(-0.65, 1), Vector2(-1, 0.55), Vector2(-1, -0.55)]
	var levels: Array[Vector2] = [Vector2(-0.5, bottom), Vector2(-0.32, 1), Vector2(0.28, 1), Vector2(0.5, top)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for level: Vector2 in levels:
		var ring := PackedVector3Array()
		for point: Vector2 in outline:
			ring.append(Vector3(point.x * size.x * 0.5 * level.y, level.x * size.y, point.y * size.z * 0.5 * level.y))
		rings.append(ring)
	for layer in range(3):
		for index in range(8):
			var next: int = (index + 1) % 8
			var outside := Vector3(outline[index].x + outline[next].x, 0, outline[index].y + outline[next].y)
			face(surface, rings[layer][index], rings[layer][next], rings[layer + 1][next], outside)
			face(surface, rings[layer][index], rings[layer + 1][next], rings[layer + 1][index], outside)
	for index in range(8):
		face(surface, Vector3(0, -size.y * 0.5, 0), rings[0][index], rings[0][(index + 1) % 8], Vector3.DOWN)
		face(surface, Vector3(0, size.y * 0.5, 0), rings[3][index], rings[3][(index + 1) % 8], Vector3.UP)
	return finish_mesh(parent, surface, position, mat)

static func cloth_panel(parent: Node3D, points: Array[Vector3], mat: Material, direction: Vector3) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	for point: Vector3 in points:
		center += point / points.size()
	center += direction * 0.018
	for index in range(points.size()):
		face(surface, center, points[index], points[(index + 1) % points.size()], direction)
	return finish_mesh(parent, surface, Vector3.ZERO, mat)

static func blade(parent: Node3D, length: float, mat: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cross_section: Array[Vector2] = [Vector2(-0.055, 0), Vector2(0, 0.018), Vector2(0.055, 0), Vector2(0, -0.018)]
	for index in range(4):
		var a := Vector3(cross_section[index].x, cross_section[index].y, -0.14)
		var b := Vector3(cross_section[(index + 1) % 4].x, cross_section[(index + 1) % 4].y, -0.14)
		var c := Vector3(b.x * 0.68, b.y, -length)
		var d := Vector3(a.x * 0.68, a.y, -length)
		var outside := Vector3(a.x + b.x, a.y + b.y, 0)
		face(surface, a, b, c, outside)
		face(surface, a, c, d, outside)
		face(surface, d, c, Vector3(0, 0, -length - 0.2), outside)
	finish_mesh(parent, surface, Vector3.ZERO, mat)

static func humanoid(color: Color) -> Node3D:
	var root := Node3D.new()
	var cloth := material(color)
	var dark := material(Color("242a32"))
	var trousers := material(color.darkened(0.28))
	var leather := material(Color("604030"))
	var steel := material(Color("c2cbd1"), 0.4)
	var trim := material(Color("b89c62"), 0.3)
	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "RightLeg" if side > 0 else "LeftLeg"
		leg.position = Vector3(side * 0.15, 0.82, 0)
		root.add_child(leg)
		capsule(leg, 0.105, 0.43, Vector3(0, -0.16, 0), trousers)
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position.y = -0.38
		leg.add_child(knee)
		capsule(knee, 0.09, 0.38, Vector3(0, -0.15, 0), trousers)
		shell(knee, Vector3(0.23, 0.16, 0.4), Vector3(0, -0.35, -0.07), leather, 0.95, 0.72)
		var greave := shell(knee, Vector3(0.23, 0.34, 0.25), Vector3(0, -0.15, 0), leather, 0.85, 1.0)
		greave.name = "Greave" + ("Right" if side > 0 else "Left")
		shell(knee, Vector3(0.235, 0.16, 0.12), Vector3(0, 0.01, -0.09), steel)
	var upper := Node3D.new()
	upper.name = "Upper"
	upper.position.y = 0.9
	root.add_child(upper)
	shell(upper, Vector3(0.51, 0.59, 0.32), Vector3(0, 0.28, 0), cloth)
	var breastplate := shell(upper, Vector3(0.59, 0.55, 0.39), Vector3(0, 0.32, 0), steel, 0.72, 0.85)
	breastplate.name = "Breastplate"
	shell(upper, Vector3(0.58, 0.075, 0.375), Vector3(0, 0.025, 0), leather, 0.95, 0.95)
	box(upper, Vector3(0.085, 0.065, 0.025), Vector3(0, 0.025, -0.2), trim)
	capsule(upper, 0.085, 0.17, Vector3(0, 0.65, 0), dark).name = "Neck"
	var helmet := Node3D.new()
	helmet.name = "Helmet"
	helmet.position = Vector3(0, 0.84, 0)
	upper.add_child(helmet)
	shell(helmet, Vector3(0.36, 0.43, 0.35), Vector3.ZERO, steel, 0.82, 0.72)
	box(helmet, Vector3(0.255, 0.026, 0.012), Vector3(0, 0.02, -0.179), dark)
	var collar := TorusMesh.new()
	collar.inner_radius = 0.085
	collar.outer_radius = 0.18
	collar.rings = 12
	collar.ring_segments = 6
	var scarf := MeshInstance3D.new()
	scarf.name = "Scarf"
	scarf.mesh = collar
	scarf.material_override = cloth
	scarf.position = Vector3(0, 0.62, 0)
	upper.add_child(scarf)
	cloth_panel(upper, [Vector3(-0.18, 0.6, -0.17), Vector3(0.18, 0.6, -0.17), Vector3(0, 0.38, -0.211)], cloth, Vector3.FORWARD).name = "ScarfFront"
	for side: float in [-1.0, 1.0]:
		for front: float in [-1.0, 1.0]:
			cloth_panel(upper, [Vector3(side * 0.015, -0.01, front * 0.19), Vector3(side * 0.27, -0.01, front * 0.19), Vector3(side * 0.34, -0.37, front * 0.23), Vector3(side * 0.035, -0.32, front * 0.23)], cloth, Vector3(0, 0, front))
	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "RightArm" if side > 0 else "LeftArm"
		arm.position = Vector3(side * 0.37, 0.47, 0)
		upper.add_child(arm)
		capsule(arm, 0.1, 0.4, Vector3(0, -0.17, 0), cloth).name = "Sleeve"
		var shoulder := shell(arm, Vector3(0.31, 0.19, 0.34), Vector3(0, 0.01, 0), steel, 0.9, 0.58)
		shoulder.name = "Pauldron"
		shell(arm, Vector3(0.21, 0.22, 0.22), Vector3(0, -0.29, 0), steel, 0.8, 1.0).name = "Bracer"
		round_shape(arm, Vector3.ONE * 0.075, Vector3(0, -0.21, 0), leather).name = "Elbow"
		var glove: Node3D = gauntlet()
		glove.name = "Palm"
		glove.position = Vector3(0, -0.42, -0.04)
		arm.add_child(glove)
		var hand := Node3D.new()
		hand.name = "Hand"
		hand.position = Vector3(0, -0.4, -0.12)
		arm.add_child(hand)
	return root
