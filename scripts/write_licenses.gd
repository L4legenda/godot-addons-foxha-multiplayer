extends SceneTree
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/windows/licenses")
	var output := FileAccess.open("res://builds/windows/licenses/Godot.txt", FileAccess.WRITE)
	output.store_string(Engine.get_license_text() + "\n\n" + JSON.stringify(Engine.get_copyright_info(), "  ") + "\n\n" + JSON.stringify(Engine.get_license_info(), "  "))
	quit()
