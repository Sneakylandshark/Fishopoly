extends Node
## Screenshot check (not part of the game): the talk panel, mid-typing and finished.
## Run: Godot_v4.7.2-stable_win64.exe --path "<project>" res://tests/shot_talk.tscn
## Saves shot_talk_*.png to the user folder, deletes its own run log, then quits.

var main: Node
var t := 0.0
var taken := 0
const SHOTS := [1.0, 4.0]


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("UI/HelpPanel").visible = false
	while not Game.pending_pick.is_empty():
		Game.answer_pick(0)
	Game.story = [
		{"who": "Old Gus", "role": "Harbour gossip", "title": "A storm on the way", "day": 12, "text": "Sky's gone the colour of a bruise, and the gulls have all flown inland. Mark my words, there's a blow coming before the week's out. Get your deep boats home, or kiss 'em goodbye."},
		{"who": "The Crown's Herald", "role": "Speaks for your Crown", "title": "", "day": 12, "text": "The Crown expects its levy."},
	]
	main.refresh()


func _process(delta: float) -> void:
	t += delta
	if taken < SHOTS.size() and t >= SHOTS[taken]:
		get_viewport().get_texture().get_image().save_png("user://shot_talk_%d.png" % taken)
		taken += 1
	if taken >= SHOTS.size():
		var stray: String = Game.log_path
		Game._open_log(false)
		if stray != "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stray))
		get_tree().quit()
