extends SceneTree
const Thrown = preload("res://scripts/thrown_item.gd")
const Arrow = preload("res://scripts/arrow.gd")
var failures: Array[String] = []
var checks: int = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://team-smoke.cfg"
	root.add_child(world)
	world.start_game()
	var counts := [0, 0]
	var archers := [0, 0]
	for actor: Node in get_nodes_in_group("combat_actors"):
		counts[actor.team_id] += 1
		if actor.get("role") == "archer":
			archers[actor.team_id] += 1
	check(counts == [20,20], "Exactly twenty per team including player")
	check(archers == [10,10], "Ten archer AI per team")
	check(world.soldiers.size() == 39, "Thirty nine bots")
	var blue: Node = world.soldiers[10]
	var red: Node = world.soldiers[29]
	var archer: Node = world.soldiers[19]
	for actor: Node in world.soldiers:
		actor.set_physics_process(false)
	world.player.set_physics_process(false)
	var player: Node = world.player
	blue.position = Vector3(0,0.1,0)
	blue.rotation = Vector3.ZERO
	blue.health = 100
	check(blue.take_melee_hit(blue.get_combat_aim_point(), Vector3.BACK, 40, false, player) and blue.health == 60, "Friendly melee damages")
	check(blue.take_projectile_hit(blue.get_combat_aim_point(), Vector3.BACK, "arrow", player) and blue.health == 40, "Friendly arrows damage")
	check(player.take_melee_hit(player.get_combat_aim_point(), Vector3.BACK, 40, false, blue) and player.health == 60, "Friendly AI damages player")
	blue.health = 100
	red.position = Vector3(0,0.1,3)
	blue.target = archer
	check(blue.take_melee_hit(blue.get_combat_aim_point(), Vector3.FORWARD, 10, false, red), "Actual rear hit accepted")
	check(blue.target == red and blue.rear_reactions == 1, "Rear hit retargets its actual attacker")
	await physics_frame
	await physics_frame
	# Exercise actual swept arrow collision, not only the damage API.
	var friendly_arrow := Arrow.new()
	friendly_arrow.shooter = player
	friendly_arrow.velocity = Vector3(0,0,32)
	world.add_child(friendly_arrow)
	friendly_arrow.global_position = blue.get_combat_aim_point() + Vector3(0,0,-0.7)
	friendly_arrow._physics_process(0.03)
	check(friendly_arrow.is_queued_for_deletion() and blue.health == 70, "Friendly body intercepts real arrow with damage")
	var thrown := Thrown.new()
	thrown.shooter = player
	world.add_child(thrown)
	thrown._apply_impact(blue, Vector3.BACK)
	check(blue.health == 30, "Friendly thrown item deals damage")
	thrown.queue_free()
	blue.health = 100
	blue.target = archer
	blue.has_shield = true
	archer.position = Vector3(0,0.1,-15)
	var arrow := Arrow.new()
	arrow.shooter = archer
	arrow.velocity = Vector3(0,0,32)
	world.add_child(arrow)
	arrow.global_position = blue.get_combat_aim_point() + Vector3(0,0,-9)
	check(blue._observe_arrow(), "Visible incoming real arrow triggers shield threat")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,3,0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.position = Vector3(0,1.5,-4)
	# Flush the native physics broadphase without allowing our diagnostic arrow to move.
	arrow.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(not blue._observe_arrow(), "Occluded incoming arrow is not perceived")
	wall.position.x = 20
	await physics_frame
	await physics_frame
	wall.queue_free()
	blue.threat_remaining = 0.9
	blue.attack_elapsed = -1
	blue.ai_enabled = true
	blue._physics_process(0.001)
	check(blue.blocking, "Threat raises equipped shield")
	check(not blue.take_projectile_hit(blue.get_combat_aim_point(), Vector3.BACK, "arrow", archer), "Frontal shield blocks arrow")
	blue.has_shield = false
	blue._physics_process(0.001)
	check(not blue.blocking and not blue._observe_arrow(), "No shield never guards")
	blue.has_shield = true
	arrow.velocity = Vector3(32,0,0)
	check(not blue._observe_arrow(), "Passing arrow not aimed at capsule is not a threat")
	arrow.queue_free()
	player.equip("longsword", "shield")
	player.select_slot(2)
	player.shield_requested = true
	player.special_action = "kick"
	player.special_elapsed = 0.46
	player.special_pending = false
	player.blocking = player._can_block()
	check(player.blocking and player.special_action == "kick", "Shield may rise during kick recovery without cancelling recovery")
	player.kick()
	check(player.special_elapsed == 0.46 and not player.special_pending, "Raised shield cannot start another kick")
	player.special_elapsed = 0.2
	check(not player._can_block(), "Kick active window cannot guard")
	player.cancel_special()
	for actor: Node in [blue, red]:
		actor.health = 100
		actor.defeat()
	var corpse: Node = blue.ragdoll
	world._tick_battle_respawns(1.99)
	check(blue.defeated and red.defeated, "Bots remain dead before two seconds")
	world._tick_battle_respawns(0.02)
	check(not blue.defeated and not red.defeated, "Both teams respawn after two seconds")
	check(blue.position.distance_to(Vector3(-38,0,-38)) < 15 and red.position.distance_to(Vector3(38,0,38)) < 15, "Respawn near respective flags")
	check(is_instance_valid(corpse) and corpse.age_real < 20, "Respawn retains independent corpse")
	corpse._process(19.99)
	check(corpse.is_inside_tree(), "Corpse retained before twenty seconds")
	corpse._process(0.02)
	check(not corpse.is_inside_tree(), "Corpse removed at twenty seconds")
	player.die()
	check(not player.is_alive and not paused, "Player death leaves battle running")
	world.respawn_player()
	check(player.is_alive and player.position.distance_to(Vector3(-38,0,-38)) < 15, "Manual player respawn at blue flag")
	world.reset_round()
	check(get_nodes_in_group("ragdolls").is_empty() and world.respawn_timers.is_empty(), "Reset clears corpse and respawn queues")
	# Run actual native physics, targeting, shots, damage and respawns for 35 s.
	player.set_physics_process(true)
	world.battle_deaths = 0
	world.battle_respawns = 0
	var maximum_arrows: int = 0
	var minimum_live_gap: float = 1000
	var collision_samples: int = 0
	for frame: int in range(2100):
		await physics_frame
		maximum_arrows = maxi(maximum_arrows, get_nodes_in_group("arrows").size())
		if frame % 30 == 29:
			var actors: Array[Node] = get_nodes_in_group("combat_actors")
			for i: int in range(actors.size()):
				if not actors[i].is_inside_tree() or not (actors[i].get("is_alive") == true or actors[i].get("defeated") == false):
					continue
				for j: int in range(i + 1, actors.size()):
					if actors[j].get("is_alive") == true or actors[j].get("defeated") == false:
						var gap: float = actors[i].global_position.distance_to(actors[j].global_position)
						minimum_live_gap = minf(minimum_live_gap, gap)
						collision_samples += 1
		if frame % 300 == 299:
			var alive: int = 0
			var shots: int = 0
			for actor: Node in world.soldiers:
				alive += int(not actor.defeated)
				shots += actor.shots_fired
			print("BATTLE_METRICS sim=", (frame+1)/60.0, " alive_bots=", alive, " shots=", shots, " arrows=", get_nodes_in_group("arrows").size(), " corpses=", get_nodes_in_group("ragdolls").size(), " deaths=", world.battle_deaths, " respawns=", world.battle_respawns)
	check(minimum_live_gap >= 0.70, "40-person live capsules never deeply overlap during 35s battle")
	check(collision_samples > 10000, "Native live collision population sampled throughout battle")
	print("COLLISION_METRICS samples=", collision_samples, " min_gap=", minimum_live_gap)
	check(world.battle_deaths > 0, "Real battle causes casualties")
	check(world.battle_respawns > 0, "Real battle respawns bots")
	check(maximum_arrows > 0 and maximum_arrows <= 128, "Real bounded arrow population")
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(22,28,29)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("res://output/team_battle.png")
	world.end_match()
	check(get_nodes_in_group("projectiles").is_empty() and get_nodes_in_group("ragdolls").is_empty(), "Exit cleans projectiles and corpses")
	print("TEAM_BATTLE_SMOKE: ", checks, " checks, ", failures.size(), " failures; max_arrows=", maximum_arrows)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
