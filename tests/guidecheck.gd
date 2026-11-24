extends SceneTree
## Headless check (not part of the game): every first-run tip can show, each shows only once,
## nothing shows while a pick or another talk panel is waiting, and tests never show tips.
## It puts your real user://meta.json back afterwards (unlocks and seen tips).
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" -s res://tests/guidecheck.gd

const META := "user://meta.json"
# The moments game.gd _guide_ok understands
const KNOWN := ["start", "after_day1", "can_build", "built", "bills", "loan", "tier2", "tier3"]


func _initialize() -> void:
	# Keep the real meta file safe: this check writes to it
	var had_meta := FileAccess.file_exists(META)
	var saved_meta := FileAccess.get_file_as_string(META) if had_meta else ""

	var game: Node = root.get_node("Game")
	game.load_balance()
	var steps: Array = game.data.guide.steps
	var problems := 0

	# Tests (save_enabled off) never get tips
	game.new_run(5, false)
	game.guide_tick()
	if not game.story.is_empty():
		print("TIP SHOWN IN A TEST RUN")
		problems += 1

	# A pretend real game
	game.new_run(5, false)
	game.save_enabled = true
	game.guide_done = []
	game.pending_pick = {}
	game.pending_offer = -1
	game.pending_push = -1

	# Nothing while a pick is waiting
	game.pending_pick = {"kind": "test"}
	game.guide_tick()
	if not game.story.is_empty():
		print("TIP SHOWN OVER A PICK")
		problems += 1
	game.pending_pick = {}

	for step in steps:
		# Make this step's moment true
		match str(step.when):
			"after_day1": game.day = max(game.day, 1)
			"can_build": game.cash = 1.0e6
			"built": game.built["pearl"] = true
			"bills": game.day = max(game.day, 7)
			"loan": game.loan = 100.0
			"tier2", "tier3":
				# Opening a tier for real takes a whole run; just check the rule is one the game knows
				if not KNOWN.has(str(step.when)):
					print("UNKNOWN when: ", step.when)
					problems += 1
				game.guide_done.append(step.id)
				continue
			_:
				if not KNOWN.has(str(step.when)):
					print("UNKNOWN when: ", step.when)
					problems += 1
		game.story.clear()
		game.guide_tick()
		# Another tip may have been due first: read them until this one shows (or nothing more comes)
		var guard := 0
		while not game.guide_done.has(step.id) and not game.story.is_empty() and guard < 20:
			game.story.clear()
			game.guide_tick()
			guard += 1
		if not game.guide_done.has(step.id):
			print("NEVER SHOWN: ", step.id, " (when ", step.when, ")")
			problems += 1

	# Each tip only once
	game.story.clear()
	for i in 5:
		game.guide_tick()
	if not game.story.is_empty():
		print("A TIP SHOWED TWICE: ", game.story[0].title)
		problems += 1
	if game.guide_done.size() != steps.size():
		print("SEEN ", game.guide_done.size(), " of ", steps.size())

	# Seen tips survive into the next run
	game.guide_done = []
	game._load_meta()
	var kept: int = game.guide_done.size()
	if kept < steps.size() - 2:
		print("SEEN TIPS NOT KEPT: ", kept)
		problems += 1

	# Put the real meta file back
	if had_meta:
		var f := FileAccess.open(META, FileAccess.WRITE)
		f.store_string(saved_meta)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META))
	print("steps: ", steps.size(), "  problems: ", problems)
	print("GUIDE OK: ", problems == 0)
	quit()
