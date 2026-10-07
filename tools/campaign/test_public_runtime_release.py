"""运行素材公开合同：只发布活动资源、运行字段及成品完整性哈希。"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("release_pack.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
STRICT_CANDIDATE = os.environ.get("PUBLIC_RUNTIME_CANDIDATE") == "1"


def export_selections():
    """读取实际导出选择；原PNG还会由release_pack的依赖闭包追加。"""
    text = (ROOT / "export_presets.cfg").read_text()
    selected = set()
    for values in re.findall(r'^export_files=PackedStringArray\((.*)\)$', text, re.M):
        selected.update(path.removeprefix("res://") for path in re.findall(r'"([^"]+)"', values))
    for values in re.findall(r'^include_filter="([^"]*)"$', text, re.M):
        selected.update(path.strip().removeprefix("res://") for path in values.split(",") if path.strip())
    return selected


class PublicRuntimeRelease(unittest.TestCase):
    def test_character_manifests_expose_only_runtime_contract(self):
        allowed = {"character_id", "identity_id", "form_id",
                   "dir", "canvas", "move_speed_mps", "run_speed_mps", "mirror_allowed", "anims",
                   "packed_frames", "layers", "portrait_source_manifest", "scene_integration", "status",
                   "runtime_registration", "texture_groups"}
        animation_fields = {"frames", "durations_ms", "loop", "pingpong", "impact_ms", "events",
                            "single_pose", "hold_last_frame", "vertical_motion_baked", "qa_approved",
                            "clean_body", "independent_ghost_ready"}
        paths = list((ROOT / "assets/chars/pixel").glob("*/video_actions/manifest.json"))
        self.assertEqual(7, len(paths))
        released = release.video_action_sources(ROOT)
        selected = export_selections()
        for path in paths:
            with self.subTest(character=path.parent.parent.name):
                value = json.loads(path.read_text())
                self.assertFalse(set(value) - allowed)
                used = {name for action in value["anims"].values() for name in action["frames"]}
                self.assertEqual(used, set(value["packed_frames"]))
                for action in value["anims"].values():
                    self.assertFalse(set(action) - animation_fields)
                for frame in value["packed_frames"].values():
                    self.assertEqual({"atlas", "atlas_size", "region", "offset"}, set(frame))
                pages = {frame["atlas"].removeprefix("res://") for frame in value["packed_frames"].values()}
                physical = {p.relative_to(ROOT).as_posix() for p in (path.parent / "sheets").glob("*.png")}
                prefix = path.parent.relative_to(ROOT).as_posix() + "/"
                self.assertTrue(pages <= physical, "开发树可保留原稿，但不能缺活动图页")
                self.assertEqual(pages, {name for name in released if name.startswith(prefix + "sheets/")})
                self.assertTrue({name for name in selected if name.startswith(prefix) and name.endswith(".png")} <= pages,
                                "导出选择不能携带历史或未使用图页")
                if STRICT_CANDIDATE:
                    self.assertEqual(pages, physical, "已投影的公开候选只保留活动图页")
                    allowed_files = pages | {path.relative_to(ROOT).as_posix(), prefix + "contacts.json"}
                    allowed_files.update(p.relative_to(ROOT).as_posix() for p in path.parent.glob("*_sprite_frames.tres"))
                    self.assertEqual(allowed_files, {p.relative_to(ROOT).as_posix() for p in path.parent.rglob("*") if p.is_file()},
                                     "公开候选不能残留制作旁记或历史副本")
                contacts = json.loads((path.parent / "contacts.json").read_text())
                self.assertEqual(used, set(contacts["frames"]))
                self.assertFalse(set(contacts) - {"schema_version", "character_id", "canvas", "anchor", "frames"})

    def test_imagegen_metadata_pins_runtime_bytes_without_source_receipt(self):
        folder = ROOT / "assets/effects/imagegen_spells"
        registry = json.loads((folder / "registry.json").read_text())
        self.assertEqual(2, registry["schema_version"])
        self.assertIs(registry["production_renderer_enabled"], False)
        released = release.imagegen_effect_sources(ROOT)
        self.assertNotIn("assets/effects/imagegen_spells/qa_acceptance.json", released)
        if STRICT_CANDIDATE:
            self.assertEqual(released | {"assets/effects/imagegen_spells/README.md"},
                             {p.relative_to(ROOT).as_posix() for p in folder.rglob("*") if p.is_file()},
                             "公开候选只含登记的技能运行文件，私有QA可留开发树")
        for skill, form, entry in release.imagegen_effect_entries(registry):
            with self.subTest(skill=skill):
                path = ROOT / entry["manifest"].removeprefix("res://")
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), entry["manifest_sha256"])
                value = json.loads(path.read_text())
                required_fields = {"schema_version", "skill_id", "runtime_atlas", "runtime_atlas_sha256", "frame_count", "frames", "phases"}
                self.assertTrue(required_fields <= set(value))
                self.assertFalse(set(value) - required_fields - {"required_phases", "placement", "event_layers", "form_id", "skill_name", "phase_groups", "visual_event_contract", "reaction_layers"})
                for group in value.get("phase_groups", {}).values():
                    self.assertEqual({"activation_frames", "loop_frames", "binding"}, set(group))
                    self.assertEqual("physical_skill_visual_v1" if "visual_event_contract" in value else "unbound", group["binding"])
                for layer in value.get("event_layers", {}).values():
                    self.assertFalse(set(layer) - {"phase", "event_type", "target", "placement", "lifetime", "status_id", "positive_payload", "activation_frames", "loop_frames", "max_instances_per_action", "payload_equals", "requires_event", "cue", "start_phase", "reason", "positive_actual", "requires_precision", "precast_evidence", "phase_segments"})
                    self.assertFalse(set(layer.get("precast_evidence", {})) - {"schema", "source", "refinement_id", "damage_effect_index", "unique_damage_effect", "condition", "status_id", "original_target_matches"})
                    for segment in layer.get("phase_segments", []):
                        self.assertFalse(set(segment) - {"phase", "frames", "loop_frames"})
                    self.assertFalse(set(layer.get("payload_equals", {})) - {"reason"})
                    requirement = layer.get("requires_event", {})
                    self.assertFalse(set(requirement) - {"event_type", "same_action", "same_target", "payload_equals"})
                    self.assertFalse(set(requirement.get("payload_equals", {})) - {"reason"})
                if "visual_event_contract" in value:
                    self.assertEqual({"id", "version", "form", "ability_id", "variant_key"}, set(value["visual_event_contract"]))
                for layer in value.get("reaction_layers", {}).values():
                    self.assertEqual({"phase", "event_type", "requires", "lifetime", "activation_frames", "loop_frames", "target", "endpoints"}, set(layer))
                self.assertFalse(set(value.get("placement", {})) - {"cast", "travel_origin", "travel_target", "travel_mode"})
                self.assertIs(entry["approved_for_runtime"], True)
                self.assertIs(entry["gameplay_qa_pending"], True)
                for frame in value["frames"]:
                    self.assertEqual({"frame", "phase", "recovery_tail", "anchor_runtime_px", "atlas_native_xywh", "nominal_duration_ms"}, set(frame))
                atlas = folder / value["runtime_atlas"]
                self.assertEqual(hashlib.sha256(atlas.read_bytes()).hexdigest(), value["runtime_atlas_sha256"])

    def test_release_never_bundles_production_records(self):
        originals, resources = release.formal_dependencies()
        published = set(originals) | set(resources) | export_selections()
        self.assertFalse(any("provenance" in name or "art_revisions" in name or "qa_acceptance" in name or "recovery_validation" in name
                             or any(part.startswith(("frozen_", "original_runtime_")) for part in Path(name).parts) for name in published))
        self.assertIn("assets/effects/imagegen_spells/registry.json", originals)
        self.assertIn("scripts/rpg/ui/physical_skill_visual_event_policy.gd", resources)
        self.assertIn("scripts/rpg/dual_form.gd", resources)
        folder = ROOT / "assets/effects/imagegen_spells"
        registry = json.loads((folder / "registry.json").read_text())
        expected = {"assets/effects/imagegen_spells/registry.json"}
        for _, _, entry in release.imagegen_effect_entries(registry):
            manifest_path = entry["manifest"].removeprefix("res://")
            manifest = json.loads((ROOT / manifest_path).read_text())
            expected.update({manifest_path, "assets/effects/imagegen_spells/" + manifest["runtime_atlas"]})
        self.assertEqual(expected, {name for name in originals if name.startswith("assets/effects/imagegen_spells/")})

    def test_pack_audit_rejects_history_and_production_records(self):
        paths = {"assets/chars/pixel/a/video_actions/provenance.json",
                 "assets/chars/pixel/a/video_actions/frozen_20261006/manifest.json",
                 "assets/chars/pixel/a/video_actions/original_runtime_448/contacts.json",
                 "assets/effects/imagegen_spells/qa_acceptance.json",
                 "assets/chars/pixel/a/video_actions/recovery_validation.json",
                 "data/characters/art_revisions/character.json"}
        self.assertEqual(len(paths), len(release.audit_paths(paths, set())))


if __name__ == "__main__":
    unittest.main()
