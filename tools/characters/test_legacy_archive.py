"""退役角色原件归档合同：原字节、正式资源保护和发行包边界。"""
import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'old/characters/manifest.json'

class LegacyArchiveTest(unittest.TestCase):
    def manifest(self):
        self.assertTrue(MANIFEST.is_file(), '必须提供逐文件可恢复的归档清单')
        return json.loads(MANIFEST.read_text())

    def test_retired_sources_are_moved_without_changing_a_byte(self):
        manifest = self.manifest()
        self.assertEqual(len(manifest['entries']), 210)
        for row in manifest['entries']:
            with self.subTest(path=row['from']):
                self.assertFalse((ROOT / row['from']).exists())
                self.assertEqual(row['to'], 'old/characters/' + row['from'])
                self.assertEqual(hashlib.sha256((ROOT / row['to']).read_bytes()).hexdigest(), row['sha256'])

    def test_every_protected_character_file_remains_identical(self):
        manifest = self.manifest()
        self.assertGreaterEqual(len(manifest['protected_files']), 490)
        for row in manifest['protected_files']:
            with self.subTest(path=row['path']):
                self.assertEqual(hashlib.sha256((ROOT / row['path']).read_bytes()).hexdigest(), row['sha256'])
        self.assertTrue((ROOT/'assets/chars/anims/rinne_idle_f1.png').is_file())

    def test_relative_manifest_cli_preserves_historical_validation(self):
        result = subprocess.run([sys.executable, 'tools/characters/validate_assets.py',
                                 '--manifest', 'assets/chars/pixel/rinne/frame_material_refined/manifest.json'],
                                cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(': PASS', result.stdout)

    def test_archive_is_ignored_and_excluded_from_formal_release(self):
        self.assertTrue((ROOT/'old/.gdignore').is_file())
        self.assertIn('old/*', (ROOT/'export_presets.cfg').read_text())
        spec = importlib.util.spec_from_file_location('release_pack', ROOT/'tools/campaign/release_pack.py')
        release_pack = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(release_pack)
        self.assertTrue(release_pack.audit_paths({'old/characters/retired.png'}, set()))
        sources, resources = release_pack.formal_dependencies(ROOT)
        self.assertFalse(any(p.startswith('old/') for p in set(sources) | set(resources)))

if __name__ == '__main__':
    unittest.main()
