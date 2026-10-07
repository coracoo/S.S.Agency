#!/usr/bin/env python3
"""从独立源目录生成最小运行清单；只改候选目录，保留源文件与PNG原字节。"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

CHARACTER_FIELDS = ("character_id", "identity_id", "form_id",
                    "dir", "canvas", "move_speed_mps", "run_speed_mps", "mirror_allowed", "layers",
                    "portrait_source_manifest", "status")
ANIMATION_FIELDS = ("frames", "durations_ms", "loop", "pingpong", "impact_ms", "events", "single_pose",
                    "hold_last_frame", "vertical_motion_baked", "qa_approved", "clean_body", "independent_ghost_ready")
PACKED_FIELDS = ("atlas", "atlas_size", "region", "offset")
CANVAS_FIELDS = ("w", "h", "anchor", "content_height_px", "height_m")
CONTACT_FIELDS = ("point", "width_px", "strength", "kind")
LAYER_FIELDS = ("frames", "amplitude_px", "period_s", "root_y", "full_motion_y", "z_index")
REGISTRATION_FIELDS = ("target_body_height_px", "fixed_scale", "fixed_offset", "logical_canvas", "anchor")
EFFECT_FRAME_FIELDS = ("frame", "phase", "recovery_tail", "anchor_runtime_px", "atlas_native_xywh", "nominal_duration_ms")
EFFECT_ENTRY_FIELDS = ("manifest", "approved_for_runtime", "runtime_scale", "display_size_px", "gameplay_qa_pending", "particles")
EFFECT_README = """# 透明技能帧运行资源

本目录只保存登记的运行PNG与最小帧清单。registry版本为2，以manifest_sha256校验各清单；manifest版本为1，以runtime_atlas_sha256校验图集原字节。哈希用于完整性校验，不替代游戏内视觉验收。

