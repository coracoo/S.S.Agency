extends SceneTree
var failed:=0
func check(value: bool, message: String) -> void:
	print(('PASS: ' if value else 'FAIL: ')+message)
	if not value: failed+=1
func _initialize() -> void: call_deferred('run')
func run() -> void:
	var loader=load('res://scripts/characters/pixel_character_definition.gd')
	var path='res://assets/chars/rinne_25d/animation_manifest.json'
	var first: Dictionary=loader.load_definition(path)
	var second: Dictionary=loader.load_definition(path)
	check(first.ok and second.ok,'同源两次定义有效')
	var weak: WeakRef=weakref(first.frames.get_frame_texture('idle',0))
	check(first.frames.get_frame_texture('idle',0).get_rid()==second.frames.get_frame_texture('idle',0).get_rid(),'同源多实例共享纹理RID')
	first.frames.set_frame('idle',0,first.frames.get_frame_texture('idle',0),99.0)
	check(second.frames.get_frame_duration('idle',0)!=99.0,'时序容器不随纹理共享而互相污染')
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var png=FileAccess.get_file_as_bytes(original.dir+original.anims.idle.frames[0]+'.png')
	var file=FileAccess.open('user://shared_pose.png',FileAccess.WRITE);file.store_buffer(png);file.close()
	var manifest=original.duplicate(true);manifest.dir='user://'
	manifest.anims={'idle':{'frames':['shared_pose'],'durations_ms':[500]},'walk':{'frames':['shared_pose'],'durations_ms':[500]},'attack':{'frames':['shared_pose'],'durations_ms':[460],'loop':false}}
	file=FileAccess.open('user://sharing.json',FileAccess.WRITE);file.store_string(JSON.stringify(manifest));file.close()
	var copy: Dictionary=loader.load_definition('user://sharing.json')
	check(copy.ok and copy.frames.get_frame_texture('idle',0).get_rid()==second.frames.get_frame_texture('idle',0).get_rid(),'相同PNG不同路径共享纹理')
	var changed:=Image.new();changed.load_png_from_buffer(png);changed.set_pixel(0,0,Color.MAGENTA);changed.save_png('user://shared_pose.png')
	var third: Dictionary=loader.load_definition('user://sharing.json')
	check(third.ok and third.frames.get_frame_texture('idle',0).get_rid()!=second.frames.get_frame_texture('idle',0).get_rid(),'同路径内容变化不会误复用旧纹理')
	check(second.frames.get_frame_texture('idle',0).get_image().get_pixel(0,0)!=Color.MAGENTA,'已有实例纹理不会被新内容改写')
	manifest.canvas.w=1
	manifest.canvas.anchor=[0,1]
	file=FileAccess.open('user://sharing_bad.json',FileAccess.WRITE);file.store_string(JSON.stringify(manifest));file.close()
	var bad: Dictionary=loader.load_definition('user://sharing_bad.json')
	check(not bad.ok,'缓存命中仍拒绝错误画布清单')
	check(third.frames.get_frame_texture('idle',0).get_width()==original.canvas.w,'坏清单不会改变已有有效纹理')
	var changed_weak: WeakRef=weakref(third.frames.get_frame_texture('idle',0))
	first.clear();second.clear();copy.clear();third.clear()
	await process_frame
	check(weak.get_ref()==null and changed_weak.get_ref()==null,'无持有者时纹理释放，缓存不强行常驻')
	print('TEXTURE_SHARING_RESULT: ',failed)
	quit(1 if failed else 0)
