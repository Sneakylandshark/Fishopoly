extends Node3D
## The greybox scene: draws the island, boats, weather and the menus.
## The rules live in game.gd (the "Game" autoload). This script only shows them and passes on button presses.
## Click a building (or the dock) to open its menu: build, buy, upgrade.

const BOAT_SCENE := preload("res://scenes/boat.tscn")
const SAIL_TIME := 1.0
# Seconds a pirate or smuggler takes to sail out to (or back from) the horizon
const VOYAGE_SAIL := 7.0
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
	Game.loaded.connect(func(): _rebuild_boats(); refresh())
	$UI/Actions/StartDay.pressed.connect(_on_start_day)
	$UI/Actions/BuyIsland.pressed.connect(func(): Game.buy_island())
	$UI/EndScreen/Box/Restart.pressed.connect(_on_restart)
	$UI/TopBar/Row/Help.pressed.connect(func(): $UI/HelpPanel.visible = true)
	$UI/HelpPanel/Box/Close.pressed.connect(func(): $UI/HelpPanel.visible = false)
	$UI/TopBar/Row/MyRun.pressed.connect(_open_run_panel)
	$UI/RunPanel/Box/Close.pressed.connect(func(): $UI/RunPanel.visible = false)
	$UI/BuildingMenu/Box/Close.pressed.connect(close_menu)
	$UI/CrownChoice/Box/Buttons/Stay.pressed.connect(func(): Game.resolve_push(false))
	$UI/CrownChoice/Box/Buttons/Defect.pressed.connect(func(): Game.resolve_push(true))
	$UI/StatusBar/Row/Bribe.pressed.connect(func(): Game.bribe())
	# The Visitors panel also shows sea conditions and boon picks (pending_pick)
	$UI/OfferChoice/Box/Buttons/PickA.pressed.connect(func(): _on_choice(0))
	$UI/OfferChoice/Box/Buttons/PickB.pressed.connect(func(): _on_choice(1))
	$UI/OfferChoice/Box/Buttons/Later.pressed.connect(func(): _on_choice(2))
	_setup_camera()
	_make_graphs_panel()
	_make_mail_props()
	_make_champion_buildings()
	_make_newspaper_panel()
	# Made last so it sits on top of the other panels
	_make_talk_panel()
	_rebuild_boats()
	_show_weather("normal")
	refresh()


func _on_changed() -> void:
	# During the day animation the screen updates at the end instead
	if not animating:
		refresh()


func refresh() -> void:
	_update_top_bar()
	if $UI/RunPanel.visible:
		$UI/RunPanel/Box/Text.text = _run_text()
	_rebuild_side_panel()
	_update_log()
	_update_buildings()
	if open_menu != "":
		_fill_menu()
	_place_boats(0.4)
	_place_cray()
	_update_talk()
	_update_mail()
	_update_visitor_ship()
	_draw_graphs()


# ---------- Clicking buildings ----------

func _unhandled_input(event: InputEvent) -> void:
	if _camera_input(event):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam: Camera3D = $Camera3D
		var from := cam.project_ray_origin(event.position)
		var to := from + cam.project_ray_normal(event.position) * 500.0
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		if hit.is_empty():
			return
		# Each clickable thing has a StaticBody3D named "Click"; its parent's name says which menu to open
		var owner_name: String = hit.collider.get_parent().name
		if owner_name == "Letterbox":
			open_newspaper()
			return
		if owner_name == "VisitorShip":
			open_visitors()
			return
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
		_text(menu_body, "Each survey has a %d%% chance to find oil. Surveys so far: %d. Once oil is found, the Crown takes %d weeks to approve the platform, then it takes %d weeks to build. You can hunt for oil at any tier." % [int(round(os.find_chance * 100)), Game.surveys, int(os.permit_weeks), int(os.build_weeks)])
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


func _wildcat_rows() -> void:
	# A cheap wildcat well, so a lucky early strike can start earning before you can afford the platform
	var os: Dictionary = Game.data.oil_search
	if Game.wildcat:
		if Game.day < Game.wildcat_ready_day:
			_text(menu_body, "Your wildcat well is being built. It starts pumping on day %d." % Game.wildcat_ready_day)
		else:
			_text(menu_body, "Your wildcat well is pumping (%s%% of a full rig). Building the full platform replaces it." % str(os.wildcat_share * 100.0))
		return
	_header(menu_body, "Wildcat well")
	_text(menu_body, "Can't afford the platform yet? A small wildcat well earns %s%% of a full rig, takes %d weeks to build, and is replaced when you build the platform." % [str(os.wildcat_share * 100.0), int(os.build_weeks)])
	_button(menu_body, "Build a wildcat well  " + Game.money(os.wildcat_price), os.wildcat_price, Game.can_build_wildcat(), func(): Game.build_wildcat())


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
		# Oil can be hunted at any tier, so build_blockers skips the oil tier lock; champion buildings add their own
		var blockers: Array = Game.build_blockers(key)
		if Game.is_champion_building(key):
			_header(menu_body, "What it does")
			for i in a.paths.size():
				_text(menu_body, "-  %s: %s" % [a.paths[i].name, Game.cb_path_text(key, i)])
		if blockers.size() > 0:
			_header(menu_body, "Locked. To build it:" if Game.is_champion_building(key) else "Locked. Tier %d opens when you:" % int(a.tier))
			for b in blockers:
				_text(menu_body, "-  " + b)
			return
		if key == "oil" and not Game.oil_approved():
			_oil_search_rows()
			return
		if key == "oil":
			_wildcat_rows()
		var bp := Game.build_price(key)
		var what := ("Build + first %s  " % a.unit_name) if a.has("unit") else "Build  "
		var earns := ("  (~%s/day)" % Game.money(Game.avg_per_day(key))) if a.has("unit") else ""
		# Champion buildings: a guess from the last week's numbers
		if Game.is_champion_building(key):
			earns = "  (~%s/day at today's numbers)" % Game.money(Game.cb_estimate(key))
		if a.get("dirty", false) and not Game.laundering:
			_text(menu_body, "Includes a laundering front (%s) so dirty money can be turned clean at %d%%." % [Game.money(Game.data.laundering.building), int(Game.launder_rate() * 100)])
		_button(menu_body, what + Game.money(bp) + earns, bp, Game.can_afford(bp), func(): Game.build(key))
		return

	_perk_text(menu_body, key)

	_lift_text(menu_body, key)
	if Game.is_champion_building(key):
		_text(menu_body, "Earned so far this run: %s. Last 7 days: %s." % [Game.money(Game.history_total(a.name)), Game.money(Game.history_total(a.name, max(1, Game.day - 6)))])
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
			var vg: Dictionary = Game.data.voyages
			_text(menu_body, "Dirty money, laundered at %d%%. Ships in port earn %d%% of a day at sea, can be caught (%d%% a day) and can be seized by investigators. Send them on voyages from the bounty board for real money: a voyage earns every day at sea (storms pay best), paid when the ship gets back, and ships away can't be seized. Suspicion: %d / 100." % [int(Game.launder_rate() * 100), int(vg.harbour_share * 100), int(vg.harbour_caught * 100), int(Game.suspicion)])
			_bounty_rows(key)
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
		var cap_text := (" / %d" % Game.max_units(key)) if a.has("max_units") else ""
		if a.has("max_units") and owned >= Game.max_units(key):
			_text(menu_body, "%s: %d%s (all owned)" % [a.unit_name, owned, cap_text])
		else:
			var up := Game.unit_price(key)
			_button(menu_body, "Buy %s  %s  (~%s/day)   own %d%s" % [a.unit_name, Game.money(up), Game.money(Game.avg_per_day(key)), owned, cap_text], up, Game.can_buy_unit(key), func(): Game.buy_unit(key))
	_header(menu_body, "Upgrades")
	_upgrade_rows(menu_body, key)


