"""第三夜露天纸列：安全复用原回廊纹理与首夜同源几何，不写入来源文件。"""
import bpy
from mathutils import Matrix, Vector
from pathlib import Path
import sys, json, hashlib, math, random, struct

HERE = Path(__file__).resolve().parent
OUT = HERE.parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'assets/3d/night02_corridor/source'))
from adaptation_helpers import affine, uniform_grounded_transform, planar_uv, mesh_bounds
SOURCE = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
APPROACH = ROOT / 'assets/3d/act01_approach/act01_approach.glb'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
original = {}
for ob in list(bpy.data.objects):
    if ob.type == 'MESH':
        mesh = ob.data.copy(); mesh.transform(ob.matrix_world); original[ob.name] = mesh
for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
for text in list(bpy.data.texts): bpy.data.texts.remove(text)
original_mats = {m.name: m for m in bpy.data.materials}
original_images = {i.name: i for i in bpy.data.images if i.type == 'IMAGE'}
bpy.ops.import_scene.gltf(filepath=str(APPROACH))
# 首夜glTF与回廊原稿同图：统一回原图数据块，保留首夜颜色因子。
for mat in bpy.data.materials:
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image:
                stem = node.image.name.split('.png')[0] + '.png'
                if stem in original_images: node.image = original_images[stem]
approach = {}
for ob in list(bpy.data.objects):
    if ob.type != 'MESH': continue
    mesh = ob.data.copy(); mesh.transform(ob.matrix_world)
    for i, mat in enumerate(mesh.materials):
        base = mat.name.rsplit('.', 1)[0] if mat.name.rsplit('.', 1)[-1].isdigit() else mat.name
        if base in original_mats: mesh.materials[i] = original_mats[base]
    approach[ob.name] = mesh
for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)


def choose(source, prefix): return [n for n in source if n.startswith(prefix)]
def bounds(source, names):
    pts = [v.co for n in names for v in source[n].vertices]
    return Vector(tuple(min(v[i] for v in pts) for i in range(3))), Vector(tuple(max(v[i] for v in pts) for i in range(3)))
def fit(source, names, center, size):
    lo, hi = bounds(source, names); scale = Vector(tuple(size[i] / (hi[i] - lo[i]) for i in range(3)))
    return affine(scale, Vector(center) - (lo + hi) * .5 * scale)
