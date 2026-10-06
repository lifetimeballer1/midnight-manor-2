extends SceneTree

const Viewer = preload("res://scripts/test_import.gd")
const BASE_TOLERANCE_M: float = 0.02
const MOTION_EPSILON: float = 0.00001

var failures: Array[String] = []
var records: Array[Dictionary] = []
var stage := Node3D.new()
var actual_triangles: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String, local_errors: Array[String]) -> void:
	local_errors.append(message)
	failures.append(message)
	printerr("FAIL ", message)


func _nodes(node: Node, result: Array[Node]) -> void:
	result.append(node)
	for child in node.get_children():
		_nodes(child, result)


func _run() -> void:
	root.add_child(stage)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/catalog.json"))
	var assets: Array = []
	var general_errors: Array[String] = []
	if parsed is Dictionary and parsed.get("assets") is Array:
		assets = parsed["assets"]
	else:
		_fail("Invalid catalog schema", general_errors)
	var building_count: int = 0
	var character_count: int = 0
	var types: Dictionary = {}
	var seen: Dictionary = {}
	for entry: Dictionary in assets:
		var asset: String = str(entry.get("asset", ""))
		var errors: Array[String] = []
		if seen.has(asset):
			_fail(asset + ": duplicate catalog entry", errors)
		seen[asset] = true
		if entry.get("kind") == "building":
			building_count += 1
			types[asset.rsplit("_t", true, 1)[0]] = true
		elif entry.get("kind") == "character":
			character_count += 1
		else:
			_fail(asset + ": unknown kind", errors)
		var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/%s/manifest.json" % asset))
		var manifest: Dictionary = manifest_value if manifest_value is Dictionary else {}
		for key in ["asset", "file", "kind", "triangles", "meshes", "materials", "images", "clips", "dimensions_m"]:
			if manifest.get(key) != entry.get(key):
				_fail(asset + ": manifest/catalog mismatch: " + key, errors)
		for key in ["pivot", "units", "up_axis"]:
			var expected: String = {"pivot": "base_center", "units": "metres", "up_axis": "+Y"}[key]
			if entry.get(key) != expected:
				_fail(asset + ": unexpected " + key, errors)
		var path: String = "res://art/%s/%s" % [asset, entry.get("file", "")]
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail(asset + ": PackedScene load failed", errors)
			records.append({"asset": asset, "errors": errors})
			continue
		var instance: Node = packed.instantiate()
		stage.add_child(instance)
		await process_frame
		var record: Dictionary = await _check_asset(instance, entry, errors)
		records.append(record)
		actual_triangles[asset] = record["triangles"]
		print("ASSET ", asset, " triangles=", record["triangles"], " height_m=", record["size_m"][1], " errors=", errors.size())
		instance.free()
	if assets.size() != 133 or building_count != 125 or character_count != 8 or types.size() != 23:
		_fail("Counts: expected 133 assets / 125 buildings / 8 characters / 23 types; got %d / %d / %d / %d" % [assets.size(), building_count, character_count, types.size()], general_errors)
	var layout: Dictionary = _check_layout()
	var supports: Array[Dictionary] = await _check_support()
	var viewer_checks: Dictionary = await _check_viewer()
	var report: Dictionary = {
		"passed": failures.is_empty(), "godot_version": Engine.get_version_info()["string"],
		"scope": "Asset import QA only; PC checks do not establish mobile/web performance.",
		"counts": {"assets": assets.size(), "buildings": building_count, "characters": character_count, "building_types": types.size()},
		"base_tolerance_m": BASE_TOLERANCE_M, "motion_epsilon": MOTION_EPSILON,
		"bounds_method": "Static transformed mesh AABBs; character CPU-skinned vertices at imported rest pose, including tools. Heights informational.",
		"animation_method": "Resolve every keyed track/bone; seek five clip fractions; compare bone poses and CPU-skinned vertex positions.",
		"sample_display": layout, "support_samples": supports, "viewer_checks": viewer_checks, "assets": records, "failures": failures,
	}
	var output := FileAccess.open("res://docs/godot_verification.json", FileAccess.WRITE)
	if output == null:
		printerr("Cannot write docs/godot_verification.json: ", FileAccess.get_open_error())
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("ARTCHECK ", "PASS" if failures.is_empty() else "FAIL", " assets=", records.size(), " failures=", failures.size(), " T01_triangles=", layout["building_triangles"])
	stage.free()
	quit(0 if failures.is_empty() else 1)