func _bounty_rows(key: String) -> void:
	# The bounty board: send a waiting ship on one of the voyages listed
	_header(menu_body, "Bounty board")
	var shown := 0
	for i in Game.board.size():
		var v: Dictionary = Game.board[i]
		if v.avenue != key:
			continue
		shown += 1
		var vl: Dictionary = Game.data.voyages.lengths[int(v.length)]
		var days: int = Game.voyage_days(key, int(v.length))
		var label := "%s: %d days, pays ~%s, caught %d%%" % [vl.name, days, Game.money(Game.voyage_estimate(i)), int(round(Game.voyage_catch(key, int(v.length)) * 100))]
		_button(menu_body, "Send a ship   " + label, 0.0, Game.can_send(i), func(): Game.send_voyage(i))
	if shown == 0:
		_text(menu_body, "No %s voyages on the board today. New ones come in each day." % ("smuggling" if key == "smuggle" else "pirate"))


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
			_:
				effect = str(paths[i].get("text", ""))
		if Game.is_champion_building(key):
			effect = Game.cb_path_text(key, i)
			var gain: float = Game.cb_estimate(key, i) - Game.cb_estimate(key)
			if gain >= 1.0:
				effect += ", ~+%s/day" % Game.money(gain)
		if paths[i].has("avenue"):
			effect += ", champion only"
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
	$UI/Actions/StartDay.disabled = animating or Game.over or Game.pending_push >= 0 or Game.pending_offer >= 0 or not Game.pending_pick.is_empty() or not Game.story.is_empty()
	$UI/StatusBar/Row/Forecast.text = Game.forecast_text()
	$UI/StatusBar/Row/Crown.text = "Crown: %s. Good: %s Bad: %s" % [Game.crown.name, Game.crown.good, Game.crown.bad]
	if Game.champion_index >= 0:
		$UI/StatusBar/Row/Crown.text += "   |   Champion: " + Game.champion().name
	# The Crown's levy for this season, strikes and the season's decree
	$UI/StatusBar/Row/Crown.text += "   |   " + Game.levy_text()
	$UI/StatusBar/Row/Crown.modulate = Color(1, 0.6, 0.4) if Game.strikes > 0 else Color(1, 1, 1)
	_update_favour_buttons()
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
	if Game.news_preview_text() != "":
		$UI/StatusBar/Row/News.text += "   |   " + Game.news_preview_text()
	$UI/StatusBar/Row/News.modulate = Color(1, 0.7, 0.4) if Game.event_text() != "" else Color(1, 1, 1)
	_update_crown_choice()
	_update_offer_choice()


func _update_favour_buttons() -> void:
	# Crown favours (from beating levies): made once, shown only when there's a favour to spend
	var row: HBoxContainer = $UI/StatusBar/Row
	if not row.has_node("FavourStrike"):
		var b1 := Button.new()
		b1.name = "FavourStrike"
		b1.pressed.connect(func(): Game.favour_strike())
		row.add_child(b1)
		var b2 := Button.new()
		b2.name = "FavourDecree"
		b2.pressed.connect(func(): Game.favour_decree())
		row.add_child(b2)
	var fs: Button = row.get_node("FavourStrike")
	var fd: Button = row.get_node("FavourDecree")
	fs.visible = Game.can_favour_strike()
	fs.text = "Favour (%d): clear a strike" % Game.favour
	fd.visible = Game.can_favour_decree()
	fd.text = "Favour (%d): cancel the decree" % Game.favour


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
	# Picks with more than three choices (Crowns, champions) use a grid of buttons instead of the usual three
	var big: bool = p.options.size() > 3
	var grid := _pick_grid(p.options.size())
	grid.visible = big
	$UI/OfferChoice/Box/Buttons.visible = not big
	if big:
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
				b.text = p.options[i].name if p.kind == "continue" else "Take " + p.options[i].name
	return true


func _pick_grid(n: int) -> GridContainer:
	# Made the first time it's needed, three buttons to a row; grows if a pick has more choices
	var box: VBoxContainer = $UI/OfferChoice/Box
	var grid: GridContainer
	if box.has_node("PickGrid"):
		grid = box.get_node("PickGrid")
	else:
		grid = GridContainer.new()
		grid.name = "PickGrid"
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		box.add_child(grid)
	while grid.get_child_count() < n:
		var i := grid.get_child_count()
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 44)
		b.pressed.connect(func(): Game.answer_pick(i))
		grid.add_child(b)
	return grid


