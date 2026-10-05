extends RefCounted
## 仅源码开发兼容：原资源优先，已归档的旧角色URI才映射到old；正式PCK不含old。
const ROOT := "res://assets/chars/"
const ARCHIVE := "res://old/characters/assets/chars/"
const PREFIXES := ["anims/", "rinne_25d/", "pixel/rinne/frames/", "pixel/rinne/frame_material_refined/", "pixel/rinne/layers/", "pixel/guard/high_detail_pilot/"]
const FILES := ["pixel/rinne/manifest.json", "rinne_idle.png", "hakuyo_idle.png", "enemy_kanju.png", "enemy_paper_doll.png", "enemy_paper_doll_echo.png"]

static func resolve(path: String) -> String:
	if not path.begins_with(ROOT) or FileAccess.file_exists(path) or ResourceLoader.exists(path): return path
	var relative := path.trim_prefix(ROOT)
	var retired := relative in FILES
	for prefix in PREFIXES:
		if relative.begins_with(prefix): retired = true
	if retired and FileAccess.file_exists(ARCHIVE + relative): return ARCHIVE + relative
	return path
