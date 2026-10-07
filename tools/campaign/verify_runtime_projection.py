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


def effect_entries(registry):
    """只展开明确登记的形态，不把同名技能的第一套图当默认值。"""
    for skill, entry in registry["effects"].items():
        if "variants" in entry:
            variants = entry["variants"]
            if skill not in ("heavy_slash", "armor_break", "sweep", "battle_spirit") or not isinstance(variants, dict) or set(variants) != {"rinne", "homura_sword"}:
                raise ValueError("共享技能形态登记无效")
            for form, variant in variants.items():
                if not isinstance(variant, dict): raise ValueError("形态条目无效")
                yield skill, form, variant
        else:
            if skill in ("heavy_slash", "armor_break", "sweep", "battle_spirit"):
                raise ValueError("共享技能不可省略形态登记")
            yield skill, "", entry


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
        for key in ("form_id", "skill_name"):
            equal(original.get(key), public.get(key), path.parent.name + ":" + key)
        if "phase_groups" in original:
            expected_groups = {phase:{key:group[key] for key in ("activation_frames", "loop_frames", "binding") if key in group}
                               for phase, group in original["phase_groups"].items()}
            equal(expected_groups, public.get("phase_groups"), path.parent.name + ":phase_groups")
        equal(original.get("required_phases"), public.get("required_phases"), path.parent.name + ":required_phases")
        if "placement" in original:
            expected_placement = {key:original["placement"][key] for key in
                                  ("cast", "travel_origin", "travel_target", "travel_mode") if key in original["placement"]}
            equal(expected_placement, public.get("placement"), path.parent.name + ":placement")
        if "visual_event_contract" in original:
            expected_contract = {key:original["visual_event_contract"][key] for key in
                                 ("id", "version", "form", "ability_id", "variant_key") if key in original["visual_event_contract"]}
            equal(expected_contract, public.get("visual_event_contract"), path.parent.name + ":visual_event_contract")
        if "reaction_layers" in original:
            expected_reactions = {name:{key:layer[key] for key in
                                  ("phase", "event_type", "requires", "lifetime", "activation_frames", "loop_frames", "target", "endpoints") if key in layer}
                                  for name, layer in original["reaction_layers"].items()}
            equal(expected_reactions, public.get("reaction_layers"), path.parent.name + ":reaction_layers")
        if "event_layers" in original:
            expected_layers = {}
            for layer_id, layer in original["event_layers"].items():
                expected = {key:layer[key] for key in ("phase", "event_type", "target", "placement", "lifetime", "status_id",
                            "positive_payload", "activation_frames", "loop_frames", "max_instances_per_action", "cue", "start_phase", "reason", "positive_actual", "requires_precision") if key in layer}
                if "phase_segments" in layer:
                    expected["phase_segments"] = [{key:segment[key] for key in ("phase", "frames", "loop_frames") if key in segment}
                                                  for segment in layer["phase_segments"]]
                if "precast_evidence" in layer:
                    expected["precast_evidence"] = {key:layer["precast_evidence"][key] for key in
                        ("schema", "source", "refinement_id", "damage_effect_index", "unique_damage_effect", "condition", "status_id", "original_target_matches")
                        if key in layer["precast_evidence"]}
                if "payload_equals" in layer:
                    expected["payload_equals"] = {key:layer["payload_equals"][key] for key in ("reason",) if key in layer["payload_equals"]}
                if "requires_event" in layer:
                    requirement = layer["requires_event"]
                    expected["requires_event"] = {key:requirement[key] for key in ("event_type", "same_action", "same_target") if key in requirement}
                    if "payload_equals" in requirement:
                        expected["requires_event"]["payload_equals"] = {key:requirement["payload_equals"][key] for key in ("reason",) if key in requirement["payload_equals"]}
                expected_layers[layer_id] = expected
            equal(expected_layers, public.get("event_layers"), path.parent.name + ":event_layers")
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
    old_entries = {(skill, form):entry for skill, form, entry in effect_entries(old_registry)}
    new_entries = {(skill, form):entry for skill, form, entry in effect_entries(new_registry)}
    equal(set(old_entries), set(new_entries), "registered variants")
    for (skill, form), entry in old_entries.items():
        for key in ("manifest", "approved_for_runtime", "runtime_scale", "display_size_px", "gameplay_qa_pending", "particles"):
            equal(entry[key], new_entries[(skill, form)][key], skill + ":" + form + ":registry:" + key)
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
