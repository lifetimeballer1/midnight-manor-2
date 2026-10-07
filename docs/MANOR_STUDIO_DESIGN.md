# Manor Studio: First Editor Tool

## Scope

A project-local Godot editor extension, not an engine fork. The first dock
edits existing building balance fields in `data/buildings.json`. Runtime
simulation, player saves, asset sources and export settings remain unchanged.

## Workflow

- Select a building and tier using readable names.
- Edit existing resource costs, construction time, production rate/reserve,
  and tier HP, damage, range and rate multiplier.
- Stage edits in memory; explicitly Apply or Discard them.
- Validate finite nonnegative numbers and positive HP before saving.
- Preserve all unedited fields, including unlocks and advanced tuning.
- Refuse Apply if the file changed externally; never silently overwrite it.
- Serialize Studio writers with a shared write lock and recheck source content
  before replacement. This is optimistic protection for noncooperating external
  editors, not an atomic filesystem compare-and-replace; do not edit externally
  during Apply.
- Back up the previous content and replace the file through a temporary file.
- Provide an Open Game shortcut; do not launch or load player saves automatically.

## Structure

`addons/manor_studio/` contains the editor plugin, dock and a small data model.
The model handles staging, validation, conflict detection and persistence.
The dock presents the model; only the plugin uses editor-specific APIs.
Disable the extension to return to the standard editor.

## Verification

Headless tests cover real building data, staged edits/discard, invalid values,
metadata preservation, backup/round-trip save, external conflicts and dock
selection. Persistence tests use isolated fixture files, never gameplay data
or `village-v1.json`. Check plugin loading in the editor and run the applicable
game regressions once after implementation.

## Deferred

Troop/quest editors, live simulation mutation, level painting, embedded asset
previews, engine changes and automated full-suite buttons are not in this pass.
