extends RefCounted

const MAX_HEALTH: int = 100
const MELEE: int = 40
const KICK: int = 20
const SHIELD: int = 20

static func is_head_hit(actor: Node3D, point: Vector3) -> bool:
	if not actor.has_method("get_head_position"):
		return false
	# The character capsule extends ahead of the helmet. Use the helmet's
	# height band so its lower face is not misclassified as a torso hit.
	var offset: Vector3 = point - actor.get_head_position()
	return absf(offset.y) <= 0.23 and Vector2(offset.x, offset.z).length() <= 0.46

static func projectile_damage(kind: String, headshot: bool) -> int:
	if kind == "throwing_knife":
		return 100 if headshot else 60
	return 60 if headshot else 40
