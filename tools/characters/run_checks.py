#!/usr/bin/env python3
"""先核验隔离 user://，再运行角色表现测试，绝不触碰玩家存档。"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', choices=['definition', 'animator', 'world', 'layers', 'roster', 'texture_sharing', 'scene_hook', 'high_detail_gallery', 'all'], default='all')
    parser.add_argument('--godot', default='godot')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ssa-characters-') as temporary:
        env = os.environ.copy()
        for key in ('XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME', 'APPDATA', 'LOCALAPPDATA'):
            path = Path(temporary) / key
            path.mkdir()
            env[key] = str(path)
        env['RPG_TEST_ROOT'] = temporary
        env['RPG_TEST_ISOLATED'] = '0'
        def run(script):
            # Phase coverage measures simulation frames, not synchronous PNG decode stalls.
            timing = ['--fixed-fps', '60'] if script.endswith('test_pixel_roster.gd') else []
            r = subprocess.run([args.godot, '--headless', *timing, '--path', str(ROOT), '--script', 'res://' + script],
                               env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            print(r.stdout, end='')
            return r
        r = run('tools/rpg/test_environment.gd')
        paths = re.findall(r'^RPG_ISOLATION_OK:(.+)$', r.stdout, re.M)
        if r.returncode or len(paths) != 1 or not Path(paths[0]).resolve().is_relative_to(Path(temporary).resolve()):
            return 1
        env['RPG_TEST_ISOLATED'] = '1'
        for suite in (['definition', 'animator', 'world', 'layers', 'roster', 'texture_sharing', 'scene_hook', 'high_detail_gallery'] if args.suite == 'all' else [args.suite]):
            r = run(f'tools/characters/test_pixel_{suite}.gd')
            if r.returncode or re.search(r'(^|\n)(SCRIPT ERROR|ERROR):', r.stdout):
                return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
