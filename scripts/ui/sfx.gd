class_name Sfx
extends RefCounted
## 音效快捷播放（绕过 .import，直接文件加载；v2 已有 mp3 映射复用）。
## 用法: Sfx.play(self, "card_play")

const MAP := {
	"card_play": "res://assets/audio/sfx/sfx_card_play.mp3",
	"fire_ignite": "res://assets/audio/sfx/sfx_fire_ignite.mp3",
	"explosion": "res://assets/audio/sfx/sfx_explosion.mp3",
	"bell": "res://assets/audio/sfx/sfx_bell.mp3",
	"seal": "res://assets/audio/sfx/sfx_seal.mp3",
	"hurt": "res://assets/audio/sfx/sfx_unit_hurt.mp3",
	"turn_end": "res://assets/audio/sfx/sfx_turn_end.mp3",
	"door": "res://assets/audio/sfx/sfx_door.mp3",
	"pickup": "res://assets/audio/sfx/sfx_pickup.mp3",
	"push": "res://assets/audio/sfx/sfx_push.mp3",
}

static func play(node: Node, key: String, volume_db := -8.0) -> void:
	var path: String = MAP.get(key, "")
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[Sfx] 加载失败: %s" % path)
		return
	var stream := AudioStreamMP3.new()
	stream.data = f.get_buffer(f.get_length())
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	node.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
