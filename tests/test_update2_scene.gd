extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var scene: PackedScene = load("res://scenes/game.tscn")
	var game = scene.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	check(game.resource_rows.size() == 5 and game.resource_rows.has("stone"), "top-right resources include Stone")
	check(game.resource_bars.size() == 5, "all resources have real capacity bars")
	check(game.left_dock.position.x < game.resource_stack.position.x, "village HUD and resources occupy separate corners")
	check(not game.left_dock.get_rect().intersects(game.resource_stack.get_rect()), "desktop HUD corners do not overlap")
	check(not game.research_list.visible, "research stays compact until expanded")
	game._toggle_research()
	check(game.research_list.visible, "research panel expands on request")
	game._toggle_research()
	check(game.research_buttons.size() == 36, "the unified tech tree exposes all36 nodes")
	check(game.research_buttons["stoneworking"].disabled, "level1 research gate is visible")
	check(not game.research_buttons["wayfinding"].disabled or not game.research_buttons["wayfinding"].tooltip_text.is_empty(), "every branch has an entry with a stated reason")
	game.sim.xp = 100
	game.sim.living.insight = 20
	game._refresh_hud()
	check(not game.research_buttons["stoneworking"].disabled, "research button responds to live requirements")
	game._begin_research("stoneworking")
	check(game.sim.living.active == "stoneworking", "research UI starts real paid project")
	game._open_panel("build")
	check(game.build_category_order == ["Economy", "Homes", "Defense", "Roads"], "four build categories are present")
	check(game.build_cards.size() == 17, "all current building types have cards")
	for type_name in game.build_cards:
		check(game.build_cards[type_name].icon != null, "thumbnail queued/cached for " + str(type_name))
		check(game._asset_exists(game.thumbnail_asset(type_name)), "thumbnail comes from an existing GLB")
	check(game.model_asset("stone_quarry", 1) == "mine_t1", "quarry safely adapts existing art instead of missing GLB")
	game.selected_building = int(game.sim.buildings[0]["id"])
	game._open_panel("building")
	check(not game.sidebar.visible and game.bottom.visible, "selected building actions stay in compact bottom bar")
	game._choose_build("farm")
	game.preview_tile = Vector2i(1, 1)
	game._preview()
	game._cancel_placement()
	await process_frame
	check(is_instance_valid(game.ghost_layer), "cancel never deletes reusable preview layer")
	game._choose_build("farm")
	game.preview_tile = Vector2i(1, 1)
	game._preview()
	check(game.ghost_layer.get_child_count() > 0, "preview still works after cancelling")
	game._cancel_placement()
	game.sim.living.discoveries.assign(["stoneworking", "road_masonry"])
	game.sim.living.active = ""
	game.sim.living.remaining = 0
	game.sim.resources["stone"] = 16
	game.sim.living.cells.clear()
	game.sim.living.cells["2,2"] = {"wear": 1.0, "last": game.sim.elapsed, "stone": false}
	game.sim.living.revision += 1
	game._update_roads()
	check(game.road_dirt.mesh != null and game.road_cells == 1, "wear drives a cached dirt mesh")
	game._toggle_pave()
	game.preview_tile = Vector2i(2, 2)
	game._preview()
	check(not game.confirm_button.disabled and game.sim.resources["stone"] == 16, "paving preview is valid without spending")
	game._confirm_placement()
	check(game.sim.resources["stone"] == 8 and game.sim.living.cells["2,2"]["stone"], "confirm invokes actual paving cost/state")
	check(game.road_stone.mesh != null, "confirmed paving updates stone mesh")
	game._cancel_placement()
	var cottage: Dictionary = game.sim._new_building("cottage", 1, 5, true)
	game.sim.buildings.append(cottage)
	var gate: Dictionary = game.sim._new_building("gate", 5, 11, false)
	game.sim.buildings.append(gate)
	game.sim.revision += 1
	game._rebuild_buildings()
	game._update_actors(0.1)
	game.details.update(game, 0.1)
	var view: Dictionary = game.building_views[int(cottage["id"])]
	check(view["scaffold"].visible, "construction shows scaffolding")
	check(view["model"].scale.x == view["model"].scale.y, "building is not squashed during construction")
	check(view["progress"].scale.x <= 0.1, "construction progress reflects remaining time")
	cottage["remaining"] = 0
	game.details.update(game, 0.1)
	check(not view["scaffold"].visible, "finished scaffolding disappears")
	var gate_view: Dictionary = game.building_views[int(gate["id"])]
	check(gate_view.has("gate_mesh"), "gate lift remains independently animatable")
	check(gate_view["joins"].get_child_count() > 0, "gate connects to neighboring wall")
	game.sim.enemies.append({"id": game.sim._id(), "type": "raider", "x": 5.5, "y": 12.0, "hp": 80.0, "max_hp": 80.0, "phase": "idle", "cooldown": 0.0})
	game.sim.raid_active = true
	game.sim._gate_tick()
	check(not gate["gate_open"] and game.sim._blocked(Vector2i(5, 11), false), "enemy pressure closes visible and logical gate")
	game.sim.enemies.clear()
	game.sim._gate_tick()
	check(gate["gate_open"] and not game.sim._blocked(Vector2i(5, 11), false), "gate reopens after danger passes")
	game.sim.raid_active = false
	game.sim.start_raid()
	game.details.update(game, 0.1)
	check(game.details.warnings[0].visible, "first incoming wave warning matches west perimeter")
	check(not game.details.warnings[1].visible, "no false east warning for first wave")
	check(game.details.smoke_count <= 6, "smoke sources stay bounded")
	var state: Dictionary = JSON.parse_string(JSON.stringify(game.sim.export_state()))
	check(game.sim.restore_state(state), "UI-created living state remains saveable")
	root.size = Vector2i(480, 900)
	await process_frame
	game._layout_ui()
	check(not game.left_dock.get_rect().intersects(game.resource_stack.get_rect()), "portrait HUD corners do not overlap")
	root.size = Vector2i(360, 800)
	await process_frame
	game._layout_ui()
	check(not game.left_dock.get_rect().intersects(game.resource_stack.get_rect()), "narrow-phone HUD corners do not overlap")
	var file := FileAccess.open("res://docs/update2_scene_verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}, "\t"))
	file.close()
	game.free()
	await process_frame
	print("UPDATE2_SCENE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
