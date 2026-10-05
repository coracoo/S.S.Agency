#!/usr/bin/env python3
"""正式表现测试独立隔离user目录；可附加原始PNG/JSON的PCK装载验证。"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
PROJECT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN','godot'))
    parser.add_argument('--log', type=Path)
    parser.add_argument('--pack', type=Path)
    parser.add_argument('--dual', action='store_true')
    parser.add_argument('--height', action='store_true')
    parser.add_argument('--graphical', action='store_true')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    logs=[]
    with tempfile.TemporaryDirectory(prefix='ssa-campaign-presentation-') as directory:
        root=Path(directory).resolve(); env=os.environ.copy()
        for variable,name in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache'),('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
            path=root/name;path.mkdir();env[variable]=str(path)
        env.update(RPG_TEST_ROOT=str(root),RPG_TEST_ISOLATED='0')
        if args.output_dir:
            args.output_dir.resolve().mkdir(parents=True,exist_ok=True)
            env['CAMPAIGN_PRESENTATION_OUTPUT']=str(args.output_dir.resolve())
        def run(script,headless=True):
            command=[args.godot,*(['--headless'] if headless else ['--rendering-method','gl_compatibility','--audio-driver','Dummy']),'--path',str(PROJECT)]
            if args.pack: command+=['--main-pack',str(args.pack.resolve())]
            process=subprocess.run(command+['--script',script],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            print(process.stdout,end='',flush=True);logs.append(process.stdout)
            return process.returncode,process.stdout
        code,output=run('res://tools/rpg/test_environment.gd')
        verified=[line.split(':',1)[1] for line in output.splitlines() if line.startswith('RPG_ISOLATION_OK:')]
        if code or len(verified)!=1 or not Path(verified[0]).resolve().is_relative_to(root) or Path(verified[0]).resolve()==root:
            raise RuntimeError('实际user目录隔离核验失败，已阻止测试')
        env['RPG_TEST_ISOLATED']='1'
        code,output=run('res://tools/campaign/test_packed_assets.gd' if args.pack else ('res://tools/campaign/test_character_height.gd' if args.height else ('res://tools/campaign/test_dual_form_presentation.gd' if args.dual else 'res://tools/campaign/test_presentation.gd')),not args.graphical)
        if args.log: args.log.write_text(''.join(logs),encoding='utf-8')
        if code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):',output): return 1
    return 0
if __name__=='__main__': raise SystemExit(main())
