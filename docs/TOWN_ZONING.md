# The Town Outside the Walls (zoning, first version)

City-builder zoning on the manor's own land in the realm: you lay roads and paint zones, and the
town builds itself. The village and the reaches it holds are zoned too, from the first day: homes,
farms, industry and civic buildings rise there on their own, free (see "Zoning the village").

## Playing it

- **Zone** (bottom bar) opens the zoning tools; **Done** or Esc closes them.
- **Road** (4 Wood a stretch): start at the village edge (gold squares) or beside an outpost.
  Drag to plan a straight run: the cells and the total cost show first, letting go lays it (as far
  as the Wood lasts). A tap lays one stretch.
- **Pave** (2 Stone a stretch): turns a road to cobbles. Drags plan a run the same way.
- **Homes, Farms, Industry, Civic**: tap or drag to paint 4 m cells beside your roads.
  **Brush** switches between 1x1 and 3x3. **Clear** removes zones, roads and lots.
- Painting never knocks down a built lot; only Clear does. Tapping a lot shows its card: what it
  sends, its next level's needs (green when met) and what speeds or slows it.
- With the tools out, each lot held back shows what it needs ("Needs farms"). Zoned cells with no
  road yet are dotted. The Civic tool tints the ground that is already safe.
- On phones one finger paints and two fingers move the map; **Move** makes one finger pan.

## Zoning the village

- From the first day, paint **Homes, Farms, Industry** or **Civic** on open village ground (the
  base village and any reach the manor holds). No roads are needed inside the walls and painting
  costs nothing.
- The village's own buildings then rise there by themselves, free, one or two at a time while no
  raid is on: cottages (later storehouses, bathhouses, longhouses) on Homes; farms, ponds, groves
  and pastures (later butcheries, mills, bakeries) on Farms; lumber camps, mines and timber yards
  (later sawmills, quarries, workshops) on Industry; chapels, scriptoria and schoolrooms on Civic.
  A building rises only where its whole footprint is zoned for it, nearest the Manor Hall first.
- Zones can sit side by side; the village keeps its ways in and out. A building rises only where
  it leaves a walkable way from the Manor Hall to its door and to its work stands, never on another
  building's work stand, never where it would wall anyone else in, and never on a paved road.
  Well-trodden trails are built on only when nothing else fits, so paths stay lanes.
- Each building that rises gets a dirt path from its door (its work stands, for a workplace) to the
  nearest path or the Hall, and the Hall keeps one path out to the village's edge (through an open
  gate when walled). These are the living village's own trails: villagers prefer them, they wear
  in with use, fade if nobody walks them, and can be paved. Paths are freshened one building at a
  time, so villages zoned before this get them too.
- If a hand-built wall or tower closes a zoned building in, a notice says so once.
- The simulation's own rules still apply: research and story locks, the village level, the
  building limits per level. Homes rise only while few beds stand empty, so the village grows into
  them. What the current quest asks for, or what a Raise button asked for, rises first.
- Zoned buildings move up a tier on their own, free, one at a time, once the village level allows
  it (tier 2 at level 2, tier 3 at level 4...). The **Manor Hall** rises a tier on its own once
  enough villagers live in the village (12 for tier 2, 24 for tier 3).
- The **Build** menu now sells only what is bought: walls, towers, traps, the gate and the
  barracks (plus the Great Works, Roads paving, and unlocked military trades). A Raise button for
  a farm or cottage (quests, the needs panel) opens its zone instead. Moving an existing building
  works as before.
- Village zones are kept in the town's save (`town-v1.json`, field `village`); the village save is
  untouched (zoned buildings are ordinary building records). Clear removes a zone, never a building.
- Which buildings belong to which zone, the pace (`growSeconds`, `upgradeSeconds`, `maxRising`,
  `bedsSpare`, `tierLevels`, `hallPeople`) and the order they are tried in all live in
  `data/zones.json` under `village`. `tests/test_village_zoning.gd` covers it;
  `tests/capture_village_zoning.gd` captures it.

## Why a zone waits, and choosing what grows (zoning update)

- **The bar follows the view.** Over the village the zoning bar shows the village: souls, empty
  beds, jobs filled, when the Hall rises next, and four demand columns for what the village wants
  (homes when few beds stand empty, farms when the larder runs low, industry when wood and stone
  run low, civic when morale dips or the village grows). Outside the walls it shows the town as before.
- **Zones say why they wait.** With the tools out, each empty patch of a village zone that cannot
  grow carries a tag: At the limit, Waiting for people, No room, Not yet, Needs unlocking. The bar's
  second line says the same for the zone in hand, and what opens next ("Next: Moonchapel opens with
  the mission \"The Moon Well\""). Tap zoned ground of the zone in hand for its card: every building
  of the zone, whether it can rise, and what holds it back.
- **Choose what grows.** Tap the zone already in hand (or Choose What Grows on a zone's card) and
  pick one of its buildings, or Any. New strokes of that zone grow only that building; picked from a
  patch's card, the whole connected patch is set. The tool shows the pick ("Industry: Moonstone Mine";
  on phones just "Mine"). Picks are kept per cell in the town save (`village_pick`, optional).
- **Big zones raise limits.** Every 6 cells painted with a zone let one more of each of its limited
  buildings stand (at most 6 more); one-of-a-kind buildings stay unique (`village.zoneLimits`).
  `sim.building_limit()` adds these (`sim.zone_extra`, set by the growth layer, not saved).
