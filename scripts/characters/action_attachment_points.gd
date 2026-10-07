# 原图逻辑画布上的动作附件；只标注位置，不修改人物像素、固定脚锚或规则。
extends RefCounted
const OLD_MAGE_PAGES := {
	"runtime448_battle_00.png":"3eb4877fe9c6bb4cd5d5739b485e10a891a3c8fd01b5a0874b06699369724ac2",
	"runtime448_battle_01.png":"448e44904d3887e2fd9adb41223da2f50ac633b47ae20c6b06f4150a6490c8ae",
	"runtime448_battle_02.png":"fb513ba39637c6226216be40f2d5e6ea332c0e7596dd8fa981837a9e778c947b"}
# 旧49姿势逐帧标注向前的掌心；新21姿势/875ms动作必须单独校准。
const OLD_MAGE_HAND := [
	[1064,640],[1068,632],[1071,623],[1075,612],[1076,600],[1078,591],[1079,583],
	[1080,577],[1082,574],[1083,571],[1085,569],[1088,568],[1089,568],[1090,567],
	[1092,564],[1094,562],[1098,559],[1100,556],[1103,552],[1105,549],[1108,546],
	[1110,543],[1113,541],[1115,540],[1117,540],[1119,540],[1121,540],[1123,540],
	[1125,540],[1127,540],[1128,540],[1128,540],[1128,540],[1128,540],[1128,540],
	[1126,542],[1121,546],[1115,552],[1110,560],[1105,568],[1099,579],[1094,590],
	[1088,602],[1082,614],[1078,626],[1074,638],[1071,650],[1069,662],[1067,674]]
static var _verified: Dictionary = {}
static func resolve(definition: Dictionary,action: String,index: int) -> Dictionary:
	var manifest: Dictionary = definition.get("manifest",{})
	if manifest.get("identity_id")!="homura" or manifest.get("form_id")!="mage" or action!="attack": return {"ok":false,"reason":"unregistered_action_attachment"}
	var spec: Dictionary = manifest.get("anims",{}).get(action,{})
	var names: Array = spec.get("frames",[])
	var canvas: Dictionary = manifest.get("canvas",{})
	var duration := 0.0
	for value in spec.get("durations_ms",[]): duration+=float(value)
	if names.size()!=49 or names[0]!="attack_009" or names[-1]!="attack_113" or absf(duration-1306.0)>.01 or canvas.get("w")!=2048 or canvas.get("h")!=1024 or Vector2(float(canvas.get("anchor",[0,0])[0]),float(canvas.get("anchor",[0,0])[1]))!=Vector2(1024,930): return {"ok":false,"reason":"uncalibrated_action_revision"}
	if index<0 or index>=names.size(): return {"ok":false,"reason":"invalid_frame"}
	var frames: SpriteFrames = definition.get("frames")
	if frames==null: return {"ok":false,"reason":"missing_frames"}
	var key := frames.get_instance_id()
	if not _verified.has(key):
		var pages := {}
		for name in names:
			var path := str(manifest.get("packed_frames",{}).get(name,{}).get("atlas",""))
			pages[path]=true
		var valid := pages.size()==3
		for path in pages:
			valid = valid and OLD_MAGE_PAGES.get(str(path).get_file(),"")==FileAccess.get_sha256(path)
		_verified[key]=valid
		if _verified.size()>64: _verified.erase(_verified.keys()[0])
	if not _verified[key]: return {"ok":false,"reason":"attachment_source_hash_mismatch"}
	return {"ok":true,"profile":"homura_mage_recovered_attack_hand_v1","frame_key":str(names[index]),"logical_point":Vector2(OLD_MAGE_HAND[index][0],OLD_MAGE_HAND[index][1])}
