extends Node
## The title screen: New Run, Continue, Settings, Quit.
## Behind the menu, main.tscn runs in showcase mode on a pretend end-game island with every building and a big fleet.

const MAIN_SCENE := "res://scenes/main.tscn"
const SETTINGS_PATH := "user://settings.cfg"
# The pretend end-game fleet: kind -> [how many, starting zone]
const SHOWCASE_FLEET := {
	"fish": [14, "harbor"],
	"crab": [8, "harbor"],
	"whale": [4, "deep"],
	"barge": [4, "harbor"],
	"smuggler": [8, "harbor"],
	"pirate": [6, "harbor"],
	"rig": [4, "harbor"],
}

var settings := ConfigFile.new()

@onready var continue_button: Button = $Menu/Panel/Box/Continue
@onready var settings_panel: PanelContainer = $Menu/SettingsPanel
@onready var fullscreen: CheckButton = $Menu/SettingsPanel/Box/Fullscreen
@onready var volume: HSlider = $Menu/SettingsPanel/Box/Volume
@onready var confirm: ConfirmationDialog = $Menu/NewRunConfirm


func _ready() -> void:
	_load_settings()
	_fill_end_game()
	# The moving island goes in first, so the menu draws on top of it
	var island: Node = load(MAIN_SCENE).instantiate()
	island.showcase = true
	add_child(island)
	move_child(island, 0)

	$Menu/Panel/Box/NewRun.pressed.connect(_on_new_run)
	continue_button.pressed.connect(_on_continue)
	$Menu/Panel/Box/Settings.pressed.connect(func(): settings_panel.visible = true)
	$Menu/Panel/Box/Quit.pressed.connect(func(): get_tree().quit())
	$Menu/SettingsPanel/Box/Back.pressed.connect(_close_settings)
	fullscreen.toggled.connect(_set_fullscreen)
	volume.value_changed.connect(_set_volume)
	confirm.confirmed.connect(_start_new_run)

	# Continue only works when there's a saved run
	continue_button.disabled = not Game.has_save()
	if Game.has_save():
		continue_button.text = "Continue (day %d)" % int(Game._read_save().get("day", 0))


func _fill_end_game() -> void:
	# Game starts a real run (and a log file) when the game opens. Swap it for a quiet one with no log or save,
	# and delete that first log file, which would otherwise sit empty in run_logs.
	var stray: String = Game.log_path
	Game.new_run(-1, false)
	if stray != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stray))
	# Every building, with a random champion's building on the champion plot
	for key in Game.data.avenues:
		Game.built[key] = true
	# Taken the proper way, so the champion's own upgrade slots exist
	Game._take_champion(randi() % Game.data.champions.list.size())
	Game.harbor_spaces = 12
	Game.counts["cray"] = 6
	Game.pending_pick = {}
	Game.boats = []
	for kind in SHOWCASE_FLEET:
		for i in int(SHOWCASE_FLEET[kind][0]):
			Game.boats.append({"kind": kind, "zone": SHOWCASE_FLEET[kind][1]})


func _on_new_run() -> void:
	# A saved run would be lost, so ask first
	if Game.has_save():
		confirm.dialog_text = "You have a run in progress (day %d).\nStarting a new run deletes it." % int(Game._read_save().get("day", 0))
		confirm.popup_centered()
		return
	_start_new_run()


func _start_new_run() -> void:
	Game.delete_save()
	Game.new_run()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_continue() -> void:
	# A real new run offers to carry on the saved one; take that offer straight away
	Game.new_run()
	if Game.pending_pick.get("kind", "") == "continue":
		Game.answer_pick(0)
	get_tree().change_scene_to_file(MAIN_SCENE)


# ---------- Settings ----------

func _load_settings() -> void:
	settings.load(SETTINGS_PATH)
	var full: bool = settings.get_value("display", "fullscreen", false)
	var vol: float = settings.get_value("audio", "volume", 1.0)
	fullscreen.set_pressed_no_signal(full)
	volume.set_value_no_signal(vol)
	_apply_fullscreen(full)
	_apply_volume(vol)


func _set_fullscreen(on: bool) -> void:
	_apply_fullscreen(on)
	settings.set_value("display", "fullscreen", on)


func _set_volume(v: float) -> void:
	_apply_volume(v)
	settings.set_value("audio", "volume", v)


func _apply_fullscreen(on: bool) -> void:
	# Headless test runs have no window to change
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.0001)))


func _close_settings() -> void:
	settings.save(SETTINGS_PATH)
	settings_panel.visible = false
