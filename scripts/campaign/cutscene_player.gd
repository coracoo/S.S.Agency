# 一次性本地Theora播放器；不拥有剧情、奖励、存档或网络接口。
extends CanvasLayer

signal finished(result: String)

const STALL_SECONDS := 4.0
const MAX_SECONDS := 120.0
static var _crc_table := PackedInt64Array()
var video: VideoStreamPlayer
var _cover: ColorRect
var _hint: Label
var _active := false
var _used := false
var _skip_armed := false
var _tree: SceneTree
var _was_paused := false
var _audio_states: Array[Dictionary] = []
var _focus: WeakRef
var _elapsed := 0.0
var _last_position := 0.0
var _stalled := 0.0
var _duration := 0.0
var _frame_seconds := 0.0

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = ColorRect.new()
	_cover.color = Color.BLACK
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	video = VideoStreamPlayer.new()
	video.expand = true
	video.loop = false
	video.autoplay = false
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(video)
	video.finished.connect(_video_finished)
	_hint = Label.new()
	_hint.text = "Esc 跳过"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_override("font", load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"))
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color.WHITE)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(_hint)
	get_viewport().size_changed.connect(_layout)
	hide()

# 启动失败不触碰暂停/音频状态，也不发finished；调用者直接走原对白。
func play_file(path: String) -> bool:
	if _used or not is_inside_tree() or not _has_theora_header(path): return false
	_used = true
	_frame_seconds = _theora_frame_seconds(path)
	if _frame_seconds <= 0.0: return false
	var stream := VideoStreamTheora.new()
	stream.file = path
	video.stream = stream
	_duration = video.get_stream_length()
	var texture := video.get_video_texture()
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0 or _duration <= 0.0 or _duration > MAX_SECONDS:
		video.stream = null
		return false
	_tree = get_tree()
	_was_paused = _tree.paused
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		_focus = weakref(focus)
		focus.release_focus()
	_pause_audio(_tree.root)
	_active = true
	_skip_armed = not Input.is_physical_key_pressed(KEY_ESCAPE)
	_tree.paused = true
	_layout()
	show()
	video.play()
	if not video.is_playing():
		_finish("failed", false)
		return false
	return true

static func _has_theora_header(path: String) -> bool:
	if path.is_empty() or path.get_extension().to_lower() != "ogv" or not FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 42: return false
	var first := true
	var sequences := {}
	var ended := {}
	# 解码器会容忍掉包；预先核对CRC、各流页序与EOS，不能把坏片当完整剧情。
	while file.get_position() < file.get_length():
		var header := file.get_buffer(27)
		if header.size() != 27 or header.slice(0, 4).get_string_from_ascii() != "OggS" or header[4] != 0: return false
		var segments := file.get_buffer(header[26])
		if segments.size() != header[26]: return false
		var length := 0
		for size in segments: length += size
		var body := file.get_position()
		if body + length > file.get_length(): return false
		var payload := file.get_buffer(length)
		if first:
			if length < 42 or payload[0] != 0x80 or payload.slice(1, 7).get_string_from_ascii() != "theora": return false
			first = false
		var serial := header.decode_u32(14)
		var sequence := header.decode_u32(18)
		if not sequences.has(serial):
			if sequence != 0 or (header[5] & 2) == 0: return false
		elif ended.get(serial, false) or sequence != sequences[serial] + 1 or (header[5] & 2) != 0:
			return false
		sequences[serial] = sequence
		ended[serial] = (header[5] & 4) != 0
		var expected_crc := header.decode_u32(22)
		for index in range(22, 26): header[index] = 0
		header.append_array(segments)
		header.append_array(payload)
		if _ogg_crc(header) != expected_crc: return false
	return not ended.is_empty() and not ended.values().has(false)

static func _ogg_crc(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		for value in 256:
			var remainder := value << 24
			for bit in 8:
				remainder = ((remainder << 1) ^ (0x04c11db7 if (remainder & 0x80000000) != 0 else 0)) & 0xffffffff
			_crc_table.append(remainder)
	var checksum := 0
	for value in data:
		checksum = ((checksum << 8) & 0xffffffff) ^ _crc_table[((checksum >> 24) ^ value) & 0xff]
	return checksum

static func _theora_frame_seconds(path: String) -> float:
	# Theora规范6.2：识别包第22/26字节为大端FRN/FRD，首帧展示时刻为0。
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return 0.0
	var header := file.get_buffer(27)
	file.seek(27 + header[26] + 22)
	file.big_endian = true
	var numerator := file.get_32()
	var denominator := file.get_32()
	return float(denominator) / numerator if numerator > 0 and denominator > 0 else 0.0

func _layout() -> void:
	if _cover == null: return
	_cover.size = get_viewport().get_visible_rect().size
	var image_size := video.get_video_texture().get_size() if video.stream != null else Vector2(16, 9)
	if image_size.x <= 0 or image_size.y <= 0: image_size = Vector2(16, 9)
	var factor := minf(_cover.size.x / image_size.x, _cover.size.y / image_size.y)
	video.size = image_size * factor
	video.position = (_cover.size - video.size) * 0.5
	_hint.position = Vector2(0, _cover.size.y - 64)
	_hint.size = Vector2(_cover.size.x - 40, 36)

func _process(delta: float) -> void:
	if not _active: return
	if not Input.is_physical_key_pressed(KEY_ESCAPE): _skip_armed = true
	_elapsed += delta
	var position := video.stream_position
	_stalled = 0.0 if position > _last_position + 0.001 else _stalled + delta
	_last_position = maxf(_last_position, position)
	if _stalled > STALL_SECONDS or _elapsed > _duration + STALL_SECONDS:
		_finish("failed")

func _input(event: InputEvent) -> void:
	if not _active: return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and _skip_armed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		_finish("skipped")

func _video_finished() -> void:
	# 末帧起点距总长一视频帧，父节点又落后一UI帧；两者都取真实时长。
	_finish("completed" if _last_position + get_process_delta_time() + _frame_seconds >= _duration - 0.001 else "failed")

func abort() -> void:
	_finish("aborted", false)

func _finish(result: String, notify: bool = true) -> void:
	if not _active: return
	_active = false
	video.stop()
	hide()
	_restore_state()
	if notify: finished.emit(result)

func _pause_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		_audio_states.append({"node": weakref(node), "paused": node.stream_paused})
		node.stream_paused = true
	for child in node.get_children(): _pause_audio(child)

func _restore_state() -> void:
	if _tree != null:
		_tree.paused = _was_paused
		_tree = null
	for state in _audio_states:
		var node = state.node.get_ref()
		if is_instance_valid(node): node.stream_paused = state.paused
	_audio_states.clear()
	if _focus != null:
		var node = _focus.get_ref()
		if is_instance_valid(node) and node.is_inside_tree() and node.is_visible_in_tree(): node.grab_focus()
		_focus = null

func _exit_tree() -> void:
	_active = false
	if video != null: video.stop()
	_restore_state()
