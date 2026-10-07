@tool
extends RefCounted

const DEFAULT_PATH: String = "res://data/buildings.json"
const BASE_FIELDS: Dictionary = {"buildSeconds": "Build time (seconds)", "rate": "Base production rate", "reserve": "On-site reserve"}
const TIER_FIELDS: Dictionary = {"hp": "Hit points", "damage": "Damage", "range": "Range", "rateMultiplier": "Production multiplier"}
var data: Dictionary = {}
var error: String = ""
var path: String = DEFAULT_PATH
var baseline: Dictionary = {}
var original_text: String = ""


func load_file(source: String = DEFAULT_PATH) -> bool:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null: return _fail("Cannot open building data: %s" % error_string(FileAccess.get_open_error()))
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK: return _fail("Invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary: return _fail("Building data must be an object.")
	var reason: String = _validate(json.data)
	if not reason.is_empty(): return _fail(reason)
	path = source
	original_text = text
	baseline = json.data.duplicate(true)
	data = baseline.duplicate(true)
	error = ""
	return true


func editable_fields(id: String, tier: int = 0) -> Array[Dictionary]:
	if not data.has(id): return []
	return _fields(data[id], tier)


func _fields(spec: Dictionary, tier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resource: String in spec.get("cost", {}):
		result.append({"label": "%s cost" % resource.capitalize(), "path": ["cost", resource], "value": spec["cost"][resource]})
	for key: String in BASE_FIELDS:
		if spec.has(key): result.append({"label": BASE_FIELDS[key], "path": [key], "value": spec[key]})
	if tier >= 0 and tier < spec["tiers"].size():
		for key: String in TIER_FIELDS:
			if spec["tiers"][tier].has(key):
				result.append({"label": TIER_FIELDS[key], "path": ["tiers", tier, key], "value": spec["tiers"][tier][key]})
	return result


func set_numeric(id: String, field: Array, value: float) -> bool:
	var tier: int = 0
	if field.size() == 3 and field[0] == "tiers":
		if typeof(field[1]) != TYPE_INT: return _fail("Tier index must be an integer.")
		tier = field[1]
	var allowed: bool = false
	for item: Dictionary in editable_fields(id, tier):
		if item["path"] == field: allowed = true
	if not allowed: return _fail("This field is not editable.")
	var reason: String = _number_error(field, value)
	if not reason.is_empty(): return _fail(reason)
	var target: Variant = data[id]
	for index in field.size() - 1: target = target[field[index]]
	target[field.back()] = value
	error = ""
	return true


func _number_error(field: Array, value: Variant) -> String:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
		return "Values must be finite, nonnegative numbers."
	if field.back() == "hp" and float(value) <= 0.0: return "Hit points must be greater than zero."
	return ""


func _validate(document: Dictionary) -> String:
	if document.is_empty(): return "Building data is empty."
	for id: Variant in document:
		var spec: Variant = document[id]
		if not spec is Dictionary or not spec.get("name") is String or str(spec["name"]).strip_edges().is_empty():
			return "Invalid building name: %s" % id
		if not spec.get("cost", {}) is Dictionary or not spec.get("tiers") is Array or spec["tiers"].is_empty():
			return "Invalid costs or tiers: %s" % id
		for tier in spec["tiers"].size():
			if not spec["tiers"][tier] is Dictionary or not spec["tiers"][tier].has("hp"):
				return "Invalid tier: %s / %d" % [id, tier + 1]
			for field: Dictionary in _fields(spec, tier):
				var reason: String = _number_error(field["path"], field["value"])
				if not reason.is_empty(): return "%s: %s" % [id, reason]
	return ""


func is_dirty() -> bool:
	return data != baseline


func discard() -> void:
	data = baseline.duplicate(true)
	error = ""


func save() -> bool:
	var reason: String = _validate(data)
	if not reason.is_empty(): return _fail(reason)
	if not is_dirty():
		error = ""
		return true
	var lock_path: String = path + ".manor-studio.lock"
	if DirAccess.make_dir_absolute(lock_path) != OK:
		return _fail("Another Studio Apply is active, or a stale write lock exists. Source data and draft are retained.")
	var saved: bool = _save_locked()
	DirAccess.remove_absolute(lock_path)
	return saved


func _save_locked() -> bool:
	if FileAccess.get_file_as_string(path) != original_text:
		return _fail("File changed outside Manor Studio. Your draft is kept; Discard / Reload to read the new version.")
	var temporary: String = path + ".manor-studio.tmp"
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
		return _fail("A staging file already exists. Apply stopped without overwriting it.")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("Cannot create staging file: %s" % error_string(FileAccess.get_open_error()))
	var text: String = JSON.stringify(data, "\t", false, true) + "\n"
	file.store_string(text)
	file.flush()
	var result: Error = file.get_error()
	file.close()
	if result == OK and FileAccess.get_file_as_string(path) != original_text: result = ERR_BUSY
	if result == OK: result = DirAccess.copy_absolute(path, path + ".manor-studio.previous")
	if result == OK and FileAccess.get_file_as_string(path) != original_text: result = ERR_BUSY
	if result == OK: result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
		return _fail("Apply failed (%s). Source data and draft are retained." % error_string(result))
	original_text = text
	baseline = data.duplicate(true)
	error = ""
	return true


func _fail(message: String) -> bool:
	error = message
	return false
