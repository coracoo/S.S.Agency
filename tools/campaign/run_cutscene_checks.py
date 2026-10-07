#!/usr/bin/env python3
"""仓库外生成技术视频，核验隔离user目录后测试本地过场；不写真实玩家档。"""
import argparse
import fcntl
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--import-lock', type=Path, default=PROJECT.parent / 'godot-import.lock')
    parser.add_argument('--graphical', action='store_true', help='在已有桌面中额外检查实际画面')
    parser.add_argument('--output-dir', type=Path, help='图形证据目录，必须在仓库外')
    args = parser.parse_args()
    if args.output_dir and args.output_dir.resolve().is_relative_to(PROJECT):
        parser.error('证据目录必须位于仓库外')
    with tempfile.TemporaryDirectory(prefix='ssa-cutscene-') as directory:
        root = Path(directory)
        fixture = root / 'fixture.ogv'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
                        'testsrc2=size=160x90:rate=12', '-f', 'lavfi', '-i',
                        'sine=frequency=440:sample_rate=44100', '-t', '1.5',
                        '-c:v', 'libtheora', '-q:v', '3', '-c:a', 'libvorbis', '-q:a', '2', str(fixture)], check=True)
        (root / 'bad.ogv').write_bytes(b'not a video file' * 5)
        (root / 'truncated.ogv').write_bytes(fixture.read_bytes()[:100])
        long_fixture = root / 'long.ogv'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
                        'testsrc2=size=160x90:rate=12', '-f', 'lavfi', '-i',
                        'sine=frequency=440:sample_rate=44100', '-t', '4', '-g:v', '12',
                        '-c:v', 'libtheora', '-q:v', '3', '-c:a', 'libvorbis', '-q:a', '2', str(long_fixture)], check=True)
        data = long_fixture.read_bytes()
        pages, position = [], 0
        while position < len(data):
            body = position + 27 + data[position + 26]
            end = body + sum(data[position + 27:body])
            pages.append((position, body, end, int.from_bytes(data[position + 14:position + 18], 'little'),
                          int.from_bytes(data[position + 18:position + 22], 'little'), data[position + 5]))
            position = end
        video_pages = [page for page in pages if page[3] == pages[0][3] and page[4] > 1]
        page = next(page for page in video_pages if not page[5] & 4)
        damaged = bytearray(data)
        damaged[page[1]:page[2]] = bytes(value ^ 255 for value in damaged[page[1]:page[2]])
        (root / 'damaged.ogv').write_bytes(damaged)
        (root / 'missing_page.ogv').write_bytes(data[:page[0]] + data[page[2]:])
        last = video_pages[-1]
        (root / 'missing_eos.ogv').write_bytes(data[:last[0]] + data[last[2]:])
        env = os.environ.copy()
        for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'),
                          ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'appdata'), ('LOCALAPPDATA', 'local')]:
            (root / name).mkdir()
            env[key] = str(root / name)
        env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED='0', CUTSCENE_TEST_FIXTURE=str(fixture))
        if args.graphical and args.output_dir:
            args.output_dir.resolve().mkdir(parents=True, exist_ok=True)
            env['CUTSCENE_TEST_OUTPUT'] = str(args.output_dir.resolve())
        def invoke(script, graphical=False, extra=()):
            graphics = ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '960x540'] if graphical else ['--headless']
            result = subprocess.run([args.godot, *graphics, '--path', str(PROJECT), '--script', script, *extra],
                                    env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
            print(result.stdout, end='', flush=True)
            return result
        with args.import_lock.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            verified = invoke('res://tools/rpg/test_environment.gd')
            paths = re.findall(r'^RPG_ISOLATION_OK:(.*)$', verified.stdout, re.M)
            if verified.returncode or len(paths) != 1 or not Path(paths[0]).resolve().is_relative_to(root) or Path(paths[0]).resolve() == root:
                raise RuntimeError('实际user目录隔离失败，未开始测试')
            env['RPG_TEST_ISOLATED'] = '1'
            result = invoke('res://tools/campaign/test_cutscene_playback.gd', args.graphical)
            if result.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', result.stdout):
                return 1
            slow = invoke('res://tools/campaign/test_cutscene_low_fps.gd', extra=['--max-fps', '3'])
            if slow.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', slow.stdout):
                return 1
            env['CUTSCENE_PACK_MODE'] = 'build'
            built = invoke('res://tools/campaign/test_cutscene_external_pack.gd')
            if built.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', built.stdout):
                return 1
            (root / 'cutscenes').mkdir()
            shutil.copyfile(fixture, root / 'cutscenes/night1_stone_bowl.ogv')
            env['CUTSCENE_PACK_MODE'] = 'check'
            for pack_path in [str(root / 'probe.pck'), './probe.pck']:
                packed = subprocess.run([args.godot, '--headless', '--main-pack', pack_path,
                                         '--script', str(PROJECT / 'tools/campaign/test_cutscene_external_pack.gd')],
                                        cwd=root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
                print(packed.stdout, end='', flush=True)
                if packed.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR|ERROR):', packed.stdout):
                    return 1
            return 0


if __name__ == '__main__':
    raise SystemExit(main())
