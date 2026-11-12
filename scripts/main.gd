extends Node3D
## The greybox scene: draws the island, boats, weather and the menus.
## The rules live in game.gd (the "Game" autoload). This script only shows them and passes on button presses.
## Click a building (or the dock) to open its menu: build, buy, upgrade.

const BOAT_SCENE := preload("res://scenes/boat.tscn")
const SAIL_TIME := 1.0
const BOAT_COLORS := {
	"fish": Color(0.85, 0.85, 0.8),
	"crab": Color(0.85, 0.3, 0.2),
	"whale": Color(0.3, 0.32, 0.38),
	"barge": Color(0.5, 0.36, 0.2),
	"smuggler": Color(0.15, 0.4, 0.25),
	"pirate": Color(0.08, 0.08, 0.1),
	"rig": Color(0.95, 0.8, 0.2),
}
const KIND_NAMES := {"fish": "Fishing boat", "crab": "Crab boat", "whale": "Whaling ship", "barge": "Salvage barge", "smuggler": "Smuggling boat", "pirate": "Pirate ship", "rig": "Oil rig"}

# Weather looks: sky top colour, sun strength, ocean colour, fog on/off
const WEATHER_LOOK := {
	"perfect": {"sky": Color(0.3, 0.6, 0.95), "sun": 1.3, "ocean": Color(0.1, 0.45, 0.7), "fog": false},
	"normal": {"sky": Color(0.45, 0.58, 0.72), "sun": 0.9, "ocean": Color(0.12, 0.36, 0.55), "fog": false},
	"storm": {"sky": Color(0.18, 0.2, 0.24), "sun": 0.25, "ocean": Color(0.08, 0.15, 0.2), "fog": true},
}

var boat_nodes: Array = []
# Cray ships are drawn here only (the rules just count them). Each has yellow buoys, one per pot.
var cray_nodes: Array = []
var buoy_mat := StandardMaterial3D.new()
var buoy_mesh := SphereMesh.new()
var animating := false
# Which building menu is open ("" = none). "fish" is the dock / harbor menu.
var open_menu := ""
var ghost_mat := StandardMaterial3D.new()

@onready var env: Environment = $WorldEnvironment.environment
@onready var sun: DirectionalLight3D = $Sun
@onready var ocean_mat: StandardMaterial3D = $Ocean.get_surface_override_material(0)
@onready var list: VBoxContainer = $UI/Shop/Scroll/List
@onready var menu_body: VBoxContainer = $UI/BuildingMenu/Box/Scroll/Body
@onready var log_box: RichTextLabel = $UI/LogPanel/Log


func _ready() -> void:
	# Unbuilt buildings show as faint ghosts you can click
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(1, 1, 1, 0.25)
	buoy_mat.albedo_color = Color(1.0, 0.85, 0.1)
	buoy_mesh.radius = 0.45
	buoy_mesh.height = 0.9
	Game.changed.connect(_on_changed)
	Game.run_over.connect(_on_run_over)
	$UI/Actions/StartDay.pressed.connect(_on_start_day)
	$UI/Actions/BuyIsland.pressed.connect(func(): Game.buy_island())
	$UI/EndScreen/Box/Restart.pressed.connect(_on_restart)
	$UI/TopBar/Row/Help.pressed.connect(func(): $UI/HelpPanel.visible = true)
	$UI/HelpPanel/Box/Close.pressed.connect(func(): $UI/HelpPanel.visible = false)
	$UI/BuildingMenu/Box/Close.pressed.connect(close_menu)
	$UI/CrownChoice/Box/Buttons/Stay.pressed.connect(func(): Game.resolve_push(false))
	$UI/CrownChoice/Box/Buttons/Defect.pressed.connect(func(): Game.resolve_push(true))
	$UI/StatusBar/Row/Bribe.pressed.connect(func(): Game.bribe())
	# The Visitors panel also shows sea conditions and boon picks (pending_pick)
	$UI/OfferChoice/Box/Buttons/PickA.pressed.connect(func(): _on_choice(0))
	$UI/OfferChoice/Box/Buttons/PickB.pressed.connect(func(): _on_choice(1))
	$UI/OfferChoice/Box/Buttons/Later.pressed.connect(func(): _on_choice(2))
	_rebuild_boats()
	_show_weather("normal")
	refresh()


func _on_changed() -> void:
	# During the day animation the screen updates at the end instead
	if not animating:
		refresh()


func refresh() -> void:
	_update_top_bar()
	_rebuild_side_panel()
	_update_log()
	_update_buildings()
	if open_menu != "":
		_fill_menu()
	_place_boats(0.4)
	_place_cray()


