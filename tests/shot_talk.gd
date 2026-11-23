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
	# A real banter scene from the data, run through the same code the game uses
	Game.story = []
	Game.advisors_met = {"crab": "a", "cray": "a"}
	Game.data.banter.chance = 1.0
	for scene in Game.data.banter.list:
		if scene.id != "pete_kev":
			Game.banter_done.append(scene.id)
	Game.day = 10
	Game._banter_tick({"weather": "normal"})
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
