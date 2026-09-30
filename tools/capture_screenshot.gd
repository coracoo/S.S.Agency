# 临时工具:直接运行战斗场景并截图保存到项目根目录
# 用法: Godot --path <项目> --script res://tools/capture_screenshot.gd -- <输出文件名> [等待秒数]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_name: String = args[0] if args.size() > 0 else "tmp_eval_shot.png"
	var wait_s: float = float(args[1]) if args.size() > 1 else 2.5
	var scene_path: String = args[2] if args.size() > 2 else "res://scenes/battle.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("无法加载场景: " + scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	await create_timer(wait_s).timeout
	var img := root.get_texture().get_image()
	var save_path := "res://" + out_name
	var err := img.save_png(save_path)
	print("SCREENSHOT_SAVED:", save_path, " err=", err, " size=", img.get_size())
	quit(0 if err == OK else 1)