# ---------- Clicking buildings ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam: Camera3D = $Camera3D
		var from := cam.project_ray_origin(event.position)
		var to := from + cam.project_ray_normal(event.position) * 500.0
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		if hit.is_empty():
			return
		# Each clickable thing has a StaticBody3D named "Click"; its parent's name says which menu to open
		var owner_name: String = hit.collider.get_parent().name
		open_menu_for("fish" if owner_name == "Dock" else owner_name)


func open_menu_for(key: String) -> void:
	open_menu = key
	$UI/BuildingMenu.visible = true
	_fill_menu()


func _oil_search_rows() -> void:
	# Before the platform: pay for surveys, then wait for (or bribe) the Crown's permit
	var os: Dictionary = Game.data.oil_search
	if not Game.oil_found:
		_header(menu_body, "Find oil first")
		_text(menu_body, "Each survey has a %d%% chance to find oil. Surveys so far: %d. Once oil is found, the Crown takes %d weeks to approve the platform." % [int(round(os.find_chance * 100)), Game.surveys, int(os.permit_weeks)])
		var sp: float = Game.survey_price()
		_button(menu_body, "Pay for a survey  " + Game.money(sp), sp, Game.can_survey(), func(): Game.survey())
		if Game.laundering:
			_text(menu_body, "Or pay a crooked surveyor with dirty money: %d%% chance to find oil, but each one adds %d suspicion." % [int(round(os.crooked_find_chance * 100)), int(os.crooked_suspicion)])
			_button(menu_body, "Pay a crooked surveyor  " + Game.money(sp), sp, Game.can_survey_crooked(), func(): Game.survey(true))
		else:
			_text(menu_body, "Players with dirty money (smuggling, piracy or hidden moorings) could pay a crooked surveyor for better odds.")
		return
	_header(menu_body, "Oil found! Waiting for the Crown's permit")
	_text(menu_body, "The permit comes through on day %d (%d days from now)." % [Game.permit_day, Game.permit_day - Game.day])
	var bp: float = Game.permit_bribe_price()
	if Game.laundering:
		_text(menu_body, "Slip the permit office some dirty money to cut %d weeks off the wait. Each bribe adds %d suspicion." % [int(os.bribe_cut_weeks), int(os.bribe_suspicion)])
		_button(menu_body, "Bribe the permit office  " + Game.money(bp), bp, Game.can_bribe_permit(), func(): Game.bribe_permit())
	else:
		_text(menu_body, "Players with dirty money (smuggling, piracy or hidden moorings) could bribe the permit office to speed this up.")


func close_menu() -> void:
	open_menu = ""
	$UI/BuildingMenu.visible = false


