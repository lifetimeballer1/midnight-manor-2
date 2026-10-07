# Midnight Manor 2

- Prefer free Muse Spark via OpenCode Zen for bounded helper drafts, using abstract/redacted briefs only. If its connection refuses a call, do not loop retries or automatically fall back to paid models. Never claim a model was used without a successful invocation. Keep prompts, reads and reports compact; load applicable Godot skills on demand.
- Token budget: keep changes within the requested scope, reuse gathered context, avoid broad/repeated reads and large output dumps, and send only brief meaningful updates. Do not duplicate delegated investigations.
- Read README.md and docs/LIVING_VILLAGE_DELIVERY.md before continuing. Living Village is implemented; the separate asset viewer is retained.
- Preserve Manor 1's gameplay feel when implementing the core-loop port. Use Godot/GDScript, full 3D and a 20x16 starting map.
- Never overwrite or save the user's original Game Assets.blend. Export isolated copies in a separate background Blender process.
- Use art/catalog.json as the authoritative delivered-asset list. Do not silently export reference layouts, LOD duplicates or catalogue-wide rigs.
- Verify with scripts/verify_assets.py, the Python tests and Godot scripts/ArtCheck.gd. Do not claim desktop checks establish web/mobile performance.
- Run targeted tests during iteration. At completion, run the six original GDScript suites (including test_chronicle), the four overhaul suites (test_overhaul_foundation, test_village_needs, test_frontier_battles, test_campaign_actions), and applicable additional regressions once; repeat only when later changes require it. Use the console Godot executable for errors and PASS markers. Preserve the village-v1.json path and v1/v2/v3 saves when writing payload v4. Fixtures do not establish campaign reachability or real phone/browser performance.
- Keep the web export Safari-playable: variant/thread_support=false in export_presets.cfg (threaded builds need COOP/COEP headers GitHub Pages cannot send). CI guards this; never re-enable threads without a host that sends those headers.
- Do not commit, push or deploy without the user's request.
- Manor Studio is the project-local editor extension in addons/manor_studio. Preserve staged/explicit Apply, backup and external-conflict protection. Its tests use scratch files only; never tune data/buildings.json or player saves as a test side effect. Include test_combat_vfx, test_raid_navigation_cache, test_manor_studio and test_home_raid_scoring in applicable final verification.
- Coordinate balance writes: use the Studio model where practical and never manually edit data/buildings.json while a Studio Apply is active. Its lock serializes cooperating writers, not arbitrary external editors.
