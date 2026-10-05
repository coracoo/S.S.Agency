"""从已授权回廊原稿安全派生第二夜。Blender 4.3.2；不执行原文件文本。
用法：blender --background --disable-autoexec --python build_corridor.py -- 原稿.blend
仅重组真实原稿几何、UV和嵌入纹理；保留旧Godot物理足迹。"""
import bpy
from mathutils import Matrix, Vector
import sys, math, json, hashlib, random
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent
sys.path.insert(0, str(HERE))
from adaptation_helpers import affine, uniform_grounded_transform, planar_uv
SOURCE = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
SOURCE_HASH = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
# 保存所有原稿网格的世界空间副本，脱离原始父级而不修改输入文件。
original = {}
for ob in list(bpy.data.objects):
    if ob.type == 'MESH':
        data = ob.data.copy()
        data.transform(ob.matrix_world)
        original[ob.name] = data
for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
for text in list(bpy.data.texts): bpy.data.texts.remove(text)
for world in bpy.data.worlds: world.use_nodes = False


def choose(prefix): return [name for name in original if name.startswith(prefix)]
def bounds(names):
    pts = [v.co for name in names for v in original[name].vertices]
    return Vector(tuple(min(v[i] for v in pts) for i in range(3))), Vector(tuple(max(v[i] for v in pts) for i in range(3)))
def fit(names, center, size):
    lo, hi = bounds(names); scale = Vector(tuple(size[i]/(hi[i]-lo[i]) for i in range(3)))
    return affine(scale, Vector(center) - (lo+hi)*0.5*scale)
def group(name, pos=(0,0,0)):
    ob = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(ob); ob.location = pos; return ob
def batch(name, names, transform, parent, suffix=''):
    obs=[]
    for key in names:
        data = original[key].copy(); data.transform(transform)
        ob = bpy.data.objects.new(key + suffix, data); bpy.context.collection.objects.link(ob); obs.append(ob)
    return join(name, obs, parent)
def join(name, obs, parent):
    if not obs: return None
    bpy.ops.object.select_all(action='DESELECT')
    for ob in obs: ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join(); ob=bpy.context.object; ob.name=name
    ob.parent=parent; ob.matrix_parent_inverse=parent.matrix_world.inverted()
    # 按原稿面法线保留棱面/圆润边缘，不全局flat覆盖铜铃或屋瓦。
    return ob

def cube(name, center, size, material, parent, bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center); ob=bpy.context.object; ob.name=name
    ob.scale=size; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(material)
    if bevel:
        mod=ob.modifiers.new('手工磨损边缘', 'BEVEL'); mod.width=bevel; mod.segments=2
        bpy.context.view_layer.objects.active=ob; bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.parent=parent; ob.matrix_parent_inverse=parent.matrix_world.inverted(); return ob

wood=bpy.data.materials['Aged cedar • washed warm umber']
paper=bpy.data.materials['Weathered washi • fibre pigment']
bronze=bpy.data.materials['Old bell bronze']
dark=bpy.data.materials['Deep timber joints']
stone=bpy.data.materials['Mossed stone • painted gray green']
# 不创建或修图，只给复用材质设置适合实时PBR的粗糙度与不透明模式。
for mat in bpy.data.materials:
    if not mat.use_nodes: continue
    bsdf=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'), None)
    if bsdf:
        bsdf.inputs['Roughness'].default_value=max(.55, bsdf.inputs['Roughness'].default_value)

