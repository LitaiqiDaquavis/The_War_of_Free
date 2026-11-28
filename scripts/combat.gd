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
	return 40 if headshot else 20

# Team identity remains meaningful for targeting, never a damage filter.
const FRIENDLY_FIRE: bool = true
static func friendly(victim: Node, attacker: Node) -> bool:
	return is_instance_valid(attacker) and victim.get("team_id") != null and attacker.get("team_id") != null and victim.team_id == attacker.team_id

static func damage_bearing(victim: Node3D, travel: Vector3, attacker: Node) -> Vector3:
	var bearing := Vector3(-travel.x, 0, -travel.z)
	if bearing.length_squared() < 0.0001 and is_instance_valid(attacker) and attacker is Node3D:
		bearing = attacker.global_position - victim.global_position
		bearing.y = 0
	return bearing.normalized()

static func alive(actor: Node) -> bool:
	if not is_instance_valid(actor):
		return false
	if actor.get("is_alive") != null:
		return actor.is_alive
	return actor.get("defeated") == false

static func can_shoot(tree: SceneTree, shooter: Node) -> bool:
	var owned: int = 0
	var arrows: Array[Node] = tree.get_nodes_in_group("arrows")
	if arrows.size() >= 128:
		return false
	for arrow: Node in arrows:
		if arrow.shooter == shooter:
			owned += 1
	return owned < 6

# One annular-sector strike per victim during an active window. Terrain-only rays
# let the blade sweep past front-row bodies without passing through walls.
static func uses_aoe(kind: String, heavy: bool = false) -> bool:
	return kind in ["dagger", "longsword"] or (kind == "fists" and heavy)

static func in_sector(origin: Vector3, forward: Vector3, point: Vector3, reach: float) -> bool:
	var offset: Vector3 = point - origin
	return offset.length() <= reach + 0.000001 and (offset.length_squared() < 0.000001 or forward.normalized().dot(offset.normalized()) >= cos(deg_to_rad(67.5)) - 0.000001)

static func sweep(attacker: Node3D, origin: Vector3, forward: Vector3, reach: float, damage: float, critical: bool, struck: Dictionary) -> int:
	var count: int = 0
	for actor: Node in attacker.get_tree().get_nodes_in_group("combat_actors"):
		if actor == attacker or not alive(actor) or struck.has(actor.get_instance_id()):
			continue
		var point: Vector3 = actor.get_combat_aim_point()
		if not in_sector(origin, forward, point, reach):
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, point, 1, [attacker.get_rid()])
		if not attacker.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		struck[actor.get_instance_id()] = true
		if actor.take_melee_hit(point, (point - origin).normalized(), damage, critical, attacker):
			count += 1
	return count

# Return only time strictly after the two-second threshold, never bank full HP.
static func regen_tick(actor: Node, delta: float) -> void:
	if not alive(actor) or actor.get_tree().paused:
		return
	var before: float = actor.regen_elapsed
	actor.regen_elapsed = minf(2.0, before + maxf(0, delta))
	var healing_time: float = maxf(0, delta - maxf(0, 2.0 - before))
	if actor.health < MAX_HEALTH and healing_time > 0:
		actor.health = minf(MAX_HEALTH, actor.health + healing_time * 5.0)
		if actor.has_signal("health_changed"):
			actor.health_changed.emit()

static func free_spawn(actor: Node3D, desired: Transform3D) -> Transform3D:
	var result: Transform3D = desired
	for index: int in range(160):
		var occupied: bool = false
		for other: Node in actor.get_tree().get_nodes_in_group("combat_actors"):
			if other != actor and alive(other) and result.origin.distance_to(other.global_position) < 0.9:
				occupied = true
				break
		if not occupied:
			return result
		var radius: float = 1.1 * (1 + index / 12)
		result.origin = desired.origin + Vector3(cos(index * 2.39996), 0, sin(index * 2.39996)) * radius
	return result

# Value-only snapshot: delayed hits must not consult equipment at impact time.
static func actor_identity(actor: Node) -> Dictionary:
	if not is_instance_valid(actor):
		return {}
	var team: Variant = actor.get("team_id")
	var archer: bool = actor.get("role") == "archer" or actor.get("off_hand") == "bow"
	return {"class": "Archer" if archer else "Knight", "team": team if team != null else 1}

static func damage_source(attacker: Node, kind: String = "melee") -> Dictionary:
	var identity: Dictionary = actor_identity(attacker)
	if identity.is_empty():
		return {}
	if kind == "melee":
		var equipped: Variant = attacker.get("main_hand")
		if equipped == null:
			equipped = attacker.get("weapon")
		kind = str(equipped) if equipped != null else "longsword"
	identity["weapon"] = kind
	return identity
