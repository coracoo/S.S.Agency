class_name WashiOverlay
## 全屏和纸 multiply 叠加（画面 polish）：统一战斗/探索场景的绘本纸质质感。
## 用法：WashiOverlay.add_to(self) —— 场景 _ready 末尾调用一次。
## 原理：CanvasLayer(层 1) 上铺 BLEND_MODE_MUL 的纹理，alpha 控制叠加强度，
## 画面越亮处影响越小、暗部染上暖纸色；不挡输入（mouse IGNORE）。
extends CanvasLayer

const TEX_PATH := "res://assets/textures/washi_overlay.png" # washi_full 的 1920 降采样版（原图 9MB 过大）

static func add_to(parent: Node, alpha := 0.18) -> void:
	var layer := WashiOverlay.new()
	layer.layer = 1 # 高于场景层 0、低于墨线转场（转场见 ink_transition.gd 的 CanvasLayer 128）
	parent.add_child(layer)
	var rect := TextureRect.new()
	rect.texture = PngLoader.load_texture(TEX_PATH) # FileAccess 虚拟文件系统，导出 pck 内可用
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	rect.material = mat
	rect.modulate = Color(1.0, 1.0, 1.0, alpha)
	layer.add_child(rect)
