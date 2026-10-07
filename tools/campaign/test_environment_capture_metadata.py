"""环境捕获身份信息的纯读取回归。"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('environment_runner', Path(__file__).with_name('run_environment_checks.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

class CaptureIdentityTests(unittest.TestCase):
    def test_identity_records_head_dirty_and_asset_digests(self):
        self.assertTrue(hasattr(runner, 'capture_identity'), '捕获入口缺少HEAD/dirty/资源SHA记录')
        identity = runner.capture_identity(['1', '2'])
        self.assertRegex(identity['head'], r'^[0-9a-f]{40}$')
        self.assertIsInstance(identity['dirty'], str)
        self.assertIn('assets/3d/act01_approach/act01_approach.glb', identity['sha256'])
        self.assertIn('scripts/campaign/environments/night_2_art.gd', identity['sha256'])
        self.assertIn('scripts/campaign/presentation/night_2_hd2d_profile.gd', identity['sha256'])
        self.assertIn('scripts/campaign/presentation/hd2d_depth_blur.gdshader', identity['sha256'])
        self.assertTrue(all(len(value) == 64 for value in identity['sha256'].values()))
    def test_hd2d_target_hash_ignores_unrelated_ordinary_target(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            ordinary = project / '.dream-loop/target.png'
            ordinary.parent.mkdir(parents=True)
            ordinary.write_bytes(b'ordinary')
            with patch.object(runner, 'PROJECT', project):
                self.assertIsNone(runner.target_digest(True))
                self.assertEqual(runner.target_digest(False), runner.sha256_file(ordinary))

    def test_hd2d_only_target_is_recorded(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            hd2d = project / '.dream-loop/hd2d/target.png'
            hd2d.parent.mkdir(parents=True)
            hd2d.write_bytes(b'hd2d')
            with patch.object(runner, 'PROJECT', project):
                self.assertEqual(runner.target_digest(True), runner.sha256_file(hd2d))
                self.assertIsNone(runner.target_digest(False))

    def test_digest_tracks_content_change(self):
        self.assertTrue(hasattr(runner, 'sha256_file'), '捕获入口缺少内容SHA256记录')
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'asset.glb'
            path.write_bytes(b'first')
            first = runner.sha256_file(path)
            path.write_bytes(b'second')
            self.assertNotEqual(first, runner.sha256_file(path))

if __name__ == '__main__':
    unittest.main()
