extends Node
## Screenshot check (not part of the game): a close-up of every building model, all on one sheet.
## Run: Godot_v4.7.2-stable_win64.exe --path "<project>" res://tests/shot_buildings.tscn
## Saves shot_buildings.png to the user folder, deletes its own run log, then quits.

const TILE := Vector2i(400, 260)
const COLS := 6
var main: Node
var targets: Array = []
var i := -1
var wait := 0
var sheet: Image


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("UI").visible = false
	for b in main.get_node("Buildings").get_children():
		targets.append(b)
	targets.append(main.get_node("TownHall"))
	targets.append(main.get_node("Island/House"))
	var rows := int(ceil(targets.size() / float(COLS)))
	sheet = Image.create(TILE.x * COLS, TILE.y * rows, false, Image.FORMAT_RGB8)


func _process(_delta: float) -> void:
	wait -= 1
	if wait > 0:
		return
	if i >= 0:
		var shot := get_viewport().get_texture().get_image()
		shot.convert(Image.FORMAT_RGB8)
		shot.resize(TILE.x, TILE.y)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % COLS) * TILE.x, (i / COLS) * TILE.y))
	i += 1
	if i >= targets.size():
		sheet.save_png("user://shot_buildings.png")
		var stray: String = Game.log_path
		Game._open_log(false)
		if stray != "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stray))
		get_tree().quit()
		return
	# Show only this building (champion buildings share one plot), and frame it
	for t in targets:
		t.visible = t == targets[i]
	var b: Node3D = targets[i]
	var model: Node3D = b.get_node_or_null("Model")
	var top: float = main._model_top(model) if model else 3.0
	var aim: Vector3 = (model.global_position if model else b.global_position) + Vector3(0, top * 0.4, 0)
	var cam: Camera3D = main.get_node("Camera3D")
	# Look from the sea side (away from the island centre), so hills behind the camera don't block the view
	var out := Vector3(aim.x, 0, aim.z).normalized() if Vector2(aim.x, aim.z).length() > 4.0 else Vector3(0.6, 0, 0.8)
	cam.global_position = aim + (out + Vector3(0, 0.7, 0)).normalized() * (top * 1.6 + 6.0)
	cam.look_at(aim, Vector3.UP)
	print(i, " ", b.name, " top ", snappedf(top, 0.1))
	wait = 4
