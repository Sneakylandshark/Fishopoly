extends Node
## Screenshot check (not part of the game): the choice panels with portraits.
## Crown pick, champion pick, Visitors, an advisor, and a rival Crown pushing.
## Run: Godot_v4.7.2-stable_win64.exe --path "<project>" res://tests/shot_panels.tscn
## Saves shot_panels_*.png to the user folder, deletes its own run log, then quits.

var main: Node
var step := 0
var wait := 10


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("UI/HelpPanel").visible = false
	Game.story.clear()


func _process(_d: float) -> void:
	wait -= 1
	if wait > 0:
		return
	if step > 0:
		get_viewport().get_texture().get_image().save_png("user://shot_panels_%d.png" % step)
	step += 1
	wait = 8
	match step:
		1:
			# Sea conditions first, then the Crown pick
			if Game.pending_pick.get("kind", "") == "conditions":
				Game.answer_pick(0)
			print("pick: ", Game.pending_pick.get("kind", ""))
		2:
			Game.answer_pick(0)
			print("pick: ", Game.pending_pick.get("kind", ""))
		3:
			while not Game.pending_pick.is_empty():
				Game.answer_pick(0)
			Game.story.clear()
			Game.pending_offer = 0
			main.offer_open = true
		4:
			Game.pending_offer = -1
			main.offer_open = false
			Game._queue_advisor("piracy")
			Game._next_advisor()
			print("pick: ", Game.pending_pick.get("kind", ""))
		5:
			Game.pending_pick = {}
			Game.rival_index = 2
			Game.pending_push = 2
		_:
			var stray: String = Game.log_path
			Game._open_log(false)
			if stray != "":
				DirAccess.remove_absolute(ProjectSettings.globalize_path(stray))
			get_tree().quit()
			return
	main.refresh()
