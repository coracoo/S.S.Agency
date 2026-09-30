class_name PlayerController
extends Node2D
## 玩家控制器 v4 —— 网格滑动移动（防闪烁版）
##
## 防闪烁三原则：
##   1. 像素图整数倍缩放（×2），杜绝 1.5× 的奇偶像素不均
##   2. 滑动起止坐标取整（round），NEAREST 采样不做子像素抖动
##   3. 滑动回调只复位子精灵的浮动量，绝不动父节点 position（父节点由 tween 落到目标格）
##
## position = 玩家脚底世界坐标（始终整数）。

signal slide_finished()

const SLIDE_TIME := 0.15
const SCALE := 2.0
const BASE_SPRITE_Y := -96.0  # 48px 高 × 2 = 96，脚底对齐父节点原点

var _sprite: Sprite2D
var _placeholder: ColorRect
var _walk_tween: Tween


func setup(sprite_path: String, world_feet: Vector2) -> void:
	position = Vector2(roundf(world_feet.x), roundf(world_feet.y))
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(SCALE, SCALE)
	_sprite.position = Vector2(-32, BASE_SPRITE_Y)  # 64 宽水平居中，96 高脚底对齐
	_sprite.z_index = 5
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_sprite.texture = load(sprite_path)
	add_child(_sprite)
	# 占位色块（贴图丢失时可见）
	_placeholder = ColorRect.new()
	_placeholder.color = Color(0.72, 0.53, 0.04, 1)
	_placeholder.size = Vector2(48, 72)
	_placeholder.position = Vector2(-24, -72)
	_placeholder.z_index = 5
	if _sprite.texture != null:
		_placeholder.visible = false
	add_child(_placeholder)


func is_sliding() -> bool:
	return _walk_tween != null and _walk_tween.is_valid() and _walk_tween.is_running()


## 平滑滑到目标脚底坐标；返回是否开始滑动
func slide_to(world_feet: Vector2) -> bool:
	if is_sliding():
		return false
	world_feet = Vector2(roundf(world_feet.x), roundf(world_feet.y))
	var dir_x = world_feet.x - position.x
	if dir_x != 0:
		set_facing_left(dir_x < 0)
	_kill_tween()
	_walk_tween = create_tween()
	_walk_tween.set_parallel(true)
	# 父节点整体滑动（唯一的 position 写入者，无任何回调再改它）
	_walk_tween.tween_property(self, "position", world_feet, SLIDE_TIME).set_trans(Tween.TRANS_SINE)
	# 子精灵走路起伏（只在子节点上做，父节点不受影响）
	_walk_tween.tween_property(_sprite, "position:y", BASE_SPRITE_Y - 8.0, SLIDE_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	_walk_tween.chain().tween_property(_sprite, "position:y", BASE_SPRITE_Y, SLIDE_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	_walk_tween.chain().tween_callback(_finish_slide)
	return true


func _finish_slide() -> void:
	# 落格取整 + 浮动复位（只动子精灵，绝不动父节点 position 的 y）
	position = Vector2(roundf(position.x), roundf(position.y))
	_sprite.position.y = BASE_SPRITE_Y
	slide_finished.emit()


func set_facing_left(v: bool) -> void:
	if _sprite == null:
		return
	_sprite.scale.x = -SCALE if v else SCALE
	_sprite.position.x = 32 if v else -32


func _kill_tween() -> void:
	if _walk_tween != null and _walk_tween.is_valid():
		_walk_tween.kill()
		_walk_tween = null