func _update_offer_choice() -> void:
	if _update_pick():
		return
	# Not a pick: put the usual three buttons back
	_pick_grid(0).visible = false
	$UI/OfferChoice/Box/Buttons.visible = true
	var box := $UI/OfferChoice
	for b in [$UI/OfferChoice/Box/Buttons/PickA, $UI/OfferChoice/Box/Buttons/PickB, $UI/OfferChoice/Box/Buttons/Later]:
		b.visible = true
	$UI/OfferChoice/Box/Buttons/Later.text = "Not now"
	# Visitors wait on their ship until you click it
	box.visible = offer_open and Game.pending_offer >= 0 and Game.pending_push < 0 and not Game.over
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
		# Only your champion's own building stands on the champion plot (hidden ones can't be clicked)
		if Game.is_champion_building(key):
			var mine: bool = key == Game.champion_building()
			b.visible = mine
			b.get_node("Click/Shape").disabled = not mine
			if not mine:
				continue
		if Game.built.has(key):
			b.material_override = null
			tag.text = a.name
		else:
			b.material_override = ghost_mat
			var open: bool = Game.build_blockers(key).is_empty() if Game.is_champion_building(key) else Game.tier_open(int(a.tier))
			tag.text = a.name + ("\n(click to build)" if open else "\n(locked)")


# ---------- Right panel: boats ----------

func _rebuild_side_panel() -> void:
	for c in list.get_children():
		c.queue_free()
	_header(list, "Click a building or the dock")
	_text(list, "Every building on the island opens its own menu: build it, buy more, upgrade it. The dock opens fishing boats and the harbor.")
	_button(list, "Open Dock and Harbor", 0.0, true, func(): open_menu_for("fish"))
	# Shortcuts in case the ship or letterbox is off screen
	if Game.pending_offer >= 0 and Game.pending_push < 0 and not offer_open:
		_button(list, "Visitors are waiting at the dock: talk to them", 0.0, true, open_visitors)
	if Game.news_unread:
		_button(list, "Mail in the letterbox: read the paper", 0.0, true, open_newspaper)

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
		# Only your own champion's building is listed
		if Game.is_champion_building(key) and key != Game.champion_building():
			continue
		var open: bool = Game.build_blockers(key).is_empty() if Game.is_champion_building(key) else Game.tier_open(int(a.tier))
		var state := "built" if Game.built.has(key) else ("not built" if open else "locked")
		var label := "%s  (%s, champion)" % [a.name, state] if Game.is_champion_building(key) else "%s  (%s)" % [a.name, state]
		_button(list, label, 0.0, true, func(): open_menu_for(key))


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
		zones = ["harbor", "hidden"]
	# A ship away on a voyage can't be moved until it's back
	if b.zone == "voyage":
		var away := Label.new()
		away.text = "away on a voyage, back day %d" % int(b.back)
		row.add_child(away)
		list.add_child(row)
		return
	for z in zones:
		var btn := Button.new()
		btn.text = ({"harbor": "In port", "hidden": "Hide"}[z]) if dirty else z.capitalize()
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
	if zone == "voyage":
		# Away on a voyage: over the western horizon
		return Vector3(-160.0 - (i % 4) * 6.0, 0, -30.0 + (i / 4) * 6.0)
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
		var n: Node3D = boat_nodes[i]
		n.set_color(BOAT_COLORS[b.kind])
		var was: String = n.get_meta("zone", zone)
		n.set_meta("zone", zone)
		var spot := _spot_for(zone, b.kind, idx)
		if zone == "voyage" and was != "voyage":
			# Setting off: a slow sail out to the horizon, then out of sight
			n.set_meta("busy_until", Time.get_ticks_msec() + VOYAGE_SAIL * 1000)
			n.sail_to(spot, VOYAGE_SAIL).finished.connect(func():
				if n.get_meta("zone", "") == "voyage":
					n.visible = false)
		elif was == "voyage" and zone != "voyage":
			# Home from a voyage: appears on the horizon and sails back in
			n.visible = true
			n.position = _spot_for("voyage", b.kind, idx)
			n.set_meta("busy_until", Time.get_ticks_msec() + VOYAGE_SAIL * 1000)
			n.sail_to(spot, VOYAGE_SAIL)
		elif Time.get_ticks_msec() >= int(n.get_meta("busy_until", 0)):
			# Not mid-voyage-sail: move to its spot as usual
			n.visible = zone != "voyage"
			n.sail_to(spot, seconds)


# ---------- The day ----------

func _on_start_day() -> void:
	if animating or Game.over or Game.pending_push >= 0 or Game.pending_offer >= 0 or not Game.pending_pick.is_empty() or not Game.story.is_empty():
		return
	animating = true
	$UI/Actions/StartDay.disabled = true
	# Boats head out a little before the weather shows
	for n in boat_nodes:
		if n.visible and Time.get_ticks_msec() >= int(n.get_meta("busy_until", 0)):
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
		summary += "   A visitors' ship is docking: click it!"
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
	$UI/Newspaper.visible = false
	offer_open = false
	close_menu()
	Game.new_run()
	_rebuild_boats()
	_show_weather("normal")
	$UI/TopBar/Row/Weather.text = "Weather: ?"
	refresh()


# ---------- My run: everything picked, and what it adds up to ----------

const PERK_NAMES := {
	"zone_fish_harbor": "Harbour fishing income", "zone_fish_deep": "Deep-sea fishing income",
	"survive_add": "Deep boats' storm survival", "home_add": "Lighthouse get-home chance",
	"fine": "Investigation fines", "suspicion": "Suspicion build-up", "launder_add": "Laundering rate",
	"rent_mult": "Rent", "rent_growth_add": "Rent growth per step", "upgrade_cost": "Upgrade prices",
	"build_cost": "Building prices", "storm_add": "Storm chance", "wrecks_add": "Extra wrecks per storm",
	"pots_add": "Pots per cray ship", "daily_add": "Daily bonus", "income_all": "All income",
	"risk_all": "All risks", "accuracy_add": "Forecast accuracy", "oil_find_add": "Oil survey odds",
	"survey_cost": "Survey prices", "news_swing": "How far news moves prices", "news_ahead_add": "Days of news warning",
	"warning_add": "Storm warning chance", "interest_add": "Weekly interest", "covers_add": "Silent Partner covers",
	"voyage_pay": "Voyage pay", "voyage_days_add": "Voyage length (days)", "price_mult": "Island price",
	"piracy_clean_add": "Piracy that comes in clean",
}


