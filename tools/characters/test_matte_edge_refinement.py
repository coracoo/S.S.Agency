"""保守去溢色必须保住实体、alpha、合法绿色和细武器。"""
import importlib.util
from pathlib import Path
import unittest

import numpy as np
from PIL import Image

SCRIPT = Path(__file__).with_name('matte_edge_refinement.py')


class MatteEdgeTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), '缺少独立候选处理工具')
        spec = importlib.util.spec_from_file_location('matte_edge_refinement', SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def frame(self, body=(130, 110, 100, 255)):
        frame = np.zeros((40, 40, 4), dtype=np.uint8)
        frame[10:30, 10:30] = body
        return frame

    def test_soft_green_and_magenta_reduce_without_alpha_or_core_change(self):
        src = self.frame()
        src[9, 14:20] = [60, 190, 55, 64]
        src[30, 14:20] = [180, 40, 150, 64]
        out, stats = self.module.refine_frame(Image.fromarray(src))
        result = np.array(out)
        np.testing.assert_array_equal(result[:, :, 3], src[:, :, 3])
        np.testing.assert_array_equal(result[10:30, 10:30], src[10:30, 10:30])
        self.assertLess(result[9, 15, 1], src[9, 15, 1])
        self.assertGreater(result[30, 15, 1], src[30, 15, 1])
        self.assertEqual(stats['alpha_changed_pixels'], 0)

    def test_similar_green_material_and_protected_area_are_unchanged(self):
        src = self.frame((45, 150, 45, 255))
        src[9, 14:20] = [50, 165, 50, 64]
        for profile in ('v1', 'v2'):
            out, _ = self.module.refine_frame(Image.fromarray(src), profile=profile)
            np.testing.assert_array_equal(np.array(out), src)
        polluted = self.frame()
        polluted[9, 14:20] = [40, 190, 40, 64]
        protected = np.zeros((40, 40), dtype=bool)
        protected[:12] = True
        for profile in ('v1', 'v2'):
            out, _ = self.module.refine_frame(Image.fromarray(polluted), protected=protected, profile=profile)
            np.testing.assert_array_equal(np.array(out), polluted)

    def test_thin_weapon_and_opaque_contamination_are_never_eroded(self):
        src = self.frame()
        src[10, 2:10] = [190, 190, 190, 255]
        src[11, 15] = [20, 200, 20, 255]
        out, _ = self.module.refine_frame(Image.fromarray(src))
        np.testing.assert_array_equal(np.array(out), src)

    def test_v2_can_refine_opaque_outer_edge_but_preserves_all_alpha_and_interior(self):
        src = self.frame()
        src[10, 14:20] = [30, 190, 30, 255]
        src[20, 18] = [30, 190, 30, 255]
        out, stats = self.module.refine_frame(Image.fromarray(src), profile='v2')
        result = np.array(out)
        self.assertLess(result[10, 15, 1], src[10, 15, 1])
        np.testing.assert_array_equal(result[:, :, 3], src[:, :, 3])
        np.testing.assert_array_equal(result[15:26, 15:26], src[15:26, 15:26])
        self.assertEqual(stats['interior_pixels_changed'], 0)

    def test_micro_specks_require_two_neighbors_and_preserve_supported_points(self):
        src = self.frame()
        src[3, 3] = [120, 120, 120, 24]
        src[3, 30] = [120, 120, 120, 90]
        empty = np.zeros((40, 40), dtype=bool)
        out, _ = self.module.refine_frame(Image.fromarray(src), clean_specks=True)
        self.assertEqual(np.array(out)[3, 3, 3], 24)
        out, _ = self.module.refine_frame(Image.fromarray(src), clean_specks=True, neighbors=(empty, empty))
        self.assertEqual(np.array(out)[3, 3, 3], 0)
        self.assertEqual(np.array(out)[3, 30, 3], 90)
        supported = empty.copy()
        supported[3, 3] = True
        out, _ = self.module.refine_frame(Image.fromarray(src), clean_specks=True, neighbors=(supported, empty))
        self.assertEqual(np.array(out)[3, 3, 3], 24)


if __name__ == '__main__':
    unittest.main()
