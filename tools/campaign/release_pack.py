#!/usr/bin/env python3
"""核对官方Godot PCK，并追加FileAccess必需的原始素材字节。

Godot include_filter不会保留已导入资源的源PNG。此工具仅支持未加密的
独立PCK v2/v3/v4；保留官方导出内容，追加源文件与完整目录，再核验每条MD5。
布局依据官方Godot 4.7.2 core/io/file_access_pack.cpp；不重新编译脚本或改import。
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

PROJECT = Path(__file__).resolve().parents[2]


def _read(stream, size):
    data = stream.read(size)
    if len(data) != size:
        raise ValueError("截断PCK")
    return data


def read_pack(pack):
    entries = {}
    size = pack.stat().st_size
    with pack.open("rb") as stream:
        magic, version, major, minor, patch, flags, base = struct.unpack("<6IQ", _read(stream, 32))
        if magic != 0x43504447 or version not in (2, 3, 4) or flags & 5:
            raise ValueError("仅支持未加密、非sparse的独立Godot PCK v2/v3/v4")
        if version in (3, 4):
            directory, = struct.unpack("<Q", _read(stream, 8))
            stream.seek(directory)
        else:
            _read(stream, 64)
        count, = struct.unpack("<I", _read(stream, 4))
        if count > 100000:
            raise ValueError("异常PCK目录计数")
        for _ in range(count):
            length, = struct.unpack("<I", _read(stream, 4))
            if length > 65536:
                raise ValueError("异常PCK路径长度")
            name = _read(stream, length).rstrip(b"\0").decode("utf-8").removeprefix("res://")
            offset, length = struct.unpack("<QQ", _read(stream, 16))
            md5 = _read(stream, 16).hex()
            file_flags, = struct.unpack("<I", _read(stream, 4))
            if not name or name in entries or name.startswith("/") or ".." in Path(name).parts or file_flags or base + offset + length > size:
                raise ValueError("异常/重复/加密PCK条目：" + name)
            entries[name] = {"offset": base + offset, "size": length, "md5": md5, "flags": file_flags}
    return entries


def read_entry(pack, entry):
    with pack.open("rb") as stream:
        stream.seek(entry["offset"])
        return _read(stream, entry["size"])


def verify_entries(pack, entries):
    return ["PCK条目MD5不符：" + name for name, entry in entries.items()
            if hashlib.md5(read_entry(pack, entry)).hexdigest() != entry["md5"]]


def append_originals(pack, sources):
    entries = read_pack(pack)
    failures = verify_entries(pack, entries)
    if failures:
        raise ValueError(str(failures))
    pending = {}
    for name, source in sorted(sources.items()):
        data = source.read_bytes()
        if name in entries:
            if read_entry(pack, entries[name]) != data:
                raise ValueError("已有PCK原始文件不同：" + name)
        else:
            pending[name] = data
    if not pending:
        return
    _write_directory(pack, entries, pending)


def _write_directory(pack, entries, pending):
    # 官方4.7.2导出v4；非加密独立v3/v4共用目录偏移，v2只读/校验。
    with pack.open("r+b") as stream:
        stream.seek(4)
        version, = struct.unpack("<I", _read(stream, 4))
        if version not in (3, 4):
            raise ValueError("追加原始文件只支持官方非加密独立v3/v4包")
        stream.seek(24)
        base, = struct.unpack("<Q", _read(stream, 8))
        stream.seek(0, 2)
        for name, data in pending.items():
            entries[name] = {"offset": stream.tell(), "size": len(data), "md5": hashlib.md5(data).hexdigest(), "flags": 0}
            stream.write(data)
        directory = stream.tell()
        stream.write(struct.pack("<I", len(entries)))
        for name, entry in sorted(entries.items()):
            encoded = name.encode("utf-8")
            encoded += bytes((-len(encoded)) % 4)
            stream.write(struct.pack("<I", len(encoded)))
            stream.write(encoded)
            stream.write(struct.pack("<QQ", entry["offset"] - base, entry["size"]))
            stream.write(bytes.fromhex(entry["md5"]))
            stream.write(struct.pack("<I", entry["flags"]))
        stream.seek(32)
        stream.write(struct.pack("<Q", directory))
    if verify_entries(pack, read_pack(pack)):
        raise ValueError("追加后PCK校验失败")


def packed_target(path, paths):
    logical = path.removeprefix("res://")
    return logical in paths or logical + ".remap" in paths or logical + ".import" in paths


def filter_class_cache(text, paths):
    blocks = re.findall(r"\{[^{}]*\}", text)
    retained = []
    for block in blocks:
        match = re.search(r'"path"\s*:\s*"([^"]+)"', block)
        if not match:
            raise ValueError("无法解析官方class缓存条目")
        if packed_target(match.group(1), paths):
            retained.append(block)
    return "list=[" + ", ".join(retained) + "]\n"


def uid_entries(data):
    # 官方4.6 resource_uid.cpp: uint32 count，然后uint64 ID/uint32 pathlen/UTF8。
    if len(data) < 4:
        raise ValueError("截断UID缓存")
    count, = struct.unpack_from("<I", data)
    offset = 4
    result = []
    for _ in range(count):
        if offset + 12 > len(data):
            raise ValueError("截断UID缓存条目")
        uid, length = struct.unpack_from("<QI", data, offset)
        offset += 12
        if offset + length > len(data):
            raise ValueError("截断UID缓存路径")
        result.append((uid, data[offset:offset + length].decode("utf-8")))
        offset += length
    if offset != len(data):
        raise ValueError("UID缓存异常尾部")
    return result


def filter_uid_cache(data, paths):
    retained = [(uid, path) for uid, path in uid_entries(data) if packed_target(path, paths)]
    return struct.pack("<I", len(retained)) + b"".join(struct.pack("<QI", uid, len(path.encode("utf-8"))) + path.encode("utf-8") for uid, path in retained)


def filter_pack_caches(pack):
    entries = read_pack(pack)
    paths = set(entries)
    updates = {}
    report = {}
    for name in (".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin"):
        if name not in entries:
            continue
        original = read_entry(pack, entries[name])
        filtered = (filter_class_cache(original.decode("utf-8"), paths).encode("utf-8")
                    if name.endswith(".cfg") else filter_uid_cache(original, paths))
        report[name] = {"original_sha256": hashlib.sha256(original).hexdigest(), "filtered_sha256": hashlib.sha256(filtered).hexdigest(),
                        "original_bytes": len(original), "filtered_bytes": len(filtered)}
        if filtered != original:
            updates[name] = filtered
    if updates:
        # 只重写这两份Godot生成索引；编译脚本、素材与source/import都保持官方字节。
        _write_directory(pack, entries, updates)
    return report


def audit_paths(paths, required):
    failures = ["缺少发布依赖：" + path for path in sorted(required - paths)]
    for path in sorted(paths):
        private_record = (any(token in Path(path).name for token in ("provenance", "qa_acceptance", "recovery_validation"))
                          or "art_revisions" in Path(path).parts
                          or any(part.startswith(("frozen_", "original_runtime_")) for part in Path(path).parts))
        if private_record or path.startswith(("tools/", "docs/", "admin/", "archive/", "old/", "config/", ".git/", ".agents/", ".codex/", "build/", "screenshots/", "evidence/", "captures/")) or "/source/" in path or "_raw_" in path or path.endswith((".xlsx", ".blend", ".blend1", ".md")):
            failures.append("开发/源稿内容误入发布包：" + path)
    return failures


def video_action_sources(project):
    """保留活动视频图集及运行元数据，不递归打包原片/逐帧缓存。"""
    def source_path(uri):
        if not isinstance(uri, str) or not uri.startswith("res://"):
            raise ValueError("视频资源必须使用res://路径")
        name = uri.removeprefix("res://")
        if not name or "\\" in name or Path(name).is_absolute() or ".." in Path(name).parts:
            raise ValueError("视频资源路径不能越出项目：" + uri)
        return name

    sources = set()
    for path in sorted((project / "assets/chars/pixel").glob("*/video_actions/manifest.json")):
        manifest = json.loads(path.read_text())
        sources.add(path.relative_to(project).as_posix())
        packed = manifest.get("packed_frames", {})
        for animation in manifest["anims"].values():
            for frame in animation["frames"]:
                if frame not in packed or not packed[frame].get("atlas"):
                    raise ValueError("活动视频帧缺少图集登记：" + frame)
                sources.add(source_path(packed[frame]["atlas"]))
        uri = manifest.get("scene_integration", {}).get("contact_metadata")
        if uri:
            sources.add(source_path(uri))
    return sources


def imagegen_effect_sources(project):
    """生图清单的运行闭包：registry、最小帧描述与原PNG，不携带制作收据。"""
    folder = project / "assets/effects/imagegen_spells"
    registry_path = folder / "registry.json"
    if not registry_path.is_file():
        return set()
    registry = json.loads(registry_path.read_text())
    if registry.get("schema_version") != 2 or registry.get("asset_root") != "res://assets/effects/imagegen_spells":
        raise ValueError("生图运行registry版本或根目录无效")
    sources = {registry_path.relative_to(project).as_posix()}
    for skill, entry in registry["effects"].items():
        expected = "res://assets/effects/imagegen_spells/" + skill + "/manifest.json"
        if not re.fullmatch(r"[a-z][a-z0-9_]*", skill) or entry.get("manifest") != expected:
            raise ValueError("生图清单路径非法")
        path = project / expected.removeprefix("res://")
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry.get("manifest_sha256"):
            raise ValueError("生图运行清单哈希不符：" + skill)
        manifest = json.loads(path.read_text())
        atlas = manifest.get("runtime_atlas", "")
        if manifest.get("schema_version") != 1 or manifest.get("skill_id") != skill or not isinstance(atlas, str) or len(Path(atlas).parts) != 2 or Path(atlas).parts[0] != skill or Path(atlas).suffix != ".png" or "\\" in atlas or ".." in Path(atlas).parts:
            raise ValueError("生图运行图集路径或版本非法")
        atlas_path = folder / atlas
        if hashlib.sha256(atlas_path.read_bytes()).hexdigest() != manifest.get("runtime_atlas_sha256"):
            raise ValueError("生图运行图集哈希不符：" + skill)
        sources.update({path.relative_to(project).as_posix(), atlas_path.relative_to(project).as_posix()})
    return sources


def spell_effect_sources(project):
    """只保留登记的透明技能成品；loader读取原PNG，不依赖导入缓存。"""
    folder = project / "assets/effects/illustrated_spells"
    manifest = folder / "manifest.json"
    if not manifest.is_file():
        return set()
    sources = {manifest.relative_to(project).as_posix()}
    for action in json.loads(manifest.read_text())["actions"].values():
        name = action["file"]
        if Path(name).name != name or not name.endswith(".png"):
            raise ValueError("法术图集必须是登记目录下的PNG：" + name)
        sources.add((folder / name).relative_to(project).as_posix())
    return sources


def formal_dependencies(project=PROJECT):
    """正式可调用路径与解析依赖分开；旧profile URI不等同资源硬依赖。"""
    sources = set()
    resources = {"scenes/campaign/title.tscn", "scenes/campaign/ending.tscn", "scenes/rpg/battle.tscn",
                 "scenes/campaign/saga.tscn", "scenes/campaign/saga_ending.tscn",
                 *(f"scenes/campaign/night_{night}.tscn" for night in range(1, 6)),
                 "scenes/preview/act01_approach_3d.tscn", "assets/3d/act01_approach/act01_approach.glb",
                 "assets/fonts/Alibaba-PuHuiTi-Regular.ttf", "assets/chars/portraits/sayo_half.png"}
    npc_manifest = project / "assets/chars/npcs/act_one/asset_manifest.json"
    if npc_manifest.is_file():
        sources.add(npc_manifest.relative_to(project).as_posix())
    saga_npcs = project / "assets/chars/npcs/saga/asset_manifest.json"
    if saga_npcs.is_file():
        sources.add(saga_npcs.relative_to(project).as_posix())
        npc_data = json.loads(saga_npcs.read_text())
        # NPC图集由PNG原字节解码；只纳入manifest明确登记的成品，不递归预览/原稿。
        for character in npc_data["characters"].values():
            sources.add(character["sheet"].removeprefix("res://"))
    saga_enemies = project / "assets/chars/enemies/saga/asset_manifest.json"
    if saga_enemies.is_file():
        sources.add(saga_enemies.relative_to(project).as_posix())
        enemy_data = json.loads(saga_enemies.read_text())
        for enemy in enemy_data["enemies"].values():
            sources.add(enemy["sheet"].removeprefix("res://"))
    # NightMenuArt按ROOT + id动态读原PNG；只收批准目录的直接成品，不递归原稿或整个UI树。
    menu_pngs = {path.relative_to(project).as_posix()
                 for path in (project / "assets/ui/night_menu").glob("*.png") if path.is_file()}
    sources.update(menu_pngs)
    resources.update(menu_pngs)
    # 主线人物provider使用七形态首帧；旧对白portrait URI无需把旧半身/旧候选发包。
    sources.update({"data/dialogues.json", "data/cases/night_patrol.json", "data/ui_theme.json",
                    "data/exploration_3d/approach.json", "assets/ui/panel_washi_9slice.png",
                    "assets/chars/portraits/sayo_half.png", "assets/chars/pixel/roster.json",
                    "assets/chars/pixel/high_detail_roster.json", "assets/chars/enemies/current/asset_manifest.json",
                    "assets/3d/act01_approach/act01_approach.glb", "assets/fonts/Alibaba-PuHuiTi-Regular.ttf"})
    sources.update(path.relative_to(project).as_posix() for path in (project / "data/rpg").glob("*.json"))
    sources.update(spell_effect_sources(project))
    sources.update(imagegen_effect_sources(project))
    sources.update(video_action_sources(project))
    for stage in ("test_approach", "corridor_act", "night3_procession", "night4_mirror", "honden_act"):
        sources.add("data/clues/" + stage + ".json")
    presentation = json.loads((project / "data/rpg/presentation.json").read_text())
    sources.add(presentation["fallback_background"].removeprefix("res://"))
    sources.update(path.removeprefix("res://") for path in presentation["night_backgrounds"].values())
    sources.update(path.removeprefix("res://") for path in presentation["enemy_art"].values())
    sources.update(value["badge"].removeprefix("res://") for value in presentation["class_art"].values())
    sources.update(path.relative_to(project).as_posix() for path in (project / "assets/audio").rglob("*.mp3"))
    profile = "data/characters/scene_integration/dusk_illustration.json"
    sources.add(profile)
    resources.add(json.loads((project / profile).read_text())["character_shader"].removeprefix("res://"))
    for manifest_path in sorted((project / "assets/chars/pixel").glob("*/high_detail_complete/manifest.json")):
        sources.add(manifest_path.relative_to(project).as_posix())
        manifest = json.loads(manifest_path.read_text())
        for animation in manifest["anims"].values():
            sources.update((manifest["dir"] + frame + ".png").removeprefix("res://") for frame in animation["frames"])
        for layer in manifest.get("layers", []):
            sources.update(path.removeprefix("res://") for path in layer["frames"])
        contact = manifest.get("scene_integration", {}).get("contact_metadata")
        if contact:
            sources.add(contact.removeprefix("res://"))
    # 静态preload/extends与主线可用脚本的load依赖闭包。场景URI兼容fallback不扩展。
    scripts = {path.relative_to(project).as_posix(): path.read_text() for path in (project / "scripts").rglob("*.gd")}
    classes = {match.group(1): name for name, text in scripts.items() if (match := re.search(r"^class_name\s+(\w+)", text, re.M))}
    todo = list(resources)
    examined = set()
    while todo:
        name = todo.pop()
        if name in examined:
            continue
        examined.add(name)
        if Path(name).suffix not in (".gd", ".tscn"):
            continue
        text = (project / name).read_text()
        targets = set(re.findall(r"res://([^\s\"'\)\]\},;]+)", text))
        for target in targets:
            if target.startswith("data/") and target.endswith(".json") and (project / target).is_file():
                sources.add(target)
            if (project / target).is_file() and Path(target).suffix in (".gd", ".gdshader"):
                if target not in resources:
                    resources.add(target)
                    todo.append(target)
            elif (project / target).is_file() and Path(target).suffix in (".glb", ".png", ".ttf", ".svg", ".tres", ".material"):
                # resources选择导出不保证隐式携带脚本中的图像preload，必须明确列根。
                # 只采集实际load/preload调用与tscn外部资源，避免把注释/历史URI当活跃依赖。
                static_calls = set(re.findall(r"(?:preload|load)\s*\(\s*[\"']res://([^\"']+)[\"']", text))
                if name.endswith(".tscn") or target in static_calls:
                    resources.add(target)
        if name.endswith(".gd"):
            code = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
            for symbol, target in classes.items():
                if re.search(r"\b" + symbol + r"\b", code) and target not in resources:
                    resources.add(target)
                    todo.append(target)
    missing = [path for path in sources | resources if not (project / path).is_file()]
    if missing:
        raise ValueError("正式依赖不存在：" + str(missing))
    return {name: project / name for name in sorted(sources)}, sorted(resources)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--append-originals", action="store_true")
    parser.add_argument("--configure-export", action="store_true", help="按正式roots写入resources导出选择与JSON精确include")
    args = parser.parse_args()
    pack, output = args.pack.resolve(), args.output_dir.resolve()
    if output.is_relative_to(PROJECT):
        parser.error("发布证据必须位于仓库外")
    output.mkdir(parents=True, exist_ok=True)
    sources, resources = formal_dependencies()
    if args.configure_export:
        preset = PROJECT / "export_presets.cfg"
        text = preset.read_text()
        text = re.sub(r'export_filter="[^"]*"', 'export_filter="resources"', text)
        text = re.sub(r'^export_files=.*\n', '', text, flags=re.M)
        text = text.replace('export_filter="resources"', 'export_filter="resources"\nexport_files=PackedStringArray(' + ', '.join(json.dumps("res://" + path) for path in resources) + ')')
        text = re.sub(r'include_filter="[^"]*"', 'include_filter="' + ', '.join(path for path in sources if path.endswith(".json")) + '"', text)
        preset.write_text(text)
        (output / "formal-dependencies.json").write_text(json.dumps({"sources": sorted(sources), "resource_roots": resources}, ensure_ascii=False, indent=2) + "\n")
        print(f"FORMAL EXPORT: {len(resources)} explicit resources, {len(sources)} original dependencies")
        return 0
    if args.append_originals:
        append_originals(pack, sources)
        cache_report = filter_pack_caches(pack)
        (output / "generated-cache-audit.json").write_text(json.dumps(cache_report, indent=2) + "\n")
    entries = read_pack(pack)
    failures = verify_entries(pack, entries) + audit_paths(set(entries), set(sources))
    classes = read_entry(pack, entries[".godot/global_script_class_cache.cfg"]).decode("utf-8")
    for path in re.findall(r'"path"\s*:\s*"([^"]+)"', classes):
        if not packed_target(path, entries): failures.append("悬空class_name缓存路径：" + path)
    for uid, path in uid_entries(read_entry(pack, entries[".godot/uid_cache.bin"])):
        if not packed_target(path, entries): failures.append("悬空UID缓存路径：" + str(uid) + ":" + path)
    for path in entries:
        if path.startswith(("scenes/v3/", "scenes/exploration_3d/", "scenes/rpg/launcher.", "scenes/preview/friendly_")) or "/atlases/" in path:
            failures.append("历史入口/未使用atlas误入包：" + path)
        if path.startswith(".godot/imported/") and "high_detail_complete" in path:
            failures.append("FileAccess逐帧不应重复携带导入纹理：" + path)
    # ctex文件名没有原目录名；必须解析逐帧的import元数据核对实际缓存路径。
    for name, source in sources.items():
        if "/high_detail_complete/frames/" not in name or not name.endswith(".png"):
            continue
        metadata = Path(str(source) + ".import")
        if metadata.is_file():
            for imported in re.findall(r"res://([^\"\s]+\.ctex)", metadata.read_text()):
                if imported in entries:
                    failures.append("七形态原帧重复携带ctex：" + name + " -> " + imported)
    source_hashes = {}
    for name, source in sources.items():
        expected = hashlib.sha256(source.read_bytes()).hexdigest()
        source_hashes[name] = expected
        if name in entries and hashlib.sha256(read_entry(pack, entries[name])).hexdigest() != expected:
            failures.append("原始素材SHA256与开发源不符：" + name)
    report = {"generated_utc": datetime.now(timezone.utc).isoformat(), "pack": str(pack),
              "sha256": hashlib.sha256(pack.read_bytes()).hexdigest(), "size_bytes": pack.stat().st_size,
              "entry_count": len(entries), "required_original_count": len(sources), "source_sha256": source_hashes,
              "failures": failures, "status": "pass" if not failures else "fail", "entries": entries}
    (output / "pack-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    (output / "pack-files.txt").write_text("\n".join(sorted(entries)) + "\n")
    print(f"PCK AUDIT: {report['status']}; entries={len(entries)}; originals={len(sources)}; size={pack.stat().st_size}; failures={len(failures)}")
    for failure in failures:
        print("FAIL:", failure)
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
