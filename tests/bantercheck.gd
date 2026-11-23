extends SceneTree
## Headless check (not part of the game): every banter scene is well formed, every speaker has a role and a
## portrait, every scene can be reached, and banter turns up in a long simulated run without crowding other story.
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" -s res://tests/bantercheck.gd

const PORTRAIT_DIR := "res://assets/portraits/"


func _slug(who: String) -> String:
	var slug := ""
	for ch in who.to_lower().replace("'", ""):
		slug += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while slug.contains("__"):
		slug = slug.replace("__", "_")
	return slug.trim_prefix("_").trim_suffix("_")


func _initialize() -> void:
	var game: Node = root.get_node("Game")
	game.load_balance()
	game.new_run(1234, false)
	var b: Dictionary = game.data.banter
	var problems := 0
	var ids := {}
	for scene in b.list:
		if ids.has(scene.id):
			print("DUPLICATE id ", scene.id)
			problems += 1
		ids[scene.id] = true
		for line in scene.lines:
			var who: String = line[0]
			if game.role_of(who) == "":
				print("NO ROLE: ", who, " in ", scene.id)
				problems += 1
			if not ResourceLoader.exists(PORTRAIT_DIR + _slug(who) + ".png"):
				print("NO PORTRAIT: ", who, " in ", scene.id)
				problems += 1
		# Make every rule true, then the scene must pass
		for rule in scene.needs:
			var p: PackedStringArray = str(rule).split(":")
			match p[0]:
				"day": game.day = max(game.day, int(p[1]))
				"built": game.built[p[1]] = true
				"advisor": game.advisors_met[p[1]] = p[2] if p.size() > 2 else "a"
				"offer": game.offers_done[p[1]] = p[2] if p.size() > 2 else "a"
				"champion":
					for i in game.data.champions.list.size():
						if game.data.champions.list[i].name == p[1]:
							game.champion_index = i
				"loan": game.loan = 100.0
				"suspicion": game.suspicion = float(p[1])
		if not game._banter_ok(scene, {"weather": "storm"}):
			print("UNREACHABLE: ", scene.id)
			problems += 1
		game.new_run(1234, false)
	print("scenes: ", b.list.size(), "  problems: ", problems)

	# A long run where everything is met, to see how often banter turns up
	game.new_run(99, false)
	for k in game.data.advisors.list:
		game.advisors_met[k] = "a"
	for o in game.data.offers.list:
		game.offers_done[o.id] = "b"
	game.champion_index = 0
	var scenes_seen := 0
	var crowded := 0
	for d in 120:
		game.story.clear()
		game.banter_last = min(game.banter_last, game.day)
		var before: int = game.banter_done.size()
		game.day += 1
		game._banter_tick({"weather": "normal"})
		if game.banter_done.size() > before:
			scenes_seen += 1
			if game.story.size() > 4:
				crowded += 1
	print("120 quiet days: ", scenes_seen, " scenes played, ", crowded, " longer than 4 lines")
	print("BANTER OK: ", problems == 0 and scenes_seen > 10)
	quit()
