#!/usr/bin/env python3
"""隔离用户目录后的第一幕真实物理检查。"""
import os, re, subprocess, tempfile
from pathlib import Path
PROJECT = Path(__file__).resolve().parents[2]
def main():
    with tempfile.TemporaryDirectory(prefix='ssa-act-one-physics-') as temporary:
        root = Path(temporary).resolve(); env = os.environ.copy()
        for variable in ('XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA'):
            path = root / variable.lower(); path.mkdir(); env[variable] = str(path)
        env.update(RPG_TEST_ROOT=str(root),RPG_TEST_ISOLATED='0')
        def run(script):
            result = subprocess.run([os.environ.get('GODOT_BIN','godot'),'--headless','--fixed-fps','60','--quit-after','20000','--path',str(PROJECT),'--script',script],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=300)
            print(result.stdout,end='',flush=True)
            return result
        result = run('res://tools/rpg/test_environment.gd')
        paths = re.findall(r'^RPG_ISOLATION_OK:(.*)$',result.stdout,re.M)
        if result.returncode or len(paths)!=1 or not Path(paths[0]).resolve().is_relative_to(root) or Path(paths[0]).resolve()==root:
            raise RuntimeError('隔离目录未通过，未运行物理测试')
        env['RPG_TEST_ISOLATED']='1'
        result=run('res://tools/campaign/test_act_one_geometry.gd')
        return int(bool('ACT ONE GEOMETRY:' not in result.stdout or result.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):',result.stdout)))
if __name__=='__main__':raise SystemExit(main())