func _open_run_panel() -> void:
	$UI/RunPanel/Box/Text.text = _run_text()
	$UI/RunPanel.visible = true


func _avenue_name(key: String) -> String:
	if key == "fish":
		return "Fishing"
	return Game.data.avenues[key].name if Game.data.avenues.has(key) else key


func _perk_label(name: String) -> String:
	# A readable name for a perk, e.g. "income_pearl" -> "Pearl Diving income"
	if PERK_NAMES.has(name):
		return PERK_NAMES[name]
	for pre in ["income_", "risk_", "unit_cost_", "voyage_pay_", "voyage_catch_", "voyage_days_", "max_", "step_"]:
		if name.begins_with(pre):
			var key := name.substr(pre.length()).trim_suffix("_add")
			var what: String = {"income_": "income", "risk_": "risk (storm harm, catches, suspicion)", "unit_cost_": "unit price", "voyage_pay_": "voyage pay", "voyage_catch_": "voyage catch chance", "voyage_days_": "voyage length (days)", "max_": "unit cap", "step_": "upgrades"}[pre]
			if pre == "step_":
				return "%s upgrades per level" % key.capitalize()
			return "%s %s" % [_avenue_name(key), what]
	return name


func _pct(x: float) -> String:
	return "%d%%" % int(round(x * 100.0))


func _mult_text(m: float) -> String:
	# 1.25 -> "+25%", 0.8 -> "-20%"
	var d := int(round((m - 1.0) * 100.0))
	return ("+%d%%" % d) if d >= 0 else ("%d%%" % d)


func _run_text() -> String:
	var t := "[font_size=26][b]My run[/b][/font_size]   Day %d, season %d\n\n" % [Game.day, Game.season]

	# Who you chose
	t += "[b]Crown:[/b] %s\n   Good: %s\n   Bad: %s\n" % [Game.crown.name, Game.crown.good, Game.crown.bad]
	if Game.defected:
		t += "   (You defected. Crowns served: %s)\n" % ", ".join(Game.served.map(func(i): return Game.data.crowns.list[i].name))
	if Game.champion_index >= 0:
		var c: Dictionary = Game.champion()
		t += "[b]Champion:[/b] %s\n   Good: %s\n   Bad: %s\n" % [c.name, c.good, c.bad]
		for cp in c.paths:
			var ps: Array = Game.paths_for(cp.avenue)
			for i in ps.size():
				if ps[i].has("avenue") and ps[i].name == cp.name:
					t += "   %s (%s): level %d\n" % [cp.name, _avenue_name(cp.avenue), Game.levels[cp.avenue][i]]
	t += "\n"

	# This season
	t += "[b]This season[/b]\n   %s\n   Favours: %d   Strikes: %d / %d\n\n" % [Game.levy_text(), Game.favour, Game.strikes, int(Game.data.levy.max_strikes)]

	# Everything picked along the way
	t += "[b]Sea conditions[/b]\n"
	for c in Game.data.conditions.list:
		if Game.conditions_now.has(c.id):
			t += "   %s: %s\n" % [c.name, c.text]
	t += "\n[b]Boons[/b]\n"
	if Game.boons_taken.is_empty():
		t += "   none yet\n"
	for b in Game.data.boons.list:
		if Game.boons_taken.has(b.id):
			t += "   %s: %s\n" % [b.name, b.text]
	t += "\n[b]Advisors[/b]\n"
	if Game.advisors_met.is_empty():
		t += "   none yet\n"
	for key in Game.advisors_met:
		var ad: Dictionary = Game.data.advisors.list[key]
		var pick: Dictionary = ad[Game.advisors_met[key]]
		t += "   %s (%s): %s. %s\n" % [ad.who, _avenue_name(key), pick.name, pick.text]
	t += "\n[b]Visitors' offers taken[/b]\n"
	if Game.offers_done.is_empty():
		t += "   none yet\n"
	for o in Game.data.offers.list:
		if Game.offers_done.has(o.id):
			var po: Dictionary = o[Game.offers_done[o.id]]
			t += "   %s: %s\n" % [po.who, po.effect]

	# Short-lived effects (events and decrees)
	if not Game.active_effects.is_empty():
		t += "\n[b]For now (events and decrees)[/b]\n"
		for a in Game.active_effects:
			var v: String = _mult_text(float(a.mult)) if a.has("mult") else (("+" if float(a.add) >= 0 else "") + str(float(a.add)))
			t += "   %s %s, until day %d\n" % [_perk_label(a.perk), v, int(a.until)]

	# What it all adds up to
	t += "\n[b]What it all adds up to[/b]\n"
	if Game.built.has("deep"):
		var s_c: float = Game.survive_chance()
		var h_c: float = Game.home_chance()
		t += "   Deep boats in a storm: survive %s, then the lighthouse saves %s of the rest. About %s of deep boats are lost per storm.\n" % [_pct(s_c), _pct(h_c), _pct((1.0 - s_c) * (1.0 - h_c))]
	for key in ["whaling", "oil"]:
		if Game.built.has(key):
			var base: float = float(Game.data.storm_damage.chance.get(key, 0.0))
			t += "   %s: storm damage chance per unit %s (normally %s).\n" % [_avenue_name(key), _pct(Game.damage_chance(key)), _pct(base)]
	for key in ["crab", "cray", "smuggle", "piracy", "hiding"]:
		if Game.built.has(key) and abs(Game.risk(key) - 1.0) > 0.001:
			t += "   %s risk: %s of normal.\n" % [_avenue_name(key), _pct(Game.risk(key))]
	for key in ["smuggle", "piracy"]:
		if Game.built.has(key):
			var parts := []
			for li in Game.data.voyages.lengths.size():
				parts.append("%s %s" % [Game.data.voyages.lengths[li].name.to_lower(), _pct(Game.voyage_catch(key, li))])
			t += "   %s voyages caught: %s.\n" % [_avenue_name(key), ", ".join(parts)]
	t += "   Fines %s   Suspicion build-up %s   Laundering keeps %s\n" % [_pct(Game.perk("fine")), _pct(Game.perk("suspicion")), _pct(Game.launder_rate())]
	t += "   Rent %s   Upgrades cost %s   Buildings cost %s\n" % [_pct(Game.perk("rent_mult")), _pct(Game.perk("upgrade_cost")), _pct(Game.perk("build_cost"))]
	var inc := []
	for key in ["fish"] + Game.data.avenues.keys():
		if key != "fish" and not Game.built.has(key):
			continue
		# Income from picks only (not upgrades or supply chains)
		var m: float = Game.perk("income_" + key) * Game.perk("income_all") * float(Game.crown.buffs.get(key, 1.0))
		if abs(m - 1.0) > 0.001:
			inc.append("%s %s" % [_avenue_name(key), _mult_text(m)])
	if not inc.is_empty():
		t += "   Income from your picks: " + ", ".join(inc) + "\n"
	return t