def group(name, parent=None, location=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(ob); ob.location = location
    if parent: ob.parent = parent; ob.matrix_parent_inverse = parent.matrix_world.inverted()
    return ob
def join(name, objects, parent):
    if not objects: return None
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join(); ob = bpy.context.object; ob.name = name
    ob.parent = parent; ob.matrix_parent_inverse = parent.matrix_world.inverted()
    return ob
def batch(name, source, names, transform, parent):
    objects = []
    for key in names:
        mesh = source[key].copy(); mesh.transform(transform)
        ob = bpy.data.objects.new(key, mesh); bpy.context.collection.objects.link(ob); objects.append(ob)
    return join(name, objects, parent)
def cube(name, center, size, material, parent, bevel=.01, uv_axes=None, repeat=(1, 1)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center); ob = bpy.context.object; ob.name = name
    ob.scale = size; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(material)
    if bevel:
        mod = ob.modifiers.new('实体磨损倒角', 'BEVEL'); mod.width = bevel; mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if uv_axes is not None: planar_uv(ob.data, repeat, uv_axes)
    ob.parent = parent; ob.matrix_parent_inverse = parent.matrix_world.inverted()
    return ob
def mesh_object(name, vertices, faces, material, parent, axes=(0, 2), repeat=(1, 1), thickness=0):
    mesh = bpy.data.meshes.new(name); mesh.from_pydata(vertices, [], faces); mesh.update()
    mesh.materials.append(material); planar_uv(mesh, repeat, axes)
    ob = bpy.data.objects.new(name, mesh); bpy.context.collection.objects.link(ob)
    ob.parent = parent; ob.matrix_parent_inverse = parent.matrix_world.inverted()
    if thickness:
        bpy.context.view_layer.objects.active = ob; ob.select_set(True)
        mod = ob.modifiers.new('真实和纸边厚', 'SOLIDIFY'); mod.thickness = thickness
        bpy.ops.object.modifier_apply(modifier=mod.name); ob.select_set(False)
    return ob

def face_projected_uv(mesh, repeat=3.2):
    # 依每面主法线选择投影轴，侧面不再把同一纹理像素拉成长条。
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        dominant=max(range(3),key=lambda i:abs(polygon.normal[i]))
        axes=[i for i in range(3) if i!=dominant]
        for loop_index in polygon.loop_indices:
            v=mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv=(v[axes[0]]/repeat,v[axes[1]]/repeat)


def grounded_group(source, names, center_xy, scale, bottom):
    lo, hi = bounds(source, names); center = (lo + hi) * .5
    return affine((scale,) * 3, (center_xy[0] - center.x * scale, center_xy[1] - center.y * scale, bottom - lo.z * scale))

wood = original_mats['Aged cedar • washed warm umber']
paper = original_mats['Weathered washi • fibre pigment']
stone = original_mats['Mossed stone • painted gray green']
dark = original_mats['Deep timber joints']
bronze = original_mats['Old bell bronze']
edge = original_mats['Worn wood edge • muted ochre']
earth_material = approach['01_Terrain_Watertight_Sculpted_Earth'].materials[0]
for mat in bpy.data.materials:
    if mat.use_nodes:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf: bsdf.inputs['Roughness'].default_value = max(.72, bsdf.inputs['Roughness'].default_value)
# 灯罩只提供低强度可辨发光，真正局部照明由Godot统一集成。
lamp = original_mats['Lantern warm paper']
lamp_bsdf = next(n for n in lamp.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
lamp_bsdf.inputs['Emission Strength'].default_value = .3
lamp_texture = lamp.node_tree.nodes.new('ShaderNodeTexImage'); lamp_texture.image = original_images['paper.png']
lamp.node_tree.links.new(lamp_texture.outputs['Color'], lamp_bsdf.inputs['Base Color'])
seam = paper.copy(); seam.name = 'Washi coffin seam • restrained cold light'
bsdf = next(n for n in seam.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Emission Color'].default_value = (.28, .39, .62, 1); bsdf.inputs['Emission Strength'].default_value = .5
root = group('Night03SourceProcession')
path = group('StoneProcessionPath', root)
# 青石板完全复用首夜原轮廓及UV，复制整段布局而不拉扁岩石。
floorparts = []
for layer in range(2):
    for row in range(1, 5):
        key = '02_Path_Flat_Flagstones_%d' % row
        for tile in range(3):
            floorparts.append(batch('Source_flagstone_row', approach, [key], affine(offset=(-5 + tile * 9.5, -0.7 + layer * 2.81, -.023)), path))
join('Worn_source_flagstones_all_walkable_bounds', floorparts, path)
base = batch('Indigo_stone_earth_below_path', original, ['Garden dark earth'], fit(original, ['Garden dark earth'], (0, -.1, -.27), (34, 7, .45)), path)
base.data.materials.clear(); base.data.materials.append(earth_material); face_projected_uv(base.data)
# 草叶以贴地组独立合批，不与高灌木共享跨通路AABB。
leaves = []
for x in (-8, 2, 12):
    names = choose(original, 'Scattered dry leaf')
    leaves.append(batch('Path_dry_leaves', original, names, affine(offset=(x, 0, -.69)), path))
join('Thin_dry_leaves_on_slate', leaves, path)

wall = group('ShrineEnclosure', root)
# 后墙外真实抬高地形托住七具纸躯；不在旧可达边界内造新障碍。
terrace=batch('Raised_rear_earth_supports_procession',original,['Garden dark earth'],fit(original,['Garden dark earth'],(0,4.85,.28),(33,3.8,.60)),wall)
terrace.data.materials.clear(); terrace.data.materials.append(earth_material); face_projected_uv(terrace.data)
# 低围垣：把原青石板转为竖向砌石，不生成规整纯色立方体阵列。
wallpieces = []
key = '02_Path_Flat_Flagstones_1'; lo, hi = mesh_bounds(approach[key]); center = (lo + hi) * .5
for tile in range(4):
    transform = Matrix.Translation(Vector((-14.2 + tile * 9.5, 3.03, .24))) @ Matrix.Rotation(math.pi / 2, 4, 'X') @ Matrix.Translation(-center)
    wallpieces.append(batch('Worn_boundary_stone', approach, [key], transform, wall))
join('Low_rough_stone_boundary', wallpieces, wall)
cube('Boundary_wood_footrail', (0, 3.12, .56), (33, .18, .12), wood, wall, .018, (0, 2), (2.4, .7))
# 五根范围内旧柱逐一对应原碰撞，横向延伸柱只作镜头连续背景。
for index, x in enumerate((-13.35, -10.65, -8, -5.35, -2.6, 0, 2.6, 5.35, 8, 10.65, 13.35)):
    column = group('BoundaryPost_%02d' % index, wall)
    batch('Aged_cedar_post_%02d' % index, original, ['Cedar principal post -0.8'], fit(original, ['Cedar principal post -0.8'], (x, 2.65, 1.5), (.26, .26, 3)), column)
    batch('Stone_post_shoe_%02d' % index, original, ['Post stone shoe -0.8'], fit(original, ['Post stone shoe -0.8'], (x, 2.65, .07), (.26, .26, .14)), column)
    cap = cube('Post_dark_cap_%02d' % index, (x, 2.65, 3.035), (.38, .37, .12), dark, column)
# 后置透空栅栏不再横穿纸躯正面。全部在旧后墙外。
rails = [cube('Rear_fence_rail', (0, 3.91, height), (33, .14, .13), wood, wall, .014, (0, 2), (2.4, .6)) for height in (.89, 2.05)]
for i in range(67): rails.append(cube('Rear_fence_picket', (-16.5 + i * .5, 3.91, 1.46), (.06, .075, 1.13), wood, wall, .008))
join('Open_fence_behind_paper_figures', rails, wall)

# 木鸟居复用首夜完整形体，按统一比例缩小，仅放远后景。
torii = group('DistantTorii', root)
torii_names = [n for n in approach if n.startswith(('10_Torii', '11_Torii', '12_Torii', '13_Torii', '14_Torii', '15_Torii', '16_Torii', '17_Torii', '18_Torii'))]
batch('Distant_source_wood_torii', approach, torii_names, grounded_group(approach, torii_names, (3.8, 5.5), .9, .02), torii)

# 棺材可见足迹严格落在1.85×.8旧实体内；纸带与盖缝不横伸入可达区。
coffin = group('PaperCoffin', root)
bodyparts = []
bodyparts.append(cube('Washi_coffin_body', (.6, 1.55, .32), (1.845, .795, .545), paper, coffin, .065, (0, 2), (.8, .8)))
bodyparts.append(cube('Dark_hollow_under_lid', (.6, 1.55, .616), (1.71, .66, .03), dark, coffin, .032))
bodyparts.append(cube('Folded_washi_lid', (.6, 1.55, .665), (1.84, .79, .07), paper, coffin, .034, (0, 1), (.8, .8)))
for x in (-.15, .6, 1.35):
    bodyparts.append(cube('Lid_folded_paper_band', (x, 1.55, .706), (.066, .776, .01), paper, coffin, .002, (0, 1), (.4, .4)))
    bodyparts.append(cube('Front_folded_paper_band', (x, 1.153, .32), (.067, .011, .50), paper, coffin, .002, (0, 2), (.4, .4)))
join('Paper_coffin_body_lid_and_bands', bodyparts, coffin)
cube('CoffinLightSeam', (.6, 1.151, .617), (1.69, .012, .018), seam, coffin, .003, (0, 2), (.8, .8))
poles = group('CarryingPoles', root)
parts = []
for y in (1.23, 1.87):
    parts.append(cube('Short_cedar_carrying_pole', (.6, y, .46), (1.72, .065, .065), wood, poles, .015, (0, 2), (1.8, .5)))
    for x in (-.06, 1.26): parts.append(cube('Pole_washi_grip', (x, y, .46), (.18, .076, .076), paper, poles, .018))
join('Contained_carrying_poles_and_washi_grips', parts, poles)
keepsake = group('ProcessionKeepsakeBox', root)
parts = []
for i in range(5): parts.append(cube('Old_box_cedar_plank', (1.2 + i * .2, 2.05, .28), (.197, .548, .498), wood, keepsake, .006, (0, 2), (.7, .8)))
parts.append(cube('Old_box_paper_lid', (1.6, 2.05, .546), (.994, .548, .03), paper, keepsake, .006, (0, 1)))
for x in (1.18, 2.02): parts.append(cube('Old_box_paper_band', (x, 1.774, .30), (.05, .006, .44), paper, keepsake, .002))
join('Kept_legacy_wood_box_footprint', parts, keepsake)

# 七个扎纸侍从：三折衣片、薄边袖、折角空心头；不是加厚盒子人。
queue = group('PaperProcession', root)
def paper_person(index, x, y, height, tilt):
    actor = group('PaperAttendant_%02d' % index, queue)
    bottom = .60; h = height; parts = []
    # 中脊朝观众，前后片有真实深度与薄边，垂边错开形成衣褶。
    verts = [(-.24, .06, .06), (0, -.10, 0), (.24, .065, .035), (-.13, .03, h*.66), (0, -.09, h*.71), (.13, .04, h*.66), (-.20, .16, .06), (.20, .16, .035), (-.11, .14, h*.65), (.11, .14, h*.65)]
    faces = [(0, 1, 4, 3), (1, 2, 5, 4), (6, 8, 9, 7), (0, 3, 8, 6), (2, 7, 9, 5)]
    parts.append(mesh_object('Folded_fibrous_robe', verts, faces, paper, actor, thickness=.008, repeat=(.6,.6)))
    for sign in (-1, 1):
        sleeve = [(sign*.10, .005, h*.63), (sign*.39, .015, h*.47), (sign*.34, -.065, h*.35), (sign*.18, -.09, h*.49), (sign*.12, .08, h*.59), (sign*.38, .07, h*.45)]
        parts.append(mesh_object('Thin_folded_sleeve', sleeve, [(0,1,2,3), (0,4,5,1)], paper, actor, thickness=.009, repeat=(.5,.5)))
        parts.append(cube('Paper_folded_foot', (sign*.10, -.006, .05), (.12, .20, .055), paper, actor, .009))
    # 不对称五折面头部，保留窄侧面和清楚前折线。
    z = h*.81; w=.25; depth=.15
    verts=[(-w/2,-depth/2,z-.12),(0,-depth*.62,z-.11),(w/2,-depth/2,z-.115),(-w/2,depth/2,z-.12),(w/2,depth/2,z-.12),(-w/2,-depth/2,z+.13),(0,-depth*.58,z+.145),(w/2,-depth/2,z+.135),(-w/2,depth/2,z+.12),(w/2,depth/2,z+.12)]
    faces=[(0,1,6,5),(1,2,7,6),(0,5,8,3),(2,4,9,7),(3,8,9,4),(5,6,7,9,8)]
    parts.append(mesh_object('Creased_hollow_washi_head', verts, faces, paper, actor, thickness=.009, repeat=(.44,.44)))
    for ex in (-.053,.052): parts.append(cube('Subtle_ink_eye', (ex,-.098,z+.018),(.036,.007,.009),dark,actor,.002))
    parts.append(cube('Quiet_ink_mouth',(0,-.098,z-.062),(.026,.008,.007),dark,actor,.001))
    # 细旧木色折领，用源材质避免新纯色大面积。
    collar=mesh_object('Folded_collar',[(-.12,-.055,h*.67),(0,-.103,h*.61),(.12,-.055,h*.67),(0,-.095,h*.64)],[(0,1,3),(1,2,3)],edge,actor,thickness=.009)
    parts.append(collar)
    ob = join('Washi_attendant_folded_body_%02d' % index, parts, actor)
    transform=Matrix.Translation((x,y,bottom)) @ Matrix.Rotation(tilt,4,'Z')
    # join保留active原点；烘到世界后再变换，保证胶囊检测和导出一致。
    ob.data.transform(ob.matrix_world); ob.matrix_world=Matrix.Identity(4); ob.data.transform(transform)
    actor['visual_bottom'] = bottom; actor['height'] = h; actor['outside_legacy_rear_wall'] = True
for spec in [(0,-4.8,3.35,1.32,.12),(1,-3.0,3.23,1.42,-.12),(2,-1.23,3.17,1.24,.12),(3,-.50,3.53,1.48,-.1),(4,1.43,3.5,1.48,.09),(5,2.18,3.19,1.27,-.1),(6,4.85,3.31,1.42,.13)]: paper_person(*spec)

lanterns = group('StoneLanterns', root)
for index,x in enumerate((-8.4,-4.1,3.9,8.3)):
    names=choose(original,'Toro ')
    batch('Source_stone_lantern_%02d'%index,original,names,grounded_group(original,names,(x,3.34),.63,.53),lanterns)
    group('StoneLanternLightAnchor_%02d'%index,lanterns,(x,3.34,1.56))

landscape = group('DistantGrove',root)
# 背景树与鸟居均只平移+等比，取源细枝和片簇树冠。
for i,(x,y,scale) in enumerate([(-12,6.4,.85),(-7,6.0,.83),(-2.5,6.5,.8),(6,6.1,.87),(11,6.5,.88)]):
    source_i=i+1; names=['60_Cedar_%d_Trunk'%source_i,'61_Cedar_%d_Foliage'%source_i]
    batch('Layered_source_cedar_%02d'%i,approach,names,grounded_group(approach,names,(x,y),scale,-.15),landscape)
# 前景独立土基保证无悬浮；石体不非均匀压扁。
front = group('ForegroundRockBank',root)
earth=batch('Foreground_damp_stone_earth',original,['Garden dark earth'],fit(original,['Garden dark earth'],(0,-6.0,-.65),(35,7,.4)),front)
earth.data.materials.clear(); earth.data.materials.append(earth_material); face_projected_uv(earth.data)
bank=batch('Sloped_soil_join_below_flagstones',original,['Garden dark earth'],fit(original,['Garden dark earth'],(0,-3.54,-.41),(33,1.4,.26)),front)
for vertex in bank.data.vertices: vertex.co.z+=(vertex.co.y+3.54)*.35
bank.data.update();bank.data.materials.clear();bank.data.materials.append(earth_material);face_projected_uv(bank.data)
rocks=[]
rock_names=choose(original,'Low garden moss stone')
for i in range(56):
    key=rock_names[i%len(rock_names)]; scale=.75+(i%5)*.12
    x=-15+(i%28)*1.1; y=-3.5-(i//28)*1.9-(i%3)*.14
    lo,hi=mesh_bounds(original[key]); y=min(y,-3.08-(hi.y-lo.y)*scale*.5)
    rocks.append(batch('Natural_layered_source_rock',original,[key],uniform_grounded_transform(original[key],(x,y),scale,-.54),front))
join('Grounded_irregular_foreground_stone_clusters',rocks,front)
# 原首夜草丛逐连通网格拆分后，仅将小簇放界外；沿用原片叶UV。
grasses=[]
for i,key in enumerate(choose(approach,'70_Ferns_And_Grasses')):
    # 整组原布局仅作为较远环境层，最低点贴地，全部退在前可走界外。
    grasses.append(batch('Source_fern_band',approach,[key],grounded_group(approach,[key],(-4+i*4,-6.7-i*.7),.65,-.47),front))
join('Far_bank_source_ferns_and_grasses',grasses,front)

# 原纸图的树影斑原为门纸构图服务，小道具不能缩成密集迷彩。
# 只改原图UV，取上中部清净纤维区域；PNG逐字节保留。
for ob in bpy.data.objects:
    if ob.type!='MESH': continue
    mesh=ob.data; uv=mesh.uv_layers.active
    if uv is None: continue
    lo,hi=mesh_bounds(mesh)
    for polygon in mesh.polygons:
        mat=mesh.materials[polygon.material_index]
        if not mat.name.startswith(('Weathered washi','Washi coffin seam')): continue
        dominant=max(range(3),key=lambda i:abs(polygon.normal[i]))
        axes=[i for i in range(3) if i!=dominant]
        for loop_index in polygon.loop_indices:
            vertex=mesh.vertices[mesh.loops[loop_index].vertex_index].co
            values=[min(1,max(0,(vertex[a]-lo[a])/max(.001,hi[a]-lo[a]))) for a in axes]
            uv.data[loop_index].uv=(.405+values[0]*.22,.89+values[1]*.08)

bpy.context.scene.world=None
for mesh in list(bpy.data.meshes):
    if mesh.users==0: bpy.data.meshes.remove(mesh)
for image in bpy.data.images:
    if image.type=='IMAGE' and not image.packed_file: image.pack()
HERE.mkdir(parents=True,exist_ok=True); (HERE/'.gdignore').write_text('')
bpy.context.preferences.filepaths.save_version=0
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'night03_procession_editable.blend'),check_existing=False)
bpy.ops.export_scene.gltf(filepath=str(OUT/'night03_procession.glb'),export_format='GLB',export_cameras=False,export_lights=False,export_extras=True,export_yup=True,export_apply=True,export_image_format='AUTO',export_animations=False)
production=OUT/'night03_procession.glb'; raw=production.read_bytes(); json_size=struct.unpack_from('<I',raw,12)[0]; doc=json.loads(raw[20:20+json_size])
# 写manifest之前立即校验递归纹理索引，不能让外观损坏被计数掩盖。
def check_refs(value):
    if isinstance(value,dict):
        for key,child in value.items():
            if key.endswith('Texture') and isinstance(child,dict) and 'index' in child:
                texture=doc['textures'][child['index']]; image=doc['images'][texture['source']]; assert 'bufferView' in image and 'uri' not in image; assert image['bufferView']<len(doc['bufferViews'])
            check_refs(child)
    elif isinstance(value,list):
        for child in value: check_refs(child)
check_refs(doc['materials'])
meshes=[o for o in bpy.data.objects if o.type=='MESH']
manifest={'version':1,'iteration':2,'original_blend_filename':SOURCE.name,'original_blend_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'approach_glb_sha256':hashlib.sha256(APPROACH.read_bytes()).hexdigest(),'production_sha256':hashlib.sha256(raw).hexdigest(),'blender_version':bpy.app.version_string,'mesh_objects':len(meshes),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),'embedded_images':len(doc.get('images',[])),'paper_attendants':7,'visual_wall_height':.6,'coordinate_system':'Godot(x,y,z)=(Blender x,z,-y)，wrapper不缩放','runtime_lighting':'GLB没有相机或灯，灯光由集成层所有','source_reuse':'原回廊旧木/和纸/石材、石灯、自然岩石；首夜石板、片簇杉树、真实木鸟居、草叶。纸列与棺使用原图正确UV补建。','collision_policy':'无新增碰撞；五柱/棺/木箱保持旧足迹，七纸人和石灯均在旧后墙外。'}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('PROCESSION_ASSET_BUILD',json.dumps(manifest,ensure_ascii=False))
