# 已测铃口/卷轴端盖的动作焦点；只覆盖S至M+1帧，未测恢复帧不插值或钳到末点。
extends RefCounted
const PROFILES := {
	"healer": {
		"profile": "healer_recovered_attack_tool_focus_v1",
		"frames": [
			"attack_025",
			"attack_027",
			"attack_029",
			"attack_031",
			"attack_033",
			"attack_035",
			"attack_037",
			"attack_039",
			"attack_041",
			"attack_043",
			"attack_045",
			"attack_046",
			"attack_047",
			"attack_048",
			"attack_049",
			"attack_050",
			"attack_051",
			"attack_052",
			"attack_053",
			"attack_054",
			"attack_055",
			"attack_056",
			"attack_057",
			"attack_058",
			"attack_059",
			"attack_060",
			"attack_061",
			"attack_065",
			"attack_069",
			"attack_073",
			"attack_077",
			"attack_081",
			"attack_085",
			"attack_087",
			"attack_089",
			"attack_091",
			"attack_093",
			"attack_095",
			"attack_097",
			"attack_099",
			"attack_101",
			"attack_103",
			"attack_105"
		],
		"durations_ms": [
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			25,
			20,
			20,
			20,
			20,
			20,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30
		],
		"impact_ms": 300,
		"points": [
			[
				1121,
				648
			],
			[
				1122,
				648
			],
			[
				1124,
				648
			],
			[
				1125,
				646
			],
			[
				1123,
				629
			],
			[
				1127,
				605
			],
			[
				1129,
				597
			],
			[
				1138,
				582
			],
			[
				1133,
				582
			],
			[
				1133,
				577
			],
			[
				1138,
				574
			],
			[
				1134,
				576
			]
		],
		"pages": {
			"runtime448_battle_00.png": "b318022cb4bd37c45bc219406b9984f0b51124811a12c6207979a189ca2b15e3",
			"runtime448_battle_01.png": "f1fa8eab2a0547e4ca5b874ca183fcb4d3f1bcdc6d5a095df7e4842caeeb863d",
			"runtime448_battle_02.png": "624da2b3d2782e128daab29db84638459732d497fb0f14af5d2b3b3124c01341"
		},
		"launch_seconds": 0.21,
		"cast_scale": 0.6
	},
	"controller": {
		"profile": "controller_recovered_attack_tool_focus_v1",
		"frames": [
			"attack_016",
			"attack_018",
			"attack_020",
			"attack_022",
			"attack_024",
			"attack_026",
			"attack_028",
			"attack_030",
			"attack_032",
			"attack_034",
			"attack_036",
			"attack_037",
			"attack_038",
			"attack_039",
			"attack_040",
			"attack_041",
			"attack_042",
			"attack_043",
			"attack_044",
			"attack_045",
			"attack_048",
			"attack_053",
			"attack_058",
			"attack_063",
			"attack_068",
			"attack_073",
			"attack_078",
			"attack_080",
			"attack_082",
			"attack_084",
			"attack_086",
			"attack_088",
			"attack_090",
			"attack_092",
			"attack_094",
			"attack_096",
			"attack_098",
			"attack_100",
			"attack_102",
			"attack_104",
			"attack_106",
			"attack_108"
		],
		"durations_ms": [
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			20,
			20,
			20,
			20,
			20,
			20,
			20,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30,
			30
		],
		"impact_ms": 390,
		"points": [
			[
				1033,
				706
			],
			[
				1048,
				705
			],
			[
				1063,
				698
			],
			[
				1082,
				691
			],
			[
				1111,
				674
			],
			[
				1130,
				653
			],
			[
				1148,
				632
			],
			[
				1160,
				604
			],
			[
				1164,
				586
			],
			[
				1167,
				568
			],
			[
				1167,
				546
			],
			[
				1165,
				537
			],
			[
				1164,
				533
			],
			[
				1161,
				528
			],
			[
				1160,
				524
			]
		],
		"pages": {
			"runtime448_battle_00.png": "2fcf0f79fa71ea445662f38af6a8e7deb2cd3033418dec245df86127fa8f3896",
			"runtime448_battle_01.png": "a13a6313e66ae6c0a75f2a097389d55475769afa3380a1562f680c9d7ecfc70e"
		},
		"launch_seconds": 0.24,
		"cast_scale": 0.6
	}
}
static var _verified:Dictionary={}
static func resolve(definition:Dictionary,action:String,index:int)->Dictionary:
	var manifest:Dictionary=definition.get("manifest",{})
	var identity:=str(manifest.get("identity_id",""))
	if action!="attack" or not PROFILES.has(identity):return {"ok":false,"reason":"unregistered_action_attachment"}
	var profile:Dictionary=PROFILES[identity]
	var canvas:Dictionary=manifest.get("canvas",{});var anchor:Array=canvas.get("anchor",[])
	var spec:Dictionary=manifest.get("anims",{}).get("attack",{});var names:Array=spec.get("frames",[]);var durations:Array=spec.get("durations_ms",[])
	if canvas.get("w")!=2048 or canvas.get("h")!=1024 or anchor.size()!=2 or Vector2(float(anchor[0]),float(anchor[1]))!=Vector2(1024,930) or names!=profile.frames or durations.size()!=profile.durations_ms.size() or absf(float(spec.get("impact_ms",0))-float(profile.impact_ms))>.001:return {"ok":false,"reason":"uncalibrated_action_revision"}
	for frame in durations.size():
		if absf(float(durations[frame])-float(profile.durations_ms[frame]))>.001:return {"ok":false,"reason":"uncalibrated_action_revision"}
	if index<0 or index>=profile.points.size():return {"ok":false,"reason":"unmeasured_action_frame"}
	var frames:SpriteFrames=definition.get("frames")
	if frames==null:return {"ok":false,"reason":"missing_frames"}
	var key:=str(frames.get_instance_id())+":"+identity
	if not _verified.has(key):
		var pages:Dictionary={}
		for name in names:pages[str(manifest.get("packed_frames",{}).get(name,{}).get("atlas",""))]=true
		var valid:bool=pages.size()==profile.pages.size()
		for path in pages:valid=valid and profile.pages.get(str(path).get_file(),"")==FileAccess.get_sha256(path)
		_verified[key]=valid
		if _verified.size()>64:_verified.erase(_verified.keys()[0])
	if not _verified[key]:return {"ok":false,"reason":"attachment_source_hash_mismatch"}
	return {"ok":true,"profile":profile.profile,"frame_key":str(names[index]),"logical_point":Vector2(profile.points[index][0],profile.points[index][1]),"launch_seconds":profile.launch_seconds,"cast_scale":profile.cast_scale}