# ---------- Graphs: every number, every day ----------

const GRAPH_SCRIPT := preload("res://scripts/graph_view.gd")
# Line colours, given out in this order as lines are ticked (a line keeps its colour while ticked)
const LINE_COLORS := [Color("#3987e5"), Color("#d95926"), Color("#199e70"), Color("#c98500"), Color("#d55181"), Color("#008300"), Color("#9085e9"), Color("#e66767")]
# Running numbers: a week shows its last value, not a sum
const RUNNING := ["Cash", "Loan", "Island price", "Levy target", "Earned this season", "Suspicion", "Strikes"]
# Series name -> colour slot, for the lines ticked now
var graph_ticked: Dictionary = {}
var graph_view: Control
var graph_totals: RichTextLabel
var graph_range: OptionButton
var graph_mode: OptionButton


func _make_graphs_panel() -> void:
	var b := Button.new()
	b.text = "  Graphs  "
	b.pressed.connect(_open_graphs)
	$UI/TopBar/Row.add_child(b)
	var panel := PanelContainer.new()
	panel.name = "GraphPanel"
	panel.visible = false
	$UI.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 56
	panel.offset_right = -40
	panel.offset_bottom = -40
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	# Left: what to show
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var left := VBoxContainer.new()
	left.name = "Left"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(left)
	graph_range = OptionButton.new()
	for t in ["Whole run", "Last 4 weeks", "Last week"]:
		graph_range.add_item(t)
	graph_range.item_selected.connect(func(_i): _draw_graphs())
	left.add_child(graph_range)
	graph_mode = OptionButton.new()
	for t in ["Each day", "Each week (added up)"]:
		graph_mode.add_item(t)
	graph_mode.item_selected.connect(func(_i): _draw_graphs())
	left.add_child(graph_mode)
	for group in Game.HISTORY_GROUPS:
		var h := Label.new()
		h.text = group
		h.add_theme_font_size_override("font_size", 18)
		left.add_child(h)
		for s in Game.HISTORY_GROUPS[group]:
			var cb := CheckBox.new()
			cb.name = "Tick_" + s
			cb.text = s
			cb.toggled.connect(func(on): _tick_series(s, on, cb))
			left.add_child(cb)
	# Right: the graph, the totals and a close button
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	graph_view = GRAPH_SCRIPT.new()
	graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_view.custom_minimum_size = Vector2(400, 300)
	right.add_child(graph_view)
	graph_totals = RichTextLabel.new()
	graph_totals.bbcode_enabled = true
	graph_totals.custom_minimum_size = Vector2(0, 190)
	right.add_child(graph_totals)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): panel.visible = false)
	right.add_child(close)
	# Start with the two lines most people want first
	for s in ["Cash", "Earned today"]:
		var cb2: CheckBox = left.get_node("Tick_" + s)
		cb2.button_pressed = true


func _tick_series(s: String, on: bool, cb: CheckBox) -> void:
	if on:
		var used: Array = graph_ticked.values()
		var slot := -1
		for i in LINE_COLORS.size():
			if not used.has(i):
				slot = i
				break
		if slot < 0:
			# Eight lines at most, so every line keeps a colour you can tell apart
			cb.set_pressed_no_signal(false)
			graph_totals.text = "[color=#ff9a7a]Eight lines at most. Untick one first.[/color]"
			return
		graph_ticked[s] = slot
		cb.add_theme_color_override("font_color", LINE_COLORS[slot])
		cb.add_theme_color_override("font_pressed_color", LINE_COLORS[slot])
		cb.add_theme_color_override("font_hover_pressed_color", LINE_COLORS[slot])
	else:
		graph_ticked.erase(s)
		cb.remove_theme_color_override("font_color")
		cb.remove_theme_color_override("font_pressed_color")
		cb.remove_theme_color_override("font_hover_pressed_color")
	_draw_graphs()


func _open_graphs() -> void:
	$UI/GraphPanel.visible = true
	_draw_graphs()


func _graph_values(s: String, from_day: int) -> Array:
	var a: Array = Game.history.get(s, [])
	var vals: Array = a.slice(from_day - 1)
	if graph_mode.selected == 0:
		return vals
	var out := []
	for i in range(0, vals.size(), 7):
		var chunk: Array = vals.slice(i, i + 7)
		if RUNNING.has(s):
			out.append(chunk[-1])
		else:
			var t := 0.0
			for v in chunk:
				t += float(v)
			out.append(t)
	return out


