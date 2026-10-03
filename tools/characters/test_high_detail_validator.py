import json
from pathlib import Path
import tempfile
import unittest
from validate_assets import ROOT, validate_manifest

class HighDetailContract(unittest.TestCase):
    path=ROOT/'assets/chars/pixel/guard/high_detail_complete/manifest.json'

    def validate_high(self,path):
        try:
            return validate_manifest(path,profile='high_detail')
        except TypeError:
            return ['尚未支持显式高细节合同']

    def test_real_full_set_keeps_native_resolution_and_colors(self):
        self.assertEqual([],self.validate_high(self.path))

    def test_low_density_cannot_claim_high_detail(self):
        manifest=json.loads(self.path.read_text())
        manifest['canvas']['content_height_px']=104
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'manifest.json'
            path.write_text(json.dumps(manifest))
            self.assertTrue(any('1024' in e for e in self.validate_high(path)))

if __name__=='__main__':unittest.main()
