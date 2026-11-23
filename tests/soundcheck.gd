extends SceneTree
## Headless check (not part of the game): on the title screen's end-game island, every building has its
## looping sound and it's playing. Run:
## Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" -s res://tests/soundcheck.gd

var title: Node
var frames := 0


func _initialize() -> void:
	title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 10:
		return false
	var island: Node = title.get_child(0)
	var total := 0
	var playing := 0
	var looping := 0
	var missing := []
	var shown := []
	for b in island.get_node("Buildings").get_children() + [island.get_node("TownHall"), island.get_node("Island/House")]:
		if not b.visible:
			continue
		shown.append(b.name)
		var p: AudioStreamPlayer3D = b.get_node_or_null("Ambience")
		if p == null:
			missing.append(b.name)
			continue
		total += 1
		if p.playing:
			playing += 1
		if p.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and p.stream.loop_end > 0:
			looping += 1
	print("buildings shown: ", shown.size(), "  with sound: ", total, "  playing: ", playing, "  looping: ", looping)
	print("no sound: ", missing)
	print("listener current: ", island.listener != null and island.listener.is_current())
	return true
