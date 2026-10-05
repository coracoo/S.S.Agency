# 同行人物在连续寺域中的可见停驻与路引；不拥有战斗资源，也不写入主线进度。
extends Node3D
const Layout = preload("res://scripts/campaign/act_one_layout.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
const FONT := preload("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
const SCENE_LIGHT_SHADER := preload("res://scripts/characters/illustration_scene_light.gdshader")
const RESIDENT_ART := {
	"liang": {"texture": preload("res://assets/chars/npcs/act_one/liang_world.png"), "height_cm": 172.0, "anchor": Vector2(510, 1487), "crown_y": 64.0},
	"acheng": {"texture": preload("res://assets/chars/npcs/act_one/acheng_world.png"), "height_cm": 176.0, "anchor": Vector2(470, 1497), "crown_y": 62.0},
}
const RESIDENT_PORTRAITS := {
	"liang": preload("res://assets/chars/npcs/act_one/liang_half.png"),
	"acheng": preload("res://assets/chars/npcs/act_one/acheng_half.png"),
}
const PARTY_ACTORS := {"guard": "p_guard", "mint": "p_ranger", "controller": "p_controller"}
const ROSTER := [
	{
		"identity_id": "liang", "label": "守山人·老梁", "position": [14.0, Layout.TEMPLE_HEIGHT, 3.0],
		"source": "本轮新增普通守山人；仅指路，不接替原神社祭主；assets/chars/npcs/act_one/asset_manifest.json",
		"lines": [
			"上山的石阶有些滑。沿原路往西就能下山，别抄树边的小道。今夜的雾，来得早。",
			"你找回廊？从前庭往北走。风还没起，檐下倒先有了声音。",
			"东南那条石径通纸棺庭。落叶没有动，脚步声却过去了……我就守着这段山路。",
			"镜殿在北侧，穿过中庭再拐过去。雾把屋檐遮住了，认脚下的石路。",
			"本殿在最东头。这一路都通着。我在山门边留神，你们办完了，沿来路下山。",
		],
	},
	{
		"identity_id": "acheng", "label": "扫庭人·阿诚", "position": [21.0, Layout.TEMPLE_HEIGHT, -3.1],
		"source": "本轮新增普通扫庭人；无宗教职衔与主线知情设定；assets/chars/npcs/act_one/asset_manifest.json",
		"lines": [
			"这几片叶子，总扫不出石缝。回廊在北边，沿檐前的石路过去就成。",
			"檐下的灯低了。扫帚碰不着，我也不敢去拨。你们看灯，脚下的路我让开。",
			"去纸棺庭走南边。今日扫起来的纸屑，轻得不像纸，风停了还在挪。",
			"北边那间是镜殿。方才扫过的地，转眼又湿了；走门前，别踩苔边。",
			"东面的本殿前，今夜格外静。这里已经扫过了，你们从中庭过去吧。",
		],
	},
	{
		"identity_id": "guard", "label": "岑照", "position": [17.6, Layout.TEMPLE_HEIGHT, 5.6],
		"source": "assets/chars/pixel/high_detail_roster.json:26-30；data/characters/stature.json:guard",
		"lines": [
			"山门在身后。要回参道，就沿石路往西下；进了庭院，也记着来时的路。",
			"去回廊，从庭院北边绕过去。檐下那条路通着，别往树根间挤。",
			"纸棺庭在东南。沿南侧石径走，到了转角再往东；山门这边仍可原路返回。",
			"镜殿在北侧，过中庭再向北转。看清了再走，雾里容易错认门。",
			"本殿在最东面。沿中庭向东，路一直通到殿前；回来的路也在。",
		],
	},
	{
		"identity_id": "mint", "label": "薄荷", "position": [19.9, Layout.TEMPLE_HEIGHT, 5.6],
		"source": "docs/chapters/chapter1_棺女.md:16-19；data/dialogues.json:test_approach/a2；data/characters/stature.json:mint",
		"lines": [
			"从前庭往北，就通回廊。参道那边的石钵，水声很轻。走远了，就只剩风声了。",
			"回廊在前庭北面。灯光压得好低……先看清灯旁留下的东西，我再把听见的记下来。",
			"南边是纸棺庭。方才那阵脚步声，像许多人踩着同一拍……我们从石径过去看看。",
			"镜殿在北侧。这一夜的声音比先前还轻，像隔着水。先走近些，别急着碰镜面。",
			"该往东面的本殿去了。凛音，我听着呢。你叩门的时候，不用回头找我。",
		],
	},
	{
		"identity_id": "controller", "label": "清明", "position": [22.0, Layout.TEMPLE_HEIGHT, 6.5],
		"source": "assets/chars/pixel/high_detail_roster.json:38-42；data/characters/stature.json:controller",
		"lines": [
			"从中庭分路，北去镜殿，南去纸棺庭，向东才是本殿。先记住路，再看异象。",
			"回廊在前庭北面。查完檐下的灯，再回到这里；各处的路都通着，不必越过栏边。",
			"去纸棺庭，沿前庭南边的石径向东走。看见列队的纸影，先留出距离。",
			"镜殿在中庭北侧。从侧径绕过去，进出都走门前的石路。",
			"本殿在最东面。穿过中庭，石路一直通到殿前。其余岔路，回来时仍认得。",
		],
	},
]
var night_id := 0
var load_errors: Array[String] = []

static func definitions(value: int, party: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value < 1 or value > 5: return result
	for record in ROSTER:
		var identity: String = record.identity_id
		if PARTY_ACTORS.has(identity) and party.has(PARTY_ACTORS[identity]): continue
		result.append({
			"id": "npc:" + identity, "identity_id": identity, "label": record.label,
			"role": "camp_companion" if PARTY_ACTORS.has(identity) else "resident",
			"kind": "npc", "position": record.position.duplicate(), "radius": 2.1,
			"interaction_radius": 2.1, "body": record.lines[value - 1], "source": record.source,
			"appearance": {"identity_id": identity, "form_id": identity, "height_cm": _height_cm(identity)},
		})
	return result

static func build(value: int, party: Array = []) -> Node3D:
	var group := new()
	group.name = "ActOneNPCs"
	group.refresh_night(value, party)
	return group

func refresh_night(value: int, party: Array = []) -> void:
	var entries := definitions(value, party)
	if entries.is_empty(): return
	night_id = value
	var wanted: Array[String] = []
	for entry in entries: wanted.append(str(entry.id).replace(":", "_"))
	for child in get_children():
		if str(child.name) not in wanted:
			remove_child(child)
			child.queue_free()
	for entry in entries:
		var node_name: String = str(entry.id).replace(":", "_")
		var actor := get_node_or_null(node_name) as Node3D
		if actor == null:
			actor = _create_actor(entry)
			actor.name = node_name
			add_child(actor)
		actor.position = Vector3(entry.position[0], entry.position[1], entry.position[2])
		actor.set_meta("interaction_id", entry.id)
		actor.set_meta("identity_id", entry.identity_id)
		actor.set_meta("body", entry.body)
		actor.set_meta("night_id", value)

func _create_actor(entry: Dictionary) -> Node3D:
	var actor := Node3D.new()
	# 只读取该人物的完整待机PNG，不加载战斗动作，不从敌图或半身像拼人。
	var definition: Dictionary = _idle_definition(entry.identity_id)
	if not definition.get("ok", false):
		var message := "%s的NPC待机素材加载失败：%s" % [entry.label, definition.get("error", "未知错误")]
		load_errors.append(message)
		push_error(message)
		return actor
	actor.set_meta("portrait_definition", definition)
	var canvas: Dictionary = definition.manifest.canvas
	var anchor: Vector2 = RESIDENT_ART[entry.identity_id].anchor if RESIDENT_ART.has(entry.identity_id) else Stature.body_anchor(definition)
	var sprite := AnimatedSprite3D.new()
	sprite.name = "Body"
	sprite.sprite_frames = definition.frames
	sprite.offset = Vector2(float(canvas.w) * 0.5 - anchor.x, anchor.y - float(canvas.h) * 0.5)
	sprite.pixel_size = _height_cm(entry.identity_id) / 100.0 / (anchor.y - float(RESIDENT_ART[entry.identity_id].crown_y)) if RESIDENT_ART.has(entry.identity_id) else Stature.world_pixel_size(definition)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.no_depth_test = false
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	actor.add_child(sprite)
	sprite.play(&"idle")
	# 地图人物与主角共用受光语言，原图/半身对白/身高保持原样；待机换帧同步纹理。
	var scene_material := ShaderMaterial.new()
	scene_material.shader = SCENE_LIGHT_SHADER
	scene_material.set_shader_parameter("scene_light_mix",0.65)
	sprite.material_override = scene_material
	_refresh_lit_frame(sprite,scene_material)
	sprite.frame_changed.connect(_refresh_lit_frame.bind(sprite,scene_material))
	# 脚底原点与主角共用身高标尺，阴影只是低透明接地提示，不创建碰撞。
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	var disc := PlaneMesh.new(); disc.size = Vector2(.46,.24)
	shadow.mesh = disc; shadow.position.y = .014
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/characters/ground_contact_shadow.gdshader")
	material.set_shader_parameter("opacity",.62)
	shadow.material_override = material
	actor.add_child(shadow)
	var nameplate := Label3D.new()
	nameplate.name = "Nameplate"
	nameplate.text = entry.label
	nameplate.font = FONT
	nameplate.font_size = 36
	nameplate.pixel_size = 0.004
	nameplate.position.y = _height_cm(entry.identity_id) / 100.0 + 0.28
	nameplate.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	nameplate.modulate = Color("e8ddbf")
	nameplate.outline_modulate = Color("242630")
	nameplate.outline_size = 6
	nameplate.no_depth_test = false
	actor.add_child(nameplate)
	return actor

static func _height_cm(identity: String) -> float:
	return float(RESIDENT_ART[identity].height_cm) if RESIDENT_ART.has(identity) else Stature.height_cm(identity)

func _refresh_lit_frame(sprite: AnimatedSprite3D, material: ShaderMaterial) -> void:
	if not is_instance_valid(sprite) or sprite.sprite_frames == null: return
	material.set_shader_parameter("art_texture",sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame))

func _idle_definition(identity: String) -> Dictionary:
	if not RESIDENT_ART.has(identity): return Portraits.load_idle_definition(identity)
	var texture: Texture2D = RESIDENT_ART[identity].texture
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.add_frame(&"idle", texture)
	return {"ok": true, "frames": frames, "manifest": {"canvas": {"w": texture.get_width(), "h": texture.get_height()}}}

# 对话必须使用半身：居民独立专图，同伴走与主线一致的上身取景，绝不退回地图全身。
func portrait(npc_id: String) -> Dictionary:
	var actor := get_node_or_null(npc_id.replace(":", "_"))
	if actor == null: return {"ok": true, "empty": true}
	var identity: String = actor.get_meta("identity_id", "")
	if RESIDENT_PORTRAITS.has(identity):
		return {"ok": true, "texture": RESIDENT_PORTRAITS[identity], "key": npc_id + ":half", "framing": "half_body", "source_path": "res://assets/chars/npcs/act_one/" + identity + "_half.png"}
	var definition: Dictionary = actor.get_meta("portrait_definition", {})
	if definition.is_empty(): return {"ok": true, "empty": true}
	return Portraits.from_definition(definition, identity, "portrait")
