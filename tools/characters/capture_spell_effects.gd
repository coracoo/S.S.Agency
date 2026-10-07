# 真Godot图形proof：仅验证独立效果运动/朝向/透明合成，不宣称真实战斗或实时FPS。
extends SceneTree
const Effects = preload("res://scripts/rpg/ui/battle_effects.gd")
const JOBS := [
	["firebolt_right", "firebolt", false, false], ["firebolt_left", "firebolt", true, false],
	["ice_right", "ice_arrow", false, false], ["ice_left", "ice_arrow", true, false],
	["heal_single", "heal", false, false], ["group_heal_all", "group_heal", false, true],
	["slow_all", "slow", false, true], ["seal_single", "seal", false, false],
	["holy_shield", "holy_shield", false, false], ["magic_break", "magic_break", false, false],
	["flame_wave", "flame_wave", false, true], ["cleanse", "cleanse", false, false],
	["burn_brand", "burn_brand", false, false], ["weaken", "weaken", false, false]
]
var output := ""
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	output = OS.get_environment("SPELL_FX_OUTPUT")
	if output.is_empty(): quit(1); return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new(); background.size = Vector2(640,360); background.color = Color("263440")
	viewport.add_child(background)
	var title := Label.new(); title.position = Vector2(14,12); title.add_theme_font_size_override("font_size",20)
	viewport.add_child(title)
	var floor_line := Line2D.new(); floor_line.points = PackedVector2Array([Vector2(28,293),Vector2(612,293)]); floor_line.width = 2; floor_line.default_color = Color("4a6170")
	viewport.add_child(floor_line)
	var fx := Effects.new(); viewport.add_child(fx); fx.set_process(false)
	var report := {"engine":Engine.get_version_info(), "purpose":"独立技能图形运动/合成；非实际战斗与实时FPS", "logical_fps":24, "render_size":[640,360], "jobs":[]}
	for job in JOBS:
		fx.clear()
		title.text = job[0] + " / authored RGBA + deterministic particles"
		var folder := output.path_join(job[0]); DirAccess.make_dir_recursive_absolute(folder)
		var source := Vector2(528,184) if job[2] else Vector2(108,184)
		var center := Vector2(116,184) if job[2] else Vector2(518,184)
		var targets := {"one":center}
		if job[3]: targets = {"one":Vector2(345,148),"two":Vector2(510,148),"three":Vector2(430,256)}
		var markers: Array[Node] = []
		for location in [source] + targets.values():
			var line := Line2D.new(); line.width = 1.5; line.default_color = Color("6b7e80")
			line.points = PackedVector2Array([location+Vector2(-19,42),location+Vector2(-13,-28),location+Vector2(13,-28),location+Vector2(19,42)])
			viewport.add_child(line); viewport.move_child(line,viewport.get_child_count()-2); markers.append(line)
		var command := {"command_id":job[0],"ability_id":job[1],"kind":"skill","impact_delay":0.5}
		fx.present_action(command,"homura_mage",source,targets,"capture")
		var snapshots: Array = []
		var max_texture := 0
		for frame in range(36):
			if frame == 12:
				var spec := Effects.ability_profile(job[1])
				var sequence := 1
				for id in targets:
					var payload := {"damage":18,"actual":20,"reason":"cleanse","status":{"id":"slow"},"shield":{"amount":30}}
					var event := {"sequence":sequence,"type":spec.events[0],"actor_id":"source","target_id":id,"payload":payload}
					fx.present_event(event,"homura_mage",source,targets[id],"capture",command); sequence += 1
			fx.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			max_texture = maxi(max_texture,fx.texture_memory_bytes())
			# 每三帧采样一次12张原PNG，记录真实渲染时刻，避免全尺寸RGB缓存。
			if frame % 3 == 0:
				var pixels := viewport.get_texture().get_image()
				var path := folder.path_join("frame_%03d.png" % frame)
				if pixels.save_png(path) != OK: quit(1); return
				snapshots.append({"frame":frame,"time_seconds":float(frame)/24.0,"file":path.get_file(),"sha256":FileAccess.get_sha256(path),"active_bursts":fx.active_count()})
			fx._process(1.0/24.0)
		report.jobs.append({"id":job[0],"ability_id":job[1],"target_count":targets.size(),"leftward":job[2],"peak_texture_bytes":max_texture,"final_active":fx.active_count(),"final_texture_bytes":fx.texture_memory_bytes(),"snapshots":snapshots})
		for marker in markers: marker.queue_free()
	FileAccess.open(output.path_join("capture_report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPELL_FX_CAPTURE: 14 jobs / 12 unique spells, 168 graphical snapshots, nominal 24fps simulation only")
	quit()