func _fill_menu() -> void:
	for c in menu_body.get_children():
		c.queue_free()
	var key := open_menu
	if key == "fish":
		$UI/BuildingMenu/Box/Title.text = "Dock and Harbor"
		_text(menu_body, "Fishing boats in the harbor are safe and earn about %s a day each. You have %d harbor spaces (%d used). Extra boats wait at the dock or go deep." % [Game.money(Game.avg_per_day("fish")), Game.harbor_spaces, min(Game.count_boats("fish", "harbor"), Game.harbor_spaces)])
		_lift_text(menu_body, "fish")
		_button(menu_body, "Buy fishing boat  " + Game.money(Game.fishing_boat_price()), Game.fishing_boat_price(), Game.can_afford(Game.fishing_boat_price()), func(): Game.buy_fishing_boat())
		_button(menu_body, "Expand harbor (+1 space)  " + Game.money(Game.harbor_space_price()), Game.harbor_space_price(), Game.can_afford(Game.harbor_space_price()), func(): Game.expand_harbor())
		_perk_text(menu_body, "fish")
		_header(menu_body, "Fishing upgrades (all fishing boats)")
		_upgrade_rows(menu_body, "fish")
		return

	var a: Dictionary = Game.data.avenues[key]
	$UI/BuildingMenu/Box/Title.text = "%s  (tier %d)" % [a.name, int(a.tier)]
	_text(menu_body, a.blurb)
	if not Game.built.has(key):
		var blockers: Array = Game.tier_blockers(int(a.tier))
		if blockers.size() > 0:
			_header(menu_body, "Locked. Tier %d opens when you:" % int(a.tier))
			for b in blockers:
				_text(menu_body, "-  " + b)
			return
		if key == "oil" and not Game.oil_approved():
			_oil_search_rows()
			return
		var bp := Game.build_price(key)
		var what := ("Build + first %s  " % a.unit_name) if a.has("unit") else "Build  "
		var earns := ("  (~%s/day)" % Game.money(Game.avg_per_day(key))) if a.has("unit") else ""
		if a.get("dirty", false) and not Game.laundering:
			_text(menu_body, "Includes a laundering front (%s) so dirty money can be turned clean at %d%%." % [Game.money(Game.data.laundering.building), int(Game.launder_rate() * 100)])
		_button(menu_body, what + Game.money(bp) + earns, bp, Game.can_afford(bp), func(): Game.build(key))
		return

	_perk_text(menu_body, key)

	_lift_text(menu_body, key)
	match key:
		"deep":
			_text(menu_body, "Send boats deep from the Boats list on the right. A deep fishing boat earns about %s a day on average. In a storm, deep boats survive %d%% of the time (Hull upgrades raise this, up to 60%%)." % [Game.money(Game.avg_per_day("fish_deep")), int(round(Game.survive_chance() * 100))])
		"cray":
			_text(menu_body, "%d pots per ship." % Game.pots_per_ship())
		"lighthouse":
			_text(menu_body, "If a storm would sink a deep boat, %d%% of the time it gets home instead, keeping %d%% of a normal catch." % [int(round(Game.home_chance() * 100)), int(round(Game.keep_share() * 100))])
			var covers := ["fishing and crab boats"]
			if Game.lighthouse_covers("whaling"):
				covers.append("whaling ships")
			if Game.lighthouse_covers("oil"):
				covers.append("pirate ships and oil rigs")
			_text(menu_body, "Covers: " + ", ".join(covers) + ".")
		"meteo":
			_text(menu_body, Game.forecast_text())
			if Game.has_orders():
				_text(menu_body, "Standing orders are on: when the forecast says storm, deep boats stay in port that day (no catch, no risk).")
		"salvage":
			_text(menu_body, "Wrecks waiting: %d" % Game.wrecks)
		"smuggle", "piracy":
			_text(menu_body, "Dirty money, laundered at %d%%. Best in storms. Patrols catch sailing ships on clear days (perfect days most). Suspicion: %d / 100. To cool off: hide ships in the Hidden Moorings, or pay off officials (button by the suspicion bar)." % [int(Game.launder_rate() * 100), int(Game.suspicion)])
		"hiding":
			_text(menu_body, "Dirty money, laundered at %d%%. Each berth earns a fee from other captains, OR hides one of your own smuggling or pirate ships (Hide button in the Boats list). Hidden ships earn nothing but add no suspicion, can't be caught and are never seized. Berths: %d, your ships hidden: %d." % [int(Game.launder_rate() * 100), int(Game.counts.hiding), Game.hidden_own()])
		"oil":
			_text(menu_body, "Storms can damage rigs (repairs cost money).")
		"treasure":
			var odds := []
			for row in Game.loot_table():
				odds.append("%s %s (%.1f%%)" % [row[0], Game.money(row[2] * Game.income_mult("treasure")), row[1] * 100.0])
			_text(menu_body, "Finds right now: " + ",  ".join(odds))
	if a.has("unit"):
		var owned := Game.units_owned(key)
		var cap_text := (" / %d" % int(a.max_units)) if a.has("max_units") else ""
		if a.has("max_units") and owned >= int(a.max_units):
			_text(menu_body, "%s: %d%s (all owned)" % [a.unit_name, owned, cap_text])
		else:
			var up := Game.unit_price(key)
			_button(menu_body, "Buy %s  %s  (~%s/day)   own %d%s" % [a.unit_name, Game.money(up), Game.money(Game.avg_per_day(key)), owned, cap_text], up, Game.can_buy_unit(key), func(): Game.buy_unit(key))
	_header(menu_body, "Upgrades")
	_upgrade_rows(menu_body, key)


func _lift_text(into: Control, key: String) -> void:
	var l: float = Game.lift(key)
	if l > 1.0:
		_text(into, "Supply chain bonus: +%d%% income" % int(round((l - 1.0) * 100)))


