# 小图集验证分组加载、原时序脚锚和强引用释放；仅由隔离Python入口执行。
extends SceneTree
var Definition: Variant = load("res://scripts/characters/pixel_character_definition.gd")
var Bundle: Variant = load("res://scripts/characters/party_asset_bundle.gd")
const WORLD := ["idle", "walk", "run", "jump", "interact", "pickup"]
const BATTLE := ["idle", "attack", "item", "down", "hit", "defend", "recover"]
var failures := 0
var assertions := 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	print(("PASS: " if value else "FAIL: ") + message)
	if not value: failures += 1
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	var supports_context := false
	for method in Definition.get_script_method_list():
		if method.name == "load_definition": supports_context = method.args.size() == 2
	check(supports_context, "定义加载器支持显式上下文，默认仍完整验证")
	if not supports_context: _finish(); return
	var manifest := _fixture("rinne", "rinne")
	var path := _write(manifest, "rinne")
	var full: Dictionary = Definition.call("load_definition", path)
	check(full.ok and full.frames.get_animation_names().size() == 12, "完整模式保留全部12个动作")
	full.clear()
	var inactive := manifest.duplicate(true)
	inactive.packed_frames.attack.atlas = "user://must_not_open_missing.png"
	var world: Dictionary = Definition.call("load_definition", _write(inactive, "inactive"), "world")
	check(world.ok and not world.frames.has_animation("attack"), "世界模式不打开战斗专用缺失PNG")
	check(not Definition.call("load_definition", _write(inactive, "inactive"), "battle").ok, "战斗模式严格拒绝自己的缺失图集")
	check(not Definition.call("load_definition", _write(inactive, "inactive")).ok, "默认完整验证不会掩盖未加载动作缺失")
	var battle_only := manifest.duplicate(true)
	battle_only.packed_frames.walk.atlas = "user://must_not_open_missing.png"
	var battle: Dictionary = Definition.call("load_definition", _write(battle_only, "battle_only"), "battle")
	check(battle.ok and not battle.frames.has_animation("walk"), "战斗模式不打开世界专用缺失PNG")
	for pair in [[world, WORLD], [battle, BATTLE]]:
		var loaded: Dictionary = pair[0]
		check(loaded.frames.get_animation_names().size() == pair[1].size(), "只装配所需动作集合")
		check(loaded.manifest.canvas == JSON.parse_string(JSON.stringify(manifest)).canvas and loaded.manifest.anims == JSON.parse_string(JSON.stringify(manifest)).anims and loaded.manifest.identity_id == manifest.identity_id, "保留身份、脚锚、逐帧时序与标记元数据")
		for action in pair[1]:
			check(loaded.frames.get_frame_count(action) == 2 and is_equal_approx(loaded.frames.get_frame_duration(action, 1) / loaded.frames.get_animation_speed(action), .13), "保留两帧与130ms节奏：" + action)
	var invalid := manifest.duplicate(true)
	invalid.packed_frames.jump.region = [0, 0, 9, 8]
	check(not Definition.call("load_definition", _write(invalid, "invalid"), "world").ok, "所选动作继续严格校验图集边界")
	check(not Definition.call("load_definition", path, "unknown").ok, "拒绝未知上下文")
	var idle_ref: WeakRef = weakref(world.frames.get_frame_texture("idle", 0).atlas)
	var world_ref: WeakRef = weakref(world.frames.get_frame_texture("walk", 0).atlas)
	var battle_ref: WeakRef = weakref(battle.frames.get_frame_texture("attack", 0).atlas)
	check(world.frames.get_frame_texture("idle", 0).atlas == battle.frames.get_frame_texture("idle", 0).atlas, "两上下文只弱共享相同idle纹理")
	world.clear()
	check(world_ref.get_ref() == null and idle_ref.get_ref() != null, "释放世界定义立即释放世界专用页，保留战斗idle")
	battle.clear()
	check(idle_ref.get_ref() == null and battle_ref.get_ref() == null, "最后定义释放后弱缓存不常驻idle或战斗页")
	await _bundle_checks()
	await _player_replacement_checks()
	_finish()