- **Filling zones open tiers.** A zoned building may move up to a tier once the village level allows
  it, or once enough buildings of its zone stand (3 for tier 2, 6 for tier 3, 10 for tier 4, 15 for
  tier 5; `village.zoneTiers`), whichever comes first. Still one upgrade at a time, still free.
- **Looks.** With the tools away, a zone waiting to grow shows only a thin rim, no wash. With them
  out, each zone edge has a dark line inside its bright rim so it reads on grass and dirt.
- **Phones held upright** keep one row of tools: the four zones, More and Done. More opens a second
  row with Road, Pave, Clear, the brush size and Move.
- Code: `village_growth.gd` (`zone_report`, `village_demand`, `unlock_hint`, `ground_for`,
  `limit_extras`, `tier_open`), `village_zoning.gd` (tags, cards, bar, tool row). Tests:
  `tests/test_zoning_update.gd`; captures: `tests/capture_zoning_update.gd`.

## The frontier is open: buy it or fight for it

- **Past the town's border.** Tap wild ground with a zone tool and its card offers to buy it:
  the land about 14 m around the spot becomes the manor's (50 Gold + 40 Wood, each parcel a
  little dearer). Buyable ground shows a gold grid while the tools are out. A neighbour's land is
  never for sale: its card offers a Raid (break them and they swear to the manor, land and all)
  or Gifts to win them over. Outposts still claim a wider ring from the realm map.
- **The four reaches around the village** are no longer locked behind Act IV. Each can be
  bought outright (300 Wood, 100 Stone, 120 Gold for the first, rising), or its region won on the
  Frontier and then settled for the old price (250 Wood, 100 Stone). Frontier expeditions are
  open from the start. A ready reach's banner shows its price before the tap that claims it.

## How it grows

- Where: cells on the manor's land (its claim around the village, outposts, sworn neighbours),
  not water, bridges, jetties, outpost spots or steep ground. More land means more town, so
  outposts now also make room to build.
- A zoned cell grows a lot only beside a road that leads back to the manor or an outpost, and only
  when the town wants that zone. The four bars on the zoning bar are that demand:
  homes follow jobs, farms and industry follow people, civic follows a growing population.
- Lots go up as scaffolds, then pop into the zone's art. Each zone has three levels; a lot moves up
  when its next level's needs hold for a while (its card lists them with ticks):

| Zone | Level 2 needs | Level 3 needs | Sends the manor |
|---|---|---|---|
| Homes | farms nearby, 20 Food in store, safety | civic and industry nearby, safety, a paved road | Gold (2 / 4 / 7 a minute) |
| Farms | homes nearby | 3 homes and industry nearby | Food (4 / 7 / 11) |
| Industry | homes nearby, 12 townsfolk | 3 homes and farms nearby, 30 townsfolk | Wood, then Stone |
| Civic | 3 homes nearby | 50 townsfolk, farms nearby, a paved road | Gold from level 2 |

  Safety: within 22 m of the village edge, 20 m of an outpost, or near a civic lot.
- Pace: a home with industry right next door levels at half speed; civic within 3 cells and a
  paved road beside a lot each make it 25% faster.
- Cut off: a lot whose road no longer reaches the manor or an outpost sends nothing (its badge and
  card say so, and the zoning bar counts them) until the road is joined up again.
- Titles: Outskirts, Hamlet (10 townsfolk), Village (30), Market Town (60), Town (100) and Borough
  (160). The first time the town reaches one, the folk send a gift (Gold, later Stone too).
- Income arrives every active minute through the village's own storage rules (full stores keep
  nothing extra). Paused or closed time adds nothing; lots never lose levels.

## Changing it

Everything tunable is in `data/zones.json`: per-level art (any `art/catalog.json` asset key, so the
look can change without code), residents, jobs, income, needs, timings, road and paving costs,
pace rules, titles and their gifts, and colours.

## Code and saves

- `scripts/game/town_zoning.gd`: the model (grid, land rules, roads network, demand, needs, growth,
  income, save). No scene dependencies; `tests/test_town_zoning.gd` drives it directly.
- `scripts/game/village_zoning.gd`: the scene layer over the realm layers (tools, colours, roads,
  lots, townsfolk, cards). `scenes/game.tscn` points at it.
- Saves to `user://town-v1.json`, beside the village and realm saves. The village save is untouched.
  Paving and the highest title reached are optional fields, so earlier town saves still load (an
  earlier town takes its current title quietly, without the gifts).
- World text (badges, income, titles) uses only glyphs Godot's built-in font has: the web build has
  no system fonts to fall back on. `tests/test_town_zoning.gd` checks this.
- Trees, rocks and grass outside the village are hidden (not deleted) under roads and lots.

Phone budget: zone colours, the paint grid and all roads are one mesh each, rebuilt only when the
town changes; each lot is a yard mesh, a lantern and its model; at most 6 townsfolk (3 on phones);
at most 24 need badges (12 on phones), refreshed a little under twice a second.
Real phone frame rates have not been measured.

Capture (not a test, never touches a save):
`godot --path . --resolution 1280x800 --script res://tests/capture_zoning.gd -- --no-save --day --capture-dir=<abs dir> [--phone]`

## Next steps

Zone districts with names and policies, neighbours raiding the town, smarter growth (bigger lots
on merged cells), service ranges drawn on the map, and a real-device performance pass.
