import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from PIL import Image, ImageDraw

class AssetsTest(unittest.TestCase):
    def test_high_detail_preserves_soft_alpha_and_rejects_missing_body(self):
        path=Path(__file__).with_name('validate_assets.py')
        spec=importlib.util.spec_from_file_location('validator',path)
        validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
        project=Path(__file__).resolve().parents[2]
        manifest=json.loads((project/'assets/chars/pixel/guard/high_detail_complete/manifest.json').read_text())
        manifest['dir']='res://'
        for animation in manifest['anims'].values():
            animation['frames']=['sample']*len(animation['frames'])
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);candidate=root/'manifest.json';candidate.write_text(json.dumps(manifest))
            image=Image.new('RGBA',(1216,1216))
            ImageDraw.Draw(image).rectangle((400,100,800,1100),fill=(40,50,60,250))
            image.putpixel((399,500),(40,50,60,80));image.save(root/'sample.png')
            self.assertEqual([],validator.validate_manifest(candidate,root,profile='high_detail'))
            image.putpixel((0,500),(40,50,60,1));image.save(root/'sample.png')
            self.assertEqual([],validator.validate_manifest(candidate,root,profile='high_detail'), '保留不可见alpha=1边缘噪点不能误报主体裁切')
            image.putpixel((0,500),(40,50,60,8));image.save(root/'sample.png')
            self.assertTrue(any('边缘' in error for error in validator.validate_manifest(candidate,root,profile='high_detail')), 'alpha=8软边到画布边缘仍拒绝')
            image.putpixel((0,500),(40,50,60,128));image.save(root/'sample.png')
            self.assertTrue(any('边缘' in error for error in validator.validate_manifest(candidate,root,profile='high_detail')), '真实实体到画布边缘仍拒绝')
            for name,image in [('opaque_background',Image.new('RGBA',(1216,1216),(40,50,60,255))),
                               ('empty',Image.new('RGBA',(1216,1216))),
                               ('no_effective_body',Image.new('RGBA',(1216,1216)))]:
                if name=='no_effective_body':
                    ImageDraw.Draw(image).rectangle((400,100,800,1100),fill=(40,50,60,7))
                image.save(root/'sample.png')
                with self.subTest(name=name):
                    errors=validator.validate_manifest(candidate,root,profile='high_detail')
                    expected='透明背景' if name=='opaque_background' else '有效人物主体'
                    self.assertTrue(any(expected in error for error in errors),errors)
            image=Image.new('RGBA',(1216,1216));image.putpixel((608,600),(40,50,60,255));image.save(root/'sample.png')
            self.assertTrue(any('有效人物主体' in error for error in validator.validate_manifest(candidate,root,profile='high_detail')), '孤立像素不能充当有效人物主体')
    def test_validator_detects_dirty_alpha_and_missing_motion(self):
        path = Path(__file__).with_name('validate_assets.py')
        self.assertTrue(path.exists(), '生产资产校验器尚未实现')
        spec = importlib.util.spec_from_file_location('validator', path)
        validator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(validator)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            image = Image.new('RGBA', (192, 160))
            image.putpixel((96,148), (40,50,60,255))
            image.save(root/'sample.png')
            manifest = {'canvas':{'w':192,'h':160,'anchor':[96,148]},'dir':'res://',
                        'anims':{'idle':{'frames':['sample'],'durations_ms':[3000],'loop':True}}}
            (root/'manifest.json').write_text(json.dumps(manifest))
            errors = validator.validate_manifest(root/'manifest.json',root)
            self.assertTrue(any('walk' in x for x in errors))
            self.assertTrue(any('idle' in x for x in errors))
            image.putpixel((20,20), (255,255,255,7)); image.save(root/'sample.png')
            errors = validator.validate_manifest(root/'manifest.json',root)
            self.assertTrue(any('alpha' in x for x in errors))
            image = Image.new('RGBA',(191,160));image.save(root/'sample.png')
            errors = validator.validate_manifest(root/'manifest.json',root)
            self.assertTrue(any('192' in x for x in errors))
    def test_equal_total_cannot_hide_changed_walk_phase(self):
        path=Path(__file__).with_name('validate_assets.py')
        spec=importlib.util.spec_from_file_location('validator',path)
        validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
        root=Path(__file__).resolve().parents[2]
        manifest=json.loads((root/'old/characters/assets/chars/pixel/rinne/manifest.json').read_text())
        durations=manifest['anims']['walk']['durations_ms']
        durations[0],durations[4]=durations[4],durations[0]
        with tempfile.TemporaryDirectory() as tmp:
            candidate=Path(tmp)/'manifest.json'
            candidate.write_text(json.dumps(manifest))
            self.assertTrue(any('相位' in x for x in validator.validate_manifest(candidate,root)))
    def test_accepted_eight_phase_material_revision_is_valid(self):
        path=Path(__file__).with_name('validate_assets.py')
        spec=importlib.util.spec_from_file_location('validator',path)
        validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
        root=Path(__file__).resolve().parents[2]
        self.assertEqual([],validator.validate_manifest(root/'assets/chars/pixel/rinne/frame_material_refined/manifest.json',root))
    def test_all_resolves_delivery_roster_revisions(self):
        result=subprocess.run([sys.executable,str(Path(__file__).with_name('validate_assets.py')),'--all'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertIn('healer: PASS',result.stdout)
        self.assertEqual(result.stdout.count(': PASS'),7)
if __name__ == '__main__': unittest.main()
