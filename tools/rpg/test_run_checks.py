"""验证隔离入口的失败关闭行为；真实引擎负例也只使用临时环境。"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]
RUNNER = PROJECT / "tools/rpg/run_checks.py"
GODOT = os.environ.get("GODOT_BIN", "/usr/local/bin/godot")


class IsolationRunnerTests(unittest.TestCase):
    def run_fake_engine(self, behavior: str) -> tuple[subprocess.CompletedProcess, list[str]]:
        with tempfile.TemporaryDirectory(prefix="rpg-runner-contract-") as directory:
            root = Path(directory)
            engine = root / "fake_godot.py"
            log = root / "calls.log"
            engine.write_text(
                "#!/usr/bin/env python3\nimport os, sys\nfrom pathlib import Path\n"
                f"log = Path({str(log)!r})\n"
                "with log.open('a') as f: f.write(' '.join(sys.argv[1:]) + '\\n')\n"
                "is_preflight = 'res://tools/rpg/test_environment.gd' in sys.argv\n"
                + behavior,
                encoding="utf-8",
            )
            engine.chmod(0o755)
            result = subprocess.run([sys.executable, str(RUNNER), "--suite", "data", "--legacy",
                                     "--godot", str(engine)], text=True, capture_output=True)
            return result, log.read_text().splitlines()

    def test_outside_user_directory_blocks_import_and_legacy(self):
        result, calls = self.run_fake_engine("print('RPG_ISOLATION_OK:/tmp/outside-user-dir')\n")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 1)

    def test_root_itself_is_not_user_directory(self):
        result, calls = self.run_fake_engine("print('RPG_ISOLATION_OK:' + os.environ['RPG_TEST_ROOT'])\n")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 1)

    def test_sibling_prefix_is_not_isolation(self):
        result, calls = self.run_fake_engine("print('RPG_ISOLATION_OK:' + os.environ['RPG_TEST_ROOT'] + '-outside/data')\n")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 1)

    def test_preflight_script_error_blocks_even_with_zero_exit(self):
        result, calls = self.run_fake_engine("print('RPG_ISOLATION_OK:' + os.environ['XDG_DATA_HOME'] + '/user')\nprint('SCRIPT ERROR: synthetic preflight failure')\n")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 1)

    def test_runtime_error_blocks_legacy_even_with_zero_exit(self):
        result, calls = self.run_fake_engine(
            "if is_preflight: print('RPG_ISOLATION_OK:' + os.environ['XDG_DATA_HOME'] + '/user')\n"
            "elif '--import' in sys.argv: print('import ok')\n"
            "else: print('PASS: fake group\\nSCRIPT ERROR: synthetic test failure')\n"
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 3)
        self.assertFalse(any('test_v4_battle_rules' in call for call in calls))

    def test_legacy_runs_all_three_after_verified_preflight(self):
        result, calls = self.run_fake_engine(
            "if is_preflight: print('RPG_ISOLATION_OK:' + os.environ['XDG_DATA_HOME'] + '/user')\n"
            "else: print('PASS: step')\n"
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(calls), 6)
        self.assertIn('test_v4_battle_rules.gd', calls[3])
        self.assertIn('test_rinne_v3_timing.gd', calls[4])
        self.assertIn('test_act01_approach_preview.gd', calls[5])

    def test_legacy_runtime_error_still_runs_remaining_checks_but_fails(self):
        result, calls = self.run_fake_engine(
            "if is_preflight: print('RPG_ISOLATION_OK:' + os.environ['XDG_DATA_HOME'] + '/user')\n"
            "elif any('test_rinne_v3_timing' in a for a in sys.argv): print('PASS: timing\\nSCRIPT ERROR: synthetic timing failure')\n"
            "else: print('PASS: step')\n"
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 6)
        self.assertIn('test_act01_approach_preview.gd', calls[-1])

    def test_real_engine_rejects_wrong_root_without_real_user_access(self):
        with tempfile.TemporaryDirectory(prefix="rpg-preflight-negative-") as directory:
            env = os.environ.copy()
            for variable in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                path = Path(directory) / variable.lower()
                path.mkdir()
                env[variable] = str(path)
            env["RPG_TEST_ROOT"] = directory + "-wrong"
            env["RPG_TEST_ISOLATED"] = "0"
            result = subprocess.run([GODOT, "--headless", "--path", str(PROJECT), "--script",
                                     "res://tools/rpg/test_environment.gd"], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertNotIn("RPG_ISOLATION_OK:", result.stdout)
            self.assertIn("未隔离", result.stderr)


if __name__ == "__main__":
    unittest.main()
