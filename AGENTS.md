# Midnight Manor 2

- Prefer free Space Bunny via OpenCode for helper drafts, per the latest user request. GPT-6 Luna is the user's other delegation preference when appropriate. Do not automatically fall back to paid models or claim a model was used without an actual invocation.
- Read README.md and docs/LIVING_VILLAGE_DELIVERY.md before continuing. Living Village is implemented; the separate asset viewer is retained.
- Preserve Manor 1's gameplay feel when implementing the core-loop port. Use Godot/GDScript, full 3D and a 20x16 starting map.
- Never overwrite or save the user's original Game Assets.blend. Export isolated copies in a separate background Blender process.
- Use art/catalog.json as the authoritative delivered-asset list. Do not silently export reference layouts, LOD duplicates or catalogue-wide rigs.
- Verify with scripts/verify_assets.py, the Python tests and Godot scripts/ArtCheck.gd. Do not claim desktop checks establish web/mobile performance.
- Also run the five GDScript gameplay suites: test_village, test_game_scene, test_workers_defense, test_living_village and test_update2_scene. Use the console Godot executable to reliably capture errors and PASS markers. Keep save-v1 path compatibility while migrating the payload to version2.
- Keep the web export Safari-playable: variant/thread_support=false in export_presets.cfg (threaded builds need COOP/COEP headers GitHub Pages cannot send). CI guards this; never re-enable threads without a host that sends those headers.
- Do not commit, push or deploy without the user's request.
