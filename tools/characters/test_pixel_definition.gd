extends SceneTree
var failed := 0
func check(value: bool, message: String) -> void:
	print(('PASS: ' if value else 'FAIL: ') + message)
	if not value: failed += 1
func _initialize() -> void:
	if not FileAccess.file_exists('res://scripts/characters/pixel_character_definition.gd'):
		check(false, '角色清单加载器尚未实现')
		quit(1)
		return
	var loader = load('res://scripts/characters/pixel_character_definition.gd')
	var result: Dictionary = loader.load_definition('res://assets/chars/rinne_25d/animation_manifest.json')
	check(result.ok, '现有凛音清单成功载入，原件无需修改')
	if result.ok:
		var frames: SpriteFrames = result.frames
		for row in [['walk', 10, 0.50302], ['attack', 6, 0.460], ['idle', 6, 3.0]]:
			var duration := 0.0
			for i in frames.get_frame_count(row[0]): duration += frames.get_frame_duration(row[0], i) / frames.get_animation_speed(row[0])
			check(frames.get_frame_count(row[0]) == row[1] and absf(duration - row[2]) < 0.00001, '%s原节奏无损' % row[0])
		check(not frames.get_animation_loop('attack'), '攻击非循环')
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string('res://assets/chars/rinne_25d/animation_manifest.json'))
	for mutation in ['missing', 'duration', 'count', 'anchor', 'canvas', 'canvas_type', 'anims_type', 'spec_type', 'frames_type', 'duration_type', 'speed_type', 'layers_type', 'layer_type', 'layer_without_idle']:
		var m := baseline.duplicate(true)
		match mutation:
			'missing': m.anims.walk.frames[0] = '不存在'
			'duration': m.anims.walk.durations_ms[0] = 0
			'count': m.anims.walk.durations_ms.pop_back()
			'anchor': m.canvas.anchor = [-1, 700]
			'canvas': m.canvas.w = 33
			'canvas_type': m.canvas = []
			'anims_type': m.anims = []
			'spec_type': m.anims.walk = []
			'frames_type': m.anims.walk.frames = 'bad'
			'duration_type': m.anims.walk.durations_ms[0] = 'bad'
			'speed_type': m.move_speed_mps = 'bad'
			'layers_type': m.layers = {}
			'layer_type': m.layers = [42]
			'layer_without_idle':
				m = JSON.parse_string(FileAccess.get_file_as_string('res://assets/chars/pixel/rinne/manifest.json'))
				m.anims.erase('idle')
		var path: String = 'user://broken_' + mutation + '.json'
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(m))
		file.close()
		var broken: Dictionary = loader.load_definition(path)
		check(not broken.get('ok', false) and not broken.get('errors', []).is_empty(), mutation + '不允许悄悄错配帧时长')
	check(not loader.load_definition('res://missing.json').ok, '不存在清单明确失败')
	print('DEFINITION_RESULT: ', failed)
	quit(1 if failed else 0)
