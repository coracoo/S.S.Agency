"""内殿资源契约：只验证来源/引用/空间，不替代固定镜头实拍。"""
import hashlib
import json
from pathlib import Path
import struct
import unittest
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', raw)
    assert magic == b'glTF' and version == 2 and length == len(raw)
    size, kind = struct.unpack_from('<I4s', raw, 12)
    assert kind == b'JSON'
    return json.loads(raw[20:20 + size])


class NightFourSourceAsset(unittest.TestCase):
    night = 4
    slug = 'night04_mirror'

    def setUp(self):
        self.directory = ROOT / 'assets/3d' / self.slug
        self.path = self.directory / (self.slug + '.glb')
        self.assertTrue(self.path.is_file(), '必须有原材质真实GLB，不能以积木wrapper替代')
        self.doc = read_glb(self.path)
        self.manifest = json.loads((self.directory / 'source/manifest.json').read_text())

    def test_embedded_original_five_images_and_references(self):
        d = self.doc
        self.assertEqual(len(d['images']), 5)
        for image in d['images']:
            self.assertIn('bufferView', image)
            self.assertNotIn('uri', image)
            self.assertLess(image['bufferView'], len(d['bufferViews']))
        def walk(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key.endswith('Texture') and isinstance(item, dict) and 'index' in item:
                        texture = d['textures'][item['index']]
                        self.assertLess(texture['source'], len(d['images']))
                    walk(item)
            elif isinstance(value, list):
                for item in value: walk(item)
        walk(d['materials'])
        materials = ' '.join(m.get('name', '') for m in d['materials'])
        for word in ('Aged cedar', 'Weathered washi', 'Blue gray glazed clay', 'Mossed stone', 'Muted lime plaster'):
            self.assertIn(word, materials)

    def test_hollow_is_deep_geometry_instead_of_front_disk(self):
        d = self.doc
        raw = self.path.read_bytes()
        json_length = struct.unpack_from('<I', raw, 12)[0]
        binary_start = 28 + json_length
        def values(index):
            a = d['accessors'][index]; v = d['bufferViews'][a['bufferView']]
            form = {5126: 'f', 5125: 'I', 5123: 'H'}[a['componentType']]
            size = {'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[a['type']]
            fmt = '<' + form * size
            stride = v.get('byteStride', struct.calcsize(fmt))
            start = binary_start + v.get('byteOffset', 0) + a.get('byteOffset', 0)
            return [struct.unpack_from(fmt, raw, start + i * stride) for i in range(a['count'])]
        node = next(n for n in d['nodes'] if n.get('name') == 'Hollow_tree_bark_roots_and_branches')
        x, y, front = (1.18, 1.377, -5.25) if self.night == 4 else (-.54, 1.53, -3.61)
        intersections = []
        for p in d['meshes'][node['mesh']]['primitives']:
            vertices = values(p['attributes']['POSITION']); indices = [i[0] for i in values(p['indices'])]
            for i in range(0, len(indices), 3):
                a,b,c = [vertices[k] for k in indices[i:i+3]]
                determinant = (b[1]-c[1])*(a[0]-c[0]) + (c[0]-b[0])*(a[1]-c[1])
                if abs(determinant) < 1e-8: continue
                u = ((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1])) / determinant
                v = ((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1])) / determinant
                w = 1-u-v
                if min(u,v,w) >= -1e-6:
                    intersections.append(u*a[2]+v*b[2]+w*c[2])
        self.assertTrue(intersections, '树洞后方须有真实内壁')
        self.assertLess(max(intersections), front-.6, '洞心射线不能撞到前置实心圆盘')

    def test_no_unadapted_sloped_grass_groups(self):
        self.assertNotIn('Source_ferns_on_outer_bank', [n.get('name') for n in self.doc['nodes']])

    def test_paper_attendants_have_real_support(self):
        if self.night != 5: return
        d=self.doc
        def all_nodes(index):
            yield d['nodes'][index]
            for child in d['nodes'][index].get('children', []): yield from all_nodes(child)
        def extrema(name, direction):
            index=next(i for i,n in enumerate(d['nodes']) if n.get('name')==name)
            values=[d['accessors'][p['attributes']['POSITION']][direction][1]
                    for n in all_nodes(index) if 'mesh' in n
                    for p in d['meshes'][n['mesh']]['primitives']]
            return (min if direction=='min' else max)(values)
        feet=extrema('PaperAttendants','min');ground=extrema('Rear_sanctuary_dais','max')
        self.assertLessEqual(feet-ground,.02,'纸人脚必须与界外实台接触')
        self.assertLessEqual(ground-feet,.03,'台面不能埋掉纸人脚')

    def test_independent_lighting_module_exists(self):
        path = ROOT / 'scripts/campaign/environments' / f'night_{self.night}_lighting.gd'
        self.assertTrue(path.is_file(), '资源光源须由独立Godot灯光模块接入')

    def test_actual_floor_and_tree_roof_mesh_bounds(self):
        d = self.doc
        def tree_nodes(index):
            node = d['nodes'][index]
            yield node
            for child in node.get('children', []):
                yield from tree_nodes(child)
        def bounds_of(name):
            index = next(i for i, n in enumerate(d['nodes']) if n.get('name') == name)
            accessors = [d['accessors'][p['attributes']['POSITION']]
                         for node in tree_nodes(index) if 'mesh' in node
                         for p in d['meshes'][node['mesh']]['primitives']]
            return ([min(a['min'][i] for a in accessors) for i in range(3)],
                    [max(a['max'][i] for a in accessors) for i in range(3)])
        floor = 'Aged_cedar_floor_original_planks' if self.night == 4 else 'Stone_forecourt_worn_slabs'
        self.assertLessEqual(bounds_of(floor)[1][1], .025)
        tlo, thi = bounds_of('SacredTreeHollow')
        rlo, rhi = bounds_of('RoofRafters')
        if self.night == 4:
            self.assertLess(thi[2], rlo[2] - .2, '第四夜神木必须实退到屋面之后')
        else:
            self.assertLess(rhi[2], tlo[2] - .2, '第五夜本殿必须实退到神木开放天井后')

    def test_source_hash_and_no_runtime_lights_or_cameras(self):
        self.assertEqual(self.manifest['production_sha256'], hashlib.sha256(self.path.read_bytes()).hexdigest())
        self.assertEqual(self.manifest['original_blend_sha256'], '94886b03ddbca36c01a431e69345ebd7b6863bd0c232b5e528aba7ecd2ea2727')
        self.assertTrue((self.directory / 'source' / (self.slug + '_editable.blend')).is_file())
        self.assertTrue((self.directory / 'source/.gdignore').is_file())
        self.assertFalse(self.doc.get('cameras'))
        self.assertNotIn('KHR_lights_punctual', self.doc.get('extensions', {}))
        self.assertLess(len(self.doc['meshes']), 150)

    def test_named_hero_parts_and_floor_plane(self):
        names = [n.get('name', '') for n in self.doc['nodes']]
        for name in ('RitualPaperCoffin', 'SacredTreeHollow', 'RoofRafters', 'CourtyardStones'):
            self.assertIn(name, names)
        self.assertLessEqual(self.manifest['floor_top'], .025)
        self.assertEqual(self.manifest['collision_policy'], '保留原碰撞，无新碰撞')
        self.assertGreaterEqual(self.manifest['tree_roof_gap_metres'], .2)
        if self.night == 4:
            self.assertIn('TiltedBronzeMirror', names)
            self.assertIn('HalfOpenPaperDoors', names)
        else:
            self.assertIn('CoffinShapedHollowMark', names)
            self.assertIn('PaperAttendants', names)
            self.assertIn('UpperRoofRafters', names)


