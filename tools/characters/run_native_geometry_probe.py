#!/usr/bin/env python3
"""原生桌面单独启动：真实几何多次构造/释放，隔离user://、同锁、4CPU。"""
import fcntl,json,os,re,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT.parent

def main():
    if not os.environ.get('DISPLAY'):raise RuntimeError('需要原生桌面显示连接')
    out=BASE/'native-geometry-lifetime-probe';out.mkdir(exist_ok=False)
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    engine=BASE/'tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64'
    with (BASE/'godot-import.lock').open('a') as lock,tempfile.TemporaryDirectory(prefix='ssa-native-geometry-') as tmp:
        fcntl.flock(lock,fcntl.LOCK_EX)
        env=os.environ.copy();isolation=Path(tmp)
        for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA']:
            path=isolation/key;path.mkdir();env[key]=str(path)
        env.update(RPG_TEST_ROOT=tmp,RPG_TEST_ISOLATED='0',LP_NUM_THREADS='4',OMP_NUM_THREADS='4',GEOMETRY_PROBE_OUTPUT=str(out))
        check=subprocess.run([str(engine),'--headless','--path',str(ROOT),'--script','res://tools/rpg/test_environment.gd'],env=env,capture_output=True,text=True,timeout=60)
        text=check.stdout+check.stderr;(out/'isolation.log').write_text(text)
        found=re.findall(r'^RPG_ISOLATION_OK:(.+)$',text,re.M)
        if check.returncode or 'ERROR:' in text or 'Godot Engine v4.7.2.stable' not in text or len(found)!=1 or not Path(found[0]).resolve().is_relative_to(isolation):raise RuntimeError('隔离核验未通过')
        env['RPG_TEST_ISOLATED']='1'
        with (out/'godot.log').open('w') as log:
            result=subprocess.run([str(engine),'--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--fixed-fps','30','--script','res://tools/characters/probe_native_geometry_lifetime.gd'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        text=(out/'godot.log').read_text()
        report={'exit_code':result.returncode,'native_report_written':(out/'geometry.json').exists(),'errors':[line for line in text.splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:'))],'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}
        (out/'status.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        return int(result.returncode!=0 or bool(report['errors']))
if __name__=='__main__':raise SystemExit(main())
