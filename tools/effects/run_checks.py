"""先验证实际 user:// 隔离，再运行程序特效专项。"""
import os, re, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='ssa-effects-tests-') as tmp:
    env = os.environ.copy()
    for var in ('HOME','XDG_RUNTIME_DIR','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA'):
        p = Path(tmp)/var; p.mkdir(mode=0o700); env[var] = str(p)
    env['RPG_TEST_ROOT'] = tmp
    scripts = ['tools/rpg/test_environment.gd', 'tools/effects/test_parameters.gd']
    for script in scripts:
        r = subprocess.run(['godot','--headless','--path',str(ROOT),'--script','res://'+script],env=env,text=True,capture_output=True)
        output = r.stdout+r.stderr; print(output, end='')
        if r.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):',output): sys.exit(1)
        if script.endswith('test_environment.gd'):
            lines = [s.split(':',1)[1] for s in output.splitlines() if s.startswith('RPG_ISOLATION_OK:')]
            if len(lines)!=1 or not Path(lines[0]).resolve().is_relative_to(Path(tmp)): sys.exit('isolation failed')
            env['RPG_TEST_ISOLATED']='1'
