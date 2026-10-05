# 独立战斗镜头复用正式寺域几何。只桥接现有动作帧与脚点，不保存或结算战斗状态。
extends Control
const Geometry = preload("res://scripts/campaign/act_one_geometry.gd")
const Layout = preload("res://scripts/campaign/act_one_layout.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
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
	geometry = Geometry.build({})
	_world.add_child(geometry)
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
	geometry.update_visibility(stage_origin,1.0,camera)
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
		actor_entries[actor_id] = {"source":source,"visual":visual,"animated":animated != null,"body":body,"shadow":shadow,"original_visible":visual.visible}
		visual.hide()
		if is_instance_valid(actors[actor_id].get("shadow")): actors[actor_id].shadow.hide()
	sync_visuals()

func sync_visuals(delta: float = 1.0/60.0) -> void:
	var positions:Array[Vector3]=[]
	for record in actor_entries.values():
		if not is_instance_valid(record.source): continue
		var body: Sprite3D = record.body
		var source: Node2D = record.source
		var visual: Node2D = record.visual
		var texture: Texture2D
		var tint := source.modulate * visual.modulate
		var foot: Vector2 = source.position
		if record.animated:
			var sprite: AnimatedSprite2D = visual.sprite
			if sprite.sprite_frames == null: continue
			texture = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
			var definition: Dictionary = source._definition
			var canvas: Dictionary = definition.manifest.canvas
			var anchor := Stature.body_anchor(definition)
			if sprite.flip_h: anchor.x = float(canvas.w) - anchor.x
			body.offset = Vector2(float(canvas.w)*.5-anchor.x,anchor.y-float(canvas.h)*.5)
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
		record.shadow.position = body.position + Vector3(0,.014,0)
		body.visible = source.visible
		record.shadow.visible = source.visible
		if source.visible: positions.append(body.position)
	if not positions.is_empty(): geometry.update_tree_occlusion_many(positions,delta,camera)

func _ground_point(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	return origin + direction * ((stage_origin.y-origin.y)/direction.y)

func clear_visuals() -> void:
	for record in actor_entries.values():
		if is_instance_valid(record.visual): record.visual.visible = record.original_visible
		if is_instance_valid(record.body): record.body.free()
		if is_instance_valid(record.shadow): record.shadow.free()
	actor_entries.clear()

func _exit_tree() -> void:
	clear_visuals()
