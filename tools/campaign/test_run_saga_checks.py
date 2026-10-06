import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).with_name('run_saga_checks.py')

class SagaRunnerTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.is_file(), '七章必须有可复现、核验隔离的统一入口')
        spec = importlib.util.spec_from_file_location('saga_runner', MODULE)
        self.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runner)

    def test_rejects_error_even_with_zero_exit(self):
        self.assertTrue(self.runner.failed(0, '  SCRIPT ERROR: bad route'))
        self.assertTrue(self.runner.failed(0, 'FAIL: skipped ending'))
        self.assertFalse(self.runner.failed(0, 'WARNING: historical\nSAGA_STATE_ASSERTIONS: 190'))

    def test_actual_user_path_must_be_inside_temporary_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            self.assertFalse(self.runner.verified_isolation(0, f'RPG_ISOLATION_OK:{root}', root))
            self.assertFalse(self.runner.verified_isolation(0, 'RPG_ISOLATION_OK:/real/user', root))
            self.assertFalse(self.runner.verified_isolation(1, f'RPG_ISOLATION_OK:{root}/user', root))
            self.assertTrue(self.runner.verified_isolation(0, f'RPG_ISOLATION_OK:{root}/user', root))

    def test_real_matrix_includes_both_first_chapter_outcomes(self):
        cases = self.runner.scenarios('real')
        self.assertEqual(len(cases), 5)
        self.assertEqual({case['ending'] for case in cases}, {'dawn', 'vigil', 'shatter', 'eternal'})
        self.assertIn('seal_monitoring', {case['resolution'] for case in cases})
        self.assertTrue(all(case['real'] for case in cases))