func _upgrade_rows(into: Control, key: String) -> void:
	var paths: Array = Game.paths_for(key)
	for i in paths.size():
		var lvl: int = Game.levels[key][i]
		if lvl >= Game.path_max_level(key, i):
			_text(into, "%s: level %d (max)" % [paths[i].name, lvl])
			continue
		var price := Game.upgrade_price(key, i)
		var effect := ""
		match paths[i].effect:
			"income":
				effect = "+%d%% income" % int(round((paths[i].per_level - 1.0) * 100))
			"survive":
				effect = "storm survival %d%% -> %d%%" % [int(round(Game.survive_chance() * 100)), int(round(min(paths[i].max, Game.survive_chance() + paths[i].per_level) * 100))]
			"pots":
				effect = "+1 pot per ship"
			"odds":
				effect = "rarer finds more likely"
			"home":
				effect = "get-home chance %d%% -> %d%%" % [int(round(Game.path_value(key, i) * 100)), int(round(min(paths[i].max, Game.path_value(key, i) + paths[i].per_level) * 100))]
			"range":
				effect = "also covers whaling ships" if lvl == 0 else "also covers pirate ships and oil rigs"
			"keep":
				effect = "boats that get home keep %d%% of a catch" % int(round((Game.path_value(key, i) + paths[i].per_level) * 100))
			"accuracy":
				effect = "forecast right %d%% -> %d%%" % [int(round(Game.path_value(key, i) * 100)), int(round(min(paths[i].max, Game.path_value(key, i) + paths[i].per_level) * 100))]
			"ahead":
				effect = "also forecast the day after"
			"orders":
				effect = "deep boats stay in port when a storm is forecast"
		_button(into, "%s  %d -> %d   %s  (%s)" % [paths[i].name, lvl, lvl + 1, Game.money(price), effect], price, Game.can_upgrade(key, i), func(): Game.upgrade(key, i))


# ---------- Top bar, log, buildings ----------

func _update_top_bar() -> void:
	$UI/TopBar/Row/Day.text = "Day %d" % Game.day
	$UI/TopBar/Row/Cash.text = "Cash " + Game.money(Game.cash)
	# Loan, plus how many Silent Partner covers are left
	var covers := "  (Silent Partner covers left: %d)" % Game.covers_left()
	$UI/TopBar/Row/Loan.text = (("Loan %s (due day %d)" % [Game.money(Game.loan), Game.loan_due]) if Game.loan > 0 else "No loan") + covers
	$UI/TopBar/Row/Bills.text = "Bills in %d day(s): rent %s + tax ~%s" % [Game.days_to_bills(), Game.money(Game.next_rent()), Game.money(Game.tax_estimate())]
	$UI/TopBar/Row/Island.text = "Island " + Game.money(Game.island_price())
	var safe := Game.safe_to_spend()
	$UI/TopBar/Row/Safe.text = "Safe to spend " + Game.money(max(safe, 0.0))
	$UI/TopBar/Row/Safe.modulate = Color(1, 0.55, 0.4) if safe < 0 else Color(0.6, 1, 0.6)
	$UI/Actions/BuyIsland.disabled = not Game.can_afford(Game.island_price())
	$UI/Actions/StartDay.disabled = animating or Game.over or Game.pending_push >= 0 or Game.pending_offer >= 0 or not Game.pending_pick.is_empty()
	$UI/StatusBar/Row/Forecast.text = Game.forecast_text()
	$UI/StatusBar/Row/Crown.text = "Crown: %s. Good: %s Bad: %s" % [Game.crown.name, Game.crown.good, Game.crown.bad]
	# The Crown's levy for this season, strikes and the season's decree
	$UI/StatusBar/Row/Crown.text += "   |   " + Game.levy_text()
	$UI/StatusBar/Row/Crown.modulate = Color(1, 0.6, 0.4) if Game.strikes > 0 else Color(1, 1, 1)
	var sus := int(Game.suspicion)
	$UI/StatusBar/Row/Suspicion.text = "Suspicion %d/100 (investigation %d%% a day)" % [sus, int(round(Game.investigation_chance() * 100))]
	$UI/StatusBar/Row/Suspicion.modulate = Color(1, 0.5, 0.4) if sus >= 60 else (Color(1, 0.85, 0.4) if sus >= 30 else Color(0.8, 0.8, 0.8))
	if Game.investigation_due >= 0:
		$UI/StatusBar/Row/Suspicion.text = "INVESTIGATORS ARRIVE DAY %d: get suspicion under %d (now %d)" % [Game.investigation_due, int(Game.calloff_at), sus]
		$UI/StatusBar/Row/Suspicion.modulate = Color(1, 0.4, 0.3)
	var bribe_btn: Button = $UI/StatusBar/Row/Bribe
	bribe_btn.visible = Game.suspicion >= 1.0
	bribe_btn.text = "Pay off officials %s (-%d)" % [Game.money(Game.bribe_price()), int(Game.data.suspicion.bribe.drop)]
	bribe_btn.disabled = not Game.can_afford(Game.bribe_price())
	$UI/StatusBar/Row/News.text = ("News: " + Game.news.text) if Game.news.has("text") else "News: none yet"
	# A warned event shows next to the news, in orange
	if Game.event_text() != "":
		$UI/StatusBar/Row/News.text += "   |   COMING: " + Game.event_text()
	$UI/StatusBar/Row/News.modulate = Color(1, 0.7, 0.4) if Game.event_text() != "" else Color(1, 1, 1)
	_update_crown_choice()
	_update_offer_choice()


