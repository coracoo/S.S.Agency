#!/usr/bin/env python3
"""隔离环境艺术/碰撞回归与正式stage截图；先核验引擎真实user路径。"""
import argparse
import os
import json
import hashlib
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[2]


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def capture_identity(nights):
    paths = {PROJECT / path for path in (
        'project.godot', 'scripts/campaign/chapter_geometry.gd',
        'scripts/campaign/chapter_stage.gd', 'scripts/campaign/chapter_catalog.gd',
        'scripts/exploration_3d/camera_rig.gd', 'scripts/exploration_3d/player_controller.gd',
        'scripts/characters/pixel_character_world.gd', 'scripts/characters/pixel_character_animator.gd',
        'assets/chars/pixel/rinne/high_detail_complete/manifest.json')}
    paths.update((PROJECT / 'scripts/campaign/presentation').rglob('*'))
    for night in nights:
        if str(night) == '1':
            paths.update((PROJECT / 'assets/3d/act01_approach').rglob('*'))
        else:
            paths.add(PROJECT / f'scripts/campaign/environments/night_{night}_art.gd')
            paths.add(PROJECT / f'scripts/campaign/environments/night_{night}_lighting.gd')
            for directory in (PROJECT / 'assets/3d').glob(f'night{int(night):02d}*'):
                paths.update(directory.rglob('*'))
    digests = {path.relative_to(PROJECT).as_posix(): sha256_file(path)
               for path in sorted(paths) if path.is_file() and not path.name.endswith('.import')}
    return {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=PROJECT, text=True).strip(),
            'dirty': subprocess.check_output(['git', 'status', '--porcelain=v1'], cwd=PROJECT, text=True),
            'sha256': digests}


