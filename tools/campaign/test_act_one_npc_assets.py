"""两居民原始独立PNG、来源及身体参考点的非绘图检查。"""
import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image

PROJECT = Path(__file__).resolve().parents[2]
ASSETS = PROJECT / 'assets/chars/npcs/act_one'

class ResidentAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ASSETS / 'asset_manifest.json').read_text())

    def test_independent_originals_and_provenance(self):
        """重用敌图、漏图、静默重绘而未更新hash都应失败。"""
        records = self.manifest['assets']
        self.assertEqual({entry['id'] for entry in records}, {'liang', 'acheng'})
        hashes = set()
        enemy_hashes = {
            hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (PROJECT / 'assets/chars/enemies/current').glob('*.png')
        }
        for entry in records:
            with self.subTest(identity=entry['id']):
                digest = hashlib.sha256((ASSETS / entry['file']).read_bytes()).hexdigest()
                self.assertEqual(digest, entry['sha256'])
                self.assertNotIn(digest, hashes | enemy_hashes)
                self.assertTrue(entry['prompt'])
                hashes.add(digest)

    def test_dedicated_half_body_portraits_and_edge_alpha(self):
        """全身图不能冒充半身，人物肩外/头侧也必须是真透明。"""
        portraits = self.manifest['portraits']
        self.assertEqual({r['identity_id'] for r in portraits}, {'liang', 'acheng'})
        active_world_files = {r['file'] for r in self.manifest['assets']}
        for entry in portraits:
            with self.subTest(identity=entry['identity_id']):
                self.assertEqual(entry['framing'], 'half_body')
                self.assertTrue(entry['file'].endswith('_half.png'))
                self.assertNotIn(entry['file'], active_world_files)
                data = (ASSETS / entry['file']).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry['sha256'])
                self.assertEqual(len(entry['references']), 2)
                self.assertTrue(entry['identity_reference'])
                with Image.open(ASSETS / entry['file']) as image:
                    self.assertEqual(image.mode, 'RGBA')
                    self.assertEqual(list(image.size), entry['canvas'])
                    self.assertEqual(image.width * 3, image.height * 2)
                    alpha = image.getchannel('A')
                    for point in entry['alpha_probe_points']:
                        self.assertEqual(alpha.getpixel(tuple(point)), 0, point)

    def test_uncropped_alpha_and_physical_reference(self):
        """人物与道具不得出画布；真实头顶和脚底必须是有像素的参考点。"""
        for entry in self.manifest['assets']:
            with self.subTest(identity=entry['id']):
                with Image.open(ASSETS / entry['file']) as image:
                    self.assertEqual(image.mode, 'RGBA')
                    self.assertEqual(list(image.size), entry['canvas'])
                    alpha = image.getchannel('A')
                    left, top, right, bottom = alpha.point(lambda a: 255 if a >= 128 else 0).getbbox()
                    self.assertGreater(min(left, top, image.width - right, image.height - bottom), 4)
                    for point in [(0, 0), (image.width-1, 0), (0, image.height-1), (image.width-1, image.height-1)]:
                        self.assertEqual(alpha.getpixel(point), 0)
                    self.assertGreater(alpha.getpixel(tuple(entry['crown_px'])), 127)
                    self.assertGreater(alpha.getpixel(tuple(entry['sole_pixel_px'])), 127)
                    self.assertGreater(entry['ground_y_px'], entry['sole_pixel_px'][1])
                    self.assertEqual(entry['ground_y_px'], entry['anchor_px'][1])
                    self.assertTrue(160 <= entry['height_cm'] <= 190)

if __name__ == '__main__':
    unittest.main()