func _check_asset(instance: Node, entry: Dictionary, errors: Array[String]) -> Dictionary:
	var asset: String = entry["asset"]
	var nodes: Array[Node] = []
	_nodes(instance, nodes)
	var bounds := AABB()
	var has_bounds: bool = false
	var meshes: int = 0
	var skinned: int = 0
	var skeletons: Array[Skeleton3D] = []
	var skin_meshes: Array[MeshInstance3D] = []
	var players: Array[AnimationPlayer] = []
	var materials: Dictionary = {}
	var textures: Dictionary = {}
	for node in nodes:
		if node is Skeleton3D:
			skeletons.append(node)
		if node is AnimationPlayer:
			players.append(node)
		if not node is MeshInstance3D:
			continue
		var mesh_node: MeshInstance3D = node
		if mesh_node.mesh == null:
			_fail(asset + ": empty mesh " + str(node.name), errors)
			continue
		meshes += 1
		var aabb: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
		if mesh_node.skin != null:
			_check_skin(asset, mesh_node, errors)
			var points: PackedVector3Array = _skin_vertices(mesh_node)
			if not points.is_empty():
				aabb = AABB(points[0], Vector3.ZERO)
				for point in points:
					aabb = aabb.expand(point)
		bounds = bounds.merge(aabb) if has_bounds else aabb
		has_bounds = true
		for surface in mesh_node.mesh.get_surface_count():
			var material: Material = mesh_node.get_active_material(surface)
			if material == null:
				_fail(asset + ": missing surface material " + str(node.name), errors)
				continue
			materials[material.get_instance_id()] = true
			if material is BaseMaterial3D and material.albedo_texture != null:
				textures[material.albedo_texture.get_instance_id()] = true
		if mesh_node.skin != null:
			skinned += 1
			skin_meshes.append(mesh_node)
	var triangles: int = Viewer.mesh_triangles(instance)
	if not has_bounds or triangles == 0:
		_fail(asset + ": no triangle geometry", errors)
	if triangles != int(entry["triangles"]) or meshes != int(entry["meshes"]):
		_fail(asset + ": geometry counts disagree with manifest (%d triangles, %d meshes)" % [triangles, meshes], errors)
	if materials.size() != int(entry["materials"]) or textures.size() != int(entry["images"]):
		_fail(asset + ": material/image counts disagree with manifest (%d materials, %d textures)" % [materials.size(), textures.size()], errors)
	if textures.is_empty():
		_fail(asset + ": no embedded albedo palette on asset", errors)
	if bounds.size.x > 8.0 or bounds.size.y > 8.0 or bounds.size.z > 8.0:
		_fail(asset + ": bounds exceed 8 metres: " + str(bounds.size), errors)
	var clips: Array[Dictionary] = []
	if entry["kind"] == "building":
		if absf(bounds.position.y) > BASE_TOLERANCE_M:
			_fail(asset + ": building base y=" + str(bounds.position.y), errors)
		if absf(bounds.get_center().x) > BASE_TOLERANCE_M or absf(bounds.get_center().z) > BASE_TOLERANCE_M:
			_fail(asset + ": building not base-centred in X/Z", errors)
		for player in players:
			for clip in player.get_animation_list():
				if clip != "RESET":
					_fail(asset + ": static building has unexpected clip " + clip, errors)
		if asset.begins_with("gate_"):
			var lift_found: bool = false
			for node in nodes:
				if "lift" in str(node.name).to_lower() and node is MeshInstance3D:
					lift_found = true
			if not lift_found:
				_fail(asset + ": no separate Lift Gate mesh", errors)
	else:
		if skeletons.is_empty() or skinned == 0:
			_fail(asset + ": missing Skeleton3D or skinned mesh", errors)
		for node in nodes:
			if "lod1" in str(node.name).to_lower() and "body" in str(node.name).to_lower():
				_fail(asset + ": unexpected LOD1 body", errors)
		var expected: Array[String] = ["idle", "walk", "work", "death", "attack" if asset in ["char_warrior", "char_archer"] else "gather"]
		var declared: Array = entry["clips"].duplicate()
		declared.sort()
		var sorted_expected: Array[String] = expected.duplicate()
		sorted_expected.sort()
		if declared != sorted_expected:
			_fail(asset + ": manifest has incorrect five clips", errors)
		var player: AnimationPlayer = players[0] if not players.is_empty() else null
		if player == null:
			_fail(asset + ": no AnimationPlayer", errors)
		else:
			var actual: Array[String] = []
			for name in player.get_animation_list():
				if name != "RESET":
					actual.append(name)
			actual.sort()
			if actual != sorted_expected:
				_fail(asset + ": incorrect imported clip set: " + str(actual), errors)
			for clip in expected:
				if not player.has_animation(clip):
					_fail(asset + ": missing clip " + clip, errors)
					continue
				clips.append(await _check_clip(asset, player, skeletons, skin_meshes, clip, errors))
	return {"asset": asset, "kind": entry["kind"], "triangles": triangles, "meshes": meshes,
		"materials": materials.size(), "textures": textures.size(), "skinned_meshes": skinned,
		"skeletons": skeletons.size(), "min_m": _vector(bounds.position), "size_m": _vector(bounds.size),
		"height_m": bounds.size.y, "manifest_height_m": entry["dimensions_m"][1], "clips": clips, "errors": errors}


