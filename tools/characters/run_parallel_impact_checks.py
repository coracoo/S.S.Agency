#!/usr/bin/env python3
"""同M多目标与KO姿态门禁，保留单目标既有呈现合同；统一隔离/同锁入口。"""
import argparse,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CASES=[('test_parallel_impact_timing.gd',r'PARALLEL_IMPACT_TIMING: \d+ assertions, 0 failures'),('test_parallel_impact_boundaries.gd',r'PARALLEL_IMPACT_BOUNDARIES: \d+ assertions, 0 failures'),('test_deferred_defeat_pose.gd',r'DEFERRED_DEFEAT_POSE: \d+ assertions, 0 failures'),('test_enemy_impact_hud.gd',r'ENEMY_IMPACT_HUD_RESULT: 0')]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default=os.environ.get('GODOT_BIN',str(ROOT.parent/'tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')))
    parser.add_argument('--log',type=Path,required=True)
    args=parser.parse_args()
    command=[sys.executable,str(ROOT/'tools/characters/run_runtime_recovery_checks.py'),'--godot',args.godot,'--log',str(args.log)]
    for name,_ in CASES:command+=['--script','tools/characters/'+name]
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
    print(result.stdout,end='');print(result.stderr,end='',file=sys.stderr)
    missing=[name for name,pattern in CASES if not re.search(pattern,result.stdout)]
    if missing:print('FAIL: 缺少通过标记：'+', '.join(missing))
    return int(result.returncode!=0 or bool(missing))
if __name__=='__main__':raise SystemExit(main())
