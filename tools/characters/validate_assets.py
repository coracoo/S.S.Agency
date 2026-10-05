#!/usr/bin/env python3
"""只读检查生产精灵画布、透明边界、动作节奏；不将源图整理等同于手工像素绘制。"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = ('idle','walk','attack','hit','defend','down','recover')

def high_detail_alpha_errors(image: Image.Image, label: str) -> list[str]:
    errors=[]
    if image.mode!='RGBA': errors.append(label+': 高清帧须保留RGBA透明通道')
    rgba=image.convert('RGBA'); histogram=rgba.getchannel('A').histogram()
    if not histogram[0]: errors.append(label+': 缺少透明背景，不能使用整张不透明底')
    # 允许绘制素材的真实软边；alpha>=128的实体须超过孤立噪点规模。
    if sum(histogram[128:]) < max(16,math.ceil(rgba.width*rgba.height*0.0001)):
        errors.append(label+': 缺少有效人物主体，空帧或稀疏噪点不能通过')
    return errors

def validate_manifest(path: Path, root: Path = ROOT, profile: str = 'legacy_pixel') -> list[str]:
    errors = []
    if not path.exists(): return [f'缺少清单: {path}']
    try: manifest = json.loads(path.read_text())
    except (ValueError,OSError) as exc: return [str(exc)]
    canvas = manifest.get('canvas',{})
    high_detail = profile == 'high_detail'
    if profile not in ('legacy_pixel','high_detail'): return ['未知素材合同: '+profile]
    expected_size = (canvas.get('w'),canvas.get('h')) if high_detail else (192,160)
    if high_detail:
        if any(type(n) is not int or n<=0 or n>4096 for n in expected_size):
            errors.append('高细节画布须为1..4096整数，尺寸按动作范围确定')
        anchor=canvas.get('anchor')
        if not isinstance(anchor,list) or len(anchor)!=2 or any(type(n) not in (int,float) or not math.isfinite(n) for n in anchor):
            errors.append('高细节脚锚必须为有限二元数组')
        elif all(type(n) is int and n>0 for n in expected_size) and (anchor[0]*2!=expected_size[0] or not 0<=anchor[1]<expected_size[1]):
            errors.append('高细节脚锚须水平居中且纵向在画布内')
        if canvas.get('content_height_px')!=1024: errors.append('高细节身体原生高度须1024px')
        if type(canvas.get('height_m')) not in (int,float) or not math.isfinite(canvas['height_m']) or canvas['height_m']<=0:
            errors.append('世界身高必须为有限正数')
    elif (canvas.get('w'),canvas.get('h'),canvas.get('anchor')) != (192,160,[96,148]):
        errors.append('画布必须192×160，脚锚[96,148]')
    anims = manifest.get('anims',{})
    for name in REQUIRED:
        if name not in anims: errors.append('缺少动作: '+name)
    all_colors = set()
    for name,spec in anims.items():
        frames, durations = spec.get('frames',[]),spec.get('durations_ms',[])
        if not frames or len(frames)!=len(durations): errors.append(name+': 帧数/时长不符')
        if any(not isinstance(d,(int,float)) or not math.isfinite(d) or d<=0 for d in durations): errors.append(name+': 无效时长')
        if name not in ('idle','walk') and spec.get('loop',False): errors.append(name+': 不得循环')
        for frame in frames:
            image_path = root / (manifest.get('dir','').removeprefix('res://') + frame + '.png')
            if not image_path.exists(): errors.append('缺帧: '+str(image_path));continue
            with Image.open(image_path) as original:
                image = original.convert('RGBA')
                if image.size != expected_size: errors.append(frame+(': 与清单原生画布不符' if high_detail else ': 必须192×160'))
                if high_detail:
                    errors.extend(high_detail_alpha_errors(original,frame))
                else:
                    pixels = list(image.get_flattened_data())
                    if any(a not in (0,255) for r,g,b,a in pixels): errors.append(frame+': alpha不是二值')
                    opaque = [(r,g,b) for r,g,b,a in pixels if a]
                    if not opaque: errors.append(frame+': 空帧')
                    all_colors.update(opaque)
                # 高清生成源的alpha=1等近透明噪点原样保留，裁边按可见软边实体判断。
                bounds = image.getchannel('A').point(lambda alpha: 255 if alpha>=8 else 0).getbbox() if high_detail else image.getchannel('A').getbbox()
                if bounds and (bounds[0]==0 or bounds[1]==0 or bounds[2]==image.width or bounds[3]==image.height):
                    errors.append(frame+': 接触画布边缘，可能裁切')
    if len(all_colors)>64: errors.append(f'共享调色板超过64色: {len(all_colors)}')
    idle=anims.get('idle',{})
    idle_durations=idle.get('durations_ms',[])
    idle_period=sum(idle_durations) + (sum(idle_durations[1:-1]) if idle.get('pingpong',False) else 0)
    if len(idle.get('frames',[]))!=4 or not idle.get('pingpong',False) or abs(idle_period-3000)>0.01:
        errors.append('idle须4姿势往返6帧/3000ms')
    for layer in manifest.get('layers',[]):
        if len(layer.get('frames',[]))!=len(idle.get('frames',[])):
            errors.append('layer帧数须与idle源帧匹配')
        for layer_path in layer.get('frames',[]):
            file=root/layer_path.removeprefix('res://')
            if not file.exists(): errors.append('缺少layer: '+str(file));continue
            with Image.open(file) as raw:
                layer_image=raw.convert('RGBA')
                if layer_image.size!=expected_size: errors.append('layer须匹配原生画布')
                if high_detail:
                    errors.extend(high_detail_alpha_errors(raw,'layer'))
                elif sum(layer_image.getchannel('A').histogram()[1:255]): errors.append('layer alpha不是二值')
                if not high_detail:
                    all_colors.update((r,g,b) for r,g,b,a in layer_image.get_flattened_data() if a)
    if len(all_colors)>64: errors.append(f'包含layers的共享调色板超过64色: {len(all_colors)}')
    walk=anims.get('walk',{})
    walk_count=len(walk.get('frames',[]))
    if walk_count not in (8,10) or abs(sum(walk.get('durations_ms',[]))-503.02)>0.01:
        errors.append('walk须8或历史10帧/503.02ms')
    expected_walk=[62.8775]*8 if walk_count==8 else [41.92,41.92,41.92,41.92,83.83,41.92,41.92,41.92,41.92,83.83]
    if walk.get('durations_ms',[]) != expected_walk:
        errors.append('walk逐帧相位改变')
    attack=anims.get('attack',{})
    if len(attack.get('frames',[]))!=6 or abs(sum(attack.get('durations_ms',[]))-460)>0.01:
        errors.append('attack须6帧/460ms')
    if attack.get('durations_ms',[]) != [75,55,95,55,80,100]:
        errors.append('attack逐帧相位改变')
    if high_detail:
        for name,count in {'idle':4,'walk':8,'attack':6,'hit':1,'defend':1,'down':1,'recover':1}.items():
            if len(anims.get(name,{}).get('frames',[]))!=count: errors.append(f'高细节完整集{name}须{count}张真姿态')
    return errors

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--form',default='rinne')
    parser.add_argument('--all',action='store_true')
    parser.add_argument('--manifest',type=Path,help='显式验收独立revision清单')
    parser.add_argument('--roster',type=Path,help='显式验收一套角色清单')
    parser.add_argument('--profile',choices=['legacy_pixel','high_detail'],default=None)
    args=parser.parse_args()
    chosen_profile=args.profile or 'legacy_pixel'
    if args.manifest:
        if args.all or args.roster: parser.error('--manifest不可与--all/--roster同时使用')
        forms=[(args.manifest.parent.name,args.manifest)]
    elif args.all or args.roster:
        roster=json.loads((args.roster or ROOT/'assets/chars/pixel/roster.json').read_text())
        chosen_profile=args.profile or roster.get('asset_profile','legacy_pixel')
        forms=[(form['id'],ROOT/form['manifest'].removeprefix('res://')) for form in roster['forms']]
    else:
        forms=[(args.form,ROOT/'assets/chars/pixel'/args.form/'manifest.json')]
    all_errors=[]
    for form,path in forms:
        errors=validate_manifest(path,profile=chosen_profile)
        print(form+': '+('PASS' if not errors else 'INCOMPLETE/FAIL'))
        for error in errors: print('  '+error)
        all_errors.extend(errors)
    return int(bool(all_errors))
if __name__=='__main__': raise SystemExit(main())
