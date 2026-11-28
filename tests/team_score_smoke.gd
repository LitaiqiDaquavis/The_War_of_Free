extends SceneTree

const Timing = preload("res://scripts/attack_timing.gd")
const Visuals = preload("res://scripts/visuals.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://team-score-smoke.cfg"
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	player.set_physics_process(false)
	for soldier: Node in world.soldiers:
		soldier.set_physics_process(false)
	var ally: Node = world.soldiers[10]
	var enemy: Node = world.soldiers[29]
	var archer: Node = world.soldiers[19]
	check(world.score_label.is_visible_in_tree() and world.team_scores == [0, 0], "A new match displays a 0-0 score.")

	enemy.health = 40
	enemy.take_melee_hit(enemy.get_combat_aim_point(), Vector3.FORWARD, 40, false, player)
	check(world.team_scores == [1, 0] and world.score_label.text.contains("BLUE  1"), "Player melee kill scores for blue.")
	enemy.take_projectile_hit(enemy.get_combat_aim_point(), Vector3.FORWARD, "arrow", ally)
	check(world.team_scores == [1, 0], "A defeated actor cannot score twice.")
	world._tick_battle_respawns(2.0)
	enemy.set_physics_process(false)
	enemy.health = 20
	enemy.take_kick(enemy.get_combat_aim_point(), Vector3.FORWARD, ally)
	check(world.team_scores == [2, 0], "A blue bot kick earns one point after enemy respawn.")
	ally.health = 20
	ally.take_shield_hit(ally.get_combat_aim_point(), Vector3.FORWARD, player)
	check(world.team_scores == [2, 0], "Friendly kills never score.")

	player.health = 20
	player.take_projectile_hit(player.get_combat_aim_point(), Vector3.FORWARD, "arrow", archer)
	check(world.team_scores == [2, 1], "A red archer killing the player adds one red point.")
	world.respawn_player()
	player.set_physics_process(false)
	check(world.team_scores == [2, 1] and player.is_alive, "Player respawn preserves the team scores.")
	world.suicide()
	check(world.team_scores == [2, 1], "Suicide never scores.")
	world.respawn_player()
	player.set_physics_process(false)
	archer.defeat()
	check(world.team_scores == [2, 1], "A defeat without a killer never scores.")

	var blue_spawn: Vector3 = world.battlefield.get_spawn_transform(0, 0).origin
	player.position = Vector3(20, -25, -15)
	player.velocity = Vector3(0, -6, 0)
	player._physics_process(1.0 / 60.0)
	check(player.position.distance_to(blue_spawn) < 3 and player.velocity == Vector3.ZERO, "Falling out returns the player to a clear team spawn with zero velocity.")
	check(world.team_scores == [2, 1], "Returning after an unassisted fall leaves the score intact.")

	world.end_match()
	world.start_game()
	check(world.team_scores == [0, 0], "Starting another match resets both scores.")
	player.set_physics_process(false)
	for soldier: Node in world.soldiers:
		soldier.set_physics_process(false)
	archer.target = player
	archer.velocity = Vector3(0, 0, -5)
	archer.sprinting = true
	archer.bow_elapsed = 1.2
	archer._animate_fighter(0.20)
	var left: Node3D = archer.upper.get_node("LeftArm")
	var upper_arm: Vector3 = left.get_node("Elbow").position
	var forearm: Vector3 = left.get_node("Hand").position - upper_arm
	check(upper_arm.normalized().dot(forearm.normalized()) > 0.99 and archer.bow.get_node("NockedArrow").visible, "AI aims from the shared full-draw pose with its bow arm extended.")

	var spearman: Node = world.soldiers[32]
	check(spearman.weapon == "spear", "Fixture uses a spawned spearman.")
	spearman.target = player
	spearman.attack_cooldown = 0
	spearman.spear_carry = 1
	spearman._melee_tick(0.0, Vector3.FORWARD, 3.0)
	spearman._melee_tick(0.29, Vector3.FORWARD, 3.0)
	check(spearman.attack_elapsed == 0 and spearman.spear_switch_remaining > 0, "AI spear must finish switching out of chest carry before starting normal wind-up.")
	spearman._melee_tick(0.02, Vector3.FORWARD, 3.0)
	check(Timing.stage("spear", spearman.attack_elapsed) == "windup" and spearman.spear_switch_remaining == 0, "AI spear enters normal wind-up after the 0.30-second transition.")

	if failures.is_empty():
		print("TEAM_SCORE_SMOKE: PASS")
	quit(0 if failures.is_empty() else 1)
