# 会话只强持有所选队员；焰华双形态预载供战内即时切换，仍是六身份同一角色。
class_name PartyAssetBundle
extends RefCounted
signal progress(completed: int, total: int)
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const MANIFESTS := {
	"rinne": "res://assets/chars/pixel/rinne/high_detail_complete/manifest.json",
	"mint": "res://assets/chars/pixel/mint/high_detail_complete/manifest.json",
	"guard": "res://assets/chars/pixel/guard/high_detail_complete/manifest.json",
	"homura_mage": "res://assets/chars/pixel/homura_mage/high_detail_complete/manifest.json",
	"homura_sword": "res://assets/chars/pixel/homura_sword/high_detail_complete/manifest.json",
	"healer": "res://assets/chars/pixel/healer/high_detail_complete/manifest.json",
	"controller": "res://assets/chars/pixel/controller/high_detail_complete/manifest.json"
}
const FORMS := {"rinne": ["rinne"], "mint": ["mint"], "guard": ["guard"], "homura": ["mage", "sword"], "healer": ["healer"], "controller": ["controller"]}
var _definitions: Dictionary = {}
var _bindings: Dictionary = {}
var _generation := 0
var _preparing := false

static func canonical_form(identity_id: String, form_id: String) -> String:
	if identity_id == "homura": return form_id.trim_prefix("homura_")
	return form_id
static func asset_key(identity_id: String, form_id: String = "") -> String:
	if identity_id in ["homura_mage", "homura_sword"] and form_id.is_empty(): return identity_id
	var form := canonical_form(identity_id, form_id if not form_id.is_empty() else ("mage" if identity_id == "homura" else identity_id))
	if not FORMS.has(identity_id) or not FORMS[identity_id].has(form): return ""
	return "homura_" + form if identity_id == "homura" else identity_id

func prepare(bindings: Dictionary) -> Dictionary:
	if _preparing: return _failure("人物资源正在加载")
	if bindings.is_empty() or bindings.size() > 3: return _failure("当前队伍须有一至三名人物绑定")
	var identities: Array[String] = []
	var keys: Array[String] = []
	var normalized: Dictionary = {}
	for actor_id in bindings:
		if not actor_id is String or not bindings[actor_id] is Dictionary: return _failure("人物绑定格式错误")
		var binding: Dictionary = bindings[actor_id]
		if binding.size() != 2 or not binding.get("identity_id") is String or not binding.get("form_id") is String: return _failure("人物绑定必须声明身份和形态")
		var identity: String = binding.identity_id
		var form := canonical_form(identity, binding.form_id)
		if not FORMS.has(identity) or not FORMS[identity].has(form): return _failure("人物身份或形态不在正式六身份清单")
		var key := asset_key(identity, form)
		if key.is_empty(): return _failure("人物或形态不在正式高清清单")
		if identities.has(identity): return _failure("同一身份不能重复出战")
		identities.append(identity)
		if not keys.has(key): keys.append(key)
		if identity == "homura":
			for other_form in FORMS.homura:
				var other_key := asset_key(identity, other_form)
				if not keys.has(other_key): keys.append(other_key)
		normalized[actor_id] = {"identity_id": identity, "form_id": form}
	if _bindings == normalized and not _definitions.is_empty(): return {"ok": true, "error": ""}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return _failure("人物加载需要场景树")
	_generation += 1
	var generation := _generation
	_preparing = true
	var prepared: Dictionary = {}
	for key in keys:
		var definition: Dictionary = _definitions.get(key, {})
		if definition.is_empty(): definition = Definition.load_definition(MANIFESTS[key])
		if not definition.get("ok", false):
			_preparing = false
			return _failure("%s高清资源加载失败：%s" % [key, "；".join(definition.get("errors", []))])
		var manifest: Dictionary = definition.manifest
		if asset_key(str(manifest.get("identity_id", "")), str(manifest.get("form_id", ""))) != key:
			_preparing = false
			return _failure("高清清单身份或形态不符：" + key)
		prepared[key] = definition
		progress.emit(prepared.size(), keys.size())
		# 主线程创建纹理，每个形态让出帧；clear后的旧加载不改变新加载状态。
		await tree.process_frame
		if generation != _generation: return {"ok": false, "error": "人物资源加载已取消", "cancelled": true}
	_definitions = prepared
	_bindings = normalized
	_preparing = false
	return {"ok": true, "error": ""}

func get_definition(identity_id: String, form_id: String = "") -> Dictionary:
	if form_id.is_empty():
		for binding in _bindings.values():
			if binding.identity_id == identity_id:
				form_id = binding.form_id
				break
	return _definitions.get(asset_key(identity_id, form_id), {}).duplicate(true)
func clear() -> void:
	_generation += 1
	_preparing = false
	_definitions.clear()
	_bindings.clear()
func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
