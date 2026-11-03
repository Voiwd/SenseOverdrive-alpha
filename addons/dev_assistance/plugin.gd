@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_tool_menu_item("DevAssistance: executar cena atual", _run_current)


func _exit_tree() -> void:
	remove_tool_menu_item("DevAssistance: executar cena atual")


func _run_current() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	if scene != null and not scene.scene_file_path.is_empty():
		EditorInterface.play_custom_scene(scene.scene_file_path)
