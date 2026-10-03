extends SceneTree
var failed := 0
func check(value: bool, message: String) -> void:
	print(('PASS: ' if value else 'FAIL: ') + message)
	if not value: failed += 1
func _initialize() -> void: call_deferred('run')
func run() -> void:
	var loader = load('res://scripts/characters/pixel_character_definition.gd')
	var definition: Dictionary = loader.load_definition('res://assets/chars/pixel/rinne/manifest.json')
	check(definition.ok, '新凛音真实帧清单可读')
	var frames: SpriteFrames = definition.frames
	var idle_seconds := 0.0
	for i in frames.get_frame_count('idle'): idle_seconds += frames.get_frame_duration('idle',i)
	check(frames.get_frame_count('idle')==6 and absf(idle_seconds-3.0)<0.0001, '新凛音待机往返3秒')
	var animator = load('res://scripts/characters/pixel_character_animator.gd').new()
	root.add_child(animator)
	animator.configure(definition)
	check(animator._layers.size() == 1, '真实尾尖图层已绑定，不是仅声明支持')
	if animator._layers.size() == 1:
		var layer = animator._layers[0]
		check(layer.material is ShaderMaterial, '发根固定的像素位移材质')
		var first = layer.texture
		animator.sprite.set_frame_and_progress(2,0.0)
		animator._process(0.2)
		check(layer.texture != first, '层随主体待机帧同步')
		var neutral_position: Vector2 = layer.position
		animator._process(0.8)
		check(layer.position == neutral_position, '仅末梢像素移动，不整体挪根')
		animator.set_motion(2.6, 1)
		check(not layer.visible, '走路隐藏待机局部层')
		animator.set_motion(0,1)
		check(layer.visible, '停步恢复分层')
		animator.request_action('attack')
		check(not layer.visible, '攻击使用完整帧不叠待机层')
	animator.queue_free()
	await process_frame
	print('LAYERS_RESULT: ',failed)
	quit(1 if failed else 0)
