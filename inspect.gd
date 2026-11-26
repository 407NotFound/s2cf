extends SceneTree
func _init():
	print("PROJECT_NAME=[", ProjectSettings.get_setting("application/config/name"), "]")
	var cf := ConfigFile.new()
	var err := cf.load("res://export_presets.cfg")
	print("cfg_err=", err)
	print("sections=", cf.get_sections())
	for s in cf.get_sections():
		if s.begins_with("preset"):
			print("  [", s, "] name=", cf.get_value(s, "name", "?"))
			if s.ends_with("options"):
				print("    product_name=", cf.get_value(s, "application/product_name", "<none>"))
				print("    app_name=", cf.get_value(s, "application/app_name", "<none>"))
				print("    bundle=", cf.get_value(s, "application/bundle_identifier", "<none>"))
	quit()
