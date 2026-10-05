#!/usr/bin/env python3
"""Run formal campaign checks only after verifying the actual isolated user:// path."""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('rpg_runner', PROJECT / 'tools/rpg/run_checks.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

def main():
    engine = shutil.which(os.environ.get('GODOT_BIN', 'godot'))
    if not engine:
        print('FAIL: Godot not found')
        return 1
    with tempfile.TemporaryDirectory(prefix='ssa-campaign-tests-') as directory:
        root = Path(directory).resolve()
        env = os.environ.copy()
        for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
            target = root / name
            target.mkdir()
            env[key] = str(target)
        env['RPG_TEST_ROOT'] = str(root)
        env['RPG_TEST_ISOLATED'] = '0'
        code, output = runner.run(engine, PROJECT, env, ['--script', 'res://tools/rpg/test_environment.gd'])
        verified = [line.split(':', 1)[1].strip() for line in output.splitlines() if line.startswith('RPG_ISOLATION_OK:')]
        if code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output) or len(verified) != 1 or Path(verified[0]).resolve() == root or not Path(verified[0]).resolve().is_relative_to(root):
            print('FAIL: actual user:// isolation not verified; no tests started')
            return 1
        env['RPG_TEST_ISOLATED'] = '1'
        failed = False
        for script in ['test_state.gd', 'test_dual_form.gd']:
            code, output = runner.run(engine, PROJECT, env, ['--script', 'res://tools/campaign/' + script])
            failed |= bool(code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output))
        return 1 if failed else 0

if __name__ == '__main__':
    sys.exit(main())
