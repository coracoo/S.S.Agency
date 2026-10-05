"""PCK验证/原始依赖追加工具的真实字节回归，不依赖已安装Godot。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

MODULE = Path(__file__).with_name("release_pack.py")


class PackTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.exists(), "缺少可读取/校验并追加原始依赖的PCK工具")
        spec = importlib.util.spec_from_file_location("release_pack", MODULE)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def fixture(self, root, payload=b"official-imported-bytes"):
        pack = root / "game.pck"
        header = struct.pack("<6IQQ", 0x43504447, 3, 4, 6, 3, 2, 112, 112 + len(payload)) + bytes(72)
        name = b".godot/imported/frame.ctex\0"
        directory = struct.pack("<II", 1, len(name)) + name + struct.pack("<QQ", 0, len(payload)) + hashlib.md5(payload).digest() + struct.pack("<I", 0)
        pack.write_bytes(header + payload + directory)
        return pack

    def test_reads_official_v3_offsets_and_validates_existing_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            pack = self.fixture(Path(directory))
            entries = self.module.read_pack(pack)
            self.assertEqual([".godot/imported/frame.ctex"], list(entries))
            self.assertEqual(b"official-imported-bytes", self.module.read_entry(pack, entries[".godot/imported/frame.ctex"]))
            self.assertEqual([], self.module.verify_entries(pack, entries))

    def test_append_retains_imported_bytes_and_adds_exact_original_png(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pack = self.fixture(root)
            image = root / "frame.png"
            image.write_bytes(b"original-raw-png-bytes")
            self.module.append_originals(pack, {"assets/frame.png": image})
            entries = self.module.read_pack(pack)
            self.assertEqual(2, len(entries))
            self.assertEqual(image.read_bytes(), self.module.read_entry(pack, entries["assets/frame.png"]))
            self.assertEqual(b"official-imported-bytes", self.module.read_entry(pack, entries[".godot/imported/frame.ctex"]))
            self.assertEqual([], self.module.verify_entries(pack, entries))

    def test_append_is_idempotent_but_rejects_changed_existing_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pack = self.fixture(root)
            image = root / "frame.png"
            image.write_bytes(b"original")
            self.module.append_originals(pack, {"assets/frame.png": image})
            size = pack.stat().st_size
            self.module.append_originals(pack, {"assets/frame.png": image})
            self.assertEqual(size, pack.stat().st_size)
            image.write_bytes(b"changed")
            with self.assertRaises(ValueError):
                self.module.append_originals(pack, {"assets/frame.png": image})

    def test_tampered_imported_payload_fails_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            pack = self.fixture(Path(directory))
            with pack.open("r+b") as stream:
                stream.seek(112)
                stream.write(b"X")
            self.assertTrue(self.module.verify_entries(pack, self.module.read_pack(pack)))

    def test_development_and_raw_sheets_are_rejected_by_release_audit(self):
        failures = self.module.audit_paths({"tools/test.gd", "config/dialogue.xlsx", "assets/fx/_raw_fire_burst_sheet.png", "assets/chars/pixel/rinne/high_detail_complete/frames/idle1.png"}, set())
        self.assertEqual(3, len(failures))

    def test_formal_roots_expand_exact_frames_without_atlas_or_old_scenes(self):
        self.assertTrue(hasattr(self.module, "formal_dependencies"), "正式发布须按主线与动态清单收敛依赖")
        originals, resources = self.module.formal_dependencies()
        frames = [path for path in originals if "/high_detail_complete/frames/" in path]
        self.assertEqual(154, len(frames))
        self.assertFalse(any("/atlases/" in path for path in originals))
        self.assertFalse(any(path.startswith("scenes/v3/") or path == "scenes/rpg/launcher.tscn" for path in resources))
        self.assertIn("assets/audio/sfx/sfx_bell.mp3", originals)
        self.assertIn("assets/chars/enemies/current/hound.png", originals)
        self.assertIn("scripts/exploration_3d/approach_session.gd", resources)
        # 实际新生产脚本的FileAccess配置必须进入包，避免新增系统静默用空配置。
        if (self.module.PROJECT / "scripts/characters/character_stature.gd").is_file():
            self.assertIn("data/characters/stature.json", originals, "新增人物身高配置不能漏包")

    def test_npc_images_and_provenance_are_explicit_formal_dependencies(self):
        originals, resources = self.module.formal_dependencies()
        for name in ("liang_world.png", "acheng_world.png", "liang_half.png", "acheng_half.png"):
            with self.subTest(name=name):
                self.assertIn("assets/chars/npcs/act_one/" + name, resources)
        self.assertIn("assets/chars/npcs/act_one/asset_manifest.json", originals)

    def test_class_cache_keeps_current_class_and_removes_unexported_legacy(self):
        self.assertTrue(hasattr(self.module, "filter_class_cache"), "选择导出不能留下全项目旧class路径")
        cache = 'list=[{\n"class": &"Current",\n"path": "res://scripts/current.gd"\n}, {\n"class": &"Old",\n"path": "res://tools/old.gd"\n}]\n'
        filtered = self.module.filter_class_cache(cache, {"scripts/current.gd.remap"})
        self.assertIn('"Current"', filtered)
        self.assertNotIn('"Old"', filtered)
        self.assertNotIn('tools/', filtered)

    def test_manifest_art_revision_provenance_is_retained_without_raw_generation_sources(self):
        originals, _ = self.module.formal_dependencies()
        for manifest_path in (self.module.PROJECT / "assets/chars/pixel").glob("*/high_detail_complete/manifest.json"):
            provenance = json.loads(manifest_path.read_text()).get("art_revision", {}).get("provenance")
            if provenance:
                self.assertIn(provenance.removeprefix("res://"), originals, "正式成品来源JSON必须随manifest保留")
        self.assertFalse(any("full-set-raw" in path for path in originals))

    def test_uid_cache_preserves_ids_only_for_actual_pack_targets(self):
        self.assertTrue(hasattr(self.module, "filter_uid_cache"), "UID生成缓存必须只指向实际发包路径")
        paths = [(137, b"res://scripts/current.gd"), (251, b"res://scenes/v3/title.tscn")]
        cache = struct.pack("<I", 2) + b"".join(struct.pack("<QI", uid, len(path)) + path for uid, path in paths)
        filtered = self.module.filter_uid_cache(cache, {"scripts/current.gd.remap"})
        self.assertEqual([(137, "res://scripts/current.gd")], self.module.uid_entries(filtered))

    def test_packed_cache_filter_changes_only_generated_metadata(self):
        self.assertTrue(hasattr(self.module, "filter_pack_caches"), "仅允许过滤PCK内的生成缓存")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pack = self.fixture(root)
            cache = root / "classes.cfg"
            cache.write_text('list=[{\n"class": &"Old",\n"path": "res://tools/old.gd"\n}]\n')
            self.module.append_originals(pack, {".godot/global_script_class_cache.cfg": cache})
            self.module.filter_pack_caches(pack)
            entries = self.module.read_pack(pack)
            self.assertEqual(b"official-imported-bytes", self.module.read_entry(pack, entries[".godot/imported/frame.ctex"]))
            self.assertNotIn(b"tools/", self.module.read_entry(pack, entries[".godot/global_script_class_cache.cfg"]))
            self.assertEqual([], self.module.verify_entries(pack, entries))


if __name__ == "__main__":
    unittest.main()
