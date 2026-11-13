extends Node
## Headless check of the screen code: drives the real main scene through every new panel and menu.
## Run: <godot console exe> --headless --path "<project>" res://tests/uicheck.tscn
## Script errors show up in the output; "UICHECK DONE" means it got to the end.

var main: Node


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	# The camera rig must start exactly where main.tscn puts the camera (6, 45, 64)
	print("camera start: ", main.get_node("Camera3D").global_position, " looking at ", main.cam_target)
	main.cam_dist = main.ZOOM_MIN
	main.cam_yaw += PI
	main._apply_camera()
	print("camera zoomed in, other side: ", main.get_node("Camera3D").global_position)
	main._setup_camera()

	# Sea conditions, then the Crown pick (grid), then the champion pick (grid)
	_step("conditions")
	Game.answer_pick(0)
	await _frames(2)
	_step("crown pick")
	Game.answer_pick(2)
	await _frames(2)
	_step("champion pick")
	Game.answer_pick(0)
	await _frames(2)

	# Champion buildings: yours shows on the plot and can be opened; the others stay hidden and locked
	_step("champion building")
	var cbk: String = Game.champion_building()
	print("champion: ", Game.champion().id, "  building: ", cbk, "  blockers: ", Game.build_blockers(cbk))
	print("  plot node visible: ", main.get_node("Buildings/" + cbk).visible, "  others hidden: ", Game.data.avenues.keys().filter(func(k): return Game.is_champion_building(k) and k != cbk and main.get_node("Buildings/" + k).visible).is_empty())
	print("  another champion's blockers: ", Game.build_blockers("bank"))
	main.open_menu_for(cbk)
	await _frames(1)
	main.close_menu()
	Game.cash = 50000.0
	print("  built: ", Game.build(cbk), "  cash after: ", Game.cash, "  can build bank too: ", Game.can_build("bank"))
	for i in Game.data.avenues[cbk].paths.size():
		print("  ", Game.data.avenues[cbk].paths[i].name, ": ", Game.cb_path_text(cbk, i))
	main.open_menu_for(cbk)
	await _frames(1)
	main.close_menu()

	# Records buildings: graphs are locked until their building is built
	_step("records locked")
	main._open_graphs()
	await _frames(1)
	var locked: Array = Game.HISTORY_GROUPS.keys().filter(func(g): return not Game.graph_group_open(g))
	print("  locked groups before building: ", locked)
	print("  cash tick disabled: ", main.get_node("UI/GraphPanel").find_child("Tick_Cash", true, false).disabled)
	main.get_node("UI/GraphPanel").visible = false
	Game.cash = 50000.0
	print("  built harbour office: ", Game.build("harbour_office"))
	main._open_graphs()
	await _frames(1)
	print("  cash tick disabled after: ", main.get_node("UI/GraphPanel").find_child("Tick_Cash", true, false).disabled, "  still locked: ", Game.HISTORY_GROUPS.keys().filter(func(g): return not Game.graph_group_open(g)))
	main.get_node("UI/GraphPanel").visible = false

	# Own everything, with money to spare, so every menu has something to show
	Game.cash = 1000000000.0
	Game.laundering = true
	for key in Game.data.avenues:
		if not Game.built.has(key):
			Game.built[key] = true
			if Game.data.avenues[key].has("unit"):
				Game._add_unit(key)
	Game.oil_ready_day = 0
	main.refresh()
	await _frames(2)
	for key in ["fish"] + Game.data.avenues.keys():
		_step("menu " + key)
		main.open_menu_for(key)
		await _frames(1)
	main.close_menu()

	# Voyages from the bounty board
	_step("voyages")
	for i in range(Game.board.size() - 1, -1, -1):
		if Game.can_send(i):
			Game.send_voyage(i)
	main.open_menu_for("piracy")
	await _frames(2)
	main.close_menu()

	# An advisor
	_step("advisor")
	Game._queue_advisor("pearl")
	Game._next_advisor()
	await _frames(2)
	Game.answer_pick(1)
	await _frames(1)

	# The wildcat well (oil found, permit through, no platform yet)
	_step("wildcat")
	Game.built.erase("oil")
	Game.oil_found = true
	Game.permit_day = 0
	main.open_menu_for("oil")
	await _frames(1)
	Game.build_wildcat()
	await _frames(1)
	main.close_menu()

	# Favours
	_step("favour")
	Game.favour = 2
	Game.strikes = 1
	Game.decree = Game.data.levy.decrees[0]
	main.refresh()
	await _frames(1)
	Game.favour_strike()
	await _frames(1)

	# The My run panel, with everything owned
	_step("my run panel")
	main._open_run_panel()
	await _frames(2)
	print(main.get_node("UI/RunPanel/Box/Text").get_parsed_text().substr(0, 1500))

	# Ten days through the real day button (boats sail, sink, come back from voyages)
	for d in 10:
		_step("day %d" % (d + 1))
		while not Game.pending_pick.is_empty():
			Game.answer_pick(0)
		while not Game.story.is_empty():
			print("story: ", Game.story[0].who, " | ", Game.story[0].title)
			Game.read_story()
		if Game.pending_offer >= 0:
			main.open_visitors()
			await _frames(1)
			Game.answer_offer("later")
		if Game.pending_push >= 0:
			Game.resolve_push(false)
		await main._on_start_day()
		await _frames(1)

	# Graphs, newspaper and a talk panel
	_step("graphs")
	main._open_graphs()
	for s in ["Bank", "Tax", "Rent", "Suspicion"]:
		main.get_node("UI/GraphPanel").find_child("Tick_" + s, true, false).button_pressed = true
	main.graph_mode.select(1)
	main._draw_graphs()
	await _frames(2)
	print(main.graph_totals.get_parsed_text())
	main.get_node("UI/GraphPanel").visible = false
	_step("newspaper")
	main.open_newspaper()
	await _frames(1)
	print(main.paper_text.get_parsed_text().substr(0, 600))
	main.get_node("UI/Newspaper").visible = false
	_step("talk panel")
	Game.event_due = {"index": Game.data.events.list.size() - 1, "day": Game.day + 1}
	while not Game.pending_pick.is_empty():
		Game.answer_pick(0)
	if Game.pending_offer >= 0:
		Game.answer_offer("later")
	if Game.pending_push >= 0:
		Game.resolve_push(false)
	await main._on_start_day()
	await _frames(1)
	print("talk visible: ", main.get_node("UI/TalkPanel").visible, " | ", main.talk_text.get_parsed_text())
	print("history days: ", Game.history["Cash"].size(), " day ", Game.day)

	# Save, start a new run (it offers to continue), continue, then clean up
	_step("save and continue")
	Game.save_enabled = true
	Game.save_run()
	var saved_day: int = Game.day
	Game.new_run(-1, true)
	var test_log: String = Game.log_path
	await _frames(2)
	print("continue offered: ", Game.pending_pick.get("kind", ""))
	Game.answer_pick(0)
	await _frames(2)
	print("day after continue: %d (saved %d)" % [Game.day, saved_day])
	Game.save_enabled = false
	Game.delete_save()
	if test_log != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_log))
	print("UICHECK DONE")
	# Remove this test's own run log, so it never mixes with real play logs
	var path: String = Game.log_path
	if Game.log_file != null:
		Game.log_file.close()
		Game.log_file = null
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	get_tree().quit()


func _step(name: String) -> void:
	print("step: ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
