extends Node3D

const Visuals = preload("res://scripts/visuals.gd")
const PATHS: Array[NodePath] = [
	^"Upper", ^"Upper/Helmet", ^"LeftLeg", ^"LeftLeg/Knee", ^"RightLeg", ^"RightLeg/Knee",
	^"Upper/LeftArm/Sleeve", ^"Upper/LeftArm/Pauldron", ^"Upper/LeftArm/Elbow",
	^"Upper/LeftArm/Bracer", ^"Upper/LeftArm/Palm", ^"Upper/LeftArm/Hand",
	^"Upper/RightArm/Sleeve", ^"Upper/RightArm/Pauldron", ^"Upper/RightArm/Elbow",
	^"Upper/RightArm/Bracer", ^"Upper/RightArm/Palm", ^"Upper/RightArm/Hand",
]

var model: Node3D
var joints: Array[Node3D] = []
var left_prop: Node3D
var right_prop: Node3D
var left_kind: String = ""
var right_kind: String = ""

static func capture(actor: Node) -> Dictionary:
	var player: bool = actor.has_method("bow_active")
	var source: Node3D = actor.get("body_model") if player else actor.get("model")
	if not is_instance_valid(source):
		return {}
	var transforms: Array[Transform3D] = []
	for path: NodePath in PATHS:
		transforms.append((source.get_node(path) as Node3D).transform)
	var main: String = ""
	var off: String = ""
	var bow_draw: float = 0.0
	var arrow_ready: bool = false
	var color := Color("ce3543")
	if player:
		color = Color("2455d8")
		if actor.body_knife.visible:
			main = "throwing_knife"
		elif actor.main_hand != "fists" and source.get_node("Upper/RightArm/Hand").visible:
			main = actor.main_hand
		if actor.active_slot == 2 and not actor.off_dropped:
			off = actor.off_hand
			if off == "bow":
				bow_draw = actor.bow_visual_draw()
				arrow_ready = actor.body_bow.get_node("NockedArrow").visible
	else:
		if actor.get("team_id") == 0:
			color = Color("277cce")
		if actor.get("role") == "archer":
			off = "bow"
			bow_draw = 1.0
			arrow_ready = true
		else:
			main = str(actor.get("weapon")) if actor.get("weapon") != null else "longsword"
			off = "shield" if actor.get("has_shield") == true else ""
	return {
		"frame": Engine.get_physics_frames(), "body": source.global_transform,
		"joints": transforms, "color": color, "main": main, "off": off,
		"draw": bow_draw, "arrow": arrow_ready,
	}

func build(pose: Dictionary) -> void:
	model = Visuals.humanoid(pose.color)
	add_child(model)
	for path: NodePath in PATHS:
		joints.append(model.get_node(path))
	apply(pose, pose, 0.0)

func apply(from: Dictionary, to: Dictionary, weight: float) -> void:
	model.global_transform = (from.body as Transform3D).interpolate_with(to.body, weight)
	var a: Array = from.joints
	var b: Array = to.joints
	for index: int in joints.size():
		joints[index].transform = (a[index] as Transform3D).interpolate_with(b[index], weight)
	var gear: Dictionary = from if weight < 0.5 else to
	if left_kind != gear.off:
		left_kind = gear.off
		left_prop = _replace_prop(left_prop, model.get_node("Upper/LeftArm/Hand"), left_kind)
	if right_kind != gear.main:
		right_kind = gear.main
		right_prop = _replace_prop(right_prop, model.get_node("Upper/RightArm/Hand"), right_kind)
	if left_kind == "bow":
		show_bow(lerpf(from.draw, to.draw, weight), gear.arrow)

func show_bow(draw: float, arrow_visible: bool) -> void:
	if left_kind != "bow":
		return
	left_prop.scale = Vector3(1, 1, Visuals.BOW_BODY_DEPTH)
	Visuals.pose_bow(left_prop, draw, arrow_visible, 1.0, Visuals.BOW_BODY_LATERAL_PULL)
	left_prop.get_node("DrawHand").hide()

func _replace_prop(previous: Node3D, mount: Node3D, kind: String) -> Node3D:
	if is_instance_valid(previous):
		mount.remove_child(previous)
		previous.queue_free()
	if kind.is_empty():
		return null
	var prop: Node3D = Visuals.weapon(kind)
	mount.add_child(prop)
	return prop
