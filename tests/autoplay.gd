extends SceneTree
## Headless check: plays the real rules (Game autoload) with a simple robot.
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" -s res://tests/autoplay.gd

const RUNS := 60
# Set to true to print one run week by week
const TRACE := false
# CARELESS = buys the cheapest thing it can afford and ignores rent (a new player who skips the help)
var CARELESS := OS.get_cmdline_user_args().has("careless")

var step := 0
var game: Node


func _initialize() -> void:
	# Use the autoload if it exists, otherwise load the rules script directly
	game = root.get_node_or_null("/root/Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		root.add_child(game)


func _process(_delta: float) -> bool:
	# Wait one frame so the autoload has loaded the balance file
	step += 1
	if step < 2:
		return false
	var wins := 0
	var t2_days := []
	var t3 := 0
	var t4 := 0
	var defects := 0
	var win_days := []
	var loss_days := []
	for r in RUNS:
		# false = don't write a run log file for test runs
		game.new_run(r, false)
		while not game.over and game.day < 600:
			# Answer a rival Crown: defect only if a lot of income is dirty (the rival favours dirty avenues)
			if game.pending_push >= 0:
				game.resolve_push(_dirty_share() >= 0.3)
			# Tipped off: pay off officials if it can
			if game.investigation_due >= 0 and game.suspicion >= game.calloff_at:
				game.bribe()
			# Visitors: pick one of the two at random if it leaves money for the next bill, else Not now
			if game.pending_offer >= 0:
				var o: Dictionary = game.data.offers.list[game.pending_offer]
				if game.loan == 0 and game.cash - o.cost >= game.next_bill():
					game.answer_offer("a" if game.rng.randf() < 0.5 else "b")
				else:
					game.answer_offer("later")
			_shop()
			# Sea conditions and boon picks: take a random one
			if not game.pending_pick.is_empty():
				game.answer_pick(randi() % max(game.pending_pick.options.size(), 1))
			game.start_day()
			if TRACE and r == 0 and game.day % 7 == 0:
				print("day %d cash %d loan %d rent %d boats %s built %s pearl %d cray %d levels %s" % [game.day, game.cash, game.loan, game.rent_for_week(game.day / 7), str(game.boats.map(func(b): return b.kind[0] + b.zone[0])), str(game.built.keys()), game.pearl_spots, game.cray_ships, str(game.levels)])
			if game.can_afford(game.island_price()):
				game.buy_island()
		if game.built.has("salvage") or game.built.has("whaling") or game.built.has("treasure"):
			t2_days.append(game.day)
		if game.built.has("smuggle") or game.built.has("piracy") or game.built.has("hiding"):
			t3 += 1
		if game.built.has("oil"):
			t4 += 1
		if game.defected:
			defects += 1
		if game.over and game.cash >= 0 and game.loan == 0 and game.day < 600 and _won():
			wins += 1
			win_days.append(game.day)
		else:
			loss_days.append(game.day)
	win_days.sort()
	loss_days.sort()
	print("runs that built tier 2: %d, tier 3: %d, tier 4: %d, defected: %d" % [t2_days.size(), t3, t4, defects])
	print(("careless " if CARELESS else "careful ") + "runs %d  wins %d (%d%%)  median win day %s  median loss day %s" % [
		RUNS, wins, wins * 100 / RUNS,
		str(win_days[win_days.size() / 2]) if win_days.size() > 0 else "-",
		str(loss_days[loss_days.size() / 2]) if loss_days.size() > 0 else "-"])
	return true


func _won() -> bool:
	return game.log_lines.size() > 0 and game.log_lines[-1] == "You bought the island!"


func _income_of(key: String) -> float:
	# Rough earnings per day of everything owned in one avenue (used to value upgrades)
	if key == "fish":
		return game.avg_per_day("fish") * min(game.count_boats("fish", "harbor"), game.harbor_spaces) + max(game.avg_per_day("fish_deep"), 0.0) * game.count_boats("fish", "deep")
	if key == "salvage":
		return game.avg_per_day("salvage") if game.units_owned("salvage") > 0 else 0.0
	return game.avg_per_day(key) * game.units_owned(key)


func _dirty_share() -> float:
	var dirty := 0.0
	for k in ["smuggle", "piracy", "hiding"]:
		if game.built.has(k):
			dirty += game.avg_per_day(k) * game.units_owned(k)
	var total: float = game.income_estimate()
	return dirty / total if total > 0 else 0.0


func _shop() -> void:
	# A payback robot: keep a week of rent, then buy whatever pays for itself fastest.
	# Things that open tier 2 get a push (a real player would aim for the unlock).
	var next_tier := _next_tier()
	var blocking: Array = game.tier_blockers(next_tier) if next_tier > 0 else []
	for k in 10:
		var reserve: float = game.next_rent()
		var options := []
		if game.count_boats("fish", "harbor") < game.harbor_spaces:
			var p: float = game.fishing_boat_price()
			options.append([p / game.avg_per_day("fish"), p, func(): game.buy_fishing_boat()])
		else:
			var p2: float = game.harbor_space_price()
			options.append([(p2 + game.fishing_boat_price()) / game.avg_per_day("fish"), p2, func(): game.expand_harbor()])
		for key in game.data.avenues:
			var a: Dictionary = game.data.avenues[key]
			if not game.built.has(key):
				if not game.tier_open(int(a.tier)):
					continue
				var c: float = game.build_price(key)
				var v: float = game.avg_per_day(key) if a.has("unit") else 20.0
				var push: float = 0.3 if blocking.size() > 0 and int(a.tier) == next_tier - 1 else 1.0
				options.append([c / max(v, 1.0) * push, c, func(): game.build(key)])
				continue
			if a.has("unit") and game.can_buy_unit(key):
				options.append([game.unit_price(key) / max(game.avg_per_day(key), 1.0), game.unit_price(key), func(): game.buy_unit(key)])
		for key in ["fish"] + game.data.avenues.keys():
			if key != "fish" and not game.built.has(key):
				continue
			var inc := _income_of(key)
			for i in game.paths_for(key).size():
				if not game.can_upgrade(key, i):
					continue
				var path: Dictionary = game.paths_for(key)[i]
				var gain: float = inc * (path.per_level - 1.0) if path.effect == "income" or path.effect == "odds" else inc * 0.2
				var push: float = 0.3 if blocking.size() > 0 and game.tier_of(key) == next_tier - 1 and game.levels[key][i] < int(game.data.tiers.min_level[str(next_tier)]) else 1.0
				options.append([game.upgrade_price(key, i) / max(gain, 0.5) * push, game.upgrade_price(key, i), func(): game.upgrade(key, i)])
		if CARELESS:
			options.sort_custom(func(a, b): return a[1] < b[1])
			reserve = 0.0
		else:
			options.sort_custom(func(a, b): return a[0] < b[0])
		var best = options[0] if options.size() > 0 else null
		if best == null or game.cash - best[1] < reserve:
			break
		best[2].call()
		next_tier = _next_tier()
		blocking = game.tier_blockers(next_tier) if next_tier > 0 else []
	# Send boats deep once the hull is strong enough
	for i in game.boats.size():
		var b: Dictionary = game.boats[i]
		# Storm safety = survives, or the lighthouse gets it home
		var safe_chance: float = game.survive_chance() + (1.0 - game.survive_chance()) * game.home_chance()
		if (b.kind == "fish" or b.kind == "crab") and game.built.has("deep") and safe_chance >= 0.6:
			game.set_zone(i, "deep")
		elif b.kind == "fish" and b.zone == "dock" and game.built.has("deep") and safe_chance >= 0.4:
			game.set_zone(i, "deep")


func _next_tier() -> int:
	for t in [2, 3, 4]:
		if not game.tier_open(t):
			return t
	return 0
