extends SceneTree
const Arrow = preload("res://scripts/arrow.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://kill-feed-projectile.cfg"
	root.add_child(world)
	world.start_game()
	world.player.set_physics_process(false)
	world.player.position = Vector3(40, 1, 40)
	for soldier: Node in world.soldiers:
		soldier.set_physics_process(false)
		soldier.position = Vector3(80 + soldier.slot * 2, 1, 80 + soldier.team_id * 4)
	var victim: Node = world.soldiers[0]
	var shooter: Node = world.soldiers[19]
	victim.position = Vector3(0, 2, 0)
	victim.blocking = false
	victim.health = 20
	var arrow := Arrow.new()
	arrow.shooter = shooter
	world.add_child(arrow)
	arrow.set_physics_process(false)
	arrow.position = Vector3(-2, 3.15, 0)
	arrow.velocity = Vector3(40, 0, 0)
	shooter.role = "melee"
	shooter.weapon = "mace"
	await physics_frame
	await physics_frame
	arrow._physics_process(0.1)
	check(victim.defeated and world.kill_feed.entries.size() == 1, "Actual projectile ray contact creates exactly one kill row.")
	if not world.kill_feed.entries.is_empty():
		var entry: Dictionary = world.kill_feed.entries[0]
		check(entry.killer.weapon == "arrow" and entry.killer["class"] == "Archer" and entry.killer.team == 1, "Collision path retains launch snapshot despite AI role / equipment change.")
	# Exercise the separate player projectile-contact API with an unavailable shooter.
	world.player.position = Vector3(0, 2, 5)
	world.player.blocking = false
	world.player.health = 60
	shooter.role = "archer"
	var knife := Arrow.new()
	knife.projectile_kind = "throwing_knife"
	knife.shooter = shooter
	world.add_child(knife)
	knife.set_physics_process(false)
	knife.position = Vector3(-2, 3.15, 5)
	knife.velocity = Vector3(40, 0, 0)
	knife.shooter = null
	await physics_frame
	await physics_frame
	knife._physics_process(0.1)
	check(not world.player.is_alive and world.kill_feed.entries.size() == 2, "Player projectile contact still attributes a delayed knife when shooter reference is gone.")
	if world.kill_feed.entries.size() == 2:
		check(world.kill_feed.entries[1].killer.weapon == "throwing_knife", "Player contact preserves knife icon rather than current equipment.")
	if failures.is_empty():
		print("KILL_FEED_PROJECTILE_SMOKE: PASS (real ray collisions, delayed loadout, unavailable shooter, player contact)")
	quit(0 if failures.is_empty() else 1)
