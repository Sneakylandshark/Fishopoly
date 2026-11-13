extends SceneTree
## Headless check of every champion building: for each champion, own everything, build and max their building,
## then play 28 days and print what it earned and what it changed.
## Run: <godot console exe> --headless --path "<project>" -s res://tests/cbcheck.gd

var step := 0
var game: Node


func _initialize() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)


func _process(_delta: float) -> bool:
	# Wait one frame so the rules script has loaded the balance file
	step += 1
	if step < 2:
		return false
	for ci in game.data.champions.list.size():
		_check(ci)
	print("CBCHECK DONE")
	return true


func _check(ci: int) -> void:
	game.new_run(500 + ci, false)
	# Answer the start picks; take this champion when it's offered
	var guard := 0
	while not game.pending_pick.is_empty() and guard < 10:
		guard += 1
		var p: Dictionary = game.pending_pick
		var choice := 0
		if p.kind == "champion":
			for i in p.options.size():
				if int(p.options[i].index) == ci:
					choice = i
		game.answer_pick(choice)
	var cid: String = game.champion().get("id", "-")
	var key: String = game.champion_building()
	if key == "":
		print("CB FAIL champion=%s has no building" % cid)
		return
	var a: Dictionary = game.data.avenues[key]
	# Own every ordinary avenue with a few units, every upgrade maxed, so every tier is open
	game.cash = 1.0e12
	game.laundering = true
	game.oil_ready_day = 0
	for k in game.data.avenues:
		if game.is_champion_building(k):
			continue
		game.built[k] = true
		if game.data.avenues[k].has("unit"):
			for n in 3:
				game._add_unit(k)
	for k in ["fish"] + game.data.avenues.keys():
		if k != "fish" and game.is_champion_building(k):
			continue
		for i in game.base_paths(k).size():
			game.levels[k][i] = game.path_max_level(k, i)
	# Numbers the building's upgrades change, before it's built
	var before := _modifiers()
	var others_blocked := true
	for k in game.data.avenues:
		if game.is_champion_building(k) and k != key and game.can_build(k):
			others_blocked = false
	var ok: bool = game.build(key)
	for i in a.paths.size():
		while game.upgrade(key, i):
			pass
	var after := _modifiers()
	# Buy a few boats and units for real, so the Shipyard has spending to earn on
	for n in 3:
		game.buy_fishing_boat()
		game.buy_unit("crab")
		game.buy_unit("whaling")
	var changed := []
	for m in before:
		if abs(after[m] - before[m]) > 0.000001:
			changed.append("%s %s -> %s" % [m, str(snapped(before[m], 0.0001)), str(snapped(after[m], 0.0001))])
	# Play 28 days
	var start_day: int = game.day + 1
	for d in 28:
		game.cash = max(game.cash, 1.0e12)
		game.suspicion = min(game.suspicion, 10.0)
		if game.pending_push >= 0:
			game.resolve_push(false)
		if game.pending_offer >= 0:
			game.answer_offer("later")
		while not game.pending_pick.is_empty():
			game.answer_pick(0)
		for i in range(game.board.size() - 1, -1, -1):
			if game.can_send(i):
				game.send_voyage(i)
		game.start_day()
		if game.over:
			break
	var earned: float = game.history_total(a.name, start_day)
	var total: float = game.history_total("Clean money", start_day) + game.history_total("Laundered", start_day)
	print("CB champion=%s building=%s built=%s others_blocked=%s levels=%s earned_28d=%s share=%.4f" % [cid, key, str(ok), str(others_blocked), str(game.levels[key]), game.money(earned), earned / max(total, 1.0)])
	print("   changes: %s" % ("; ".join(changed) if not changed.is_empty() else "none"))


func _modifiers() -> Dictionary:
	# Every number a champion building upgrade can change
	var m := {}
	m["launder_rate"] = game.launder_rate()
	m["upgrade_price_pearl"] = game.upgrade_price("pearl", 0) if game.levels.pearl[0] < 99 else 0.0
	m["crab_boat_price"] = game.unit_price("crab")
	m["fishing_boat_price"] = game.fishing_boat_price()
	m["fish_income_mult"] = game.income_mult("fish")
	m["cb_hedge"] = game.cb_value("hedge")
	m["cb_wrecks"] = game.cb_value("wrecks")
	m["cb_fade"] = game.cb_value("fade")
	m["cb_voyage_pay"] = game.cb_value("voyage_pay")
	m["cb_outfit"] = game.cb_value("outfit")
	return m
