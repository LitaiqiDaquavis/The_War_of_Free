extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Soldier = preload("res://scripts/soldier.gd")
const Timing = preload("res://scripts/attack_timing.gd")
var checks: int = 0
var failures: Array[String] = []
var world: Node
var player: Node
var bots: Array[Node] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func sync() -> void:
	await physics_frame
	await physics_frame

func setup_targets() -> void:
	player.reset_for_match()
	player.set_physics_process(false)
	player.position = Vector3(0, 0, 0)
	player.look_pitch = 0
	player.rotation = Vector3.ZERO
	player._update_camera()
	player.set_controls_active(true)
	for i: int in range(bots.size()):
		var bot: Node = bots[i]
		bot.reset_for_match()
		bot.set_physics_process(false)
		bot.ai_enabled = false
		bot.has_shield = false
		bot.position = Vector3(10 + i * 2, 0, 0)

func hit(kind: String, heavy: bool = false) -> void:
	player.equip(kind, "shield")
	player._start_attack(heavy, false)
	player._tick_melee(Timing.durations(kind, heavy).x)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.battle_mode = false
	world.training_mode = true
	world.settings_path = "user://health-aoe-smoke.cfg"
	root.add_child(world)
	world.start_game()
	player = world.player
	world.get_node("TrainingEnemy").position = Vector3(40, 0, 40)
	world.get_node("TrainingEnemy").set_physics_process(false)
	for i: int in range(5):
		var bot := Soldier.new()
		bot.team_id = i % 2
		bot.ai_enabled = false
		world.add_child(bot)
		bots.append(bot)
	setup_targets()
	# Precise clocks for player and both teams, independent from AI activation.
	for actor: Node in [player, bots[0], bots[1]]:
		actor.health = 50
		actor.regen_elapsed = 0
		Combat.regen_tick(actor, 1.999)
		check(actor.health == 50, "No healing before 2s")
		Combat.regen_tick(actor, 0.001)
		check(is_equal_approx(actor.health, 50), "At exactly 2s zero healing")
		Combat.regen_tick(actor, 0.4)
		check(is_equal_approx(actor.health, 52), "Exactly 5HP/s for each faction")
		actor.health = 50
		actor.regen_elapsed = 1.9
		Combat.regen_tick(actor, 0.3)
		check(is_equal_approx(actor.health, 51), "Cross threshold consumes only remaining .2s")
		actor.health = 50
		actor.regen_elapsed = 0
		for i: int in range(173):
			Combat.regen_tick(actor, 0.017)
		check(is_equal_approx(actor.health, 50 + (173 * 0.017 - 2) * 5), "Variable timestep invariant")
		actor.take_melee_hit(actor.get_combat_aim_point(), Vector3.FORWARD, 1, false, null)
		var damaged: float = actor.health
		check(actor.regen_elapsed == 0, "Actual damage resets full wait and fraction")
		Combat.regen_tick(actor, 2)
		check(is_equal_approx(actor.health, damaged), "No old fractional healing leaks after interrupt")
		Combat.regen_tick(actor, 0.2)
		check(is_equal_approx(actor.health, damaged + 1), "Restarts at 5HP/s after interrupt")
		actor.health = 99
		Combat.regen_tick(actor, 100)
		check(actor.health == 100, "Healing clamps maximum")
		Combat.regen_tick(actor, 1000)
		actor.take_melee_hit(actor.get_combat_aim_point(), Vector3.FORWARD, 10, false, null)
		Combat.regen_tick(actor, 1.9)
		check(actor.health == 90, "No banked full-health burst")
		paused = true
		Combat.regen_tick(actor, 100)
		check(actor.health == 90 and is_equal_approx(actor.regen_elapsed, 1.9), "Paused clock does not progress")
		paused = false
		actor.reset_for_match()
		actor.set_physics_process(false)
		check(actor.regen_elapsed == 0 and actor.health == 100, "Reset clears heal clock")
	for actor: Node in [player, bots[0], bots[1]]:
		actor.health = 50
		actor.regen_elapsed = 1.9
		actor._physics_process(0.3)
		check(is_equal_approx(actor.health, 51), "Native actor tick integrates regeneration even with AI disabled")
		actor.set_physics_process(false)
	# Guarded hits must not reset regeneration, including friendly arrows.
	player.equip("longsword", "shield")
	player.select_slot(2)
	player.shield_requested = true
	player.blocking = true
	player.health = 70
	player.regen_elapsed = 2
	check(not player.take_projectile_hit(player.get_combat_aim_point(), Vector3.BACK, "arrow", bots[0]), "Friendly projectile still blockable")
	Combat.regen_tick(player, 0.2)
	check(player.health == 71 and player.regen_elapsed == 2, "Player blocked hit preserves active healing")
	bots[0].has_shield = true
	bots[0].blocking = true
	bots[0].health = 70
	bots[0].rotation = Vector3.ZERO
	bots[0].regen_elapsed = 2
	check(not bots[0].take_melee_hit(bots[0].get_combat_aim_point(), Vector3.BACK, 40, false, player), "Friendly AI guard works")
	Combat.regen_tick(bots[0], 0.2)
	check(bots[0].health == 71, "AI block does not interrupt healing")
	for actor: Node in [player, bots[0], bots[1]]:
		if actor == player:
			actor.die()
		else:
			actor.defeat()
		Combat.regen_tick(actor, 100)
		check(actor.health == 0 and actor.collision_layer == 0, "Dead neither heals nor blocks actors")
	world._restore_time()
	world.start_game() # reset below restores actor, then resume controls
	setup_targets()
	world.start_game()
	check(player.collision_layer == 2 and player.collision_mask == 3, "Player on actor layer, not terrain")
	for bot: Node in bots:
		check(bot.collision_layer == 2 and bot.collision_mask == 3 and not bot.get_child(0) == null, "Live AI solid terrain + actor mask")
	# Direct mathematical exact boundary, including pitched vertical cone.
	for angle: float in [-180, -68, -67.501, -67.5, -67.499, 0, 67.499, 67.5, 67.501, 68, 180]:
		var point := Basis(Vector3.UP, deg_to_rad(angle)) * Vector3.FORWARD * 1.8
		check(Combat.in_sector(Vector3.ZERO, Vector3.FORWARD, point, 1.9) == (absf(angle) <= 67.5), "135-degree boundary " + str(angle))
	check(Combat.in_sector(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -1.9), 1.9), "Reach inclusive exact boundary")
	check(not Combat.in_sector(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -1.901), 1.9), "Reach excludes outside")
	var pitched: Vector3 = Basis(Vector3.RIGHT, 0.7) * Vector3.FORWARD
	check(Combat.in_sector(Vector3.ZERO, pitched, pitched * 1.8, 1.9) and not Combat.in_sector(Vector3.ZERO, pitched, Vector3(0, -2, 0), 1.9), "3D pitch and height are respected")
	# Both AOE weapon types and elbow: multiple enemies and friendly; bodies do not occlude.
	for kind: String in ["dagger", "longsword", "fists"]:
		setup_targets()
		bots[0].position = Vector3(0, 0, -0.85)
		bots[1].position = Vector3(0, 0, -1.5)
		bots[2].position = Vector3(0.9, 0, -0.9)
		bots[3].position = Vector3(0, 0, 1)
		await sync()
		hit(kind, kind == "fists")
		check(bots[0].health == 60 and bots[1].health == 60 and bots[2].health == 60, "AOE multi-target including friends and rear rank: " + kind)
		check(bots[3].health == 100, "AOE rejects behind: " + kind)
		player._tick_melee(0.02)
		check(bots[0].health == 60 and bots[1].health == 60 and bots[2].health == 60, "No duplicate across active frames: " + kind)
		bots[4].position = Vector3(-0.8, 0, -1)
		await sync()
		player._tick_melee(0.02)
		check(bots[4].health == 60 and bots[0].health == 60, "Late entrant hit once without repeating prior targets: " + kind)
		player._reset_melee()
		check(player.struck_ids.is_empty(), "Cancel clears per-strike IDs")
	for kind: String in ["spear", "mace", "fists"]:
		setup_targets()
		bots[0].position = Vector3(0, 0, -1)
		bots[1].position = Vector3(0.8, 0, -1)
		await sync()
		hit(kind)
		check(bots[0].health == 60 and bots[1].health == 100, "Non-AOE stays single-target: " + kind)
	# Player and AI damage APIs: kick, shield and all projectile kinds use friendly fire.
	setup_targets()
	for method: String in ["take_kick", "take_shield_hit"]:
		player.health = 100
		bots[0].health = 100
		check(player.call(method, player.get_combat_aim_point(), Vector3.FORWARD, bots[0]) and player.health == 80, "Friendly AI -> player " + method)
		check(bots[0].call(method, bots[0].get_combat_aim_point(), Vector3.FORWARD, player) and bots[0].health == 80, "Friendly player -> AI " + method)
	for kind: String in ["arrow", "throwing_knife"]:
		player.health = 100
		bots[0].health = 100
		var remaining: int = 80 if kind == "arrow" else 40
		check(player.take_projectile_hit(player.get_combat_aim_point(), Vector3.FORWARD, kind, bots[0]) and player.health == remaining, "Friendly projectile -> player " + kind)
		check(bots[0].take_projectile_hit(bots[0].get_combat_aim_point(), Vector3.FORWARD, kind, player) and bots[0].health == remaining, "Friendly projectile -> AI " + kind)
	# Real sector boundary targets and wall obstruction.
	setup_targets()
	bots[0].position = Basis(Vector3.UP, deg_to_rad(67.5)) * Vector3.FORWARD * 1.8
	bots[1].position = Basis(Vector3.UP, deg_to_rad(-67.6)) * Vector3.FORWARD * 1.8
	bots[2].position = Vector3(0, 3, -1)
	await sync()
	hit("dagger")
	check(bots[0].health == 60 and bots[1].health == 100 and bots[2].health == 100, "Real aim-point angle edge and height boundary")
	setup_targets()
	bots[0].position = Vector3(0, 0, -1.5)
	bots[1].position = Vector3(1.2, 0, -1.1)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.65, 3, 0.15)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = Vector3(0, 1.5, -0.7)
	await sync()
	hit("longsword")
	check(bots[0].health == 100 and bots[1].health == 60, "Terrain blocks sweep only behind wall, side target still hit")
	wall.queue_free()
	# AI uses exact same AOE and preserves hostile target after friendly impact.
	for kind: String in ["dagger", "longsword"]:
		setup_targets()
		var ai: Node = bots[0]
		ai.weapon = kind
		ai.position = Vector3.ZERO
		ai.rotation = Vector3.ZERO
		ai.target = bots[1]
		bots[1].position = Vector3(0, 0, -1.4)
		bots[2].position = Vector3(0.8, 0, -1)
		player.position = Vector3(8, 0, 8)
		await sync()
		ai.attack_elapsed = Timing.durations(kind).x
		ai.attack_pending = true
		ai._strike(1.9 if kind == "dagger" else 2.5, false)
		ai._strike(1.9 if kind == "dagger" else 2.5, false)
		check(bots[1].health == 60 and bots[2].health == 60, "AI shared AOE multiple friends/enemies once " + kind)
		ai.take_kick(ai.get_combat_aim_point(), Vector3.FORWARD, bots[2])
		check(ai.health == 80 and ai.target == bots[1] and ai.rear_reactions == 0, "Friendly kick damages but never provokes revenge")
		ai.take_shield_hit(ai.get_combat_aim_point(), Vector3.FORWARD, bots[2])
		check(ai.health == 60 and Combat.friendly(ai, bots[2]), "Friendly shield damages while friendly semantics remain")
		ai._choose_target()
		check(ai.target.team_id != ai.team_id, "AI chooses only hostile faction")
	# Collision: native slide blocks player and bots from interpenetrating.
	setup_targets()
	player.position = Vector3(0, 0, 2)
	bots[0].position = Vector3(0, 0, 0)
	await sync()
	for i: int in range(120):
		player.velocity = Vector3(0, 0, -3)
		player.move_and_slide()
		await physics_frame
	check(player.position.distance_to(bots[0].position) >= 0.72, "Player cannot walk through stationary live AI")
	bots[1].position = Vector3(0, 0, -2)
	await sync()
	for i: int in range(120):
		bots[1].velocity = Vector3(0, 0, 3)
		bots[1].move_and_slide()
		await physics_frame
	check(bots[1].position.distance_to(bots[0].position) >= 0.75, "AI cannot walk through live AI")
	bots[1].spawn_transform = bots[0].transform
	bots[1].reset_for_match()
	bots[1].set_physics_process(false)
	check(bots[1].position.distance_to(bots[0].position) >= 0.9, "Occupied spawn moves to free neighboring slot")
	check(bots[1].collision_layer == 2 and bots[1].collision_mask == 3, "Spawn never solves congestion by disabling collision")
	# Ring state, clamp, resize; rendering capture on graphical run.
	player.health = 25
	player.health_changed.emit()
	check(world.health_ring.health == 25, "Health signal drives low-health ring")
	player.regen_elapsed = 2
	Combat.regen_tick(player, 1)
	check(world.health_ring.health == 30, "Regen signal drives ring")
	world.health_ring.size = Vector2(150, 130)
	world.health_ring.set_health(200)
	check(world.health_ring.health == 100, "Resize-capable ring clamps full HP")
	world.health_ring.set_health(-1)
	check(world.health_ring.health == 0, "Zero ring retains empty background")
	world.health_ring.size = Vector2(106, 106)
	world.health_ring.set_health(65)
	if DisplayServer.get_name() != "headless":
		player.position = Vector3(0, 0, 5)
		player.look_pitch = 0
		player._update_camera()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://output/health_ring_hud.png") == OK, "Rendered ring screenshot")
	world.end_match()
	world.queue_free()
	paused = false
	await process_frame
	print("HEALTH_AOE_SMOKE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
