# Cozy Gothic Overhaul

Approved direction: complete and polish Midnight Manor II in one major release.
Phone browser first, Cozy Gothic village against haunted wilderness, selective
asset replacements, refined existing walnut/iron/brass/parchment UI, improved
orbitable camera, optional mentor, food/housing/morale consequences, readable
automatic defense, all ten campaign acts, playable frontier battle maps,
placement/tier polish, and permanent endless progression.

## Delivery Order

1. Establish a save-isolated baseline and regression coverage.
2. Repair progression, research affordability/effects, migration, rewards,
   inspector/pause behavior, live objectives, and save feedback.
3. Improve phone lifecycle, contextual controls, optional mentoring and camera.
4. Add active-time food, housing and morale with recoverable shortages.
5. Add a reusable frontier battle scene with seven region configurations;
   pause the home village during expeditions and settle each result once.
6. Wire real delivery, prestige, expedition, contract and constructed Great Work
   objectives; prove campaign reachability and continue into endless play.
7. Finish construction/art polish and verify native/browser/device behavior.

Each subsystem requires behavior tests before implementation and review before
integration. These are internal checkpoints, not separate public releases.

## Constraints

- Preserve existing uncommitted work, the village-v1.json save path and v1/v2/v3
  saves. Validate before replacing state; never erase a corrupt original.
- No offline starvation or secret penalties while the browser is closed.
- Keep Web variant/thread_support=false for Safari compatibility.
- Reuse existing models first; never overwrite original Blender sources.
- No paid generation, commits, pushes or deployment without permission.
- Use applicable Godot skills/tools at each checkpoint, not unrelated APIs.
- Keep agent prompts/reads bounded; use free Muse only when its connection works,
  without paid fallback. Its current connection rejects calls as outside OpenCode.

## Baseline (2026-10-07)

Fresh console runs: village 94, game scene 20, workers/defense 190, living village
45, update2 scene 73, Chronicle 221; all pass (643 checks). Four Python tests and
both asset verifiers pass for 310 assets (273 buildings, 37 characters).
Scene suites report shutdown resource leaks despite passing assertions.
These checks do not establish campaign reachability or mobile performance.

## Verification Gates

- Research can be funded through normal accumulation; effects stay in their
  intended category; rewards settle once; advanced resources survive JSON saves.
- Inspector, pause transitions and live panels work without reopening panels.
- Save fixtures never access a real player's save; new-game reset is confirmed.
- Needs and battle state round-trip and cannot accrue offline penalties or
  duplicate rewards. Losing remains recoverable.
- All six existing GDScript suites, new regressions, Python asset tests and
  ArtCheck pass; campaign completion uses real commands without injected tallies.
- Capture native desktop and phone-size layouts. Separately test real Safari
  and an agreed reference phone; target stable 30 FPS, not an assumed guarantee.

## Implementation Status

- Baseline complete.
- Foundation repairs, phone-first lifecycle/mentor and needs implemented and tested.
- A separate playable frontier prototype supports seven region configurations,
  crew selection, automatic combat, rallying, pause, retreat, save/resume and
  one-time results. Home simulation and input are isolated while away.
- Campaign delivery/prestige/physical Great Work actions and specialist recruitment
  are connected. Act VIII prerequisite deadlocks, contract baselines/repeats,
  enemy role movement/range and refinery mission accounting are repaired.
- Endless state and repeat patrol hooks are implemented, not campaign-playthrough
  certified. Great Works without dedicated exports use disclosed proxy models.
- Native phone/desktop screenshots and a standalone QA data pack are verified.
- Still pending: unmodified-resource ten-act completion/balance, richer regional
  battle art, additional wall-row/tier polish, leak cleanup, full browser export
  and real Safari/phone performance. Local 4.7.2 export templates are absent.
- No paid generation, commits, pushes or deployment performed.

See OVERHAUL_DELIVERY.md for precise verification scope and remaining gates.
