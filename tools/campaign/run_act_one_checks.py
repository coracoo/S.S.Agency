#!/usr/bin/env python3
"""先验证真实隔离user目录，再执行连续地图测试或图形采集。"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--script', default='res://tools/campaign/test_act_one_stage.gd')
    parser.add_argument('--graphical', action='store_true')
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ssa-act-one-') as directory:
        root = Path(directory).resolve()
        env = os.environ.copy()
        for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
            (root / name).mkdir()
            env[key] = str(root / name)
        env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0')
        if args.output_dir:
            args.output_dir.resolve().mkdir(parents=True, exist_ok=True)
            env['ACT_ONE_OUTPUT'] = str(args.output_dir.resolve())
        common = [args.godot, '--path', str(PROJECT)]
        result = subprocess.run(common + ['--headless', '--script', 'res://tools/rpg/test_environment.gd'], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        print(result.stdout, end='', flush=True)
        paths = re.findall(r'^RPG_ISOLATION_OK:(.*)$', result.stdout, re.M)
        if result.returncode or len(paths) != 1 or not Path(paths[0]).resolve().is_relative_to(root) or Path(paths[0]).resolve() == root:
            raise RuntimeError('实际user目录隔离核验失败，未运行地图检查')
        env['RPG_TEST_ISOLATED'] = '1'
        graphics = ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '1920x1080'] if args.graphical else ['--headless']
        result = subprocess.run(common + graphics + ['--script', args.script], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1200)
        print(result.stdout, end='', flush=True)
        return int(bool(result.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', result.stdout)))
if __name__ == '__main__':
    raise SystemExit(main())