func _update_crown_choice() -> void:
	var box := $UI/CrownChoice
	box.visible = Game.pending_push >= 0 and not Game.over
	if not box.visible:
		return
	var cr: Dictionary = Game.data.crowns
	var rival: Dictionary = Game.rival()
	# The new price: re-appraised, and a Crown's own price rule (Treasure Fleet) swaps in
	var new_price: float = Game.island_price() * cr.appraisal * float(rival.perks.get("price_mult", 1.0)) / float(Game.crown.perks.get("price_mult", 1.0))
	var text := "[font_size=24][b]%s pushes for the island[/b][/font_size]\n[i](inspired by %s)[/i]\n\n%s\n\n" % [rival.name, rival.inspired_by, rival.pitch]
	text += "[b]Stay[/b] with %s: this season's levy goes from %s to %s.\n\n" % [Game.crown.name, Game.money(Game.levy_target()), Game.money(Game.levy_target() * Game.stay_levy_mult())]
	if Game.defected:
		text += "You have already defected. There is no going back."
		$UI/CrownChoice/Box/Buttons/Defect.disabled = true
	else:
		text += "[b]Defect[/b] to %s (one-way): the island is re-appraised at %s, and about %d%% of your boats and crews stay loyal to the old Crown and leave.
   You lose: %s %s
   You gain: %s %s" % [rival.name, Game.money(new_price), int(cr.defectors * 100), Game.crown.good, Game.crown.bad, rival.good, rival.bad]
		$UI/CrownChoice/Box/Buttons/Defect.disabled = false
	$UI/CrownChoice/Box/Text.text = text


func _on_choice(i: int) -> void:
	# Sea conditions / boon pick first, otherwise a Visitors offer (a, b or later)
	if not Game.pending_pick.is_empty():
		Game.answer_pick(i)
	else:
		Game.answer_offer(["a", "b", "later"][i])


func _update_pick() -> bool:
	# Shows sea conditions or a boon pick in the Visitors panel; returns true if it did
	var p: Dictionary = Game.pending_pick
	if p.is_empty() or Game.over:
		return false
	$UI/OfferChoice.visible = true
	var text := "[font_size=24][b]%s[/b][/font_size]\n%s\n\n" % [p.title, p.text]
	for o in p.options:
		text += "[b]%s[/b]\n[color=#9fe39f]%s[/color]\n\n" % [o.name, o.text]
	$UI/OfferChoice/Box/Text.text = text
	# The Crown pick has six choices, so it uses its own grid of buttons instead of the usual three
	var grid := _crown_grid()
	grid.visible = p.kind == "crown"
	$UI/OfferChoice/Box/Buttons.visible = p.kind != "crown"
	if p.kind == "crown":
		for i in grid.get_child_count():
			var cb: Button = grid.get_child(i)
			cb.visible = i < p.options.size()
			if cb.visible:
				cb.text = p.options[i].name
		return true
	var buttons := [$UI/OfferChoice/Box/Buttons/PickA, $UI/OfferChoice/Box/Buttons/PickB, $UI/OfferChoice/Box/Buttons/Later]
	for i in buttons.size():
		var b: Button = buttons[i]
		b.disabled = false
		if p.kind == "conditions":
			# One button to start the run
			b.visible = i == 0
			b.text = "Set sail"
		else:
			b.visible = i < p.options.size()
			if b.visible:
				b.text = "Take " + p.options[i].name
	return true


func _crown_grid() -> GridContainer:
	# Made once, the first time it's needed: six buttons, three to a row
	var box: VBoxContainer = $UI/OfferChoice/Box
	if box.has_node("CrownGrid"):
		return box.get_node("CrownGrid")
	var grid := GridContainer.new()
	grid.name = "CrownGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for i in Game.data.crowns.list.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 44)
		b.pressed.connect(func(): Game.answer_pick(i))
		grid.add_child(b)
	return grid


