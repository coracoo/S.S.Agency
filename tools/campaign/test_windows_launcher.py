"""启动器的静态契约；不把Linux源码检查当Windows执行验收。"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WindowsLauncherTests(unittest.TestCase):
    def test_engine_override_and_472_precede_legacy_fallback(self):
        source = (ROOT / "play.bat").read_text(encoding="utf-8")
        self.assertIn("GODOT_BIN", source)
        self.assertLess(source.index("GODOT_BIN"), source.index("Godot_v4.7.2"))
        self.assertLess(source.index("Godot_v4.7.2"), source.index("Godot_v4.6.3"))

    def test_project_is_relative_to_launcher_and_only_formal_entry(self):
        source = (ROOT / "play.bat").read_text(encoding="utf-8")
        self.assertIn('set "PROJECT=%~dp0."', source)
        self.assertNotIn("J:\\godot\\S.S.Agency", source)
        self.assertIn("res://scenes/campaign/title.tscn", source)
        self.assertNotIn("new_commission", source)

    def test_chinese_entry_delegates_without_duplicate_configuration(self):
        source = (ROOT / "启动游戏.bat").read_text(encoding="utf-8")
        self.assertIn('call "%~dp0play.bat"', source)
        self.assertNotIn('set "GODOT=', source)

if __name__ == "__main__":
    unittest.main()
