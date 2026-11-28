extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Thrown = preload("res://scripts/thrown_item.gd")
const Icon = preload("res://scripts/kill_weapon_icon.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://kill-feed-smoke.cfg"
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	player.set_physics_process(false)
	for soldier: Node in world.soldiers:
		soldier.set_physics_process(false)
	var feed: Node = world.kill_feed
	var enemy: Node = world.soldiers[19]
	var ally: Node = world.soldiers[0]
	enemy.blocking = false
	ally.blocking = false
	check(feed.entries.is_empty(), "New match feed starts empty.")
	enemy.take_projectile_hit(enemy.get_combat_aim_point(), Vector3.FORWARD, "arrow", ally)
	check(feed.entries.is_empty(), "Nonlethal damage cannot produce a kill.")
	# Snapshot a launched arrow; attacker subsequently changes class / loadout.
	player.equip("dagger", "bow")
	var arrow := Arrow.new()
	arrow.shooter = player
	world.add_child(arrow)
	arrow.set_physics_process(false)
	player.equip("mace", "shield")
	enemy.health = 20
	enemy.take_projectile_hit(enemy.get_combat_aim_point(), Vector3.FORWARD, "arrow", player, arrow.damage_source)
	check(feed.entries.size() == 1 and feed.entries[0].killer.weapon == "arrow" and feed.entries[0].killer["class"] == "Archer", "Arrow retains launch weapon AND launch class after loadout swap.")
	check(feed.entries[0].killer.team == 0 and feed.entries[0].victim.team == 1 and feed.entries[0].victim["class"] == "Archer", "Team and victim class are attributed correctly.")
	enemy.take_projectile_hit(enemy.get_combat_aim_point(), Vector3.FORWARD, "arrow", player)
	check(feed.entries.size() == 1, "Duplicate hit on corpse is ignored.")
	world._tick_battle_respawns(2.0)
	enemy.set_physics_process(false)
	check(feed.entries.size() == 1 and enemy.lethal_source.is_empty(), "Respawn clears attribution without duplicate row.")
	# Real thrown-item callback, not an equipment lookup at impact.
	var item := Thrown.new()
	item.kind = "mace"
	item.shooter = player
	world.add_child(item)
	item.set_physics_process(false)
	player.equip("fists", "bow")
	enemy.health = 40
	item._apply_impact(enemy, Vector3.FORWARD)
	check(feed.entries.size() == 2 and feed.entries[1].killer.weapon == "mace" and feed.entries[1].killer["class"] == "Knight", "Thrown mace retains original class and weapon after dropping it.")
	var first: Node = feed.rows.get_child(0).get_child(0)
	check(first.get_child(0).get_theme_color("font_color") == feed.TEAM_COLORS[0] and first.get_child(2).get_theme_color("font_color") == feed.TEAM_COLORS[1], "Labels use blue killer / red victim team colors.")
	check(first.get_child(1).kind == "arrow" and feed.rows.get_child(1).get_child(0).get_child(1).kind == "mace", "Oldest kill on top; later kills stack below with correct icons.")
	# Kick/shield/fists use actual attack kind and player death also reaches feed.
	ally.health = 20
	ally.take_kick(ally.get_combat_aim_point(), Vector3.FORWARD, player)
	check(feed.entries.back().killer.weapon == "kick", "Kick cannot be mistaken for held weapon; friendly kill is shown.")
	world._tick_battle_respawns(2.0)
	ally.set_physics_process(false)
	ally.health = 20
	ally.take_shield_hit(ally.get_combat_aim_point(), Vector3.FORWARD, player)
	check(feed.entries.back().killer.weapon == "shield", "Shield bash uses shield icon.")
	player.blocking = false
	player.health = 20
	player.take_projectile_hit(player.get_combat_aim_point(), Vector3.FORWARD, "throwing_knife", world.soldiers[20])
	check(feed.entries.back().killer.weapon == "throwing_knife" and feed.entries.back().victim["class"] == "Archer", "Player death uses loadout class and incoming knife icon.")
	world.respawn_player()
	player.set_physics_process(false)
	var count: int = feed.entries.size()
	world.suicide()
	check(feed.entries.size() == count, "Suicide is not credited to an earlier attacker.")
	world.respawn_player()
	player.set_physics_process(false)
	for i: int in range(10):
		feed.add_kill({"class": "Knight", "team": 1, "weapon": "mace"}, {"class": "Archer", "team": 0})
	check(feed.entries.size() == feed.MAX_ENTRIES and feed.rows.get_child_count() == feed.MAX_ENTRIES, "Feed is bounded.")
	var before: float = feed.entries[0].remaining
	paused = true
	feed._process(10)
	check(feed.entries[0].remaining == before, "Pause does not age the feed.")
	paused = false
	feed._process(feed.LIFETIME + 0.1)
	check(feed.entries.is_empty(), "Entries expire after unpaused gameplay.")
	for kind: String in Icon.SUPPORTED:
		var icon := Icon.new()
		icon.kind = kind
		feed.add_child(icon)
		var shape: Array = Icon.business_shape(kind)
		var rightmost: float = -INF
		for vertex: Vector2 in shape:
			rightmost = maxf(rightmost, vertex.x)
		check(icon.BUSINESS_END == Vector2.RIGHT and rightmost >= 52 and rightmost <= 68, "Rendered weapon business geometry points beyond left-side grip: " + kind)
	feed.add_kill({"class": "Knight", "team": 1, "weapon": "mace"}, {"class": "Archer", "team": 0})
	world.end_match()
	world.start_game()
	check(feed.entries.is_empty(), "New match resets feed.")
	arrow.queue_free()
	item.queue_free()
	if failures.is_empty():
		print("KILL_FEED_SMOKE: PASS (attribution / class / team colors / order / bounded / pause / expiry / reset)")
	quit(0 if failures.is_empty() else 1)
