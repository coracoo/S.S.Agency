#!/usr/bin/env python3
"""隔离二夜正式stage景深探针；不写正式场景或玩家存档。"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[2]
LOCK = PROJECT.parent / 'ssa-campaign-evidence/godot-import.lock'


def measure_images(output):
    """比较实际输出像素，不把shader参数值当景深生效证据。"""
    import numpy as np
    from PIL import Image
    report = json.loads((output / 'probe-report.json').read_text())
    arrays = {name: np.asarray(Image.open(output / (name + '.png')).convert('RGB'), dtype=np.int16)
              for name in ('night2_off', 'night2_identity', 'night2_blur', 'probe_boards_off', 'probe_boards_blur')}

    def compare(a, b, box=None):
        difference = np.abs(arrays[a] - arrays[b])
        if box is not None:
            left, top, right, bottom = (int(round(v)) for v in box)
            difference = difference[max(0, top):min(1080, bottom), max(0, left):min(1920, right)]
        return {'mean_abs_8bit': float(difference.mean()), 'maximum_8bit': int(difference.max()),
                'changed_pixels': int(np.any(difference != 0, axis=-1).sum()), 'pixels': int(difference.shape[0] * difference.shape[1])}

    metrics = {'identity_vs_off': compare('night2_off', 'night2_identity'),
               'blur_vs_off': compare('night2_off', 'night2_blur'),
               'character_including_hair_weapon': compare('night2_off', 'night2_blur', report['regions']['character']),
               'top_ui': compare('night2_off', 'night2_blur', [0, 0, 1920, 150]),
               'near_probe': compare('probe_boards_off', 'probe_boards_blur', report['regions']['near']),
               'far_probe': compare('probe_boards_off', 'probe_boards_blur', report['regions']['far'])}
    depth_debug = np.asarray(Image.open(output / 'night2_depth.png').convert('RGB'))
    actual_difference = np.abs(arrays['night2_off'] - arrays['night2_blur'])
    for name, mask in {
        'actual_focus_depth_mask': (depth_debug[:, :, 1] > 250) & (depth_debug[:, :, 0] < 3) & (depth_debug[:, :, 2] < 3),
        'actual_near_depth_mask': (depth_debug[:, :, 0] > 30) & (depth_debug[:, :, 2] < 3),
        'actual_far_depth_mask': (depth_debug[:, :, 2] > 30) & (depth_debug[:, :, 0] < 3),
    }.items():
        values = actual_difference[mask]
        metrics[name] = {'pixels': int(mask.sum()), 'mean_abs_8bit': float(values.mean()) if values.size else None,
                         'maximum_8bit': int(values.max()) if values.size else None,
                         'changed_pixels': int(np.any(values != 0, axis=-1).sum()) if values.size else 0}
    metrics['required_checks'] = {
        'identity_is_exact_noop': metrics['identity_vs_off']['maximum_8bit'] == 0,
        'focus_character_is_exact': metrics['character_including_hair_weapon']['maximum_8bit'] == 0,
        'near_depth_blur_changes_pixels': metrics['near_probe']['mean_abs_8bit'] > 3.0,
        'far_depth_blur_changes_pixels': metrics['far_probe']['mean_abs_8bit'] > 3.0,
    }
    (output / 'pixel-metrics.json').write_text(json.dumps(metrics, ensure_ascii=False, indent=2) + '\n')
    print('HD2D_PIXELS:' + json.dumps(metrics, ensure_ascii=False), flush=True)
    return all(metrics['required_checks'].values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--snapshot-results', type=Path, required=True)
    parser.add_argument('--contract-only', action='store_true')
    parser.add_argument('--hd2d-asset', action='store_true', help='仅夹具临时替换二夜视觉层为已批准HD2D variant')
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    logs = []
    with LOCK.open('a') as lock, tempfile.TemporaryDirectory(prefix='ssa-hd2d-probe-') as directory:
        fcntl.flock(lock, fcntl.LOCK_EX)
        root = Path(directory).resolve()
        env = os.environ.copy()
        for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
            (root / name).mkdir()
            env[key] = str(root / name)
        env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0', HD2D_OUTPUT=str(output))
        env['HD2D_CONTRACT_ONLY'] = '1' if args.contract_only else '0'
        env['HD2D_VARIANT'] = '1' if args.hd2d_asset else '0'
        fixture = None
        for path in sorted(args.snapshot_results.glob('*-result.json')):
            result = json.loads(path.read_text())
            if result.get('status') == 'pass' and result.get('action') == 'advance_night' and result.get('after', {}).get('world', {}).get('night') == 2:
                fixture = {'source': str(path.resolve()), 'snapshot': result['after']}
                break
        if not fixture:
            raise RuntimeError('缺少已通过真实E2E的二夜快照')
        fixture_path = root / 'fixture.json'
        fixture_path.write_text(json.dumps(fixture, ensure_ascii=False))
        env['HD2D_FIXTURE'] = str(fixture_path)

        def run(script, graphical=False):
            command = [args.godot, *(['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '1920x1080'] if graphical else ['--headless']), '--path', str(PROJECT), '--script', script]
            result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
            print(result.stdout, end='', flush=True)
            logs.append(result.stdout)
            (output / 'probe.log').write_text(''.join(logs))
            return result

        verified = run('res://tools/rpg/test_environment.gd')
        paths = re.findall(r'^RPG_ISOLATION_OK:(.*)$', verified.stdout, re.M)
        if verified.returncode or len(paths) != 1 or not Path(paths[0]).resolve().is_relative_to(root) or Path(paths[0]).resolve() == root:
            raise RuntimeError('实际user路径隔离核验失败；未启动探针')
        env['RPG_TEST_ISOLATED'] = '1'
        result = run('res://tools/campaign/test_hd2d_probe.gd', not args.contract_only)
        failed = bool(result.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', result.stdout))
        if not failed and not args.contract_only:
            failed = not measure_images(output)
        return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