func _draw_graphs() -> void:
	if graph_view == null or not $UI/GraphPanel.visible:
		return
	var from_day := 1
	if graph_range.selected == 1:
		from_day = max(1, Game.day - 27)
	elif graph_range.selected == 2:
		from_day = max(1, Game.day - 6)
	var weekly: bool = graph_mode.selected == 1
	graph_view.x_name = "Week" if weekly else "Day"
	graph_view.first_x = from_day
	if weekly:
		graph_view.first_x = (from_day - 1) / 7 + 1
	graph_view.lines = []
	var days_shown: int = max(1, Game.day - from_day + 1)
	var t := "[b]Totals[/b]   (hover the graph to read any day)\n"
	for s in graph_ticked:
		var col: Color = LINE_COLORS[graph_ticked[s]]
		graph_view.lines.append({"name": s, "values": _graph_values(s, from_day), "color": col})
		var a: Array = Game.history.get(s, [])
		var last: float = float(a[-1]) if a.size() > 0 else 0.0
		t += "[color=#%s]■[/color] %s: " % [col.to_html(false), s]
		if RUNNING.has(s):
			t += "now %s\n" % _graph_num(s, last)
		else:
			var in_range: float = Game.history_total(s, from_day)
			t += "whole run %s   |   shown %s   |   %s a day on average\n" % [_graph_num(s, Game.history_total(s)), _graph_num(s, in_range), _graph_num(s, in_range / days_shown)]
	if graph_ticked.is_empty():
		t += "Nothing ticked.\n"
	graph_totals.text = t
	graph_view.queue_redraw()


func _graph_num(s: String, v: float) -> String:
	# Counts and suspicion aren't money
	if ["Suspicion", "Strikes", "Boats sunk", "Ships caught"].has(s):
		return str(snapped(v, 0.1))
	return Game.money(v)


# ---------- Talk panels: someone tells you when the story moves ----------

var talk_face: ColorRect
var talk_initials: Label
var talk_text: RichTextLabel
var talk_ok: Button


func _make_talk_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "TalkPanel"
	panel.visible = false
	$UI.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.custom_minimum_size = Vector2(820, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -70
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	# Portrait slot: a coloured square with initials until the 2D portraits are drawn
	talk_face = ColorRect.new()
	talk_face.custom_minimum_size = Vector2(130, 130)
	talk_face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(talk_face)
	talk_initials = Label.new()
	talk_initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	talk_initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	talk_initials.add_theme_font_size_override("font_size", 40)
	talk_face.add_child(talk_initials)
	talk_initials.set_anchors_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	talk_text = RichTextLabel.new()
	talk_text.bbcode_enabled = true
	talk_text.fit_content = true
	talk_text.custom_minimum_size = Vector2(640, 0)
	col.add_child(talk_text)
	talk_ok = Button.new()
	talk_ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	talk_ok.pressed.connect(func(): Game.read_story())
	col.add_child(talk_ok)


func _update_talk() -> void:
	var panel: Control = $UI/TalkPanel
	panel.visible = not Game.story.is_empty() and not Game.over
	if not panel.visible:
		return
	var s: Dictionary = Game.story[0]
	# Each speaker keeps one colour so you learn who's who
	talk_face.color = Color.from_hsv(float(abs(hash(s.who)) % 360) / 360.0, 0.45, 0.55)
	var ini := ""
	for w in str(s.who).replace("The ", "").replace("'s", "").split(" "):
		if w != "":
			ini += w[0]
	talk_initials.text = ini.substr(0, 2)
	var t := "[font_size=22][b]%s[/b][/font_size]  [color=#aaaaaa]%s[/color]\n" % [s.who, s.role]
	if s.title != "":
		t += "[font_size=18][b]%s[/b][/font_size]   [color=#aaaaaa]day %d[/color]\n" % [s.title, int(s.day)]
	t += "\n" + s.text
	talk_text.text = t
	talk_ok.text = "Got it" if Game.story.size() == 1 else "Next (%d more)" % (Game.story.size() - 1)


# ---------- The mail boat, the postman and the letterbox ----------

const MAIL_BERTH := Vector3(-4.0, 0, 26.0)
const MAIL_FAR := Vector3(-60.0, 0, 80.0)
const LETTERBOX_AT := Vector3(-2.6, 3.0, 13.4)
# The one plot where your champion's own building stands (between the cove, salvage yard and weather bureau)
const CHAMPION_PLOT := Vector3(-3.0, 4.0, -4.5)
const VISITOR_BERTH := Vector3(6.5, 0, 27.0)
const VISITOR_FAR := Vector3(70.0, 0, 80.0)
var mail_boat: Node3D
var postman: Node3D
var letterbox: Node3D
var visitor_ship: Node3D
# "away" (no paper waiting), "busy" (delivering), "done" (paper in the box)
var mail_state := "away"
# "away", "coming", "docked"
var visitor_state := "away"
# The Visitors panel only opens when you click their ship
var offer_open := false


func _mesh(m: Mesh, color: Color, pos: Vector3, parent: Node3D, emit := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emit:
		mat.emission_enabled = true
		mat.emission = color
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _click_body(parent: Node3D, size: Vector3, offset := Vector3.ZERO) -> void:
	# Same "Click" StaticBody3D as the buildings, so _unhandled_input finds it
	var body := StaticBody3D.new()
	body.name = "Click"
	body.position = offset
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


func _make_champion_buildings() -> void:
	# GREYBOX placeholders: one plot, and only your champion's building shows on it. Real models still to make.
	var colours := [Color(0.85, 0.75, 0.3), Color(0.4, 0.6, 0.35), Color(0.55, 0.75, 0.85), Color(0.75, 0.45, 0.6), Color(0.55, 0.4, 0.3)]
	var n := 0
	for key in Game.data.avenues:
		if not Game.is_champion_building(key):
			continue
		var b := MeshInstance3D.new()
		b.name = key
		var m := _box(Vector3(3, 2.4, 3))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colours[n % colours.size()]
		m.material = mat
		b.mesh = m
		b.position = CHAMPION_PLOT
		$Buildings.add_child(b)
		var tag := Label3D.new()
		tag.name = "Tag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.4, 0)
		tag.pixel_size = 0.02
		tag.font_size = 64
		tag.outline_size = 14
		b.add_child(tag)
		_click_body(b, Vector3(3.4, 2.8, 3.4))
		b.visible = false
		n += 1


func _make_mail_props() -> void:
	# GREYBOX placeholders: the real letterbox, mail boat and TABS-style postman are models still to make
	letterbox = Node3D.new()
	letterbox.name = "Letterbox"
	letterbox.position = LETTERBOX_AT
	add_child(letterbox)
	_mesh(_box(Vector3(0.2, 1.4, 0.2)), Color(0.45, 0.3, 0.18), Vector3(0, 0.7, 0), letterbox)
	_mesh(_box(Vector3(0.7, 0.55, 1.1)), Color(0.25, 0.3, 0.6), Vector3(0, 1.65, 0), letterbox)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.35
	roof.bottom_radius = 0.35
	roof.height = 1.1
	var r := _mesh(roof, Color(0.25, 0.3, 0.6), Vector3(0, 1.92, 0), letterbox)
	r.rotation_degrees = Vector3(90, 0, 0)
	# The door flicks open on its bottom hinge
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(0, 1.4, 0.56)
	letterbox.add_child(door)
	_mesh(_box(Vector3(0.66, 0.8, 0.05)), Color(0.3, 0.36, 0.7), Vector3(0, 0.4, 0), door)
	# The red flag, hinged at its base: lying down = no mail, standing up = mail
	var flag := Node3D.new()
	flag.name = "Flag"
	flag.position = Vector3(0.38, 1.6, -0.2)
	letterbox.add_child(flag)
	_mesh(_box(Vector3(0.05, 0.8, 0.08)), Color(0.85, 0.1, 0.1), Vector3(0, 0.4, 0), flag)
	_mesh(_box(Vector3(0.05, 0.25, 0.35)), Color(0.85, 0.1, 0.1), Vector3(0, 0.7, 0.18), flag)
	# The little light on top
	var bulb := SphereMesh.new()
	bulb.radius = 0.14
	bulb.height = 0.28
	var bm := _mesh(bulb, Color(1.0, 0.85, 0.3), Vector3(0, 2.35, 0), letterbox, true)
	bm.name = "Bulb"
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.85, 0.4)
	lamp.light_energy = 3.0
	lamp.omni_range = 5.0
	lamp.position = Vector3(0, 2.6, 0)
	letterbox.add_child(lamp)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 3.3, 0)
	tag.font_size = 48
	tag.outline_size = 8
	letterbox.add_child(tag)
	_click_body(letterbox, Vector3(1.4, 3.0, 1.6), Vector3(0, 1.5, 0))
	_set_letterbox(false)

	mail_boat = BOAT_SCENE.instantiate()
	mail_boat.name = "MailBoat"
	add_child(mail_boat)
	mail_boat.set_color(Color(0.9, 0.9, 0.95))
	mail_boat.position = MAIL_FAR
	mail_boat.visible = false

	postman = Node3D.new()
	postman.name = "Postman"
	add_child(postman)
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.2
	_mesh(body, Color(0.2, 0.3, 0.65), Vector3(0, 0.6, 0), postman)
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	_mesh(head, Color(0.95, 0.8, 0.65), Vector3(0, 1.45, 0), postman)
	_mesh(_box(Vector3(0.5, 0.4, 0.2)), Color(0.5, 0.35, 0.2), Vector3(0.35, 0.7, 0.1), postman)
	var pl := Label3D.new()
	pl.text = "Postman (placeholder)"
	pl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pl.font_size = 36
	pl.outline_size = 6
	pl.position = Vector3(0, 2.2, 0)
	postman.add_child(pl)
	postman.visible = false

	visitor_ship = BOAT_SCENE.instantiate()
	visitor_ship.name = "VisitorShip"
	add_child(visitor_ship)
	visitor_ship.set_color(Color(0.55, 0.2, 0.6))
	visitor_ship.scale = Vector3(1.6, 1.6, 1.6)
	visitor_ship.position = VISITOR_FAR
	visitor_ship.visible = false
	var vt := Label3D.new()
	vt.text = "Visitors\n(click)"
	vt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	vt.font_size = 40
	vt.outline_size = 8
	vt.position = Vector3(0, 2.4, 0)
	visitor_ship.add_child(vt)
	_click_body(visitor_ship, Vector3(2.5, 2.5, 4.0), Vector3(0, 1.0, 0))


