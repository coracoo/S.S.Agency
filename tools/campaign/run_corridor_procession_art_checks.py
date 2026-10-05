#!/usr/bin/env python3
"""先核验实际隔离user目录，再执行回廊/纸棺艺术模块契约。"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
PROJECT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--night', type=int, choices=(2, 3))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ssa-corridor-art-') as directory:
        root = Path(directory).resolve()
        env = os.environ.copy()
        for variable, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
            target = root / name
            target.mkdir()
            env[variable] = str(target)
        env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0', CAMPAIGN_ART_NIGHT=str(args.night or 0))
        def run(script):
            result = subprocess.run([args.godot, '--headless', '--path', str(PROJECT), '--script', script], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            print(result.stdout, end='', flush=True)
            return result.returncode, result.stdout
        code, output = run('res://tools/rpg/test_environment.gd')
        paths = [line.split(':', 1)[1].strip() for line in output.splitlines() if line.startswith('RPG_ISOLATION_OK:')]
        if code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output) or len(paths) != 1 or Path(paths[0]).resolve() == root or not Path(paths[0]).resolve().is_relative_to(root):
            print('FAIL: 实际user目录隔离核验失败；未启动艺术测试')
            return 1
        env['RPG_TEST_ISOLATED'] = '1'
        code, output = run('res://tools/campaign/test_corridor_procession_art.gd')
        return 1 if code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output) else 0


if __name__ == '__main__':
    raise SystemExit(main())
