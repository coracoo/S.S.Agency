"""活动编辑器资源使用毫秒权重，避免Godot的0.01最小权重改变短帧。"""
def write_sprite_frames(manifest,path):
    packed=manifest['packed_frames']; canvas=manifest['canvas']; names=list(dict.fromkeys(n for a in manifest['anims'].values() for n in a['frames']))
    atlases=list(dict.fromkeys(packed[n]['atlas'] for n in names)); ids={p:f'Texture_{i+1}' for i,p in enumerate(atlases)}
    out=[f'[gd_resource type="SpriteFrames" load_steps={len(atlases)+len(names)+1} format=3]','']
    for atlas in atlases: out.append(f'[ext_resource type="Texture2D" path="{atlas}" id="{ids[atlas]}"]')
    frame_ids={name:f'Frame_{i+1}' for i,name in enumerate(names)}
    for name in names:
        r=packed[name];x,y,w,h=r['region'];dx,dy=r['offset']
        out.extend(['',f'[sub_resource type="AtlasTexture" id="{frame_ids[name]}"]',f'atlas = ExtResource("{ids[r["atlas"]]}")',f'region = Rect2({x}, {y}, {w}, {h})',f'margin = Rect2({dx}, {dy}, {canvas["w"]-w}, {canvas["h"]-h})','filter_clip = true'])
    animations=[]
    for action,spec in manifest['anims'].items():
        fs=['{"duration": %s, "texture": SubResource("%s")}'%(format(ms,'.17g'),frame_ids[name]) for name,ms in zip(spec['frames'],spec['durations_ms'])]
        animations.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": 1000.0}'%(', '.join(fs),str(spec['loop']).lower(),action))
    out.extend(['','[resource]','animations = ['+',\n'.join(animations)+']',''])
    path.write_text('\n'.join(out))
