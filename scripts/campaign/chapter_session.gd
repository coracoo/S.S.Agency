# A durable formal run owns one router and one selected-party asset lifetime.
class_name CampaignChapterSession
extends RefCounted
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
static var current: RefCounted = null
var campaign: RefCounted
var router: RefCounted
var bundle: RefCounted = Bundle.new()
var generation := 0
var asset_generation := 0

func _init(model: RefCounted = null) -> void:
	campaign = model if model != null else Campaign.new(null, null, Chapters.SAVE_PATH)
	router = Router.new(campaign)

func start_new(replace_confirmed: bool, class_ids: Array[String] = Chapters.DEFAULT_CLASSES) -> Dictionary:
	if FileAccess.file_exists(Chapters.SAVE_PATH):
		var existing: Dictionary = Store.new().load_safe(Chapters.SAVE_PATH)
		if not existing.ok: return _failure("原正式存档无法覆盖：" + existing.error)
		if not replace_confirmed:
			var result := _failure("已有正式进度，请确认替换")
			result["needs_confirmation"] = true
			return result
	var result: Dictionary = campaign.new_run(class_ids, 5, {"id": Chapters.PROFILE_ID, "bindings": Chapters.BINDINGS.duplicate(true), "world": Chapters.initial_world(1)})
	if not result.ok: return _wrap(result)
	router = Router.new(campaign)
	_activate()
	result["next_scene"] = Chapters.scene_path(1)
	return _wrap(result)

func resume() -> Dictionary:
	var result: Dictionary = router.load_safe_run()
	if not result.ok: return _wrap(result)
	if campaign.safe_snapshot().get("schema_version") != 2: return _failure("该槽不是正式五夜档")
	_activate()
	return _wrap(result)

func save_world(world: Dictionary) -> Dictionary:
	if current != self: return _failure("正式会话已关闭或已被替换")
	return _wrap(campaign.save_exploration(world))

func commit_event(world: Dictionary, event_id: String) -> Dictionary:
	if current != self: return _failure("正式会话已关闭或已被替换")
	return _wrap(campaign.commit_chapter_event(world, event_id))

func begin_encounter(world: Dictionary, clue_id: String) -> Dictionary:
	if current != self: return _failure("正式会话已关闭或已被替换")
	if not Chapters.validate_world(world).is_empty(): return _failure("正式遭遇世界非法")
	return _wrap(router.begin(world.scene_path, "res://scenes/rpg/battle.tscn", world, clue_id))

func advance_night(world: Dictionary) -> Dictionary:
	if current != self: return _failure("正式会话已关闭或已被替换")
	var result: Dictionary = campaign.advance_chapter(world)
	if result.ok: result["next_scene"] = campaign.safe_snapshot().world.scene_path
	return _wrap(result)

func choose_resolution(world: Dictionary, resolution: String) -> Dictionary:
	if current != self: return _failure("正式会话已关闭或已被替换")
	return _wrap(campaign.choose_resolution(world, resolution))

func finish_ending(world: Dictionary) -> Dictionary:
	if current != self: return _failure("正式会话已关闭或已被替换")
	var result: Dictionary = campaign.finish_ending(world)
	if result.ok: result["next_scene"] = Chapters.ENDING_PATH
	return _wrap(result)

func prepare_assets(context: String = "", entering_scene: bool = false) -> Dictionary:
	if current != self: return _failure("正式人物资源加载会话已失效")
	if bundle != null and bundle.is_preparing(): return _failure("人物资源正在加载")
	asset_generation += 1
	var request_asset_generation := asset_generation
	var request_generation := generation
	var safe: Dictionary = campaign.safe_snapshot()
	if context.is_empty(): context = "battle" if not safe.get("pending_battle", {}).is_empty() else "world"
	var bindings := {}
	for id in safe.party:
		bindings[id] = {"identity_id": safe.roster[id].identity_id, "form_id": safe.roster[id].form_id}
	if bundle == null: bundle = Bundle.new()
	var requested_bundle: RefCounted = bundle
	if entering_scene: requested_bundle.release_other_context(context)
	var result: Dictionary = await requested_bundle.prepare(bindings, context)
	var latest: Dictionary = campaign.safe_snapshot()
	var latest_bindings := {}
	for id in latest.get("party", []): latest_bindings[id] = {"identity_id": latest.roster[id].identity_id, "form_id": latest.roster[id].form_id}
	if asset_generation != request_asset_generation:
		return {"ok": false, "error": "正式人物资源加载已取消", "world": _world(), "cancelled": true}
	if generation != request_generation or current != self or bundle != requested_bundle or latest_bindings != bindings:
		if bundle == requested_bundle: requested_bundle.clear()
		return {"ok": false, "error": "正式人物资源加载已取消", "world": _world(), "cancelled": true}
	return _wrap(result)

# 场景只取消自己发起的加载；迟到的旧场景退出不能清空新请求。
func cancel_asset_preparation(request: int = -1) -> void:
	if request >= 0 and request != asset_generation: return
	asset_generation += 1
	if bundle != null: bundle.cancel_prepare()

func close() -> void:
	generation += 1
	asset_generation += 1
	if bundle != null:
		bundle.clear()
		bundle = null
	if current == self:
		current = null
		if Router.session == router: Router.clear_session()

func _activate() -> void:
	if current != null and current != self: current.close()
	current = self
	Router.activate(router)

func _world() -> Dictionary:
	return campaign.safe_snapshot().get("world", {}).duplicate(true)

func _wrap(result: Dictionary) -> Dictionary:
	var wrapped := result.duplicate(true)
	wrapped["world"] = _world()
	return wrapped

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "world": _world()}
