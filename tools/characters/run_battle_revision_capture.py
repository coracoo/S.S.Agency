#!/usr/bin/env python3
"""从原生桌面启动；真实4.7.2/隔离user:///同锁/最多4CPU，生成带时间凭据的MP4。"""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT.parent
ERROR = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")
ACTIVE_OUTPUT = None

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    global ACTIVE_OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=BASE/'tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')
    parser.add_argument('--output',type=Path,default=BASE/'runtime-capture-current-20261007')
    parser.add_argument('--cases',default='guard:right,guard:left,homura_sword:right,homura_sword:left,homura_mage:right,guard:cancel')
    parser.add_argument('--imagegen-preview',action='store_true',help='明确预览已像素批准、游戏QA尚待完成的imagegen帧')
    parser.add_argument('--continue-shutdown-diagnostic',action='store_true',help='保留失败结论，只允许已知两张349524B退出纹理错误继续收集其它原生案例')
    parser.add_argument('--allow-unapproved-dash',action='store_true',help='仅显式诊断：可读取待QA的dash或复现旧静帧滑移')
    parser.add_argument('--manifest-override',action='append',default=[],metavar='FORM=PATH',help='只读候选manifest；仅在临时user目录重映射其atlas路径')
    args=parser.parse_args()
    out=args.output.resolve()
    ACTIVE_OUTPUT=out
    if out.is_relative_to(ROOT): parser.error('录像证据须放在仓库外')
    if not os.environ.get('DISPLAY'): parser.error('必须从已确认的原生桌面启动，不创建隐藏显示器')
    out.mkdir(parents=True,exist_ok=True)
    status={'state':'starting','native_display':True,'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'cases':[]}
    overrides={}
    for argument in args.manifest_override:
        form,path=argument.split('=',1); overrides[form]=Path(path).resolve()
        if not overrides[form].is_file() or not overrides[form].is_relative_to(BASE): parser.error('候选必须是本恢复工作区的现有manifest')
    def publish(): (out/'status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n')
    publish()
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    with (BASE/'godot-import.lock').open('a') as lock, tempfile.TemporaryDirectory(prefix='ssa-native-battle-') as tmp:
        fcntl.flock(lock,fcntl.LOCK_EX)
        env=os.environ.copy(); isolated=Path(tmp).resolve()
        for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA']:
            folder=isolated/key;folder.mkdir();env[key]=str(folder)
        env.update(RPG_TEST_ROOT=str(isolated),RPG_TEST_ISOLATED='0',OMP_NUM_THREADS='4',OPENBLAS_NUM_THREADS='1',LP_NUM_THREADS='4')
        engine=str(args.godot.resolve())
        check=subprocess.run([engine,'--headless','--path',str(ROOT),'--script','res://tools/rpg/test_environment.gd'],env=env,capture_output=True,text=True,timeout=60)
        text=check.stdout+check.stderr; (out/'isolation.log').write_text(text)
        found=re.findall(r'^RPG_ISOLATION_OK:(.+)$',text,re.M)
        if check.returncode or ERROR.search(text) or 'Godot Engine v4.7.2.stable' not in text or len(found)!=1 or not Path(found[0]).resolve().is_relative_to(isolated) or Path(found[0]).resolve()==isolated: raise RuntimeError('4.7.2/user://隔离核验失败')
        env['RPG_TEST_ISOLATED']='1'
        for case in args.cases.split(','):
            form,side=case.split(':'); case_name=side; cancel=side.startswith('cancel'); cancel_phase='return' if side=='cancel_return' else 'approach';side='right' if cancel else side
            directory=out/(form+'_'+case_name); directory.mkdir(exist_ok=False)
            manifest=overrides.get(form,ROOT/f'assets/chars/pixel/{form}/video_actions/manifest.json')
            if not manifest.is_file(): raise RuntimeError('活动manifest缺失：'+str(manifest))
            spec=json.loads(manifest.read_text())
            def label(path): return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)
            resources={label(manifest):digest(manifest)}
            for frame in spec.get('packed_frames',{}).values():
                page=ROOT/frame['atlas'].removeprefix('res://')
                if form in overrides:
                    prefix=f'res://assets/chars/pixel/{form}/video_actions/'
                    candidate=manifest.parent/frame['atlas'].removeprefix(prefix)
                    if frame['atlas'].startswith(prefix) and candidate.is_file(): page=candidate
                    frame['atlas']=str(page)
                if label(page) not in resources: resources[label(page)]=digest(page)
            loaded_manifest=manifest
            if form in overrides:
                loaded_manifest=isolated/(form+'-candidate.json')
                loaded_manifest.write_text(json.dumps(spec,ensure_ascii=False)+'\n')
            for relative in ['scripts/rpg/ui/battle_view.gd','scripts/rpg/ui/battle_world_backdrop.gd','scripts/rpg/ui/imagegen_battle_effects.gd','scripts/rpg/ui/imagegen_effect_manifest.gd','scripts/rpg/ui/hd_actor_view.gd','scripts/rpg/ui/hd_event_player.gd','scripts/characters/pixel_character_definition.gd','scripts/characters/action_attachment_points.gd','scripts/rpg/battle_engine.gd','tools/characters/capture_battle_revision.gd']:
                resources[relative]=digest(ROOT/relative)
            if args.imagegen_preview:
                for asset in (ROOT/'assets/effects/imagegen_spells').rglob('*'):
                    if asset.is_file() and asset.suffix in ['.png','.json']: resources[label(asset)]=digest(asset)
            identity={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'sha256':resources,'cpu_affinity':sorted(os.sched_getaffinity(0)),'fixed_step_fps':30,'realtime_fps_claim':False}
            (directory/'build-identity.json').write_text(json.dumps(identity,ensure_ascii=False,indent=2)+'\n')
            for relative in resources:
                if relative.startswith(('scripts/','tools/')):
                    target=directory/'source-snapshot'/relative;target.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copyfile(ROOT/relative,target)
            env.update(BATTLE_REVISION_IMAGEGEN_PREVIEW='1' if args.imagegen_preview else '0',BATTLE_REVISION_OUTPUT=str(directory),BATTLE_REVISION_FORM=form,BATTLE_REVISION_SIDE=side,BATTLE_REVISION_CANCEL='1' if cancel else '0',BATTLE_REVISION_CANCEL_PHASE=cancel_phase,BATTLE_REVISION_MANIFEST=str(loaded_manifest),BATTLE_REVISION_ALLOW_UNAPPROVED_DASH='1' if args.allow_unapproved_dash else '0')
            status.update(state='capturing',active=case);publish();start=time.monotonic()
            with (directory/'godot.log').open('w') as log:
                result=subprocess.run([engine,'--path',str(ROOT),'--rendering-method','gl_compatibility','--audio-driver','Dummy','--resolution','1280x720','--fixed-fps','30','--script','res://tools/characters/capture_battle_revision.gd'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=600)
            text=(directory/'godot.log').read_text()
            if not (directory/'capture.json').is_file(): raise RuntimeError('原生录制未完成：'+str(directory/'godot.log'))
            engine_errors=[line for line in text.splitlines() if line.startswith(('SCRIPT ERROR:','ERROR:'))]
            metadata=json.loads((directory/'capture.json').read_text())
            unchanged=all(digest(ROOT/path)==value for path,value in resources.items())
            if not unchanged: raise RuntimeError('录制期间来源发生改变：'+case)
            mp4=directory/'current_battle.mp4'
            subprocess.run(['ffmpeg','-nostdin','-hide_banner','-loglevel','error','-framerate','30','-i',str(directory/'frame_%05d.jpg'),'-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-threads','2','-movflags','+faststart',str(mp4)],check=True,timeout=120)
            receipt={'case':case,'mp4':str(mp4),'sha256':digest(mp4),'frames':metadata['captured_frames'],'recording_wall_seconds':round(time.monotonic()-start,3),'source_unchanged':unchanged,'home':metadata['returned_world_home'],'model_unchanged':metadata['model_unchanged_by_presentation'],'dash_available':metadata['battle_dash_available'],'engine_errors':engine_errors,'exit_code':result.returncode}
            status['cases'].append(receipt);status.update(state='case_complete');publish()
            known_shutdown = result.returncode == 0 and len(engine_errors) == 2 and all(re.fullmatch(r'ERROR: Texture with GL ID of \d+: leaked 349524 bytes\.', line) for line in engine_errors) and 'BATTLE_REVISION_CAPTURE:' in text
            if args.continue_shutdown_diagnostic and known_shutdown:
                status['cleanup_gate_failed'] = True
                publish()
                continue
            if result.returncode or engine_errors:
                status.update(state='failed',error='原生帧已保存供诊断；引擎错误使整体门禁失败，详见case日志。');publish()
                return 1
        status.update(state='complete_with_shutdown_diagnostics' if status.get('cleanup_gate_failed') else 'complete');publish()
    return 1 if status.get('cleanup_gate_failed') else 0

if __name__=='__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        if ACTIVE_OUTPUT is not None and (ACTIVE_OUTPUT/'status.json').exists():
            path=ACTIVE_OUTPUT/'status.json'; status=json.loads(path.read_text())
            status.update(state='failed',error=str(error))
            path.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n')
        raise
