FISHOPOLY - FIRST GREYBOX (11 Nov 2026)

HOW TO OPEN
1. Open Godot 4.7.2 (Desktop\Godot\Godot_v4.7.2-stable_win64.exe).
2. In the Project Manager click Import, pick this folder's project.godot, then Open.
3. Press F5 (or the Play button, top right) to play.

HOW TO PLAY (also shown in the game: the How to play panel, and the ? button at the top)
- Click a building on the island (or the dock) to open its menu: build it, buy more, upgrade it.
  Faint buildings aren't built yet. The right panel sets where boats work and lists every building.
- Each boat row lets you choose Harbor (safe, earns less, limited spaces), Deep (more money, sinks in storms)
  or Dock (does nothing).
- Press Start Day. The weather is rolled in secret and shown once the boats head out.
- Every 7 days you pay rent and tax. If you can't pay, the Silent Partner lends the rest.
  Repay in 7 days or your things get sold.
- Save $190,000,000 and press Buy the Island to win.
- Tier 2 (Salvage Yard, Treasure Hunters, Whaling Station) opens when you own every tier 1 building and every
  tier 1 upgrade path (fishing too) is at least level 1. Each tier 2 building boosts a tier 1 avenue (supply chains).
- Buildings come with their first unit. Every shop button shows roughly what it earns per day.
- The top bar shows how much is safe to spend before rent. Buttons turn orange if a buy would leave you short.

WHERE THINGS ARE
- data/balance.json    every number (prices, payouts, rent, tax, storm odds). Edit it, save, press F5 again.
- scenes/main.tscn     the island, harbor, deep sea, building plots, camera, light and UI panels.
                       All real nodes, so you can move or reshape them in the editor.
                       The building boxes live under "Buildings" (hidden until built).
                       The boat parking spots are the Marker3D nodes under "Spots".
- scenes/boat.tscn     the greybox boat.
- scripts/game.gd      the rules (money, weather, bills, loans, buying). No visuals.
- scripts/main.gd      draws the rules: boats, weather look, shop buttons, log.
- scripts/boat.gd      boat bobbing, sailing and sinking.
- tests/autoplay.gd    a robot that plays 60 runs with the real rules and prints the win rate.
- tests/shot.tscn      takes screenshots (saved to AppData\Roaming\Godot\app_userdata\Fishopoly).

WHAT'S IN (everything from the economy tests)
- Tier 1: harbor fishing, deep sea dock (fishing and crab boats can go deep; Hull 20% -> 60% survival),
  pearl diving (max 2), crab boats, cray potting (orange ships with yellow pot buoys). Tier 2: salvage, treasure (6-item loot table), whaling.
  Tier 3 (dirty money, laundered at 70%): smugglers' cove, hidden moorings, pirate haven. Tier 4: oil platform.
- Unlocks: own every building in the tier below and get its upgrade paths to level 1 / 6 / 7.
- Supply chains: later avenues lift earlier ones (+25% per unit, up to 10).
- Visitors (replaced safe / greedy): after weekly bills, two people offer rival upgrades for something you own.
  Pay for one (the other leaves for good) or say Not now. All 12 offers are in data/balance.json under "offers".
- Suspicion and investigations (lose a day's earnings, rising fines, ships seized; hidden ships safe).
- Storm damage to oil rigs and whaling ships (repairs cost money). Pirate ships are never damaged; they need storms.
- Dirty money is not taxed (only clean income counts for tax).
- Crowns: pick 1 of 6 at the start (Lord Admiral, Merchant Admiral, Queen's Privateer, Treasure Fleet, Turtle Ship,
  Iron Fleet; each has a good and a bad side, see data/balance.json crowns.list). A random Crown you haven't served
  pushes as you get rich, in place of a season's decree: stay and that season's levy goes up (x1.5 / x2 / x3), or defect once (new buffs and drawbacks, dearer island, 10% of crews leave).
- Crown levies (4-week targets, strikes, decrees from season 6), Australian-style tax bands on clean money only, weekly news (one market up or down 50%), the Silent Partner.
- Run log: every real run is saved to AppData\Roaming\Godot\app_userdata\Fishopoly\run_logs
un_logs.

BUILT 12 NOV (LATER)
- Champions: pick 1 of 10 at the start (data/balance.json champions). Good side, bad side, champion-only
  upgrades. 3 unlocked from the start; the rest unlock by playing (saved in user://meta.json).
- Advisors: one per avenue, A/B choice when you build it (both have a catch).
- Voyages and the bounty board: smuggling/pirate ships wait in port or go on 2/4/7-day voyages.
- Wildcat well (cheap early oil), Crown favour (beat a levy by 50%), Iron Fleet and Privateer fixes.
- Mid-run save: user://save_run.txt, saved every day; the game offers to continue on start.
- tests/uicheck.tscn: headless check that drives every new panel and menu.
- My run panel (top bar): Crown, champion, conditions, boons, advisors, visitors, this season, and what it all
  adds up to (storm survival, damage, risks, fines, rent, income from picks). Nodes in main.tscn UI/RunPanel.

NOT IN YET
Characters and portraits (other than Crown names), sound, real art.

CHANGES AFTER LIAM'S FIRST PLAY (11 Nov 2026)
- In-game help, earnings on every button, rent warnings, a daily summary.
- Buildings include their first unit (pearl diving used to do nothing until you bought a spot).
- Gentler start: $500 cash, rent from $100 a week (was $200 and $130).
- Docked boats move into free harbor spaces by themselves.

ROBOT CHECK (60 runs each): careful robot 96% wins (day 122); careless robot that buys the cheapest thing 100% (day 166).
This is easy on purpose for a first play. Difficulty is the rent numbers in data/balance.json.


TIER 2 UPDATE (11 Nov 2026)
- Tier 2 added, building menus open by clicking buildings, island now $300,000.
- Robot check: careful robot 96% wins (median day 180, built tier 2 in 58 of 60 runs); careless robot 58%.
- Click test: clicking Crab Boats opens its menu, clicking the dock opens Dock and Harbor.

FULL GAME UPDATE (11 Nov 2026)
- Tiers 3 and 4, suspicion, Crowns, storm damage, styles, news, run logs added. Island $150,000,000.
- Robot check (60 runs): careful robot 30% wins (median day 312, ~73 min at 14 s a day), reaches oil in 54 of 60 runs.
  Careless robot 0% (never reaches oil).

FISHING BUFF (11 Nov 2026, after Liam's run)
- Harbor boats catch 50% on normal and storm days (was 30%): about $58/day each.
- Deep fishing pays $400 perfect / $220 normal (was $289 / $145): about $146/day at 20% survival, $179 at 60%.
- Island $110,000,000 to keep wins at 30% (careful robot, median day 271, about 63 min).
- 12 Nov: safe/greedy removed, replaced by Visitors' offers. Island $170,000,000 (careful robot 31% wins, median day 303).
- 12 Nov: Island $190,000,000. Careful robot 36% wins (median win day 335). Liam: keep it.
- 12 Nov: Silent Partner warnings: 3 covers a run, each dearer with less time; a warning wears off after 8 quiet weeks. Robot that saves for the full bill wins 45%; robot that relies on loans 0-3%.
- 12 Nov: Oil surveys + permit bribes. Later 12 Nov: oil can be hunted from day 1 ($5,000 surveys), platform takes 4 weeks to build. Luck: 2 sea conditions per run, pick 1 of 3 boons when a tier opens, Visitors in random order, 12 random events with 3-day warnings. All in balance.json: oil_search, conditions, boons, events.
