import hashlib, importlib.util, os, unittest
from pathlib import Path

PROJECT=Path(os.environ.get('SSA_PAPER_PROJECT',Path(__file__).resolve().parents[2]))
spec=importlib.util.spec_from_file_location('release_pack',PROJECT/'tools/campaign/release_pack.py')
release_pack=importlib.util.module_from_spec(spec);spec.loader.exec_module(release_pack)

class PaperRelease(unittest.TestCase):
    def test_only_reviewed_raw_papers_are_packaged(self):
        sources,resources=release_pack.formal_dependencies(PROJECT)
        expected={'leaf-candidate.png':'918abbe011a43549137dda6608b413afccc844c8e2f4f5c9b8244a227b92a402','summary-candidate.png':'dd4dcf62a2142795c57ca9e5dcbd220c3efc5e721b492dda25668f51e9d3e382'}
        for name,digest in expected.items():
            path='assets/ui/battle_washi_20261020/'+name
            with self.subTest(asset=path):
                self.assertTrue(path in sources,'Raw Image loader requires original PNG in release pack: '+path)
                self.assertEqual(hashlib.sha256(sources[path].read_bytes()).hexdigest(),digest)
        self.assertIn('scripts/rpg/ui/battle_paper_styles.gd',resources)
        self.assertNotIn('assets/ui/battle_washi_20261020/provenance.json',sources)
        self.assertNotIn('assets/ui/battle_washi_20261020/provenance.json',resources)

if __name__=='__main__':unittest.main()
