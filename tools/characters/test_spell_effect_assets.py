"""透明图集来源/帧选择/alpha与全技能覆盖；不以此代替美术目检。"""
import hashlib
import json
from pathlib import Path
import re
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/effects/illustrated_spells'

class SpellEffectAssets(unittest.TestCase):
    def test_all_profiles_have_complete_clean_rgba_frame_strips(self):
        manifest = json.loads((ASSETS / 'manifest.json').read_text())
        rows = re.findall(r'^\s*\["([^"]+)","([^"]+)","([^"]+)"', (ROOT / 'scripts/rpg/ui/skill_effect_profiles.gd').read_text(), re.M)
        skills = {s['id']:s for s in json.loads((ROOT/'data/rpg/skills.json').read_text())['definitions']}
        self.assertEqual(set(skills), {r[0] for r in rows})
        for skill, name, target_rule in rows:
            with self.subTest(skill=skill):
                self.assertEqual(skills[skill]['target_rule'], target_rule)
                self.assertIn(name, manifest['actions'], '每个运行技能必须有完整实际帧资源')
                entry = manifest['actions'][name]
                path = ASSETS / entry['file']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),entry['sha256'])
                self.assertEqual(entry['selected_frames'],list(range(24)))
                self.assertEqual(entry['phases']['cast'],list(range(6)))
                self.assertEqual(entry['phases']['projectile'],list(range(6,12)))
                self.assertEqual(entry['phases']['impact'],list(range(12,24)))
                with Image.open(path) as atlas:
                    self.assertEqual(atlas.mode,'RGBA')
                    self.assertEqual(atlas.size,(1152,768))
                    for i in range(24):
                        frame=atlas.crop(((i%6)*192,(i//6)*192,(i%6+1)*192,(i//6+1)*192))
                        self.assertEqual(hashlib.sha256(frame.tobytes()).hexdigest(),entry['frames_rgba_sha256'][i])
                        box=frame.getchannel('A').getbbox()
                        if i==23:
                            self.assertIsNone(box,'最后一帧必须透明结束')
                        else:
                            self.assertIsNotNone(box)
                            self.assertTrue(box[0]>0 and box[1]>0 and box[2]<192 and box[3]<192,f'帧{i}不得裁边: {box}')
                            self.assertEqual(frame.getpixel((0,0)),(0,0,0,0))
        self.assertEqual(manifest['generator_sha256'], hashlib.sha256((ROOT/'tools/characters/build_spell_effect_atlases.py').read_bytes()).hexdigest())

    def test_caster_silhouettes_are_not_recolored_circles(self):
        names=['firebolt','flame_wave','ice_arrow','burn_brand','heal','group_heal','cleanse','holy_shield','weaken','slow','seal','magic_break']
        silhouettes=set()
        for name in names:
            path=ASSETS/(name+'.png')
            self.assertTrue(path.exists(),f'{name}缺少实际图集')
            with Image.open(path) as im:
                silhouettes.add(hashlib.sha256(im.getchannel('A').tobytes()).hexdigest())
        self.assertEqual(len(silhouettes),12)

    def test_seal_has_authored_motion_before_hit(self):
        with Image.open(ASSETS/'seal.png') as atlas:
            for phase in [range(6),range(6,12)]:
                frames={hashlib.sha256(atlas.crop(((i%6)*192,(i//6)*192,(i%6+1)*192,(i//6+1)*192)).tobytes()).hexdigest() for i in phase}
                self.assertGreater(len(frames),2,'封条起手/纸签飛行不能只复用一张图标')

if __name__=='__main__': unittest.main()
