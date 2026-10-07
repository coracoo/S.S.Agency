#!/usr/bin/env python3
"""跳跃接地反馈回归：共享锁内先验证临时 user://，再运行真实控制器小图夹具。"""
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
    args = parser.parse_args()
    if args.log and args.log.resolve().is_relative_to(ROOT):
        parser.error('证据日志必须位于仓库外')
    logs = []
    try:
        with (ROOT.parent / 'godot-import.lock').open('a') as lock, tempfile.TemporaryDirectory(prefix='ssa-jump-contact-') as temporary:
            fcntl.flock(lock, fcntl.LOCK_EX)
            isolation = Path(temporary).resolve()
            env = os.environ.copy()
            for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA']:
                path = isolation / key; path.mkdir(); env[key] = str(path)
            env.update(RPG_TEST_ROOT=str(isolation), RPG_TEST_ISOLATED='0')
            def run(script: str) -> tuple[int,str]:
                result = subprocess.run([args.godot,'--headless','--path',str(ROOT),'--quit-after','900','--script',script],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
                print(result.stdout,end='',flush=True); logs.append(result.stdout)
                return result.returncode,result.stdout
            code,out = run('res://tools/rpg/test_environment.gd')
            paths = re.findall(r'^RPG_ISOLATION_OK:(.+)$',out,re.M)
            if code or ERROR.search(out) or len(paths)!=1 or Path(paths[0]).resolve()==isolation or not Path(paths[0]).resolve().is_relative_to(isolation):
                print('FAIL: user://隔离核验失败'); return 1
            env['RPG_TEST_ISOLATED']='1'
            scripts=['test_jump_contact_feedback.gd']
            for script in scripts:
                code,out = run('res://tools/characters/'+script)
                if code or ERROR.search(out) or not re.search(r'JUMP_CONTACT_FEEDBACK: \d+ assertions, 0 failures',out): return 1
            return 0
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ''
        if isinstance(partial, bytes): partial = partial.decode('utf-8', errors='replace')
        logs.append(partial); logs.append('\nFAIL: 跳跃反馈检查超时\n')
        print(partial, end=''); print('FAIL: 跳跃反馈检查超时'); return 1
    finally:
        if args.log:
            args.log.parent.mkdir(parents=True,exist_ok=True)
            args.log.write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__': raise SystemExit(main())
