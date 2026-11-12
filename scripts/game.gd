extends Node
## The rules of Fishopoly: money, weather, bills, loans, tiers, Crowns, suspicion, news.
## No visuals here. The main scene reads this and draws it.
## All numbers come from res://data/balance.json.

signal changed
signal day_finished(report: Dictionary)
signal run_over(won: bool, reason: String)

const BALANCE_PATH := "res://data/balance.json"
# Avenues whose units are ships on the water (stored in "boats"), and the boat kind for each
const SHIP_KIND := {"crab": "crab", "salvage": "barge", "whaling": "whale", "smuggle": "smuggler", "piracy": "pirate", "oil": "rig"}
# Avenues whose units are just counted (not ships you can see)
const COUNTED := ["pearl", "cray", "treasure", "hiding"]

var data: Dictionary = {}
var rng := RandomNumberGenerator.new()

var day := 0
var cash := 0.0
var loan := 0.0
var loan_due := 0
# Silent Partner warnings: covers used so far (each one is a warning), and the day of the last cover or cleared warning
var warnings := 0
var warning_day := 0
# Interest multiplier for the loan you have now (rises with each warning)
var loan_mult := 1.0
# Finding oil: surveys paid for, whether oil was found, and the day the Crown's permit comes through
var surveys := 0
var oil_found := false
var permit_day := -1
var permit_bribes := 0
# Dirty money earned this week and last week (sets the price of permit bribes)
var week_dirty := 0.0
var last_week_dirty := 0.0
# Roguelite luck: this run's sea conditions, boons taken, and the choice waiting on screen
# pending_pick = {} when nothing is waiting, else {"kind": "conditions" or "boon", "title", "text", "options": [{"name", "text", "index"}]}
var conditions_now: Array = []
var boons_taken: Array = []
var pending_pick: Dictionary = {}
var tiers_rewarded: Dictionary = {}
# Random events: the one you've been warned about ({"index", "day"} or {}), and temporary effects [{"perk", "mult" or "add", "until"}]
var event_due: Dictionary = {}
var active_effects: Array = []
var forced_storm_until := -1
var week_income := 0.0
# Crown levies: the season number, what you've earned this season, strikes so far and this season's decree
var season := 1
var season_earned := 0.0
var strikes := 0
var decree: Dictionary = {}
# What you earned in each finished season (for tests and the run log)
var season_log: Array = []
# Tests can scale every levy target (1 = as in balance.json)
var levy_scale := 1.0
# This season's levy multiplier (staying loyal when the rival pushes raises it)
var levy_mult := 1.0
# Clean money earned this week (only clean money is taxed)
var week_taxable := 0.0
var last_week := 0.0
var last_storm := 0
# Weather rolled ahead of time so the Weather Bureau can forecast it: [{w, u, v}] for tomorrow, the day after
var upcoming: Array = []
var harbor_spaces := 0
var harbor_buys := 0
var over := false
var price := 0.0

# Every boat is {"kind": ..., "zone": "harbor", "deep" or "dock"}.
# Fishing and crab boats can be moved; the others always work where they belong.
var boats: Array = []
var counts: Dictionary = {}
var built: Dictionary = {}
var laundering := false
# Perks bought from visitors' offers, e.g. "income_pearl" -> 1.15, "survive_add" -> 0.2
var perks: Dictionary = {}
# Offers answered: id -> "a" or "b". offer_order is the queue (Later moves an offer to the back).
var offers_done: Dictionary = {}
var offer_order: Array = []
# The offer waiting for an answer (index into data.offers.list), or -1
var pending_offer := -1
# Upgrade levels: "fish" -> [0, 0, 0], "pearl" -> [...], and so on
var levels: Dictionary = {}
var wrecks := 0

# Crowns, suspicion, news
var crown: Dictionary = {}
var defected := false
# Indexes into data.crowns.list: the Crowns you have served, and the rival pushing right now
var served: Array = []
var rival_index := -1
var push_index := 0
var pending_push := -1
var suspicion := 0.0
var investigations := 0
# Day the tipped-off investigators arrive (-1 = none coming)
var investigation_due := -1
# Suspicion must be under this when they arrive, or they investigate
var calloff_at := 0.0
var bribes := 0
var news: Dictionary = {}

var log_lines: Array = []
var log_file: FileAccess = null
var log_path := ""


func _ready() -> void:
	load_balance()
	# Headless test runs don't write log files
	new_run(-1, DisplayServer.get_name() != "headless")


