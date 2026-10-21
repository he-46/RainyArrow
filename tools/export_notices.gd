extends SceneTree
## License texts supplied by the exact engine used for the build.
func _initialize() -> void:
	var file := FileAccess.open("res://builds/windows/Godot-Third-Party-Notices.txt", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string("Godot " + Engine.get_version_info().string + "\n\n" + Engine.get_license_text())
	file.store_string("\n\nCopyright notices:\n" + JSON.stringify(Engine.get_copyright_info(), "\t"))
	var licenses: Dictionary = Engine.get_license_info()
	for name: String in licenses:
		file.store_string("\n\n" + name + "\n" + str(licenses[name]))
	file.close()
	quit()