func _update_offer_choice() -> void:
	if _update_pick():
		return
	# Not a pick: put the usual three buttons back
	_crown_grid().visible = false
	$UI/OfferChoice/Box/Buttons.visible = true
	var box := $UI/OfferChoice
	for b in [$UI/OfferChoice/Box/Buttons/PickA, $UI/OfferChoice/Box/Buttons/PickB, $UI/OfferChoice/Box/Buttons/Later]:
		b.visible = true
	$UI/OfferChoice/Box/Buttons/Later.text = "Not now"
	box.visible = Game.pending_offer >= 0 and Game.pending_push < 0 and not Game.over
	if not box.visible:
		return
	var o: Dictionary = Game.data.offers.list[Game.pending_offer]
	var afford: bool = Game.loan == 0 and Game.cash >= o.cost
	var text := "[font_size=24][b]Visitors[/b][/font_size]\nTwo people want your money. Each costs %s. Pick one and the other leaves for good.\n\n" % Game.money(o.cost)
	for c in ["a", "b"]:
		var v: Dictionary = o[c]
		text += "[b]%s[/b], %s:\n[i]\"%s\"[/i]\n[color=#9fe39f]%s[/color]\n\n" % [v.who, v.role, v.pitch, v.effect]
	if not afford:
		text += "[color=#ff9a7a]You can't pay %s right now. Say Not now and they'll come back later.[/color]" % Game.money(o.cost)
	elif Game.cash - o.cost < Game.next_bill():
		text += "[color=#ff9a7a]Paying leaves less than your next bill (%s).[/color]" % Game.money(Game.next_bill())
	$UI/OfferChoice/Box/Text.text = text
	$UI/OfferChoice/Box/Buttons/PickA.text = "Pay %s" % o.a.who
	$UI/OfferChoice/Box/Buttons/PickB.text = "Pay %s" % o.b.who
	$UI/OfferChoice/Box/Buttons/PickA.disabled = not afford
	$UI/OfferChoice/Box/Buttons/PickB.disabled = not afford


func _perk_text(into: Control, key: String) -> void:
	# List the visitors' perks bought for this building
	for o in Game.data.offers.list:
		if o.needs == key and Game.offers_done.has(o.id):
			var v: Dictionary = o[Game.offers_done[o.id]]
			_text(into, "Hired %s (%s): %s" % [v.who, v.role, v.effect])


func _buff_text(buffs: Dictionary) -> String:
	var parts := []
	for k in buffs:
		parts.append("%s %+d%%" % [Game.data.avenues[k].name, int(round((buffs[k] - 1.0) * 100))])
	return ", ".join(parts)


func _update_log() -> void:
	var lines: Array = Game.log_lines.slice(max(0, Game.log_lines.size() - 40))
	log_box.text = "\n".join(lines)


func _update_buildings() -> void:
	# Built = solid; not built = faint ghost with a hint
	for b in $Buildings.get_children():
		var key: String = b.name
		var a: Dictionary = Game.data.avenues[key]
		var tag: Label3D = b.get_node("Tag")
		if Game.built.has(key):
			b.material_override = null
			tag.text = a.name
		else:
			b.material_override = ghost_mat
			tag.text = a.name + ("\n(click to build)" if Game.tier_open(int(a.tier)) else "\n(locked)")


# ---------- Right panel: boats ----------

func _rebuild_side_panel() -> void:
	for c in list.get_children():
		c.queue_free()
	_header(list, "Click a building or the dock")
	_text(list, "Every building on the island opens its own menu: build it, buy more, upgrade it. The dock opens fishing boats and the harbor.")
	_button(list, "Open Dock and Harbor", 0.0, true, func(): open_menu_for("fish"))

	_header(list, "Where your boats work")
	if not Game.built.has("deep"):
		_text(list, "Build the Deep Sea Dock to send boats deep.")
	var others := {}
	var number := {}
	for i in Game.boats.size():
		var b: Dictionary = Game.boats[i]
		if b.kind in ["fish", "crab", "smuggler", "pirate"]:
			number[b.kind] = number.get(b.kind, 0) + 1
			_boat_row(i, number[b.kind])
		else:
			others[b.kind] = others.get(b.kind, 0) + 1
	for k in others:
		_text(list, "%s x%d (always at work)" % [KIND_NAMES[k], others[k]])
	if Game.units_owned("cray") > 0:
		_text(list, "Cray ship x%d, %d pots each (orange, left of the harbor)" % [Game.units_owned("cray"), Game.pots_per_ship()])

	_header(list, "Buildings")
	for key in Game.data.avenues:
		var a: Dictionary = Game.data.avenues[key]
		var state := "built" if Game.built.has(key) else ("not built" if Game.tier_open(int(a.tier)) else "locked")
		_button(list, "%s  (%s)" % [a.name, state], 0.0, true, func(): open_menu_for(key))


