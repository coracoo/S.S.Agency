"""第五夜：真实开放树庭、退后双檐、折纸队列与原位置空棺。"""
from pathlib import Path
import sys, math
from mathutils import Vector, Matrix
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[1]/'night04_mirror/source'))
from shrine_source_helpers import SourceScene, affine, planar_uv
s=SourceScene(sys.argv[sys.argv.index('--')+1]);root=s.group('Night05SourceHonden')
s.floor(root,stone=True);s.garden(root)
frame=s.group('HondenArchitecture',root)
for i,x in enumerate([-5.35,-2.6,0,2.6,5.35]):s.post(frame,x,name='Legacy_rear_post_%d'%i)
s.batch('Front_sanctuary_cedar_beam',['Continuous rear transom'],s.fit(['Continuous rear transom'],(0,2.75,3.05),(11.7,.31,.27)),frame)
# 连续石垣对应不可穿过的旧后墙；庭中可见树根不侵入可走区。
parts=[]
for i in range(18):parts.append(s.box('Rear_wall_worn_stone',(-5.52+i*.65,2.93,.32),(.633,.26,.62),s.stone,frame,.035))
s.join('Legacy_rear_stone_boundary',parts,frame)
s.box('Rear_sanctuary_dais',(0,5.5,-.015),(11.65,5.05,1.25),s.stone,frame,.06)
# 实体本殿退至树根/枝后，留出开放天井，而非树穿整片屋面。
for i,x in enumerate([-5.3,-3.55,-1.78,0,1.78,3.55,5.3]):s.post(frame,x,6.12,3.32,.26,'Rear_honden_post_%d'%i)
for i,x in enumerate([-4.45,-2.66,-.9,.9,2.66,4.45]):
 names=s.choose('Shoji_A ')
 s.batch('Honden_recessed_washi_%d'%i,names,s.fit(names,(x,6.29,1.98),(1.47,.11,2.61)),frame)
s.box('Honden_plaster_backing',(0,6.44,1.9),(11.2,.16,3.1),s.plaster,frame)
s.roof(root,'RoofRafters',(0,6.35,3.79),(12.4,2.55,1.02))
s.roof(root,'UpperRoofRafters',(0,6.8,4.63),(8.3,1.68,.72))
# 脊饰同源木材、真实前后深度；不新增祭祀符号或剧情。
for x in (-3.1,3.1):
 s.beam('Upper_chigi_crossing_a',(x,6.15,4.74),(x,7.26,5.56),.09,.11,s.wood,frame)
 s.beam('Upper_chigi_crossing_b',(x,7.26,4.74),(x,6.15,5.56),.09,.11,s.wood,frame)
tree=s.hollow_tree(root,-.54,3.61,1.0)
mark=s.group('CoffinShapedHollowMark',tree)
outline=[(-.30,.50),(.30,.50),(.50,.29),(.35,-.50),(-.35,-.50),(-.50,.29)]
for i,(x,z) in enumerate(outline):
 nx,nz=outline[(i+1)%len(outline)]
 s.branch('Thin_coffin_hollow_inlay',(-.54+x*.64,4.01,1.52+z*1.51),(-.54+nx*.64,4.01,1.52+nz*1.51),.014,.014,s.glow,mark,8)
s.coffin(root,mirror=False)
near=s.group('NearCoffinPattern',root)
for i,(x,z) in enumerate(outline):
 nx,nz=outline[(i+1)%len(outline)]
 s.branch('Small_empty_coffin_mark',(.3+x*.2,1.41,.43+z*.28),(.3+nx*.2,1.41,.43+nz*.28),.008,.008,s.glow,near,6)
# 原纸人队列位于后墙外。沿纸面折出真实厚度和中折，不制造积木身体。
people=s.group('PaperAttendants',root)
for i,x in enumerate([-4.62,-2.9,-1.08,1.72,3.12,4.54]):
 person=s.group('Folded_washi_attendant_%d'%i,people);y=3.27+(i%2)*.13;bottom=.61
 # 纸袍两侧不齐齐同宽，中央压痕为真实折线。
 verts=[(x-.145,y,bottom+.10),(x,y-.027,bottom+.08),(x+.145,y,bottom+.10),(x-.12,y,bottom+.97),(x,y-.035,bottom+1.0),(x+.12,y,bottom+.97)]
 robe=s.mesh('Creased_washi_robe',verts,[(0,1,4,3),(1,2,5,4)],s.paper,person)
 import bpy
 mod=robe.modifiers.new('真实薄纸厚度','SOLIDIFY');mod.thickness=.022;bpy.context.view_layer.objects.active=robe;bpy.ops.object.modifier_apply(modifier=mod.name)
 for side in (-1,1):
  ob=s.box('Flat_folded_arm',(x+side*.28,y-.005,bottom+.91),(.34,.026,.135),s.paper,person,.004);ob.rotation_euler.y=side*.22
  s.box('Paper_foot_fold',(x+side*.083,y-.01,bottom+.071),(.093,.034,.142),s.paper,person,.005)
 head=s.branch('Octagonal_blank_paper_head',(x,y+.014,bottom+1.18),(x,y-.024,bottom+1.18),.14,.14,s.paper,person,6)
 # 朝镜头的纸纤维按米UV，不写新图。
 for ob in list(person.children):
  if ob.type=='MESH':
   planar_uv(ob.data,(.7,.7),(0,2));s.quiet_paper_uv(ob.data)
 s.join('Folded_paper_person_%d'%i,list(person.children),person)
# 旧左粗柱由高石基+等比例原石灯覆盖，灯罩以上不变形。
lamp=s.group('TallStoneLantern',root);names=s.choose('Toro ');lo,hi=s.bounds(names);sc=.695/(hi.x-lo.x)
s.batch('Uniform_original_carved_toro',names,affine((sc,sc,sc),Vector((-3.8,2.1,.88))-Vector(((lo.x+hi.x)*.5,(lo.y+hi.y)*.5,lo.z))*sc),lamp)
s.box('Tall_moss_stone_pedestal',(-3.8,2.1,.45),(.69,.69,.90),s.stone,lamp,.045)
# 右侧木牌严格覆盖原1x2.4x.22足迹，文字几何只保留原有抽象旧痕。
plaque=s.group('VotiveTimberTablet',root)
s.box('Aged_tablet_body',(4.8,2.17,1.2),(1.0,.18,2.4),s.wood,plaque,.028)
s.box('Recessed_tablet_paper',(4.8,2.062,1.3),(.77,.026,1.96),s.paper,plaque,.006)
parts=[]
for i in range(7):parts.append(s.box('Old_tablet_mark',(4.62+(i%2)*.17,2.046,1.99-i*.23),(.12+(i%3)*.035,.008,.02),s.dark,plaque,.001))
s.join('Existing_weathered_tablet_marks',parts,plaque)
for x in (-4.45,4.45):s.lamp_at(root,'Honden_rear_lamp_%s'%x,x,5.98,2.63)
s.export(HERE.parent,'night05_honden',{'tree_roof_gap_metres':.22,'story_hero':'神木真实深洞与原棺纹、原纸列、双檐本殿；无新剧情','lighting_anchors_godot':{'hollow':[-.54,1.52,-4.01],'stone_lantern':[-3.8,2.08,-1.70],'empty_coffin':[.8,.65,-1.6],'rear_left':[-4.45,2.63,-5.98],'rear_right':[4.45,2.63,-5.98]}})
