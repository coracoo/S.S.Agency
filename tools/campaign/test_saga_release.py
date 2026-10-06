"""七章正式包闭包、目标引擎与包外探针的回归。"""
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools/campaign" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SagaReleaseTests(unittest.TestCase):
    def test_saga_production_scenes_are_explicit_release_roots(self):
        _, resources = load_module("release_pack").formal_dependencies()
        for path in ("scenes/campaign/saga.tscn", "scenes/campaign/saga_ending.tscn"):
            self.assertIn(path, resources, "字符串场景跳转不得依赖导出器隐式追踪")

    def test_saga_dynamic_data_and_production_scripts_are_retained(self):
        sources, resources = load_module("release_pack").formal_dependencies()
        for path in ("data/campaign/saga.json", "data/rpg/saga_enemies.json", "data/rpg/saga_encounters.json"):
            self.assertIn(path, sources)
        for path in ("saga_catalog", "saga_progress", "saga_route_rules", "saga_save_rules", "saga_stage", "saga_ending", "saga_world", "saga_battle_narrator"):
            self.assertIn("scripts/campaign/" + path + ".gd", resources)
        self.assertIn("scripts/rpg/saga_boss_rules.gd", resources)
        self.assertFalse(any(path.startswith(("tools/", "docs/")) for path in set(sources) | set(resources)))

    def test_new_npc_manifest_expands_only_declared_sheet_pngs(self):
        packer = load_module("release_pack")
        originals, resources = packer.formal_dependencies()
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in set(originals) | set(resources):
                if name.startswith("assets/chars/npcs/saga/"):
                    continue
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(ROOT / name)
            folder = project / "assets/chars/npcs/saga"
            folder.mkdir(parents=True)
            manifest = folder / "asset_manifest.json"
            sheet = folder / "approved_npc_sheet.png"
            sheet.write_bytes(b"approved-raw-sheet-bytes")
            (folder / "unapproved_preview.png").write_bytes(b"excluded-preview")
            manifest.write_text(json.dumps({"schema_version": 1, "characters": {
                "测试居民": {"speaker": "测试居民", "sheet": "res://assets/chars/npcs/saga/approved_npc_sheet.png", "world_region": [0, 0, 512, 1024], "portrait_region": [512, 0, 512, 512]}
            }}))
            sources, _ = packer.formal_dependencies(project)
            self.assertIn("assets/chars/npcs/saga/asset_manifest.json", sources)
            self.assertIn("assets/chars/npcs/saga/approved_npc_sheet.png", sources)
            self.assertEqual(sheet, sources["assets/chars/npcs/saga/approved_npc_sheet.png"])
            self.assertNotIn("assets/chars/npcs/saga/unapproved_preview.png", sources)

    def test_new_enemy_manifest_expands_only_declared_sheet_pngs(self):
        packer = load_module("release_pack")
        originals, resources = packer.formal_dependencies()
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in set(originals) | set(resources):
                if name.startswith("assets/chars/enemies/saga/"):
                    continue
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(ROOT / name)
            folder = project / "assets/chars/enemies/saga"
            folder.mkdir(parents=True)
            manifest = folder / "asset_manifest.json"
            sheet = folder / "approved_enemy_sheet.png"
            sheet.write_bytes(b"approved-raw-enemy-sheet-bytes")
            (folder / "unapproved_preview.png").write_bytes(b"excluded-preview")
            manifest.write_text(json.dumps({"schema_version": 1, "enemies": {
                "saga_paper_soldier": {"sheet": "res://assets/chars/enemies/saga/approved_enemy_sheet.png", "region": [0, 0, 512, 1024], "anchor": [256, 1000], "content_height_px": 990, "facing": "right"}
            }}))
            sources, _ = packer.formal_dependencies(project)
            self.assertIn("assets/chars/enemies/saga/asset_manifest.json", sources)
            self.assertIn("assets/chars/enemies/saga/approved_enemy_sheet.png", sources)
            self.assertEqual(sheet, sources["assets/chars/enemies/saga/approved_enemy_sheet.png"])
            self.assertNotIn("assets/chars/enemies/saga/unapproved_preview.png", sources)

    def test_release_gate_accepts_only_approved_target_official_engine(self):
        runner = load_module("build_release")
        self.assertTrue(hasattr(runner, "valid_release_engine"), "发布须显式核验本轮官方目标引擎")
        self.assertTrue(runner.valid_release_engine("4.7.2.stable.official.abcdef"))
        for version in ("4.6.3.stable.official.abcdef", "4.7.2.stable.custom.abcdef", "4.7.3.stable.official.abcdef", "4.7.2.rc.official.abcdef"):
            self.assertFalse(runner.valid_release_engine(version))

    def test_saga_packed_probe_is_external_and_after_clean_title(self):
        runner = load_module("build_release")
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            probe = project / "tools/campaign/test_saga_release_packed.gd"
            probe.parent.mkdir(parents=True)
            probe.touch()
            commands = runner.packed_smoke_commands("godot", Path("/tmp/empty"), Path("/tmp/game.pck"), project)
            self.assertTrue(any(str(probe) in command for command in commands), "七章发布探针必须真正运行")
            title_index = next(index for index, command in enumerate(commands) if "--quit-after" in command)
            saga_index = next(index for index, command in enumerate(commands) if str(probe) in command)
            self.assertLess(title_index, saga_index)
            self.assertEqual("/tmp/empty", commands[saga_index][3])

    def test_linux_launcher_is_executable_and_preserves_engine_arguments(self):
        runner = load_module("build_release")
        self.assertTrue(hasattr(runner, "write_launchers"), "发布启动脚本必须可直接执行")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            runner.write_launchers(output)
            launcher = output / "launch_campaign.sh"
            self.assertTrue(os.access(launcher, os.X_OK))
            engine = output / "fake-engine"
            engine.write_text('#!/bin/sh\nprintf "%s\\n" "$PWD" "$@"\n')
            engine.chmod(0o755)
            env = dict(os.environ, GODOT_BIN=str(engine))
            result = subprocess.run([str(launcher), "--headless", "--quit-after", "2"], cwd="/tmp", env=env, text=True, capture_output=True)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual([str(output), "--main-pack", "ssa-seven-chapter-formal.pck", "--headless", "--quit-after", "2"], result.stdout.splitlines())

    def test_dirty_or_changed_source_never_reports_formal_pass(self):
        runner = load_module("build_release")
        self.assertTrue(hasattr(runner, "verification_status"))
        self.assertEqual("pass", runner.verification_status(False, [], [], False))
        self.assertEqual("partial_no_e2e", runner.verification_status(True, [], [], False))
        for dirty, missing, changed in ((["scripts/game.gd"], [], False), ([], ["data/campaign/saga.json"], False), ([], [], True)):
            self.assertEqual("development_pass_dirty_source", runner.verification_status(False, dirty, missing, changed))

    def test_final_saga_e2e_uses_real_battles_and_external_pack(self):
        runner = load_module("build_release")
        self.assertTrue(hasattr(runner, "saga_e2e_command"))
        command = runner.saga_e2e_command("godot", Path("/tmp/game.pck"), Path("/tmp/evidence"))
        self.assertIn(str(ROOT / "tools/campaign/run_saga_checks.py"), command)
        self.assertEqual("real", command[command.index("--mode") + 1])
        self.assertEqual("/tmp/game.pck", command[command.index("--pack") + 1])


if __name__ == "__main__":
    unittest.main()
