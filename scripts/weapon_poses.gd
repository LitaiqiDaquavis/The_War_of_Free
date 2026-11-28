extends RefCounted

const Timing = preload("res://scripts/attack_timing.gd")
const SPEAR_SWITCH_TIME: float = 0.3

static func idle_weapon_hand(hand: Vector3, arm_swing: float, kind: String, spear_carry_weight: float) -> Vector3:
	var swing_weight: float = 1 - spear_carry_weight
	hand.z += arm_swing * (0.15 if kind == "fists" else 0.08) * swing_weight
	hand.y += absf(arm_swing) * 0.045 * swing_weight
	return hand

static func off_hand(arm_swing: float, has_item: bool, guard_weight: float) -> Vector3:
	var hand := Vector3(-0.31, -0.08, -0.10)
	hand.z -= arm_swing * (0.10 if has_item else 0.16)
	hand.y += absf(arm_swing) * 0.04
	return hand.lerp(Vector3(-0.22, 0.43, -0.35), guard_weight)

# Hand-authored key poses in camera space and in the torso's local space.
# Interpolation shares the same attack phase in first and third person.
static func sample(kind: String, phase: float, attacking: bool, reverse_grip: bool = false, direction: int = 1, heavy: bool = false, chained: bool = false) -> Dictionary:
	var rest := {"position": Vector3(0.82, -0.38, -0.65), "rotation": Vector3(1.5, 0, 0), "hand": Vector3(0.31, -0.04, -0.14), "wrist": Vector3(1.5, 0, 0)}
	var wind: Dictionary = rest.duplicate()
	var strike: Dictionary = rest.duplicate()
	match kind:
		"fists":
			rest.rotation = Vector3.ZERO
			rest.wrist = Vector3.ZERO
			wind = rest.duplicate()
			wind.position = Vector3(0.58, -0.34, -0.48)
			strike = {"position": Vector3(0, 0, -0.94), "rotation": Vector3.ZERO, "hand": Vector3(0.05, 0.62, -0.43), "wrist": Vector3.ZERO}
		"dagger", "longsword":
			if kind == "dagger":
				rest.position.y = -0.34
			wind = {"position": Vector3(0.58, -0.03, -0.58), "rotation": Vector3(1.1, -0.35, -0.1), "hand": Vector3(0.52, 0.36, -0.16), "wrist": Vector3(1.1, -0.35, -0.1)}
			strike = {"position": Vector3(-0.3, -0.22, -0.74), "rotation": Vector3(0.12, 1.1, -0.45), "hand": Vector3(-0.02, 0.3, -0.42), "wrist": Vector3(0.12, 1.1, -0.45)}
		"mace":
			wind = {"position": Vector3(0.33, 0.08, -0.6), "rotation": Vector3(1.7, 0, -0.08), "hand": Vector3(0.4, 0.68, -0.12), "wrist": Vector3(1.7, 0, -0.08)}
			strike = {"position": Vector3(0.08, -0.48, -0.85), "rotation": Vector3(-0.3, 0, 0), "hand": Vector3(0.16, 0.06, -0.42), "wrist": Vector3(-0.3, 0, 0)}
		"spear":
			wind = {"position": Vector3(0.55, -0.28, -0.66), "rotation": Vector3.ZERO, "hand": Vector3(0.36, 0.18, -0.28), "wrist": Vector3.ZERO}
			strike = {"position": Vector3(0.5, -0.28, -0.98), "rotation": Vector3.ZERO, "hand": Vector3(0.36, 0.13, -0.5), "wrist": Vector3.ZERO}
	if kind == "dagger" and reverse_grip:
		rest.position = Vector3(0.78, 0.06, -0.82)
		rest.hand = Vector3(0.36, 0.28, -0.16)
		rest.rotation = Vector3(-1.5, 0, 0)
		rest.wrist = rest.rotation
		wind = {"position": Vector3(0.34, 0.17, -0.54), "rotation": Vector3(-1.55, 0, -0.1), "hand": Vector3(0.35, 0.65, -0.2), "wrist": Vector3(-1.55, 0, -0.1)}
		strike = {"position": Vector3(0.03, -0.38, -0.82), "rotation": Vector3(-1.1, 0, 0), "hand": Vector3(0.12, 0.12, -0.46), "wrist": Vector3(-1.1, 0, 0)}
	if kind == "mace" and chained and not heavy:
		wind = {"position": Vector3(0.53, -0.12, -0.65), "rotation": Vector3(0.9, -0.55, 0), "hand": Vector3(0.47, 0.4, -0.21), "wrist": Vector3(0.9, -0.55, 0)}
		strike = {"position": Vector3(-0.3, -0.4, -0.82), "rotation": Vector3(-0.22, 1.0, -0.4), "hand": Vector3(-0.02, 0.2, -0.45), "wrist": Vector3(-0.22, 1.0, -0.4)}
	if direction < 0 and kind in ["dagger", "longsword", "mace"] and not reverse_grip and not heavy:
		for key: String in ["position", "hand"]:
			wind[key].x *= -1
			strike[key].x *= -1
		for key: String in ["rotation", "wrist"]:
			wind[key].y *= -1
			wind[key].z *= -1
			strike[key].y *= -1
			strike[key].z *= -1
	if heavy:
		match kind:
			"fists":
				wind = {"position": Vector3(0.65, 0.03, -0.35), "rotation": Vector3(0, 0, -1.0), "hand": Vector3(0.43, 0.56, 0), "wrist": Vector3(0, 0, -1.0)}
				strike = {"position": Vector3(0.18, -0.08, -0.48), "rotation": Vector3(0, 0.35, -1.3), "hand": Vector3(0.15, 0.48, -0.05), "wrist": Vector3(0, 0.35, -1.3)}
			"spear":
				wind.position.z = -0.52
				wind.hand.z = -0.16
				strike.position = Vector3(0.35, -0.25, -1.25)
				strike.hand = Vector3(0.28, 0.25, -0.52)
			_:
				wind.position.y += 0.14
				wind.hand.y += 0.08
				strike.position.z -= 0.12
	if not attacking:
		return rest
	var peak: float = hit_phase(kind, heavy)
	var ready: float = 0.42 if heavy else (0.25 if kind == "spear" else 0.18)
	if phase < ready:
		return blend(rest, wind, smoothstep(0, ready * 0.8 if kind == "spear" else ready, phase))
	if phase <= peak:
		return blend(wind, strike, smoothstep(ready, peak, phase))
	if kind in ["dagger", "longsword", "mace"] and not reverse_grip and not heavy:
		var follow: Dictionary = strike.duplicate()
		follow.position.x = -0.5 * direction
		follow.hand.x = -0.12 * direction
		if phase < 0.7:
			return blend(strike, follow, smoothstep(peak, 0.7, phase))
		return blend(follow, rest, smoothstep(0.7, 1.0, phase))
	return blend(strike, rest, smoothstep(peak, 1.0, phase))

