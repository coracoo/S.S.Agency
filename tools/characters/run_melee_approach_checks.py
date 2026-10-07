#!/usr/bin/env python3
"""近战闪身专用门禁；共享Godot锁、核验4.7.2与临时user://后测试真实节点。"""
from __future__ import annotations
import argparse
import fcntl
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--log', type=Path)
    parser.add_argument('--regression', action='store_true', help='同时跑现有视频时序/HP与倒地门禁')
    args = parser.parse_args()
    if args.log and args.log.resolve().is_relative_to(ROOT):
        parser.error('证据日志必须位于仓库外')
    logs: list[str] = []
    try:
        with (ROOT.parent / 'godot-import.lock').open('a') as lock, tempfile.TemporaryDirectory(prefix='ssa-melee-') as temporary:
            fcntl.flock(lock, fcntl.LOCK_EX)
            isolation = Path(temporary).resolve()
            env = os.environ.copy()
            for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA']:
                path = isolation / key
                path.mkdir()
                env[key] = str(path)
            env.update(RPG_TEST_ROOT=str(isolation), RPG_TEST_ISOLATED='0')
            def run(script: str) -> tuple[int,str]:
                timing = ['--fixed-fps','60']
                result = subprocess.run([args.godot,'--headless','--path',str(ROOT),*timing,'--script',script],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=300)
                print(result.stdout,end='',flush=True)
                logs.append(result.stdout)
                return result.returncode,result.stdout
            code,out = run('res://tools/rpg/test_environment.gd')
            paths = re.findall(r'^RPG_ISOLATION_OK:(.+)$',out,re.M)
            if code or ERROR.search(out) or 'Godot Engine v4.7.2.stable' not in out or len(paths)!=1 or Path(paths[0]).resolve()==isolation or not Path(paths[0]).resolve().is_relative_to(isolation):
                print('FAIL: 4.7.2/user://隔离核验失败')
                return 1
            env['RPG_TEST_ISOLATED']='1'
            scripts = [
                ('test_melee_return_dash.gd', r'MELEE_RETURN_DASH: \d+ assertions, 0 failures'),
                ('test_melee_production_gate.gd', r'MELEE_PRODUCTION_GATE: \d+ assertions, 0 failures'),
                ('test_melee_approach.gd', r'MELEE_APPROACH: \d+ assertions, 0 failures'),
            ]
            if args.regression:
                scripts += [
                    # 恢复后的正式替代覆盖；遗失的旧视频测试不伪称已运行。
                    ('test_recovered_action_timing.gd', r'RECOVERED_ACTION_TIMING: \d+ assertions, 0 failures'),
                    ('test_texture_contexts.gd', r'TEXTURE_CONTEXTS: \d+ assertions, 0 failures'),
                    ('test_expanded_actions.gd', r'EXPANDED_ACTIONS_RESULT: 0'),
                    ('test_registered_battle_actions.gd', r'REGISTERED_BATTLE_ACTIONS: \d+ assertions, 0 failures'),
                    ('test_lethal_status_impact.gd', r'LETHAL_STATUS_IMPACT_RESULT: 0'),
                    ('test_enemy_impact_hud.gd', r'ENEMY_IMPACT_HUD_RESULT: 0'),
                    ('test_battle_view_motion.gd', r'BATTLE_VIEW_MOTION: \d+ assertions, 0 failures'),
                ]
            failed = False
            for script, marker in scripts:
                code,out = run('res://tools/characters/' + script)
                failed |= bool(code or ERROR.search(out) or not re.search(marker,out))
            return int(failed)
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ''
        if isinstance(partial,bytes): partial = partial.decode('utf-8',errors='replace')
        logs.append(partial)
        logs.append('\nFAIL: 近战检查超时\n')
        print('FAIL: 近战检查超时')
        return 1
    finally:
        if args.log:
            args.log.parent.mkdir(parents=True,exist_ok=True)
            args.log.write_text(''.join(logs),encoding='utf-8')

if __name__ == '__main__': raise SystemExit(main())
