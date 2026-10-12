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

1. **Neighbour AI and contact**: neighbours send scouts/traders along roads; relations
   (friendly, wary, hostile) shown on their banners.
2. **Land takeover**: claim wild land with outposts, and contested border cells flip over time to
   the stronger claim.
3. **Fighting neighbours**: reuse the Frontier battle map to raid or defend against a neighbour;
   a win shrinks their claim and can make the settlement a vassal.
4. **Tap a settlement** for its info card (name, people, attitude, actions).
5. Real-device performance pass on iPhone Safari and Android Chrome.

Launch flags: `--no-realm` leaves the realm out; `--realm-view=x,z,zoom` frames a capture.
Tests: `godot --headless --path . --script res://tests/test_realm.gd -- --no-save`.
