#!/usr/bin/env python3
"""真4.7.2、临时user目录及共享导入锁下运行独立法术呈现回归。"""
import argparse
import fcntl
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--script', default='res://tools/characters/test_spell_effects.gd')
    parser.add_argument('--capture-dir', type=Path)
    args = parser.parse_args()
    version = subprocess.check_output([args.godot, '--version'], text=True, stderr=subprocess.DEVNULL).strip()
    if not version.startswith('4.7.2.stable'):
        raise RuntimeError(f'需要实际Godot4.7.2，收到{version}')
    print('VERIFIED_ENGINE:', version, flush=True)
    with tempfile.TemporaryDirectory(prefix='ssa-spell-fx-') as temporary:
        isolated = Path(temporary).resolve()
        env = os.environ.copy()
        for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'APPDATA', 'LOCALAPPDATA']:
            path = isolated / key
            path.mkdir()
            env[key] = str(path)
        env.update(RPG_TEST_ROOT=str(isolated), RPG_TEST_ISOLATED='0')
        base = [args.godot, '--path', str(ROOT)]
        with (ROOT.parent / 'godot-import.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run(base + ['--headless', '--script', 'res://tools/rpg/test_environment.gd'], env=env, capture_output=True, text=True, timeout=60)
            print(result.stdout + result.stderr, flush=True)
            found = re.findall(r'^RPG_ISOLATION_OK:(.+)$', result.stdout, re.M)
            if result.returncode or len(found) != 1 or Path(found[0]).resolve() == isolated or not Path(found[0]).resolve().is_relative_to(isolated):
                raise RuntimeError('user://隔离未核验')
            env['RPG_TEST_ISOLATED'] = '1'
            if args.capture_dir:
                output = args.capture_dir.resolve()
                if output.is_relative_to(ROOT):
                    parser.error('捕获证据须保存在仓库外')
                output.mkdir(parents=True, exist_ok=True)
                env['SPELL_FX_OUTPUT'] = str(output)
                launch = ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '960x640', '--fixed-fps', '24']
            else:
                launch = ['--headless']
            result = subprocess.run(base + launch + ['--script', args.script], env=env, capture_output=True, text=True, timeout=600)
            print(result.stdout + result.stderr, flush=True)
            if args.capture_dir:
                (output / 'godot.log').write_text(result.stdout + result.stderr)
            return int(bool(result.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', result.stdout + result.stderr)))

if __name__ == '__main__':
    raise SystemExit(main())