func _set_letterbox(mail: bool) -> void:
	letterbox.get_node("Flag").rotation_degrees.x = 0.0 if mail else -90.0
	letterbox.get_node("Lamp").visible = mail
	var bulb: MeshInstance3D = letterbox.get_node("Bulb")
	var mat: StandardMaterial3D = bulb.material_override
	mat.emission_enabled = mail
	mat.albedo_color = Color(1.0, 0.85, 0.3) if mail else Color(0.35, 0.33, 0.3)
	letterbox.get_node("Tag").text = "Mail! (click)" if mail else ""


func _update_mail() -> void:
	if Game.news_unread and mail_state == "away" and not animating:
		_deliver_mail()
	elif not Game.news_unread and mail_state == "done":
		mail_state = "away"
		_set_letterbox(false)


func _deliver_mail() -> void:
	# Boat docks, postman walks up the dock, flicks the box open, flag up, light on, then they leave
	mail_state = "busy"
	mail_boat.visible = true
	mail_boat.position = MAIL_FAR
	await mail_boat.sail_to(MAIL_BERTH, 2.5).finished
	postman.visible = true
	postman.position = MAIL_BERTH + Vector3(2.5, 0.65, -1.5)
	var walk := create_tween()
	walk.tween_property(postman, "position", Vector3(0, 0.65, 15.0), 1.6)
	walk.tween_property(postman, "position", LETTERBOX_AT + Vector3(0, 0, 1.2), 0.9)
	await walk.finished
	var door: Node3D = letterbox.get_node("Door")
	var flick := create_tween()
	flick.tween_property(door, "rotation_degrees:x", 80.0, 0.2)
	flick.tween_interval(0.3)
	flick.tween_property(door, "rotation_degrees:x", 0.0, 0.2)
	flick.tween_property(letterbox.get_node("Flag"), "rotation_degrees:x", 0.0, 0.3)
	await flick.finished
	_set_letterbox(true)
	mail_state = "done"
	var back := create_tween()
	back.tween_property(postman, "position", Vector3(0, 0.65, 15.0), 0.9)
	back.tween_property(postman, "position", MAIL_BERTH + Vector3(2.5, 0.65, -1.5), 1.6)
	await back.finished
	postman.visible = false
	await mail_boat.sail_to(MAIL_FAR, 2.5).finished
	mail_boat.visible = false
	# Read before the boat even left
	if not Game.news_unread:
		mail_state = "away"
		_set_letterbox(false)


