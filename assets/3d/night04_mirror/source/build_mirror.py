"""第四夜偏殿：同源木构、半开纸门、嵌底铜镜及界外真实神木。"""
from pathlib import Path
import sys
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from shrine_source_helpers import SourceScene, affine, planar_uv
s=SourceScene(sys.argv[sys.argv.index('--')+1]);root=s.group('Night04SourceMirrorHall')
s.floor(root);s.garden(root)
frame=s.group('MirrorHallArchitecture',root)
for i,x in enumerate([-5.35,-2.6,0,2.6,5.35]):s.post(frame,x,name='Legacy_rear_post_%d'%i)
s.post(frame,-3.8,2.1,2.8,.7,'Legacy_left_timber_pillar')
# 可走区域外的侧柱与两侧墙不堵旧bounds。
for x in (-5.84,5.84):s.post(frame,x,-.0,2.92,.20,'Exterior_side_post')
s.batch('Cedar_back_dado',['Continuous wall foot rail'],s.fit(['Continuous wall foot rail'],(0,2.97,.44),(11.6,.2,.82)),frame)
s.batch('Upper_cedar_transom',['Continuous rear transom'],s.fit(['Continuous rear transom'],(0,2.85,2.95),(11.78,.27,.22)),frame)
for x in (-5.98,5.98):s.box('Side_wall_plaster',(x,1.3,1.33),(.18,3.3,2.66),s.plaster,frame)
doors=s.group('HalfOpenPaperDoors',root)
for i,(x,width) in enumerate([(-4.46,1.37),(-1.33,2.1),(.33,.62),(2.25,.58),(3.84,2.07)]):
    names=s.choose('Shoji_C_half_open ' if i in (2,3) else 'Shoji_A ')
    s.batch('Original_washi_panel_%d'%i,names,s.fit(names,(x,2.97,1.55),(width,.11,2.73)),doors)
# 纸门背后是有真实进深的阴暗庭院；只在非开口区增加暗壁。
for x,width in [(-3.3,5.1),(4.0,3.2)]:s.box('Deep_rear_wall',(x,3.2,1.42),(width,.18,2.84),s.wood,frame)
s.roof(root,'RoofRafters',(0,3.35,3.42),(12.18,2.06,.90))
s.coffin(root,True)
s.hollow_tree(root,1.18,5.25,.90)
for name,x,y,z in [('MirrorHallLampLeft',-4.72,2.42,2.45),('MirrorHallLampRight',4.68,2.42,2.45),('CourtyardSmallLamp',.40,5.0,.63)]:s.lamp_at(root,name,x,y,z,.8 if 'Small' in name else 1)
s.export(HERE.parent,'night04_mirror',{'tree_roof_gap_metres':.36,'story_hero':'棺底斜铜镜、半开纸门、庭后神木；无新增剧情','lighting_anchors_godot':{'mirror':[1.03,.62,-1.58],'left_lamp':[-4.72,2.45,-2.42],'right_lamp':[4.68,2.45,-2.42],'courtyard_lamp':[.4,.63,-5.0]}})