static func spear_carry() -> Dictionary:
	var across_chest := Vector3(0.24, 1.32, 0.04)
	return {
		"position": Vector3(-0.13, -0.51, -0.62),
		"rotation": Vector3(0.66, 1.36, 0.0),
		"hand": Vector3(0.19, 0.38, -0.30),
		"wrist": across_chest
	}

static func hit_phase(kind: String, heavy: bool = false) -> float:
	return Timing.contact_pose(kind, heavy)

static func shield_bash(elapsed: float, initial: Dictionary = {}) -> Dictionary:
	var times: Vector3 = Timing.durations("shield")
	var rest := {"position": Vector3(-0.28, -0.12, -0.75), "rotation": Vector3(0, 0.05, 0), "hand": Vector3(-0.22, 0.43, -0.35), "wrist": Vector3(0, 0.05, 0)}
	var pull := {"position": Vector3(-0.4, -0.09, -0.49), "rotation": Vector3(0.04, -0.5, -0.2), "hand": Vector3(-0.32, 0.45, -0.19), "wrist": Vector3(0.04, -0.5, -0.2)}
	var push := {"position": Vector3(-0.12, -0.04, -1.08), "rotation": Vector3(-0.05, 0.5, 0.13), "hand": Vector3(-0.06, 0.5, -0.56), "wrist": Vector3(-0.05, 0.5, 0.13)}
	if elapsed < times.x:
		return blend(rest if initial.is_empty() else initial, pull, smoothstep(0, times.x, elapsed))
	if elapsed < times.x + times.y:
		return blend(pull, push, smoothstep(times.x, times.x + times.y, elapsed))
	return blend(push, rest, smoothstep(times.x + times.y, times.x + times.y + times.z, elapsed))

static func blend(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	var result: Dictionary = {}
	for key: String in from:
		result[key] = (from[key] as Vector3).lerp(to[key], weight)
	return result
