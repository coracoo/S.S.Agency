"""原生 Windows/POSIX 门禁的进程等待及跨进程互斥回归。"""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

SUPPORT = Path(__file__).resolve().parents[1] / "verification_support.py"


class VerificationSupportTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SUPPORT.is_file(), "门禁需要可跨平台的真实文件锁及管道等待")
        spec = importlib.util.spec_from_file_location("verification_support", SUPPORT)
        self.support = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.support)

    def test_lock_excludes_another_process_and_releases_after_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / "godot-import.lock"
            child = "from verification_support import exclusive_file_lock\nfrom pathlib import Path\nimport sys\ntry:\n with exclusive_file_lock(Path(sys.argv[1]), timeout=.2): print('acquired')\nexcept TimeoutError: print('blocked')\n"
            env = os.environ.copy()
            env["PYTHONPATH"] = str(SUPPORT.parent)
            with self.assertRaisesRegex(RuntimeError, "probe"):
                with self.support.exclusive_file_lock(lock):
                    result = subprocess.run([sys.executable, "-c", child, str(lock)], env=env, capture_output=True, text=True, timeout=5)
                    self.assertEqual(0, result.returncode, result.stderr)
                    self.assertEqual("blocked", result.stdout.strip())
                    raise RuntimeError("probe")
            result = subprocess.run([sys.executable, "-c", child, str(lock)], env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual("acquired", result.stdout.strip())

    def test_pipe_captures_unicode_and_stderr(self):
        result = self.support.run_captured([sys.executable, "-X", "utf8", "-c", "import sys; print('隔离成功'); print('stderr', file=sys.stderr)"], timeout=5)
        self.assertEqual(0, result.returncode)
        self.assertIn("隔离成功", result.stdout)
        self.assertIn("stderr", result.stdout)

    def test_engine_error_stops_process_without_waiting_for_timeout(self):
        start = time.monotonic()
        result = self.support.run_captured([sys.executable, "-u", "-c", "import time; print('SCRIPT ERROR: probe'); time.sleep(30)"], timeout=10)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("SCRIPT ERROR: probe", result.stdout)
        self.assertLess(time.monotonic() - start, 5)

    def test_timeout_kills_child_and_retains_partial_output(self):
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            self.support.run_captured([sys.executable, "-u", "-c", "import time; print('before timeout'); time.sleep(30)"], timeout=.3)
        self.assertIn(b"before timeout", caught.exception.output)

    def test_engine_error_stops_descendants_that_keep_the_output_pipe_open(self):
        code = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-u','-c',\"import time; print('descendant ready'); time.sleep(3)\"]); time.sleep(.2); print('SCRIPT ERROR: tree probe'); time.sleep(30)"
        start = time.monotonic()
        result = self.support.run_captured([sys.executable, "-u", "-c", code], timeout=10)
        self.assertIn("SCRIPT ERROR: tree probe", result.stdout)
        self.assertLess(time.monotonic() - start, 2, "引擎 console 包装进程的子引擎不能继续占着管道")


if __name__ == "__main__":
    unittest.main()
