# 正式战斗同源3D背景与2.5D身体桥接：只检查呈现，不造战斗规则。
extends SceneTree
const Portraits=preload("res://scripts/characters/identity_portraits.gd")
const HdActor=preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Stature=preload("res://scripts/characters/character_stature.gd")
const LegacyActor=preload("res://scripts/rpg/ui/legacy_actor_view.gd")
const Kit=preload("res://scripts/rpg/ui/ui_kit.gd")
var failures:Array[String]=[]
var checks:=0
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);printerr("ASSERT FAIL:",message)
func _run()->void:
	var path:="res://scripts/rpg/ui/battle_world_backdrop.gd"
	check(ResourceLoader.exists(path),"正式战斗需要同源可渲染3D背景，不能只换插画")
	if not ResourceLoader.exists(path):quit(1);return
	var backdrop=load(path).new();root.add_child(backdrop)
	backdrop.configure({"night":2,"position":[20.3,2.89,-6.0]})
	for frame in 2:await process_frame
	check(backdrop.scene_region=="corridor","背景按实际战前所在地区选构图")
	check(backdrop.viewport.own_world_3d and backdrop.geometry!=null,"独立3D世界复用正式连续几何")
	check(backdrop.get_node_or_null("BattleDepth")!=null,"战斗沿用同源可逆空间景深节点")
	check(backdrop.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"延续2.5D正交镜头")
	var definition:Dictionary=Portraits.load_idle_definition("rinne","")
	var actor:=HdActor.new();root.add_child(actor)
	check(actor.configure(definition,Stature.battle_body_height("rinne"),-1),"沿用原高清帧定义")
	actor.position=Vector2(1160,680)
	actor.set_meta("foot_point",actor.position);actor.set_meta("content_height",Stature.battle_body_height("rinne"))
	backdrop.bind_visuals({"p_rinne":{"sprite":actor}})
	for frame in 2:await process_frame
	var record:Dictionary=backdrop.actor_entries.get("p_rinne",{})
	check(not record.is_empty(),"战斗现有视觉绑定到3D身体")
	if not record.is_empty():
		var body:Sprite3D=record.body
		check(body.texture==actor.animator.sprite.sprite_frames.get_frame_texture(actor.animator.sprite.animation,actor.animator.sprite.frame),"真实当前动作帧同步，不新增静态人物副本")
		check(absf(body.pixel_size-Stature.world_pixel_size(definition))<.000001,"保持168cm原世界比例，不按武器画布fit")
		check(backdrop.camera.unproject_position(body.global_position).distance_to(Vector2(1160,680))<1.0,"3D脚点投影与原目标热区一致")
		check(not actor.animator.visible and actor.feedback_label.get_parent()==actor,"旧2D身体不叠画，反馈仍归原动画事件层")
		var opacity:Variant=record.shadow.material_override.get_shader_parameter("opacity")
		check(opacity is float and opacity>=.55,"脚点有紧凑可读接触暗部")
		actor.set_facing(1)
		actor.modulate=Color(.4,.4,.4,.55)
		backdrop.sync_visuals()
		check(not body.flip_h and body.material_override.get_shader_parameter("appearance_tint")==actor.modulate,"现有朝向/受击倒地调制同步到3D，不改源帧")
	backdrop.clear_visuals()
	check(actor.animator.visible,"销毁桥接恢复原视觉持有者")
	Kit.init()
	var enemy:=LegacyActor.new();root.add_child(enemy)
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))
	var enemy_sprite:=Kit.actor_sprite(root,config.enemy_art.hound,265.0,false,config.enemy_geometry.hound)
	root.remove_child(enemy_sprite);enemy.configure(enemy_sprite,265.0,"right",true)
	enemy.position=Vector2(340,650)
	backdrop.bind_visuals({"e_hound":{"sprite":enemy}})
	check(backdrop.actor_entries.size()==1 and not enemy.visual.visible,"敌方沿用既有表现适配器，不叠画2D身体")
	enemy.visual.position.x=24.0
	enemy.visual.modulate=Color(1,.45,.35)
	backdrop.sync_visuals()
	var enemy_body:Sprite3D=backdrop.actor_entries.e_hound.body
	check(backdrop.camera.unproject_position(enemy_body.position).distance_to(Vector2(364,650))<1.0,"原攻击前移和脚点投影同步")
	check(enemy_body.material_override.get_shader_parameter("appearance_tint")==enemy.visual.modulate,"敌人受击调制仍可见")
	backdrop.clear_visuals()
	check(enemy.visual.visible,"敌人清理桥接后恢复原可见状态")
	enemy.free();backdrop.free()
	var north=load(path).new();root.add_child(north)
	north.configure({"night":4,"position":[34.8,2.89,-11.8]})
	actor.position=Vector2(340,650)
	north.bind_visuals({"e_left":{"sprite":actor}})
	for tick in 24:north.sync_visuals()
	var faded_count:=0
	for tree in north.geometry._tree_occluders:
		if tree.occluded and float(tree.opacity)<.02:faded_count+=1
	check(faded_count>0,"侧径前景树按真实敌方位置渐隐，不能只保护画面中心")
	north.clear_visuals();actor.free();north.free()
	print("BATTLE_WORLD_BACKDROP:",checks," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
