extends Node
## Screenshot check (not part of the game). Opens the main scene, cheats in money, builds through every tier,
## shows the rival Crown popup, plays some days, and saves pictures to the user folder, then quits.
## It deletes its own run log on the way out, so it never mixes with real play logs.
## Run: Godot_v4.7.2-stable_win64.exe --path "<project>" res://tests/shot.tscn

var main: Node
var frame := 0
var clock := 0.0
var day_started_at := -1.0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(delta: float) -> void:
	frame += 1
	clock += delta
	if frame == 20:
		_save("shot_start.png")
	if frame == 25:
		main.get_node("UI/HelpPanel").visible = false
		main.open_menu_for("piracy")
	if frame == 32:
		_save("shot_locked.png")
		_cheat_everything()
		main.open_menu_for("oil")
		main.refresh()
	if frame == 38:
		# Pretend the hull-or-nets visitors have come
		main.close_menu()
		Game.pending_offer = 1
		main.refresh()
	if frame == 42:
		_save("shot_offer.png")
		Game.answer_offer("a")
		main.open_menu_for("deep")
	if frame == 45:
		_save("shot_built.png")
		# Pretend the rival Crown has pushed
		Game.last_week = 50000.0
		Game.pending_push = 0
		main.refresh()
	if frame == 55:
		_save("shot_crown.png")
		Game.resolve_push(true)
	if frame == 60:
		# Simulate a real mouse click on the Oil Platform
		main.close_menu()
		var cam: Camera3D = main.get_node("Camera3D")
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = cam.unproject_position(main.get_node("Buildings/oil").global_position)
		Input.parse_input_event(ev)
	if frame == 66:
		print("CLICK TEST: open menu = '", main.open_menu, "' (expected 'oil')")
		main.close_menu()
		main._on_start_day()
		day_started_at = clock
	# Keep playing days until a storm shows (max 12), then take the last picture
	if day_started_at >= 0 and clock - day_started_at > 3.0:
		if Game.pending_push >= 0:
			Game.resolve_push(false)
		if Game.day >= 12 or main.top_row.get_node("Weather").text.ends_with("Storm"):
			_save("shot_after_day.png")
			_quit()
		else:
			main._on_start_day()
			day_started_at = clock


func _cheat_everything() -> void:
	Game.cash = 50000000
	for t in [1, 2, 3, 4]:
		for key in Game.data.avenues:
			if int(Game.data.avenues[key].tier) == t:
				Game.build(key)
		var need := int(Game.data.tiers.min_level.get(str(t + 1), 0))
		for key in ["fish"] + Game.data.avenues.keys():
			if Game.tier_of(key) != t:
				continue
			for i in Game.paths_for(key).size():
				while Game.levels[key][i] < min(need, Game.path_max_level(key, i)):
					Game.upgrade(key, i)
	Game.buy_unit("piracy")
	Game.buy_unit("cray")
	Game.buy_fishing_boat()
	Game.cash = 3000000


func _quit() -> void:
	# Remove this test's own log file
	var path: String = Game.log_path
	if Game.log_file != null:
		Game.log_file.close()
		Game.log_file = null
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	get_tree().quit()


func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("user://" + file)
	img.save_png(path)
	print("saved ", path)
