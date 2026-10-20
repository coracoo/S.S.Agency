"""紧凑战斗UI的动态原PNG和专属脚本必须进入正式发布依赖闭包。"""
from pathlib import Path
import unittest

from release_pack import formal_dependencies

PROJECT = Path(__file__).resolve().parents[2]


class CompactBattleReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources, cls.resources = formal_dependencies(PROJECT)

    def test_raw_paper_pngs_are_retained(self):
        # Image.load_from_file直接解码原PNG；只有导入纹理资源不足以支持运行时。
        for name in ("normal-brush.png", "selected-brush.png"):
            path = "assets/ui/battle_washi_compact/" + name
            with self.subTest(path=path):
                self.assertIn(path, self.sources)
                self.assertTrue(self.sources[path].is_file())

    def test_battle_helpers_and_standard_fallback_are_runtime_dependencies(self):
        required = (
            "scripts/rpg/ui/actor_command_menu.gd",
            "scripts/rpg/ui/actor_command_menu_standard.gd",
            "scripts/rpg/ui/battle_skill_icons.gd",
            "scripts/rpg/ui/battle_hud_depth_style.gd",
            "scripts/rpg/ui/battle_scene_staging.gd",
            "scripts/rpg/ui/battle_ground_backdrop.gd",
            "scripts/rpg/ui/combat_ready_actor_view.gd",
            "scripts/characters/combat_ready_animator.gd",
            "scripts/characters/combat_ready_pose_catalog.gd",
        )
        for path in required:
            with self.subTest(path=path):
                self.assertIn(path, self.resources)
                text = (PROJECT / path).read_text(encoding="utf-8")
                self.assertNotIn("design-reference-audit", text)
                self.assertNotIn("C:/Users/", text)


if __name__ == "__main__":
    unittest.main()