func _boat_row(i: int, number: int) -> void:
	var b: Dictionary = Game.boats[i]
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s %d" % [KIND_NAMES[b.kind], number]
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var zones := ["harbor", "deep", "dock"] if b.kind == "fish" else ["harbor", "deep"]
	# Smuggling and pirate ships sail, or hide in a free Hidden Moorings berth (safe, but earn nothing)
	var dirty: bool = b.kind == "smuggler" or b.kind == "pirate"
	if dirty:
		zones = ["deep", "hidden"]
	for z in zones:
		var btn := Button.new()
		btn.text = ({"deep": "Sail", "hidden": "Hide"}[z]) if dirty else z.capitalize()
		btn.toggle_mode = true
		# The boat's current zone shows as pressed (highlighted); unavailable zones are greyed out
		btn.button_pressed = b.zone == z
		btn.disabled = animating or Game.over or (z == "deep" and not dirty and not Game.built.has("deep"))
		if z == "hidden" and b.zone != "hidden" and Game.hidden_own() >= int(Game.counts.hiding):
			btn.disabled = true
			btn.tooltip_text = "Needs a free Hidden Moorings berth"
		if b.zone == z:
			btn.add_theme_color_override("font_pressed_color", Color(1, 0.9, 0.4))
		btn.pressed.connect(func(): Game.set_zone(i, z) if b.zone != z else refresh())
		row.add_child(btn)
	list.add_child(row)


# ---------- Small UI helpers ----------

