"""用可解释的小图验证审计指标，避免将紧裁图框和正常位移误判为缺陷。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image


SCRIPT = Path(__file__).with_name('audit_video_alpha.py')


class AlphaAuditTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), '缺少可复现审计工具')
        spec = importlib.util.spec_from_file_location('audit_video_alpha', SCRIPT)
        self.audit = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.audit)

    def body(self):
        pixels = np.zeros((40, 40, 4), dtype=np.uint8)
        pixels[8:32, 8:32] = [140, 110, 90, 255]
        return pixels

    def test_holes_and_isolated_specks_have_locations(self):
        pixels = self.body()
        pixels[18:20, 18:20, 3] = 0
        pixels[2, 2] = [90, 90, 90, 128]
        result = self.audit.measure_frame(Image.fromarray(pixels))
        self.assertEqual(result['small_hole_pixels'], 4)
        self.assertEqual(result['isolated_small_pixels'], 1)
        self.assertEqual(result['hole_examples'][0]['bbox'], [18, 18, 20, 20])

    def test_residual_green_detected_only_on_visible_edge(self):
        pixels = self.body()
        pixels[8, 10:20] = [70, 180, 70, 100]
        pixels[15, 15] = [30, 200, 30, 255]
        pixels[0, 0] = [0, 255, 0, 0]
        result = self.audit.measure_frame(Image.fromarray(pixels))
        self.assertEqual(result['edge_green_pixels'], 10)
        self.assertEqual(result['opaque_interior_green_pixels'], 1)

    def test_magenta_fringe_is_recorded_separately(self):
        pixels = self.body()
        pixels[8, 10:20] = [180, 40, 160, 100]
        result = self.audit.measure_frame(Image.fromarray(pixels))
        self.assertIn('edge_magenta_pixels', result, '缺少洋红边线索指标')
        self.assertEqual(result['edge_magenta_pixels'], 10)
        self.assertEqual(result['edge_green_pixels'], 0)

    def test_tight_crop_edges_are_not_logical_canvas_clipping(self):
        pixels = np.full((20, 20, 4), 255, dtype=np.uint8)
        result = self.audit.measure_frame(Image.fromarray(pixels), offset=(30, 40), canvas=(100, 100))
        self.assertGreater(result['crop_border_opaque_pixels'], 0)
        self.assertEqual(result['canvas_border_visible_pixels'], 0)
        clipped = self.audit.measure_frame(Image.fromarray(pixels), offset=(0, 0), canvas=(20, 20))
        self.assertGreater(clipped['canvas_border_visible_pixels'], 0)

    def test_empty_frame_is_explicit(self):
        result = self.audit.measure_frame(Image.new('RGBA', (20, 20)))
        self.assertTrue(result['empty'])
        self.assertEqual(result['alpha_area'], 0)
        self.assertEqual(result['edge_green_fraction'], 0)

    def test_temporal_area_change_does_not_confuse_translation(self):
        first = self.audit.measure_frame(Image.fromarray(self.body()), offset=(0, 0))
        second = self.audit.measure_frame(Image.fromarray(self.body()), offset=(10, 0))
        result = self.audit.temporal_pair(first, second)
        self.assertEqual(result['alpha_area_relative_change'], 0)
        self.assertEqual(result['centroid_distance_px'], 10)

    def test_output_must_be_outside_repository(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaises(ValueError):
                self.audit.validate_output(root, root / 'build' / 'audit')
            with self.assertRaises(ValueError):
                self.audit.validate_output(root, root.parent)


if __name__ == '__main__':
    unittest.main()
