extends Node
## Screenshot check (not part of the game): late-game numbers in the top bars, scrolled and not, and the newspaper.
## Run: Godot_v4.7.2-stable_win64.exe --path "<project>" res://tests/shot_bars.tscn
## Saves shot_bars_*.png to the user folder, deletes its own run log, then quits.

var main: Node
var frame := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	if frame == 10:
		main.get_node("UI/HelpPanel").visible = false
		# Late-game numbers, and a month of days so the paper is long
		while not Game.pending_pick.is_empty():
			Game.answer_pick(0)
		Game.cash = 415000000.0
		for k in Game.data.avenues:
			if not Game.is_champion_building(k):
				Game.built[k] = true
				if Game.data.avenues[k].has("unit"):
					Game._add_unit(k)
		Game.laundering = true
		Game.oil_ready_day = 0
		for d in 60:
			Game.cash = max(Game.cash, 415000000.0)
			if Game.pending_push >= 0:
				Game.resolve_push(false)
			if Game.pending_offer >= 0:
				Game.answer_offer("later")
			while not Game.pending_pick.is_empty():
				Game.answer_pick(0)
			Game.start_day()
			Game.story.clear()
		main.refresh()
	if frame == 30:
		_save("shot_bars_start.png")
		main.top_row.get_parent().scroll_horizontal = 100000
		main.status_row.get_parent().scroll_horizontal = 100000
	if frame == 36:
		_save("shot_bars_scrolled.png")
		main.open_newspaper()
	if frame == 44:
		_save("shot_bars_paper.png")
		main.get_node("UI/Newspaper").visible = false
		main.open_menu_for("customs_house")
	if frame == 50:
		_save("shot_bars_customs.png")
		main.open_menu_for("gazette_office")
	if frame == 56:
		_save("shot_bars_gazette.png")
		_quit()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://" + file)
	print("saved ", file)


func _quit() -> void:
	# Remove this test's own log file
	var path: String = Game.log_path
	if Game.log_file != null:
		Game.log_file.close()
		Game.log_file = null
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	get_tree().quit()
