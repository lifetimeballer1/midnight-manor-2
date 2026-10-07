# Manor Studio Implementation Plan

**Goal:** Add the approved building-balance dock without modifying the engine.
**Architecture:** EditorPlugin hosts a Control dock; an independently testable
data model stages and safely persists JSON edits.
**Tech Stack:** Godot 4.7.2, GDScript, existing building JSON.
**Spec:** `docs/MANOR_STUDIO_DESIGN.md`.

## Constraints

- Preserve player saves, unrelated data fields, existing plugins and exports.
- Work on the existing feature branch; do not commit, push or deploy.
- Test persistence only against isolated scratch files.

## Tasks

- [x] Add `tests/test_manor_studio.gd`; first verify the missing tool fails.
- [x] Create `addons/manor_studio/balance_model.gd`: `load_file`,
  `editable_fields`, `set_numeric`, `is_dirty`, `discard`, `save`.
  Reject nonfinite/negative values and nonpositive HP; compare file content
  with the loaded baseline before saving; preserve the original in
  `<file>.manor-studio.previous` and replace via `<file>.manor-studio.tmp`.
- [x] Create `dock.gd`: building/tier selectors, scrollable numeric fields,
  Apply and Discard/Reload, status text, Open Game signal. Test real controls.
- [x] Create `plugin.cfg` and `plugin.gd`; host the dock using editor APIs,
  wire Open Game to the main scene, and enable the plugin in `project.godot`.
- [x] Run the focused model/dock tests and verify editor registration.
- [x] Run all applicable game suites once, Python tests and asset checks.
- [x] Document how to use/disable the tool and record actual results.

Results: thirteen headless suites, 971 checks, zero failures; four Python tests
and both 310-asset checks passed. Studio has 63 headless checks and 64 native
capture checks. Precision and invalid-control regressions were red before the
fixes. Concurrent Studio writers are locked; arbitrary external-editor races
remain an explicitly documented filesystem/API limitation.
