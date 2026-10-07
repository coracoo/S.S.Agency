#!/usr/bin/env python3
"""只读审计视频人物帧；指标是复核线索，不是自动美术批准或修图命令。

证据必须输出到仓库外。默认覆盖七形态全部运行帧及 build/libtv 下可发现的
历史抠图帧；不访问 .workbuddy、人物参考目录、CLI安装/凭据目录。
依赖：Pillow、NumPy、SciPy。无需 Godot、联网或视频生成。
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
FORMS = ('controller', 'guard', 'healer', 'homura_mage', 'homura_sword', 'mint', 'rinne')
STRUCTURE = np.ones((3, 3), dtype=bool)
LIMITATIONS = [
    '绿色/洋红优势不能区分真实服饰和背景污染；仅作为边缘候选，绿色内区另列。',
    '封闭透明区域可能是肢体间隙、道具镂空；小孔指标不能证明身体缺损。',
    '孤立连通块可能是飘带、合法粒子或武器；禁止据此自动删除全部非最大块。',
    '紧裁图框触边是正常打包现象；逻辑画布触边才是截裁风险，缺失源视频无法证明未截肢。',
    '面积/孔洞/残色的帧间跳变混有正常姿势、运动模糊和特效；未做光流，不能当纯抠图闪烁。',
    'RGB已去色或被预乘污染无法仅靠绿色优势找全；白/黑/棋盘背景目检仍必需。',
    '高alpha孔洞阈值、二维连通性与原生像素尺度相关；跨分辨率数值不可直接排名。',
    '运行清单无源视频映射时不得由相似帧名推断来源；历史候选与运行帧不自动等同。',
]


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def dump(path: Path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def validate_output(root: Path, output: Path):
    root, output = root.resolve(), output.resolve()
    if output == root or output.is_relative_to(root) or root.is_relative_to(output):
        raise ValueError('证据目录必须独立位于仓库外，不能是仓库或其祖先目录')


def resource_path(root: Path, uri: str) -> Path:
    if not uri.startswith('res://'):
        raise ValueError('运行图集必须使用 res://：' + uri)
    path = (root / uri[6:]).resolve()
    if not path.is_relative_to(root.resolve()) or '..' in Path(uri[6:]).parts:
        raise ValueError('运行图集路径越界')
    return path


def component_summary(mask, max_size=None):
    labels, count = ndi.label(mask, STRUCTURE)
    areas = np.bincount(labels.ravel())[1:]
    examples = []
    for label_index in np.argsort(areas)[::-1][:12]:
        area = int(areas[label_index])
        if max_size is not None and area > max_size:
            continue
        ys, xs = np.nonzero(labels == label_index + 1)
        examples.append({'pixels': area, 'bbox': [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]})
    return labels, areas, examples


def measure_frame(image: Image.Image, offset=(0, 0), canvas=None) -> dict:
    rgba = np.asarray(image.convert('RGBA'))
    a = rgba[..., 3]
    rgb = rgba[..., :3].astype(np.int16)
    visible = a >= 8
    solid = a >= 128
    edge = visible & (~ndi.binary_erosion(visible, STRUCTURE, iterations=2, border_value=0) | (a < 248))
    green = (rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])) > 12
    magenta = (np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]) > 12
    holes = ndi.binary_fill_holes(visible, structure=STRUCTURE) & ~visible
    _, hole_areas, hole_examples = component_summary(holes)
    labels, areas, _ = component_summary(visible)
    isolated = np.zeros_like(visible)
    small_component_count = 0
    if len(areas):
        main = int(areas.argmax()) + 1
        small_ids = np.flatnonzero(areas <= 8) + 1
        small_ids = small_ids[small_ids != main]
        small_component_count = len(small_ids)
        # 距主体至少3像素，减少将反走样断点直接当成漂浮噪点。
        isolated = np.isin(labels, small_ids) & ~ndi.binary_dilation(labels == main, STRUCTURE, iterations=2)
    _, _, speck_examples = component_summary(isolated)
    border = np.zeros_like(visible)
    border[0, :] = border[-1, :] = True
    border[:, 0] = border[:, -1] = True
    ox, oy = map(int, offset)
    canvas_border = np.zeros_like(visible)
    if canvas is not None:
        yy, xx = np.indices(a.shape)
        canvas_border = (xx + ox <= 0) | (yy + oy <= 0) | (xx + ox >= canvas[0] - 1) | (yy + oy >= canvas[1] - 1)
    ys, xs = np.nonzero(visible)
    alpha_area = float(a.astype(np.float64).sum() / 255)
    if alpha_area:
        centroid_y, centroid_x = ndi.center_of_mass(a)
        centroid = [float(centroid_x + ox), float(centroid_y + oy)]
    else:
        centroid = None
    edge_count = int(edge.sum())
    return {
        'size': list(image.size), 'offset': [ox, oy], 'empty': not bool(visible.any()),
        'visible_pixels': int(visible.sum()), 'solid_pixels': int(solid.sum()), 'alpha_area': round(alpha_area, 6),
        'centroid_canvas': centroid,
        'visible_bbox': [int(xs.min()), int(ys.min()), int(xs.max()+1), int(ys.max()+1)] if len(xs) else None,
        'soft_alpha_pixels': int(((a >= 8) & (a < 248)).sum()),
        'edge_pixels': edge_count, 'edge_green_pixels': int((edge & green).sum()),
        'edge_green_fraction': round(float((edge & green).sum()) / max(1, edge_count), 7),
        'edge_magenta_pixels': int((edge & magenta).sum()),
        'edge_magenta_fraction': round(float((edge & magenta).sum()) / max(1, edge_count), 7),
        'edge_green_alpha_mass': round(float(a[edge & green].sum()) / 255, 6),
        'opaque_interior_green_pixels': int((green & ~edge & solid).sum()),
        'hole_count': len(hole_areas), 'hole_pixels': int(hole_areas.sum()),
        'small_hole_count': int((hole_areas <= 64).sum()),
        'small_hole_pixels': int(hole_areas[hole_areas <= 64].sum()), 'hole_examples': hole_examples,
        'component_count': len(areas), 'small_component_count': int(small_component_count),
        'isolated_small_pixels': int(isolated.sum()), 'speck_examples': speck_examples,
        'crop_border_visible_pixels': int((border & visible).sum()),
        'crop_border_opaque_pixels': int((border & solid).sum()),
        'canvas_border_visible_pixels': int((canvas_border & visible).sum()),
    }


def temporal_pair(previous, current):
    a, b = previous['alpha_area'], current['alpha_area']
    p, q = previous['centroid_canvas'], current['centroid_canvas']
    return {
        'alpha_area_relative_change': round(abs(a - b) / max(a, b, 1), 7),
        'centroid_distance_px': round(float(np.linalg.norm(np.array(p) - q)), 4) if p is not None and q is not None else None,
        'small_hole_pixel_delta': current['small_hole_pixels'] - previous['small_hole_pixels'],
        'edge_green_fraction_delta': round(current['edge_green_fraction'] - previous['edge_green_fraction'], 7),
        'edge_magenta_fraction_delta': round(current['edge_magenta_fraction'] - previous['edge_magenta_fraction'], 7),
        'isolated_small_pixel_delta': current['isolated_small_pixels'] - previous['isolated_small_pixels'],
    }


def summary(records):
    values = list(records)
    return {
        'frames': len(values),
        'frames_with_edge_green': sum(v['edge_green_pixels'] > 0 for v in values),
        'frames_with_small_holes': sum(v['small_hole_pixels'] > 0 for v in values),
        'frames_with_isolated_small_pixels': sum(v['isolated_small_pixels'] > 0 for v in values),
        'frames_touching_crop': sum(v['crop_border_visible_pixels'] > 0 for v in values),
        'frames_touching_canvas': sum(v['canvas_border_visible_pixels'] > 0 for v in values),
        'empty_frames': sum(v['empty'] for v in values),
        'max_edge_green_fraction': max((v['edge_green_fraction'] for v in values), default=0),
        'max_edge_magenta_fraction': max((v['edge_magenta_fraction'] for v in values), default=0),
        'max_small_hole_pixels': max((v['small_hole_pixels'] for v in values), default=0),
        'max_isolated_small_pixels': max((v['isolated_small_pixels'] for v in values), default=0),
    }


def composite(image, size, background):
    if background == 'checker':
        yy, xx = np.indices((size[1], size[0]))
        base = np.where(((xx // 12 + yy // 12) % 2)[..., None], 96, 150).astype(np.uint8)
        dest = Image.fromarray(np.repeat(base, 3, axis=2)).convert('RGBA')
    else:
        dest = Image.new('RGBA', size, background)
    sprite = image.copy()
    sprite.thumbnail((size[0]-12, size[1]-12), Image.Resampling.LANCZOS)
    dest.alpha_composite(sprite, ((size[0]-sprite.width)//2, (size[1]-sprite.height)//2))
    return dest.convert('RGB')


def contact_sheet(rows, destination, tile=(180, 230)):
    """每行取首/中/末及三项最坏候选；标签给出精确帧名和复核指标。"""
    sheet = Image.new('RGB', (tile[0] * 6, (tile[1]+43) * len(rows)), '#22242a')
    draw = ImageDraw.Draw(sheet)
    for row_index, (action, frames, images, metrics) in enumerate(rows):
        if not frames:
            continue
        chosen = [frames[0], frames[len(frames)//2], frames[-1]]
        for metric in ('edge_green_fraction', 'small_hole_pixels', 'isolated_small_pixels'):
            chosen.append(max(frames, key=lambda name: metrics[name][metric]))
        for column, frame in enumerate(chosen):
            bg = ['checker', '#eeeeee', '#181c2b', '#181c2b', '#eeeeee', '#b565bd'][column]
            x, y = column*tile[0], row_index*(tile[1]+43)
            sheet.paste(composite(images[frame], tile, bg), (x, y))
            m = metrics[frame]
            draw.text((x+4, y+tile[1]+2), f'{action}: {frame}', fill='white')
            draw.text((x+4, y+tile[1]+17), f'G {m["edge_green_pixels"]} H {m["small_hole_pixels"]} S {m["isolated_small_pixels"]}', fill='white')
    sheet.save(destination)


def detail_sheet(image, metrics, label, destination):
    """保留原生像素尺寸，在三种底色上核验数字筛出的代表帧。"""
    tile = (max(image.width, 300)+20, max(image.height, 448)+20)
    sheet = Image.new('RGB', (tile[0]*3, tile[1]+40), '#22242a')
    for i, background in enumerate(('#181c2b', '#eeeeee', 'checker')):
        sheet.paste(composite(image, tile, background), (i*tile[0], 0))
    text = f'{label} native RGBA G={metrics["edge_green_pixels"]} M={metrics["edge_magenta_pixels"]} H={metrics["small_hole_pixels"]} S={metrics["isolated_small_pixels"]}'
    ImageDraw.Draw(sheet).text((5, tile[1]+5), text, fill='white')
    sheet.save(destination)


def audit_runtime(root: Path, output: Path):
    forms = []
    file_hashes = {}
    for form in FORMS:
        manifest_path = root / f'assets/chars/pixel/{form}/video_actions/manifest.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        file_hashes[str(manifest_path)] = sha(manifest_path)
        used = list(dict.fromkeys(n for action in manifest['anims'].values() for n in action['frames']))
        pages, frames, images, errors = {}, {}, {}, []
        canvas = (manifest['canvas']['w'], manifest['canvas']['h'])
        for name in used:
            spec = manifest['packed_frames'].get(name)
            if spec is None:
                errors.append({'frame': name, 'error': 'packed_frames缺失'})
                continue
            path = resource_path(root, spec['atlas'])
            if not path.exists():
                errors.append({'frame': name, 'error': '图集缺失', 'path': str(path)})
                continue
            if str(path) not in pages:
                with Image.open(path) as page:
                    pages[str(path)] = page.convert('RGBA')
                file_hashes[str(path)] = sha(path)
            page = pages[str(path)]
            x, y, width, height = spec['region']
            if min(x, y) < 0 or min(width, height) <= 0 or x+width > page.width or y+height > page.height:
                errors.append({'frame': name, 'error': '图集区域越界', 'region': spec['region']})
                continue
            sprite = page.crop((x, y, x+width, y+height))
            images[name] = sprite
            frames[name] = {**measure_frame(sprite, spec['offset'], canvas), 'frame': name,
                            'atlas_path': str(path), 'region': spec['region'],
                            'rgba_sha256': hashlib.sha256(sprite.tobytes()).hexdigest()}
        actions = {}
        rows = []
        for name, action in manifest['anims'].items():
            sequence = [n for n in action['frames'] if n in frames]
            pairs = []
            for i in range(1, len(sequence)):
                pairs.append({'from': sequence[i-1], 'to': sequence[i], 'index': i,
                              'duration_ms': action['durations_ms'][i-1], **temporal_pair(frames[sequence[i-1]], frames[sequence[i]])})
            closure = temporal_pair(frames[sequence[-1]], frames[sequence[0]]) if sequence and action.get('loop') else None
            actions[name] = {'sequence': sequence, 'declared_frames': len(action['frames']),
                             'unique_frames': len(set(sequence)), 'duration_ms': sum(action['durations_ms']),
                             'summary': summary(frames[n] for n in set(sequence)),
                             'pairs': pairs, 'loop_seam': closure,
                             'max_alpha_area_relative_change': max((p['alpha_area_relative_change'] for p in pairs), default=0)}
            rows.append((name, sequence, images, frames))
        contact_sheet(rows, output / f'{form}-contact.png')
        detailed = set(max(frames, key=lambda n: frames[n][key]) for key in
                       ('edge_green_fraction', 'edge_magenta_fraction', 'small_hole_pixels', 'isolated_small_pixels')) if frames else set()
        for name in sorted(detailed):
            detail_sheet(images[name], frames[name], f'{form}/{name}', output / f'detail-{form}-{name}.png')
        item = {'form': form, 'manifest_path': str(manifest_path), 'canvas': manifest['canvas'],
                'actions': actions, 'frames': frames, 'summary': summary(frames.values()),
                'atlas_count': len(pages), 'errors': errors,
                'unused_packed_records': sorted(set(manifest['packed_frames']) - set(used)),
                'source_video_mapping': '缺失：公开运行清单不保留源视频映射，不能从帧名猜测'}
        forms.append(item)
        dump(output / f'{form}-metrics.json', item)
        print(f'{form}: {len(actions)} actions, {len(frames)}/{len(used)} frames, {len(pages)} atlases', flush=True)
    return forms, file_hashes


def inventory_candidates(root: Path, output: Path, measure=True):
    base = root / 'build/libtv'
    groups = defaultdict(list)
    videos, manifests = [], []
    if base.exists():
        # 限于已知制作根；不跟随目录符号链接，不搜索用户参考及第三方CLI目录。
        for directory, dirs, files in __import__('os').walk(base, followlinks=False):
            dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('cli-install', 'reference', 'references')]
            folder = Path(directory)
            for filename in files:
                path = folder / filename
                if path.suffix.lower() in ('.mp4', '.webm', '.ogv'):
                    videos.append({'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)})
                elif filename in ('animation.json', 'manifest.json', 'qa.json'):
                    data = json.loads(path.read_text(encoding='utf-8'))
                    entry = {'path': str(path), 'sha256': sha(path), 'keys': list(data)}
                    for key in ('source', 'frame_count', 'source_frame_count', 'frame_pattern', 'has_alpha', 'model'):
                        if key in data:
                            entry[key] = data[key]
                    if isinstance(data.get('source'), str):
                        entry['declared_source_exists'] = (path.parent / data['source']).is_file()
                    manifests.append(entry)
                elif path.suffix.lower() == '.png':
                    groups[str(folder)].append(path)
    sequences = []
    for folder, paths in sorted(groups.items()):
        paths.sort()
        # 图像模式全部清点；仅 sprites 系列作为已抠图帧，原RGB抽帧不伪装透明QA。
        is_keyed = any(part.startswith('sprites') for part in Path(folder).parts)
        metrics, modes = {}, Counter()
        for path in paths:
            with Image.open(path) as image:
                modes[image.mode] += 1
                if is_keyed and measure:
                    result = measure_frame(image, canvas=image.size)
                    metrics[path.name] = {**result, 'path': str(path), 'sha256': sha(path), 'has_alpha_channel': 'A' in image.getbands()}
        record = {'directory': folder, 'file_count': len(paths), 'image_modes': dict(modes),
                  'first': paths[0].name, 'last': paths[-1].name, 'files': [p.name for p in paths],
                  'alpha_audited': is_keyed and measure, 'summary': summary(metrics.values()) if metrics else None,
                  'runtime_link': '未证明；不得将本候选视为正式运行帧来源'}
        if metrics:
            tag = Path(folder).relative_to(base).as_posix().replace('/', '__')
            dump(output / f'candidate-{tag}.json', {'directory': folder, 'frames': metrics, 'summary': record['summary']})
            selected = sorted(set([paths[0].name, paths[len(paths)//2].name, paths[-1].name] +
                                  [max(metrics, key=lambda n: metrics[n][k]) for k in ('edge_green_fraction', 'small_hole_pixels', 'isolated_small_pixels')]))
            imgs = {}
            for name in selected:
                with Image.open(Path(folder) / name) as image:
                    imgs[name] = image.convert('RGBA')
            contact_sheet([(Path(folder).name, selected, imgs, metrics)], output / f'candidate-{tag}-contact.png')
        sequences.append(record)
        if is_keyed:
            print(f'candidate: {folder}, {len(paths)} frames', flush=True)
    return {'scan_root': str(base), 'videos': videos, 'manifests': manifests, 'image_groups': sequences,
            'excluded': ['cli-install', '.libtv', 'reference', 'references', '.workbuddy', '人物参考未跟踪目录'],
            'missing_runtime_source_mapping_forms': list(FORMS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--skip-candidate-metrics', action='store_true')
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output_dir.resolve()
    validate_output(root, output)
    output.mkdir(parents=True, exist_ok=True)
    forms, protected = audit_runtime(root, output)
    inventory = inventory_candidates(root, output, not args.skip_candidate_metrics)
    dump(output / 'source-inventory.json', inventory)
    changed = [path for path, digest in protected.items() if sha(Path(path)) != digest]
    result = {'schema_version': 1, 'created_utc': datetime.now(timezone.utc).isoformat(),
              'tool_sha256': sha(Path(__file__)), 'python': sys.version, 'platform': platform.platform(),
              'root': str(root), 'output': str(output), 'forms': [{k: f[k] for k in ('form', 'summary', 'atlas_count', 'errors')} for f in forms],
              'coverage': {'forms': len(forms), 'actions': sum(len(f['actions']) for f in forms),
                           'unique_runtime_frames': sum(len(f['frames']) for f in forms),
                           'animation_frame_references': sum(a['declared_frames'] for f in forms for a in f['actions'].values()),
                           'runtime_atlases': sum(f['atlas_count'] for f in forms),
                           'candidate_alpha_frames': sum(g['file_count'] for g in inventory['image_groups'] if g['alpha_audited']),
                           'inventoried_video_files': len(inventory['videos']),
                           'inventoried_png_files': sum(g['file_count'] for g in inventory['image_groups'])},
              'protected_files_sha256': protected, 'changed_during_audit': changed, 'limitations': LIMITATIONS}
    dump(output / 'audit-summary.json', result)
    print(json.dumps(result['coverage'], ensure_ascii=False), flush=True)
    if changed or any(f['errors'] for f in forms):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
