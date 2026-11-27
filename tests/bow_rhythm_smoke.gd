extends SceneTree

const Player = preload("res://scripts/player.gd")
const Visuals = preload("res://scripts/visuals.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func click(player: Node) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	player._unhandled_input(event)
	event.pressed = false
	player._unhandled_input(event)

func arrows() -> int:
	return get_nodes_in_group("arrows").size()

func pose_check(player: Node, visible: bool, label: String) -> void:
	var phase: int = player.bow_phase
	var elapsed: float = player.bow_phase_elapsed
	var draw: float = player.bow_visual_draw()
	for third in [false, true]:
		player.third_person = third
		player._update_camera()
		player._animate_locomotion(0)
		player._update_weapon_pose()
		var view: Node3D = player.off_mount.get_child(0)
		check(view.get_node("NockedArrow").visible == visible and player.body_bow.get_node("NockedArrow").visible == visible, label + ": both rigs agree on nocked arrow")
		var nock: Vector3 = Visuals.bow_nock(draw, 0.0)
		var upper := Vector3(0, 0.55 - draw * 0.07, 0.13 + draw * 0.12)
		check(view.get_node("String0").position.is_equal_approx((nock + upper) / 2), label + ": signed/overdraw reaches actual first-person string mesh")
		var body_nock: Vector3 = Visuals.bow_nock(draw, player.BOW_BODY_LATERAL_PULL)
		check(player.body_bow.get_node("String0").position.is_equal_approx((body_nock + upper) / 2), label + ": third-person string follows same feedback")
		check(player.view_right_arm.get_node("Palm").position.is_finite() and player.body_model.get_node("Upper/RightArm/Palm").position.is_finite(), label + ": both arm IK rigs finite")
	check(player.bow_phase == phase and player.bow_phase_elapsed == elapsed, label + ": camera toggles cannot change timing")

func phase_boundary(player: Node, duration: float, phase: int, next: int, label: String) -> void:
	var before: int = arrows()
	player._tick_bow(duration - 0.00001)
	check(player.bow_phase == phase and not player.bow_ready(), label + ": not early")
	click(player)
	check(arrows() == before, label + ": premature click ignored")
	player._tick_bow(0.00001)
	check(player.bow_phase == next and arrows() == before, label + ": exact boundary; no click buffer")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.settings_path = "user://bow-rhythm-smoke.cfg"
	world.training_mode = true
	root.add_child(world)
	world.start_game()
	var player: Node = world.player
	world.get_node("TrainingEnemy").set_physics_process(false)
	for index in range(5):
		await physics_frame
	player.set_physics_process(false)
	player.equip("spear", "bow")
	player.select_slot(2)
	pose_check(player, false, "equip")
	phase_boundary(player, 0.45, Player.BowPhase.EQUIP, Player.BowPhase.NOCK, "equip .45")
	player._tick_bow(0.2)
	pose_check(player, true, "half nock")
	phase_boundary(player, 0.2, Player.BowPhase.NOCK, Player.BowPhase.READY, "draw .4 / first .85")
	check(player.bow_ready(), "first arrow ready exactly at .85")
	pose_check(player, true, "ready")
	var before: int = arrows()
	var frame: int = Engine.get_physics_frames()
	click(player)
	check(arrows() == before + 1 and Engine.get_physics_frames() == frame, "press synchronously spawns projectile without awaiting any frame or .1 animation")
	check(player.bow_phase == Player.BowPhase.RELEASE, "same press starts cosmetic release only")
	check(not player.off_mount.get_child(0).get_node("NockedArrow").visible and not player.body_bow.get_node("NockedArrow").visible, "same press hides nocked arrow in both rigs")
	player._tick_bow(0.04)
	check(player.bow_visual_draw() > 1.1, "release overpull exceeds full draw")
	pose_check(player, false, "overpull")
	phase_boundary(player, 0.06, Player.BowPhase.RELEASE, Player.BowPhase.STRING, "release .1")
	player._tick_bow(0.05625)
	check(player.bow_visual_draw() < 0, "string oscillates through rest rather than being clamped")
	pose_check(player, false, "string negative oscillation")
	phase_boundary(player, 0.09375, Player.BowPhase.STRING, Player.BowPhase.COOLDOWN, "string .15")
	pose_check(player, false, "cooldown")
	phase_boundary(player, 0.5, Player.BowPhase.COOLDOWN, Player.BowPhase.NOCK, "cooldown .5")
	phase_boundary(player, 0.4, Player.BowPhase.NOCK, Player.BowPhase.READY, "reload draw .4 / repeat 1.15")
	for index in range(3):
		before = arrows()
		click(player)
		check(arrows() == before + 1, "continuous cycle fires once on new press")
		player._tick_bow(1.14999)
		check(not player.bow_ready(), "continuous cycle not ready before 1.15")
		player._tick_bow(0.00001)
		check(player.bow_ready() and arrows() == before + 1, "large delta crosses all phases without autofiring")

	# Switching at partial equip, ready, and release never preserves a shot.
	for elapsed in [0.2, 0.85, 0.89]:
		player.cancel_bow()
		player._tick_bow(minf(elapsed, 0.85))
		if elapsed > 0.85:
			click(player)
			player._tick_bow(elapsed - 0.85)
		player.select_slot(1)
		player._tick_bow(5)
		player.select_slot(2)
		before = arrows()
		player._tick_bow(0.84999)
		click(player)
		check(not player.bow_ready() and arrows() == before, "weapon reselect cannot skip .45 equip + .4 draw")
		player._tick_bow(0.00001)
		check(player.bow_ready() and arrows() == before, "weapon reselect no queued shot")

	# All interruptions discard feedback/draw and require full equipment again.
	for action in ["sprint", "special", "controls"]:
		if action == "sprint":
			player.sprinting = true
		elif action == "special":
			player._begin_special("kick")
		else:
			player.set_controls_active(false)
		before = arrows()
		player._tick_bow(10)
		click(player)
		check(not player.bow_ready() and arrows() == before, action + ": interruption cannot fire or advance preparation")
		player.sprinting = false
		player.cancel_special()
		player.set_controls_active(true)
		player._tick_bow(0.84999)
		check(not player.bow_ready(), action + ": resume cannot skip equipment")
		player._tick_bow(0.00001)
		check(player.bow_ready(), action + ": fresh draw completes without shot")

	before = arrows()
	player.die()
	player._tick_bow(10)
	click(player)
	check(not player.bow_ready() and arrows() == before and player.bow_prepare_elapsed == 0, "death clears draw and blocks stale input")
	player.reset_for_match()
	player.set_controls_active(true)
	player.select_slot(2)
	player._tick_bow(0.84999)
	click(player)
	check(not player.bow_ready() and arrows() == before, "reset cannot restore old ready state")
	player._tick_bow(0.00001)
	check(player.bow_ready() and arrows() == before, "reset requires fresh .85 and no buffered shot")
	if failures.is_empty():
		print("BOW_RHYTHM_SMOKE: PASS (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)
