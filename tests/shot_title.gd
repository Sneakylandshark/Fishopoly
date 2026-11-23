extends Node
## Screenshot check (not part of the game): the title screen and its moving end-game island.
## Run: Godot_v4.7.2-stable_win64.exe --path "<project>" res://tests/shot_title.tscn
## Saves shot_title_*.png to the user folder, then quits.

# Seconds after start to take each screenshot
const SHOTS := [3.0, 12.0, 20.0, 28.0]
var title: Node
var t := 0.0
var taken := 0


func _ready() -> void:
	title = load("res://scenes/title.tscn").instantiate()
	add_child(title)


func _process(delta: float) -> void:
	t += delta
	if taken < SHOTS.size() and t >= SHOTS[taken]:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://shot_title_%d.png" % taken)
		print("shot ", taken, " boats visible: ", _visible_boats())
		taken += 1
	if taken >= SHOTS.size():
		get_tree().quit()


func _visible_boats() -> int:
	var island: Node = title.get_child(0)
	var n := 0
	for b in island.get_node("Boats").get_children():
		if b.visible:
			n += 1
	return n