func load_balance() -> void:
	var f := FileAccess.open(BALANCE_PATH, FileAccess.READ)
	if f == null:
		push_error("Can't open " + BALANCE_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("balance.json has a typo (check commas and brackets)")
		return
	data = parsed


func new_run(seed: int = -1, write_log: bool = true) -> void:
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	day = 0
	cash = data.start.cash
	loan = 0.0
	loan_due = 0
	warnings = 0
	warning_day = 0
	loan_mult = 1.0
	surveys = 0
	oil_found = false
	permit_day = -1
	permit_bribes = 0
	week_dirty = 0.0
	last_week_dirty = 0.0
	week_income = 0.0
	week_taxable = 0.0
	last_week = 0.0
	last_storm = 0
	harbor_spaces = int(data.start.harbor_spaces)
	harbor_buys = 0
	over = false
	price = data.island_price
	boats = []
	for i in int(data.start.fishing_boats):
		boats.append({"kind": "fish", "zone": "harbor"})
	counts = {}
	for k in COUNTED:
		counts[k] = 0
	built = {}
	laundering = false
	perks = {}
	offers_done = {}
	offer_order = range(data.offers.list.size())
	pending_offer = -1
	upcoming = []
	levels = {"fish": _zeros(data.fishing_paths.size())}
	for key in data.avenues:
		levels[key] = _zeros(data.avenues[key].paths.size())
	wrecks = 0
	# The Lord Admiral until the player picks a Crown (right after the sea conditions)
	crown = data.crowns.list[0]
	served = [0]
	rival_index = -1
	defected = false
	push_index = 0
	pending_push = -1
	suspicion = 0.0
	investigations = 0
	investigation_due = -1
	bribes = 0
	news = {}
	conditions_now = []
	boons_taken = []
	pending_pick = {}
	tiers_rewarded = {}
	event_due = {}
	active_effects = []
	forced_storm_until = -1
	# Visitors come in a random order each run
	_shuffle(offer_order)
	_fill_forecast()
	_open_log(write_log)
	log_lines = []
	season = 1
	season_earned = 0.0
	strikes = 0
	decree = {}
	season_log = []
	levy_mult = 1.0
	_say("Day 0. You own one small boat and a rock. %s owns the island and wants %s for it." % [crown.name, money(price)])
	_say("CROWN LEVY: earn %s by day %d. Miss a levy and you're fined and get a strike; %d strikes and the Crown takes the island back." % [money(levy_target()), season_end_day(), int(data.levy.max_strikes)])
	_draw_conditions()


func _zeros(n: int) -> Array:
	var a := []
	a.resize(n)
	a.fill(0)
	return a


# ---------- Run log file (so a run can be checked afterwards) ----------

func _open_log(enabled: bool) -> void:
	if log_file != null:
		log_file.close()
		log_file = null
	log_path = ""
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute("user://run_logs")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	log_path = "user://run_logs/run_%s.txt" % stamp
	log_file = FileAccess.open(log_path, FileAccess.WRITE)


func _write(line: String) -> void:
	if log_file != null:
		log_file.store_line(line)
		log_file.flush()


# ---------- Counting and prices ----------

func island_price() -> float:
	return price


func count_boats(kind: String, zone: String = "") -> int:
	var n := 0
	for b in boats:
		if b.kind == kind and (zone == "" or b.zone == zone):
			n += 1
	return n


func units_owned(key: String) -> int:
	if SHIP_KIND.has(key):
		return count_boats(SHIP_KIND[key])
	return int(counts.get(key, 0))


func avg_level(key: String) -> float:
	var l: Array = levels[key]
	var total := 0
	for x in l:
		total += x
	return float(total) / l.size()


func fishing_boat_price() -> float:
	var n := count_boats("fish")
	var h: Dictionary = data.harbor
	return h.boat_price * pow(h.boat_price_growth, max(n - 1, 0)) * (1.0 + data.upgrades.unit_price_per_level * avg_level("fish")) * perk("unit_cost_fish")


func harbor_space_price() -> float:
	return data.harbor.space_price * pow(data.harbor.space_price_growth, harbor_buys)


func unit_price(key: String) -> float:
	var a: Dictionary = data.avenues[key]
	var n := units_owned(key)
	return a.unit * pow(data.unit_price_growth, max(n - 1, 0)) * (1.0 + data.upgrades.unit_price_per_level * avg_level(key)) * perk("unit_cost_" + key)


func upgrade_price(key: String, path: int) -> float:
	var lvl: int = levels[key][path]
	var base: float
	if key == "fish":
		base = data.upgrades.fishing_first_level_cost
	else:
		# An avenue can set its own upgrade_base; otherwise upgrades are priced from its building
		base = data.avenues[key].get("upgrade_base", data.avenues[key].building) / float(data.avenues[key].paths.size())
	return base * pow(data.upgrades.cost_growth, lvl)


func build_price(key: String) -> float:
	# A building comes with its first unit; the first dirty building also needs a laundering front
	var a: Dictionary = data.avenues[key]
	var p: float = a.building + (a.unit if a.has("unit") else 0.0)
	if a.get("dirty", false) and not laundering:
		p += data.laundering.building
	return p


func paths_for(key: String) -> Array:
	if key == "fish":
		return data.fishing_paths
	return data.avenues[key].paths


# ---------- Perks (from visitors' offers) ----------

func perk(name: String) -> float:
	# "_add" perks start at 0, the rest are multipliers that start at 1
	var adds := name.ends_with("_add")
	var v := float(perks.get(name, 0.0 if adds else 1.0))
	# The current Crown's drawbacks (and any other Crown perks) count too
	var cp: Dictionary = crown.get("perks", {})
	if cp.has(name):
		v = v + float(cp[name]) if adds else v * float(cp[name])
	return v


func risk(key: String) -> float:
	# Scales storm losses, damage, getting caught and the suspicion an avenue adds
	return perk("risk_" + key) * perk("risk_all")


func launder_rate() -> float:
	return data.laundering.rate + perk("launder_add")


# ---------- Income multipliers ----------

func path_step(key: String, i: int) -> float:
	# How much one level of this path multiplies income
	var p: Dictionary = paths_for(key)[i]
	return p.per_level


func income_mult(key: String) -> float:
	var m := 1.0
	var p := paths_for(key)
	for i in p.size():
		if p[i].effect == "income":
			m *= pow(path_step(key, i), levels[key][i])
	m *= lift(key)
	m *= perk("income_" + key)
	m *= perk("income_all")
	m *= float(crown.buffs.get(key, 1.0))
	if news.get("key", "") == key:
		# Some Crowns make news move prices further
		m *= 1.0 + (float(news.mult) - 1.0) * perk("news_swing")
	return m


func lift(key: String) -> float:
	# Supply chains: each unit of a later avenue that buys from this one adds a bonus (up to a cap)
	var bonus := 0.0
	var sc: Dictionary = data.supply_chains
	for other in data.avenues:
		var a: Dictionary = data.avenues[other]
		if a.has("lifts") and key in a.lifts:
			bonus += sc.gain * min(units_owned(other), int(sc.cap))
	return 1.0 + bonus


func loot_table() -> Array:
	# Treasure: Maps upgrades make rarer finds likelier. Returns [[name, chance, value], ...]
	var t: Dictionary = data.avenues.treasure
	var maps: int = levels.treasure[0]
	var per: float = path_step("treasure", 0)
	var weights := []
	var total := 0.0
	for i in t.loot.size():
		var w: float = t.loot[i][1] * pow(per, i * maps)
		weights.append(w)
		total += w
	var out := []
	for i in t.loot.size():
		out.append([t.loot[i][0], weights[i] / total, t.loot[i][2]])
	return out


func survive_chance() -> float:
	if not built.has("deep"):
		return 0.0
	var hull: Dictionary = data.avenues.deep.paths[0]
	var raw: float = min(hull.max, hull.get("base", 0.0) + hull.per_level * levels.deep[0])
	# A visitor's perk can push survival past the Hull's max
	return min(0.95, raw + perk("survive_add"))


# ---------- Weather tools ----------

func home_chance() -> float:
	# Lighthouse: chance a deep boat the storm would sink gets home instead
	if not built.has("lighthouse"):
		return 0.0
	return clamp(path_value("lighthouse", 0) + perk("home_add"), 0.0, 0.9)


func keep_share() -> float:
	# Share of a normal day's catch a boat keeps when the lighthouse guides it home
	return path_value("lighthouse", 2) if built.has("lighthouse") else 0.0


func lighthouse_covers(key: String) -> bool:
	# Range 1 adds whaling ships, range 2 adds pirate ships and oil rigs
	if not built.has("lighthouse"):
		return false
	var r: float = path_value("lighthouse", 1)
	if key == "whaling":
		return r >= 1
	if key == "piracy" or key == "oil":
		return r >= 2
	return false


func damage_chance(key: String) -> float:
	# Chance a storm damages one unit; the lighthouse can steer covered ships clear
	var c: float = float(data.storm_damage.chance.get(key, 0.0)) * risk(key)
	if lighthouse_covers(key):
		c *= 1.0 - home_chance()
	return c


func _fill_forecast() -> void:
	# Roll the hidden weather for the next two days (in order, so the storm gap rule still works)
	while upcoming.size() < 2:
		var d: int = day + 1 + upcoming.size()
		upcoming.append({"w": roll_weather(d), "u": rng.randf(), "v": rng.randf()})


func accuracy() -> float:
	if not built.has("meteo"):
		return 0.0
	return min(0.95, path_value("meteo", 0) + perk("accuracy_add"))


func forecast_call(e: Dictionary) -> String:
	# Right "accuracy" of the time; otherwise one of the other two weathers
	if e.u < accuracy():
		return e.w
	var others := ["perfect", "normal", "storm"]
	others.erase(e.w)
	return others[int(e.v * 2.0) % 2]


func forecast_text() -> String:
	if not built.has("meteo") or upcoming.is_empty():
		return ""
	var t := "Forecast: tomorrow %s" % forecast_call(upcoming[0]).capitalize()
	if path_value("meteo", 1) >= 1 and upcoming.size() > 1:
		t += ", day after %s" % forecast_call(upcoming[1]).capitalize()
	return t + " (right %d%% of the time)" % int(round(accuracy() * 100))


func has_orders() -> bool:
	return built.has("meteo") and path_value("meteo", 2) >= 1


func pots_per_ship() -> int:
	return int(data.avenues.cray.pots) + int(levels.cray[0]) + int(perk("pots_add"))


# ---------- Tiers ----------

func tier_of(key: String) -> int:
	return 1 if key == "fish" else int(data.avenues[key].tier)


func max_level_for(key: String) -> int:
	return int(data.tiers.max_level[str(tier_of(key))])


func path_value(key: String, path: int) -> float:
	# For paths with a base and a max: base + per_level x level, up to the max
	var p: Dictionary = paths_for(key)[path]
	return min(float(p.max), float(p.base) + float(p.per_level) * levels[key][path])


func path_max_level(key: String, path: int) -> int:
	# A path with a max stops once it reaches it (Hull: 20% + 10% a level, max 60% = level 4)
	var p: Dictionary = paths_for(key)[path]
	if p.has("max"):
		return int(ceil((p.max - p.get("base", 0.0)) / p.per_level - 0.0001))
	return max_level_for(key)


func tier_blockers(t: int) -> Array:
	# What still stops tier t opening, as readable lines (empty = open)
	if t <= 1:
		return []
	# Oil (tier 4) opens with tier 3: tier 2 done is enough, the dirty avenues are optional
	if t == 4:
		return tier_blockers(3)
	var out := []
	var need: int = int(data.tiers.min_level[str(t)])
	var keys := ["fish"] if t == 2 else []
	for key in data.avenues:
		# Optional buildings (lighthouse, weather bureau) never block a tier
		if int(data.avenues[key].tier) == t - 1 and not data.avenues[key].get("optional", false):
			keys.append(key)
			if not built.has(key):
				out.append("Build the " + data.avenues[key].name)
	for key in keys:
		var p := paths_for(key)
		for i in p.size():
			var need_here: int = min(need, path_max_level(key, i))
			if levels[key][i] < need_here:
				var where: String = "Fishing" if key == "fish" else data.avenues[key].name
				out.append("%s: %s to level %d" % [where, p[i].name, need_here])
	return out


func tier_open(t: int) -> bool:
	return tier_blockers(t).is_empty()


# ---------- Bills ----------

func rent_for_week(week: int) -> float:
	var r: Dictionary = data.rent
	var n: int = max(0, int((week - 1) / int(r.weeks_per_step)))
	var g: float = r.step_growth
	var steps: float = n if is_equal_approx(g, 1.0) else (pow(g, n) - 1.0) / (g - 1.0)
	return (r.start + r.first_step * steps) * perk("rent_mult")


func next_rent() -> float:
	# The next bill lands on the next multiple of 7
	return rent_for_week(int(ceil((day + 1) / 7.0)))


func tax_on(week_total: float) -> float:
	var t := 0.0
	var lo := 0.0
	for band in crown.tax_bands:
		var hi: float = band[0]
		if week_total > lo:
			t += band[1] * (min(week_total, hi) - lo)
		lo = hi
	return t


func days_to_bills() -> int:
	return 7 - (day % 7)


# ---------- Weather and news ----------

func storm_gap(d: int) -> int:
	var gap := 0
	for pair in data.weather.storm_gap_by_day:
		if d >= pair[0]:
			gap = pair[1]
	return gap


func roll_weather(d: int) -> String:
	var allowed := (d - last_storm) >= storm_gap(d)
	if allowed and rng.randf() < data.weather.storm_chance + perk("storm_add"):
		last_storm = d
		return "storm"
	# The other five faces: 1 perfect, 2-5 normal
	if rng.randi_range(1, 5) == 1:
		return "perfect"
	return "normal"


func _new_news() -> void:
	# One market moves each week, for any avenue (built or not) or fishing
	var keys: Array = ["fish"] + data.avenues.keys()
	keys.erase("deep")
	keys.erase("lighthouse")
	keys.erase("meteo")
	var key: String = keys[rng.randi_range(0, keys.size() - 1)]
	var up := rng.randf() < 0.5
	var name: String = "Fish" if key == "fish" else data.avenues[key].name
	var text: String
	if up:
		text = "%s prices up %d%% this week!" % [name, int(round((data.news.up - 1.0) * 100))]
	else:
		text = "%s prices crash: down %d%% this week." % [name, int(round((1.0 - data.news.down) * 100))]
	news = {"key": key, "mult": data.news.up if up else data.news.down, "text": text}


# ---------- The day ----------

func start_day() -> Dictionary:
	if over or pending_push >= 0 or pending_offer >= 0 or not pending_pick.is_empty():
		return {}
	_fill_forecast()
	day += 1
	if (day - 1) % 7 == 0:
		_new_news()
		_say("NEWS: " + news.text)
	var today: Dictionary = upcoming.pop_front()
	var w: String = today.w
	# Standing orders: when the Weather Bureau forecast a storm, deep boats stay in port today
	var held := has_orders() and forecast_call(today) == "storm"
	# "removed" lists boat indices in the order they were removed, so the scene can remove the same boats
	var report := {"day": day, "weather": w, "lines": [], "sunk": [], "removed": [], "income": 0.0}
	# Random events: old effects wear off, a warned event may hit today (a hurricane forces storms)
	_event_tick(report)
	if day <= forced_storm_until:
		w = "storm"
		report.weather = w
		last_storm = day
	var clean := 0.0
	var dirty := 0.0
	var dirty_risk := 0.0
	var h: Dictionary = data.harbor
	var ds: Dictionary = data.deep_sea
	var av: Dictionary = data.avenues

	# Fishing boats in the harbor (only as many as there are spaces)
	var in_harbor: int = min(count_boats("fish", "harbor"), harbor_spaces)
	if in_harbor > 0:
		var e: float = h.catch * h[w] * income_mult("fish") * perk("zone_fish_harbor") * in_harbor
		clean += e
		report.lines.append("Harbor fishing: +$%s" % _money(e))

	# Boats sent deep: fishing and crab. Storms sink them unless they survive.
	var deep_e := 0.0
	var survive := survive_chance()
	var home := home_chance()
	var homed := 0
	var stayed := 0
	for i in range(boats.size() - 1, -1, -1):
		var b: Dictionary = boats[i]
		if b.zone != "deep" or not (b.kind == "fish" or b.kind == "crab"):
			continue
		if held:
			stayed += 1
			continue
		if w == "storm":
			if rng.randf() >= survive:
				if rng.randf() < home:
					# The lighthouse guides it home: back to the harbor (or the dock if the harbor is full)
					homed += 1
					if b.kind == "crab" or count_boats("fish", "harbor") < harbor_spaces:
						b.zone = "harbor"
					else:
						b.zone = "dock"
					if b.kind == "fish":
						deep_e += keep_share() * ds.fishing_normal * income_mult("fish") * perk("zone_fish_deep")
					else:
						deep_e += keep_share() * ds.crab_normal * income_mult("crab")
				else:
					report.sunk.append(i)
					report.removed.append(i)
					boats.remove_at(i)
		elif b.kind == "fish":
			deep_e += ds["fishing_" + w] * income_mult("fish") * perk("zone_fish_deep")
		else:
			deep_e += ds["crab_" + w] * income_mult("crab")
	if deep_e > 0:
		clean += deep_e
		report.lines.append("Deep sea: +$%s" % _money(deep_e))
	if report.sunk.size() > 0:
		report.lines.append("Storm sank %d deep boat(s)!" % report.sunk.size())
	if homed > 0:
		report.lines.append("The lighthouse guided %d boat(s) home." % homed)
	if stayed > 0:
		report.lines.append("Standing orders: storm forecast, %d deep boat(s) stayed in port." % stayed)
	if perk("daily_add") > 0:
		clean += perk("daily_add")
		report.lines.append("Newspaper: +$%s" % _money(perk("daily_add")))

	# Crab boats in the harbor: big storm hauls; storms can wreck a boat's gear (the boat is safe)
	var n_crab := count_boats("crab", "harbor")
	if n_crab > 0:
		var c: Dictionary = av.crab
		var ce: float = c[w] * income_mult("crab") * n_crab
		clean += ce
		report.lines.append("Crab boats: +$%s" % _money(ce))
		if w == "storm":
			var lost := 0
			for i in n_crab:
				if rng.randf() < c.storm_pot_loss * risk("crab"):
					lost += 1
			if lost > 0:
				clean -= lost * c.pot_cost
				report.lines.append("Storm wrecked the gear of %d crab boat(s): -$%s" % [lost, _money(lost * c.pot_cost)])

	# Pearl spots: steady
	if counts.pearl > 0:
		var pe: float = av.pearl[w] * income_mult("pearl") * counts.pearl
		clean += pe
		report.lines.append("Pearls: +$%s" % _money(pe))

	# Cray ships drop pots. Storms lose pots, which cost money to replace.
	if counts.cray > 0:
		var cr: Dictionary = av.cray
		var pots: int = counts.cray * pots_per_ship()
		if w == "storm":
			var lost_pots := 0
			for i in pots:
				if rng.randf() < cr.pot_storm_loss * risk("cray"):
					lost_pots += 1
			if lost_pots > 0:
				clean -= lost_pots * cr.pot_cost
				report.lines.append("Storm lost %d cray pots: -$%s" % [lost_pots, _money(lost_pots * cr.pot_cost)])
		else:
			var cye: float = pots * cr["pot_" + w] * income_mult("cray")
			clean += cye
			report.lines.append("Cray pots: +$%s" % _money(cye))

	# Storms wash up wrecks (more for every boat of yours that sank); barges haul one each a day
	if w == "storm" and built.has("salvage"):
		wrecks += int(av.salvage.wrecks_per_storm) + int(perk("wrecks_add")) + report.sunk.size()
	var n_barge := count_boats("barge")
	if n_barge > 0 and wrecks > 0:
		var take: int = min(wrecks, n_barge)
		wrecks -= take
		var se: float = take * av.salvage.wreck_value * income_mult("salvage")
		clean += se
		report.lines.append("Salvage: %d wreck(s) +$%s (%d left)" % [take, _money(se), wrecks])

	# Whaling ships: big calm-day catches, home empty in storms
	var n_whale := count_boats("whale")
	if n_whale > 0:
		if w == "storm":
			report.lines.append("Whalers came home empty (storm).")
		else:
			var we: float = av.whaling[w] * income_mult("whaling") * n_whale
			clean += we
			report.lines.append("Whaling: +$%s" % _money(we))

	# Treasure divers: one find each on perfect days
	if counts.treasure > 0 and w == "perfect":
		var table := loot_table()
		var te := 0.0
		var finds := {}
		for d in counts.treasure:
			var x := rng.randf()
			var acc := 0.0
			for row in table:
				acc += row[1]
				if x < acc:
					te += row[2] * income_mult("treasure")
					finds[row[0]] = finds.get(row[0], 0) + 1
					break
		clean += te
		var names := []
		for k in finds:
			names.append("%s x%d" % [k, finds[k]])
		report.lines.append("Treasure: %s  +$%s" % [", ".join(names), _money(te)])

	# Smuggling and piracy: dirty money, best in storms; on clear days ships can be caught and seized
	_check_hidden()
	for key in ["smuggle", "piracy"]:
		var kind: String = SHIP_KIND[key]
		# Ships hidden in the moorings don't sail: no money, no risk
		var n: int = count_boats(kind, "deep")
		if n == 0:
			continue
		var a: Dictionary = av[key]
		var caught_chance: float = float(a.get("caught_" + w, 0.0)) * risk(key)
		var caught := 0
		for i in range(boats.size() - 1, -1, -1):
			if boats[i].kind == kind and boats[i].zone == "deep" and rng.randf() < caught_chance:
				report.removed.append(i)
				boats.remove_at(i)
				caught += 1
		var de: float = a[w] * income_mult(key) * (n - caught)
		# A licensed share of piracy (Queen's Privateer) comes in clean: no laundering, no suspicion
		var licensed: float = de * clamp(perk(key + "_clean_add"), 0.0, 1.0)
		clean += licensed
		de -= licensed
		dirty += de
		dirty_risk += de * risk(key)
		if licensed > 0:
			report.lines.append("%s: +$%s clean (licensed) +$%s dirty" % [a.name, _money(licensed), _money(de)])
		else:
			report.lines.append("%s: +$%s dirty" % [a.name, _money(de)])
		if caught > 0:
			report.lines.append("Patrols caught %d of your %s(s)!" % [caught, a.unit_name.to_lower()])

	# Hidden moorings: a flat fee every day for each berth not holding one of your own ships
	if counts.hiding - hidden_own() > 0:
		var he: float = av.hiding[w] * income_mult("hiding") * (counts.hiding - hidden_own())
		dirty += he
		dirty_risk += he * risk("hiding")
		report.lines.append("Hidden moorings: +$%s dirty" % _money(he))

	# Oil rigs: mostly perfect days
	var n_rig := count_boats("rig")
	if n_rig > 0:
		var oe: float = av.oil[w] * income_mult("oil") * n_rig
		clean += oe
		if oe > 0:
			report.lines.append("Oil: +$%s" % _money(oe))

	# Dirty money is laundered at a flat rate
	var laundered: float = dirty * launder_rate()
	var income: float = clean + laundered
	if dirty > 0:
		report.lines.append("Laundered $%s dirty into $%s clean." % [_money(dirty), _money(laundered)])

	# Storms damage rigs and big ships; repairs are paid at once
	var repairs := 0.0
	if w == "storm":
		var sd: Dictionary = data.storm_damage
		for key in sd.chance:
			var n2: int = units_owned(key)
			var hit := 0
			for i in n2:
				if rng.randf() < damage_chance(key):
					hit += 1
			if hit > 0:
				var cost: float = hit * sd.repair_share * data.avenues[key].unit
				repairs += cost
				report.lines.append("Storm damaged %d %s(s): repairs -$%s" % [hit, data.avenues[key].unit_name.to_lower(), _money(cost)])

	# Suspicion rises with the share of income that is dirty, then fades a little
	var sp: Dictionary = data.suspicion
	if dirty > 0 and income > 0:
		var share: float = laundered / income
		var r: float = dirty_risk / dirty
		suspicion += sp.gain * share * r * perk("suspicion")
	suspicion *= 1.0 - sp.fade_per_day
	suspicion = min(suspicion, 100.0)
	var fine := 0.0
	var investigate := false
	if investigation_due >= 0 and day >= investigation_due:
		investigation_due = -1
		if suspicion < calloff_at:
			report.lines.append("The investigators found nothing and left.")
		else:
			investigate = true
	elif investigation_due < 0 and (suspicion >= 100.0 or (suspicion > sp.safe_below and rng.randf() < investigation_chance())):
		# An informant tips you off first, so you have time to hide ships or pay off officials
		investigation_due = day + int(sp.tipoff_days)
		calloff_at = max(0.0, suspicion - sp.calloff_drop)
		report["tipoff"] = true
		report.lines.append("TIP-OFF: investigators arrive on day %d. Get suspicion under %d by then (hide ships, pay off officials) and they'll find nothing." % [investigation_due, int(calloff_at)])
	if investigate:
		investigations += 1
		var steps: Array = sp.fine_weeks
		fine = steps[min(investigations - 1, steps.size() - 1)] * last_week * perk("fine")
		income = 0.0
		var seized := 0
		for i in range(boats.size() - 1, -1, -1):
			if (boats[i].kind == "smuggler" or boats[i].kind == "pirate") and boats[i].zone != "hidden" and rng.randf() < sp.seize:
				report.removed.append(i)
				boats.remove_at(i)
				seized += 1
		report.lines.append("INVESTIGATION! No earnings today, fined $%s, %d sailing ship(s) seized. Your hidden ships are safe." % [_money(fine), seized])
		report["investigation"] = true
		suspicion = sp.after_investigation

	_fill_harbor()
	report.income = income - repairs - fine
	cash += income - repairs - fine
	week_income = income if (day - 1) % 7 == 0 else week_income + income
	# Dirty money is off the books, so only clean money counts for tax
	var taxable: float = 0.0 if investigate else clean
	week_taxable = taxable if (day - 1) % 7 == 0 else week_taxable + taxable
	week_dirty = dirty if (day - 1) % 7 == 0 else week_dirty + dirty
	season_earned += income

	# Weekly bills
	if day % 7 == 0:
		var t := tax_on(max(week_taxable, 0.0))
		var rent := rent_for_week(day / 7)
		cash -= t + rent
		report.lines.append("Bills: rent $%s + tax $%s (tax on the $%s clean money you earned this week; dirty money isn't taxed)" % [_money(rent), _money(t), _money(week_taxable)])
		report["bills"] = t + rent
		last_week = week_income
		last_week_dirty = week_dirty

	# End of a season: the Crown checks the levy, then sets the next one
	if not over and day % int(data.levy.season_days) == 0:
		_end_season(report)

	# Interest on any loan, then the Silent Partner covers a shortfall (if you have warnings left)
	if loan > 0:
		loan *= 1.0 + data.silent_partner.daily_interest * loan_mult
	if cash < 0:
		_cover_shortfall(report)
	_clear_old_warning(report)
	if oil_found and day == permit_day:
		report.lines.append("The Crown approves your oil permit. You can build the Oil Platform.")
	# While you owe the Silent Partner, everything you earn goes to paying them back first
	var pay: float = min(loan, cash)
	loan -= pay
	cash -= pay
	if loan < 0.01:
		loan = 0.0
	if pay > 0:
		report["repaid"] = pay
		if loan > 0:
			report.lines.append("Paid $%s to the Silent Partner (still owe $%s)." % [_money(pay), _money(loan)])
		else:
			report.lines.append("Paid $%s to the Silent Partner. Loan cleared!" % _money(pay))
	if not over and loan > 0 and day >= loan_due:
		_liquidate(report)

	# After the weekly bills a visitor may come with an offer (not in the same week as a Crown push)
	if not over and day % 7 == 0 and pending_push < 0:
		_next_offer()
		if pending_offer >= 0:
			report["offer"] = true
			var o: Dictionary = data.offers.list[pending_offer]
			report.lines.append("Visitors: %s and %s have offers for you." % [o.a.who, o.b.who])

	# After the weekly bills a random event may be on its way (you get a warning first)
	if not over and day % 7 == 0 and event_due.is_empty() and rng.randf() < float(data.events.chance):
		_warn_event(report)
	# A newly opened tier earns a pick of 1 of 3 random boons
	if not over:
		_check_tier_boon()

	_fill_forecast()
	for line in report.lines:
		log_lines.append("Day %d (%s): %s" % [day, w, line])
		_write("Day %d (%s): %s" % [day, w, line])
	_write("Day %d end: cash %s, loan %s, suspicion %d" % [day, money(cash), money(loan), int(suspicion)])
	day_finished.emit(report)
	changed.emit()
	return report


func _liquidate(report: Dictionary) -> void:
	var share: float = data.silent_partner.sale_share
	report.lines.append("Loan overdue! The Silent Partner sells your things.")
	# Sell counted units first, then boats and ships, until the loan is paid
	for key in COUNTED:
		while loan > 0.01 and counts[key] > 0:
			counts[key] -= 1
			cash += share * unit_price(key)
			_pay_loan()
	var key_for := {}
	for k in SHIP_KIND:
		key_for[SHIP_KIND[k]] = k
	while loan > 0.01 and boats.size() > 0:
		report.removed.append(boats.size() - 1)
		var b: Dictionary = boats.pop_back()
		cash += share * (unit_price(key_for[b.kind]) if key_for.has(b.kind) else fishing_boat_price())
		_pay_loan()
	if loan > 0.01:
		over = true
		_write("RUN LOST on day %d" % day)
		run_over.emit(false, "The Silent Partner took everything. The Crown takes back the island.")
	else:
		loan = 0.0


func _pay_loan() -> void:
	var pay: float = min(loan, cash)
	loan -= pay
	cash -= pay


func covers_left() -> int:
	return max(int(data.silent_partner.covers) - warnings, 0)


func _cover_shortfall(report: Dictionary) -> void:
	# Cash has gone below zero. An open loan just grows; a new shortfall uses up a warning, or gets nothing.
	var sp: Dictionary = data.silent_partner
	if loan > 0:
		loan += -cash
		cash = 0.0
		return
	if covers_left() <= 0:
		# No covers left: the shortfall is due today, so your things are sold now
		report.lines.append("The Silent Partner refuses to cover you again. Your things are sold to pay the bill.")
		loan = -cash
		cash = 0.0
		loan_due = day
		_liquidate(report)
		return
	var i: int = warnings
	warnings += 1
	warning_day = day
	loan_mult = float(sp.interest_mult[min(i, sp.interest_mult.size() - 1)])
	loan_due = day + int(sp.repay_days[min(i, sp.repay_days.size() - 1)])
	loan = -cash
	cash = 0.0
	var line := "SILENT PARTNER WARNING %d of %d: they cover you this time. Repay by day %d, interest %d%% a day." % [warnings, int(sp.covers), loan_due, int(round(sp.daily_interest * loan_mult * 100))]
	if covers_left() == 0:
		line += " This was your last cover: next time they sell your things."
	report.lines.append(line)
	report["warning"] = warnings


# ---------- Finding oil ----------

func oil_approved() -> bool:
	return oil_found and day >= permit_day


func survey_price() -> float:
	var os: Dictionary = data.oil_search
	return max(float(os.survey_min), float(os.survey_weeks) * last_week)


func can_survey() -> bool:
	return tier_open(4) and not oil_found and can_afford(survey_price())


func can_survey_crooked() -> bool:
	# A crooked surveyor needs dirty money: you must run a dirty avenue (which opens your laundering front)
	return laundering and can_survey()


func survey(crooked: bool = false) -> bool:
	# Pay for a survey; it may find oil, which starts the Crown's permit wait
	if not can_survey():
		return false
	if crooked and not laundering:
		return false
	var os: Dictionary = data.oil_search
	cash -= survey_price()
	surveys += 1
	var chance: float = float(os.find_chance)
	# A crooked surveyor knows where the oil is, but word gets around
	if crooked:
		chance = float(os.crooked_find_chance)
		suspicion += float(os.crooked_suspicion)
	if rng.randf() < chance + perk("oil_find_add"):
		oil_found = true
		permit_day = day + int(os.permit_weeks) * 7
		_say("Survey %d struck oil! The Crown's permit will take until day %d." % [surveys, permit_day])
	else:
		_say("Survey %d found no oil. Try another spot." % surveys)
	return true


func permit_bribe_price() -> float:
	var os: Dictionary = data.oil_search
	return max(float(os.bribe_min), float(os.bribe_dirty_weeks) * last_week_dirty)


func can_bribe_permit() -> bool:
	# Needs dirty money: you must run a dirty avenue (which opens your laundering front)
	return oil_found and day < permit_day and laundering and can_afford(permit_bribe_price())


func bribe_permit() -> bool:
	if not can_bribe_permit():
		return false
	var os: Dictionary = data.oil_search
	cash -= permit_bribe_price()
	permit_bribes += 1
	permit_day = max(day, permit_day - int(os.bribe_cut_weeks) * 7)
	suspicion += float(os.bribe_suspicion)
	_say("You slipped the permit office some dirty money. The permit now comes through on day %d. (Suspicion +%d)" % [permit_day, int(os.bribe_suspicion)])
	return true


func _clear_old_warning(report: Dictionary) -> void:
	# A warning wears off after a quiet spell with no loan
	if warnings <= 0 or loan > 0:
		return
	if day - warning_day >= int(data.silent_partner.clear_after_weeks) * 7:
		warnings -= 1
		warning_day = day
		report.lines.append("The Silent Partner forgets one warning. You have %d cover(s) left." % covers_left())


# ---------- Rival Crowns ----------

func stay_levy_mult() -> float:
	# Staying with your Crown when the rival pushes makes this season's levy bigger (each push more)
	var steps: Array = data.crowns.stay_levy_mult
	return float(steps[min(max(pending_push, 0), steps.size() - 1)])


func rival() -> Dictionary:
	# The Crown pushing for the island right now
	return data.crowns.list[max(rival_index, 0)]


func _pick_rival() -> void:
	# A random Crown you haven't served
	var pool := []
	for i in data.crowns.list.size():
		if not served.has(i):
			pool.append(i)
	rival_index = pool[rng.randi_range(0, pool.size() - 1)]


func _push_due() -> bool:
	# The rival pushes as you get rich (at shares of the island price), until you defect
	var pushes: Array = data.crowns.push_at
	return not defected and push_index < pushes.size() and cash >= pushes[push_index] * price


func resolve_push(defect: bool) -> void:
	if pending_push < 0:
		return
	var cr: Dictionary = data.crowns
	if defect and not defected:
		defected = true
		var old_mult: float = perk("price_mult")
		crown = cr.list[rival_index]
		served.append(rival_index)
		# Re-appraised dearer; a Crown with its own price rule (Treasure Fleet) changes it too
		price *= cr.appraisal * perk("price_mult") / old_mult
		# Some of your people stay loyal to the old Crown and leave
		var left := 0
		for i in range(boats.size() - 1, -1, -1):
			if rng.randf() < cr.defectors:
				boats.remove_at(i)
				left += 1
		for k in COUNTED:
			var keep: int = counts[k]
			for i in counts[k]:
				if rng.randf() < cr.defectors:
					keep -= 1
					left += 1
			counts[k] = keep
		pending_push = -1
		_say("You defected to %s. The island is re-appraised at %s. %d of your boats and crews stayed loyal to the old Crown and left." % [crown.name, money(price), left])
		decree = {"id": "rival_push", "name": "New Crown", "text": "You serve %s now." % crown.name}
	else:
		levy_mult = stay_levy_mult()
		pending_push = -1
		decree = {"id": "rival_push", "name": "Loyalty levy", "text": "You stayed with %s, so this season's levy is x%s." % [crown.name, str(levy_mult)]}
		_say("You stayed with %s. To keep the rival away, this season's levy is now %s." % [crown.name, money(levy_target())])


# ---------- Crown levies ----------

func levy_target(s: int = -1) -> float:
	# What the Crown wants you to earn in season s (grows every season)
	var lv: Dictionary = data.levy
	var n: int = season if s < 0 else s
	var t: Array = lv.targets
	# The loyalty multiplier only applies to the current season
	var m: float = levy_scale * (levy_mult if n == season else 1.0)
	if n <= t.size():
		return float(t[n - 1]) * m
	# After the table ends, each season asks growth_after times the last
	return float(t[-1]) * pow(float(lv.growth_after), n - t.size()) * m


func season_end_day() -> int:
	return season * int(data.levy.season_days)


func levy_text() -> String:
	# For the top bar
	var t := "Levy: earn %s by day %d (%s so far)  Strikes %d/%d" % [money(levy_target()), season_end_day(), money(season_earned), strikes, int(data.levy.max_strikes)]
	if not decree.is_empty():
		t += "  |  Decree: %s (%s)" % [decree.name, decree.text]
	return t


func _end_season(report: Dictionary) -> void:
	var lv: Dictionary = data.levy
	var target := levy_target()
	season_log.append(season_earned)
	if season_earned >= target:
		report.lines.append("CROWN LEVY MET: you earned $%s this season (needed $%s)." % [_money(season_earned), _money(target)])
	else:
		strikes += 1
		var fine: float = (target - season_earned) * float(lv.fine_share)
		cash -= fine
		report["levy_missed"] = true
		report.lines.append("CROWN LEVY MISSED: you earned $%s of $%s. Fined $%s. Strike %d of %d." % [_money(season_earned), _money(target), _money(fine), strikes, int(lv.max_strikes)])
		if strikes >= int(lv.max_strikes):
			over = true
			_write("RUN LOST on day %d (levy strikes)" % day)
			run_over.emit(false, "You missed %d Crown levies. The Crown takes back the island." % strikes)
			return
	season += 1
	season_earned = 0.0
	levy_mult = 1.0
	decree = {}
	# The rival Crown's push takes the place of this season's decree
	if _push_due():
		pending_push = push_index
		push_index += 1
		_pick_rival()
		decree = {"id": "rival_push", "name": "Rival Crown", "text": "%s pushes for the island. Stay (this season's levy goes up) or defect." % rival().name}
		report["push"] = true
		report.lines.append("CROWN DECREE: %s pushes for the island! Stay loyal and this season's levy rises, or defect." % rival().name)
	elif season >= int(lv.decree_from_season):
		_draw_decree(report)
	report.lines.append("NEXT LEVY: earn $%s by day %d." % [_money(levy_target()), season_end_day()])


func _draw_decree(report: Dictionary) -> void:
	# A random twist for the season, only for things you own
	var pool := []
	for i in data.levy.decrees.size():
		if _event_ok(data.levy.decrees[i]):
			pool.append(i)
	if pool.is_empty():
		return
	decree = data.levy.decrees[pool[rng.randi_range(0, pool.size() - 1)]]
	_apply_perks(decree.perks, season_end_day())
	report.lines.append("CROWN DECREE for this season: %s. %s" % [decree.name, decree.text])


# ---------- Roguelite luck: sea conditions, boons, random events ----------

func _shuffle(a: Array) -> void:
	# Shuffle with the run's own dice, so a seed always plays the same
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _apply_perks(list: Array, until: int = -1) -> void:
	# Add perks the same way Visitors' perks work; until >= 0 makes them wear off after that day
	for pk in list:
		if pk.has("mult"):
			perks[pk.perk] = perk(pk.perk) * float(pk.mult)
		else:
			perks[pk.perk] = perk(pk.perk) + float(pk.add)
		if until >= 0:
			var e: Dictionary = pk.duplicate()
			e["until"] = until
			active_effects.append(e)


func _draw_conditions() -> void:
	# Two random sea conditions for the whole run, shown before day 1
	var pool: Array = range(data.conditions.list.size())
	_shuffle(pool)
	var options := []
	for n in min(int(data.conditions.draw), pool.size()):
		var c: Dictionary = data.conditions.list[pool[n]]
		conditions_now.append(c.id)
		_apply_perks(c.perks)
		options.append({"name": c.name, "text": c.text, "index": pool[n]})
		_say("Sea condition: %s. %s" % [c.name, c.text])
	pending_pick = {"kind": "conditions", "title": "This year's seas", "text": "Every run's seas are different. These last the whole run:", "options": options}


func _offer_crowns() -> void:
	# Every run starts by choosing which Crown to lease the rock from
	var options := []
	for i in data.crowns.list.size():
		var c: Dictionary = data.crowns.list[i]
		options.append({"name": c.name, "text": "Good: %s
Bad: %s" % [c.good, c.bad], "index": i})
	pending_pick = {"kind": "crown", "title": "Choose your Crown", "text": "Six Crowns will lease you the rock. Each has its own rules. You can defect later, but only once.", "options": options}


func _check_tier_boon() -> void:
	# The first time each tier opens, offer 1 of 3 random boons not taken yet
	if not pending_pick.is_empty():
		return
	for t in [2, 3, 4]:
		if tiers_rewarded.has(t) or not tier_open(t):
			continue
		tiers_rewarded[t] = true
		var pool := []
		for i in data.boons.list.size():
			if not boons_taken.has(data.boons.list[i].id):
				pool.append(i)
		_shuffle(pool)
		var options := []
		for n in min(int(data.boons.choices), pool.size()):
			var b: Dictionary = data.boons.list[pool[n]]
			options.append({"name": b.name, "text": b.text, "index": pool[n]})
		if options.size() > 0:
			pending_pick = {"kind": "boon", "title": "Tier %d is open: pick a boon" % t, "text": "Word of your success spreads. Pick one, free. The others are gone.", "options": options}
			_write("Tier %d boon offered: %s" % [t, ", ".join(options.map(func(o): return o.name))])
		return


func answer_pick(choice: int) -> bool:
	if pending_pick.is_empty():
		return false
	var p := pending_pick
	if p.kind == "boon":
		if choice < 0 or choice >= p.options.size():
			return false
		var b: Dictionary = data.boons.list[p.options[choice].index]
		boons_taken.append(b.id)
		_apply_perks(b.perks)
		pending_pick = {}
		_say("Boon: %s. %s" % [b.name, b.text])
		return true
	if p.kind == "crown":
		if choice < 0 or choice >= data.crowns.list.size():
			return false
		crown = data.crowns.list[choice]
		served = [choice]
		price = data.island_price * perk("price_mult")
		pending_pick = {}
		_say("You lease the rock from %s. %s %s The island costs %s." % [crown.name, crown.good, crown.bad, money(price)])
		return true
	if p.kind == "conditions":
		_offer_crowns()
		changed.emit()
		return true
	pending_pick = {}
	changed.emit()
	return true


func _event_ok(e: Dictionary) -> bool:
	if e.needs == "any":
		return true
	if e.needs == "dirty":
		return laundering
	if e.needs == "fish":
		return true
	return built.has(e.needs)


func _warn_event(report: Dictionary) -> void:
	var pool := []
	for i in data.events.list.size():
		if _event_ok(data.events.list[i]):
			pool.append(i)
	if pool.is_empty():
		return
	var i: int = pool[rng.randi_range(0, pool.size() - 1)]
	var e: Dictionary = data.events.list[i]
	event_due = {"index": i, "day": day + int(data.events.warn_days)}
	report.lines.append("WARNING (%s, day %d): %s" % [e.name, event_due.day, e.warn])
	report["event_warning"] = true


func event_text() -> String:
	# For the status bar: the event you've been warned about
	if event_due.is_empty():
		return ""
	var e: Dictionary = data.events.list[event_due.index]
	return "%s on day %d" % [e.name, event_due.day]


func _event_tick(report: Dictionary) -> void:
	# Temporary effects wear off
	for k in range(active_effects.size() - 1, -1, -1):
		var a: Dictionary = active_effects[k]
		if day > int(a.until):
			if a.has("mult"):
				perks[a.perk] = perk(a.perk) / float(a.mult)
			else:
				perks[a.perk] = perk(a.perk) - float(a.add)
			active_effects.remove_at(k)
	# The warned event hits
	if event_due.is_empty() or day < int(event_due.day):
		return
	var e: Dictionary = data.events.list[event_due.index]
	event_due = {}
	report.lines.append("EVENT: " + e.hit)
	report["event"] = e.id
	if int(e.days) > 0:
		_apply_perks(e.perks, day + int(e.days) - 1)
	if e.has("cost_weeks"):
		var c: float = float(e.cost_weeks) * last_week
		cash -= c
		report.lines.append("%s cost you $%s." % [e.name, _money(c)])
	if e.has("suspicion"):
		suspicion = min(100.0, suspicion + float(e.suspicion))
	if e.has("wrecks"):
		wrecks += int(e.wrecks)
	if e.has("storm_days"):
		forced_storm_until = day + int(e.storm_days) - 1


# ---------- Visitors' offers ----------

func _next_offer() -> void:
	# The first unanswered offer in the queue whose building you own
	for i in offer_order:
		var o: Dictionary = data.offers.list[i]
		if offers_done.has(o.id):
			continue
		if o.needs == "fish" or built.has(o.needs):
			pending_offer = i
			return


func answer_offer(choice: String) -> bool:
	# choice: "a" or "b" (pay for that one; the other is gone) or "later" (it comes back after the others)
	if pending_offer < 0:
		return false
	var o: Dictionary = data.offers.list[pending_offer]
	if choice == "later":
		offer_order.erase(pending_offer)
		offer_order.append(pending_offer)
		# Clear the offer before _say, which refreshes the screen
		pending_offer = -1
		_say("You sent %s and %s away for now. They'll be back." % [o.a.who, o.b.who])
		return true
	if loan > 0 or cash < o.cost:
		return false
	var pick: Dictionary = o[choice]
	cash -= o.cost
	for pk in pick.perks:
		if pk.has("mult"):
			perks[pk.perk] = perk(pk.perk) * float(pk.mult)
		else:
			perks[pk.perk] = perk(pk.perk) + float(pk.add)
	offers_done[o.id] = choice
	var other: Dictionary = o["b" if choice == "a" else "a"]
	pending_offer = -1
	_say("You paid %s %s. %s  (%s leaves for good.)" % [pick.who, money(o.cost), pick.effect, other.who])
	return true


# ---------- Buying (between days) ----------

func can_afford(p: float) -> bool:
	return not over and pending_push < 0 and loan == 0 and cash >= p


func buy_fishing_boat() -> bool:
	var p := fishing_boat_price()
	if not can_afford(p):
		return false
	cash -= p
	var zone := "harbor" if count_boats("fish", "harbor") < harbor_spaces else "dock"
	boats.append({"kind": "fish", "zone": zone})
	_say("Bought a fishing boat for $%s." % _money(p))
	return true


func expand_harbor() -> bool:
	var p := harbor_space_price()
	if not can_afford(p):
		return false
	cash -= p
	harbor_spaces += 1
	harbor_buys += 1
	_fill_harbor()
	_say("Harbor now has %d spaces." % harbor_spaces)
	return true


func can_build(key: String) -> bool:
	return not built.has(key) and tier_open(tier_of(key)) and (key != "oil" or oil_approved()) and can_afford(build_price(key))


func build(key: String) -> bool:
	if built.has(key) or not tier_open(tier_of(key)):
		return false
	# The oil platform needs oil found and the Crown's permit
	if key == "oil" and not oil_approved():
		return false
	var p := build_price(key)
	if not can_afford(p):
		return false
	cash -= p
	built[key] = true
	var a: Dictionary = data.avenues[key]
	if a.get("dirty", false) and not laundering:
		laundering = true
		log_lines.append("Opened a laundering front for dirty money.")
		_write("Opened a laundering front for dirty money.")
	if a.has("unit"):
		_add_unit(key)
		_say("Built the %s, with your first %s." % [a.name, a.unit_name])
	else:
		_say("Built the %s." % a.name)
	return true


func _add_unit(key: String) -> void:
	if SHIP_KIND.has(key):
		var zone := "deep" if key in ["whaling", "smuggle", "piracy", "oil"] else "harbor"
		boats.append({"kind": SHIP_KIND[key], "zone": zone})
	else:
		counts[key] += 1


func can_buy_unit(key: String) -> bool:
	if not built.has(key) or not data.avenues[key].has("unit"):
		return false
	var a: Dictionary = data.avenues[key]
	if a.has("max_units") and units_owned(key) >= int(a.max_units):
		return false
	return can_afford(unit_price(key))


func buy_unit(key: String) -> bool:
	if not can_buy_unit(key):
		return false
	var p := unit_price(key)
	cash -= p
	_add_unit(key)
	_say("Bought a %s for $%s." % [data.avenues[key].unit_name, _money(p)])
	return true


func can_upgrade(key: String, path: int) -> bool:
	if key != "fish" and not built.has(key):
		return false
	if levels[key][path] >= path_max_level(key, path):
		return false
	return can_afford(upgrade_price(key, path))


func upgrade(key: String, path: int) -> bool:
	if not can_upgrade(key, path):
		return false
	var p := upgrade_price(key, path)
	cash -= p
	levels[key][path] += 1
	_say("%s upgraded to level %d." % [paths_for(key)[path].name, levels[key][path]])
	return true


func set_zone(index: int, zone: String) -> bool:
	if over or index < 0 or index >= boats.size():
		return false
	var b: Dictionary = boats[index]
	if b.kind == "smuggler" or b.kind == "pirate":
		# Dirty ships either sail or hide in a free Hidden Moorings berth
		if zone == "hidden" and b.zone != "hidden" and hidden_own() >= int(counts.hiding):
			return false
		if not (zone == "deep" or zone == "hidden"):
			return false
		b.zone = zone
		changed.emit()
		return true
	if not (b.kind == "fish" or b.kind == "crab"):
		return false
	if zone == "deep" and not built.has("deep"):
		return false
	if zone == "harbor" and b.kind == "fish" and b.zone != "harbor" and count_boats("fish", "harbor") >= harbor_spaces:
		return false
	if zone == "dock" and b.kind == "crab":
		return false
	b.zone = zone
	changed.emit()
	return true


# ---------- Keeping suspicion down ----------

func hidden_own() -> int:
	return count_boats("smuggler", "hidden") + count_boats("pirate", "hidden")


func _check_hidden() -> void:
	# If berths were lost (defectors), extra hidden ships go back to sailing
	for b in boats:
		if b.zone == "hidden" and hidden_own() > int(counts.hiding):
			b.zone = "deep"


func bribe_price() -> float:
	var br: Dictionary = data.suspicion.bribe
	return max(float(br.min), br.share * last_week) * pow(br.growth, bribes)


func bribe() -> bool:
	var p := bribe_price()
	if suspicion <= 0 or not can_afford(p):
		return false
	cash -= p
	bribes += 1
	suspicion = max(0.0, suspicion - data.suspicion.bribe.drop)
	_say("Paid officials %s. Suspicion down to %d. (Bribes get dearer each time.)" % [money(p), int(suspicion)])
	return true


func buy_island() -> bool:
	if not can_afford(island_price()):
		return false
	cash -= island_price()
	over = true
	_say("You bought the island!")
	_write("RUN WON on day %d" % day)
	run_over.emit(true, "You bought the island on day %d. The Crown has no hold on you now." % day)
	return true


# ---------- Help for the player ----------

func odds() -> Dictionary:
	# Rough day odds after the first two weeks: 1 in 6 storm, the rest split 1 perfect : 4 normal
	var s: float = data.weather.storm_chance
	return {"perfect": (1.0 - s) / 5.0, "normal": (1.0 - s) * 4.0 / 5.0, "storm": s}


func avg_per_day(key: String) -> float:
	# Roughly what ONE more unit earns on an average day, after its risks
	var o := odds()
	var av: Dictionary = data.avenues
	match key:
		"fish":
			var h: Dictionary = data.harbor
			return h.catch * (o.perfect * h.perfect + o.normal * h.normal + o.storm * h.storm) * income_mult("fish") * perk("zone_fish_harbor")
		"fish_deep":
			var ds: Dictionary = data.deep_sea
			return (o.perfect * ds.fishing_perfect + o.normal * ds.fishing_normal) * income_mult("fish") * perk("zone_fish_deep") - o.storm * (1.0 - survive_chance()) * ((1.0 - home_chance()) * fishing_boat_price() - home_chance() * keep_share() * ds.fishing_normal * income_mult("fish") * perk("zone_fish_deep"))
		"pearl":
			var p: Dictionary = av.pearl
			return (o.perfect * p.perfect + o.normal * p.normal + o.storm * p.storm) * income_mult("pearl")
		"crab":
			var c: Dictionary = av.crab
			return (o.perfect * c.perfect + o.normal * c.normal + o.storm * c.storm) * income_mult("crab") - o.storm * c.storm_pot_loss * risk("crab") * c.pot_cost
		"cray":
			var cr: Dictionary = av.cray
			return pots_per_ship() * ((o.perfect * cr.pot_perfect + o.normal * cr.pot_normal) * income_mult("cray") - o.storm * cr.pot_storm_loss * risk("cray") * cr.pot_cost)
		"salvage":
			# The first barge gets about every wreck; more barges mostly clear the pile faster
			var sv: Dictionary = av.salvage
			var rate: float = o.storm * (sv.wrecks_per_storm + perk("wrecks_add")) * sv.wreck_value * income_mult("salvage")
			return rate if count_boats("barge") == 0 else rate * 0.15
		"treasure":
			var avg := 0.0
			for row in loot_table():
				avg += row[1] * row[2]
			return o.perfect * avg * income_mult("treasure")
		"whaling", "oil":
			var a: Dictionary = av[key]
			var gross: float = (o.perfect * a.perfect + o.normal * a.normal) * income_mult(key)
			var dmg: float = o.storm * damage_chance(key) * data.storm_damage.repair_share * a.unit
			return gross - dmg
		"smuggle", "piracy":
			var a2: Dictionary = av[key]
			var cp: float = a2.caught_perfect * risk(key)
			var cn: float = a2.caught_normal * risk(key)
			var g2: float = (o.perfect * a2.perfect * (1.0 - cp) + o.normal * a2.normal * (1.0 - cn) + o.storm * a2.storm) * income_mult(key) * launder_rate()
			var dmg2: float = o.storm * damage_chance(key) * data.storm_damage.repair_share * a2.unit
			return g2 - (o.perfect * cp + o.normal * cn) * unit_price(key) - dmg2
		"hiding":
			return av.hiding.normal * income_mult("hiding") * launder_rate()
	return 0.0


func income_estimate(clean_only: bool = false) -> float:
	# Roughly what everything you own earns on an average day (clean_only skips dirty avenues)
	var total: float = avg_per_day("fish") * min(count_boats("fish", "harbor"), harbor_spaces)
	total += max(avg_per_day("fish_deep"), 0.0) * count_boats("fish", "deep")
	for key in data.avenues:
		if key == "deep" or not built.has(key):
			continue
		# For tax, dirty avenues only count their licensed (clean) share, if any
		var share := 1.0
		if clean_only and data.avenues[key].get("dirty", false):
			share = clamp(perk(key + "_clean_add"), 0.0, 1.0)
			if share <= 0.0:
				continue
		if key == "salvage":
			if count_boats("barge") > 0:
				var sv: Dictionary = data.avenues.salvage
				total += odds().storm * (sv.wrecks_per_storm + perk("wrecks_add")) * sv.wreck_value * income_mult("salvage")
			continue
		var n := units_owned(key)
		if key == "crab":
			n = count_boats("crab", "harbor")
		if key == "smuggle" or key == "piracy":
			n = count_boats(SHIP_KIND[key], "deep")
		if key == "hiding":
			n = int(counts.hiding) - hidden_own()
		total += avg_per_day(key) * n * share
	return total


func week_earned_so_far() -> float:
	# Income since the last bill (resets the day after bills)
	return week_income if day % 7 != 0 else 0.0


func week_taxable_so_far() -> float:
	# Clean income since the last bill (resets the day after bills)
	return week_taxable if day % 7 != 0 else 0.0


func tax_estimate() -> float:
	# Tax on this week's clean income: what you've earned so far plus a guess for the days left
	return tax_on(max(week_taxable_so_far() + income_estimate(true) * days_to_bills(), 0.0))


func next_bill() -> float:
	return next_rent() + tax_estimate()


func safe_to_spend() -> float:
	# Cash left after keeping enough for the next bill (rent + estimated tax)
	return cash - next_bill()


func investigation_chance() -> float:
	var sp: Dictionary = data.suspicion
	if suspicion >= 100.0:
		return 1.0
	return sp.investigation_rate * pow(max(0.0, (suspicion - sp.safe_below) / (100.0 - sp.safe_below)), 2)


func _fill_harbor() -> void:
	# Fishing boats waiting at the dock move into any free harbor space
	for b in boats:
		if b.kind == "fish" and b.zone == "dock" and count_boats("fish", "harbor") < harbor_spaces:
			b.zone = "harbor"


func _say(text: String) -> void:
	log_lines.append(text)
	_write(text)
	changed.emit()


func _money(x: float) -> String:
	var n := int(round(x))
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func money(x: float) -> String:
	return "$" + _money(x)
