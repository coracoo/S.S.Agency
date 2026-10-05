"""第二夜HD2D独立完整variant；安全复用R03和首夜原生网格，不写fallback。"""
import bpy,bmesh,json,hashlib,math,sys
from pathlib import Path
from mathutils import Matrix,Vector
HERE=Path(__file__).resolve().parent;OUT=HERE.parent;ROOT=HERE.parents[3]
BASE=ROOT/'assets/3d/night02_corridor/source/night02_corridor_editable.blend'
APPROACH=ROOT/'assets/3d/act01_approach/act01_approach.glb'
FALLBACK=ROOT/'assets/3d/night02_corridor/night02_corridor.glb'
FALLBACK_HASH='a95880eeb4ebe20c1c7dd20867273c2ae56fc7b94bfd9d918641d3c6480ec893'
assert hashlib.sha256(FALLBACK.read_bytes()).hexdigest()==FALLBACK_HASH
bpy.ops.wm.open_mainfile(filepath=str(BASE),use_scripts=False)
for ob in list(bpy.data.objects):
 if ob.type=='MESH':
  data=ob.data.copy();data.transform(ob.matrix_world);ob.data=data;ob.matrix_world=Matrix.Identity(4)
base={o.name:o.data.copy() for o in bpy.data.objects if o.type=='MESH'}

def bounds_data(data):
 return Vector(tuple(min(v.co[i] for v in data.vertices) for i in range(3))),Vector(tuple(max(v.co[i] for v in data.vertices) for i in range(3)))
def bounds_set(data):
 bb=[bounds_data(d) for d in data];return Vector(tuple(min(b[0][i] for b in bb) for i in range(3))),Vector(tuple(max(b[1][i] for b in bb) for i in range(3)))
def matrix(scale=(1,1,1),offset=(0,0,0)):
 m=Matrix.Diagonal((*scale,1));m.translation=Vector(offset);return m
def fit(data,center,size):
 lo,hi=bounds_set(data);s=Vector(tuple(size[i]/max(hi[i]-lo[i],.001) for i in range(3)));return matrix(s,Vector(center)-(lo+hi)*.5*s)
def group(name,parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;return o
def mesh(name,data,parent,transform=None):
 d=data.copy()
 if transform is not None:d.transform(transform)
 o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.parent=parent;return o
def join(name,objects,parent):
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=name;o.parent=parent;return o
def clip(data,limit):
 bm=bmesh.new();bm.from_mesh(data)
 for sign in (-1,1):
  geom=list(bm.verts)+list(bm.edges)+list(bm.faces)
  bmesh.ops.bisect_plane(bm,geom=geom,dist=.00001,plane_co=(sign*limit,0,0),plane_no=(sign,0,0),clear_outer=True,clear_inner=False)
 bm.to_mesh(data);bm.free();data.update()
def clone_set(name,names,library,parent,center_xy,scale,bottom):
 data=[library[n] for n in names];lo,hi=bounds_set(data);c=(lo+hi)*.5
 t=matrix((scale,)*3,(center_xy[0]-c.x*scale,center_xy[1]-c.y*scale,bottom-lo.z*scale))
 return join(name,[mesh(name+'_'+str(i),d,parent,t) for i,d in enumerate(data)],parent)

root=group('Night02HD2DVariant')
mid=bpy.data.objects['Night02SourceCorridor'];mid.name='MidCorridor';mid.parent=root
near=group('NearFrame',root);outer=group('OuterForecourt',root);far=group('DistantGate',root);side=group('SideVeranda',root)
# 原中景灯/调查父级保留名字和位移；仅裁掉界外直线延伸的建筑边翼。
for parent_name in ('CorridorArchitecture','PaperDoors','RoofRafters','SacredBraidedRope'):
 parent=bpy.data.objects[parent_name]
 for ob in list(parent.children_recursive):
  if ob.type!='MESH':continue
  limit=6.65 if parent_name!='RoofRafters' else 6.78
  if ob.name.startswith(('Deck_','Scattered_thin')):limit=7.10
  lo,hi=bounds_data(ob.data)
  if lo.x>limit or hi.x<-limit:bpy.data.objects.remove(ob,do_unlink=True);continue
  if lo.x<-limit or hi.x>limit:clip(ob.data,limit)
  if not ob.data.polygons:bpy.data.objects.remove(ob,do_unlink=True)
for parent in list(bpy.data.objects):
 if not parent.name.startswith('WarmWallLantern_'):continue
 meshes=[o for o in parent.children_recursive if o.type=='MESH']
 if meshes and abs(sum(bounds_data(o.data)[0].x+bounds_data(o.data)[1].x for o in meshes)/(2*len(meshes)))>7.1:
  for o in list(parent.children_recursive):bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.objects.remove(parent,do_unlink=True)
# 原庭院基底/岩石仍保持已修接地，另归类供近远层控制。
courtyard=bpy.data.objects['CourtyardFront']
for ob in list(courtyard.children):
 ob.parent=outer
 if ob.name in ('Rear_cedar_canopy','Carved_water_basin_exterior') or ob.name.startswith('Carved_stone_lantern_'):
  bpy.data.objects.remove(ob,do_unlink=True)
bpy.data.objects.remove(courtyard,do_unlink=True)

# 导入首夜授权资产到临时集合，取世界化网格后清走临时对象。
existing=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(APPROACH))
imported=[o for o in bpy.data.objects if o not in existing];approach={}
for o in imported:
 if o.type=='MESH':
  d=o.data.copy();d.transform(o.matrix_world);approach[o.name]=d
