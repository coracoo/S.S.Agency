# FPS/帧耗时探针：加载指定场景跑 N 秒，统计平均/p95/最差帧耗时与最低瞬帧率
# 用法: Godot --path <项目> --script res://tools/measure_fps.gd -- <场景.tscn> [秒数]
extends SceneTree

var _deltas: Array = []
var _elapsed := 0.0
var _target := 12.0
var _scene := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("缺少场景参数")
		quit(1)
	_scene = args[0]
	# 其余参数原样留给场景自己消费（如 --auto-demo）；只有可解析数字才当秒数
	for i in range(1, args.size()):
		if args[i].is_valid_float():
			_target = float(args[i])
			break
	root.window_size = Vector2i(1920, 1080)
	call_deferred("_start")

func _start() -> void:
	var err := change_scene_to_file(_scene)
	if err != OK:
		printerr("场景加载失败: ", _scene)
		quit(1)

func _process(delta: float) -> bool:
	if _scene.is_empty():
		return false
	# 等场景就绪后再采（前 1 秒是加载抖动，跳过）
	if root.get_child_count() > 0 and root.get_child(0).name != "root":
		if _elapsed > 1.0:
			_deltas.append(delta)
		_elapsed += delta
		if _elapsed >= _target:
			_report()
			quit(0)
	return false

func _report() -> void:
	if _deltas.is_empty():
		printerr("无采样")
		return
	_deltas.sort()
	var n := _deltas.size()
	var avg := 0.0
	for d in _deltas:
		avg += d
	avg /= n
	var p95: float = _deltas[int(n * 0.95)]
	var worst: float = _deltas[n - 1]
	var fps_now := Engine.get_frames_per_second()
	print("FPS_PROBE scene=%s frames=%d avg_ms=%.2f p95_ms=%.2f worst_ms=%.2f min_fps=%d" % [
		_scene, n, avg * 1000.0, p95 * 1000.0, worst * 1000.0,
		int(1.0 / worst)])