class NightFiveSourceAsset(NightFourSourceAsset):
    night = 5
    slug = 'night05_honden'


def run_spatial_checks():
    """先核验实际user隔离位置，再执行两夜全bounds真胶囊轻测。"""
    with tempfile.TemporaryDirectory(prefix='ssa-inner-shrine-') as temporary:
        root = Path(temporary).resolve(); env = os.environ.copy()
        for key, name in [('XDG_DATA_HOME','data'), ('XDG_CONFIG_HOME','config'), ('XDG_CACHE_HOME','cache'), ('APPDATA','appdata'), ('LOCALAPPDATA','localappdata')]:
            path = root/name; path.mkdir(); env[key] = str(path)
        env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0', CAMPAIGN_ENVIRONMENT_NIGHTS='4,5')
        def run(script):
            return subprocess.run([os.environ.get('GODOT_BIN','godot'), '--headless', '--path', str(ROOT), '--script', script], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        result = run('res://tools/rpg/test_environment.gd'); print(result.stdout, end='')
        paths = re.findall(r'^RPG_ISOLATION_OK:(.*)$', result.stdout, re.M)
        if result.returncode or len(paths) != 1 or Path(paths[0]).resolve() == root or not Path(paths[0]).resolve().is_relative_to(root):
            raise RuntimeError('引擎实际user目录未通过隔离核验，停止')
        env['RPG_TEST_ISOLATED'] = '1'
        result = run('res://tools/campaign/test_night04_05_source_assets.gd'); print(result.stdout, end='')
        return int(bool(result.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', result.stdout)))


if __name__ == '__main__':
    if '--spatial' in sys.argv:
        raise SystemExit(run_spatial_checks())
    unittest.main()
