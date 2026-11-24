extends Node
## Trailer recorder (not part of the game): plays a short scripted trailer on the real island.
## Record it with Godot's Movie Maker (30 fps, 1920x1080, no music; add music afterwards):
##   Godot_v4.7.2-stable_win64.exe --path "<project>" --write-movie "<out>.avi" --fixed-fps 30 --resolution 1920x1080 res://tests/trailer.tscn
## It never saves, never writes a run log and never touches your saved run.

const MAIN_SCENE := "res://scenes/main.tscn"
const HEADING_FONT := "res://assets/fonts/cinzel-latin-700-normal.woff2"
# The big end-game fleet: kind -> [how many, starting zone] (same as the title screen)
const BIG_FLEET := {
	"fish": [14, "harbor"],
	"crab": [8, "harbor"],
	"whale": [4, "deep"],
	"barge": [4, "harbor"],
	"smuggler": [8, "harbor"],
	"pirate": [6, "harbor"],
	"rig": [4, "harbor"],
}
# Each shot: seconds long, the caption, and the function that sets it up
const SHOTS := [
	[6.0, "Start with one boat and $500.", "_shot_start"],
	[5.0, "Brave the storms.", "_shot_storm"],
	[5.5, "Meet the locals.", "_shot_talk"],
	[8.0, "Build a fishing empire.", "_shot_empire"],
	[5.5, "Buy the island from the Crown.", "_shot_win"],
	[5.0, "", "_shot_card"],
]
const FADE := 0.4

var main: Node
var caption: Label
var fader: ColorRect
var card: Control
# Degrees per second the camera turns in the current shot
var turn := 0.0
var zoom_to := -1.0
# The middle of the island's land (measured from island_art.tscn), and the game's own harbour view
const ISLAND_MIDDLE := Vector3(-2.5, 3.0, -14.0)
var harbour_target := Vector3.ZERO


func _ready() -> void:
	# The game opens a real run (and a log file) on start: swap it for a quiet one and delete that log
	var stray: String = Game.log_path
	Game.new_run(7, false)
	if stray != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stray))
	Game.pending_pick = {}
	Game._take_champion(0)
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	harbour_target = main.cam_target0
	_make_overlay()
	_run()


func _process(delta: float) -> void:
	if main == null:
		return
	main.cam_yaw += deg_to_rad(turn) * delta
	if zoom_to > 0.0:
		main.cam_dist = lerp(main.cam_dist, zoom_to, 1.0 - exp(-1.2 * delta))
	main._apply_camera()


func _run() -> void:
	for s in SHOTS:
		fader.color.a = 1.0
		call(s[2])
		# The "How to play" panel opens by itself on a new game: keep it out of the trailer
		main.get_node("UI/HelpPanel").visible = false
		_caption(s[1])
		create_tween().tween_property(fader, "color:a", 0.0, FADE)
		await get_tree().create_timer(float(s[0]) - FADE).timeout
		var out := create_tween()
		out.tween_property(fader, "color:a", 1.0, FADE)
		await out.finished
	get_tree().quit()


# ---------- The shots ----------

func _look_at_island() -> void:
	# cam_pan isn't turned with the camera, so the island stays in the middle as it circles
	main.cam_target0 = Vector3.ZERO
	main.cam_pan = ISLAND_MIDDLE


func _look_at_harbour() -> void:
	main.cam_target0 = harbour_target
	main.cam_pan = Vector3.ZERO


func _shot_start() -> void:
	# A fresh island, the whole of it in view, then the first Start Day
	main.get_node("UI").visible = true
	_look_at_island()
	main.cam_dist = 92.0
	zoom_to = 80.0
	turn = 4.0
	main._show_weather("perfect")
	get_tree().create_timer(1.2).timeout.connect(main._on_start_day)


func _shot_storm() -> void:
	main.get_node("UI").visible = false
	# Wait for the first day to finish, so its own weather doesn't replace the storm
	main.animating = false
	main._show_weather("storm")
	_look_at_island()
	main.cam_dist = 85.0
	zoom_to = 72.0
	turn = -5.0
	for n in main.boat_nodes:
		n.head_out(3.0, 1.5)


