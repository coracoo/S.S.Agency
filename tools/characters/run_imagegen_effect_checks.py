#!/usr/bin/env python3
"""生图技能清单/事件/真实BattleView门禁：委托统一隔离同锁入口并验证三个零失败标记。"""
import argparse,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CASES=[('test_action_attachments.gd','ACTION_ATTACHMENTS'),('test_imagegen_effect_manifest.gd','IMAGEGEN_EFFECT_MANIFEST'),('test_imagegen_battle_effects.gd','IMAGEGEN_BATTLE_EFFECTS'),('test_imagegen_battle_view.gd','IMAGEGEN_BATTLE_VIEW')]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default=os.environ.get('GODOT_BIN',str(ROOT.parent/'tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')))
    parser.add_argument('--log',type=Path,required=True)
    args=parser.parse_args()
    command=[sys.executable,str(ROOT/'tools/characters/run_runtime_recovery_checks.py'),'--godot',args.godot,'--log',str(args.log)]
    for name,_ in CASES:command+=['--script','tools/characters/'+name]
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
    print(result.stdout,end='');print(result.stderr,end='',file=sys.stderr)
    missing=[marker for _,marker in CASES if not re.search(marker+r': \d+ assertions, 0 failures',result.stdout)]
    if missing:print('FAIL: 缺少零失败标记：'+', '.join(missing))
    return int(result.returncode!=0 or bool(missing))
if __name__=='__main__':raise SystemExit(main())
