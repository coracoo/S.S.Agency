"""恢复七套活动编辑器SpriteFrames毫秒时基；只替换权重与speed。"""
import argparse, hashlib, json, re
from pathlib import Path
from write_video_sprite_frames import write_sprite_frames

FORMS = ['rinne', 'mint', 'guard', 'homura_sword', 'homura_mage', 'healer', 'controller']
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()

def normalize(text):
    text = re.sub(r'"duration": [0-9.e+-]+', '"duration": WEIGHT', text)
    return re.sub(r'"speed": [0-9.e+-]+', '"speed": TIMEBASE', text)

def restore(repo, receipt):
    rows = []
    for form in FORMS:
        root = repo / 'assets/chars/pixel' / form / 'video_actions'
        manifest = root / 'manifest.json'
        provenance = root / 'provenance.json'
        target = root / f'{form}_sprite_frames.tres'
        before = target.read_text()
        original_sha = sha(target)
        protected = {str(p.relative_to(repo)): sha(p) for p in [manifest, provenance, *root.rglob('*.png'), *root.glob('frozen_20261006/*')] if p.is_file()}
        m = json.loads(manifest.read_text())
        candidate = target.with_suffix('.tres.pending')
        write_sprite_frames(m, candidate)
        after = candidate.read_text()
        if normalize(before) != normalize(after):
            raise ValueError('权重以外的编辑器资源数据发生变化：' + form)
        actual = [float(x) for x in re.findall(r'"duration": ([0-9.e+-]+)', after)]
        expected = [x for anim in m['anims'].values() for x in anim['durations_ms']]
        assert len(actual) == len(expected)
        assert all(abs(max(a, .01) - b) < 1e-9 for a,b in zip(actual,expected))
        assert all(float(x) == 1000 for x in re.findall(r'"speed": ([0-9.e+-]+)', after))
        candidate.replace(target)
        assert all(sha(repo / p) == digest for p,digest in protected.items())
        rows.append({'form':form,'active_tres':str(target.relative_to(repo)), 'previous_sha256':original_sha,'current_sha256':sha(target),'editor_frame_records':len(actual),'minimum_declared_frame_ms':min(expected),'protected_files':protected,'non_timing_tres_data_unchanged':True})
    result = {'status':'pass','timebase':1000,'native_fps_and_declared_durations_unchanged':True,'rows':rows,'changed_files':[x['active_tres'] for x in rows]}
    receipt.parent.mkdir(parents=True,exist_ok=True)
    receipt.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':'pass','editor_frame_records':sum(x['editor_frame_records'] for x in rows),'minimum_frame_ms':min(x['minimum_declared_frame_ms'] for x in rows),'changed_files':result['changed_files']}))

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[2]);p.add_argument('--receipt',type=Path,required=True);a=p.parse_args();restore(a.repo,a.receipt)