production_renderer_enabled保持false，gameplay_qa_pending保持true；素材批准只允许明确预览。播放使用全部登记阶段与帧顺序，atlas_native_xywh乘runtime_scale得到实际区域，anchor_runtime_px保持注册锚，nominal_duration_ms保持时长权重。
"""


def subset(value, keys):
    return {key: value[key] for key in keys if key in value}


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def resource(uri):
    if not isinstance(uri, str) or not uri.startswith("res://"):
        raise ValueError("运行资源须使用res://")
    path = uri.removeprefix("res://")
    if not path or Path(path).is_absolute() or ".." in Path(path).parts or "\\" in path:
        raise ValueError("运行资源路径越界")
    return path


def sanitize(source: Path, candidate: Path):
    source, candidate = source.resolve(), candidate.resolve()
    if source == candidate or source.is_relative_to(candidate) or candidate.is_relative_to(source):
        raise ValueError("源目录与候选目录必须独立")
    if not (source / "project.godot").is_file() or not (candidate / "project.godot").is_file():
        raise ValueError("源目录与候选目录须已有完整项目")
    writes, removed, atlas_hashes, characters, effects = {}, set(), {}, [], []

    def stage(name, value):
        writes[name] = encoded(value)

    def preserve_atlas(name):
        original, target = source / name, candidate / name
        expected = sha(original)
        if sha(target) != expected:
            raise ValueError("候选PNG字节已改变：" + name)
        atlas_hashes[name] = expected
        return expected

    paths = sorted((source / "assets/chars/pixel").glob("*/video_actions/manifest.json"))
    if len(paths) != 7:
        raise ValueError("预期七份人物运行清单")
    for path in paths:
        name = path.relative_to(source).as_posix()
        original = read(path)
        public = subset(original, CHARACTER_FIELDS)
        public["canvas"] = subset(original["canvas"], CANVAS_FIELDS)
        if "layers" in original:
            public["layers"] = [subset(layer, LAYER_FIELDS) for layer in original["layers"]]
        public["anims"] = {key: subset(value, ANIMATION_FIELDS) for key, value in original["anims"].items()}
        used = {frame for action in original["anims"].values() for frame in action["frames"]}
        public["packed_frames"] = {key: subset(value, PACKED_FIELDS) for key, value in original["packed_frames"].items() if key in used}
        if set(public["packed_frames"]) != used:
            raise ValueError("人物运行帧缺失：" + name)
        public["scene_integration"] = subset(original["scene_integration"], ("contact_metadata",))
        registration = original.get("runtime_derivative", original.get("runtime_registration"))
        if not isinstance(registration, dict) or not all(key in registration for key in REGISTRATION_FIELDS):
            raise ValueError("人物固定注册合同缺失：" + name)
        public["runtime_registration"] = subset(registration, REGISTRATION_FIELDS)
        active = {resource(frame["atlas"]) for frame in public["packed_frames"].values()}
        public["texture_groups"] = {group: [uri for uri in pages if resource(uri) in active]
                                    for group, pages in original.get("texture_groups", {}).items()}
        if {resource(uri) for pages in public["texture_groups"].values() for uri in pages} != active:
            raise ValueError("图集分组与活动页不一致：" + name)
        for atlas in active:
            preserve_atlas(atlas)
        stage(name, public)
        contact_name = resource(public["scene_integration"]["contact_metadata"])
        contacts = read(source / contact_name)
        trimmed = subset(contacts, ("schema_version", "character_id", "canvas", "anchor"))
        trimmed["frames"] = {frame: subset(contacts["frames"][frame], ("sha256", "contacts")) for frame in public["packed_frames"]}
        for frame, record in trimmed["frames"].items():
            record["contacts"] = [subset(contact, CONTACT_FIELDS) for contact in record["contacts"]]
            if record["sha256"] != atlas_hashes[resource(public["packed_frames"][frame]["atlas"])]:
                raise ValueError("人物接触点PNG哈希不符：" + frame)
        stage(contact_name, trimmed)
        allowed = {name, contact_name} | active
        allowed.update(resource(uri) for layer in public.get("layers", []) for uri in layer["frames"])
        for tres in path.parent.glob("*_sprite_frames.tres"):
            references = {resource(uri) for uri in re.findall(r'path="(res://[^"]+)"', tres.read_text())}
            if not references or not references.issubset(active):
                raise ValueError("活动SpriteFrames引用未登记图页：" + tres.name)
            allowed.add(tres.relative_to(source).as_posix())
        # 用明确运行白名单投影整个素材目录，未来新增制作旁记也不会被顺带公开。
        for root in (source, candidate):
            for item in (root / path.parent.relative_to(source)).rglob("*"):
                if item.is_file() and item.relative_to(root).as_posix() not in allowed:
                    removed.add(item.relative_to(root).as_posix())
        characters.append({"character":path.parent.parent.name, "frames":len(used), "pages":len(active),
                           "removed_frame_records":len(original["packed_frames"]) - len(used)})

    folder = source / "assets/effects/imagegen_spells"
    registry = read(folder / "registry.json")
    source_schema = registry.get("schema_version")
    if type(source_schema) is not int or source_schema not in (1, 2) or registry.get("production_renderer_enabled") is not False:
        raise ValueError("只接受仍关闭生产门禁的源registry v1/v2")
    if source_schema == 1 and registry.get("generation_route") != "image_gen.imagegen":
        raise ValueError("源素材路线不符")
    receipt_verified, integrity_verified = [], []
    public_registry = subset(registry, ("asset_root", "production_renderer_enabled"))
    public_registry["schema_version"] = 2
    public_registry["effects"] = {}
    effect_allowed = {"assets/effects/imagegen_spells/registry.json", "assets/effects/imagegen_spells/README.md"}
    for skill, entry in registry["effects"].items():
        name = resource(entry["manifest"])
        path = source / name
        manifest = read(path)
        if manifest.get("skill_id") != skill:
            raise ValueError("源技能清单不符")
        if entry.get("approved_for_runtime") is not True or entry.get("gameplay_qa_pending") is not True:
            raise ValueError("源技能批准状态改变")
        if source_schema == 1:
            if manifest.get("generator") != "image_gen.imagegen":
                raise ValueError("源技能生成路线不符")
            receipt = read(source / resource(entry["qa_receipt"]))
            if not any(item.get("skill_id") == skill and item.get("manifest_sha256") == sha(path)
                       and item.get("runtime_atlas_sha256") == manifest.get("runtime_atlas_sha256")
                       and item.get("runtime_grid_cells_match_export") is True for item in receipt.get("skills", [])):
                raise ValueError("源技能像素收据不匹配：" + skill)
            receipt_verified.append(skill)
        else:
            # 已公开源只复核现有完整性登记，不能宣称再次获得独立素材审核。
            if manifest.get("schema_version") != 1 or entry.get("manifest_sha256") != sha(path):
                raise ValueError("公开源技能清单版本或哈希不匹配：" + skill)
        atlas = resource(registry["asset_root"].rstrip("/") + "/" + manifest["runtime_atlas"])
        if preserve_atlas(atlas) != manifest["runtime_atlas_sha256"]:
            raise ValueError("源技能图集哈希不符：" + skill)
        integrity_verified.append(skill)
        public = subset(manifest, ("skill_id", "runtime_atlas", "runtime_atlas_sha256", "frame_count", "phases"))
        public["schema_version"] = 1
        public["frames"] = [subset(frame, EFFECT_FRAME_FIELDS) for frame in manifest["frames"]]
        stage(name, public)
        public_entry = subset(entry, EFFECT_ENTRY_FIELDS)
        public_entry["manifest_sha256"] = hashlib.sha256(writes[name]).hexdigest()
        public_registry["effects"][skill] = public_entry
        effect_allowed.update({name, atlas})
        effects.append({"skill":skill, "frames":len(public["frames"]), "runtime_atlas_sha256":manifest["runtime_atlas_sha256"]})
    stage("assets/effects/imagegen_spells/registry.json", public_registry)
    writes["assets/effects/imagegen_spells/README.md"] = EFFECT_README.encode("utf-8")
    for root in (source, candidate):
        for item in (root / "assets/effects/imagegen_spells").rglob("*"):
            if item.is_file() and item.relative_to(root).as_posix() not in effect_allowed:
                removed.add(item.relative_to(root).as_posix())

    for path in (source / "assets/chars/pixel").glob("*/high_detail_complete/manifest.json"):
        value = read(path)
        revision = value.pop("art_revision", None)
        if revision:
            stage(path.relative_to(source).as_posix(), value)
            if revision.get("provenance"):
                removed.add(resource(revision["provenance"]))

    # 整个计划核实后才落候选文件；永不修改独立源目录。
    for name in set(writes) | removed:
        target = candidate / name
        if not target.resolve().is_relative_to(candidate) or target.is_symlink():
            raise ValueError("候选文件链接越出目录：" + name)
        original = source / name
        if target.exists() and original.exists() and target.samefile(original):
            raise ValueError("候选文件不能与源目录共享hardlink：" + name)
    for name, data in writes.items():
        (candidate / name).write_bytes(data)
    for name in sorted(removed):
        (candidate / name).unlink(missing_ok=True)
    return {"characters":characters, "effects":effects, "changed_metadata":sorted(writes), "omitted_paths":sorted(removed),
            "atlas_sha256":dict(sorted(atlas_hashes.items())), "production_renderer_enabled":False,
            "source_registry_schema":source_schema, "source_receipts_verified":source_schema == 1,
            "source_receipt_verified_skills":sorted(receipt_verified),
            "source_integrity_verified_skills":sorted(integrity_verified), "runtime_atlas_bytes_identical":True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.resolve().is_relative_to(args.candidate.resolve()) or args.report.resolve().is_relative_to(args.source.resolve()):
        parser.error("验证报告须位于源目录与候选目录外")
    result = sanitize(args.source, args.candidate)
    args.report.write_bytes(encoded(result))
    print("RUNTIME_METADATA_SANITIZED: %d characters, %d effects, %d unchanged atlases" %
          (len(result["characters"]), len(result["effects"]), len(result["atlas_sha256"])))


if __name__ == "__main__":
    main()
