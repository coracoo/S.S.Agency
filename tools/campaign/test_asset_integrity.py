#!/usr/bin/env python3
"""最终图像原始字节、透明度、七份manifest动态路径完整性。"""
import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    'hound': '19e3c8da9e1b9e79b67cd842aa3751a2ccf0e4fb42dd0c71125fc0286e294fd7',
    'shield_soldier': '1339c65fa163550b306b4d70fc77891ed5dbd6cf8fae3904abc1adbd518c5760',
    'fire_spirit': '18d735e30df7a86eead3a8f5b2127fac78a505963ec563105d511b12e01ccc7b',
    'cultist': 'e385bbac0b89cc43dda769a61744cf81028f9fcc0b9ebb9fe641ff0677eb67c5',
    'elite_shield_soldier': '7ab602d1a2122e661bef2101cba2025c9711017861a53e5fa967f83dd217d1b2',
    'gatekeeper': '3319142b7b7b827890752261b8b50caa901fa0e9b19b658622dbc3fbdcacae12',
}
class FinalAssets(unittest.TestCase):
    def test_registered_art_revisions_match_frames_atlases_and_contacts(self):
        retained={'walk5':'c0511a79e389f6492fe62c0f4a08e504a7d8d350b5257276bab6bf5188fc9f27',
                  'walk6':'fb50f0401b8a657ca2528ee7f11fb5da4b86eeb27c812a1cc62fa7aa388aa3e5',
                  'down':'6caf18d128d82e271c8bc2e937c39465475c09f54c3092292c2b4f5ccb7ed388'}
        for form in ['guard','rinne']:
            with self.subTest(form=form):
                manifest=json.loads((ROOT/f'assets/chars/pixel/{form}/high_detail_complete/manifest.json').read_text())
                self.assertIn('art_revision',manifest,'最终绘制修正须登记可追溯来源')
                revision=json.loads((ROOT/manifest['art_revision']['provenance'].removeprefix('res://')).read_text())
                contacts=json.loads((ROOT/manifest['scene_integration']['contact_metadata'].removeprefix('res://')).read_text())
                names={frame for animation in manifest['anims'].values() for frame in animation['frames']}
                self.assertEqual(len(names),22)
                self.assertEqual(set(revision['frames']),names)
                self.assertEqual(set(contacts['frames']),names)
                generated=[]
                for animation in manifest['anims'].values():
                    atlas_spec=animation['atlas']
                    with Image.open(ROOT/atlas_spec['path'].removeprefix('res://')) as atlas:
                        self.assertEqual(atlas.size,(manifest['canvas']['w']*atlas_spec['columns'],manifest['canvas']['h']*atlas_spec['rows']))
                        for index,name in enumerate(animation['frames']):
                            path=ROOT/(manifest['dir']+name+'.png').removeprefix('res://')
                            sha=hashlib.sha256(path.read_bytes()).hexdigest()
                            record=revision['frames'][name]
                            self.assertEqual(record['production_sha256'],sha)
                            self.assertEqual(contacts['frames'][name]['sha256'],sha)
                            with Image.open(path) as frame:
                                x=(index%atlas_spec['columns'])*frame.width;y=(index//atlas_spec['columns'])*frame.height
                                self.assertEqual(atlas.crop((x,y,x+frame.width,y+frame.height)).tobytes(),frame.tobytes(),'atlas须与正式原帧逐像素一致')
                            if record['selection']=='retained_original':
                                self.assertEqual(form,'rinne');self.assertIn(name,retained);self.assertEqual(sha,retained[name])
                            else:
                                self.assertEqual(record['selection'],'generated');generated.append(name)
                                self.assertEqual(len(record['raw_sha256']),64)
                                self.assertTrue(record['prompt'].strip())
                                self.assertNotIn('/workspace/',record['source_filename'])
                                self.assertGreater(record['mechanical_transform']['uniform_scale'],0)
                                self.assertEqual(len(record['mechanical_transform']['offset_px']),2)
                self.assertEqual(len(generated),22 if form=='guard' else 19)
    def test_final_enemy_original_bytes(self):
        config = json.loads((ROOT/'data/rpg/presentation.json').read_text())
        for key, expected in EXPECTED.items():
            with self.subTest(enemy_id=key):
                path = ROOT/'assets/chars/enemies/current'/f'{key}.png'
                self.assertTrue(path.is_file(), f'最终敌图缺失：{key}')
                if not path.is_file(): continue
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
                with Image.open(path) as im:
                    self.assertEqual(im.mode, 'RGBA')
                    self.assertEqual(im.size, (1024,1536))
                    self.assertEqual(im.getchannel('A').getextrema()[0], 0)
                    self.assertLess(im.getchannel('A').getextrema()[1], 255)
                self.assertEqual(config['enemy_art'][key], f'res://assets/chars/enemies/current/{key}.png')
                self.assertEqual(config['asset_facings'][config['enemy_art'][key]], 'right')
    def test_stature_measurements_use_unchanged_real_pixels(self):
        config = json.loads((ROOT/'data/characters/stature.json').read_text())
        for key, profile in config['forms'].items():
            with self.subTest(form=key):
                path = ROOT/profile['reference_frame'].removeprefix('res://')
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), profile['reference_sha256'])
                with Image.open(path) as im:
                    self.assertGreaterEqual(im.getpixel(tuple(profile['crown_px']))[3],128)
                    self.assertGreaterEqual(im.getpixel(tuple(profile['sole_pixel_px']))[3],128)
                    self.assertGreater(profile['ground_y_px'],profile['crown_px'][1])
                    self.assertEqual(profile['ground_y_px'],profile['sole_pixel_px'][1]+1)
                    self.assertLessEqual(profile['ground_y_px'],im.height)
    def test_seven_manifests_and_all_dynamic_frames(self):
        forms = ['rinne','mint','guard','homura_mage','homura_sword','healer','controller']
        identities = set()
        for form in forms:
            manifest = json.loads((ROOT/f'assets/chars/pixel/{form}/high_detail_complete/manifest.json').read_text())
            identities.add(manifest['identity_id'])
            for animation in manifest['anims'].values():
                for frame in animation['frames']:
                    self.assertTrue((ROOT/(manifest['dir']+frame+'.png').removeprefix('res://')).is_file())
        self.assertEqual(len(identities), 6)
if __name__ == '__main__': unittest.main()
