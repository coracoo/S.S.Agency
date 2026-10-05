"""第二夜可关闭HD2D完整variant：原场景保护、层级、来源与导出预算。"""
from pathlib import Path
import hashlib,json,unittest
from test_night02_source_asset import read_glb
ROOT=Path(__file__).resolve().parents[2]
ASSET=ROOT/'assets/3d/night02_corridor_hd2d'
class HD2DAsset(unittest.TestCase):
 def test_variant_and_untouched_fallback(self):
  self.assertEqual(hashlib.sha256((ROOT/'assets/3d/night02_corridor/night02_corridor.glb').read_bytes()).hexdigest(),'a95880eeb4ebe20c1c7dd20867273c2ae56fc7b94bfd9d918641d3c6480ec893')
  path=ASSET/'night02_corridor_hd2d.glb';self.assertTrue(path.exists(),'缺少独立HD2D完整variant')
  d=read_glb(path);names=[n.get('name') for n in d['nodes']]
  for name in ['MidCorridor','NearFrame','OuterForecourt','DistantGate','SideVeranda','HangingBell','SendoffFragment','OfferingTable','GuideLantern']:self.assertIn(name,names)
  self.assertFalse(d.get('cameras'));self.assertNotIn('KHR_lights_punctual',d.get('extensions',{}))
  self.assertLessEqual(len(d['meshes']),160)
  triangles=sum(d['accessors'][p['indices']]['count']//3 for m in d['meshes'] for p in m['primitives'])
  self.assertLess(triangles,400000)
  self.assertEqual(len(d['images']),5,'首夜/回廊相同原图按内容去重')
  for image in d['images']:self.assertIn('bufferView',image);self.assertNotIn('uri',image)
  for texture in d['textures']:self.assertLess(texture['source'],len(d['images']))
  def validate(value):
   if isinstance(value,dict):
    for key,child in value.items():
     if key.endswith('Texture') and isinstance(child,dict) and 'index' in child:self.assertLess(child['index'],len(d['textures']))
     validate(child)
   elif isinstance(value,list):
    for child in value:validate(child)
  validate(d['materials'])
  m=json.loads((ASSET/'source/manifest.json').read_text());self.assertEqual(m['production_sha256'],hashlib.sha256(path.read_bytes()).hexdigest())
  self.assertEqual(set(m['layer_world_bounds']),{'MidCorridor','NearFrame','OuterForecourt','DistantGate','SideVeranda'})
  self.assertTrue((ASSET/'source/.gdignore').exists());self.assertTrue((ASSET/'source/night02_hd2d_editable.blend').exists())
if __name__=='__main__':unittest.main()
