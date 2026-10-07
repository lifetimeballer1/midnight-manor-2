# Manor Studio

Project-local building-balance tools for Godot 4.7.2. No custom engine build,
runtime autoload or external dependency is required.

## Use

1. Reopen the project if the running editor has not picked up the new plugin.
   Alternatively enable **Manor Studio** in **Project Settings > Plugins**.
2. Open the **Manor Studio** dock in the right-hand editor column.
3. Choose a building and tier. Change numeric fields using the form.
4. **Apply Balance Changes** validates and saves the draft.
   **Discard / Reload** reads saved values and discards the draft on success.
5. **Open Game Scene** opens `scenes/game.tscn` without starting a game.

Costs, build time, production rate and reserve are building-level values.
Base costs affect all tiers; authored upgrade curves and tier-specific costs
still apply. HP, damage, range and production multiplier belong to the
selected tier. Existing saved building HP is retained; new tier HP applies
when buildings are created/upgraded. Some runtime values are derived from
research or `data/living_village.json`; this dock does not edit those overrides.

Changes affect the next game run, not a simulation already running. Player
saves are never read or written by the tool. Changes can still affect game
balance; the dock validates numeric safety, not campaign difficulty.

## Safety

- Edits stay in memory until Apply. Disabling/reloading the plugin can discard
  unsubmitted drafts; Apply or Discard before doing so.
- The last pre-Apply content is retained in
  `data/buildings.json.manor-studio.previous`.
- Apply refuses conflicting external edits or an existing staging file.
  Source data and the working draft are retained when saving fails.
- Studio writers share a `.manor-studio.lock` directory. External editors do
  not honor this lock: do not write the JSON elsewhere during Apply. Content
  is rechecked just before replacement, but Godot's file API does not provide
  an atomic compare-and-replace against arbitrary external writers.
- Numeric serialization and display retain full floating-point precision.
- Only existing approved numeric fields are editable. Structural metadata,
  unlocks, art references and unrelated properties are preserved.
- Disable Manor Studio in **Project Settings > Plugins** to remove the dock.

## Verification

`tests/test_manor_studio.gd` exercises the real model and form against isolated
scratch files. Run with the project's console Godot executable:

```powershell
godot --headless --path . --script res://tests/test_manor_studio.gd -- --no-save
```

The model exposes `load_file`, `editable_fields`, `set_numeric`, `is_dirty`,
`discard` and `save` for repeatable scripted editing. No gameplay state or
engine source modifications are involved.

Verified: 63 headless checks, 64 in the native capture run, and real editor
registration of all 63 authored buildings. The capture in
`docs/previews/manor-studio-dock.png` is a standalone dock fixture, not a
screenshot of the user's editor session. Editor shutdown still reports
ObjectDB/resource diagnostics; these are not claimed resolved by this tool.
The final editor check also logged socket-probe errors in the existing Funplay
MCP plugin. Studio registration succeeded, but MCP connectivity is not certified.
