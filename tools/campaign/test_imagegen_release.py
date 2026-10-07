"""生图运行发布闭包必须验证元数据和PNG哈希，并拒绝路径越界。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("release_pack.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ImagegenRelease(unittest.TestCase):
    def fixture(self, root):
        folder = root / "assets/effects/imagegen_spells"
        (folder / "firebolt").mkdir(parents=True)
        atlas = folder / "firebolt/runtime.png"
        atlas.write_bytes(b"original runtime atlas fixture")
        value = {"schema_version":1, "skill_id":"firebolt", "runtime_atlas":"firebolt/runtime.png",
                 "runtime_atlas_sha256":hashlib.sha256(atlas.read_bytes()).hexdigest()}
        manifest = folder / "firebolt/manifest.json"
        manifest.write_text(json.dumps(value))
        registry = {"schema_version":2, "asset_root":"res://assets/effects/imagegen_spells", "production_renderer_enabled":False,
                    "effects":{"firebolt":{"manifest":"res://assets/effects/imagegen_spells/firebolt/manifest.json",
                    "manifest_sha256":hashlib.sha256(manifest.read_bytes()).hexdigest()}}}
        (folder / "registry.json").write_text(json.dumps(registry))
        return folder, registry, value

    def test_exact_runtime_closure_does_not_recurse_into_receipts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder, _, _ = self.fixture(root)
            (folder / "qa_acceptance.json").write_text("private fixture")
            (folder / "unregistered.png").write_bytes(b"unused")
            prefix = "assets/effects/imagegen_spells/"
            self.assertEqual({prefix + "registry.json", prefix + "firebolt/manifest.json", prefix + "firebolt/runtime.png"}, release.imagegen_effect_sources(root))

    def test_manifest_and_atlas_mutations_are_rejected(self):
        for name in ("firebolt/manifest.json", "firebolt/runtime.png"):
            with tempfile.TemporaryDirectory() as temp, self.subTest(path=name):
                root = Path(temp)
                folder, _, _ = self.fixture(root)
                with (folder / name).open("ab") as stream:
                    stream.write(b"changed")
                with self.assertRaises(ValueError):
                    release.imagegen_effect_sources(root)

    def test_manifest_and_atlas_paths_cannot_escape_the_registered_skill(self):
        for change in ("manifest", "atlas"):
            with tempfile.TemporaryDirectory() as temp, self.subTest(change=change):
                root = Path(temp)
                folder, registry, value = self.fixture(root)
                if change == "manifest":
                    registry["effects"]["firebolt"]["manifest"] = "res://../private.json"
                else:
                    value["runtime_atlas"] = "firebolt/../private.png"
                    path = folder / "firebolt/manifest.json"
                    path.write_text(json.dumps(value))
                    registry["effects"]["firebolt"]["manifest_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
                (folder / "registry.json").write_text(json.dumps(registry))
                with self.assertRaises(ValueError):
                    release.imagegen_effect_sources(root)


if __name__ == "__main__":
    unittest.main()
