# 独立战斗镜头复用正式寺域几何。只桥接现有动作帧与脚点，不保存或结算战斗状态。
extends Control
signal visuals_synchronized
const MeleeMotion = preload("res://scripts/rpg/ui/melee_motion.gd")
const Attachments = preload("res://scripts/characters/action_attachment_points.gd")
const MeleeContacts = preload("res://scripts/characters/melee_contact_points.gd")
const SagaWorld = preload("res://scripts/campaign/saga_world.gd")
const Geometry = preload("res://scripts/campaign/act_one_geometry.gd")
const Layout = preload("res://scripts/campaign/act_one_layout.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
const TightFrame = preload("res://scripts/characters/tight_sprite_frame.gd")
const PartyFraming = preload("res://scripts/rpg/ui/battle_party_framing.gd")
const SnapshotTrail = preload("res://scripts/characters/snapshot_ghost_trail.gd")
const ActorLight = preload("res://scripts/characters/illustration_scene_light.gdshader")
const Contact = preload("res://scripts/characters/ground_contact_shadow.gdshader")
const Depth = preload("res://scripts/campaign/presentation/act_one_depth.gd")
const STAGES := {
	"approach": Vector3(-4.5, .03, .45),
	"forecourt": Vector3(15.5, 2.89, .2),
	"corridor": Vector3(25.0, 2.89, -6.6),
	"procession": Vector3(43.0, 2.89, 4.0),
	"mirror": Vector3(43.0, 2.89, -12.7),
	"honden": Vector3(61.0, 2.89, -4.8),
	"central_court": Vector3(34.8, 2.89, -4.8),
	"north_walk": Vector3(35.8, 2.89, -11.8),
	"south_walk": Vector3(33.0, 2.89, 4.0),
}
var viewport: SubViewport
var geometry: Node3D
var camera: Camera3D
var scene_region := ""
var stage_origin := Vector3.ZERO
var actor_entries: Dictionary = {}
var _world: Node3D

func configure(world: Dictionary, depth_enabled: bool = true) -> void:
	if viewport != null: return
	name = "BattleWorldBackdrop"
	size = Vector2(1920,1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var position_data: Array = world.get("position", [-4.5,.03,.45])
	var source := Vector3(position_data[0],position_data[1],position_data[2])
	scene_region = Layout.region_at(source)
	if not STAGES.has(scene_region): scene_region = "approach"
	stage_origin = STAGES[scene_region]
	var saga_chapter: int = int(world.get("night", 1)) - 4 if world.get("map_layout") == "saga_regions_v1" else 0
	if saga_chapter >= 2:
		scene_region = "chapter_%d" % saga_chapter
		var anchor: Array = SagaWorld.anchors(saga_chapter).get("battle", SagaWorld.anchors(saga_chapter).spawn)
		stage_origin = Vector3(anchor[0], anchor[1], anchor[2])
	set_meta("source_position",source)
	set_meta("source_region",scene_region)
	viewport = SubViewport.new()
	viewport.name = "BattleWorldViewport"
	viewport.size = Vector2i(1920,1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var display := TextureRect.new()
	display.size = size
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.texture = viewport.get_texture()
	add_child(display)
	_world = Node3D.new()
	viewport.add_child(_world)
	geometry = SagaWorld.build(saga_chapter) if saga_chapter >= 2 else Geometry.build({})
	_world.add_child(geometry)
	if geometry.has_method("enable_battle_prop_occlusion"): geometry.enable_battle_prop_occlusion()
	# 当前地图的碰撞由探索舞台持有；战斗舞台没有角色控制器或额外剧情实例。
	var collision := geometry.get_node_or_null("PermanentCollision")
	if collision != null: collision.free()
	camera = Camera3D.new()
	_world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.far = 100.0
	var offset := Vector3(0,4.8 if scene_region == "forecourt" else 6.2,11.0)
	var focus := stage_origin + Vector3(0,.9,0)
	camera.position = focus + offset
	camera.look_at(focus)
	# 固定Y薄片保留原物理身高；正交镜头按既有190px/m校准投影高度。
	camera.size = 1080.0 / Stature.battle_pixels_per_metre() * cos(atan2(offset.y,offset.z))
	if geometry.has_method("update_visibility"): geometry.update_visibility(stage_origin,1.0,camera)
	var depth := Depth.new()
	depth.name = "BattleDepth"
	add_child(depth)
	depth.configure(camera)
	depth.follow(stage_origin)
	depth.set_enabled(depth_enabled)

func bind_visuals(actors: Dictionary) -> void:
	clear_visuals()
	for actor_id in actors:
		var source: Node2D = actors[actor_id].get("sprite")
		if source == null: continue
		var animated := source.get("animator") as Node2D
		var visual: Node2D = animated if animated != null else source.get("visual") as Node2D
		if visual == null: continue
		var body := Sprite3D.new()
		body.name = "BattleActor_" + str(actor_id)
		body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		var material := ShaderMaterial.new()
		material.shader = ActorLight
		body.material_override = material
		_world.add_child(body)
		var shadow := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(.48,.25)
		shadow.mesh = plane
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow_material := ShaderMaterial.new()
		shadow_material.shader = Contact
		shadow_material.set_shader_parameter("opacity",.62)
		shadow.material_override = shadow_material
		_world.add_child(shadow)
		var trail := SnapshotTrail.new()
		_world.add_child(trail)
		trail.bind_actor(str(actor_id))
		var moved := _on_presentation_position_changed.bind(str(actor_id))
		actor_entries[actor_id] = {"actor_id":str(actor_id),"source":source,"visual":visual,"animated":animated != null,"body":body,"shadow":shadow,"original_visible":visual.visible,"tight_frames":TightFrame.new(),"frame_set_id":0,"trail":trail,"ghost_elapsed":0.0,"position_callback":moved}
		if source.has_signal("presentation_position_changed"): source.connect("presentation_position_changed",moved)
		# AnimatedSprite在父级_process之后换帧；直接订阅帧/动画切换，真实3D材质不迟一帧。
		if animated != null:
			animated.sprite.frame_changed.connect(moved)
			animated.sprite.animation_changed.connect(moved)
		visual.hide()
		if is_instance_valid(actors[actor_id].get("shadow")): actors[actor_id].shadow.hide()
	sync_visuals(0.0)

func _on_presentation_position_changed(actor_id: String) -> void:
	if not actor_entries.has(actor_id): return
	var record: Dictionary = actor_entries[actor_id]
	# configure先切SpriteFrames、再提交完整definition；中间信号不能混用旧锚与新页。
	if record.animated and record.source._definition.get("frames") != record.visual.sprite.sprite_frames: return
	# 人物子节点在父_process之后位移/换帧；回调立即更新真实3D，不推进时钟。
	sync_visuals(0.0)

func sync_visuals(delta: float = 1.0/60.0) -> void:
	var positions:Array[Vector3]=[]
	for record in actor_entries.values():
		if not is_instance_valid(record.source): continue
		var body: Sprite3D = record.body
		var source: Node2D = record.source
		var visual: Node2D = record.visual
		var texture: Texture2D
		var logical_texture: Texture2D
		var effective_anchor := Vector2.ZERO
		var tint := source.modulate * visual.modulate
		var foot: Vector2 = source.position
		if record.animated:
			var sprite: AnimatedSprite2D = visual.sprite
			if sprite.sprite_frames == null: continue
			texture = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
			logical_texture = texture
			var definition: Dictionary = source._definition
			var canvas: Dictionary = definition.manifest.canvas
			var anchor := Stature.body_anchor(definition)
			if sprite.flip_h: anchor.x = float(canvas.w) - anchor.x
			effective_anchor = anchor
			if record.frame_set_id != sprite.sprite_frames.get_instance_id():
				record.tight_frames.clear()
				record.trail.cancel()
				record.ghost_elapsed = 0.0
				record.frame_set_id = sprite.sprite_frames.get_instance_id()
				if source.has_method("configure_melee_bounds"):
					source.configure_melee_bounds(melee_foot_bounds(record.actor_id),float(source.get_meta("melee_body_radius_px",45.0)))
			# Sprite3D仅翻UV、不翻AtlasTexture边距；显式紧凑片补偿才能镜像固定脚锚。
			# 此处修正锚点，不把引擎本已裁切的图集网格宣称为过绘制优化。
			body.offset = TightFrame.offset_for(texture,anchor,sprite.flip_h)
			body.set_meta("logical_frame_texture_id",texture.get_instance_id())
			body.set_meta("rendered_action",str(sprite.animation));body.set_meta("rendered_action_frame",sprite.frame)
			body.set_meta("logical_frame_rect",TightFrame.logical_rect(texture))
			body.set_meta("logical_canvas_size",texture.get_size())
			texture = record.tight_frames.texture_for(texture)
			body.pixel_size = Stature.world_pixel_size(definition)
			body.flip_h = sprite.flip_h
			tint *= sprite.modulate
		else:
			var sprite := visual.get_child(0) as Sprite2D
			if sprite == null: continue
			texture = sprite.texture
			body.offset = Vector2(sprite.offset.x,-sprite.offset.y)
			body.pixel_size = sprite.scale.y / Stature.battle_pixels_per_metre()
			body.flip_h = sprite.flip_h
			foot += visual.position
			tint *= sprite.modulate
		body.texture = texture
		body.material_override.set_shader_parameter("art_texture",texture)
		body.material_override.set_shader_parameter("appearance_tint",tint)
		body.position = _ground_point(foot)
		if record.animated:
			# 帧资源可被重绑复用；资格随当前definition检查，页面原字节校验在profile内缓存。
			var contact:Dictionary=MeleeContacts.resolve(source._definition)
			var reach:=-1.0
			if not contact.is_empty():
				var offset:Vector2=contact.logical_point-Stature.body_anchor(source._definition)
				if body.flip_h:offset.x=-offset.x
				var right:=Vector3(camera.global_basis.x.x,0,camera.global_basis.x.z).normalized()
				var point:=camera.unproject_position(body.global_position+(right*offset.x-Vector3.UP*offset.y)*body.pixel_size)
				reach=absf(point.x-camera.unproject_position(body.global_position).x)
				source.set_meta("melee_contact_profile",contact.profile)
			elif source.has_meta("melee_contact_profile"):source.remove_meta("melee_contact_profile")
			if source.has_method("configure_melee_contact_reach"):source.configure_melee_contact_reach(reach)
		record.shadow.position = body.position + Vector3(0,.014,0)
		body.visible = source.visible
		record.shadow.visible = source.visible
		_sync_trail(record,logical_texture,effective_anchor,tint,delta)
		if source.visible: positions.append(body.position)
	if geometry.has_method("update_tree_occlusion_many"): geometry.update_tree_occlusion_many(positions,delta,camera)
	visuals_synchronized.emit()

func _ground_point(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	return origin + direction * ((stage_origin.y-origin.y)/direction.y)

# 正交镜头中先量测完整动作相对脚点的投影，再反推可用脚域；不逐帧缩放角色。
func melee_foot_bounds(actor_id: String) -> Rect2:
	if not actor_entries.has(actor_id): return Rect2()
	var record: Dictionary = actor_entries[actor_id]
	if not record.animated: return Rect2()
	var source: Node2D = record.source
	var home := source.position
	var ground := _ground_point(home)
	var bounds := PartyFraming.projected_bounds(camera,ground,source._definition,false)
	bounds = bounds.merge(PartyFraming.projected_bounds(camera,ground,source._definition,true))
	var low := Vector2(16,154) - (bounds.position-home)
	var high := Vector2(1904,744) - (bounds.end-home)
	var allowed := Rect2(low,high-low)
	var fits := allowed.has_area() and allowed.has_point(home)
	source.set_meta("melee_home_outside_safe_bounds",not fits)
	# 若原站位本身已越界，保留原地并报告门禁，不能靠放宽边界掩盖裁图。
	return allowed if fits else Rect2(home-Vector2.ONE*.001,Vector2.ONE*.002)

func actor_screen_bounds(actor_id: String) -> Rect2:
	if not actor_entries.has(actor_id): return Rect2()
	var body: Sprite3D = actor_entries[actor_id].body
	if body.texture == null: return Rect2()
	var half := body.texture.get_size()*.5
	var right := Vector3(camera.global_basis.x.x,0,camera.global_basis.x.z).normalized()
	var result := Rect2()
	var first := true
	for x in [-half.x,half.x]:
		for y in [-half.y,half.y]:
			var world: Vector3 = body.global_position+(right*(body.offset.x+x)+Vector3.UP*(body.offset.y+y))*body.pixel_size
			var point := camera.unproject_position(world)
			result = Rect2(point,Vector2.ZERO) if first else result.expand(point)
			first = false
	return result

func actor_effect_center(actor_id: String) -> Vector2:
	if not actor_entries.has(actor_id): return Vector2.ZERO
	var record: Dictionary = actor_entries[actor_id]
	var height := float(record.source.get_meta("content_height",300.0)) / Stature.battle_pixels_per_metre()
	return camera.unproject_position(record.body.global_position+Vector3.UP*height*.48)

func actor_action_attachment(actor_id: String) -> Dictionary:
	if not actor_entries.has(actor_id): return {"ok":false,"reason":"missing_actor"}
	var record: Dictionary = actor_entries[actor_id]
	if not record.animated: return {"ok":false,"reason":"unregistered_static_actor"}
	var body: Sprite3D = record.body
	var result := Attachments.resolve(record.source._definition,str(body.get_meta("rendered_action","")),int(body.get_meta("rendered_action_frame",-1)))
	if not result.ok: return result
	var anchor := Stature.body_anchor(record.source._definition)
	var offset: Vector2 = result.logical_point-anchor
	if body.flip_h: offset.x=-offset.x
	var right := Vector3(camera.global_basis.x.x,0,camera.global_basis.x.z).normalized()
	var world := body.global_position+(right*offset.x-Vector3.UP*offset.y)*body.pixel_size
	result["world_point"]=world
	result["position"]=camera.unproject_position(world)
	return result

func _sync_trail(record: Dictionary, original: Texture2D, anchor: Vector2, tint: Color, delta: float) -> void:
	var source: Node2D = record.source
	var allowed := false
	if record.animated and source.visible and not source.is_downed():
		var action := str(record.visual.sprite.animation)
		var spec: Dictionary = source._definition.get("manifest",{}).get("anims",{}).get(action,{})
		# clean只代表源资格；设计启用独立判断，施法者不会因清洁素材自动出影。
		var clean: Variant = spec.get("clean_body",false)
		var approved: Variant = spec.get("qa_approved",false)
		var independent: Variant = spec.get("independent_ghost_ready",false)
		var form := MeleeMotion.form_key(source._definition)
		if action=="battle_dash": allowed=MeleeMotion.is_melee_form(source._definition) and clean is bool and clean and approved is bool and approved
		elif action=="attack": allowed=form=="rinne" and clean is bool and clean and independent is bool and independent
	if not allowed:
		record.trail.cancel()
		record.ghost_elapsed = 0.0
		return
	if delta <= 0.0: return
	record.ghost_elapsed += delta
	if record.ghost_elapsed < .045: return
	record.ghost_elapsed = 0.0
	record.trail.capture(original,anchor,record.body.global_transform,record.body.pixel_size,record.body.flip_h,tint)

func cancel_trails() -> void:
	for record in actor_entries.values():
		record.trail.cancel()
		record.ghost_elapsed = 0.0

func clear_visuals() -> void:
	for record in actor_entries.values():
		if is_instance_valid(record.source) and record.source.has_signal("presentation_position_changed") and record.source.is_connected("presentation_position_changed",record.position_callback):
			record.source.disconnect("presentation_position_changed",record.position_callback)
		if record.animated and is_instance_valid(record.visual):
			for signal_name in ["frame_changed","animation_changed"]:
				if record.visual.sprite.is_connected(signal_name,record.position_callback): record.visual.sprite.disconnect(signal_name,record.position_callback)
		if is_instance_valid(record.trail): record.trail.cancel(); record.trail.free()
		record.tight_frames.clear()
		if is_instance_valid(record.visual): record.visual.visible = record.original_visible
		if is_instance_valid(record.body): record.body.free()
		if is_instance_valid(record.shadow): record.shadow.free()
	actor_entries.clear()

func _exit_tree() -> void:
	clear_visuals()
