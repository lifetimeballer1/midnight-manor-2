@tool
extends VBoxContainer

signal open_game_requested
signal data_saved

const Model = preload("res://addons/manor_studio/balance_model.gd")
var model = Model.new()
var data_path: String = Model.DEFAULT_PATH
var building_ids: Array[String] = []
var buildings := OptionButton.new()
var tiers := OptionButton.new()
var fields := VBoxContainer.new()
var editors: Dictionary = {}
var status := Label.new()
var apply_button := Button.new()
var discard_button := Button.new()
var open_button := Button.new()


func _ready() -> void:
	name = "Manor Studio"
	custom_minimum_size.x = 260
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "MANOR STUDIO / BUILDING BALANCE"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	var help := Label.new()
	help.text = "Stage changes, then Apply. Changes affect the next game run; player saves are never edited."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	buildings.tooltip_text = "Select an authored building"
	buildings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buildings.item_selected.connect(_select_building)
	add_child(buildings)
	tiers.tooltip_text = "Select the tier to edit"
	tiers.item_selected.connect(_select_tier)
	add_child(tiers)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	add_child(scroll)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	apply_button.text = "Apply Balance Changes"
	apply_button.pressed.connect(_apply)
	apply_button.tooltip_text = "Validate, back up previous data, then save. Does not alter a running game."
	add_child(apply_button)
	discard_button.text = "Discard / Reload"
	discard_button.pressed.connect(_reload)
	add_child(discard_button)
	open_button.text = "Open Game Scene"
	open_button.pressed.connect(func(): open_game_requested.emit())
	add_child(open_button)
	_reload()


func _reload() -> void:
	var selected: String = building_ids[buildings.selected] if buildings.selected >= 0 and not building_ids.is_empty() else ""
	if not model.load_file(data_path):
		_refresh_status()
		return
	building_ids.clear()
	buildings.clear()
	for id: String in model.data: building_ids.append(id)
	building_ids.sort_custom(func(a, b): return str(model.data[a]["name"]).naturalnocasecmp_to(str(model.data[b]["name"])) < 0)
	for id: String in building_ids: buildings.add_item("%s (%s)" % [model.data[id]["name"], id])
	var index: int = maxi(0, building_ids.find(selected))
	buildings.select(index)
	_select_building(index)


func _select_building(index: int) -> void:
	if index < 0 or index >= building_ids.size(): return
	tiers.clear()
	for tier in model.data[building_ids[index]]["tiers"].size(): tiers.add_item("Tier %d" % (tier + 1))
	tiers.select(0)
	_render_fields()


func _select_tier(_index: int) -> void:
	_render_fields()


func _render_fields() -> void:
	for child: Node in fields.get_children():
		fields.remove_child(child)
		child.queue_free()
	editors.clear()
	if buildings.selected < 0: return
	var id: String = building_ids[buildings.selected]
	for field: Dictionary in model.editable_fields(id, tiers.selected):
		var row := VBoxContainer.new()
		var label := Label.new()
		label.text = field["label"]
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = 1000000.0
		spin.allow_greater = true
		spin.step = 0.0
		spin.custom_arrow_step = 1.0
		spin.value = float(field["value"])
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_changed.bind(id, field["path"], spin))
		spin.get_line_edit().focus_exited.connect(_sync_text.bind(spin), CONNECT_DEFERRED)
		row.add_child(spin)
		fields.add_child(row)
		var key: String = ".".join(field["path"].map(func(part): return str(part)))
		editors[key] = spin
		_sync_text(spin)
	_refresh_status()


func _changed(value: float, id: String, field: Array, spin: SpinBox) -> void:
	if not model.set_numeric(id, field, value):
		var previous: Variant = model.data[id]
		for part: Variant in field: previous = previous[part]
		spin.set_value_no_signal(float(previous))
	_sync_text(spin)
	_refresh_status()


func _sync_text(spin: SpinBox) -> void:
	if is_instance_valid(spin): spin.get_line_edit().text = JSON.stringify(spin.value, "", false, true)


func _apply() -> void:
	if model.save(): data_saved.emit()
	_refresh_status()


func _refresh_status() -> void:
	apply_button.disabled = model.data.is_empty() or not model.is_dirty()
	status.text = model.error if not model.error.is_empty() else ("Unsaved balance changes. Apply or Discard / Reload." if model.is_dirty() else "Saved data loaded. No staged changes.")
