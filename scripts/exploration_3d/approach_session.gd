# 试玩跨探索和战斗强持有一次会话；只有返回标题才关闭。
class_name ApproachSession
extends RefCounted
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
const Profile = preload("res://scripts/exploration_3d/trial_profile.gd")
const World = preload("res://scripts/exploration_3d/world_snapshot.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
static var current: RefCounted = null
var campaign: RefCounted
var router: RefCounted
var bundle: RefCounted = Bundle.new()
var _store: RefCounted
var _path: String
var generation := 0
func _init(store: RefCounted = null, path: String = Profile.SAVE_PATH) -> void:
	_store = store if store != null else Store.new()
	_path = path
	campaign = Campaign.new(null, _store, path)
	router = Router.new(campaign)
func start_new(replace_confirmed: bool) -> Dictionary:
	if FileAccess.file_exists(_path):
		var existing: Dictionary = _store.load_safe(_path)
		if not existing.ok: return _failure("原试玩存档无法覆盖：" + existing.error)
		if existing.snapshot.get("run_profile", {}).get("id") != Profile.ID: return _failure("该槽不是参道试玩档，保持原样")
		if not replace_confirmed: return {"ok": false, "error": "已有试玩进度，请确认替换", "needs_confirmation": true}
	var result: Dictionary = campaign.new_run(Profile.CLASS_IDS, 5, Profile.make(World.initial({})))
	if not result.ok: return result
	# 新局提交完成后才替换路由，不能把上一局返场快照带入。
	router = Router.new(campaign)
	_activate()
	result["next_scene"] = World.SCENE_PATH
	return result
func resume() -> Dictionary:
	var saved: Dictionary = _store.load_safe(_path)
	if not saved.ok: return saved
	if saved.snapshot.get("run_profile", {}).get("id") != Profile.ID: return _failure("该槽不是参道试玩档")
	var result: Dictionary = router.load_safe_run()
	if result.ok: _activate()
	return result
func save_world(world: Dictionary) -> Dictionary:
	return campaign.save_exploration(world)
func begin_encounter(world: Dictionary) -> Dictionary:
	if current != self: return _failure("试玩会话已失效")
	return router.begin(World.SCENE_PATH, "res://scenes/rpg/battle.tscn", world, "basin_reflection")
func commit_event(world: Dictionary, event_id: String) -> Dictionary:
	if current != self: return _failure("试玩会话已失效")
	return campaign.commit_world_event(world, event_id)
func prepare_assets() -> Dictionary:
	if current != self: return _failure("试玩会话已关闭或已被替换")
	var request_generation := generation
	if bundle == null: bundle = Bundle.new()
	var requested_bundle: RefCounted = bundle
	var result: Dictionary = await requested_bundle.prepare(Profile.BINDINGS)
	if generation != request_generation or current != self or bundle != requested_bundle:
		return {"ok": false, "error": "试玩资源加载已取消", "cancelled": true}
	return result
func close() -> void:
	generation += 1
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
func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
