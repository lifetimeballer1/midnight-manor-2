extends SceneTree

# Startup loading screen: real progress that only moves forward, named stages,
# and a clean hand-over to the village scene. Run with -- --no-save.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	root.size = Vector2i(390, 844)
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/loading.tscn", "loading screen is the main scene")
	check(ResourceLoader.exists(ProjectSettings.get_setting("application/boot_splash/image")), "boot splash image exists")
	var loader: Node = load("res://scenes/loading.tscn").instantiate()
	root.add_child(loader)
	current_scene = loader
	await process_frame
	var labels: Array = loader._items.map(func(item: Dictionary) -> String: return item["label"])
	for stage in ["Waking the manor", "Rendering terrain", "Rendering buildings: Manor Hall", "Rendering characters: Archer", "Raising the village"]:
		check(labels.has(stage), "planned stage: %s" % stage)
	check(labels[-1] == "Raising the village", "village is raised last")
	var last: float = 0.0
	var backwards: bool = false
	var seen: Dictionary = {}
	var frames: int = 0
	while is_instance_valid(loader) and frames < 3000:
		var bar_value: float = loader._bar.value
		backwards = backwards or bar_value < last - 0.0001
		last = bar_value
		seen[loader._status.text.get_slice(":", 0).trim_suffix("...")] = true
		await process_frame
		frames += 1
	check(not backwards, "progress never moves backwards")
	check(seen.has("Rendering buildings") and seen.has("Rendering characters"), "status line names what is loading")
	check(not is_instance_valid(loader), "loader frees itself after hand-over")
	var game: Node = current_scene
	check(game != null and game.name == "MidnightManor2", "village becomes the current scene")
	check(game != null and game.get("no_save") == true, "village honours --no-save through the loader")
	check(game != null and game.building_views.size() > 0, "village built its buildings")
	await create_timer(1.5).timeout
	var overlay_left: bool = false
	for child in root.get_children():
		overlay_left = overlay_left or (child is CanvasLayer and child.layer == 120)
	check(not overlay_left, "loading overlay fades out and frees")
	if failures.is_empty():
		print("PASS checks=%d failures=0" % checks)
		quit(0)
	else:
		quit(1)
