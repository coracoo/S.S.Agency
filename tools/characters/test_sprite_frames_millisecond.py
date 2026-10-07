"""恢复最短帧的真实时间，防止编辑器SpriteFrames的0.01权重钳制。"""
import re
import tempfile
import unittest
from pathlib import Path
from write_video_sprite_frames import write_sprite_frames


class MillisecondTimingTests(unittest.TestCase):
    def test_shortest_archived_frame_survives_engine_weight_clamp(self):
        shortest = 1.7543859649122169
        manifest = {'packed_frames': {'frame': {'atlas': 'res://sheet.png', 'region': [0, 0, 2, 3], 'offset': [4, 5]}}, 'canvas': {'w': 20, 'h': 30}, 'anims': {'run': {'frames': ['frame'], 'durations_ms': [shortest], 'loop': True}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.tres'
            write_sprite_frames(manifest, path)
            text = path.read_text()
        weight = float(re.search(r'"duration": ([0-9.e+-]+)', text)[1])
        speed = float(re.search(r'"speed": ([0-9.e+-]+)', text)[1])
        self.assertAlmostEqual(max(weight, 0.01) / speed * 1000, shortest, places=9)
        self.assertEqual(speed, 1000)
        self.assertIn('region = Rect2(0, 0, 2, 3)', text)


if __name__ == '__main__':
    unittest.main()