for o in imported:bpy.data.objects.remove(o,do_unlink=True)
# 原两套场景共享图片，按真正图片字节去重，不生成/编辑图像。
images={}
for img in list(bpy.data.images):
 if not img.packed_file:
  try:img.pack()
  except RuntimeError:continue
 if not img.packed_file:continue
 key=hashlib.sha256(bytes(img.packed_file.data)).hexdigest()
 if key in images:
  for mat in bpy.data.materials:
   if mat.use_nodes:
    for n in mat.node_tree.nodes:
     if n.type=='TEX_IMAGE' and n.image==img:n.image=images[key]
 else:images[key]=img

def keys(prefix):return [n for n in approach if n.startswith(prefix)]
# 首夜石板直接平移铺外庭，石块真实厚度/UV不拉伸；石地低于既有廊面。
path_names=keys('02_Path_Flat_Flagstones')
for index,x in enumerate((-4.7,4.7)):
 clone_set('Damp_forecourt_flagstones_%d'%index,path_names,approach,outer,(x,-6.5),1.0,-.64)
# 源低多边形山石层移到外庭边缘，地面保持连续。
rock_names=keys('51_Layered_Rocks_Back')+keys('52_Moss_Patches_Back')
clone_set('Outer_rock_bank_left',rock_names,approach,outer,(-9,-7.1),.50,-.72)
clone_set('Outer_rock_bank_right',rock_names,approach,outer,(9,-7.6),.50,-.72)
# 前庭真实石灯在界外，光照仍由profile提供。
for index,x in enumerate((-7.35,7.35)):
 clone_set('ForecourtStoneLantern_%d'%index,keys('20_Lantern_Left_Stone')+keys('21_Lantern_Left_WashiGlow'),approach,outer,(x,-4.9),.78,-.58)
# 中央原地基扩到稍拉远镜头下沿；使用同源土石材质。
ground_data=base['Garden_ground_below_deck']
mesh('Extended_earth_to_camera_edge',ground_data,outer,fit([ground_data],(0,-10,-.76),(38,8.2,.30)))
# 实拍暴露侧廊下z<3.2为无几何的背景蓝；连续低土基横贯侧庭并接到原前庭。
mesh('Continuous_sidecourt_foundation',ground_data,outer,fit([ground_data],(0,1.0,-.76),(38,10.0,.30)))

# 侧廊由原长板/檐/梁柱转向构成。所有实体x至少6.95，完全在旧可玩界外。
for sign in (-1,1):
 wing=group('SideVerandaLeft' if sign<0 else 'SideVerandaRight',side)
 deck=base['Deck_aged_cedar_planks_nails'].copy();clip(deck,1.60)
 mesh('Side_aged_cedar_deck',deck,wing,matrix(offset=(sign*9.80,2.7,0)))
 for key in ('Curved_kawara_roof','Kawara_barrels_and_ends','Exposed_cedar_rafters','Stepped_eave_beams'):
  d=base[key].copy();clip(d,1.75)
  # 转90°令檐向后延伸；平移轴心，不改源纹理比例。
  r=Matrix.Translation(Vector((sign*9.90,3.5,0)))@Matrix.Rotation(math.pi/2,4,'Z')@Matrix.Translation(Vector((0,-2.45,0)))
  mesh('Side_'+key,d,wing,r)
 post_data=base['Cedar_post_05'];shoe_data=base['Stone_shoe_05']
 for j,y in enumerate((.15,2.8,5.2)):
  for x in (sign*8.30,sign*11.25):
   mesh('Side_cedar_post',post_data,wing,fit([post_data],(x,y,1.46),(.20,.20,2.87)))
   mesh('Side_stone_foot',shoe_data,wing,fit([shoe_data],(x,y,.06),(.23,.23,.12)))
 # 内侧低栏清楚标识视觉边廊，并不打开旧边界。
 for z in (.40,.87):
  mesh('Side_cedar_guardrail',post_data,wing,fit([post_data],(sign*8.25,2.68,z),(.12,5.1,.12)))
 # 主回廊界外端柱包住裁切断面。
 mesh('Corridor_end_post',post_data,bpy.data.objects['CorridorArchitecture'],fit([post_data],(sign*6.70,2.65,1.54),(.27,.27,3.02)))

