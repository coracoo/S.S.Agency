#!/usr/bin/env python3
"""原生矢量曲线直接栅格化成straight RGBA；无视频、抠像或人物合成。"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'assets/effects/illustrated_spells'
CELL, FRAMES, COLS, SS = 192, 24, 6, 3
TAU = math.tau

def point(x, y, angle=0):
    return (x * math.cos(angle) - y * math.sin(angle), x * math.sin(angle) + y * math.cos(angle))

class Vector:
    def __init__(self):
        self.image = Image.new('RGBA', (CELL * SS, CELL * SS))
        self.draw = ImageDraw.Draw(self.image)

    def coords(self, xy):
        return [((x + 96) * SS, (y + 96) * SS) for x, y in xy]

    def polygon(self, xy, color, outline=None, width=1):
        self.draw.polygon(self.coords(xy), fill=color)
        if outline:
            self.line(xy + xy[:1], outline, width)

    def line(self, xy, color, width=1):
        self.draw.line(self.coords(xy), fill=color, width=max(1, round(width * SS)), joint='curve')

    def path(self, start, segments, color, outline=None, width=1):
        xy, current = [start], start
        for a, b, end in segments:
            for i in range(1, 15):
                t = i / 14
                xy.append(tuple((1-t)**3*current[j]+3*(1-t)**2*t*a[j]+3*(1-t)*t*t*b[j]+t**3*end[j] for j in (0, 1)))
            current = end
        self.polygon(xy, color, outline, width)

    def petal(self, cx, cy, size, angle, color, outline=None):
        def tr(p):
            x, y = point(p[0] * size, p[1] * size, angle)
            return cx + x, cy + y
        self.path(tr((0, -1)), [(tr((-0.9, 0)), tr((-0.5, 0.9)), tr((0, 1))), (tr((0.5, 0.9)), tr((0.9, 0)), tr((0, -1)))], color, outline)

    def shard(self, cx, cy, length, width, angle, alpha=255):
        def tr(x, y):
            px, py = point(x, y, angle)
            return px + cx, py + cy
        self.polygon([tr(0,-length),tr(width,-length*.15),tr(width*.45,length*.5),tr(-width*.7,length*.35),tr(-width,-length*.15)], (57,139,194,alpha), (178,237,248,alpha), 1)
        self.polygon([tr(0,-length),tr(width,-length*.15),tr(0,length*.5)], (217,250,255,alpha))
        self.polygon([tr(0,-length),tr(0,length*.5),tr(-width,-length*.15)], (96,208,237,alpha))
        self.line([tr(0,-length),tr(0,length*.5)], (255,255,242,alpha), .7)

    def finish(self):
        return self.image.resize((CELL, CELL), Image.Resampling.LANCZOS)

def flame(v, cx, cy, size, angle=0, phase=0, alpha=255):
    def tr(x,y):
        a,b=point(x*size,y*size,angle)
        return (cx+a,cy+b)
    sway=math.sin(phase*TAU)*.18
    shape=[((-0.5,.45),(-.55,.1),(-.32,-.14)),((-.48,.06),(-.26,-.3),(-.3,-.68)),((-.12,-.4),(.03,-.77),(.12+sway,-1.05)),((.03,-.28),(.38,-.3),(.35,-.61)),((.6,-.1),(.58,.4),(.1,.55)),((-.05,.7),(-.25,.6),(-.4,.48))]
    v.path(tr(-.4,.48),[(tr(*a),tr(*b),tr(*c)) for a,b,c in shape],(228,66,34,alpha),(255,139,67,alpha),1)
    inner=[((-.23,.38),(-.23,.01),(-.08,-.23)),((.03,.08),(.16,-.25),(.19,-.49)),((.4,-.03),(.4,.37),(.05,.48)),((-.03,.52),(-.1,.49),(-.18,.45))]
    v.path(tr(-.18,.45),[(tr(*a),tr(*b),tr(*c)) for a,b,c in inner],(255,176,60,alpha))
    v.petal(cx,cy+size*.22,size*.22,angle,(255,242,159,alpha))

def ribbon(v, points, width, color, highlight):
    # 宽窄随曲线变化，笔触前端收尖；可编辑曲线而非随机烟球。
    top,bottom=[],[]
    for i,(x,y) in enumerate(points):
        amount=math.sin(math.pi*i/(len(points)-1))**.65*width
        top.append((x,y-amount));bottom.append((x,y+amount*.5))
    v.polygon(top+bottom[::-1],color)
    v.line([(x,y-width*.14) for x,y in points[2:-1]],highlight,.8)

def fire_frame(phase,t):
    v=Vector()
    if phase=='cast':
        for i in range(3):
            a=i*TAU/3+t*1.4
            flame(v,math.cos(a)*14,math.sin(a)*12,13+11*t,a+.5,t+i*.3,round(200+55*t))
    elif phase=='projectile':
        for i in range(3):
            pts=[(-74+j*8, (i-1)*12+math.sin(j*.6+t*8+i)*7) for j in range(17)]
            ribbon(v,pts,6-i,(213+15*i,62+36*i,36,230),(255,213,117,245))
        flame(v,37,0,35,math.pi/2,t)
    else:
        a=round(255*(1-t)**.6)
        for i in range(5):
            angle=(i-2)*.46
            flame(v,math.sin(angle)*(12+37*t),20-math.cos(angle)*(5+23*t),36*(1-t*.4),angle,t+i*.2,a)
        for i in range(9):
            angle=i*2.39996
            v.petal(math.cos(angle)*(22+48*t),math.sin(angle)*(15+40*t)-12,3.5*(1-t)+1,angle,(255,213,126,a))
    return v.finish()

def ice_frame(phase,t):
    v=Vector()
    if phase=='cast':
        for i in range(3):
            a=i*TAU/3+t*.5
            v.shard(math.cos(a)*14,math.sin(a)*14,11+13*t,5,a+math.pi/2,round(180+75*t))
    elif phase=='projectile':
        for i in range(4):
            y=(i-1.5)*12
            v.line([(-76,y+4),(-40,y),(14,y)],(98,200,236,120+i*24),1.3)
        v.shard(24,0,52+2*math.sin(t*TAU),12,math.pi/2)
        v.shard(-24,-24+3*math.sin(t*TAU),21,7,math.pi/2+.08,210)
        v.shard(-39,22-3*math.sin(t*TAU),17,6,math.pi/2-.08,200)
    else:
        a=round(255*(1-t)**.5)
        for i in range(7):
            angle=i*TAU/7+.2
            d=12+38*t
            v.shard(math.cos(angle)*d,math.sin(angle)*d,24-10*t,6-2*t,angle+math.pi/2,a)
        for i in range(5):
            ang=i*2.39996
            v.line([(0,0),(math.cos(ang)*28,math.sin(ang)*25),(math.cos(ang+.12)*(46+24*t),math.sin(ang+.12)*(42+20*t))],(202,246,255,round(a*.65)),1.2)
    return v.finish()

def bell(v, y, scale, alpha=255):
    v.path((-18*scale,y+10*scale),[((-10*scale,y),( -13*scale,y-16*scale),(0,y-19*scale)),((13*scale,y-16*scale),(10*scale,y),(18*scale,y+10*scale)),((8*scale,y+17*scale),(-8*scale,y+17*scale),(-18*scale,y+10*scale))],(220,220,153,alpha),(255,250,202,alpha),1)
    v.line([(-15*scale,y+9*scale),(15*scale,y+9*scale)],(101,164,129,alpha),2)
    v.petal(0,y+17*scale,3*scale,0,(255,244,183,alpha))
    v.line([(0,y-19*scale),(0,y-27*scale)],(250,241,167,alpha),1.3)

def heal_frame(phase,t):
    v=Vector()
    if phase=='cast':
        bell(v,0,.55+.45*t,round(180+75*t))
        for i in range(4):
            angle=i*TAU/4+t
            v.petal(math.cos(angle)*30,math.sin(angle)*23,7,angle,(153,236,196,round(140+100*t)))
    elif phase=='projectile':
        for i in range(5):
            v.petal(-42+i*17,math.sin(i*.9+t*5)*11,7-i*.4,.3+i*.6,(153+i*18,232,191,180+i*15))
        bell(v,0,.62,245)
    else:
        a=round(255*(1-t)**.6)
        bell(v,-34-15*t,.65,a)
        for i in range(7):
            angle=(i-3)*.43
            v.petal(math.sin(angle)*(24+22*t),26-math.cos(angle)*17,17*(1-t*.25),angle,(106+i*15,218+i*4,171+i*6,a),(216,255,218,a))
        for i in range(9):
            angle=i*2.39996
            v.petal(math.cos(angle)*(28+31*t),math.sin(angle)*(19+19*t)-t*36,4+2*(i%2),angle+t,(206,255,222,a))
        for level in range(2):
            y=14-level*29-t*20
            pts=[(-57+j*6.3,y+math.sin(j*math.pi/18)*7) for j in range(19)]
            ribbon(v,pts,1.6,(159,246,214,round(a*.6)),(220,255,224,a))
    return v.finish()

def wave_frame(phase,t):
    v=Vector(); a=255 if phase!='impact' else round(255*(1-t)**.6)
    if phase=='cast':
        for i in range(3): flame(v,(i-1)*21,8,24+t*12,0,t+i*.3,a)
    else:
        for i in range(5):
            x=(i-2)*27
            h=34+14*math.sin(i*.8+t*5)
            flame(v,x,18-i*3,h,-.28,t+i*.17,a)
        pts=[(-80+i*8,30+math.sin(i*.32+t*4)*9) for i in range(21)]
        ribbon(v,pts,7,(217,80,39,a),(255,216,125,a))
    return v.finish()

def brand_frame(phase,t):
    v=Vector(); a=255 if phase!='impact' else round(255*(1-t)**.5)
    s=.55+.4*t if phase=='cast' else 1
    if phase=='projectile':
        flame(v,10,0,31,math.pi/2,t,a)
        ribbon(v,[(-66+i*9,math.sin(i*.7+t*4)*8) for i in range(11)],4,(223,92,45,a),(255,221,143,a))
    else:
        # 灼印为破口菱框与火字式印记，区别火弹爆焰。
        for side in (-1,1):
            v.line([(side*7*s,-42*s),(side*37*s,0),(side*11*s,36*s)],(255,173,86,a),3)
        for points in [[(-21,-12),(21,-12)],[(-12,-25),(-9,15),(-27,31)],[(11,-25),(8,15),(27,31)],[(-3,0),(4,25)]]:
            v.line([(x*s,y*s) for x,y in points],(255,223,137,a),4)
        for i in range(4): flame(v,(i-1.5)*19,40-12*t,13+8*t,0,t+i*.2,a)
    return v.finish()

def group_frame(phase,t):
    v=Vector(); a=255 if phase!='impact' else round(255*(1-t)**.55)
    if phase=='cast':
        for i in range(3): bell(v,-10+i*7,.34+.12*t,round(a*(.65+.15*i)))
    elif phase=='projectile':
        for i in range(7): v.petal(-50+i*17,math.sin(i*.8+t*4)*20,9,i*.7,(227,244,163,a))
    else:
        for i in range(3):
            x=(i-1)*42
            for j in range(5): v.petal(x+math.sin((j-2)*.55)*19,20-math.cos((j-2)*.55)*13,13,(j-2)*.55,(147+j*14,226+j*5,169+j*7,a),(234,255,212,a))
            v.petal(x,-36-20*t,7,0,(252,248,181,a))
        for i in range(3):
            pts=[(-77+j*7,33-i*24-t*18+math.sin(j*math.pi/22)*15) for j in range(23)]
            ribbon(v,pts,2.8,(192,241,169,round(a*.8)),(255,254,207,a))
    return v.finish()

def cleanse_frame(phase,t):
    v=Vector(); a=255 if phase!='impact' else round(255*(1-t)**.55)
    if phase=='cast':
        for i in range(5): v.petal((i-2)*12,math.cos(i)*9,11,math.pi/2,(209,250,226,a))
    elif phase=='projectile':
        for i in range(3):
            ribbon(v,[(-72+j*8,(i-1)*14+math.sin(j*.35+t*4)*10) for j in range(18)],4,(153,224,205,a),(249,255,228,a))
    else:
        for i in range(3):
            pts=[(-62+j*7,math.sin(j*.3+t*3)*22+25-i*26-t*13) for j in range(19)]
            ribbon(v,pts,7-i*1.5,(121+i*27,216+i*12,199+i*10,a),(240,255,220,a))
        for i in range(7):
            side=1 if i%2 else -1
            x=side*(30+42*t);y=-28+i*8-26*t
            v.polygon([(x,y-5),(x+side*9,y),(x+side*3,y+7),(x-side*3,y+2)],(117,115,146,round(a*.65)))
            v.petal(x*.85,y-12,4,i,(249,255,226,a))
    return v.finish()

def shield_frame(phase,t,steel=False):
    v=Vector(); a=255 if phase!='impact' else round(255*(1-t)**.4)
    s=.4+.4*t if phase=='cast' else (.65 if phase=='projectile' else .8+.16*math.sin(t*math.pi))
    y=-3
    if steel:
        outer=[(-40,-43),(0,-58),(40,-43),(34,20),(0,62),(-34,20)]
        fill=(102,146,175,round(a*.45)); edge=(198,228,235,a)
    else:
        outer=[(0,-68),(43,-34),(43,32),(0,64),(-43,32),(-43,-34)]
        fill=(123,189,166,round(a*.25)); edge=(250,246,179,a)
    v.polygon([(x*s,y0*s+y) for x,y0 in outer],fill,edge,2)
    for i in range(len(outer)):
        x1,y1=outer[i];x2,y2=outer[(i+1)%len(outer)]
        assemble=max(0,1-t*5) if phase=='impact' else 0
        dx,dy=(x1+x2)*.10*assemble,(y1+y2)*.10*assemble
        flash=max(0,1-abs(t*6-i)*1.5)
        v.polygon([(dx,y+dy),(x1*s+dx,y1*s+y+dy),(x2*s+dx,y2*s+y+dy)],(130+i*10,192+i*6,177+i*8,round(a*(.10+.04*(i%3)+flash*.26))),edge,.6)
    v.line([(0,-53*s),(0,48*s)],edge,2)
    if steel:
        for side in (-1,1):
            for i in range(3): v.line([(side*40*s,(-23+i*20)*s),(side*(65-i*5)*s,(-32+i*21)*s)],edge,3)
    else:
        for i in range(4): v.petal(math.cos(i*TAU/4)*60*s,math.sin(i*TAU/4)*67*s,5,0,edge)
    return v.finish()

def paper(v,cx,cy,w,h,angle,alpha=255,ink=(97,65,136)):
    def tr(x,y):
        px,py=point(x,y,angle);return cx+px,cy+py
    v.polygon([tr(-w,-h),tr(w,-h*.96),tr(w,h*.73),tr(w*.4,h),tr(0,h*.85),tr(-w*.6,h),tr(-w,h*.7)],(235,222,183,alpha),(252,241,211,alpha),.7)
    for j in range(4):
        y=-h*.65+j*h*.37
        v.line([tr(-w*.58,y),tr(w*.5,y-w*.3),tr(-w*.25,y+w*.55)],(*ink,alpha),1.7)
    v.line([tr(0,-h*.78),tr(0,h*.67)],(*ink,alpha),1.3)

def weaken_frame(phase,t):
    v=Vector();a=255 if phase!='impact' else round(255*(1-t)**.6)
    if phase=='cast': paper(v,0,0,9,25,-.2+.4*t,a)
    elif phase=='projectile':
        for i in range(3): paper(v,-37+i*28,math.sin(i+t*5)*10,7,17,math.pi/2+.12*math.sin(t*7+i),a)
    else:
        for i in range(3): paper(v,(i-1)*27,-18+18*t+abs(i-1)*13,10,29,(i-1)*.2,a)
        for i in range(3):
            pts=[(-61+j*7,18+i*11+math.sin(j*.37+t*4+i)*9) for j in range(18)]
            ribbon(v,pts,3,(95,73,131,round(a*.8)),(180,158,211,a))
    return v.finish()

def slow_frame(phase,t):
    v=Vector();a=255 if phase!='impact' else round(255*(1-t)**.5)
    s=.4+.5*t if phase=='cast' else (.7 if phase=='projectile' else 1)
    # 双三角沙漏与横向锁链；不复用虚弱符纸的垂落形态。
    for side in (-1,1):
        v.polygon([(-27*s,side*40*s),(27*s,side*40*s),(0,0)],(111,133,192,round(a*.24)),(189,207,245,a),1.4)
        v.line([(-33*s,side*44*s),(33*s,side*44*s)],(236,225,188,a),3)
    for i in range(5): v.petal((i%2-.5)*3,(-20+i*9+t*17)%43-20,2,0,(242,228,174,a))
    for side in (-1,1):
        for i in range(3):
            cx=side*(32+i*16+max(0,.2-t)*40)*s
            v.polygon([(cx,(-6+i*2)*s),(cx+8*s,i*2*s),(cx,(6+i*2)*s),(cx-8*s,i*2*s)],None,(155,180,223,a),1.5)
    return v.finish()

def seal_frame(phase,t):
    v=Vector();a=255 if phase!='impact' else round(255*(1-t)**.5)
    if phase=='cast': paper(v,0,4-8*t,8+2*t,23+7*t,-.25+.35*t,a,(156,70,68))
    elif phase=='projectile':
        paper(v,12,math.sin(t*TAU)*3,9+math.sin(t*TAU),35,math.pi/2+.08*math.sin(t*TAU),a,(156,70,68))
        for i in range(3): v.line([(-69,i*9-9),(-33,i*9-9)],(223,166,139,a),1)
    else:
        close=max(0,1-t*5)
        for angle in (-.65,.65): paper(v,math.copysign(18*close,angle),-12*close,12,56,angle*(1+.20*close),a,(148,65,76))
        d=20+9*math.exp(-t*12)*math.sin(t*24)
        v.polygon([(-d,-d),(d,-d),(d,d),(-d,d)],(146,46,65,round(a*.7)),(254,207,160,a),2)
        v.line([(-11,-9),(11,-9),(11,10),(-11,10),(-11,-9)],(255,235,190,a),1.4)
        v.line([(-8,1),(8,1),(0,1),(0,13)],(255,235,190,a),2)
    return v.finish()

def break_frame(phase,t):
    v=Vector();a=255 if phase!='impact' else round(255*(1-t)**.55)
    if phase=='cast':
        v.shard(0,0,25+12*t,8,-.55,200)
        paper(v,15,7,7,19,.45,a)
    elif phase=='projectile':
        for i in range(3): ribbon(v,[(-73+j*9,(i-1)*13+math.sin(j*.33+t*6)*8) for j in range(17)],3,(154,100,193,a),(251,211,247,a))
    else:
        for i in range(6):
            ang=i*TAU/6-math.pi/2
            d=18+35*t
            x,y=math.cos(ang)*d,math.sin(ang)*d
            pts=[point(-12,-18,ang),point(18,-7,ang),point(8,21,ang)]
            v.polygon([(x+px,y+py) for px,py in pts],(119,82,169,round(a*.4)),(226,184,246,a),1.5)
        ribbon(v,[(-65+i*7,(-65+i*7)*.78+math.sin(i*.25)*8) for i in range(20)],5,(228,192,247,a),(255,242,244,a))
        paper(v,-24-30*t,26+23*t,6,13,-.5-t,a)
    return v.finish()

def physical_frame(name,phase,t):
    v=Vector();a=255 if phase!='impact' else round(255*(1-t)**.65)
    if phase=='cast':
        if name in ['mark','taunt']: pass
        else:
            for i in range(3): v.petal((i-1)*13,0,8+i*3,.7,(241,226,180,a))
            return v.finish()
    if name in ['slash','sweep','armor_break']:
        horizontal=name=='sweep'
        for i in range(2):
            pts=[]
            for j in range(24):
                u=j/23
                x=-77+154*u
                y=(math.sin(u*math.pi)*24 if horizontal else x*.65)+i*12+t*8
                pts.append((x,y))
            ribbon(v,pts,(8 if i==0 else 3)*(1-t*.35),(162,215,205,a),(248,248,212,a))
        if name=='armor_break':
            for side in (-1,1):
                x=side*(16+31*t)
                v.polygon([(x,-39),(x+side*18,-29),(x+side*10,16),(x,34)],(131,156,164,round(a*.65)),(226,230,205,a),1.2)
    elif name=='shield_bash':
        v.polygon([(-27,-40),(18,-37),(33,0),(13,40),(-29,24)],(111,157,182,round(a*.7)),(235,227,182,a),2)
        for i in range(7):
            ang=-1.4+i*.46
            x,y=point(35+32*t,0,ang)
            v.line([(x*.7,y*.7),(x,y)],(255,232,161,a),3)
    elif name=='taunt':
        for side in (-1,1):
            v.line([(side*18,-41),(side*36,-20),(side*18,0)],(243,172,99,a),4)
            v.line([(side*39,-40),(side*57,-20),(side*39,0)],(255,229,166,a),2)
        v.polygon([(-5,-26),(5,-26),(3,7),(-3,7)],(251,215,141,a))
        v.petal(0,21,4,0,(255,238,180,a))
    elif name=='mark':
        size=31+6*math.sin(t*math.pi)
        for i in range(4):
            ang=i*TAU/4
            pts=[point(-9,-size,ang),point(0,-size-12,ang),point(9,-size,ang)]
            v.line(pts,(252,228,163,a),2)
        v.polygon([(0,-17),(12,0),(0,17),(-12,0)],(185,145,91,round(a*.5)),(255,234,180,a),1.4)
    elif name=='hunt':
        for i in range(3):
            y=(i-1)*17
            v.line([(-74,y+10),(44,y)],(229,218,166,a),2)
            v.polygon([(65,y-2),(35,y-10),(40,y+11)],(255,239,183,a))
        if phase=='impact':
            for i in range(5):
                angle=i*2.39996
                v.line([point(24,0,angle),point(43+25*t,0,angle)],(244,214,133,a),2)
    elif name=='battle_spirit':
        for i in range(5):
            x=(i-2)*21
            ribbon(v,[(x+math.sin(j*.6+t*4)*6,43-j*9) for j in range(10)],4,(213,123,74,a),(253,230,157,a))
        v.polygon([(-15,6),(0,-13),(15,6),(0,31)],(251,219,155,round(a*.65)))
    elif name=='smoke_screen':
        for i in range(5):
            pts=[(-73+j*8,math.sin(j*.35+t*4+i)*17+(i-2)*17) for j in range(19)]
            ribbon(v,pts,7,(91+i*12,104+i*11,134+i*9,round(a*.65)),(172,188,198,round(a*.7)))
        for i in range(4): v.petal((i-1.5)*31,25-53*t,5,i+t,(211,209,178,a))
    return v.finish()

RENDERERS={'firebolt':fire_frame,'flame_wave':wave_frame,'ice_arrow':ice_frame,'burn_brand':brand_frame,'heal':heal_frame,'group_heal':group_frame,'cleanse':cleanse_frame,'holy_shield':shield_frame,'weaken':weaken_frame,'slow':slow_frame,'seal':seal_frame,'magic_break':break_frame,'protect':lambda p,t:shield_frame(p,t,True)}
for _name in ['slash','sweep','armor_break','shield_bash','taunt','mark','hunt','battle_spirit','smoke_screen']:
    RENDERERS[_name]=lambda phase,t,name=_name:physical_frame(name,phase,t)

def build(selected, evidence):
    OUTPUT.mkdir(parents=True,exist_ok=True)
    manifest_path=OUTPUT/'manifest.json'
    manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {'schema_version':1,'source':'作者矢量Bezier曲线与多边形，直接透明RGBA栅格化，无视频/无色键','alpha_mode':'straight','cell_size':[CELL,CELL],'columns':COLS,'frame_count':FRAMES,'frame_rate':24,'texture_bytes_each':CELL*CELL*FRAMES*4,'actions':{}}
    previews=[]
    for name in selected:
        atlas=Image.new('RGBA',(CELL*COLS,CELL*4))
        frames=[];hashes=[]
        for index in range(FRAMES):
            phase='cast' if index<6 else ('projectile' if index<12 else 'impact')
            start,end=(0,5) if phase=='cast' else ((6,11) if phase=='projectile' else (12,23))
            t=(index-start)/(end-start)
            im=RENDERERS[name](phase,t) if index != 23 else Image.new('RGBA',(CELL,CELL))
            atlas.paste(im,((index%COLS)*CELL,(index//COLS)*CELL))
            hashes.append(hashlib.sha256(im.tobytes()).hexdigest());frames.append(im)
        path=OUTPUT/(name+'.png');atlas.save(path,optimize=True)
        manifest['actions'][name]={'file':name+'.png','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'frames_rgba_sha256':hashes,'selected_frames':list(range(FRAMES)),'phases':{'cast':[0,1,2,3,4,5],'projectile':[6,7,8,9,10,11],'impact':list(range(12,24))},'nominal_frame_ms':[1000/24]*FRAMES,'anchor':[96,96],'duration_seconds':1.0,'loop':False}
        previews.append((name,frames))
    manifest['generator_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    if evidence:
        evidence.mkdir(parents=True,exist_ok=True)
        board=Image.new('RGB',(CELL*5,len(previews)*(CELL+28)),(27,36,46));draw=ImageDraw.Draw(board)
        for row,(name,frames) in enumerate(previews):
            for col,frame in enumerate([4,8,12,15,19]):
                x,y=col*CELL,row*(CELL+28)
                draw.text((x+8,y+7),f'{name} / frame {frame}',fill=(235,223,187))
                board.paste(frames[frame],(x,y+28),frames[frame])
        board.save(evidence/'proof_contact.png')
        (evidence/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'built':selected,'atlas_size':[CELL*COLS,CELL*4],'each_rgba_mib':manifest['texture_bytes_each']/1048576,'evidence':str(evidence)},ensure_ascii=False))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skills',nargs='+',default=list(RENDERERS))
    parser.add_argument('--evidence',type=Path)
    args=parser.parse_args()
    build(args.skills,args.evidence)
