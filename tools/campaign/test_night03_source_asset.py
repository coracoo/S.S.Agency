"""第三夜同源石道：纹理引用、可编辑来源与真实空间轻量契约。"""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/3d/night03_procession'


def read_glb(path):
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from('<4sII', raw)
    assert magic == b'glTF' and version == 2 and size == len(raw)
    length, kind = struct.unpack_from('<I4s', raw, 12)
    assert kind == b'JSON'
    return json.loads(raw[20:20 + length])


class NightThreeSourceAsset(unittest.TestCase):
    def setUp(self):
        self.path = ASSET / 'night03_procession.glb'
        self.assertTrue(self.path.is_file(), '第三夜必须有真实同源GLB，不能仍依赖纯色box')
        self.doc = read_glb(self.path)

    def test_embedded_source_textures_are_valid(self):
        d = self.doc
        self.assertGreaterEqual(len(d.get('images', [])), 3)
        for img in d['images']:
            self.assertNotIn('uri', img)
            self.assertLess(img['bufferView'], len(d['bufferViews']))
        def inspect(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    if key.endswith('Texture') and isinstance(child, dict) and 'index' in child:
                        self.assertLess(child['index'], len(d['textures']))
                        self.assertLess(d['textures'][child['index']]['source'], len(d['images']))
                    inspect(child)
            elif isinstance(value, list):
                for child in value: inspect(child)
        inspect(d['materials'])
        names = ' '.join(m.get('name', '') for m in d['materials'])
        for signature in ('Aged cedar', 'Weathered washi', 'Mossed stone'):
            self.assertIn(signature, names)
        for m in d['materials']:
            if m.get('name', '').startswith(('Mossed stone', 'Weathered washi', 'Aged cedar')):
                self.assertIn('baseColorTexture', m['pbrMetallicRoughness'])

    def test_batched_real_outdoor_components(self):
        d = self.doc
        self.assertLessEqual(len(d['meshes']), 80)
        self.assertGreaterEqual(len(d['meshes']), 25)
        triangles = sum(d['accessors'][p['indices']]['count'] // 3 for m in d['meshes'] for p in m['primitives'])
        self.assertGreater(triangles, 25000)
        self.assertLess(triangles, 230000)
        self.assertFalse(d.get('cameras'))
        self.assertNotIn('KHR_lights_punctual', d.get('extensions', {}))
        names = [n.get('name', '') for n in d['nodes']]
        for name in ('StoneProcessionPath', 'ShrineEnclosure', 'DistantTorii', 'PaperCoffin', 'CoffinLightSeam', 'CarryingPoles', 'PaperProcession', 'StoneLanterns'):
            self.assertIn(name, names)
        self.assertNotIn('PaperDoors', names)
        self.assertEqual(len([n for n in names if n.startswith('PaperAttendant_')]), 7)
        for mesh in d['meshes']:
            for primitive in mesh['primitives']:
                if 'baseColorTexture' in d['materials'][primitive['material']].get('pbrMetallicRoughness', {}):
                    self.assertIn('TEXCOORD_0', primitive['attributes'])

    def test_paper_uv_selects_quiet_original_fibres_and_figures_have_solid_support(self):
        d = self.doc
        names = {node.get('name'): node for node in d['nodes']}
        self.assertIn('Raised_rear_earth_supports_procession', names, '后墙外抬高土台必须支撑整列纸人')
        raw = self.path.read_bytes(); json_size = struct.unpack_from('<I', raw, 12)[0]
        inspected = 0
        for mesh in d['meshes']:
            for primitive in mesh['primitives']:
                if not d['materials'][primitive['material']]['name'].startswith('Weathered washi'): continue
                inspected += 1
                acc = d['accessors'][primitive['attributes']['TEXCOORD_0']]
                view = d['bufferViews'][acc['bufferView']]
                offset = 28 + json_size + view.get('byteOffset', 0) + acc.get('byteOffset', 0)
                stride = view.get('byteStride', 8)
                uv = [struct.unpack_from('<ff', raw, offset + index * stride) for index in range(acc['count'])]
                self.assertTrue(all(.399 < u < .641 and .009 < v < .141 for u, v in uv), '纸纹只取原图清净纤维区，避免密重复树影斑')
        self.assertGreater(inspected, 7)

    def test_lighting_module_has_public_entry_points(self):
        path = ROOT / 'scripts/campaign/environments/night_3_lighting.gd'
        self.assertTrue(path.is_file(), '第三夜使用独立轻量夜色/石灯模块')
        source = path.read_text()
        self.assertIn('static func setup_environment(', source)
        self.assertIn('static func build_lights(', source)

    def test_rebuildable_source_and_origin_manifest(self):
        manifest = json.loads((ASSET / 'source/manifest.json').read_text())
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).hexdigest(), manifest['production_sha256'])
        self.assertEqual(manifest['original_blend_sha256'], '94886b03ddbca36c01a431e69345ebd7b6863bd0c232b5e528aba7ecd2ea2727')
        self.assertEqual(hashlib.sha256((ROOT / 'assets/3d/act01_approach/act01_approach.glb').read_bytes()).hexdigest(), manifest['approach_glb_sha256'])
        for name in ('night03_procession_editable.blend', 'build_procession.py', 'README.md', '.gdignore'):
            self.assertTrue((ASSET / 'source' / name).is_file())
        self.assertEqual(manifest['paper_attendants'], 7)
        self.assertLessEqual(manifest['visual_wall_height'], .6)

    @unittest.skipUnless(os.environ.get('NIGHT03_RUN_GODOT') == '1', '按需执行隔离Godot胶囊轻测')
    def test_isolated_real_godot_space(self):
        with tempfile.TemporaryDirectory(prefix='ssa-night03-source-') as directory:
            root = Path(directory).resolve(); env = os.environ.copy()
            for var, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
                target = root / name; target.mkdir(); env[var] = str(target)
            env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0')
            def run(script):
                proc = subprocess.run([os.environ.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT), '--script', script], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                print(proc.stdout)
                self.assertEqual(proc.returncode, 0, proc.stdout)
                self.assertFalse(re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', proc.stdout), proc.stdout)
                return proc.stdout
            output = run('res://tools/rpg/test_environment.gd')
            paths = [line.split(':', 1)[1].strip() for line in output.splitlines() if line.startswith('RPG_ISOLATION_OK:')]
            self.assertEqual(len(paths), 1)
            self.assertTrue(Path(paths[0]).resolve().is_relative_to(root))
            self.assertNotEqual(Path(paths[0]).resolve(), root)
            env['RPG_TEST_ISOLATED'] = '1'
            output = run('res://tools/campaign/test_night03_source_asset.gd')
            self.assertIn('unsafe_meshes=0', output)


if __name__ == '__main__':
    unittest.main()
