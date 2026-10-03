extends SceneTree
var failed := 0
var finishes := 0
func check(value: bool, message: String) -> void:
	print(('PASS: ' if value else 'FAIL: ') + message)
	if not value: failed += 1
func _initialize() -> void: call_deferred('run')
func run() -> void:
	if not FileAccess.file_exists('res://scripts/characters/pixel_character_animator.gd'):
		check(false, '唯一动画状态机尚未实现')
		quit(1)
		return
	var loader = load('res://scripts/characters/pixel_character_definition.gd')
	var definition: Dictionary = loader.load_definition('res://assets/chars/rinne_25d/animation_manifest.json')
	var animator = load('res://scripts/characters/pixel_character_animator.gd').new()
	root.add_child(animator)
	check(animator.configure(definition), '装配已有帧而非重做节奏')
	animator.action_finished.connect(func(): finishes += 1)
	animator.set_motion(2.6, 1)
	check(animator.sprite.animation == 'walk' and is_equal_approx(animator.sprite.speed_scale, 1.0), '真实速度驱动步态')
	animator.sprite.set_frame_and_progress(3, 0.4)
	animator.set_motion(2.6, -1)
	check(animator.sprite.frame == 3 and animator.sprite.flip_h, '反向不重置步态')
	animator.set_motion(0.0, -1)
	check(animator.sprite.animation == 'idle' and animator.sprite.speed_scale == 1.0, '堵墙/停步恢复待机速度')
	check(animator.request_action('attack'), '攻击开始')
	check(not animator.request_action('attack'), '攻击不可重入')
	check(not animator.request_action('recover'), '恢复不能打断攻击或自行重入')
	await create_timer(0.6).timeout
	check(animator.sprite.animation == 'idle' and finishes == 1, '零参结束回调收招回待机一次')
	check(animator.request_action('hit'), '缺少可选受击有明确neutral完成路径')
	await process_frame
	check(not animator.is_action_locked(), 'neutral不会卡死')
	animator.request_action('attack')
	animator.request_action('down')
	await create_timer(0.6).timeout
	check(animator.is_downed(), '迟到攻击结束不能取消倒地')
	animator.request_action('recover')
	await process_frame
	check(not animator.is_downed(), '恢复解除倒地')
	animator.request_action('attack')
	animator.configure(definition)
	await create_timer(0.6).timeout
	check(animator.sprite.animation == 'idle' and not animator.is_action_locked(), '切换资产取消旧动作')
	animator.set_motion(2.6, 1)
	animator.reset()
	check(animator.sprite.animation == 'idle', '重置清除运动')
	for fps in [30, 60, 120]:
		animator.request_action('attack')
		animator.sprite.pause() # 模拟结束信号丢失，只检验视觉watchdog。
		for tick in range(int(fps * 0.7)): animator._process(1.0 / fps)
		check(not animator.is_action_locked() and animator.sprite.animation == 'idle', '%dfps信号缺失可恢复' % fps)
	animator.set_motion(2.6, 1)
	paused = true
	var paused_frame: int = animator.sprite.frame
	await create_timer(0.15, true).timeout
	check(animator.sprite.frame == paused_frame, '树暂停不推进动作')
	paused = false
	await create_timer(0.15).timeout
	check(animator.sprite.frame != paused_frame, '恢复暂停后正常推进')
	animator.queue_free()
	await process_frame
	print('ANIMATOR_RESULT: ', failed)
	quit(1 if failed else 0)