func _check_skin(asset: String, node: MeshInstance3D, errors: Array[String]) -> void:
	var skeleton: Skeleton3D = node.get_node_or_null(node.skeleton) as Skeleton3D
	if skeleton == null or node.skin.get_bind_count() == 0:
		_fail(asset + ": unresolved skeleton or empty skin on " + str(node.name), errors)
		return
	for bind in node.skin.get_bind_count():
		var bone_name: StringName = node.skin.get_bind_name(bind)
		var bone: int = skeleton.find_bone(bone_name) if not bone_name.is_empty() else node.skin.get_bind_bone(bind)
		if bone < 0 or bone >= skeleton.get_bone_count():
			_fail(asset + ": invalid skin bind on " + str(node.name), errors)
	for surface in node.mesh.get_surface_count():
		var arrays: Array = node.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if bones.is_empty() or bones.size() != weights.size() or bones.size() not in [vertices.size() * 4, vertices.size() * 8]:
			_fail(asset + ": malformed skin arrays on " + str(node.name), errors)
			continue
		var stride: int = bones.size() / vertices.size()
		for vertex in vertices.size():
			var total_weight: float = 0
			for influence in stride:
				var index: int = vertex * stride + influence
				total_weight += weights[index]
				if weights[index] > 0 and (bones[index] < 0 or bones[index] >= node.skin.get_bind_count()):
					_fail(asset + ": out-of-range weighted skin index on " + str(node.name), errors)
					return
			if absf(total_weight - 1.0) > 0.02:
				_fail(asset + ": non-normalized vertex weights on " + str(node.name), errors)
				return


func _skin_vertices(node: MeshInstance3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	var skeleton: Skeleton3D = node.get_node_or_null(node.skeleton) as Skeleton3D
	if skeleton == null:
		return result
	var transforms: Array[Transform3D] = []
	for bind in node.skin.get_bind_count():
		var name: StringName = node.skin.get_bind_name(bind)
		var bone: int = skeleton.find_bone(name) if not name.is_empty() else node.skin.get_bind_bone(bind)
		if bone < 0 or bone >= skeleton.get_bone_count():
			return PackedVector3Array()
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * node.skin.get_bind_pose(bind))
	for surface in node.mesh.get_surface_count():
		var arrays: Array = node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones.is_empty() or bones.size() != weights.size():
			return PackedVector3Array()
		var stride: int = bones.size() / vertices.size()
		for vertex in vertices.size():
			var point := Vector3.ZERO
			for influence in stride:
				var index: int = vertex * stride + influence
				if weights[index] <= 0:
					continue
				if bones[index] < 0 or bones[index] >= transforms.size():
					return PackedVector3Array()
				point += (transforms[bones[index]] * vertices[vertex]) * weights[index]
			result.append(point)
	return result


