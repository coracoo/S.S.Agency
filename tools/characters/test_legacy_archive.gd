extends SceneTree
var failed := 0
func check(value: bool, message: String) -> void:
	print(('PASS: ' if value else 'FAIL: ') + message)
	if not value: failed += 1
func _initialize() -> void:
	if not FileAccess.file_exists('res://scripts/characters/legacy_asset_paths.gd'):
		check(false, '归档原件须有明确的开发兼容路径')
		quit(1)
		return
	var paths = load('res://scripts/characters/legacy_asset_paths.gd')
	var png = load('res://scripts/ui/png_loader.gd')
	var definition = load('res://scripts/characters/pixel_character_definition.gd')
	var current := 'res://assets/chars/pixel/rinne/high_detail_complete/manifest.json'
	var retired := 'res://assets/chars/rinne_25d/animation_manifest.json'
	check(paths.resolve(current) == current, '正式清单原位优先')
	check(paths.resolve('res://missing.json') == 'res://missing.json', '未知资源不伪装为归档')
	check(paths.resolve(retired) == 'res://old/characters/assets/chars/rinne_25d/animation_manifest.json', '旧清单映射到字节保留的归档')
	check(definition.load_definition(current).ok, '正式七形态接口继续可读')
	check(definition.load_definition(retired).ok, '历史2.5D清单和原dir仍可读')
	check(definition.load_definition('res://assets/chars/pixel/rinne/manifest.json').ok, '历史像素清单与分层仍可读')
	check(definition.load_definition('res://assets/chars/pixel/guard/high_detail_pilot/manifest.json').ok, '试点清单仍可用于历史验证')
	check(png.load_texture('res://assets/chars/enemy_paper_doll.png') != null, '旧战斗JSON的图片URI仍可读')
	check(png.load_texture('res://assets/chars/anims/rinne_idle_f1.png') != null, '仍被正式3D源场景使用的旧首帧原位可读')
	check(not definition.load_definition('res://assets/chars/pixel/rinne/missing.json').ok, '真正缺帧清单不被掩盖')
	print('LEGACY_ARCHIVE_RESULT: ', failed)
	quit(1 if failed else 0)
