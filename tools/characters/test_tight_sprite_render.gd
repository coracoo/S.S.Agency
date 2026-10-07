# 小图集证明引擎实际网格、固定锚点映射和直连纹理；只由隔离入口执行。
extends SceneTree
const World = preload("res://scripts/characters/pixel_character_world.gd")
const Player = preload("res://scripts/exploration_3d/player_controller.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
var failures := 0
var assertions := 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: print("FAIL: " + message); failures += 1
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	await _engine_probe()
	var helper_exists := ResourceLoader.exists("res://scripts/characters/tight_sprite_frame.gd")
	check(helper_exists, "存在只复用图集页的紧凑绘制视图")
	if helper_exists: await _mapping_checks()
	await _world_checks()
	await _battle_checks()
	_lantern_checks()
	print("TIGHT_SPRITE_RENDER: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
func _texture(rect: Rect2 = Rect2(2,3,4,5), at: Vector2 = Vector2(6,4)) -> AtlasTexture:
	var page := Image.create(32,16,false,Image.FORMAT_RGBA8)
	# 图集周围洋红哨兵，块内包含透明/半透明像素，不能按alpha阈值再裁切。
	page.fill(Color.MAGENTA)
	for y in int(rect.size.y):
		for x in int(rect.size.x):
			page.set_pixel(int(rect.position.x)+x,int(rect.position.y)+y,Color(float(x)/8,float(y)/8,.25,float((x+y)%4)/3))
	var source := AtlasTexture.new()
	source.atlas = ImageTexture.create_from_image(page)
	source.region = rect
	source.margin = Rect2(at, Vector2(20,12)-rect.size)
	source.filter_clip = true
	return source
func _engine_probe() -> void:
	var body := Sprite3D.new()
	body.texture = _texture()
	body.pixel_size = 1.0
	body.offset = Vector2(3,4)
	root.add_child(body)
	await process_frame
	await process_frame
	var bounds := body.get_aabb()
	print("ENGINE_ATLAS_AABB: ",bounds," logical=",body.get_item_rect())
	check(bounds.size.is_equal_approx(Vector3(4,5,0)), "Godot实际图集网格已经按region裁切，逻辑画布不是光栅面积")
	body.flip_h = true
	await process_frame
	await process_frame
	print("ENGINE_FLIPPED_ATLAS_AABB: ",body.get_aabb()," expected logical mirror x=[3,7]")
	check(body.get_aabb().is_equal_approx(bounds),"原Sprite3D仅翻UV，不翻图集边距；显式直连必须补偿")
	body.free()
func _mapping_checks() -> void:
	var helper = load("res://scripts/characters/tight_sprite_frame.gd").new()
	var pixel_size := .017
	var anchor := Vector2(7,10)
	for rect in [Rect2(2,3,4,5),Rect2(11,1,7,3),Rect2(1,1,1,1)]:
		for at in [Vector2.ZERO,Vector2(3,2),Vector2(20,12)-rect.size]:
			var source := _texture(rect,at)
			var before_margin := source.margin
			var texture: Texture2D = helper.texture_for(source)
			check(texture is AtlasTexture and texture.atlas == source.atlas and texture.region == source.region,"紧凑包装只复用原图集和region，不拷贝像素")
			check(texture.get_size() == rect.size and texture.margin == Rect2(),"包装无逻辑边距，网格只覆盖原region")
			check(texture.filter_clip and helper.texture_for(source) == texture,"同帧复用包装且保持filter_clip")
			check(source.margin == before_margin and source.get_size() == Vector2(20,12),"原动画纹理与逻辑尺寸不变")
			check(texture.get_image().get_data() == source.atlas.get_image().get_region(Rect2i(rect)).get_data(),"所有RGB与alpha字节逐像素相等，包含半透明边缘")
			for flipped in [false,true]:
				var offset: Vector2 = helper.offset_for(source,anchor,flipped)
				for y in int(rect.size.y):
					for x in int(rect.size.x):
						var point := Vector2(x+.5,y+.5)
						var logical: Vector2 = at+point
						var expected := Vector2((20-logical.x if flipped else logical.x)-anchor.x,anchor.y-logical.y)*pixel_size
						var local := Vector2((rect.size.x-point.x if flipped else point.x)-rect.size.x*.5+offset.x,rect.size.y*.5-point.y+offset.y)*pixel_size
						check(local.is_equal_approx(expected),"每像素正反向局部坐标等于原逻辑画布，固定密度/脚锚")
				var body := Sprite3D.new(); body.texture = texture; body.offset = offset; body.pixel_size = pixel_size; body.flip_h = flipped
				root.add_child(body)
				await process_frame
				await process_frame
				var actual := body.get_aabb()
				var left: float = (20-at.x-rect.size.x if flipped else at.x)-anchor.x
				check(actual.position.is_equal_approx(Vector3(left,anchor.y-at.y-rect.size.y,0)*pixel_size) and actual.size.is_equal_approx(Vector3(rect.size.x,rect.size.y,0)*pixel_size),"真实Sprite3D网格位置/大小等于原画布映射")
				body.free()
	var source := _texture()
	var weak: WeakRef = weakref(source.atlas)
	var wrapper: Texture2D = helper.texture_for(source)
	source = null; wrapper = null
	check(weak.get_ref() != null,"当前定义包装持有共享图集")
	helper.clear()
	check(weak.get_ref() == null,"清理演员缓存立即释放不再使用的页")
func _definition(layered: bool = false, packed: bool = true) -> Dictionary:
	var first := _texture()
	var second := _texture(Rect2(11,1,7,3),Vector2(2,1))
	var frames := SpriteFrames.new(); frames.remove_animation("default")
	var animations := {}
	for action in ["idle","walk","run","jump","interact","pickup","attack","item","down"]:
		frames.add_animation(action); frames.set_animation_speed(action,1.0); frames.set_animation_loop(action,action in ["idle","walk","run"])
		frames.add_frame(action,first,.07); frames.add_frame(action,second,.13)
		animations[action] = {"frames":["first","second"],"durations_ms":[70,130],"events":{"contact":80}}
	var manifest := {"identity_id":"fixture","form_id":"fixture","move_speed_mps":2.6,"canvas":{"w":20,"h":12,"anchor":[7,10],"content_height_px":8,"height_m":1.68},"anims":animations}
	if packed: manifest["packed_frames"] = {"first":{},"second":{}}
	var layers: Array = []
	if layered: layers.append({"spec":{"root_y":2,"full_motion_y":10,"amplitude_px":1,"period_s":3},"textures":[first,second]})
	return {"ok":true,"manifest":manifest,"frames":frames,"layer_frames":layers}
func _world_checks() -> void:
	var player := Player.new()
	player.shared_definition = _definition()
	root.add_child(player)
	player.set_physics_process(false)
	player.animator.sprite.pause()
	check(player.billboard.texture is AtlasTexture,"世界单层图集直接使用紧凑帧")
	check(player.composite.render_target_update_mode == SubViewport.UPDATE_DISABLED,"世界单层图集不再持续重画2D视口")
	if not player.billboard.texture is AtlasTexture:
		player.free(); return
	var density: float = player.billboard.pixel_size
	var root_point := player.position
	check(player.enable_scene_integration(),"直接帧仍支持既有灯光/接触阴影helper")
	var frames: SpriteFrames = player.animator.sprite.sprite_frames
	for action in frames.get_animation_names():
		player.animator.sprite.animation = action; player.animator.sprite.pause()
		for frame in frames.get_frame_count(action):
			player.animator.sprite.frame = frame
			for flipped in [false,true]:
				player.animator.sprite.flip_h = flipped
				player._process(0)
				var original: AtlasTexture = frames.get_frame_texture(action,frame)
				check(player.billboard.texture.atlas == original.atlas and player.billboard.texture.region == original.region,"每动作/每帧切换同步纹理")
				check(player.billboard.flip_h == flipped and player.billboard.pixel_size == density and player.position == root_point,"翻转不改变密度或世界根位置")
				check(player.billboard.material_override.get_shader_parameter("art_texture") == player.billboard.texture,"scene shader及时跟随新帧纹理")
				check(int(player.billboard.get_meta("logical_frame_texture_id")) == original.get_instance_id(),"外部量测只记录原帧整数ID，不持有额外纹理")
				var point := Vector2(4,6)
				var expected := Vector3((20-point.x if flipped else point.x)-7,10-point.y,0)*density
				check(player.scene_integration.canvas_point_to_world(point).is_equal_approx(expected),"接触点继续采用相同逻辑画布映射")
	player.animator.reset()
	var events: Array[StringName] = []
	player.animator.action_marker.connect(func(marker: StringName): events.append(marker))
	check(player.animator.request_action(&"interact"),"直接显示仍由原状态机启动交互")
	player.animator._process(.081)
	check(events == [&"contact"] and player.animator.is_action_locked(),"隐藏2D绘制不丢动作标记或提前解锁")
	player.animator.reset(); player.animator.sprite.pause()
	player.animator.self_modulate = Color(.2,.3,.4,.5)
	player.animator.sprite.modulate = Color(.7,.8,.9,.75)
	player._process(0)
	check(player.billboard.material_override.get_shader_parameter("appearance_tint") == player.animator.sprite.modulate,"同纹理染色同步shader，Node2D父级self_modulate不误乘给子精灵")
	check(player.billboard.alpha_cut==SpriteBase3D.ALPHA_CUT_DISCARD and is_equal_approx(player.billboard.alpha_scissor_threshold,.5) and player.billboard.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and not player.billboard.no_depth_test,"保留alpha cut、过滤和深度测试设置")
	var old_page: WeakRef = weakref(player.billboard.texture.atlas)
	frames = null
	check(player.apply_definition("layered",_definition(true)),"可替换到叠层定义")
	check(player.billboard.texture is ViewportTexture and player.animator.visible and not player.billboard.flip_h,"有动态头发层时保留2D合成，不能二次翻转")
	check(player.composite.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"叠层视口保持激活")
	check(player.billboard.material_override.get_shader_parameter("art_texture") == player.billboard.texture,"返回合成纹理时shader同步")
	check(old_page.get_ref() == null,"换领队/定义释放旧紧凑包装与图集")
	check(player.apply_definition("legacy",_definition(false,false)) and player.billboard.texture is ViewportTexture,"旧非图集定义仍保留合成路线")
	player.apply_definition("packed",_definition())
	player.hide(); player.show()
	check(player.composite.render_target_update_mode == SubViewport.UPDATE_DISABLED,"隐藏再显示不误启动直接路线的SubViewport")
	player.disable_scene_integration()
	check(player.billboard.material_override == null and player.billboard.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"关闭融合恢复既有材质和阴影开关")
	player.free()
func _battle_checks() -> void:
	var backdrop = load("res://scripts/rpg/ui/battle_world_backdrop.gd").new()
	root.add_child(backdrop)
	backdrop._world = Node3D.new(); backdrop.add_child(backdrop._world)
	backdrop.geometry = Node3D.new(); backdrop._world.add_child(backdrop.geometry)
	backdrop.camera = Camera3D.new(); backdrop._world.add_child(backdrop.camera)
	backdrop.camera.position = Vector3(0,5,10); backdrop.camera.look_at(Vector3.ZERO)
	backdrop.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var source = load("res://scripts/rpg/ui/hd_actor_view.gd").new()
	root.add_child(source)
	var definition := _definition()
	source.configure(definition,200,1)
	source.animator.sprite.pause()
	backdrop.bind_visuals({"actor":{"sprite":source}})
	var body: Sprite3D = backdrop.actor_entries.actor.body
	# 关闭内置billboard的扩展包围球，只量测提交给GPU的未旋转真实四顶点平面。
	body.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var frames: SpriteFrames = definition.frames
	for action in frames.get_animation_names():
		source.animator.sprite.animation = action; source.animator.sprite.pause()
		for frame in frames.get_frame_count(action):
			source.animator.sprite.frame = frame
			for flipped in [false,true]:
				source.set_facing(-1 if flipped else 1)
				source.animator.sprite.animation = action; source.animator.sprite.frame = frame; source.animator.sprite.pause()
				backdrop.sync_visuals()
				await process_frame
				await process_frame
				var texture: AtlasTexture = frames.get_frame_texture(action,frame)
				var anchor := Stature.body_anchor(definition)
				var x: float = anchor.x-texture.margin.position.x-texture.region.size.x if flipped else texture.margin.position.x-anchor.x
				var expected := AABB(Vector3(x,anchor.y-texture.margin.position.y-texture.region.size.y,0)*body.pixel_size,Vector3(texture.region.size.x,texture.region.size.y,0)*body.pixel_size)
				check(body.get_aabb().is_equal_approx(expected),"战斗实际镜像网格每帧都围绕固定脚锚，不翻错边距")
				check(body.texture.margin == Rect2() and body.texture.atlas == texture.atlas and body.texture.region == texture.region,"战斗包装保持原像素/完整region")
				check(body.material_override.get_shader_parameter("art_texture")==body.texture and body.flip_h==flipped,"战斗shader及UV翻转跟随同一紧凑帧")
				check(is_equal_approx(body.pixel_size,Stature.world_pixel_size(definition)),"战斗锚修正不改变世界身高")
	var old_page: WeakRef = weakref(body.texture.atlas)
	definition = {}; frames = null
	source.configure(_definition(),200,1); source.animator.sprite.pause(); backdrop.sync_visuals()
	check(old_page.get_ref()==null,"战斗换定义同步释放旧包装缓存")
	backdrop.clear_visuals()
	check(source.animator.visible,"退出战斗桥接恢复原2D显示")
	backdrop.free(); source.free()
func _lantern_checks() -> void:
	var geometry = load("res://scripts/campaign/act_one_geometry.gd").new()
	root.add_child(geometry)
	geometry._make_materials()
	geometry._stone_lantern(geometry,Vector3(0,0,0),true)
	geometry._stone_lantern(geometry,Vector3(8,0,0),false)
	var approach := Node3D.new(); approach.name = "ApproachArt"; geometry.add_child(approach)
	var model: Node3D = geometry.APPROACH.instantiate(); model.name = "OriginalApproach"; approach.add_child(model)
	var imported: MeshInstance3D = model.get_node("20_Lantern_Left_Stone")
	var imported_glow: MeshInstance3D = model.get_node("21_Lantern_Left_WashiGlow")
	var imported_material := imported.get_active_material(0)
	var glow_material := imported_glow.get_active_material(0)
	var lantern: Node3D = geometry.get_child(0)
	var cap: MeshInstance3D = lantern.get_node("Cap")
	var base: MeshInstance3D = lantern.get_node("Base")
	var original := cap.get_active_material(0)
	var original_base := base.get_active_material(0)
	var at := Vector3(0,0,-1)
	for index in 25: geometry.update_tree_occlusion(at,1.0/60.0)
	check(cap.get_active_material(0) == original,"默认世界石灯不参加战斗前景渐隐")
	check(geometry.has_method("enable_battle_prop_occlusion"),"石灯遮挡具有显式战斗开关")
	if not geometry.has_method("enable_battle_prop_occlusion"):
		geometry.free(); return
	geometry.enable_battle_prop_occlusion(); geometry.enable_battle_prop_occlusion()
	check(geometry._tree_occluders.size() == 3,"重复启用不重复登记石灯")
	var clear := Vector3(30,0,-1)
	var both: Array[Vector3] = [at,clear]
	geometry.update_tree_occlusion_many(both,1.0/60.0)
	check(is_equal_approx(cap.get_active_material(0).albedo_color.a,1.0-5.5/60.0),"被遮挡身体触发一次渐隐")
	for index in 25: geometry.update_tree_occlusion_many(both,1.0/60.0)
	check(cap.get_active_material(0).albedo_color.a<=.02,"前景灯顶不会挡住身体")
	check(base.get_active_material(0)==original_base,"石灯底座保持不透明接地")
	check(geometry.get_child(1).get_node("Cap").get_active_material(0)==original,"无关石灯保持原材质")
	check(lantern.position==Vector3.ZERO and cap.position==Vector3(0,1.44,0),"只改逐实例材质，原几何不动")
	var none: Array[Vector3] = []
	for index in 40: geometry.update_tree_occlusion_many(none,1.0/60.0)
	check(cap.get_active_material(0)==original,"所有身体离开后恢复原材质")
	for index in 25: geometry.update_tree_occlusion(Vector3(-6.25,0,-.5),1.0/60.0)
	check(imported.get_active_material(0)!=imported_material and imported.get_active_material(0).albedo_color.a<=.13,"截图实际左前景石灯被选择性淡化")
	check(imported_glow.get_active_material(0)!=glow_material and imported_glow.get_active_material(0).albedo_color.a<=.13,"同一灯笼发光纸面同步淡化，不遗留亮方块")
	check(imported.get_active_material(0).albedo_color.a>=.1,"合并石灯保留轻微实体轮廓，不移动或拆改网格")
	for index in 40: geometry.update_tree_occlusion_many(none,1.0/60.0)
	check(imported.get_active_material(0)==imported_material and imported_glow.get_active_material(0)==glow_material,"实际原灯石/发光材质可完整恢复")
	geometry.free()
