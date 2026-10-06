#!/usr/bin/env python3
"""七章隔离验收：模型事务/真实合法指令，并明确区别于人工GUI通关。"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

PROJECT = Path(__file__).resolve().parents[2]
ENGINE_SCRIPT = PROJECT / 'tools/campaign/test_saga_state.gd'


def failed(code: int, text: str) -> bool:
    return bool(code or re.search(r'^\s*(?:SCRIPT ERROR|ERROR|FAIL|ASSERT FAIL):', text, re.M))


def verified_isolation(code: int, text: str, root: Path) -> bool:
    matches = re.findall(r'^RPG_ISOLATION_OK:(.*)$', text, re.M)
    if failed(code, text) or len(matches) != 1:
        return False
    actual = Path(matches[0].strip()).resolve()
    return actual != root.resolve() and actual.is_relative_to(root.resolve())


def scenarios(mode: str) -> list[dict]:
    result = []
    if mode in ('state', 'all'):
        result.append(dict(name='state-transactions', real=False, ending='', resolution='sendoff', clinic='gentle'))
    if mode in ('real', 'all'):
        for ending in ('dawn', 'vigil', 'shatter', 'eternal'):
            result.append(dict(name='sendoff-gentle-' + ending, real=True, ending=ending, resolution='sendoff', clinic='gentle'))
        result.append(dict(name='monitoring-isolate-dawn', real=True, ending='dawn', resolution='seal_monitoring', clinic='isolate', defer_seal=True))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--pack', type=Path)
    parser.add_argument('--mode', choices=('state', 'real', 'all'), default='all')
    parser.add_argument('--timeout', type=int, default=1200)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.is_relative_to(PROJECT):
        parser.error('证据必须放在仓库外')
    engine = shutil.which(args.godot)
    if not engine:
        parser.error('Godot不存在')
    pack = args.pack.resolve() if args.pack else None
    if pack and not pack.is_file():
        parser.error('发布PCK不存在')
    output.mkdir(parents=True, exist_ok=True)
    runtime = output / 'empty-runtime' if pack else PROJECT
    script = ENGINE_SCRIPT
    if pack:
        runtime.mkdir(exist_ok=True)
        if any(runtime.iterdir()):
            parser.error('包运行目录必须为空，禁止宿主资源回退')
        helper = output / 'external-test-tools'
        helper.mkdir(exist_ok=True)
        strategy = helper / 'saga_battle_strategy.gd'
        shutil.copyfile(PROJECT / 'tools/campaign/saga_battle_strategy.gd', strategy)
        script = helper / 'test_saga_state.gd'
        script.write_text(ENGINE_SCRIPT.read_text(encoding='utf-8').replace('res://tools/campaign/saga_battle_strategy.gd', strategy.as_posix()), encoding='utf-8')
    version_env = os.environ.copy()
    (output / 'engine-cache').mkdir(exist_ok=True)
    version_env['XDG_CACHE_HOME'] = str(output / 'engine-cache')
    version_output = subprocess.run([engine, '--headless', '--version'], env=version_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
    versions = re.findall(r'^\d+\.\d+(?:\.\d+)?\.[^\s]+$', version_output, re.M)
    version = versions[-1] if versions else version_output
    commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=PROJECT, text=True, stdout=subprocess.PIPE).stdout.strip()
    dirty = subprocess.run(['git', 'status', '--short'], cwd=PROJECT, text=True, stdout=subprocess.PIPE).stdout.splitlines()
    report = dict(status='running', kind='packed_real_campaign' if pack else 'source_campaign', manual_gui='not_run_by_this_runner', engine=version, source_commit=commit, dirty=dirty, pack=str(pack) if pack else None, mode=args.mode, started_utc=datetime.now(timezone.utc).isoformat(), runs=[])
    report_path = output / 'saga-verification.json'

    def save_report():
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')

    def invoke(env, arguments, log):
        command = [engine, '--headless', '--path', str(runtime), *(['--main-pack', str(pack)] if pack else []), *arguments]
        started = time.monotonic()
        try:
            completed = subprocess.run(command, env=env, text=True, encoding='utf-8', errors='replace', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout)
            code, text = completed.returncode, completed.stdout
        except subprocess.TimeoutExpired as exc:
            code = 124
            raw = exc.stdout or ''
            text = raw.decode('utf-8', errors='replace') if isinstance(raw, bytes) else raw
            text += '\nFAIL: 验收超时，结果未完成\n'
        log.write_text(text, encoding='utf-8')
        return code, text, round(time.monotonic() - started, 3)

    save_report()
    for case in scenarios(args.mode):
        directory = output / case['name']
        directory.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='ssa-seven-chapters-') as temporary:
            root = Path(temporary).resolve()
            env = os.environ.copy()
            for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
                (root / name).mkdir()
                env[key] = str(root / name)
            env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0', ACT_ONE_OUTPUT=str(directory), SAGA_SMOKE_ONLY='0', SAGA_REAL_BATTLES='1' if case['real'] else '0', SAGA_ENDING=case['ending'], SAGA_RESOLUTION=case['resolution'], SAGA_CLINIC_PLAN=case['clinic'], SAGA_DEFER_SEAL='1' if case.get('defer_seal', False) else '0')
            code, text, seconds = invoke(env, ['--script', str(PROJECT / 'tools/rpg/test_environment.gd')], directory / '00-isolation.log')
            if not verified_isolation(code, text, root):
                report['runs'].append(dict(name=case['name'], status='blocked', reason='actual user:// isolation not verified', seconds=seconds))
                report['status'] = 'fail'
                save_report()
                print('FAIL: ' + case['name'] + ' 隔离核验失败')
                return 1
            env['RPG_TEST_ISOLATED'] = '1'
            code, text, seconds = invoke(env, ['--script', script.as_posix()], directory / '10-campaign.log')
            routes = re.findall(r'^SAGA_ROUTE: (.*)$', text, re.M)
            battles = re.findall(r'^SAGA_REAL_BATTLE: (.*)$', text, re.M)
            broken = failed(code, text) or not routes or (case['real'] and len(battles) < 20)
            report['runs'].append(dict(name=case['name'], status='fail' if broken else 'pass', real_battles=case['real'], exit=code, seconds=seconds, routes=routes, battles=battles, log=str(directory / '10-campaign.log')))
            if case['real'] and not broken:
                checkpoints = sorted((directory / 'checkpoints').glob('*.json'))
                resumes = []
                if len(checkpoints) < 9:
                    broken = True
                    resumes.append(dict(status='fail', reason='missing cross-process checkpoints'))
                for checkpoint in checkpoints:
                    env['SAGA_RESUME_SNAPSHOT'] = str(checkpoint)
                    resume_log = directory / ('resume-' + checkpoint.stem + '.log')
                    resume_code, resume_text, resume_seconds = invoke(env, ['--script', str(PROJECT / 'tools/campaign/test_saga_process_resume.gd')], resume_log)
                    resume_failed = failed(resume_code, resume_text) or 'SAGA_PROCESS_RESUME:' not in resume_text
                    broken |= resume_failed
                    resumes.append(dict(checkpoint=checkpoint.name, status='fail' if resume_failed else 'pass', seconds=resume_seconds, log=str(resume_log)))
                report['runs'][-1]['process_resumes'] = resumes
                report['runs'][-1]['status'] = 'fail' if broken else 'pass'
            if broken:
                report['status'] = 'fail'
                print(text[-6000:])
            save_report()
            print(f"SAGA {case['name']}: {'FAIL' if broken else 'PASS'} ({seconds}s)", flush=True)
    if report['status'] != 'fail':
        report['status'] = 'pass'
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    save_report()
    return int(report['status'] != 'pass')


if __name__ == '__main__':
    raise SystemExit(main())