func _shot_talk() -> void:
	main._show_weather("normal")
	main.get_node("UI").visible = true
	# The first quiet-day banter scene, with its portraits
	var scene: Dictionary = Game.data.banter.list[0]
	Game.story.clear()
	for i in scene.lines.size():
		var who: String = scene.lines[i][0]
		Game.story.append({"day": 12, "who": who, "role": Game.role_of(who), "title": "Overheard on the docks" if i == 0 else "", "text": scene.lines[i][1]})
	Game.day = 12
	main.refresh()
	_look_at_harbour()
	main.cam_dist = 50.0
	zoom_to = 46.0
	turn = 2.0


func _shot_empire() -> void:
	Game.story.clear()
	main.get_node("UI").visible = false
	# Every building and a big fleet, like the title screen
	for key in Game.data.avenues:
		Game.built[key] = true
	Game.harbor_spaces = 12
	Game.counts["cray"] = 6
	Game.boats = []
	for kind in BIG_FLEET:
		for i in int(BIG_FLEET[kind][0]):
			Game.boats.append({"kind": kind, "zone": BIG_FLEET[kind][1]})
	Game.day = 240
	main._update_buildings()
	main._rebuild_boats()
	main._place_boats(0.01)
	main._show_weather("perfect")
	main.get_node("DeepSea").visible = false
	for label in main.find_children("*", "Label3D", true, false):
		label.visible = false
	main.cam_dist = 62.0
	zoom_to = 82.0
	turn = 7.0
	# Half way through, everyone sails to a new spot
	get_tree().create_timer(2.0).timeout.connect(func():
		main._shuffle_showcase_boats()
		# Ships sent on a voyage need a day they're back (the side panel reads it)
		for b in Game.boats:
			if b.zone == "voyage":
				b["back"] = Game.day + 3
		main._place_boats(4.0))


func _shot_win() -> void:
	main.get_node("UI").visible = true
	Game.cash = Game.island_price() + 4.2e7
	main.refresh()
	# Look straight at the middle of the island's land (measured from island_art.tscn) instead of the harbour,
	# from here to the end card. cam_pan isn't turned with the camera, so the island stays centred as it circles.
	_look_at_island()
	main.cam_dist = 112.0
	zoom_to = 105.0
	turn = 3.0
	# The real end screen, shown directly: buy_island() would delete your saved run
	get_tree().create_timer(1.2).timeout.connect(func():
		main.get_node("UI/EndScreen").visible = true
		main.get_node("UI/EndScreen/Box/Text").text = "YOU WIN\n\nYou bought the island on day 240.\nThe Crown has no hold on you now.")


func _shot_card() -> void:
	main.get_node("UI").visible = false
	turn = 4.0
	card.visible = true


# ---------- Captions, fades and the end card ----------

func _make_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var font: FontFile = load(HEADING_FONT)

	caption = Label.new()
	caption.add_theme_font_override("font", font)
	caption.add_theme_font_size_override("font_size", 58)
	caption.add_theme_color_override("font_color", Color(0.96, 0.82, 0.47))
	caption.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.12))
	caption.add_theme_constant_override("outline_size", 18)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.offset_left = 0.0
	caption.offset_right = 0.0
	caption.offset_top = 190.0
	layer.add_child(caption)

	card = ColorRect.new()
	card.color = Color(0.06, 0.09, 0.15, 0.82)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.visible = false
	layer.add_child(card)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	for line in [["FISHOPOLY", 130, Color(0.96, 0.82, 0.47)], ["Fish, scheme and buy the island from the Crown.", 34, Color(0.92, 0.9, 0.85)], ["Free on itch.io", 44, Color(0.96, 0.82, 0.47)]]:
		var l := Label.new()
		l.text = line[0]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", line[1])
		l.add_theme_color_override("font_color", line[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)

	fader = ColorRect.new()
	fader.color = Color(0, 0, 0, 1)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fader.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fader)


func _caption(text: String) -> void:
	caption.text = text
	caption.modulate.a = 0.0
	if text != "":
		create_tween().tween_property(caption, "modulate:a", 1.0, 0.6).set_delay(0.3)
