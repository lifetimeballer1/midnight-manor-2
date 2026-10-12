# The Realm: open world groundwork

The manor now sits in the middle of a WorldBox-style open realm. The home village, its art,
controls and simulation are unchanged; the realm is a new visual layer (`scripts/game/village_realm.gd`)
over the idle-motion layer, with its world data in `scripts/game/realm_map.gd`.

## What is in this step

- **A 512 m realm (256 x 256 tiles)** of hills, autumn woods, wheat, rocky rises and lakes around
  the 20 x 16 home map. Hills fade out near home so the village diorama and its haunted edge look
  exactly as before; the haunted ground is trimmed to the outskirts and the realm ground starts in
  its colour, so the haunt still recedes as the manor grows.
- **Five rival settlements** (Ashfen Hollow, Briarwatch, Cinderholt, Gallowmere, Thornvale), built
  from the delivered building models, each with a tall banner in its colour and a name/population
  label. The nearest is about 100 m from the manor, so it shows at the edge of a zoomed-out view.
- **People in the distance**: villagers (the delivered character models and walk/idle clips) stroll
  between the buildings of the settlements near the camera.
- **Territory**: each settlement and the manor claim land. Claims show as a light wash in the
  owner's colour with a brighter border line. The strongest claim (radius minus distance) wins
  contested ground, so borders move as neighbours grow. The manor's claim widens with every
  expansion plot.
- **Growth**: each neighbour gains a settler every 75 active seconds (cap 40). More people means a
  higher building tier, more cottages and a wider claim. Paused or closed time adds nothing.
- **Camera**: pan reaches the whole realm and zoom goes out to 130 (was 90). Default view, recentre
  and all gestures are unchanged.
- **Save**: realm growth saves to `user://realm-v1.json`, beside (never inside) `village-v1.json`.

## Realm life (neighbours, outposts, raids)

`scripts/game/village_realm_life.gd` sits over the realm layer (the scene points at it).

- **Moods**: every neighbour is friendly, wary or hostile (or sworn once beaten), shown on its
  banner. Borders that touch the manor's land sour it by about 3 points a minute. Apart, it eases
  back. Gifts (40 Gold) warm it by 20.
- **Neighbours that act**: friendly neighbours send a trader every 90 active seconds who walks to
  the manor's edge and leaves 10 Gold (banked within storage). Hostile ones send scouts every 70 s,
  grow 1.5x faster and overrun any outpost their land swallows.
- **Tap the realm**: tapping a settlement or its land opens its card (people, mood, land, defence,
  Send Gifts, Raid). Tapping wild land offers an outpost. Taps on the village and its locked plots
  behave as before.
- **Outposts (land takeover)**: 120 Wood + 60 Gold, up to six, each within 36 m of land the manor
  already holds. Each claims 26 m for the manor, so borders move out step by step and weaker
  neighbour claims change hands.
- **Raids (fighting neighbours)**: 20 Food + 10 Gold of supplies and at least two fighters. The
  village's own fighters' combined levels set the warband's strength; they never leave the village's
  defence. A column of up to four marches from the village edge, and the fight resolves on
  arrival. A win brings Gold and Food (banked within storage) and costs the neighbour a quarter of
  its people. A neighbour beaten down to five people swears to the manor: its land becomes yours
  and it flies your colour. Each raid leaves the target on guard for two minutes.
- **Save**: realm save v2 adds moods, outposts, sworn neighbours and a marching warband. v1 realm
  saves still load. The village save is unchanged.

## Mobile sizing

The limit on phones is draw calls and per-frame script work, not map area. The realm is built so
cost follows what the camera sees, not the size of the world:

| Piece | Cost |
|---|---|
| Ground | one mesh, 4 m cells (8 m on phones): ~33k triangles desktop, ~8k phone, one draw call |
| Water | one flat quad |
| Trees | one MultiMesh per 64 m chunk and shape, streamed around the camera; at most 36 chunks (16 on phones), 3 built per 0.25 s so panning never hitches |
| Settlements | only the 3 (2 on phones) nearest the camera get models and walkers; others are a banner pole + their territory tint |
| Walkers | 6 per loaded settlement (3 on phones) |
| Rival growth | a few numbers per settlement per frame |

Recommendation: keep the realm at 256 x 256 tiles until it has been played on real phones. With the
same streaming it could go to 384 x 384 tiles (768 m), but bigger maps mostly add empty travel, and
real Safari/Android frame rates have not been measured yet. Desktop captures do not establish phone
performance.

## Next steps

1. Neighbours raiding back: hostile neighbours' attacks arriving as home raid waves.
2. Fought raids: play a raid out on the Frontier battle map instead of resolving it on arrival.
3. Neighbours fighting each other and trading land between themselves.
4. Real-device performance pass on iPhone Safari and Android Chrome.

Launch flags: `--no-realm` leaves the realm out; `--realm-view=x,z,zoom` frames a capture.
Tests: `godot --headless --path . --script res://tests/test_realm.gd -- --no-save`.
