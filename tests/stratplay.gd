extends SceneTree
## Headless test: robots that follow one strategy for the whole run.
## Run: <godot console exe> --headless --path "<project>" -s res://tests/stratplay.gd -- strat=clean runs=50 seed=1000
## Strategies:
##   plain  - buys best payback, saves for the whole bill, never hides ships (the old careful robot)
##   smart  - like plain, but hides dirty ships and pays officials off when investigators are coming
##   clean  - smart, but never builds smuggling, piracy or hidden moorings
##   dirty  - smart, rushes the dirty avenues and defects to the rival Crown
##   saver  - smart, keeps 1.5x the bill, only buys things that pay back within 40 days
##   rusher - smart, puts everything into opening the next tier as fast as possible
##   wildcat - plain, but pours every spare dollar into oil surveys from day 1

const DIRTY := ["smuggle", "piracy", "hiding"]

var STRAT := "plain"
var RUNS := 50
var SEED := 1000
# storm= overrides the daily storm chance for this test only (-1 = use balance.json)
var STORM := -1.0
# levy_scale= multiplies every Crown levy target for this test only (0 = levy off)
var LEVY_SCALE := 1.0
# decree_from= sets the first season with a decree for this test only (-1 = use balance.json)
var DECREE_FROM := -1
# crown= picks the starting Crown by id (e.g. turtle_admiral), or "random" (default: the Lord Admiral)
var CROWN := "lord_admiral"
# champion= picks the champion by id (e.g. banker), or "random" (default: random)
var CHAMPION := "random"
var step := 0
var game: Node
var dice := RandomNumberGenerator.new()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("strat="):
			STRAT = a.substr(6)
		elif a.begins_with("runs="):
			RUNS = int(a.substr(5))
		elif a.begins_with("seed="):
			SEED = int(a.substr(5))
		elif a.begins_with("storm="):
			STORM = float(a.substr(6))
		elif a.begins_with("levy_scale="):
			LEVY_SCALE = float(a.substr(11))
		elif a.begins_with("crown="):
			CROWN = a.substr(6)
		elif a.begins_with("champion="):
			CHAMPION = a.substr(9)
		elif a.begins_with("decree_from="):
			DECREE_FROM = int(a.substr(12))
	game = root.get_node_or_null("/root/Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		root.add_child(game)


func _smart() -> bool:
	return STRAT != "plain"


func _process(_delta: float) -> bool:
	# Wait one frame so the rules script has loaded the balance file
	step += 1
	if step < 2:
		return false
	dice.seed = SEED * 17 + 3
	if STORM >= 0.0:
		game.data.weather.storm_chance = STORM
	game.levy_scale = LEVY_SCALE
	if DECREE_FROM >= 0:
		game.data.levy.decree_from_season = DECREE_FROM
	for r in RUNS:
		game.new_run(SEED + r, false)
		var t_open := {2: -1, 3: -1, 4: -1}
		var covers := 0
		var last_cause := "-"
		var end_cause := "-"
		var peak := 0.0
		var oil_day := -1
		# The day cash first passes $1M and $10M (where a run snowballs)
		var m1 := -1
		var m10 := -1
		while not game.over and game.day < 600:
			if game.pending_push >= 0:
				var cb: int = game.covers_left()
				game.resolve_push(_defect())
				if game.covers_left() < cb:
					covers += 1
					last_cause = "tribute"
			if game.pending_offer >= 0:
				var o: Dictionary = game.data.offers.list[game.pending_offer]
				if game.loan == 0 and game.cash - o.cost >= _reserve():
					game.answer_offer("a" if dice.randf() < 0.5 else "b")
				else:
					game.answer_offer("later")
			_find_oil()
			_shop()
			_send_voyages()
			_use_favour()
			if _smart():
				_dodge_investigators()
			if not game.pending_pick.is_empty():
				game.answer_pick(_pick_boon())
			var before: int = game.covers_left()
			var rep: Dictionary = game.start_day()
			var lines: Array = rep.get("lines", [])
			var refused := false
			for line in lines:
				if str(line).contains("refuses"):
					refused = true
			if game.covers_left() < before or refused:
				covers += 1
				last_cause = _cause(lines)
			for line in lines:
				if str(line).contains("Loan overdue"):
					end_cause = "overdue_after_" + last_cause
				elif str(line).contains("refuses"):
					end_cause = "refused_" + last_cause
				elif str(line).contains("CROWN LEVY MISSED") and game.over:
					end_cause = "levy_strikes"
			for t in [2, 3, 4]:
				if t_open[t] < 0 and game.tier_open(t):
					t_open[t] = game.day
			peak = max(peak, game.cash)
			if m1 < 0 and game.cash >= 1000000.0:
				m1 = game.day
			if m10 < 0 and game.cash >= 10000000.0:
				m10 = game.day
			if oil_day < 0 and game.built.has("oil"):
				oil_day = game.day
			if game.can_afford(game.island_price()):
				game.buy_island()
		var won: bool = game.over and game.log_lines.size() > 0 and game.log_lines[-1] == "You bought the island!"
		var result := "WIN" if won else ("TIMEOUT" if game.day >= 600 else "LOSS")
		var tier := 1
		for t in [2, 3, 4]:
			if t_open[t] >= 0:
				tier = t
		print("RUN strat=%s seed=%d %s day=%d tier=%d t2=%d t3=%d t4=%d covers=%d defected=%s invest=%d peak=%d end=%s surveys=%d oilbuilt=%d pbribes=%d strikes=%d season=%d crown=%s start_crown=%s m1=%d m10=%d champion=%s favour=%d slow=%d wildcat=%s" % [STRAT, SEED + r, result, game.day, tier, t_open[2], t_open[3], t_open[4], covers, str(game.defected), game.investigations, int(peak), end_cause, game.surveys, oil_day, game.permit_bribes, game.strikes, game.season, game.crown.id, game.data.crowns.list[game.served[0]].id, m1, m10, game.champion().get("id", "-"), game.favour, int(game.stats.slow), str(game.wildcat or game.wildcat_ready_day > 0)])
		print("SEASONS seed=%d %s" % [SEED + r, " ".join(game.season_log.map(func(x): return str(int(x))))])
	return true


const DIRTY_BOONS := ["pirates_charter", "smugglers_map", "friendly_magistrate", "laundry_man", "silver_tongue"]


# Pick the boon this strategy likes best: dirty strategies want dirty boons, the rest avoid them
func _pick_boon() -> int:
	var opts: Array = game.pending_pick.options
	if game.pending_pick.kind == "crown":
		if CROWN == "random":
			return dice.randi_range(0, opts.size() - 1)
		for i in game.data.crowns.list.size():
			if game.data.crowns.list[i].id == CROWN:
				return i
		return 0
	if game.pending_pick.kind == "champion":
		for i in opts.size():
			if game.data.champions.list[int(opts[i].index)].id == CHAMPION:
				return i
		return dice.randi_range(0, opts.size() - 1)
	if game.pending_pick.kind == "advisor":
		return dice.randi_range(0, 1)
	if game.pending_pick.kind != "boon":
		return 0
	for i in opts.size():
		var id: String = game.data.boons.list[opts[i].index].id
		if (STRAT == "dirty") == (id in DIRTY_BOONS):
			return i
	return 0

func _find_oil() -> void:
	# Survey whenever it leaves the reserve intact; dirty-money strategies bribe the permit office
	# Most robots only hunt for oil once tier 2 is done (as before); the wildcat hunts from day 1
	if STRAT != "wildcat" and not game.tier_open(4):
		return
	if game.can_survey() and game.cash - game.survey_price() >= _reserve():
		# Dirty-money strategies use the crooked surveyor when they can
		game.survey(STRAT != "plain" and STRAT != "clean" and game.can_survey_crooked())
	if STRAT != "plain" and STRAT != "clean" and game.can_bribe_permit() and game.cash - game.permit_bribe_price() >= _reserve():
		game.bribe_permit()
	# The wildcat builds a cheap wildcat well as soon as the permit is through
	if STRAT == "wildcat" and game.can_build_wildcat() and game.cash - float(game.data.oil_search.wildcat_price) >= _reserve():
		game.build_wildcat()


func _send_voyages() -> void:
	# Any waiting smuggling or pirate ship takes a voyage; the dirty rusher likes long hauls best
	var tries := 0
	while tries < 10:
		tries += 1
		var pick := -1
		for i in game.board.size():
			if game.can_send(i):
				if pick < 0 or (STRAT == "dirty" and int(game.board[i].length) > int(game.board[pick].length)):
					pick = i
		if pick < 0:
			return
		game.send_voyage(pick)


func _use_favour() -> void:
	# A favour clears a strike first; otherwise it cancels a decree
	if game.can_favour_strike():
		game.favour_strike()
	elif game.can_favour_decree() and game.favour >= 2:
		game.favour_decree()


func _defect() -> bool:
	if STRAT == "dirty":
		return true
	if STRAT == "clean":
		return false
	return _dirty_share() >= 0.3


func _dodge_investigators() -> void:
	# Investigators coming: hide dirty ships in free berths, then pay officials off if still too suspicious.
	# No one coming: send hidden ships back out to earn.
	if game.investigation_due >= 0:
		for i in game.boats.size():
			var b: Dictionary = game.boats[i]
			if (b.kind == "smuggler" or b.kind == "pirate") and b.zone != "hidden":
				game.set_zone(i, "hidden")
		if game.suspicion >= game.calloff_at:
			game.bribe()
	else:
		for i in game.boats.size():
			var b: Dictionary = game.boats[i]
			if (b.kind == "smuggler" or b.kind == "pirate") and b.zone == "hidden":
				game.set_zone(i, "deep")


func _cause(lines: Array) -> String:
	# The biggest cost on a shortfall day
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
	var bill: float = game.next_bill()
	return bill * (1.5 if STRAT == "saver" else 1.0)


func _income_of(key: String) -> float:
	if key == "fish":
		return game.avg_per_day("fish") * min(game.count_boats("fish", "harbor"), game.harbor_spaces) + max(game.avg_per_day("fish_deep"), 0.0) * game.count_boats("fish", "deep")
	if key == "salvage":
		return game.avg_per_day("salvage") if game.units_owned("salvage") > 0 else 0.0
	return game.avg_per_day(key) * game.units_owned(key)


func _dirty_share() -> float:
	var dirty := 0.0
	for k in DIRTY:
		if game.built.has(k):
			dirty += game.avg_per_day(k) * game.units_owned(k)
	var total: float = game.income_estimate()
	return dirty / total if total > 0 else 0.0


func _next_tier() -> int:
	for t in [2, 3, 4]:
		if not game.tier_open(t):
			return t
	return 0


func _weight(key: String) -> float:
	# Lower = more wanted
	if STRAT == "dirty" and key in DIRTY:
		return 0.3
	return 1.0


func _shop() -> void:
	var next_tier := _next_tier()
	var blocking: Array = game.tier_blockers(next_tier) if next_tier > 0 else []
	# How hard this strategy pushes for the next tier's unlock
	var unlock_push := 0.05 if STRAT == "rusher" else 0.3
	for k in 10:
		var reserve := _reserve()
		var options := []
		if game.count_boats("fish", "harbor") < game.harbor_spaces:
			var p: float = game.fishing_boat_price()
			options.append([p / game.avg_per_day("fish"), p, func(): game.buy_fishing_boat(), p / game.avg_per_day("fish")])
		else:
			var p2: float = game.harbor_space_price()
			var pb: float = (p2 + game.fishing_boat_price()) / game.avg_per_day("fish")
			options.append([pb, p2, func(): game.expand_harbor(), pb])
		for key in game.data.avenues:
			var a: Dictionary = game.data.avenues[key]
			if STRAT == "clean" and key in DIRTY:
				continue
			if not game.built.has(key):
				# The oil platform needs the permit (at any tier); everything else needs its tier
				var can_open: bool = game.oil_approved() if key == "oil" else game.tier_open(int(a.tier))
				if not can_open:
					continue
				var c: float = game.build_price(key)
				var v: float = game.avg_per_day(key) if a.has("unit") else 20.0
				var push: float = unlock_push if blocking.size() > 0 and int(a.tier) == next_tier - 1 else 1.0
				options.append([c / max(v, 1.0) * push * _weight(key), c, func(): game.build(key), c / max(v, 1.0)])
				continue
			if a.has("unit") and game.can_buy_unit(key):
				var up: float = game.unit_price(key) / max(game.avg_per_day(key), 1.0)
				options.append([up * _weight(key), game.unit_price(key), func(): game.buy_unit(key), up])
		for key in ["fish"] + game.data.avenues.keys():
			if key != "fish" and not game.built.has(key):
				continue
			var inc := _income_of(key)
			for i in game.paths_for(key).size():
				if not game.can_upgrade(key, i):
					continue
				var path: Dictionary = game.paths_for(key)[i]
				var gain: float = inc * (path.per_level - 1.0) if path.effect == "income" or path.effect == "odds" else inc * 0.2
				var push: float = unlock_push if blocking.size() > 0 and game.tier_of(key) == next_tier - 1 and game.levels[key][i] < int(game.data.tiers.min_level[str(next_tier)]) else 1.0
				var pb2: float = game.upgrade_price(key, i) / max(gain, 0.5)
				options.append([pb2 * push * _weight(key), game.upgrade_price(key, i), func(): game.upgrade(key, i), pb2])
		if STRAT == "saver":
			# Savers skip anything slower than 40 days to pay back, unless it opens the next tier
			options = options.filter(func(o): return o[3] <= 40.0 or o[0] < o[3])
		options.sort_custom(func(a, b): return a[0] < b[0])
		var best = options[0] if options.size() > 0 else null
		if best == null or game.cash - best[1] < reserve:
			break
		best[2].call()
		next_tier = _next_tier()
		blocking = game.tier_blockers(next_tier) if next_tier > 0 else []
	# Boats: deep sea once storm safety reaches 60%
	for i in game.boats.size():
		var b: Dictionary = game.boats[i]
		var safe_chance: float = game.survive_chance() + (1.0 - game.survive_chance()) * game.home_chance()
		if (b.kind == "fish" or b.kind == "crab") and game.built.has("deep") and safe_chance >= 0.6:
			game.set_zone(i, "deep")
		elif b.kind == "fish" and b.zone == "dock" and game.built.has("deep") and safe_chance >= 0.4:
			game.set_zone(i, "deep")
