extends Node
## Headless check of the screen code: drives the real main scene through every new panel and menu.
## Run: <godot console exe> --headless --path "<project>" res://tests/uicheck.tscn
## Script errors show up in the output; "UICHECK DONE" means it got to the end.

var main: Node


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)

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

	# Ten days through the real day button (boats sail, sink, come back from voyages)
	for d in 10:
		_step("day %d" % (d + 1))
		while not Game.pending_pick.is_empty():
			Game.answer_pick(0)
		if Game.pending_offer >= 0:
			Game.answer_offer("later")
		if Game.pending_push >= 0:
			Game.resolve_push(false)
		await main._on_start_day()
		await _frames(1)

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
	get_tree().quit()


func _step(name: String) -> void:
	print("step: ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
