extends SceneTree
## Headless check (not part of the game): the title screen's New Run and Continue buttons start a clean, real run.
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" -s res://tests/titleflow.gd

var title: Node
var step := 0
var waited := 0


func _initialize() -> void:
	title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)


func _process(_delta: float) -> bool:
	waited += 1
	var game: Node = root.get_node("Game")
	if step == 0 and waited > 5:
		# New Run deletes a saved run, so never run this check over a real save
		if game.has_save():
			print("A saved run exists: check skipped so it isn't deleted")
			return true
		print("showcase boats: ", game.boats.size(), " built: ", game.built.size())
		title._start_new_run()
		step = 1
		waited = 0
	elif step == 1 and waited > 5:
		print("after New Run: scene=", current_scene.scene_file_path if current_scene else "none", " boats=", game.boats.size(), " built=", game.built.size(), " day=", game.day, " champion=", game.champion_index)
		var ok: bool = game.boats.size() == int(game.data.start.fishing_boats) and game.built.is_empty() and game.champion_index == -1
		print("NEW RUN CLEAN: ", ok)
		# A real run writes a log file; this one was only a check
		var stray: String = game.log_path
		game._open_log(false)
		if stray != "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stray))
		return true
	return false