func _header(into: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	into.add_child(l)


func _text(into: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(0.8, 0.8, 0.8)
	into.add_child(l)


func _button(into: Control, text: String, price: float, enabled: bool, action: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	# Warn when a buy would leave too little for the next bill (rent + tax)
	if price > 0 and enabled and Game.cash - price < Game.next_bill():
		btn.text += "  - leaves you short for bills!"
		btn.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	btn.disabled = not enabled or animating
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(action)
	into.add_child(btn)


# ---------- Boats on the water ----------

func _rebuild_boats() -> void:
	for n in boat_nodes:
		n.queue_free()
	boat_nodes.clear()
	for b in Game.boats:
		_add_boat_node(b)


func _add_boat_node(b: Dictionary) -> void:
	var n: Node3D = BOAT_SCENE.instantiate()
	$Boats.add_child(n)
	n.set_color(BOAT_COLORS[b.kind])
	n.position = $Spots/DockSpot.position
	boat_nodes.append(n)


func _spot_for(zone: String, kind: String, index_in_zone: int) -> Vector3:
	var i := index_in_zone
	if kind == "whale":
		return $Spots/DeepSpot.position + Vector3((i % 8) * 6.0, 0, 9.0)
	if kind == "barge":
		return Vector3(-11.0 + (i % 4) * 3.2, 0, 29.0)
	if zone == "hidden":
		# Tucked into a cove on the east coast
		return Vector3(17.0 + (i % 3) * 2.6, 0, -4.0 + (i / 3) * 3.4)
	if kind == "smuggler":
		return $Spots/DeepSpot.position + Vector3(-12.0 - (i % 4) * 4.0, 0, (i / 4) * 4.0)
	if kind == "pirate":
		return $Spots/DeepSpot.position + Vector3(-12.0 - (i % 4) * 4.0, 0, 10.0 + (i / 4) * 4.0)
	if kind == "rig":
		return Vector3(30.0 + (i % 4) * 5.0, 0, 36.0 + (i / 4) * 5.0)
	match zone:
		"dock":
			# Two rows either side of the dock
			var side := -1 if i % 2 == 0 else 1
			return Vector3(2.6 * side, 0, 15.5 + (i / 2) * 3.2)
		"harbor":
			if kind == "crab":
				return $Spots/CrabSpot.position + Vector3((i % 3) * 3.0, 0, (i / 3) * 3.6)
			return $Spots/HarborSpot.position + Vector3(-(i % 3) * 3.0, 0, (i / 3) * 3.6)
		"deep":
			return $Spots/DeepSpot.position + Vector3((i % 12) * 4.0, 0, (i / 12) * 4.5)
	return Vector3.ZERO


func _place_cray() -> void:
	# One orange ship per cray ship owned, in rows left of the harbor, with its pots around it
	var ships: int = Game.units_owned("cray")
	var pots: int = Game.pots_per_ship()
	while cray_nodes.size() > ships:
		cray_nodes.pop_back().queue_free()
	for i in ships:
		if i >= cray_nodes.size():
			var n: Node3D = BOAT_SCENE.instantiate()
			$Boats.add_child(n)
			n.set_color(Color(1.0, 0.5, 0.1))
			n.position = Vector3(-24.0 - (i % 3) * 7.0, 0, 8.0 + (i / 3) * 6.0)
			cray_nodes.append(n)
		var ship: Node3D = cray_nodes[i]
		# Redo the buoys when the pot count changes (the "Pots per ship" upgrade)
		if ship.get_meta("pots", -1) != pots:
			for b in ship.get_children():
				if b.name.begins_with("Buoy"):
					b.free()
			for k in pots:
				var buoy := MeshInstance3D.new()
				buoy.name = "Buoy%d" % k
				buoy.mesh = buoy_mesh
				buoy.material_override = buoy_mat
				var a: float = TAU * k / pots
				buoy.position = Vector3(cos(a) * 2.2, 0.15, sin(a) * 2.2)
				ship.add_child(buoy)
			ship.set_meta("pots", pots)


func _place_boats(seconds: float) -> void:
	# Keep one node per boat, then move each to its spot in its zone
	while boat_nodes.size() < Game.boats.size():
		_add_boat_node(Game.boats[boat_nodes.size()])
	while boat_nodes.size() > Game.boats.size():
		boat_nodes.pop_back().queue_free()
	var counts := {}
	for i in Game.boats.size():
		var b: Dictionary = Game.boats[i]
		var zone: String = b.zone
		# Fishing boats beyond the harbor's spaces wait at the dock
		if zone == "harbor" and b.kind == "fish" and counts.get("harbor_fish", 0) >= Game.harbor_spaces:
			zone = "dock"
		var key: String = zone + "_" + b.kind
		var idx: int = counts.get(key, 0)
		counts[key] = idx + 1
		boat_nodes[i].set_color(BOAT_COLORS[b.kind])
		boat_nodes[i].sail_to(_spot_for(zone, b.kind, idx), seconds)


# ---------- The day ----------

func _on_start_day() -> void:
	if animating or Game.over or Game.pending_push >= 0 or Game.pending_offer >= 0 or not Game.pending_pick.is_empty():
		return
	animating = true
	$UI/Actions/StartDay.disabled = true
	# Boats head out a little before the weather shows
	for n in boat_nodes:
		n.sail_to(n.position + Vector3(0, 0, 3), SAIL_TIME * 0.6)
	await get_tree().create_timer(SAIL_TIME * 0.6).timeout
	var report: Dictionary = Game.start_day()
	_show_weather(report.weather)
	$UI/TopBar/Row/Weather.text = "Weather: " + report.weather.capitalize()
	# Sink or wreck the boats the rules removed, in the same order
	for i in report.removed:
		var n: Node3D = boat_nodes[i]
		boat_nodes.remove_at(i)
		n.sink(1.2).finished.connect(n.queue_free)
	var summary := "Day %d: %s.  Today %s%s" % [report.day, report.weather.capitalize(), "+" if report.income >= 0 else "", Game.money(report.income)]
	if report.has("bills"):
		summary += "   Rent + tax paid: " + Game.money(report.bills)
	if report.has("repaid"):
		summary += "   Loan repaid: " + Game.money(report.repaid)
	if report.sunk.size() > 0:
		summary += "   %d boat(s) sank!" % report.sunk.size()
	if report.has("investigation"):
		summary += "   INVESTIGATION!"
	if report.has("tipoff"):
		summary += "   TIP-OFF: investigators coming!"
	if report.has("push"):
		summary += "   A rival Crown is pushing!"
	if report.has("offer"):
		summary += "   Visitors!"
	$UI/Today.text = summary
	await get_tree().create_timer(SAIL_TIME).timeout
	animating = false
	refresh()


func _show_weather(w: String) -> void:
	var look: Dictionary = WEATHER_LOOK[w]
	var t := create_tween().set_parallel(true)
	t.tween_property(env.sky.sky_material, "sky_top_color", look.sky, 0.8)
	t.tween_property(sun, "light_energy", look.sun, 0.8)
	t.tween_property(ocean_mat, "albedo_color", look.ocean, 0.8)
	env.fog_enabled = look.fog
	for n in boat_nodes:
		n.bob_strength = 0.35 if w == "storm" else 0.08


func _on_run_over(won: bool, reason: String) -> void:
	$UI/EndScreen/Box/Text.text = ("YOU WIN\n\n" if won else "RUN OVER\n\n") + reason + "\n\nThis run was saved to a log file (AppData/Roaming/Godot/app_userdata/Fishopoly/run_logs)."
	$UI/EndScreen.visible = true
	refresh()


func _on_restart() -> void:
	$UI/EndScreen.visible = false
	close_menu()
	Game.new_run()
	_rebuild_boats()
	_show_weather("normal")
	$UI/TopBar/Row/Weather.text = "Weather: ?"
	refresh()
