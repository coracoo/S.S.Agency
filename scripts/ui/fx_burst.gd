class_name FxBurst
extends RefCounted
## 一次性粒子迸发（卡牌化作粒子 / 命中 / 场景槽激活）。
## 用法: FxBurst.burst(self, pos, color) —— 自动释放。

static func burst(parent: Node, pos: Vector2, c: Color, count := 26, spread := 220.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = count
	p.lifetime = 0.55
	p.position = pos
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = spread * 0.4
	p.initial_velocity_max = spread
	p.gravity = Vector2(0, 320)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = c
	parent.add_child(p)
	p.emitting = true
	_free_later(p)

static func _free_later(p: CPUParticles2D) -> void:
	await p.get_tree().create_timer(1.2).timeout
	if is_instance_valid(p):
		p.queue_free()
