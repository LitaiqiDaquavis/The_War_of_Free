extends RefCounted

# Seconds: wind-up, active strike, recovery. Shared by player, bot and poses.
const LIGHT: Dictionary = {
	"longsword": Vector3(0.36, 0.47, 0.17),
	"spear": Vector3(0.25, 0.3, 0.3),
	"dagger": Vector3(0.3, 0.35, 0.55),
	"mace": Vector3(0.32, 0.65, 0.55),
	"fists": Vector3(0.2, 0.3, 0.3),
	"kick": Vector3(0.15, 0.3, 0.35),
	"shield": Vector3(0.3, 0.15, 0.75)
}
const HEAVY: Dictionary = {
	"longsword": Vector3(0.65, 0.25, 0.5),
	"spear": Vector3(0.6, 0.2, 0.6),
	"dagger": Vector3(0.6, 0.7, 0.3),
	"mace": Vector3(0.55, 0.28, 0.2),
	"fists": Vector3(0.55, 0.4, 0.4)
}

static func durations(kind: String, heavy: bool = false) -> Vector3:
	return HEAVY[kind] if heavy and HEAVY.has(kind) else LIGHT[kind]

static func total(kind: String, heavy: bool = false) -> float:
	var times: Vector3 = durations(kind, heavy)
	return times.x + times.y + times.z

static func stage(kind: String, elapsed: float, heavy: bool = false) -> String:
	var times: Vector3 = durations(kind, heavy)
	if elapsed + 0.000001 < times.x:
		return "windup"
	if elapsed + 0.000001 < times.x + times.y:
		return "active"
	if elapsed + 0.000001 < times.x + times.y + times.z:
		return "cooldown"
	return "done"

static func ready_pose(kind: String, heavy: bool = false) -> float:
	return 0.42 if heavy else (0.25 if kind == "spear" else 0.18)

static func contact_pose(kind: String, heavy: bool = false) -> float:
	return 0.64 if heavy else (0.42 if kind == "fists" else (0.52 if kind == "spear" else (0.5 if kind == "mace" else 0.48)))

static func pose_phase(kind: String, elapsed: float, heavy: bool = false) -> float:
	var times: Vector3 = durations(kind, heavy)
	var ready: float = ready_pose(kind, heavy)
	var contact: float = contact_pose(kind, heavy)
	if elapsed < times.x:
		return lerpf(0, ready, clampf(elapsed / times.x, 0, 1))
	if elapsed < times.x + times.y:
		return lerpf(ready, contact, clampf((elapsed - times.x) / times.y, 0, 1))
	return lerpf(contact, 1, clampf((elapsed - times.x - times.y) / times.z, 0, 1))