func _check_clip(asset: String, player: AnimationPlayer, skeletons: Array[Skeleton3D], skin_meshes: Array[MeshInstance3D], clip: String, errors: Array[String]) -> Dictionary:
	var animation: Animation = player.get_animation(clip)
	var animation_root: Node = player.get_node_or_null(player.root_node)
	var invalid_tracks: Array[String] = []
	var bone_tracks: int = 0
	if animation.length <= 0 or animation.get_track_count() == 0:
		_fail(asset + "/" + clip + ": empty animation", errors)
	for track in animation.get_track_count():
		var path: NodePath = animation.track_get_path(track)
		var node_path := NodePath(str(path).split(":")[0])
		var target_node: Node = animation_root.get_node_or_null(node_path) if animation_root != null else null
		var valid: bool = target_node != null and animation.track_get_key_count(track) > 0 and animation.track_is_enabled(track)
		var type: int = animation.track_get_type(track)
		if type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] and path.get_subname_count() > 0:
			valid = valid and target_node is Skeleton3D and target_node.find_bone(path.get_subname(0)) >= 0
			bone_tracks += 1
		elif type == Animation.TYPE_VALUE:
			valid = valid and path.get_subname_count() > 0
			if valid:
				valid = target_node.get_indexed(NodePath(":" + str(path.get_concatenated_subnames()))) != null
		if not valid:
			invalid_tracks.append(str(path))
	if not invalid_tracks.is_empty() or bone_tracks == 0:
		_fail(asset + "/" + clip + ": invalid/empty tracks: " + str(invalid_tracks), errors)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(clip)
	player.seek(0.0, true)
	player.advance(0)
	var baseline: Array[Transform3D] = _poses(skeletons)
	var baseline_vertices: Array[PackedVector3Array] = []
	for mesh in skin_meshes:
		baseline_vertices.append(_skin_vertices(mesh))
	var maximum_vertex_delta: float = 0
	var maximum: float = 0
	var changed: Dictionary = {}
	var sample_times: Array[float] = []
	for fraction in [0.2, 0.4, 0.6, 0.8, 0.99]:
		var sample_time: float = animation.length * fraction
		sample_times.append(sample_time)
		player.seek(sample_time, true)
		player.advance(0)
		await process_frame
		var sampled: Array[Transform3D] = _poses(skeletons)
		for mesh_index in skin_meshes.size():
			var points: PackedVector3Array = _skin_vertices(skin_meshes[mesh_index])
			var initial: PackedVector3Array = baseline_vertices[mesh_index]
			if points.size() != initial.size():
				_fail(asset + "/" + clip + ": cannot sample skinned geometry", errors)
				continue
			for vertex in points.size():
				maximum_vertex_delta = maxf(maximum_vertex_delta, points[vertex].distance_to(initial[vertex]))
		for bone in baseline.size():
			var delta: float = baseline[bone].origin.distance_to(sampled[bone].origin)
			delta += baseline[bone].basis.get_rotation_quaternion().angle_to(sampled[bone].basis.get_rotation_quaternion())
			delta += baseline[bone].basis.get_scale().distance_to(sampled[bone].basis.get_scale())
			maximum = maxf(maximum, delta)
			if delta > MOTION_EPSILON:
				changed[bone] = true
	player.stop()
	if maximum <= MOTION_EPSILON:
		_fail(asset + "/" + clip + ": sampled bone pose unchanged (max delta=" + str(maximum) + ")", errors)
	if maximum_vertex_delta <= MOTION_EPSILON:
		_fail(asset + "/" + clip + ": sampled skinned vertices unchanged (max delta=" + str(maximum_vertex_delta) + ")", errors)
	return {"clip": clip, "length_s": animation.length, "tracks": animation.get_track_count(), "bone_tracks": bone_tracks,
		"invalid_tracks": invalid_tracks, "sample_times_s": sample_times, "changed_bones": changed.size(), "max_pose_delta": maximum,
		"max_skinned_vertex_delta_m": maximum_vertex_delta}


func _poses(skeletons: Array[Skeleton3D]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for skeleton in skeletons:
		for bone in skeleton.get_bone_count():
			result.append(skeleton.get_bone_pose(bone))
	return result


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _check_layout() -> Dictionary:
	var total: int = 0
	var parts: Array[Dictionary] = []
	var errors: Array[String] = []
	for type_name in Viewer.DISPLAY_TYPES:
		var asset: String = type_name + "_t1"
		if not actual_triangles.has(asset):
			_fail("T01 sample missing " + asset, errors)
		var triangles: int = int(actual_triangles.get(asset, 0))
		total += triangles
		parts.append({"asset": asset, "triangles": triangles})
	# Ground, grid and rim use 43 boxes (12 triangles each); labels are UI, not art.
	var static_total: int = total + 43 * 12
	if static_total >= 30000:
		_fail("T01 sample static triangle budget >= 30000: " + str(static_total), errors)
	return {"tier": 1, "building_triangles": total, "board_triangles": 43 * 12,
		"static_triangles": static_total, "limit_exclusive": 30000, "parts": parts}


func _check_support() -> Array[Dictionary]:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.18, 32)
	shape.shape = box
	body.position.y = -0.09
	body.add_child(shape)
	stage.add_child(body)
	await physics_frame
	await physics_frame
	var result: Array[Dictionary] = []
	var errors: Array[String] = []
	for asset in ["manor_hall_t1", "gate_t1", "cottage_t1", "char_builder", "char_warrior"]:
		var record: Dictionary = {}
		for item in records:
			if item["asset"] == asset:
				record = item
		if not record.has("min_m"):
			_fail(asset + ": unavailable support sample", errors)
			continue
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(0, -1, 0))
		var hit: Dictionary = stage.get_world_3d().direct_space_state.intersect_ray(ray)
		var ground_y: float = hit["position"].y if not hit.is_empty() else INF
		var base_y: float = record["min_m"][1]
		var passed: bool = not hit.is_empty() and absf(base_y - ground_y) <= BASE_TOLERANCE_M
		if not passed:
			_fail(asset + ": support sample gap=" + str(base_y - ground_y), errors)
		result.append({"asset": asset, "aggregate_min_y_m": base_y, "ground_hit_y_m": ground_y,
			"gap_m": base_y - ground_y, "passed": passed, "method": "Aggregate rest bound base vs ground box raycast at origin; not per-foot contact or animated collision."})
	body.free()
	return result


