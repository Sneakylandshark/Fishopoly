extends SceneTree
## Headless test: every run is a different kind of player, rolled at the start of the run.
## Saving: how much of the coming bill (rent + tax) they keep back.
## Loans: how many Silent Partner covers they're happy to use up on purpose.
## Risk: how bold they are with deep sea, defecting, Visitors and bribes.
## Noise: how often they just do something random.
## Run: <godot console exe> --headless --path "<project>" -s res://tests/mixedplay.gd -- runs=50 seed=1000

var RUNS := 50
var SEED := 1000
var step := 0
var game: Node
# The robot's own dice, separate from the game's weather dice
var dice := RandomNumberGenerator.new()

# This run's player
var save := 0.0
var loans := 0
var risk := 0.0
var noise := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("runs="):
			RUNS = int(a.substr(5))
		elif a.begins_with("seed="):
			SEED = int(a.substr(5))
	game = root.get_node_or_null("/root/Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		root.add_child(game)


func _roll_player() -> void:
	# Saving: 0 = keeps back nothing, 1 = keeps back the whole coming bill, up to 1.5 = extra cushion
	save = dice.randf_range(0.0, 1.5)
	# Loans: 0 = never leans on the Silent Partner on purpose, up to 2 covers used on purpose
	loans = dice.randi_range(0, 2)
	# Risk: 0 = timid, 1 = reckless
	risk = dice.randf()
	# Noise: up to 30% of choices made without thinking
	noise = dice.randf_range(0.0, 0.3)


func _rand() -> bool:
	return dice.randf() < noise


func _process(_delta: float) -> bool:
	# Wait one frame so the rules script has loaded the balance file
	step += 1
	if step < 2:
		return false
	dice.seed = SEED * 13 + 5
	for r in RUNS:
		_roll_player()
		game.new_run(SEED + r, false)
		var t_open := {2: -1, 3: -1, 4: -1}
		var covers_used := 0
		var last_cause := "-"
		var end_cause := "-"
		var causes := []
		var peak := 0.0
		while not game.over and game.day < 600:
			if game.pending_push >= 0:
				# Bolder players defect at a lower dirty share
				var cb: int = game.covers_left()
				game.resolve_push(dice.randf() < 0.5 if _rand() else _dirty_share() >= 0.5 - 0.4 * risk)
				if game.covers_left() < cb:
					last_cause = "tribute"
					causes.append(last_cause)
			if game.investigation_due >= 0 and game.suspicion >= game.calloff_at:
				# Timid players pay the officials off; reckless ones sometimes gamble
				if dice.randf() > risk * 0.6:
					game.bribe()
			if game.pending_offer >= 0:
				var o: Dictionary = game.data.offers.list[game.pending_offer]
				if _rand():
					game.answer_offer(["a", "b", "later"][dice.randi() % 3])
				elif game.loan == 0 and game.cash - o.cost >= _reserve() and dice.randf() < 0.3 + 0.7 * risk:
					game.answer_offer("a" if dice.randf() < 0.5 else "b")
				else:
					game.answer_offer("later")
			_shop()
			var before: int = game.covers_left()
			# Sea conditions and boon picks: take a random one
			if not game.pending_pick.is_empty():
				game.answer_pick(randi() % max(game.pending_pick.options.size(), 1))
			var rep: Dictionary = game.start_day()
			var refused := false
			for line in rep.get("lines", []):
				if str(line).contains("refuses"):
					refused = true
			if game.covers_left() < before or refused:
				covers_used += 1
				last_cause = _cause(rep.get("lines", []))
				causes.append(last_cause)
			for line in rep.get("lines", []):
				if str(line).contains("Loan overdue"):
					end_cause = "overdue after " + last_cause
				elif str(line).contains("refuses"):
					end_cause = "refused: " + last_cause
			for t in [2, 3, 4]:
				if t_open[t] < 0 and game.tier_open(t):
					t_open[t] = game.day
			peak = max(peak, game.cash)
			if game.can_afford(game.island_price()):
				game.buy_island()
		var won: bool = game.over and game.log_lines.size() > 0 and game.log_lines[-1] == "You bought the island!"
		var result := "WIN" if won else ("TIMEOUT" if game.day >= 600 else "LOSS")
		var tier := 1
		for t in [2, 3, 4]:
			if t_open[t] >= 0:
				tier = t
		print("RUN seed=%d %s day=%d tier=%d save=%.2f loans=%d risk=%.2f noise=%.2f covers=%d defected=%s invest=%d peak=%d end=%s causes=%s" % [SEED + r, result, game.day, tier, save, loans, risk, noise, covers_used, str(game.defected), game.investigations, int(peak), end_cause.replace(" ", "_"), ",".join(causes)])
	return true


func _cause(lines: Array) -> String:
	# The biggest cost on a shortfall day: tax, rent, fine or storm repairs
	var cost := {"tax": 0.0, "rent": 0.0, "fine": 0.0, "storm": 0.0}
	var re := RegEx.new()
	for line in lines:
		var l := str(line)
		if l.begins_with("Bills:"):
			re.compile("rent \\$([\\d,]+) \\+ tax \\$([\\d,]+)")
			var m := re.search(l)
			if m:
				cost.rent += float(m.get_string(1).replace(",", ""))
				cost.tax += float(m.get_string(2).replace(",", ""))
		elif l.begins_with("INVESTIGATION"):
			re.compile("fined \\$([\\d,]+)")
			var m2 := re.search(l)
			if m2:
				cost.fine += float(m2.get_string(1).replace(",", ""))
		elif l.contains("repairs -$") or l.contains("gear of") or l.contains("cray pots: -"):
			re.compile("-\\$([\\d,]+)")
			var m3 := re.search(l)
			if m3:
				cost.storm += float(m3.get_string(1).replace(",", ""))
	var best := "other"
	var top := 0.0
	for k in cost:
		if cost[k] > top:
			top = cost[k]
			best = k
	return best


func _reserve() -> float:
	# Cash this player keeps back: rent always, plus their share of the tax
	var rent: float = game.next_rent()
	var bill: float = game.next_bill()
	var keep: float = rent + save * max(bill - rent, 0.0)
	# Players happy to use the Silent Partner spend it all while they have covers to spare
	if loans > 0 and game.covers_left() > int(game.data.silent_partner.covers) - loans:
		keep = 0.0
	return keep


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
	# Payback shopping like autoplay.gd, but keeping back this player's reserve
	var next_tier := _next_tier()
	var blocking: Array = game.tier_blockers(next_tier) if next_tier > 0 else []
	for k in 10:
		var reserve := _reserve()
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
			var afford := options.filter(func(o): return o[1] <= game.cash)
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
	# Boats: bolder players send boats deep at a lower storm-safety chance
	var need: float = 0.8 - 0.5 * risk
	for i in game.boats.size():
		var b: Dictionary = game.boats[i]
		var safe_chance: float = game.survive_chance() + (1.0 - game.survive_chance()) * game.home_chance()
		if (b.kind == "fish" or b.kind == "crab") and game.built.has("deep") and safe_chance >= need:
			game.set_zone(i, "deep")
		elif b.kind == "fish" and b.zone == "dock" and game.built.has("deep") and safe_chance >= need - 0.2:
			game.set_zone(i, "deep")
