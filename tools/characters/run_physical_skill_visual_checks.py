#!/usr/bin/env python3
"""最小副本内核验16形态合同/真实模型及旧caster；4.7.2、共享锁、先验user://。"""
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

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r'(^|\n)(?:SCRIPT ERROR|ERROR):')
CASES = (
    ('test_physical_skill_manifest_contract.gd', 'PHYSICAL_SKILL_MANIFEST_CONTRACT'),
    ('test_physical_skill_visual_event_policy.gd', 'PHYSICAL_SKILL_VISUAL_POLICY'),
    ('test_imagegen_effect_manifest.gd', 'IMAGEGEN_EFFECT_MANIFEST'),
    ('test_imagegen_variant_manifest.gd', 'IMAGEGEN_VARIANT_MANIFEST'),
    ('test_skill_visual_event_policy.gd', 'SKILL_VISUAL_EVENT_POLICY'),
    ('test_public_runtime_snapshot.gd', 'PUBLIC_RUNTIME_SNAPSHOT'),
)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--script', action='append', choices=[name for name, _ in CASES], help='仅运行指定聚焦检查；可重复')
    parser.add_argument('--godot', type=Path, default=ROOT.parent / 'tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')
    parser.add_argument('--output-dir', type=Path, default=ROOT.parent / 'physical-skill-contract-checks')
    args = parser.parse_args()
    repo, godot, output = args.repo.resolve(), args.godot.resolve(), args.output_dir.resolve()
    if output.is_relative_to(repo): parser.error('证据必须在仓库外')
    output.mkdir(parents=True, exist_ok=True)
    files = [*repo.glob('scripts/rpg/*.gd'), *repo.glob('data/rpg/*.json')]
    files = [p for p in files if p.stem not in ['campaign', 'save_store', 'encounter_router', 'replay']]
    files += [repo / ('tools/rpg/' + name) for name in ['fixtures.gd', 'test_engine.gd', 'test_environment.gd']]
    files += [repo / ('scripts/rpg/ui/' + name) for name in ['imagegen_effect_manifest.gd', 'skill_visual_event_policy.gd', 'physical_skill_visual_event_policy.gd']]
    files += [repo / ('scripts/characters/' + name) for name in ['pixel_character_definition.gd', 'legacy_asset_paths.gd']]
    files += [repo / ('tools/characters/' + name) for name, _ in CASES]
    files += [repo / 'assets/effects/imagegen_spells/registry.json']
    files += list(repo.glob('assets/effects/imagegen_spells/*/manifest.json'))
    files += list(repo.glob('assets/effects/imagegen_spells/*/*.png'))
    hashes = {str(p.relative_to(repo)): digest(p) for p in files}
    results = []
    with (repo.parent / 'godot-import.lock').open('a') as lock, tempfile.TemporaryDirectory(prefix='ssa-physical-contract-') as temporary:
        fcntl.flock(lock, fcntl.LOCK_EX)
        version = subprocess.check_output([str(godot), '--version'], text=True, stderr=subprocess.DEVNULL).strip()
        if not version.startswith('4.7.2.stable'): raise RuntimeError('不是指定Godot 4.7.2：' + version)
        root = Path(temporary).resolve()
        project = root / 'project'
        project.mkdir()
        for source in files:
            destination = project / source.relative_to(repo)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            if digest(destination) != hashes[str(source.relative_to(repo))]: raise RuntimeError('源文件在复制时变化：' + str(source))
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Physical skill contract isolated checks"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        env = os.environ.copy()
        for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'APPDATA', 'LOCALAPPDATA']:
            location = root / key
            location.mkdir()
            env[key] = str(location)
        env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0')
        base = [str(godot), '--headless', '--path', str(project)]
        probe = subprocess.run(base + ['--script', 'res://tools/rpg/test_environment.gd'], env=env, text=True, capture_output=True, timeout=60)
        log = probe.stdout + probe.stderr
        (output / 'isolation.log').write_text(log)
        print(log, flush=True)
        found = re.findall(r'^RPG_ISOLATION_OK:(.+)$', log, re.M)
        if probe.returncode or ERROR.search(log) or len(found) != 1 or Path(found[0]).resolve() == root or not Path(found[0]).resolve().is_relative_to(root):
            raise RuntimeError('真实user://隔离核验失败')
        env.update(RPG_TEST_ISOLATED='1', PHYSICAL_POLICY_OUTPUT=str(output), PHYSICAL_EFFECTS_ONLY='1', PUBLIC_RUNTIME_SNAPSHOT_PATH=str(output / 'runtime-effect-snapshot.json'))
        for name, marker in CASES:
            if args.script and name not in args.script: continue
            test = subprocess.run(base + ['--script', 'res://tools/characters/' + name], env=env, text=True, capture_output=True, timeout=120)
            log = test.stdout + test.stderr
            (output / (name.removesuffix('.gd') + '.log')).write_text(log)
            print(log, flush=True)
            matched = re.search(re.escape(marker) + r': (\d+) assertions, 0 failures', log)
            passed = not test.returncode and not ERROR.search(log) and bool(matched)
            results.append({'test': name, 'passed': passed, 'assertions': int(matched[1]) if matched else None})
        unchanged = all(digest(repo / path) == value for path, value in hashes.items())
        (output / 'source-hashes.json').write_text(json.dumps(hashes, ensure_ascii=False, indent=2) + '\n')
        (output / 'results.json').write_text(json.dumps({'engine':version, 'cases':results, 'source_unchanged':unchanged, 'rendering_qa':False}, ensure_ascii=False, indent=2) + '\n')
        return int(not unchanged or not all(case['passed'] for case in results))

if __name__ == '__main__':
    raise SystemExit(main())
