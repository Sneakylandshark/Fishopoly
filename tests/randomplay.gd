extends SceneTree
## Headless test: the careful robot, but each decision is random with chance R.
## R = 0 plays like autoplay.gd; R = 1 makes every choice at random.
## Run: <godot console exe> --headless --path "<project>" -s res://tests/randomplay.gd -- r=0.5 runs=40 seed=1000

var R := 0.0
var RUNS := 40
var SEED := 1000
# taxsave = keep back the whole next bill (rent + tax), not just rent
var TAXSAVE := false
# idle = never buys anything, only presses Next Day (answers pop-ups with the default)
var IDLE := false
# allin = keeps nothing back for bills; spends every dollar on the best payback and lets the Silent Partner cover bills
var ALLIN := false
var step := 0
var game: Node


func _initialize() -> void:
	# Read r=, runs= and seed= from the user args after --
	for a in OS.get_cmdline_user_args():
		if a.begins_with("r="):
			R = float(a.substr(2))
		elif a.begins_with("runs="):
			RUNS = int(a.substr(5))
		elif a == "allin":
			ALLIN = true
		elif a == "idle":
			IDLE = true
		elif a == "taxsave":
			TAXSAVE = true
		elif a.begins_with("seed="):
			SEED = int(a.substr(5))
	game = root.get_node_or_null("/root/Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		root.add_child(game)


# The robot's own dice, separate from the game's weather dice
var dice := RandomNumberGenerator.new()


func _rand() -> bool:
	return dice.randf() < R


func _process(_delta: float) -> bool:
	# Wait one frame so the rules script has loaded the balance file
	step += 1
	if step < 2:
		return false
	dice.seed = SEED * 7 + int(R * 1000)
	for r in RUNS:
		game.new_run(SEED + r, false)
		var t_open := {2: -1, 3: -1, 4: -1}
		var storms := 0
		while not game.over and game.day < 600:
			if game.pending_push >= 0:
				game.resolve_push(dice.randf() < 0.5 if _rand() else _dirty_share() >= 0.3)
			if game.investigation_due >= 0:
				if _rand():
					if dice.randf() < 0.5:
						game.bribe()
				elif game.suspicion >= game.calloff_at:
					game.bribe()
			if game.pending_offer >= 0:
				var o: Dictionary = game.data.offers.list[game.pending_offer]
				if _rand():
					game.answer_offer(["a", "b", "later"][dice.randi() % 3])
				elif game.loan == 0 and game.cash - o.cost >= game.next_bill():
					game.answer_offer("a" if dice.randf() < 0.5 else "b")
				else:
					game.answer_offer("later")
			if not IDLE:
				_shop()
			# Sea conditions and boon picks: take a random one
			if not game.pending_pick.is_empty():
				game.answer_pick(randi() % max(game.pending_pick.options.size(), 1))
			var rep: Dictionary = game.start_day()
			if str(rep.get("weather", "")) == "storm":
				storms += 1
			for t in [2, 3, 4]:
				if t_open[t] < 0 and game.tier_open(t):
					t_open[t] = game.day
			if game.can_afford(game.island_price()):
				game.buy_island()
		var won: bool = game.over and game.log_lines.size() > 0 and game.log_lines[-1] == "You bought the island!"
		var result := "WIN" if won else ("TIMEOUT" if game.day >= 600 else "LOSS")
		var tier := 1
		for t in [2, 3, 4]:
			if t_open[t] >= 0:
				tier = t
		# Last few log lines before a loss, to see what tipped it over
		var tail := ""
		if result == "LOSS":
			var n: int = game.log_lines.size()
			for i in range(max(0, n - 6), n):
				tail += " | " + str(game.log_lines[i]).substr(0, 90)
		print("RUN r=%.2f seed=%d %s day=%d tier=%d t2=%d t3=%d t4=%d defected=%s invest=%d storms=%d%s" % [R, SEED + r, result, game.day, tier, t_open[2], t_open[3], t_open[4], str(game.defected), game.investigations, storms, tail])
	return true


func _income_of(key: String) -> float:
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


func _next_tier() -> int:
	for t in [2, 3, 4]:
		if not game.tier_open(t):
			return t
	return 0


func _shop() -> void:
	# Same payback shopping as autoplay.gd; with chance R a purchase is a random affordable option instead
	var next_tier := _next_tier()
	var blocking: Array = game.tier_blockers(next_tier) if next_tier > 0 else []
	for k in 10:
		var reserve: float = 0.0 if ALLIN else (game.next_bill() if TAXSAVE else game.next_rent())
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
		var best = null
		if _rand():
			# Random player: any option it can afford right now, and it may ignore the rent reserve
			var afford := options.filter(func(o): return o[1] <= game.cash)
			if dice.randf() < 0.5:
				reserve = 0.0
			if afford.size() > 0:
				best = afford[dice.randi() % afford.size()]
		else:
			options.sort_custom(func(a, b): return a[0] < b[0])
			best = options[0] if options.size() > 0 else null
		if best == null or game.cash - best[1] < reserve:
			break
		best[2].call()
		next_tier = _next_tier()
		blocking = game.tier_blockers(next_tier) if next_tier > 0 else []
	# Boats: careful = send deep once safe enough; random = any allowed zone
	for i in game.boats.size():
		var b: Dictionary = game.boats[i]
		if _rand():
			if b.kind == "fish":
				game.set_zone(i, ["harbor", "dock", "deep"][dice.randi() % 3])
			elif b.kind == "crab":
				game.set_zone(i, ["harbor", "deep"][dice.randi() % 2])
			elif b.kind == "smuggler" or b.kind == "pirate":
				game.set_zone(i, ["deep", "hidden"][dice.randi() % 2])
			continue
		var safe_chance: float = game.survive_chance() + (1.0 - game.survive_chance()) * game.home_chance()
		if (b.kind == "fish" or b.kind == "crab") and game.built.has("deep") and safe_chance >= 0.6:
			game.set_zone(i, "deep")
		elif b.kind == "fish" and b.zone == "dock" and game.built.has("deep") and safe_chance >= 0.4:
			game.set_zone(i, "deep")
