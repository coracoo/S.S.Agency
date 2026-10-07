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
        for skill, entry in registry["effects"].items():
            with self.subTest(skill=skill):
                path = ROOT / entry["manifest"].removeprefix("res://")
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), entry["manifest_sha256"])
                value = json.loads(path.read_text())
                self.assertEqual({"schema_version", "skill_id", "runtime_atlas", "runtime_atlas_sha256", "frame_count", "frames", "phases"}, set(value))
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
        self.assertEqual(9, sum(name.startswith("assets/effects/imagegen_spells/") for name in originals))

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
