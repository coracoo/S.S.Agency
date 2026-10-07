"""视频角色通过FileAccess读图集；发布必须保留活动页的原PNG。"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_pack', Path(__file__).with_name('release_pack.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class VideoActionRelease(unittest.TestCase):
    def fixture(self, root):
        folder = root / 'assets/chars/pixel/rinne/video_actions'
        folder.mkdir(parents=True)
        prefix = 'res://assets/chars/pixel/rinne/video_actions/'
        data = {'anims': {'idle': {'frames': ['idle_1']}, 'attack': {'frames': ['attack_1']}},
                'packed_frames': {'idle_1': {'atlas': prefix+'sheets/shared.png'},
                                  'attack_1': {'atlas': prefix+'sheets/battle.png'},
                                  'unused': {'atlas': prefix+'sheets/unselected.png'}},
                'scene_integration': {'contact_metadata': prefix+'contact_points.json'},
                'art_revision': {'provenance': prefix+'provenance.json'}}
        (folder/'manifest.json').write_text(json.dumps(data))
        return folder, data

    def test_keep_used_atlases_and_metadata_without_native_caches(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder, _data = self.fixture(root)
            (folder/'unregistered.png').write_bytes(b'unused')
            sources = release.video_action_sources(root)
            prefix = 'assets/chars/pixel/rinne/video_actions/'
            self.assertEqual(sources, {prefix+'manifest.json', prefix+'sheets/shared.png',
                                      prefix+'sheets/battle.png', prefix+'contact_points.json'})

    def test_missing_used_frame_fails_instead_of_exporting_broken_actor(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder, data = self.fixture(root)
            del data['packed_frames']['attack_1']
            (folder/'manifest.json').write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                release.video_action_sources(root)

    def test_reject_paths_outside_project(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder, data = self.fixture(root)
            data['packed_frames']['attack_1']['atlas'] = 'res://../private.png'
            (folder/'manifest.json').write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                release.video_action_sources(root)


if __name__ == '__main__':
    unittest.main()
