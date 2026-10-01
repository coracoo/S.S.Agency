# 先核验引擎真实写档目录，禁止用未验证的命令行目录参数替代。
extends SceneTree

func _initialize() -> void:
	var root := OS.get_environment("RPG_TEST_ROOT").replace("\\", "/").simplify_path().trim_suffix("/")
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if root.is_empty() or not root.is_absolute_path() or not user_dir.begins_with(root + "/"):
		printerr("FAIL: user:// 未隔离：", user_dir)
		quit(1)
		return
	for key in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"]:
		var directory := OS.get_environment(key).replace("\\", "/").simplify_path()
		if not directory.begins_with(root + "/"):
			printerr("FAIL: 环境变量未隔离：", key)
			quit(1)
			return
	print("RPG_ISOLATION_OK:", user_dir)
	quit(0)
