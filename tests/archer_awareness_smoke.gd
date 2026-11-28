extends SceneTree

const DamageIndicator = preload("res://scripts/damage_indicator.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func sync_physics() -> void:
	await physics_frame
	await physics_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://archer-awareness-smoke.cfg"
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	player.set_physics_process(false)
	for soldier: Node in world.soldiers:
		soldier.set_physics_process(false)
	var archer: Node = world.soldiers[19]
	var blocker: Node = world.soldiers[29]
	archer.position = Vector3(0, 0.1, 0)
	archer.rotation = Vector3.ZERO
	player.position = Vector3(0, 0.1, -12)
	player.rotation = Vector3.ZERO
	blocker.position = Vector3(0, 0.1, -4)
	archer.target = player
	await sync_physics()

	archer.bow_elapsed = 2.0
	archer._archer_tick(0.016, Vector3.FORWARD, 12)
	check(archer.shots_fired == 0 and get_nodes_in_group("arrows").is_empty(), "The archer must hold fire with an ally between it and its target.")
	check(absf(archer.velocity.x) > 1.0 and absf(archer.velocity.z) < 0.001, "An ally in the lane triggers a sideways step.")
	check(archer._ally_on_arrow_path(Vector3(0, 1.55, -0.60), Vector3(0, 1.4, -32), 0.35), "The launch check must also identify an ally on the curved trajectory.")
	archer.position += archer.firing_step * 2.2
	archer.look_at(Vector3(player.position.x, archer.position.y, player.position.z))
	await sync_physics()
	var to_player: Vector3 = player.position - archer.position
	archer.firing_probe_remaining = 0
	archer.velocity = Vector3(1, 0, 0)
	archer._archer_tick(0.016, to_player.normalized(), to_player.length())
	check(archer.shots_fired == 1 and archer.bow_elapsed == 0, "The archer fires while moving once its new sightline is clear.")
	for arrow: Node in get_nodes_in_group("arrows"):
		arrow.set_physics_process(false)

	archer.position = Vector3(0, 0.1, 0)
	archer.rotation = Vector3.ZERO
	blocker.position = Vector3(5, 0.1, -4)
	player.position = Vector3(0, 0.1, -4)
	player.velocity = Vector3.BACK * 3
	await sync_physics()
	archer.velocity = Vector3.ZERO
	archer._archer_tick(0.1, Vector3.FORWARD, 4)
	check(archer.velocity.dot(Vector3.FORWARD) >= -0.001 and archer.velocity.length() < 0.001, "The archer holds its ground as an enemy approaches.")

	archer.take_melee_hit(archer.get_combat_aim_point(), Vector3.LEFT, 10, false, player)
	check(archer.damage_bearing.is_equal_approx(Vector3.RIGHT) and archer.target == player, "AI registers the direction of a side hit and keeps the hostile source.")
	archer._physics_process(0.18)
	check((-archer.global_basis.z).dot(Vector3.RIGHT) > 0.95, "The soldier turns to face the incoming hit.")
	archer.take_melee_hit(archer.get_combat_aim_point(), Vector3.FORWARD, 10, false, blocker)
	check(archer.damage_bearing.is_equal_approx(Vector3.BACK) and archer.target == player, "AI notices a friendly hit from behind while keeping an enemy target.")

	var ring: Control = world.damage_indicator
	var center: Vector2 = ring.get_global_rect().get_center()
	check(center.distance_to(root.get_visible_rect().size * 0.5) < 1.0, "Damage indicator is centered on the crosshair.")
	player.equip("longsword", "shield")
	player.take_kick(player.get_combat_aim_point(), Vector3.LEFT, archer)
	player.take_projectile_hit(player.get_head_position(), Vector3.RIGHT, "arrow", archer)
	check(ring.hits.size() == 2 and ring.hits[0].bearing == Vector3.RIGHT and ring.hits[1].bearing == Vector3.LEFT, "Separate damage sources use separate directions.")
	check(ring.hits[0].amount == 20 and ring.hits[1].amount == 40 and DamageIndicator.span_for(40) > DamageIndicator.span_for(20), "Heavier damage makes a longer arc.")
	check(is_equal_approx(DamageIndicator.angle_for(Vector3.FORWARD, Vector3.RIGHT), -PI / 2) and is_equal_approx(DamageIndicator.angle_for(Vector3.BACK, Vector3.RIGHT), PI / 2), "Front hits appear above center and rear hits below.")
	check(is_equal_approx(DamageIndicator.angle_for(Vector3.RIGHT, Vector3.BACK), -PI / 2), "Turning toward a hit rotates its arc to the front.")
	player.select_slot(2)
	player.shield_requested = true
	player.blocking = true
	var blocked: bool = not player.take_melee_hit(player.get_combat_aim_point(), Vector3.BACK, 40, false, archer)
	check(blocked and ring.hits.size() == 3 and ring.hits.back().blocked and player.health == 40, "A blocked attack shows a gray arc without damage.")
	ring._process(1.0)
	check(ring.hits.is_empty(), "Old damage arcs expire.")

	if failures.is_empty():
		print("ARCHER_AWARENESS_SMOKE: PASS")
	quit(0 if failures.is_empty() else 1)
