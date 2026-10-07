#!/usr/bin/env python3
"""原生第一夜候选世界动作，隔离user://和共享引擎锁；逐帧证据不是实时FPS。"""
from __future__ import annotations
import argparse,fcntl,hashlib,json,os,re,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT.parent
ERROR=re.compile(r'(^|\n)(?:SCRIPT ERROR|ERROR):')
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--check-only',action='store_true')
    parser.add_argument('--background-only',action='store_true',help='只顺路拍原场景无角色/无HUD画面，不重复动作录像')
    args=parser.parse_args();out=args.output.resolve();manifest=args.manifest.resolve()
    if out.is_relative_to(ROOT) or not manifest.is_relative_to(BASE):parser.error('候选/证据路径不合法')
    if not args.check_only and not os.environ.get('DISPLAY'):parser.error('需由原生桌面启动')
    out.mkdir(parents=True,exist_ok=True)
    if not args.check_only and (out/'capture.json').exists():parser.error('不覆盖已有原片')
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    status={'state':'starting','native':not args.check_only,'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}
    def publish():(out/'status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n')
    publish()
    with (BASE/'godot-import.lock').open('a') as lock,tempfile.TemporaryDirectory(prefix='ssa-native-world-') as temporary:
        fcntl.flock(lock,fcntl.LOCK_EX);isolated=Path(temporary).resolve();env=os.environ.copy()
        for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA']:
            folder=isolated/key;folder.mkdir();env[key]=str(folder)
        env.update(RPG_TEST_ROOT=str(isolated),RPG_TEST_ISOLATED='0',OMP_NUM_THREADS='4',OPENBLAS_NUM_THREADS='1',LP_NUM_THREADS='4')
        engine=str(BASE/'tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')
        result=subprocess.run([engine,'--headless','--path',str(ROOT),'--script','res://tools/rpg/test_environment.gd'],env=env,capture_output=True,text=True,timeout=60)
        text=result.stdout+result.stderr;(out/'isolation.log').write_text(text)
        match=re.findall(r'^RPG_ISOLATION_OK:(.+)$',text,re.M)
        if result.returncode or ERROR.search(text) or 'Godot Engine v4.7.2.stable' not in text or len(match)!=1 or Path(match[0]).resolve()==isolated or not Path(match[0]).resolve().is_relative_to(isolated):raise RuntimeError('实际版本/user隔离核验失败')
        env.update(RPG_TEST_ISOLATED='1',WORLD_REVISION_OUTPUT=str(out),WORLD_REVISION_MANIFEST=str(manifest),WORLD_REVISION_BACKGROUND_ONLY='1' if args.background_only else '0')
        resources={str(manifest):sha(manifest)};spec=json.loads(manifest.read_text())
        for record in spec['packed_frames'].values():
            path=ROOT/record['atlas'].removeprefix('res://');resources[str(path)]=sha(path)
        paths=['scripts/characters/pixel_character_world.gd','scripts/characters/pixel_character_animator.gd','scripts/characters/character_scene_integration.gd','scripts/exploration_3d/player_controller.gd','scripts/campaign/chapter_stage.gd','scripts/campaign/presentation/act_one_camera.gd','tools/characters/capture_world_revision.gd']
        for relative in paths:
            resources[str(ROOT/relative)]=sha(ROOT/relative);target=out/'source-snapshot'/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/relative,target)
        (out/'build-identity.json').write_text(json.dumps({'head':status['head'],'sha256':resources,'fixed_step_fps':30,'realtime_fps_claim':False},indent=2)+'\n')
        command=[engine,'--path',str(ROOT),'--script','res://tools/characters/capture_world_revision.gd']
        command+=['--headless','--check-only'] if args.check_only else ['--rendering-method','gl_compatibility','--audio-driver','Dummy','--resolution','1280x720','--fixed-fps','30']
        status['state']='checking' if args.check_only else 'capturing';publish();started=time.monotonic()
        with (out/'godot.log').open('w') as log:result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        text=(out/'godot.log').read_text();errors=[line for line in text.splitlines() if line.startswith(('SCRIPT ERROR:','ERROR:'))]
        unchanged=all(sha(path)==value for path,value in resources.items())
        status.update(exit_code=result.returncode,engine_errors=errors,source_unchanged=unchanged,wall_seconds=time.monotonic()-started)
        if not args.check_only and not args.background_only and (out/'capture.json').exists():
            mp4=out/'current_world.mp4'
            subprocess.run(['ffmpeg','-nostdin','-hide_banner','-loglevel','error','-framerate','30','-i',str(out/'frame_%05d.jpg'),'-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-threads','2','-movflags','+faststart',str(mp4)],check=True,timeout=120)
            status.update(mp4=str(mp4),sha256=sha(mp4))
        passed=result.returncode==0 and not errors and unchanged and (args.check_only or (out/'capture.json').exists())
        status['state']='complete' if passed else 'failed';publish();return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
