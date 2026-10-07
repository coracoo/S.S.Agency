# 新深弓步的刃内接触点；按实际源页绑定，不把整张图宽或剑尖极限直接当站距。
extends RefCounted
const RINNE_PAGES:={
	"attack_clean_v001_00.png":"9e9b0e964cd2f7b348b7abfa23c7c356bbd133aecf8467aef9a14c4484446e11",
	"attack_clean_v001_01.png":"d42872d2071aac5b177e73dc202aa9e52c6445be655ab15f1bddea41667bba88",
	"attack_clean_v001_02.png":"27b88c342e9e3fc4c55284fd61e50c4f62d7aa8c1cc9f29430865ad3825179e9"}
const RINNE_FRAMES:=[5,6,7,8,9,10,15,16,17,18,19,20,21,22,27,28,29,30,31,32,33,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81]
static var _verified:Dictionary={}
static func resolve(definition:Dictionary)->Dictionary:
	var manifest:Dictionary=definition.get("manifest",{})
	if manifest.get("identity_id")!="rinne":return {}
	var spec:Dictionary=manifest.get("anims",{}).get("attack",{});var names:Array=spec.get("frames",[])
	var canvas:Dictionary=manifest.get("canvas",{})
	var anchor:Array=canvas.get("anchor",[])
	var clean:Variant=spec.get("clean_body",false)
	if names.size()!=36 or canvas.get("w")!=2048 or canvas.get("h")!=1536 or anchor.size()!=2 or Vector2(float(anchor[0]),float(anchor[1]))!=Vector2(1024,1442) or not clean is bool or not clean:return {}
	if absf(float(spec.get("impact_ms",0))-17000.0/24.0)>.01 or spec.get("durations_ms",[]).size()!=36:return {}
	for index in names.size():
		if names[index]!="attack_clean_%03d"%RINNE_FRAMES[index] or absf(float(spec.durations_ms[index])-1000.0/24.0)>.01:return {}
	var frames:SpriteFrames=definition.get("frames")
	if frames==null:return {}
	var key:=frames.get_instance_id()
	if not _verified.has(key):
		var pages:Dictionary={}
		for name in names:pages[str(manifest.get("packed_frames",{}).get(name,{}).get("atlas",""))]=true
		var valid:=pages.size()==3
		for path in pages:valid=valid and RINNE_PAGES.get(str(path).get_file(),"")==FileAccess.get_sha256(path)
		_verified[key]=valid
		if _verified.size()>64:_verified.erase(_verified.keys()[0])
	if not _verified[key]:return {}
	# M姿势的前端刃内点；约51逻辑像素留在剑尖之前，让端部进入目标轮廓。
	return {"profile":"rinne_repaired_lunge_contact_v1","logical_point":Vector2(1510,1377)}
