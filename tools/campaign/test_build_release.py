import importlib.util
from pathlib import Path
import tempfile
import unittest


class ReleaseRunnerTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).with_name("build_release.py")
        self.assertTrue(path.exists(), "发布入口必须隔离并阻止PCK宿主资源回退")
        spec = importlib.util.spec_from_file_location("build_release", path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_packed_command_has_only_empty_project_and_external_test(self):
        command = self.module.packed_command("godot", Path("/tmp/empty"), Path("/tmp/game.pck"), Path("/tmp/test.gd"))
        self.assertEqual(["godot", "--headless", "--path", "/tmp/empty", "--main-pack", "/tmp/game.pck", "--script", "/tmp/test.gd"], command)

    def test_isolation_accepts_only_one_actual_subdirectory_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            good = "RPG_ISOLATION_OK:" + str(root / "data/user")
            self.assertTrue(self.module.valid_isolation(0, good, root))
            for bad in ("RPG_ISOLATION_OK:" + str(root), good + "\n" + good, good + "\nSCRIPT ERROR: failure", "RPG_ISOLATION_OK:" + str(root) + "-sibling/data"):
                self.assertFalse(self.module.valid_isolation(0, bad, root))
            self.assertFalse(self.module.valid_isolation(1, good, root))

    def test_source_delivery_rejects_required_untracked_runtime_dependency(self):
        self.assertTrue(hasattr(self.module, "untracked_dependencies"), "源码ZIP不得静默遗漏正在生成的必需文件")
        self.assertEqual(["data/characters/stature.json"], self.module.untracked_dependencies(
            ["scripts/characters/character_stature.gd", "data/characters/stature.json"], {"scripts/characters/character_stature.gd"}))

    def test_clean_title_is_launched_before_height_test_writes_formal_save(self):
        self.assertTrue(hasattr(self.module, "packed_smoke_commands"), "发布命令顺序须保护干净用户启动验收")
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            height = project / "tools/campaign/test_character_height.gd"
            height.parent.mkdir(parents=True)
            height.touch()
            commands = self.module.packed_smoke_commands("godot", Path("/tmp/empty"), Path("/tmp/game.pck"), project)
            self.assertEqual(4, len(commands))
            self.assertIn("--quit-after", commands[2])
            self.assertIn(str(height), commands[3])

    def test_optional_modal_layout_runs_before_state_writing_stature(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            folder = project / "tools/campaign"
            folder.mkdir(parents=True)
            for name in ("test_character_height.gd", "test_modal_layout.gd"):
                (folder / name).touch()
            commands = self.module.packed_smoke_commands("godot", Path("/tmp/empty"), Path("/tmp/game.pck"), project)
            self.assertEqual(5, len(commands))
            self.assertIn("--quit-after", commands[2])
            self.assertIn(str(folder / "test_modal_layout.gd"), commands[3])
            self.assertIn(str(folder / "test_character_height.gd"), commands[4])


if __name__ == "__main__":
    unittest.main()
