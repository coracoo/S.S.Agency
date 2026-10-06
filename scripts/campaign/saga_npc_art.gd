# 后章居民独立静态原画：精确姓名登记、整图原字节加载与Atlas区域裁取；不改同行六人素材。
class_name CampaignSagaNpcArt
extends RefCounted
const MANIFEST_PATH := "res://assets/chars/npcs/saga/asset_manifest.json"
const PNG = preload("res://scripts/ui/png_loader.gd")
const Existing = preload("res://scripts/campaign/act_one_npcs.gd")
const FONT = preload("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
const LIGHT = preload("res://scripts/characters/illustration_scene_light.gdshader")
const SHADOW = preload("res://scripts/characters/ground_contact_shadow.gdshader")
const BUILTIN := {"老梁":"liang","阿诚":"acheng"}
static var _data: Dictionary = {}
static var _definitions: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(MANIFEST_PATH):
		var value = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if value is Dictionary and int(value.get("schema_version",0))==1 and value.get("characters") is Dictionary: _data=value
	return _data

static func supports(speaker: String) -> bool:
	return BUILTIN.has(speaker) or data().get("characters",{}).has(speaker)

static func definition(speaker: String) -> Dictionary:
	if _definitions.has(speaker): return _definitions[speaker]
	if BUILTIN.has(speaker):
		var identity: String=BUILTIN[speaker]
		var original: Dictionary=Existing.RESIDENT_ART[identity]
		var value: Dictionary={"ok":true,"speaker":speaker,"world":original.texture,"portrait":Existing.RESIDENT_PORTRAITS[identity],"body_anchor":original.anchor,"crown_y":original.crown_y,"height_cm":original.height_cm,"sheet":"res://assets/chars/npcs/act_one/%s_world.png" % identity,"portrait_sheet":"res://assets/chars/npcs/act_one/%s_half.png" % identity,"builtin":true}
		_definitions[speaker]=value
		return value
	var record: Dictionary=data().get("characters",{}).get(speaker,{})
	if record.is_empty(): return _failure("尚未提供%s的独立人物原画" % speaker)
	if str(record.get("speaker",""))!=speaker: return _failure("人物登记姓名不一致："+speaker)
	var path: String=str(record.get("sheet",""))
	if not path.begins_with("res://assets/chars/npcs/saga/") or not path.ends_with(".png"): return _failure("人物原图路径未获登记："+speaker)
	var texture: Texture2D=PNG.load_texture(path)
	if texture==null: return _failure("人物原图无法加载："+speaker)
	var result:=from_record(record,texture)
	if result.get("ok",false): _definitions[speaker]=result
	return result

static func from_record(record: Dictionary, texture: Texture2D) -> Dictionary:
	var speaker:=str(record.get("speaker",""))
	if texture==null or speaker.is_empty(): return _failure("人物图片或姓名缺失")
	for field in ["world_region","portrait_region"]:
		var values=record.get(field)
		if not values is Array or values.size()!=4: return _failure("人物取景字段缺失："+field)
		for value in values:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)): return _failure("人物取景必须为有限整数像素")
		if values[2]<=0 or values[3]<=0 or not Rect2(Vector2.ZERO,texture.get_size()).encloses(Rect2(values[0],values[1],values[2],values[3])): return _failure("人物取景超出原画："+speaker)
	var anchor=record.get("body_anchor")
	if not anchor is Array or anchor.size()!=2: return _failure("人物脚底锚点缺失")
	for value in anchor:
		if not (value is int or value is float) or not is_finite(float(value)): return _failure("人物脚底锚点格式非法")
	for field in ["crown_y","height_cm"]:
		if not (record.get(field) is int or record.get(field) is float) or not is_finite(float(record[field])): return _failure("人物标尺格式非法")
	var world: Array=record.world_region
	if anchor[0]<0 or anchor[0]>world[2] or anchor[1]<=record.crown_y or anchor[1]>world[3] or record.crown_y<0 or record.height_cm<=0: return _failure("人物身高或脚底锚点越界")
	var result: Dictionary={"ok":true,"speaker":speaker,"world":_atlas(texture,record.world_region),"portrait":_atlas(texture,record.portrait_region),"body_anchor":Vector2(anchor[0],anchor[1]),"crown_y":float(record.crown_y),"height_cm":float(record.height_cm),"sheet":str(record.get("sheet","")),"source_texture":texture,"builtin":false}
	return result

static func _atlas(texture: Texture2D, values: Array) -> AtlasTexture:
	var atlas:=AtlasTexture.new(); atlas.atlas=texture; atlas.region=Rect2(values[0],values[1],values[2],values[3]); atlas.filter_clip=true
	return atlas

static func portrait(speaker: String) -> Dictionary:
	var entry:=definition(speaker)
	if not entry.get("ok",false): return entry
	return {"ok":true,"texture":entry.portrait,"key":"saga_npc:"+speaker,"source_path":entry.get("portrait_sheet",entry.sheet),"framing":"half_body"}

static func world_actor(speaker: String) -> Node3D:
	var entry:=definition(speaker)
	if not entry.get("ok",false): return null
	var actor:=Node3D.new(); actor.name="Resident"; actor.set_meta("speaker",speaker); actor.set_meta("source_path",entry.sheet)
	var sprite:=Sprite3D.new(); sprite.name="Body"; sprite.texture=entry.world
	var anchor: Vector2=entry.body_anchor
	var dimensions: Vector2=entry.world.get_size()
	sprite.offset=Vector2(dimensions.x*.5-anchor.x,anchor.y-dimensions.y*.5)
	sprite.pixel_size=float(entry.height_cm)/100.0/(anchor.y-float(entry.crown_y))
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.billboard=BaseMaterial3D.BILLBOARD_FIXED_Y; sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD; sprite.alpha_scissor_threshold=.5
	sprite.shaded=false; sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var material:=ShaderMaterial.new(); material.shader=LIGHT; material.set_shader_parameter("scene_light_mix",.65)
	material.set_shader_parameter("art_texture",entry.get("source_texture",entry.world)); sprite.material_override=material; actor.add_child(sprite)
	var shadow:=MeshInstance3D.new(); shadow.name="ContactShadow"; var plane:=PlaneMesh.new(); plane.size=Vector2(.5,.25); shadow.mesh=plane; shadow.position.y=.014
	var ground:=ShaderMaterial.new(); ground.shader=SHADOW; ground.set_shader_parameter("opacity",.58); shadow.material_override=ground; shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; actor.add_child(shadow)
	var nameplate:=Label3D.new(); nameplate.name="Nameplate"; nameplate.text=speaker; nameplate.font=FONT; nameplate.font_size=36; nameplate.pixel_size=.004
	nameplate.position.y=float(entry.height_cm)/100+.28; nameplate.billboard=BaseMaterial3D.BILLBOARD_FIXED_Y; nameplate.modulate=Color("e8ddbf"); nameplate.outline_modulate=Color("242630"); nameplate.outline_size=6; actor.add_child(nameplate)
	return actor

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"missing":true}