func _check_viewer() -> Dictionary:
	var errors: Array[String] = []
	var packed: PackedScene = load("res://scenes/test_import.tscn") as PackedScene
	var viewer: Node3D = packed.instantiate() as Node3D
	stage.add_child(viewer)
	await process_frame
	var tiers: Array[Dictionary] = []
	for tier_index in range(1, 7):
		var key := InputEventKey.new()
		key.physical_keycode = KEY_0 + tier_index
		key.pressed = true
		viewer._unhandled_input(key)
		await process_frame
		var triangles: int = Viewer.mesh_triangles(viewer.buildings)
		var fallback_names: Array[String] = []
		if viewer.buildings.get_child_count() != Viewer.DISPLAY_TYPES.size() or viewer.tier != tier_index:
			_fail("Viewer tier %d: incorrect display count or key handling" % tier_index, errors)
		for index in Viewer.DISPLAY_TYPES.size():
			var type_name: String = Viewer.DISPLAY_TYPES[index]
			var expected_asset: String = "%s_t%d" % [type_name, tier_index]
			if not actual_triangles.has(expected_asset):
				expected_asset = type_name + "_t1"
				fallback_names.append(expected_asset)
			if index >= viewer.buildings.get_child_count():
				continue
			var displayed: Node3D = viewer.buildings.get_child(index)
			if not displayed.scene_file_path.ends_with(expected_asset + ".glb") or not displayed.scale.is_equal_approx(Vector3.ONE):
				_fail("Viewer tier %d: incorrect model or scale for %s" % [tier_index, type_name], errors)
		if triangles + 516 >= 30000:
			_fail("Viewer tier %d: static triangle budget >=30000" % tier_index, errors)
		tiers.append({"tier": tier_index, "building_triangles": triangles, "static_triangles": triangles + 516, "fallbacks": fallback_names})
	if viewer.characters.size() != 8:
		_fail("Viewer: not all eight characters displayed", errors)
	for clip_index in range(7):
		viewer._set_animation(clip_index)
		for character: Dictionary in viewer.characters:
			var player: AnimationPlayer = character["player"]
			if player == null or not player.is_playing():
				_fail("Viewer: animation selection %d not playing" % clip_index, errors)
	viewer._toggle_day()
	if not viewer.night:
		_fail("Viewer: night toggle failed", errors)
	viewer._toggle_day()
	var before: Vector3 = viewer.camera.position
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	viewer._unhandled_input(wheel)
	if viewer.camera.position.is_equal_approx(before):
		_fail("Viewer: wheel zoom did not move camera", errors)
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_RIGHT
	drag.pressed = true
	viewer._unhandled_input(drag)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20, 10)
	before = viewer.camera.position
	viewer._unhandled_input(motion)
	drag.pressed = false
	viewer._input(drag)
	if viewer.camera.position.is_equal_approx(before) or viewer.dragging:
		_fail("Viewer: right-drag orbit/release failed", errors)
	# Exercise held-key camera controls through the same public input state as runtime.
	for key_code in [KEY_Q, KEY_E, KEY_W, KEY_A, KEY_S, KEY_D]:
		var key := InputEventKey.new()
		key.physical_keycode = key_code
		key.keycode = key_code
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		before = viewer.camera.position
		viewer._process(0.1)
		var release := InputEventKey.new()
		release.physical_keycode = key_code
		release.keycode = key_code
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		if viewer.camera.position.is_equal_approx(before):
			_fail("Viewer: camera key did not move camera: " + OS.get_keycode_string(key_code), errors)
	viewer.free()
	return {"passed": errors.is_empty(), "tiers": tiers, "animation_selections": 7,
		"controls": "1-6, Q/E, WASD, wheel, right-drag/release, day/night exercised", "errors": errors}
