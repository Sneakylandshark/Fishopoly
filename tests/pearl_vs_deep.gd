extends SceneTree
## One-off check: pearls vs deep-sea fishing, using the real rules. Spend and average earnings per day.
func _process(_d):
	var g = load("res://scripts/game.gd").new()
	root.add_child(g)
	g.load_balance()
	print("level | PEARL: total spent, earns/day (2 spots) | DEEP FISHING: total spent, earns/day (4 deep boats, hull maxed)")
	for L in range(0, 7):
		# Pearls: building + 2 spots + every pearl path to level L
		g.new_run(1)
		g.cash = 10000000
		var c0: float = g.cash
		g.build("pearl")
		g.buy_unit("pearl")
		for lvl in L:
			for i in 3:
				g.upgrade("pearl", i)
		var pearl_spent: float = c0 - g.cash
		var pearl_day: float = g.avg_per_day("pearl") * g.pearl_spots
		# Deep fishing: dock + hull to max + 3 more boats (4 total) + every fishing path to level L, all boats deep
		g.new_run(1)
		g.cash = 10000000
		c0 = g.cash
		g.build("deep")
		for h in 4:
			g.upgrade("deep", 0)
		for b in 3:
			g.buy_fishing_boat()
		for lvl in L:
			for i in 3:
				g.upgrade("fish", i)
		for i in g.boats.size():
			g.set_zone(i, "deep")
		var deep_spent: float = c0 - g.cash
		var deep_day: float = g.avg_per_day("fish_deep") * g.count_boats("fish", "deep")
		print("  %d   | $%d, $%d/day  (payback %d days) | $%d, $%d/day  (payback %d days)" % [L, pearl_spent, pearl_day, pearl_spent / pearl_day, deep_spent, deep_day, deep_spent / max(deep_day, 1.0)])
	return true