def target_digest(hd2d_experiment):
    target = PROJECT / ('.dream-loop/hd2d/target.png' if hd2d_experiment else '.dream-loop/target.png')
    return sha256_file(target) if target.is_file() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--round-id', help='视觉迭代编号；记录在capture_metadata.json')
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--log', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--graphical', action='store_true')
    parser.add_argument('--lighting-ab', action='store_true', help='仅临时stage做二夜固定镜头三配置A/B，不改生产配置')
    parser.add_argument('--comparison', action='store_true', help='各夜左/中/右另存同默认镜头的无HUD对照图')
    parser.add_argument('--overview', action='store_true', help='另存第四/五夜拉远、无HUD的艺术全景检查图，非默认游玩镜头')
    parser.add_argument('--record-walk', action='store_true', help='图形检查时追加每夜约3秒真实角色移动JPEG序列')
    parser.add_argument('--hd2d-hud-click', action='store_true', help='真实图形夹具等待人工点击HD2D开/关后继续录制')
    parser.add_argument('--hd2d-experiment', action='store_true', help='仅二夜真实stage显式启用可逆HD2D试点并验证关闭恢复')
    parser.add_argument('--hd2d-profile', action='store_true', help='追加仅二夜可逆HD2D呈现检查')
    parser.add_argument('--hd2d-camera', action='store_true', help='追加仅二夜实验相机可逆性检查')
    parser.add_argument('--scene-flow', action='store_true', help='同一隔离目录内加跑既有正式stage运行回归')
    parser.add_argument('--nights', default='2,3,4,5')
    parser.add_argument('--snapshot-results', type=Path, help='已通过模型E2E结果目录，读取真实推进后的各夜快照')
    parser.add_argument('--record-baseline', type=Path, help='仅用于修改前记录旧碰撞，拒绝覆盖已有基线')
    args = parser.parse_args()
    logs = []
    identity_before = capture_identity(args.nights.split(',')) if args.graphical else None
    started_utc = datetime.now(timezone.utc).isoformat()
    with tempfile.TemporaryDirectory(prefix='ssa-environment-tests-') as directory:
        root = Path(directory).resolve()
        env = os.environ.copy()
        for variable, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
            path = root / name
            path.mkdir()
            env[variable] = str(path)
        env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0', CAMPAIGN_ENVIRONMENT_NIGHTS=args.nights)
        if args.hd2d_hud_click:
            if not args.hd2d_experiment:
                parser.error('--hd2d-hud-click需配合--hd2d-experiment')
            env['CAMPAIGN_HD2D_HUD_CLICK'] = '1'
        if args.hd2d_experiment:
            if not args.graphical or not args.output_dir or args.nights != '2':
                parser.error('--hd2d-experiment需要图形模式和仅二夜')
            env['CAMPAIGN_ENVIRONMENT_HD2D'] = '1'
        if args.lighting_ab:
            if not args.graphical or not args.output_dir or args.nights != '2':
                parser.error('--lighting-ab需要--graphical、--output-dir和--nights 2')
            env['CAMPAIGN_ENVIRONMENT_LIGHTING_AB'] = '1'
        if args.comparison:
            if not args.graphical or not args.output_dir:
                parser.error('--comparison需要--graphical和--output-dir')
            env['CAMPAIGN_ENVIRONMENT_COMPARISON'] = '1'
        if args.overview:
            if not args.graphical or not args.output_dir:
                parser.error('--overview需要--graphical和--output-dir')
            env['CAMPAIGN_ENVIRONMENT_OVERVIEW'] = '1'
        if args.record_walk:
            if not args.graphical or not args.output_dir:
                parser.error('--record-walk需要--graphical和--output-dir')
            env['CAMPAIGN_ENVIRONMENT_WALK'] = '1'
        if args.output_dir:
            args.output_dir.resolve().mkdir(parents=True, exist_ok=True)
            env['CAMPAIGN_ENVIRONMENT_OUTPUT'] = str(args.output_dir.resolve())
        if args.graphical:
            if not args.snapshot_results:
                parser.error('--graphical需要--snapshot-results提供已通过E2E快照')
            fixtures = {}
            for path in sorted(args.snapshot_results.glob('*-result.json')):
                result = json.loads(path.read_text(encoding='utf-8'))
                after = result.get('after', {})
                if result.get('status') == 'pass' and result.get('action') in ('start_new', 'advance_night') and after.get('world', {}).get('night'):
                    fixtures.setdefault(str(after['world']['night']), {'source': str(path.resolve()), 'snapshot': after})
            if not set(args.nights.split(',')).issubset(fixtures):
                parser.error('快照结果缺少请求夜晚')
            fixture_path = root / 'e2e-fixtures.json'
            fixture_path.write_text(json.dumps(fixtures, ensure_ascii=False), encoding='utf-8')
            env['CAMPAIGN_ENVIRONMENT_FIXTURES'] = str(fixture_path)
        if args.record_baseline:
            if args.record_baseline.exists():
                parser.error('基线已存在；不自动覆盖修改前证据')
            env['CAMPAIGN_ENVIRONMENT_RECORD'] = str(args.record_baseline.resolve())
        def run(script, graphical=False):
            command = [args.godot, *(['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '1920x1080'] if graphical else ['--headless']), '--path', str(PROJECT), '--script', script]
            result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
            print(result.stdout, end='', flush=True)
            logs.append(result.stdout)
            return result.returncode, result.stdout
        code, output = run('res://tools/rpg/test_environment.gd')
        verified = re.findall(r'^RPG_ISOLATION_OK:(.*)$', output, re.M)
        if code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output) or len(verified) != 1 or Path(verified[0]).resolve() == root or not Path(verified[0]).resolve().is_relative_to(root):
            raise RuntimeError('实际user目录隔离核验失败，未启动回归')
        env['RPG_TEST_ISOLATED'] = '1'
        code, output = run('res://tools/campaign/test_environment_art.gd', args.graphical)
        failed = bool(code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output))
        if args.hd2d_camera and not failed:
            code, output = run('res://tools/campaign/test_hd2d_camera.gd')
            failed |= bool(code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output))
        if args.hd2d_profile and not failed:
            code, output = run('res://tools/campaign/test_hd2d_profile.gd')
            failed |= bool(code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output))
        if args.scene_flow and not failed:
            code, output = run('res://tools/campaign/test_scene_flow.gd')
            failed |= bool(code or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', output))
        if args.graphical and args.output_dir:
            identity_after = capture_identity(args.nights.split(','))
            assets_stable = identity_before['sha256'] == identity_after['sha256']
            metadata = {'round_id': args.round_id or args.output_dir.name, 'started_utc': started_utc,
                        'finished_utc': datetime.now(timezone.utc).isoformat(), 'before': identity_before,
                        'after': identity_after, 'assets_stable_during_capture': assets_stable,
                        'fixed_idle': {'animation': 'idle', 'frame': 0, 'facing': 1, 'hair_clock': 0.0},
                        'target_sha256': target_digest(args.hd2d_experiment),
                        'hd2d_experiment': args.hd2d_experiment,
                        'lighting_ab_fixture_only': args.lighting_ab,
                        'render_report': 'render-report.json', 'status': 'fail' if failed or not assets_stable else 'pass'}
            (args.output_dir.resolve() / 'capture_metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            if not assets_stable:
                print('FAIL: 捕获期间相关场景/资产发生变化，请新建轮次重拍')
                failed = True
        if args.log:
            args.log.parent.mkdir(parents=True, exist_ok=True)
            args.log.write_text(''.join(logs), encoding='utf-8')
        return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
