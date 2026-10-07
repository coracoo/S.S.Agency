# 原图逻辑画布上的动作附件；只标注位置，不修改人物像素、固定脚锚或规则。
extends RefCounted
const CasterTools = preload("res://scripts/characters/caster_tool_focus_points.gd")
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
const QUICK_MAGE_PAGES := {
	"attack_cycles_v001_00.png":"f0f7be16d01713ef70cb247be807803c57a664decb16a9b8d664a98e4a1e42d0"}
# 875ms新动作的逐姿势掌前点；36帧来自原生掌心量测，其余直接复核实际注册图集。
const QUICK_MAGE_HAND := [
	[1026,628],[1027,607],[1028,581],[1034,566],[1060,549],[1102,547],
	[1163.137,538.767],[1163,539],[1163,539],[1163,539],[1163,539],[1163,539],
	[1163,539],[1163,539],[1161,540],[1107,550],[1060,575],[1030,607],
	[1026,628],[1026,628],[1026,628]]
static var _verified: Dictionary = {}
static func resolve(definition: Dictionary,action: String,index: int) -> Dictionary:
	var manifest: Dictionary = definition.get("manifest",{})
	if str(manifest.get("identity_id","")) in ["healer","controller"]:return CasterTools.resolve(definition,action,index)
	if manifest.get("identity_id")!="homura" or manifest.get("form_id")!="mage" or action!="attack": return {"ok":false,"reason":"unregistered_action_attachment"}
	var spec: Dictionary = manifest.get("anims",{}).get(action,{})
	var names: Array = spec.get("frames",[])
	var canvas: Dictionary = manifest.get("canvas",{})
	var duration := 0.0
	for value in spec.get("durations_ms",[]): duration+=float(value)
	if canvas.get("w")!=2048 or canvas.get("h")!=1024 or Vector2(float(canvas.get("anchor",[0,0])[0]),float(canvas.get("anchor",[0,0])[1]))!=Vector2(1024,930): return {"ok":false,"reason":"uncalibrated_action_revision"}
	var points: Array = []
	var expected_pages: Dictionary = {}
	var profile := ""
	if names.size()==49 and names[0]=="attack_009" and names[-1]=="attack_113" and absf(duration-1306.0)<.01:
		points=OLD_MAGE_HAND;expected_pages=OLD_MAGE_PAGES;profile="homura_mage_recovered_attack_hand_v1"
	elif names.size()==21 and absf(duration-875.0)<.01:
		if absf(float(spec.get("impact_ms",0))-7000.0/24.0)>.01:return {"ok":false,"reason":"uncalibrated_action_revision"}
		for frame in names.size():
			if names[frame]!="attack_cycles_%03d"%(frame+30): return {"ok":false,"reason":"uncalibrated_action_revision"}
			if absf(float(spec.durations_ms[frame])-1000.0/24.0)>.01:return {"ok":false,"reason":"uncalibrated_action_revision"}
		points=QUICK_MAGE_HAND;expected_pages=QUICK_MAGE_PAGES;profile="homura_mage_quick_attack_hand_v1"
	else: return {"ok":false,"reason":"uncalibrated_action_revision"}
	if index<0 or index>=names.size(): return {"ok":false,"reason":"invalid_frame"}
	var frames: SpriteFrames = definition.get("frames")
	if frames==null: return {"ok":false,"reason":"missing_frames"}
	var key := str(frames.get_instance_id())+":"+profile
	if not _verified.has(key):
		var pages := {}
		for name in names:
			var path := str(manifest.get("packed_frames",{}).get(name,{}).get("atlas",""))
			pages[path]=true
		var valid := pages.size()==expected_pages.size()
		for path in pages:
			valid = valid and expected_pages.get(str(path).get_file(),"")==FileAccess.get_sha256(path)
		_verified[key]=valid
		if _verified.size()>64: _verified.erase(_verified.keys()[0])
	if not _verified[key]: return {"ok":false,"reason":"attachment_source_hash_mismatch"}
	var result:={"ok":true,"profile":profile,"frame_key":str(names[index]),"logical_point":Vector2(points[index][0],points[index][1])}
	# 新动作到native35才开始推掌；提前收掌阶段只保留较小聚能，不提前离身。
	if profile=="homura_mage_quick_attack_hand_v1":result["launch_seconds"]=5.0/24.0;result["cast_scale"]=.55
	return result
