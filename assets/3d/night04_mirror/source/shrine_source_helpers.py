"""内殿同源网格工具。只在构建脚本显式调用时打开原稿，禁止执行原Text。"""
import bpy
from mathutils import Matrix, Vector
import math, hashlib, json, random, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'night02_corridor/source'))
from adaptation_helpers import affine, uniform_grounded_transform, planar_uv

class SourceScene:
    def __init__(self, source):
        self.source = Path(source).resolve()
        self.source_hash = hashlib.sha256(self.source.read_bytes()).hexdigest()
        bpy.ops.wm.open_mainfile(filepath=str(self.source), use_scripts=False)
        self.original = {}
        for ob in list(bpy.data.objects):
            if ob.type == 'MESH':
                data = ob.data.copy(); data.transform(ob.matrix_world); self.original[ob.name] = data
        for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
        for text in list(bpy.data.texts): bpy.data.texts.remove(text)
        self.wood = bpy.data.materials['Aged cedar • washed warm umber']
        self.paper = bpy.data.materials['Weathered washi • fibre pigment']
        self.stone = bpy.data.materials['Mossed stone • painted gray green']
        self.plaster = bpy.data.materials['Muted lime plaster']
        self.dark = bpy.data.materials['Deep timber joints']
        self.bronze = bpy.data.materials['Old bell bronze']
        self.edge = bpy.data.materials['Worn wood edge • muted ochre']
        self.lamp = bpy.data.materials['Lantern warm paper']
        self.bsdf(self.lamp).inputs['Emission Strength'].default_value = .3
        image = next(n.image for n in self.paper.node_tree.nodes if n.type == 'TEX_IMAGE')
        texture = self.lamp.node_tree.nodes.new('ShaderNodeTexImage'); texture.image = image
        self.lamp.node_tree.links.new(texture.outputs['Color'], self.bsdf(self.lamp).inputs['Base Color'])
        self.bark = self.wood.copy(); self.bark.name = 'Aged cedar bark • same original grain'
        self.bsdf(self.bark).inputs['Roughness'].default_value = .98
        self.mirror = self.bronze.copy(); self.mirror.name = 'Patinated bronze mirror • no real-time reflection'
        b = self.bsdf(self.mirror); b.inputs['Base Color'].default_value=(.18,.37,.32,1); b.inputs['Metallic'].default_value=.48; b.inputs['Roughness'].default_value=.58; b.inputs['Specular IOR Level'].default_value=.15
        b.inputs['Emission Color'].default_value=(.025,.1,.08,1); b.inputs['Emission Strength'].default_value=.18
        self.glow = self.bronze.copy(); self.glow.name = 'Coffin mark • quiet blue patina'
        b=self.bsdf(self.glow);b.inputs['Base Color'].default_value=(.26,.52,.65,1);b.inputs['Metallic'].default_value=.22;b.inputs['Roughness'].default_value=.62
        b.inputs['Emission Color'].default_value=(.18,.47,.62,1);b.inputs['Emission Strength'].default_value=.55

    def load_approach_vegetation(self):
        """只取首夜已验真实树叶/草网格，不改其文件、不添加图片。"""
        path = Path(__file__).resolve().parents[2] / 'act01_approach/act01_approach.glb'
        self.approach_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(path))
        bpy.context.view_layer.update()
        for ob in list(bpy.data.objects):
            if ob in before: continue
            if ob.type == 'MESH' and ob.name.startswith(('60_Cedar_', '61_Cedar_', '70_Ferns_', '71_Fallen_', '72_Leaves_')):
                data = ob.data.copy(); data.transform(ob.matrix_world)
                self.original['Approach:' + ob.name] = data
        for ob in list(bpy.data.objects):
            if ob not in before: bpy.data.objects.remove(ob, do_unlink=True)

    @staticmethod
    def bsdf(mat): return next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    def choose(self, *prefixes): return [n for n in self.original if n.startswith(prefixes)]
    def bounds(self, names):
        pts=[v.co for n in names for v in self.original[n].vertices]
        return Vector(tuple(min(v[i] for v in pts) for i in range(3))),Vector(tuple(max(v[i] for v in pts) for i in range(3)))
    def fit(self, names, center, size):
        lo,hi=self.bounds(names);scale=Vector(tuple(size[i]/max(.000001,hi[i]-lo[i]) for i in range(3)))
        return affine(scale,Vector(center)-(lo+hi)*.5*scale)
    def group(self,name,parent=None):
        ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob);ob.parent=parent;return ob
    def join(self,name,objects,parent):
        if not objects:return None
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=name;ob.parent=parent
        return ob
    def batch(self,name,names,transform,parent):
        objects=[]
        for key in names:
            data=self.original[key].copy();data.transform(transform)
            ob=bpy.data.objects.new(key,data);bpy.context.collection.objects.link(ob);objects.append(ob)
        return self.join(name,objects,parent)
    def box(self,name,center,size,mat,parent,bevel=.012):
        bpy.ops.mesh.primitive_cube_add(size=1,location=center);ob=bpy.context.object;ob.name=name;ob.scale=size
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);ob.data.materials.append(mat)
        if bevel:
            mod=ob.modifiers.new('磨损实体棱','BEVEL');mod.width=bevel;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
        ob.parent=parent
        if mat == self.paper: self.quiet_paper_uv(ob.data)
        return ob
    def mesh(self,name,verts,faces,mat,parent):
        data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.materials.append(mat);data.update()
        ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob);ob.parent=parent
        planar_uv(data,(2.4,2.4),(0,2))
        if mat == self.paper: self.quiet_paper_uv(data)
        return ob
    @staticmethod
    def quiet_paper_uv(mesh):
        """仅选原纸图上缘平缓纤维区，避免小器物被整幅旧污斑占满。"""
        uv=mesh.uv_layers.active
        if not uv:return
        lo=[min(v.uv[i] for v in uv.data) for i in range(2)]
        hi=[max(v.uv[i] for v in uv.data) for i in range(2)]
        for value in uv.data:
            u=(value.uv.x-lo[0])/max(.00001,hi[0]-lo[0]);v=(value.uv.y-lo[1])/max(.00001,hi[1]-lo[1])
            value.uv=(.36+u*.14,.93+v*.06)

    def branch(self,name,a,b,radius1,radius2,mat,parent,vertices=10):
        a,b=Vector(a),Vector(b);direction=b-a
        bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius1,radius2=radius2,depth=direction.length,location=(a+b)*.5)
        ob=bpy.context.object;ob.name=name;ob.rotation_euler=direction.to_track_quat('Z','Y').to_euler();ob.data.materials.append(mat);ob.parent=parent;return ob
    def beam(self,name,a,b,width,depth,mat,parent):
        a,b=Vector(a),Vector(b);direction=b-a
        ob=self.box(name,(a+b)*.5,(width,depth,direction.length),mat,parent,.006);ob.rotation_euler=direction.to_track_quat('Z','Y').to_euler();return ob
    def floor(self,parent,stone=False):
        group=self.group('ForegroundFloor',parent)
        if not stone:
            names=self.choose('Deck board','Dark flush deck nail','Quiet worn plank ridge')
            for key in self.choose('Deck board'):
                data=self.original[key];uv=data.uv_layers.active
                for poly in data.polygons:
                    for li in poly.loop_indices:
                        v=data.vertices[data.loops[li].vertex_index].co
                        uv.data[li].uv=(v.x/2.4,v.y/7 if abs(poly.normal.z)>.5 else v.z/7)
            self.batch('Aged_cedar_floor_original_planks',names,self.fit(names,(0,0,-.053),(11.56,5.64,.15)),group)
        else:
            # 每块保留轻微缺角轮廓和不同UV偏移，顶面一致低于调查金环。
            slabs=[]
            for row in range(7):
                for col in range(11):
                    x=-5.24+col*1.048;y=-2.4+row*.80
                    ob=self.box('Worn_slate_slab',(x,y,-.041),(1.02,.774,.124),self.stone,group,.042)
                    planar_uv(ob.data,(2.2,2.2));uv=ob.data.uv_layers.active
                    for loop in uv.data:loop.uv+=Vector((col*.23,row*.17))
                    slabs.append(ob)
            self.join('Stone_forecourt_worn_slabs',slabs,group)
        names=['Veranda substructure shadow','Front worn fascia']
        self.batch('Foundation_cedar_fascia',names,self.fit(names,(0,0,-.33),(11.86,5.9,.66)),group)
        return group
    def garden(self,parent):
        garden=self.group('CourtyardStones',parent)
        earth=['Garden dark earth']
        ground=self.batch('Continuous_original_stone_ground',earth,self.fit(earth,(0,-1,-.77),(34,25,.35)),garden)
        ground.data.materials.clear();ground.data.materials.append(self.stone);planar_uv(ground.data,(3.8,3.8))
        names=self.choose('Low garden moss stone');parts=[]
        # 所有石体均匀缩放、真实底点贴地，前景与左右台基相接。
        for i,key in enumerate(names):
            for layer in range(2):
                x=-14+(i%14)*2.05+(layer*.65);y=-3.54-(i//14)*1.1-layer*1.35
                scale=.85+(i%4)*.15
                parts.append(self.batch('Grounded_original_moss_stone',[key],uniform_grounded_transform(self.original[key],(x,y),scale,-.65),garden))
        self.join('Grounded_natural_foreground_rocks',parts,garden)
        for side in (-1,1):
            parts=[]
            for i in range(9):
                key=names[i];parts.append(self.batch('Side_root_rock',[key],uniform_grounded_transform(self.original[key],(side*(6.4+(i%2)*.55),-2+i*.82),1.0+(i%3)*.2,-.55),garden))
            self.join('Side_moss_rockbank_%d'%side,parts,garden)
        self.load_approach_vegetation()
        for side in (-1,1):
            # 首夜真实叶片替代原回廊粗大的多面叶团；布局中心独立移动，保持比例。
            names=self.choose('Approach:60_Cedar_1', 'Approach:61_Cedar_1')
            lo,hi=self.bounds(names);sc=.88
            transform=affine((sc,sc,sc),Vector((side*7.6,4.8,-.56))-Vector(((lo.x+hi.x)*.5,(lo.y+hi.y)*.5,lo.z))*sc)
            self.batch('Approach_leaf_cedar_%d'%side,names,transform,garden)
        return garden
    def post(self,parent,x,y=2.65,height=3,wide=.26,name='Cedar_post'):
        group=self.group(name,parent)
        self.batch(name+'_timber',['Cedar principal post -0.8'],self.fit(['Cedar principal post -0.8'],(x,y,height*.5),(wide,wide,height)),group)
        self.batch(name+'_shoe',['Post stone shoe -0.8'],self.fit(['Post stone shoe -0.8'],(x,y,.10),(wide,wide,.20)),group)
        self.batch(name+'_joint',['Upper tie joint -0.8'],self.fit(['Upper tie joint -0.8'],(x,y,height-.08),(max(wide,.48),.32,.24)),group)
        return group
    def roof(self,parent,name,center,size):
        group=self.group(name,parent)
        prefixes=('Canopy exposed rafter','Continuous canopy beam','Curved clay tile roof','Soffit plank','Tile barrel ridge','Horizontal tile seam','Round kawara tile end','Eave stepped bracket')
        names=self.choose(*prefixes);transform=self.fit(names,center,size)
        for label,subset in [('Curved_original_roof',('Curved clay tile roof',)),('Barrel_tiles_and_round_ends',('Tile barrel ridge','Horizontal tile seam','Round kawara tile end')),('Exposed_original_cedar_rafters',('Canopy exposed rafter','Soffit plank')),('Layered_cedar_beams_and_brackets',('Continuous canopy beam','Eave stepped bracket'))]:
            self.batch(label,self.choose(*subset),transform,group)
        return group
    def lamp_at(self,parent,name,x,y,z,scale=1):
        names=self.choose('Altar lantern left');lo,hi=self.bounds(names)
        s=.43/(hi.z-lo.z)*scale
        group=self.group(name,parent)
        self.batch(name+'_source',names,affine((s,s,s),Vector((x,y,z))-(lo+hi)*.5*s),group)
        return group
    def coffin(self,parent,mirror=True):
        group=self.group('RitualPaperCoffin',parent);cx=.8;cy=1.6
        outline=[(-.91,-.28),(-.69,-.38),(.64,-.38),(.91,-.24),(.91,.24),(.64,.38),(-.69,.38),(-.91,.28)]
        parts=[self.box('Cedar_coffin_base',(cx,cy,.14),(1.81,.75,.18),self.wood,group)]
        parts.append(self.box('Dark_washi_bottom',(cx,cy,.238),(1.64,.62,.02),self.paper,group,.008))
        # 八片有厚度纤维纸壁及木边，真实开口；前壁稍低让嵌底铜镜可读。
        for i,(x,y) in enumerate(outline):
            nx,ny=outline[(i+1)%len(outline)];h=.285 if y<-.20 and ny<-.20 else .375
            a=Vector((cx+x,cy+y,.22));b=Vector((cx+nx,cy+ny,.22))
            # 端点X方向形成有厚度的竖直纸面，不用朝向相机的背景片。
            direction=b-a;ln=direction.length;ob=self.box('Folded_washi_coffin_wall',(a+b)*.5+Vector((0,0,h*.5)),(ln,.05,h),self.paper,group,.01);ob.rotation_euler.z=math.atan2(direction.y,direction.x);parts.append(ob)
            rail=self.box('Bronze_worn_coffin_rim',(a+b)*.5+Vector((0,0,h)),(ln+.018,.062,.035),self.edge,group,.008);rail.rotation_euler.z=math.atan2(direction.y,direction.x);parts.append(rail)
            if i%2==0:parts.append(self.box('Cedar_coffin_corner',(cx+x,cy+y,.405),(.036,.052,.38),self.wood,group,.005))
        self.join('Folded_paper_coffin_shell',parts,group)
        if mirror:
            lid=self.box('Partly_raised_paper_lid',(cx,cy+.255,.708),(1.68,.045,.43),self.paper,group,.018);lid.rotation_euler.x=math.radians(-30)
            # 镜盘法向朝前(-Y)并上仰，最低镜缘接棺底。
            g=self.group('TiltedBronzeMirror',group);center=Vector((cx+.23,cy-.015,.475));angle=math.radians(52)
            R=Matrix.Rotation(angle,4,'X');parts=[]
            for label,radius,depth,z,mat in [('Cast_bronze_mirror_back',.295,.03,0,self.bronze),('Mirror_polished_face',.25,.011,.022,self.mirror)]:
                bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=radius,depth=depth,location=center+R@Vector((0,0,z)));ob=bpy.context.object;ob.name=label;ob.rotation_euler.x=angle;ob.data.materials.append(mat);parts.append(ob)
            for i in range(18):
                a=i*math.tau/18;p=center+R@Vector((math.cos(a)*.276,math.sin(a)*.276,.027))
                bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=.009,location=p);ob=bpy.context.object;ob.data.materials.append(self.edge);parts.append(ob)
            self.join('Bronze_disk_rim_and_studs',parts,g)
        return group
    def hollow_tree(self,parent,cx,cy,scale=1):
        group=self.group('SacredTreeHollow',parent);parts=[];n=24;verts=[]
        # 连续起伏树干先成体，再布尔挖真实凹洞；不再用放射木片围椭圆。
        rings=[(0,.99),(.27,.96),(.62,.83),(1.05,.74),(1.52,.70),(2.03,.67),(2.53,.63),(2.94,.56),(3.20,.49)]
        for z,radius in rings:
            for i in range(n):
                a=i*math.tau/n
                r=radius*(1+.045*math.sin(a*5+z*.27)+.035*math.cos(a*7-z*.24))
                verts.append((cx+math.cos(a)*r*scale,cy+(.5+math.sin(a)*r*.71)*scale,z*scale))
        faces=[]
        for j in range(len(rings)-1):
            for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
        faces.append(tuple(reversed(range(n))));faces.append(tuple((len(rings)-1)*n+i for i in range(n)))
        trunk=self.mesh('Continuous_cedar_hollow_trunk',verts,faces,self.bark,group)
        planar_uv(trunk.data,(2.4,2.4),(2,0))
        profile=[(-.22,2.50),(.20,2.53),(.39,2.26),(.43,1.15),(.32,.55),(-.33,.54),(-.42,1.10),(-.39,2.22)]
        cutverts=[(cx+x*scale,cy+depth*scale,z*scale) for depth in (-.65,.85) for x,z in profile]
        cutfaces=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8)for i in range(8)]
        cutter=self.mesh('Temporary_true_hollow_cut',cutverts,cutfaces,self.bark,group)
        bpy.context.view_layer.objects.active=trunk
        mod=trunk.modifiers.new('真实深凹树洞','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
        bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
        planar_uv(trunk.data,(2.4,2.4),(2,0));parts.append(trunk)
        # 洞后深处保留暗内壁，前面没有填洞圆盘。
        parts.append(self.box('Hollow_recess_back',(cx,cy+.845*scale,1.53*scale),(.78*scale,.018,1.82*scale),self.dark,group,.006))
        paths=[((-.15,.48,2.82),(-.33,.54,4.2),.40,.27),((-.33,.54,4.2),(.07,.57,5.4),.27,.16),((-.15,.48,3.15),(-1.35,.6,4.12),.25,.12),((-1.35,.6,4.12),(-2.2,.64,4.35),.12,.055),((-.22,.55,4.0),(1.25,.67,4.8),.17,.065)]
        for a,b,r1,r2 in paths:
            parts.append(self.branch('Cedar_trunk_branch',Vector(a)*scale+Vector((cx,cy,0)),Vector(b)*scale+Vector((cx,cy,0)),r1*scale,r2*scale,self.bark,group,12))
        for i in range(9):
            a=i*math.tau/9
            parts.append(self.branch('Gnarled_grounded_root',(cx+math.cos(a)*.65*scale,cy+.45*scale+math.sin(a)*.35*scale,.56*scale),(cx+math.cos(a)*1.38*scale,cy+.45*scale+math.sin(a)*.65*scale,.08),.19*scale,.05*scale,self.bark,group,9))
        self.join('Hollow_tree_bark_roots_and_branches',parts,group)
        rope=self.choose('Braided rice-straw','Dry straw catchlight','Rice straw hanging fringe','Shide ')
        self.batch('Tree_braided_rope_and_shide',rope,self.fit(rope,(cx,cy-.12*scale,2.71*scale),(2.1*scale,.21*scale,.67*scale)),group)
        return group
    def export(self,out,slug,extra):
        out=Path(out);src=out/'source';src.mkdir(parents=True,exist_ok=True);(src/'.gdignore').write_text('')
        bpy.context.scene.world=None
        # 把顶点烘成共同世界坐标，保留逻辑父级与原UV，方便空间检测。
        for ob in list(bpy.data.objects):
            if ob.type=='MESH':
                ob.data.transform(ob.matrix_world);ob.matrix_world=Matrix.Identity(4)
        for mesh in list(bpy.data.meshes):
            if mesh.users==0:bpy.data.meshes.remove(mesh)
        for image in bpy.data.images:
            if image.type=='IMAGE' and not image.packed_file:image.pack()
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(src/(slug+'_editable.blend')),check_existing=False)
        path=out/(slug+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_cameras=False,export_lights=False,export_extras=True,export_yup=True,export_apply=True,export_animations=False)
        obs=[o for o in bpy.data.objects if o.type=='MESH']
        manifest={'version':1,'iteration':4,'original_blend_filename':self.source.name,'original_blend_sha256':self.source_hash,'production_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'original_textures_reused':5,'blender_version':bpy.app.version_string,'mesh_objects':len(obs),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in obs),'floor_top':.022,'collision_policy':'保留原碰撞，无新碰撞','coordinate_system':'Blender Z-up to glTF Y-up; Godot原位载入','tree_roof_gap_metres':.4}
        manifest['approach_vegetation_sha256']=getattr(self,'approach_hash',None)
        manifest.update(extra);(src/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
        print('SHRINE_ASSET_BUILD',json.dumps(manifest,ensure_ascii=False))