# 远景主山门置右翼空窗，避免穿过中央屋檐。源首夜真实鸟居保留结构。
torii=keys('10_Torii')+keys('11_Torii')+keys('12_Torii')+keys('13_Torii')+keys('14_Torii')+keys('15_Torii')+keys('16_Torii')+keys('17_Torii')+keys('18_Torii')
clone_set('Distant_weathered_sanmon',torii,approach,far,(7.55,4.45),.18,-.60)
shrine=[n for n in approach if n.startswith(('40_Shrine','41_Shrine','42_Shrine','43_Shrine','44_Shrine','45_Shrine','46_Shrine'))]
clone_set('Far_left_shrine_roof_and_hall',shrine,approach,far,(-9.9,7.0),.62,-1.7)
# 遥远地形坡面给山门真实承托，不用背景图。
terrain=keys('01_Terrain')
clone_set('Distant_sculpted_ground',terrain,approach,far,(0,9.2),1.08,-3.15)
# 中央屋脊以上只留低层树冠，侧翼用真实同源杉木制造深度。
for index,(x,y,scale,bottom) in enumerate(((-10.8,7.8,.63,-1.0),(-6.9,9.6,.55,-2.4),(7.6,9.2,.65,-2.0),(12.3,8.2,.70,-1.0))):
 clone_set('Far_cedar_%d'%index,keys('60_Cedar_2_Trunk')+keys('61_Cedar_2_Foliage'),approach,far,(x,y),scale,bottom)
# 前景树干与叶全部界外，中心x±6.8无近景实体。
for sign in (-1,1):
 clone_set('Near_cedar_frame_left' if sign<0 else 'Near_cedar_frame_right',keys('60_Cedar_1_Trunk')+keys('61_Cedar_1_Foliage'),approach,near,(sign*9.35,-4.55),.85,-.72)

# 原石板材质复用，轻降粗糙度表现潮湿；不改fallback文件，也不绘制贴图。
for ob in outer.children_recursive:
 if ob.type=='MESH' and ob.name.startswith('Damp_forecourt'):
  for slot in ob.material_slots:
   if slot.material and 'Mossed stone' in slot.material.name:
    wet=slot.material.copy();wet.name='HD2D damp forecourt stone'
    for n in wet.node_tree.nodes:
     if n.type=='BSDF_PRINCIPLED':n.inputs['Roughness'].default_value=.46
    slot.material=wet

# 空逻辑节点和相机/灯不进入导出，保护完整variant可独立加载。
for o in list(bpy.data.objects):
 if o.type in ('CAMERA','LIGHT'):bpy.data.objects.remove(o,do_unlink=True)
for text in list(bpy.data.texts):bpy.data.texts.remove(text)
for data in list(bpy.data.meshes):
 if data.users==0:bpy.data.meshes.remove(data)
bpy.context.scene.world=None;bpy.context.view_layer.update()
layer_bounds={}
for layer in (mid,near,outer,far,side):
 points=[o.matrix_world@v.co for o in layer.children_recursive if o.type=='MESH' for v in o.data.vertices]
 g=[Vector((v.x,v.z,-v.y)) for v in points]
 layer_bounds[layer.name]={'min':[round(min(v[i] for v in g),4) for i in range(3)],'max':[round(max(v[i] for v in g),4) for i in range(3)]}
HERE.mkdir(parents=True,exist_ok=True);(HERE/'.gdignore').write_text('');bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'night02_hd2d_editable.blend'),check_existing=False)
bpy.ops.export_scene.gltf(filepath=str(OUT/'night02_corridor_hd2d.glb'),export_format='GLB',export_cameras=False,export_lights=False,export_extras=True,export_animations=False,export_yup=True,export_apply=True)
prod=OUT/'night02_corridor_hd2d.glb';mesh_objects=[o for o in bpy.data.objects if o.type=='MESH']
manifest={'iteration':2,'production_sha256':hashlib.sha256(prod.read_bytes()).hexdigest(),'fallback_sha256':FALLBACK_HASH,'base_editable_sha256':hashlib.sha256(BASE.read_bytes()).hexdigest(),'approach_source_sha256':hashlib.sha256(APPROACH.read_bytes()).hexdigest(),'mesh_objects':len(mesh_objects),'triangles':sum(len(p.vertices)-2 for o in mesh_objects for p in o.data.polygons),'camera_design':{'orthographic_size':9.2,'offset':[0,6.2,11],'target_up':1.1},'layer_world_bounds':layer_bounds,'layer_policy':{'MidCorridor':'清晰可玩中景，调查与原灯锚点保留','NearFrame':'仅侧边界外枝叶，可局部轻虚化；中央x±6.8清空','OuterForecourt':'界外石板庭院、岩岸、石灯；原碰撞不扩展','SideVeranda':'界外转折侧廊，不新增可进入路线','DistantGate':'侧翼远山门/杉林/神龛，可弱虚化和冷调'},'no_cameras_lights_collisions':True}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
assert hashlib.sha256(FALLBACK.read_bytes()).hexdigest()==FALLBACK_HASH
print('HD2D_BUILD',json.dumps(manifest,ensure_ascii=False))
