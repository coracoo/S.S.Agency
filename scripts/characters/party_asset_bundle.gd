# 试玩会话持有已选三人的定义；纹理由Definition弱缓存共享，离开试玩才clear。
class_name PartyAssetBundle
extends RefCounted
signal progress(completed: int, total: int)
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const MANIFESTS := {
	"rinne": "res://assets/chars/pixel/rinne/high_detail_complete/manifest.json",
	"mint": "res://assets/chars/pixel/mint/high_detail_complete/manifest.json",
	"guard": "res://assets/chars/pixel/guard/high_detail_complete/manifest.json"
}
var _definitions: Dictionary = {}
var _bindings: Dictionary = {}
var _generation := 0
var _preparing := false

func prepare(bindings: Dictionary) -> Dictionary:
	if _preparing: return _failure("人物资源正在加载")
	var identities: Array[String] = []
	if bindings.is_empty(): return _failure("当前队伍没有人物绑定")
	for actor_id in bindings:
		if not actor_id is String or not bindings[actor_id] is Dictionary: return _failure("人物绑定格式错误")
		var binding: Dictionary = bindings[actor_id]
		if binding.size() != 2 or not binding.get("identity_id") is String or not binding.get("form_id") is String: return _failure("人物绑定必须声明身份和形态")
		var id: String = binding.identity_id
		if not MANIFESTS.has(id) or binding.form_id != id: return _failure("人物或形态不在试玩高清白名单")
		if not identities.has(id): identities.append(id)
	if _bindings == bindings and not _definitions.is_empty(): return {"ok": true, "error": ""}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return _failure("人物加载需要场景树")
	_generation += 1
	var generation := _generation
	_preparing = true
	var prepared: Dictionary = {}
	for id in identities:
		var definition: Dictionary = _definitions.get(id, {})
		if definition.is_empty(): definition = Definition.load_definition(MANIFESTS[id])
		if not definition.get("ok", false):
			_preparing = false
			return _failure("%s高清资源加载失败：%s" % [id, "；".join(definition.get("errors", []))])
		if definition.manifest.get("identity_id") != id or definition.manifest.get("form_id") != id:
			_preparing = false
			return _failure("高清清单身份不符：" + id)
		prepared[id] = definition
		progress.emit(prepared.size(), identities.size())
		# 主线程创建纹理，角色之间让出帧；退出后的旧加载不得发布结果。
		await tree.process_frame
		if generation != _generation: return {"ok": false, "error": "人物资源加载已取消", "cancelled": true}
	_definitions = prepared
	_bindings = bindings.duplicate(true)
	_preparing = false
	return {"ok": true, "error": ""}

func get_definition(identity_id: String) -> Dictionary:
	return _definitions.get(identity_id, {}).duplicate(true)

func clear() -> void:
	_generation += 1
	_preparing = false
	_definitions.clear()
	_bindings.clear()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
