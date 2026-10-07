# 极小PCK验证外置路径；不打包视频或生成正式发布物。
extends SceneTree
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var directory := OS.get_environment("RPG_TEST_ROOT")
	if OS.get_environment("CUTSCENE_PACK_MODE") == "build":
		var config := directory.path_join("probe-project.godot")
		var file := FileAccess.open(config, FileAccess.WRITE)
		file.store_string('config_version=5\n[application]\nconfig/name="CutsceneExternalProbe"\n')
		file.close()
		var pack := PCKPacker.new()
		assert(pack.pck_start(directory.path_join("probe.pck")) == OK)
		assert(pack.add_file("res://project.godot", config) == OK)
		assert(pack.add_file("res://scripts/campaign/cutscene_catalog.gd", "res://scripts/campaign/cutscene_catalog.gd") == OK)
		assert(pack.flush() == OK)
		quit()
		return
	var clips: Script = load("res://scripts/campaign/cutscene_catalog.gd")
	var actual: String = clips.resolve_file(clips.STONE_BOWL_FILE)
	var expected := directory.path_join("cutscenes/night1_stone_bowl.ogv")
	print("CUTSCENE_EXTERNAL_ARGS:", OS.get_cmdline_args())
	print("CUTSCENE_RESOURCE_ROOT:", ProjectSettings.globalize_path("res://"))
	print("CUTSCENE_SETTINGS:", ProjectSettings.get_setting("application/run/main_scene", ""), " EDITOR:", OS.has_feature("editor"))
	print("CUTSCENE_EXTERNAL_FILE:", actual)
	if actual != expected:
		printerr("ASSERT FAIL: 独立PCK未找到旁置过场")
		quit(1)
		return
	quit()
