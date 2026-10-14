# The Town Outside the Walls (zoning, first version)

City-builder zoning on the manor's own land in the realm: you lay roads and paint zones, and the
town builds itself. The village and its four reaches keep hand-placed building exactly as before.

## Playing it

- **Town** (bottom bar) opens the zoning tools; **Done** or Esc closes them.
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