func _update_visitor_ship() -> void:
	var here: bool = Game.pending_offer >= 0 and Game.pending_push < 0 and not Game.over
	if here and visitor_state == "away":
		visitor_state = "coming"
		visitor_ship.visible = true
		visitor_ship.position = VISITOR_FAR
		visitor_ship.sail_to(VISITOR_BERTH, 3.0).finished.connect(func():
			if visitor_state == "coming":
				visitor_state = "docked")
	elif not here and visitor_state != "away":
		visitor_state = "away"
		offer_open = false
		visitor_ship.sail_to(VISITOR_FAR, 3.0).finished.connect(func():
			if visitor_state == "away":
				visitor_ship.visible = false)


func open_visitors() -> void:
	if Game.pending_offer >= 0:
		offer_open = true
		refresh()


# ---------- The newspaper ----------

var paper_text: RichTextLabel


func _make_newspaper_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "Newspaper"
	panel.visible = false
	$UI.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Off-white paper
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.9, 0.82)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	panel.add_child(col)
	paper_text = RichTextLabel.new()
	paper_text.bbcode_enabled = true
	paper_text.fit_content = true
	paper_text.add_theme_color_override("default_color", Color(0.1, 0.1, 0.1))
	col.add_child(paper_text)
	var close := Button.new()
	close.text = "Fold the paper"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func():
		panel.visible = false
		Game.news_unread = false
		refresh())
	col.add_child(close)


func open_newspaper() -> void:
	var week: int = max(0, Game.day - 1) / 7 + 1
	var t := "[center][font_size=34][b]THE ROCK GAZETTE[/b][/font_size]\n[font_size=14]Week %d  ·  Day %d[/font_size][/center]\n\n" % [week, Game.day]
	t += "[font_size=26][b]%s[/b][/font_size]\n\n" % (Game.news.text if Game.news.has("text") else "Quiet week on the water")
	if Game.event_text() != "":
		t += "[b]Down at the docks:[/b] word is of %s.\n\n" % Game.event_text()
	if Game.news_preview_text() != "":
		t += "[b]Market whispers:[/b] %s\n\n" % Game.news_preview_text()
	t += "[b]From the Crown:[/b] %s\n\n" % Game.levy_text()
	# Your own last week, from the history
	var from_day: int = max(1, Game.day - 6)
	t += "[b]Your island, last 7 days[/b]\n"
	var best := ""
	var best_v := 0.0
	for s in Game.HISTORY_GROUPS["Income by avenue"]:
		var v: float = Game.history_total(s, from_day)
		if v > best_v:
			best_v = v
			best = s
	t += "   Earned %s." % Game.money(Game.history_total("Earned today", from_day))
	if best != "":
		t += " Best earner: %s (%s)." % [best, Game.money(best_v)]
	t += "\n   Rent %s, tax %s." % [Game.money(Game.history_total("Rent", from_day)), Game.money(Game.history_total("Tax", from_day))]
	var cb := Game.champion_building()
	if cb != "" and Game.history_total(Game.data.avenues[cb].name) > 0:
		t += " Your %s earned %s." % [Game.data.avenues[cb].name, Game.money(Game.history_total(Game.data.avenues[cb].name, from_day))]
	t += "\n\n[font_size=14][i]Open Graphs (top bar) for every number of every day.[/i][/font_size]"
	paper_text.text = t
	$UI/Newspaper.visible = true


# ---------- Camera: scroll to zoom, right-drag (or Q / E) to turn around the island ----------

# Closest and furthest the camera may be from the point it looks at
const ZOOM_MIN := 30.0
const ZOOM_MAX := 130.0
const ZOOM_STEP := 0.1
# Degrees turned per pixel of right-drag, and per second holding Q or E
const TURN_DRAG := 0.3
const TURN_KEYS := 70.0
var cam_target := Vector3.ZERO
var cam_dist := 60.0
var cam_yaw := 0.0
var cam_pitch := 0.0
var cam_dragging := false
# The look point at the start, and the turn at the start (turning swings the look point around the island centre)
var cam_target0 := Vector3.ZERO
var cam_yaw0 := 0.0


func _setup_camera() -> void:
	# Start from wherever the camera sits in main.tscn: find the sea-level point it looks at
	var cam: Camera3D = $Camera3D
	var fwd: Vector3 = -cam.global_transform.basis.z
	var pos: Vector3 = cam.global_position
	var t: float = -pos.y / fwd.y if abs(fwd.y) > 0.01 else 60.0
	cam_target = pos + fwd * t
	var off: Vector3 = pos - cam_target
	cam_dist = off.length()
	cam_yaw = atan2(off.x, off.z)
	cam_pitch = asin(off.y / cam_dist)
	cam_target0 = cam_target
	cam_yaw0 = cam_yaw
	_apply_camera()


func _apply_camera() -> void:
	var cam: Camera3D = $Camera3D
	# The island centre is (0, 0, 0), so the whole view circles the island
	cam_target = cam_target0.rotated(Vector3.UP, cam_yaw - cam_yaw0)
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	cam.global_position = cam_target + off
	cam.look_at(cam_target, Vector3.UP)


func _camera_input(event: InputEvent) -> bool:
	# Returns true when the event was used by the camera
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = clamp(cam_dist * (1.0 - ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
			_apply_camera()
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = clamp(cam_dist * (1.0 + ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
			_apply_camera()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cam_dragging = event.pressed
			return true
	if event is InputEventMouseMotion and cam_dragging:
		cam_yaw -= deg_to_rad(event.relative.x * TURN_DRAG)
		_apply_camera()
		return true
	return false


func _process(delta: float) -> void:
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		turn -= 1.0
	if turn != 0.0:
		cam_yaw += deg_to_rad(turn * TURN_KEYS * delta)
		_apply_camera()
