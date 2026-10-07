#!/usr/bin/env python3
"""独立比较源清单与公开投影的运行语义，可同时核对真实Godot加载结果。"""
import argparse
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(source, candidate, before=None, after=None):
    comparisons = 0
    pages = set()
    animation_count = frame_count = duration_count = events = contacts = 0

    def equal(left, right, label):
        nonlocal comparisons
        if left != right:
            raise ValueError("运行投影改变：" + label)
        comparisons += 1

    for path in sorted(source.glob("assets/chars/pixel/*/video_actions/manifest.json")):
        name = path.relative_to(source)
        original, public = read(path), read(candidate / name)
        for key in ("character_id", "identity_id", "form_id", "dir", "move_speed_mps", "run_speed_mps",
                    "mirror_allowed", "portrait_source_manifest", "scene_integration", "status"):
            equal(original.get(key), public.get(key), str(name) + ":" + key)
        for key in ("w", "h", "anchor", "content_height_px", "height_m"):
            equal(original["canvas"][key], public["canvas"][key], str(name) + ":canvas:" + key)
        layer_fields = ("frames", "amplitude_px", "period_s", "root_y", "full_motion_y", "z_index")
        equal([{key:layer[key] for key in layer_fields if key in layer} for layer in original.get("layers", [])],
              public.get("layers", []), str(name) + ":layers")
        equal(set(original["anims"]), set(public["anims"]), str(name) + ":anims")
        animation_count += len(original["anims"])
        used = {frame for action in original["anims"].values() for frame in action["frames"]}
        frame_count += len(used)
        equal(used, set(public["packed_frames"]), str(name) + ":packed_frames")
        for action, spec in original["anims"].items():
            for key in ("frames", "durations_ms", "loop", "pingpong", "impact_ms", "events", "single_pose",
                        "hold_last_frame", "vertical_motion_baked", "qa_approved", "clean_body", "independent_ghost_ready"):
                equal(spec.get(key), public["anims"][action].get(key), str(name) + ":" + action + ":" + key)
            duration_count += len(spec["durations_ms"])
            events += len(spec.get("events", {}))
        for frame in used:
            for key in ("atlas", "atlas_size", "region", "offset"):
                equal(original["packed_frames"][frame][key], public["packed_frames"][frame][key], frame + ":" + key)
            pages.add(public["packed_frames"][frame]["atlas"].removeprefix("res://"))
        registration = original.get("runtime_derivative", original.get("runtime_registration", {}))
        for key in ("target_body_height_px", "fixed_scale", "fixed_offset", "logical_canvas", "anchor"):
            equal(registration[key], public["runtime_registration"][key], str(name) + ":registration:" + key)
        old_contacts = read(source / original["scene_integration"]["contact_metadata"].removeprefix("res://"))
        new_contacts = read(candidate / public["scene_integration"]["contact_metadata"].removeprefix("res://"))
        for key in ("character_id", "canvas", "anchor"):
            equal(old_contacts[key], new_contacts[key], str(name) + ":contacts:" + key)
        for frame in used:
            record = old_contacts["frames"][frame]
            runtime_record = {"sha256":record["sha256"], "contacts":[{key:contact[key] for key in
                              ("point", "width_px", "strength", "kind") if key in contact} for contact in record["contacts"]]}
            equal(runtime_record, new_contacts["frames"][frame], str(name) + ":contacts:" + frame)
            contacts += 1
    effect_frames = 0
    for path in sorted(source.glob("assets/effects/imagegen_spells/*/manifest.json")):
        original, public = read(path), read(candidate / path.relative_to(source))
        for key in ("skill_id", "runtime_atlas", "runtime_atlas_sha256", "frame_count", "phases"):
            equal(original[key], public[key], path.parent.name + ":" + key)
        equal(len(original["frames"]), len(public["frames"]), path.parent.name + ":frame_count")
        effect_frames += len(public["frames"])
        for old_frame, new_frame in zip(original["frames"], public["frames"]):
            for key in ("frame", "phase", "recovery_tail", "anchor_runtime_px", "atlas_native_xywh", "nominal_duration_ms"):
                equal(old_frame[key], new_frame[key], path.parent.name + ":frame:" + key)
        pages.add("assets/effects/imagegen_spells/" + public["runtime_atlas"])
    for name in sorted(pages):
        equal(sha(source / name), sha(candidate / name), name + ":PNG")
    old_registry = read(source / "assets/effects/imagegen_spells/registry.json")
    new_registry = read(candidate / "assets/effects/imagegen_spells/registry.json")
    if old_registry.get("production_renderer_enabled") is not False or new_registry.get("production_renderer_enabled") is not False:
        raise ValueError("生产门禁必须保持关闭")
    equal(set(old_registry["effects"]), set(new_registry["effects"]), "registered effects")
    for skill, entry in old_registry["effects"].items():
        for key in ("approved_for_runtime", "runtime_scale", "display_size_px", "gameplay_qa_pending", "particles"):
            equal(entry[key], new_registry["effects"][skill][key], skill + ":registry:" + key)
    if before is not None:
        equal(read(before), read(after), "Godot真实运行投影")
    return {"passed":True, "exact_comparisons":comparisons, "character_unique_frames":frame_count,
            "animations":animation_count, "duration_values":duration_count, "event_markers":events,
            "contact_records":contacts, "unchanged_atlases":len(pages), "effect_frames":effect_frames,
            "godot_runtime_projections_equal":True if before is not None else None, "production_renderer_enabled":False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--before", type=Path)
    parser.add_argument("--after", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    if (args.before is None) != (args.after is None):
        parser.error("before与after必须成对提供")
    if any(args.report.resolve().is_relative_to(root.resolve()) for root in (args.source, args.candidate)):
        parser.error("报告必须位于项目外")
    result = verify(args.source.resolve(), args.candidate.resolve(), args.before, args.after)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("RUNTIME_PROJECTION_EQUAL:", result["exact_comparisons"], "comparisons")


if __name__ == "__main__":
    main()
