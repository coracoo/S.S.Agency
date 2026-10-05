"""第二夜原稿派生资源：嵌入贴图、结构合批及来源可追溯契约。"""
import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/3d/night02_corridor'


def read_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data)
    assert magic == b'glTF' and version == 2 and length == len(data)
    json_size, kind = struct.unpack_from('<I4s', data, 12)
    assert kind == b'JSON'
    return json.loads(data[20:20 + json_size])


class NightTwoSourceAsset(unittest.TestCase):
    def setUp(self):
        self.path = ASSET / 'night02_corridor.glb'
        self.assertTrue(self.path.exists(), '缺少原稿派生GLB；不能用积木模块通过门禁')
        self.doc = read_glb(self.path)

    def test_embedded_textures_have_no_dangling_references(self):
        d = self.doc
        self.assertGreaterEqual(len(d.get('images', [])), 5)
        for image in d['images']:
            self.assertIn('bufferView', image)
            self.assertNotIn('uri', image)
            self.assertLess(image['bufferView'], len(d['bufferViews']))
        def inspect(obj):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    if key.endswith('Texture') and isinstance(value, dict) and 'index' in value:
                        texture = d['textures'][value['index']]
                        self.assertLess(texture['source'], len(d['images']))
                    inspect(value)
            elif isinstance(obj, list):
                for value in obj: inspect(value)
        inspect(d['materials'])
        names = ' '.join(m.get('name', '') for m in d['materials'])
        for signature in ('Aged cedar', 'Weathered washi', 'Blue gray glazed clay', 'Mossed stone'):
            self.assertIn(signature, names)

    def test_batched_meshes_and_game_only_content(self):
        d = self.doc
        self.assertGreaterEqual(len(d['meshes']), 20)
        self.assertLessEqual(len(d['meshes']), 140)
        triangles = sum(d['accessors'][p['indices']]['count'] // 3 for m in d['meshes'] for p in m['primitives'])
        self.assertGreater(triangles, 50000)
        self.assertLess(triangles, 260000)
        self.assertFalse(d.get('cameras'))
        self.assertNotIn('KHR_lights_punctual', d.get('extensions', {}))
        names = [n.get('name') for n in d['nodes']]
        for name in ('CorridorArchitecture', 'PaperDoors', 'RoofRafters', 'HangingBell', 'SendoffFragment', 'OfferingTable', 'GuideLantern', 'CourtyardFront'):
            self.assertIn(name, names)

    def test_floor_uv_uses_physical_scale_instead_of_small_cube_island(self):
        d = self.doc
        node = next(n for n in d['nodes'] if n.get('name') == 'Deck_aged_cedar_planks_nails')
        primitive = next(p for p in d['meshes'][node['mesh']]['primitives'] if d['materials'][p['material']]['name'].startswith('Aged cedar'))
        accessor = d['accessors'][primitive['attributes']['TEXCOORD_0']]
        view = d['bufferViews'][accessor['bufferView']]
        binary = self.path.read_bytes()
        json_size = struct.unpack_from('<I', binary, 12)[0]
        offset = 20 + json_size + 8 + view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        self.assertEqual(accessor['componentType'], 5126)
        stride = view.get('byteStride', 8)
        u = [struct.unpack_from('<f', binary, offset + index * stride)[0] for index in range(accessor['count'])]
        self.assertGreater(max(u) - min(u), 4, '长板不再只挤入四分之一cube UV岛')

    def test_lantern_paper_not_flat_white_and_exterior_stair_removed(self):
        d = self.doc
        lamp = next(m for m in d['materials'] if m['name'] == 'Lantern warm paper')
        self.assertIn('baseColorTexture', lamp['pbrMetallicRoughness'])
        self.assertLess(max(lamp['emissiveFactor']), .5)
        self.assertNotIn('Exterior_three_worn_steps', [n.get('name') for n in d['nodes']])

    def test_foundation_interlocks_with_existing_soil_and_uses_source_stone_texture(self):
        d = self.doc
        nodes = {n.get('name'): n for n in d['nodes']}
        for name in ('Deck_underfloor_ground_join', 'Earth_bank_against_foundation'):
            self.assertIn(name, nodes, '修复廊下蓝缝需要相接的真实台基/浅土坡')
        def mesh_bounds(name):
            primitive = d['meshes'][nodes[name]['mesh']]['primitives'][0]
            accessor = d['accessors'][primitive['attributes']['POSITION']]
            return accessor['min'], accessor['max']
        join_min, join_max = mesh_bounds('Deck_underfloor_ground_join')
        soil_min, soil_max = mesh_bounds('Garden_ground_below_deck')
        bank_min, bank_max = mesh_bounds('Earth_bank_against_foundation')
        self.assertLess(join_min[1], soil_max[1])
        self.assertGreater(join_max[2], soil_min[2])
        self.assertLess(bank_min[2], soil_min[2])
        self.assertGreater(bank_max[1], soil_max[1] + .1)
        material = next(m for m in d['materials'] if 'muted earth tint' in m['name'])['pbrMetallicRoughness']
        stone = next(m for m in d['materials'] if m['name'] == 'Mossed stone • painted gray green')['pbrMetallicRoughness']
        self.assertEqual(d['textures'][material['baseColorTexture']['index']]['source'], d['textures'][stone['baseColorTexture']['index']]['source'])
        self.assertGreater(material['baseColorFactor'][0], material['baseColorFactor'][2])

    def test_editable_source_and_reproducible_manifest(self):
        manifest = json.loads((ASSET / 'source/manifest.json').read_text())
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).hexdigest(), manifest['production_sha256'])
        self.assertEqual(len(manifest['original_blend_sha256']), 64)
        self.assertTrue((ASSET / 'source/night02_corridor_editable.blend').is_file())
        self.assertTrue((ASSET / 'source/build_corridor.py').is_file())
        self.assertTrue((ASSET / 'source/.gdignore').is_file())
        self.assertEqual(manifest['original_textures_reused'], 5)


if __name__ == '__main__':
    unittest.main()