# 引擎Omni负责实际照明，灯罩自身不应被1.5倍自发光漂白。
lamp=bpy.data.materials['Lantern warm paper']
lamp_bsdf=next(n for n in lamp.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
lamp_bsdf.inputs['Emission Strength'].default_value=.35
paper_image=next(n.image for n in paper.node_tree.nodes if n.type=='TEX_IMAGE')
lamp_texture=lamp.node_tree.nodes.new('ShaderNodeTexImage');lamp_texture.image=paper_image
lamp.node_tree.links.new(lamp_texture.outputs['Color'],lamp_bsdf.inputs['Base Color'])

root=group('Night02SourceCorridor')
architecture=group('CorridorArchitecture'); architecture.parent=root
floor_names=choose('Deck board')+choose('Dark flush deck nail')[::2]+choose('Quiet worn plank ridge')
# 原cube展开把约4m长板压进0.25宽UV；按实际米制重排，仅改UV不改原木图。
for index,key in enumerate(choose('Deck board')):
    data=original[key]; uv=data.uv_layers.active
    for polygon in data.polygons:
        for loop_index in polygon.loop_indices:
            v=data.vertices[data.loops[loop_index].vertex_index].co
            across=v.y if abs(polygon.normal.z)>.5 else v.z
            uv.data[loop_index].uv=(v.x/2.4+(index%7)*.137, across/7.0+(index%11)*.073)
floor_parts=[]
for offset in (-7,7):
    floor_parts.append(batch('Original_length_cedar_planks',floor_names,affine((1,1,1),(offset,0,-.68)),architecture))
join('Deck_aged_cedar_planks_nails',floor_parts,architecture)
# 稀疏叶片与整面地板分批，最高0.052m低于原金环上缘。
batch('Scattered_thin_dry_leaves', choose('Scattered dry leaf'), affine((2,1,1),(0,0,-.688)), architecture)
base_names=choose('Front worn fascia')+choose('Veranda substructure shadow')+choose('Porch bearer')+choose('Raised porch foot')
batch('Deck_understructure_and_worn_fascia', base_names, affine((2,1,1),(0,0,-.68)), architecture)
# 原暗台基只到z约3.0而地基从3.25起，补接同源暗木结构消除亮蓝透缝。
batch('Deck_underfloor_ground_join',['Veranda substructure shadow'],fit(['Veranda substructure shadow'],(0,-3.19,-.41),(28.6,.7,.58)),architecture)
# 原稿左前楼梯与本关玩法无关，移除界外伸入石景的木条块；不改旧碰撞。
posts=[-13.35,-10.65,-8,-5.35,-2.6,0,2.6,5.35,8,10.65,13.35]
for i,x in enumerate(posts):
    post=group('Post_%02d'%i); post.parent=architecture
    batch('Cedar_post_%02d'%i, ['Cedar principal post -0.8'], fit(['Cedar principal post -0.8'], (x,2.65,1.53),(.26,.26,3.0)), post)
    batch('Stone_shoe_%02d'%i, ['Post stone shoe -0.8'], fit(['Post stone shoe -0.8'],(x,2.65,.08),(.26,.26,.16)), post)
    batch('Carved_upper_joint_%02d'%i,['Upper tie joint -0.8'],fit(['Upper tie joint -0.8'],(x,2.67,3.02),(.45,.34,.27)),post)
# 实体背墙正面不越过旧墙内沿z=-2.795；纸门和门把也留在它后方。
batch('Continuous_dark_sanctuary_backing', ['Interior shadow backdrop'],fit(['Interior shadow backdrop'],(0,3.16,1.65),(29,.18,3.3)),architecture)
batch('Weathered_plaster_underpanels', ['Left facade backing'],fit(['Left facade backing'],(0,3.045,1.52),(28,.12,3.04)),architecture)
batch('Cedar_upper_crossbeam',['Continuous rear transom'],fit(['Continuous rear transom'],(0,2.85,3.15),(28.5,.3,.23)),architecture)
batch('Cedar_door_sill',['Continuous wall foot rail'],fit(['Continuous wall foot rail'],(0,2.965,.07),(28,.14,.12)),architecture)

panels=group('PaperDoors');panels.parent=root
# 原稿手工格栅、纸纤维、踢脚板、门把保持独立构件及原UV后按湾合批。
for i in range(len(posts)-1):
    left,right=posts[i]+.15,posts[i+1]-.15
    available=right-left; center=(left+right)/2
    obs=[]
    for side in [-1,1]:
        src=choose('Shoji_A ' if (i+side)%3 else 'Shoji_D ')
        panel=batch('Door_leaf_%02d_%d'%(i,side),src,fit(src,(center+side*available/4,2.956,1.47),(available/2-.014,.105,2.83)),panels)
        obs.append(panel)
    join('Shoji_pair_%02d'%i,obs,panels)

roof=group('RoofRafters');roof.parent=root
roof_names=[n for n in original if n.startswith(('Canopy exposed rafter','Continuous canopy beam','Curved clay tile roof','Soffit plank','Tile barrel ridge','Horizontal tile seam','Round kawara tile end','Eave stepped bracket'))]
# 前檐移到后半廊，避免固定俯视镜头遮脸；保留原稿曲瓦和椽端。
roof_transform=affine((1.95,.54,.74),(0,2.07,-.08))
for name,prefixes in [('Curved_kawara_roof',('Curved clay tile roof',)),('Kawara_barrels_and_ends',('Tile barrel ridge','Horizontal tile seam','Round kawara tile end')),('Exposed_cedar_rafters',('Canopy exposed rafter','Soffit plank')),('Stepped_eave_beams',('Continuous canopy beam','Eave stepped bracket'))]:
    batch(name,[n for n in roof_names if n.startswith(prefixes)],roof_transform,roof)

rope=group('SacredBraidedRope');rope.parent=root
rope_names=choose('Braided rice-straw')+choose('Dry straw catchlight')+choose('Rice straw hanging fringe')+choose('Shide ')
# 纸垂最低2.50m，保留三股螺旋与挂穗细节。
batch('Straw_twist_and_folded_shide',rope_names,fit(rope_names,(.1,1.96,3.03),(12.6,.3,1.03)),rope)

bell=group('HangingBell',(-2.5,1.73,0));bell.parent=root
bell_names=[n for n in original if n.startswith(('Bell ','Cast bronze bell')) and not n.startswith(('Bell pull cord','Bell pull tassel'))]
batch('Cast_bronze_bell_with_bosses',bell_names,fit(bell_names,(-2.5,1.73,2.55),(.68,.68,1.12)),bell)
# 原长拉绳会在可达区穿人，收成高位短绳结；仍使用原稿实体编绳。
cord=group('BellRedThread');cord.parent=bell;cord.matrix_parent_inverse=bell.matrix_world.inverted()
cord_names=choose('Bell pull cord')+choose('Bell pull tassel')
batch('Short_bell_cord_and_tassel',cord_names,fit(cord_names,(-2.5,1.73,1.97),(.15,.15,.16)),cord)

# 文书和旧物仅补足已批准调查语义，不用平面图替代建筑。
fragment=group('SendoffFragment',(-.6,1.75,0));fragment.parent=root
page=cube('Washi_remnant_page',(-.6,1.75,.05),(.5,.61,.016),paper,fragment,.005)
page.rotation_euler[2]=-.13
inkgroup=group('FragmentInk');inkgroup.parent=fragment;inkgroup.matrix_parent_inverse=fragment.matrix_world.inverted()
inkpieces=[]
for col in range(3):
    for row in range(5):
        ob=cube('Faded_ink_stroke',(-.75+col*.12,1.53+row*.087,.061),(.032+(row%2)*.018,.018,.003),dark,inkgroup,0)
        inkpieces.append(ob)
join('Faded_vertical_inscription',inkpieces,inkgroup)

# 已有1.0×0.55木箱足迹，不外伸桌腿/台面。复用旧木和雕边，不加碰撞。
offer=group('OfferingTable',(1,1.92,0));offer.parent=root
chestparts=[]
for i in range(5):chestparts.append(cube('Cedar_chest_plank',(1.2+i*.2,2.05,.28),(.198,.548,.50),wood,offer,.009))
chestparts.append(cube('Cedar_chest_lid',(1.6,2.05,.548),(.994,.548,.03),wood,offer,.012))
for x in (1.16,2.04):chestparts.append(cube('Bronze_chest_binding',(x,1.778,.30),(.046,.006,.43),bronze,offer,.002))
join('Heirloom_chest_cedar_and_bindings',chestparts,offer)
cube('Folded_washi_keepsake',(1.39,2.06,.60),(.27,.23,.074),paper,offer,.014)
# 原水钵竹杯借作供杯，真实有壁厚的空心器皿。
batch('Offering_cup', ['Ladle bamboo cup'],fit(['Ladle bamboo cup'],(1.87,2.04,.626),(.14,.14,.15)),offer)

# 原坛前灯改成高悬引路灯，最低实体2.0m，不放无碰撞落地杆。
guide=group('GuideLantern',(2.5,1.75,0));guide.parent=root
lantern_src=choose('Altar lantern left')
batch('Guide_paper_lantern',lantern_src,fit(lantern_src,(2.5,1.75,2.29),(.38,.36,.58)),guide)
batch('Guide_lantern_suspension',['Bell suspension chain'],fit(['Bell suspension chain'],(2.5,1.75,2.98),(.025,.025,.8)),guide)
for i,x in enumerate((-9.3,-6.6,-3.9,-1.3,4.0,6.7,9.4,12.0)):
    hanging=group('WarmWallLantern_%02d'%i);hanging.parent=root
    batch('Aged_altar_lantern_%02d'%i,lantern_src,fit(lantern_src,(x,2.45,2.55),(.3,.28,.43)),hanging)

# 把原稿石灯、水钵与真实不规则岩石放到边界之外，保留庭院层次。
garden=group('CourtyardFront');garden.parent=root
rock_names=choose('Low garden moss stone')
# 地基使用原石材图的米制UV；与原灰色纯色土台相比可读出土石面。
earth=['Garden dark earth']
ground=batch('Garden_ground_below_deck',earth,fit(earth,(0,-7,-.74),(36,7.5,.28)),garden)
# 同一石图乘温和土色系数，区分青石与土基；不重绘任何图像。
ground_mat=stone.copy();ground_mat.name='Mossed stone ground • muted earth tint'
bsdf=next(n for n in ground_mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
texture=next(n for n in ground_mat.node_tree.nodes if n.type=='TEX_IMAGE')
mix=ground_mat.node_tree.nodes.new('ShaderNodeMix');mix.data_type='RGBA';mix.blend_type='MULTIPLY'
mix.inputs[0].default_value=1.0;mix.inputs[7].default_value=(.9,.82,.72,1)
ground_mat.node_tree.links.new(texture.outputs['Color'],mix.inputs[6])
ground_mat.node_tree.links.new(mix.outputs[2],bsdf.inputs['Base Color'])
ground.data.materials.clear();ground.data.materials.append(ground_mat)
planar_uv(ground.data)
# 复用原土台54面形成廊脚一层浅坡，与原平地交叠而无悬空横缝。
bank=batch('Earth_bank_against_foundation',earth,fit(earth,(0,-3.8,-.58),(28.7,1.2,.30)),garden)
for vertex in bank.data.vertices:vertex.co.z+=(vertex.co.y+3.2)*.2833333
bank.data.materials.clear();bank.data.materials.append(ground_mat)
planar_uv(bank.data)
# 只伸展布局中心，不非均匀压扁石体；把各石最低点埋入地基2cm。
rock_parts=[]
for layer in range(2):
    for index,key in enumerate(rock_names):
        lo,hi=bounds([key]); center=(lo+hi)*.5
        scale=min(1.30+(index%5)*.12,.66/(hi.z-lo.z))
        dest=Vector((center.x*1.65-2.0+layer*2.2,-3.9-(center.y-3.0)*.37-layer*2.8,0))
        max_y_half=(hi.y-lo.y)*scale*.5
        dest.y=min(dest.y,-3.40-max_y_half)
        rock_transform=uniform_grounded_transform(original[key],(dest.x,dest.y),scale,-.62)
        rock_parts.append(batch('Grounded_moss_stone', [key], rock_transform,garden))
join('Grounded_layered_foreground_stones',rock_parts,garden)
for side in (-1,1):
    toronames=choose('Toro ')
    batch('Carved_stone_lantern_left' if side<0 else 'Carved_stone_lantern_right',toronames,fit(toronames,(side*7.65,-.2,1.05),(1.07,1.07,2.25)),garden)
basin_names=choose('Carved stone basin')+choose('Basin ')+choose('Ladle ')+choose('Water gentle ripple')
batch('Carved_water_basin_exterior',basin_names,fit(basin_names,(8.25,-1.4,.25),(1.45,1.45,.94)),garden)
# 原树/枝/叶放背墙后方并略收低；保留同源低多边形自然轮廓。
trees=choose('Garden cedar')+choose('Garden distant layered foliage')
batch('Rear_cedar_canopy',trees,affine((1.25,.7,.8),(-2,2.8,-.7)),garden)

# 生产资源只保留mesh与逻辑父组；内部灯光/相机不导出。
bpy.context.scene.world=None
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.update()
# 清除未使用原网格副本，保留派生数据及五张已内嵌纹理。
for mesh in list(bpy.data.meshes):
    if mesh.users==0:bpy.data.meshes.remove(mesh)
for image in bpy.data.images:
    if image.type=='IMAGE' and not image.packed_file:image.pack()
HERE.mkdir(parents=True,exist_ok=True);(HERE/'.gdignore').write_text('')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'night02_corridor_editable.blend'),check_existing=False)
bpy.ops.export_scene.gltf(filepath=str(OUT/'night02_corridor.glb'),export_format='GLB',use_selection=False,export_cameras=False,export_lights=False,export_extras=True,export_yup=True,export_apply=True,export_image_format='AUTO',export_animations=False)
production=OUT/'night02_corridor.glb'
meshes=[o for o in bpy.data.objects if o.type=='MESH']
triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
manifest={'version':1,'iteration':3,'original_blend_filename':SOURCE.name,'original_blend_sha256':SOURCE_HASH,'production_sha256':hashlib.sha256(production.read_bytes()).hexdigest(),'original_textures_reused':5,'blender_version':bpy.app.version_string,'mesh_objects':len(meshes),'triangles':triangles,'coordinate_system':'glTF Y up; Godot直接载入，无wrapper缩放','source_reuse':'原始回廊旧木/和纸/青瓦/石材/灰泥纹理，以及门格栅、编绳、铜铃、椽瓦、岩石、树木、石灯、水钵网格。仅文书与旧物箱为源材质补建。','collision_policy':'不导出碰撞，不修改旧碰撞。五柱/后墙/木箱对位，灯钟高挂，石灯水钵界外。','runtime_lighting':'由Godot集成层接入；资产不含相机灯光。'}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('CORRIDOR_ASSET_BUILD',json.dumps(manifest,ensure_ascii=False))