func _finish() -> void:
	print("TEXTURE_CONTEXTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
func _fixture(identity: String, form: String) -> Dictionary:
	var manifest := {"identity_id":identity, "form_id":form, "move_speed_mps":2.6, "canvas":{"w":8,"h":8,"anchor":[4,7],"content_height_px":6,"height_m":1.68}, "packed_frames":{}, "anims":{}}
	var actions := WORLD.duplicate()
	for action in BATTLE:
		if not actions.has(action): actions.append(action)
	for index in actions.size():
		var action: String = actions[index]
		var page := Image.create(8,8,false,Image.FORMAT_RGBA8)
		page.fill(Color(float(index+1)/16.0,float(identity.hash()%100)/100.0,.5))
		var path := "user://%s_%s.png" % [identity,action]
		page.save_png(path)
		manifest.packed_frames[action] = {"atlas":path,"atlas_size":[8,8],"region":[0,0,8,8],"offset":[0,0]}
		manifest.anims[action] = {"frames":[action,action],"durations_ms":[70,130],"loop":action in ["idle","walk","run"],"events":{"contact":80}}
	manifest.anims.attack["impact_ms"] = 80
	return manifest
func _write(manifest: Dictionary, name: String) -> String:
	var path := "user://" + name + ".json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest)); file.close()
	return path
func _prepare(bundle: RefCounted, bindings: Dictionary, context: String, output: Dictionary) -> void:
	output.result = await bundle.call("prepare",bindings,context)
	output.done = true
func _bundle_checks() -> void:
	var paths := {}
	for identity in Bundle.FORMS:
		for form in Bundle.FORMS[identity]:
			var key: String = Bundle.asset_key(identity,form)
			paths[key] = _write(_fixture(identity,form),key)
	var bundle = Bundle.new(paths)
	var first := {"p_swordsman":{"identity_id":"rinne","form_id":"rinne"}}
	check((await bundle.call("prepare",first,"world")).ok,"夹具世界编队就绪")
	var definition: Dictionary = bundle.get_definition("rinne")
	var old_page: WeakRef = weakref(definition.frames.get_frame_texture("walk",0).atlas)
	definition.clear()
	check((await bundle.call("prepare",first,"battle")).ok,"同编队切换battle仍重新装配上下文")
	check(old_page.get_ref() == null,"阶段提交释放上一阶段strong refs")
	check(bundle.get_definition("rinne").frames.has_animation("item") and not bundle.get_definition("rinne").frames.has_animation("run"),"战斗预热包含道具，不含跑步")
	var homura := {"p_mage":{"identity_id":"homura","form_id":"mage"}}
	for index in 3:
		check((await bundle.call("prepare",homura,"battle")).ok and bundle._definitions.size() == 2,"仅焰华双形态常驻，可即时切换")
		homura.p_mage.form_id = "sword" if homura.p_mage.form_id == "mage" else "mage"
		check((await bundle.call("prepare",first,"world")).ok and bundle._definitions.size() == 1,"反复换队和返场不积累旧形态")
	var before = bundle.get_definition("rinne").frames
	var broken: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(paths.rinne))
	broken.packed_frames.attack.atlas = "user://missing.png"
	_write(broken,"rinne")
	check(not (await bundle.call("prepare",first,"battle")).ok and bundle.get_definition("rinne").frames == before,"失败预热不安装部分定义或破坏安全旧阶段")
	before = null
	_write(_fixture("rinne","rinne"),"rinne")
	var outcome := {"done":false,"result":{}}
	_prepare(bundle,first,"battle",outcome)
	bundle.clear()
	check((await bundle.call("prepare",homura,"world")).ok,"取消后可开始新阶段请求")
	await process_frame
	check(outcome.done and outcome.result.get("cancelled",false) and bundle._definitions.size() == 2 and bundle.get_definition("rinne").is_empty(),"旧取消协程不得覆盖新阶段资源")
	var held: Dictionary = bundle.get_definition("homura","mage")
	var held_ref: WeakRef = weakref(held.frames.get_frame_texture("walk",0).atlas)
	bundle.clear()
	check(held_ref.get_ref() != null,"演员持有副本时仍保留其纹理")
	held.clear()
	check(held_ref.get_ref() == null,"演员与bundle同时释放后纹理确实过期")

func _player_replacement_checks() -> void:
	var Player: Variant = load("res://scripts/exploration_3d/player_controller.gd")
	var first: Dictionary = Definition.call("load_definition", _write(_fixture("healer", "healer"), "lead_healer"), "world")
	var player: CharacterBody3D = Player.new()
	player.shared_definition = first
	root.add_child(player)
	check(player.form_id == "healer" and player.animator.definition.manifest.identity_id == "healer", "初始化直接采用所选领队身份，没有默认凛音")
	var prior: WeakRef = weakref(first.frames.get_frame_texture("walk", 0).atlas)
	first = {}
	var second: Dictionary = Definition.call("load_definition", _write(_fixture("guard", "guard"), "lead_guard"), "world")
	check(player.apply_definition("guard", second), "Tab/形态替换走真实人物控制器")
	check(player.shared_definition.manifest.identity_id == "guard", "切换领队同步更新共享定义而非保留最初人物")
	check(prior.get_ref() == null, "领队替换释放旧定义最后strong ref")
	player.free()
