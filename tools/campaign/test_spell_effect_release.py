"""法术图集由原PNG解码；发布必须显式保留登记资源，不能递归纳入证据。"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_pack', Path(__file__).with_name('release_pack.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class SpellEffectRelease(unittest.TestCase):
    def test_actual_manifest_and_every_frame_strip_are_formal_originals(self):
        sources, _resources = release.formal_dependencies()
        folder = Path('assets/effects/illustrated_spells')
        manifest = json.loads((ROOT/folder/'manifest.json').read_text())
        self.assertIn((folder/'manifest.json').as_posix(),sources)
        for action in manifest['actions'].values():
            self.assertIn((folder/action['file']).as_posix(),sources)

    def test_scanner_only_retains_registered_atlases(self):
        self.assertTrue(hasattr(release,'spell_effect_sources'))
        if not hasattr(release,'spell_effect_sources'): return
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            folder=root/'assets/effects/illustrated_spells';folder.mkdir(parents=True)
            (folder/'manifest.json').write_text(json.dumps({'actions':{'firebolt':{'file':'firebolt.png'}}}))
            (folder/'firebolt.png').write_bytes(b'original')
            (folder/'review.png').write_bytes(b'evidence')
            self.assertEqual(release.spell_effect_sources(root),{'assets/effects/illustrated_spells/manifest.json','assets/effects/illustrated_spells/firebolt.png'})

if __name__=='__main__': unittest.main()
