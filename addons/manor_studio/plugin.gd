@tool
extends EditorPlugin

const StudioPanel = preload("res://addons/manor_studio/dock.gd")
var dock: EditorDock
var panel


func _enter_tree() -> void:
	dock = EditorDock.new()
	dock.name = "ManorStudio"
	dock.title = "Manor Studio"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	panel = StudioPanel.new()
	panel.open_game_requested.connect(_open_game)
	panel.data_saved.connect(_data_saved)
	dock.add_child(panel)
	add_dock(dock)
	_report_ready.call_deferred()


func _report_ready() -> void:
	if is_instance_valid(panel) and not panel.model.data.is_empty():
		print("MANOR_STUDIO READY buildings=", panel.model.data.size())


func _open_game() -> void:
	EditorInterface.open_scene_from_path("res://scenes/game.tscn")


func _data_saved() -> void:
	EditorInterface.get_resource_filesystem().update_file("res://data/buildings.json")


func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_dock(dock)
		dock.queue_free()
	dock = null
	panel = null
