#!/usr/bin/env python3
"""视频人物图集的保守边缘处理实验：只读正式资源，只写仓库外候选。

只处理指定四组动作，保留图集 region/offset/画布和时长。候选不登记到游戏。
v1限制低alpha边，v2允许实体外边RGB去色但alpha全固定；拒绝全图压绿或侵蚀主体。
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

try:
    from audit_video_alpha import ROOT, dump, measure_frame, resource_path, sha, temporal_pair, validate_output
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from audit_video_alpha import ROOT, dump, measure_frame, resource_path, sha, temporal_pair, validate_output

STRUCTURE = np.ones((3, 3), dtype=bool)
SELECTIONS = {'guard': 'jump', 'healer': 'run', 'rinne': 'run', 'mint': 'item'}
CONFIG = {
    'visible_alpha': 8, 'maximum_color_alpha': 96, 'core_alpha': 128,
    'core_erosion_px': 2, 'outer_band_px': 2.1, 'maximum_core_distance_px': 6,
    'color_advantage': 24, 'relative_color_advantage': 32, 'reference_window_px': 13,
    'channel_change_limit': 64, 'strength': 0.65, 'target_advantage_margin': 8,
    'speck_max_pixels': 2, 'speck_max_alpha': 32, 'speck_core_distance_px': 4,
    'speck_neighbor_dilation_px': 2,
}


def refine_frame(image, *, protected=None, clean_specks=False, neighbors=None, profile='v1'):
    if profile not in ('v1', 'v2'):
        raise ValueError('未知处理方案')
    original = np.array(image.convert('RGBA'))
    result = original.copy()
    rgb = original[:, :, :3].astype(np.float32)
    alpha = original[:, :, 3]
    protected = np.zeros(alpha.shape, dtype=bool) if protected is None else np.asarray(protected, dtype=bool)
    if protected.shape != alpha.shape:
        raise ValueError('保护掩码尺寸不符')
    visible = alpha >= CONFIG['visible_alpha']
    # 填洞只用于确定外轮廓距离，绝不写回alpha；内部孔洞不会进入去色带。
    filled = ndi.binary_fill_holes(visible, structure=STRUCTURE)
    outer_distance = ndi.distance_transform_edt(np.pad(filled, 1))[1:-1, 1:-1]
    solid = alpha >= CONFIG['core_alpha']
    solid_filled = ndi.binary_fill_holes(solid, structure=STRUCTURE)
    solid_inner_distance = ndi.distance_transform_edt(np.pad(solid_filled, 1))[1:-1, 1:-1]
    solid_outer_distance = ndi.distance_transform_edt(~solid_filled)
    core = ndi.binary_erosion(solid, STRUCTURE, iterations=3 if profile == 'v2' else CONFIG['core_erosion_px'])
    band = np.zeros(alpha.shape, dtype=bool)
    green_mask = np.zeros(alpha.shape, dtype=bool)
    magenta_mask = np.zeros(alpha.shape, dtype=bool)
    removed = np.zeros(alpha.shape, dtype=bool)
    if core.any():
        distance_to_core, closest = ndi.distance_transform_edt(~core, return_indices=True)
        if profile == 'v2':
            # 实体轮廓内侧2px与外侧2px。内部镂空先填充，只排除内孔去色，不改alpha。
            band = (visible & (solid_inner_distance <= 2.1) & (solid_outer_distance <= 2.1) &
                    (distance_to_core <= 6) & ~protected)
        else:
            band = (visible & (outer_distance <= CONFIG['outer_band_px']) &
                    (alpha <= CONFIG['maximum_color_alpha']) &
                    (distance_to_core <= CONFIG['maximum_core_distance_px']) & ~protected)
        green = rgb[:, :, 1] - np.maximum(rgb[:, :, 0], rgb[:, :, 2])
        magenta = np.minimum(rgb[:, :, 0], rgb[:, :, 2]) - rgb[:, :, 1]
        # 用邻近实体区的最大色优势保护合法本色；没有可靠近邻则不处理。
        if profile == 'v2':
            # v1邻域最大值被强污染的边线占据；v2只取向内至少3px的最近实体参考。
            local_green = green[closest[0], closest[1]]
            local_magenta = magenta[closest[0], closest[1]]
        else:
            local_green = ndi.maximum_filter(np.where(core, green, -255), size=CONFIG['reference_window_px'])
            local_magenta = ndi.maximum_filter(np.where(core, magenta, -255), size=CONFIG['reference_window_px'])
        green_reference = np.maximum(local_green, 0)
        magenta_reference = np.maximum(local_magenta, 0)
        green_mask = (band & (local_green > -255) & (green > CONFIG['color_advantage']) &
                      (green-green_reference > CONFIG['relative_color_advantage']))
        magenta_mask = (band & (local_magenta > -255) & (magenta > CONFIG['color_advantage']) &
                        (magenta-magenta_reference > CONFIG['relative_color_advantage']))
        change = np.zeros_like(green)
        excess_green = np.minimum(CONFIG['channel_change_limit'], CONFIG['strength'] *
                                  (green-green_reference-CONFIG['target_advantage_margin']))
        excess_magenta = np.minimum(CONFIG['channel_change_limit'], CONFIG['strength'] *
                                    (magenta-magenta_reference-CONFIG['target_advantage_margin']))
        change[green_mask] = -excess_green[green_mask]
        change[magenta_mask] = excess_magenta[magenta_mask]
        result[:, :, 1] = np.clip(np.rint(rgb[:, :, 1]+change), 0, 255).astype(np.uint8)
        if profile == 'v1' and clean_specks and neighbors is not None and len(neighbors) == 2:
            if any(np.asarray(mask).shape != alpha.shape for mask in neighbors):
                raise ValueError('邻帧支持掩码尺寸不符')
            support = ndi.binary_dilation(np.asarray(neighbors[0]) | np.asarray(neighbors[1]), STRUCTURE,
                                          iterations=CONFIG['speck_neighbor_dilation_px'])
            # 连通块按所有非零alpha定义，防止只删除块中较亮部分留下新的锯齿。
            labels, count = ndi.label(alpha > 0, STRUCTURE)
            for label_index, region in enumerate(ndi.find_objects(labels), 1):
                if region is None:
                    continue
                block = labels[region] == label_index
                if int(block.sum()) > CONFIG['speck_max_pixels']:
                    continue
                if (int(alpha[region][block].max()) <= CONFIG['speck_max_alpha'] and
                    float(distance_to_core[region][block].min()) >= CONFIG['speck_core_distance_px'] and
                    not (protected[region][block].any() or support[region][block].any())):
                    removed[region] |= block
            result[:, :, 3][removed] = 0
    delta = np.abs(result.astype(np.int16)-original.astype(np.int16))
    audit_edge = visible & (~ndi.binary_erosion(visible, STRUCTURE, iterations=2) | (alpha < 248))
    def color_energy(pixels):
        colors = pixels[:, :, :3].astype(np.float64)
        a = pixels[:, :, 3].astype(np.float64) / 255
        g = np.maximum(0, colors[:, :, 1]-np.maximum(colors[:, :, 0], colors[:, :, 2])-12)
        m = np.maximum(0, np.minimum(colors[:, :, 0], colors[:, :, 2])-colors[:, :, 1]-12)
        return {'green': round(float((g*a)[audit_edge].sum()), 6), 'magenta': round(float((m*a)[audit_edge].sum()), 6)}
    stats = {
        'green_changed_pixels': int(green_mask.sum()), 'magenta_changed_pixels': int(magenta_mask.sum()),
        'rgb_changed_pixels': int((delta[:, :, :3].max(axis=2) > 0).sum()),
        'alpha_changed_pixels': int((delta[:, :, 3] > 0).sum()),
        'removed_alpha_mass': round(float(delta[:, :, 3].sum()) / 255, 7),
        'max_channel_change': int(delta[:, :, :3].max()),
        'protected_pixels_changed': int((delta.max(axis=2)[protected] > 0).sum()),
        'opaque_pixels_changed': int((delta.max(axis=2)[alpha >= 128] > 0).sum()),
        'interior_pixels_changed': int((delta[:, :, :3].max(axis=2)[~band] > 0).sum()),
        'alpha_only_reduced': bool(np.all(result[:, :, 3] <= alpha)),
        'solid_mask_unchanged': bool(np.array_equal(result[:, :, 3] >= 128, alpha >= 128)),
        'edge_color_energy_before': color_energy(original), 'edge_color_energy_after': color_energy(result),
    }
    return Image.fromarray(result), stats


def aligned_neighbor(mask_image, source_offset, target_offset, target_size):
    """将相邻帧按原逻辑画布偏移重合，仅用于极小点的时序保留判据。"""
    sx, sy = map(int, source_offset)
    tx, ty = map(int, target_offset)
    out = np.zeros((target_size[1], target_size[0]), dtype=bool)
    source = np.asarray(mask_image.getchannel('A')) >= 8
    left, top = max(sx, tx), max(sy, ty)
    right, bottom = min(sx+source.shape[1], tx+out.shape[1]), min(sy+source.shape[0], ty+out.shape[0])
    if right > left and bottom > top:
        out[top-ty:bottom-ty, left-tx:right-tx] = source[top-sy:bottom-sy, left-sx:right-sx]
    return out


def compare_panel(original, candidate, offset, bounds, name):
    left, top, right, bottom = bounds
    size = (right-left+12, bottom-top+12)
    panel = Image.new('RGB', (size[0]*4, size[1]+24), '#22242a')
    for i, (sprite, bg) in enumerate(((original, '#181c2b'), (candidate, '#181c2b'), (original, '#eeeeee'), (candidate, '#eeeeee'))):
        tile = Image.new('RGBA', size, bg)
        tile.alpha_composite(sprite, (int(offset[0])-left+6, int(offset[1])-top+6))
        panel.paste(tile.convert('RGB'), (i*size[0], 0))
    ImageDraw.Draw(panel).text((5, size[1]+4), name+' | original dark / candidate dark / original light / candidate light', fill='white')
    return panel


def build_candidates(root, output, clean_specks=True, profile='v1'):
    root, output = Path(root).resolve(), Path(output).resolve()
    validate_output(root, output)
    output.mkdir(parents=True, exist_ok=True)
    source_hashes, records = {}, []
    for form, action_name in SELECTIONS.items():
        manifest_path = root / f'assets/chars/pixel/{form}/video_actions/manifest.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        source_hashes[str(manifest_path)] = sha(manifest_path)
        action = manifest['anims'][action_name]
        names = action['frames']
        pages, original, candidates, per_frame = {}, {}, {}, {}
        for name in names:
            spec = manifest['packed_frames'][name]
            path = resource_path(root, spec['atlas'])
            if str(path) not in pages:
                with Image.open(path) as image:
                    pages[str(path)] = image.convert('RGBA')
                source_hashes[str(path)] = sha(path)
            x, y, w, h = spec['region']
            original[name] = pages[str(path)].crop((x, y, x+w, y+h))
        canvas = (manifest['canvas']['w'], manifest['canvas']['h'])
        for i, name in enumerate(names):
            spec = manifest['packed_frames'][name]
            image = original[name]
            protection = np.zeros((image.height, image.width), dtype=bool)
            protection_note = '无显式区域保护；按局部实体颜色保护'
            if form == 'mint':
                bbox = image.getchannel('A').point(lambda a: 255 if a >= 8 else 0).getbbox()
                # 审计已确认灰绿头发是合法本色；显式锁住上部35%，不靠指标下降冒险改色。
                if bbox:
                    protection[:int(bbox[1]+(bbox[3]-bbox[1])*.35)+1] = True
                protection_note = '灰绿头发保护：可见包围盒上部35%的整个区域字节不变'
            neighbors = None
            if 0 < i < len(names)-1 or action.get('loop'):
                prev_name, next_name = names[(i-1) % len(names)], names[(i+1) % len(names)]
                neighbors = tuple(aligned_neighbor(original[n], manifest['packed_frames'][n]['offset'], spec['offset'], image.size)
                                  for n in (prev_name, next_name))
            candidate, change = refine_frame(image, protected=protection, clean_specks=clean_specks, neighbors=neighbors, profile=profile)
            candidates[name] = candidate
            before = measure_frame(image, spec['offset'], canvas)
            after = measure_frame(candidate, spec['offset'], canvas)
            per_frame[name] = {'source': spec, 'source_atlas_sha256': source_hashes[str(resource_path(root, spec['atlas']))],
                               'source_rgba_sha256': hashlib.sha256(image.tobytes()).hexdigest(),
                               'candidate_rgba_sha256': hashlib.sha256(candidate.tobytes()).hexdigest(),
                               'protection': protection_note, 'change': change, 'before': before, 'after': after}
        candidate_pages = {path: page.copy() for path, page in pages.items()}
        for name, candidate in candidates.items():
            spec = manifest['packed_frames'][name]
            candidate_pages[str(resource_path(root, spec['atlas']))].paste(candidate, tuple(spec['region'][:2]))
        page_records = []
        form_output = output / form
        form_output.mkdir(exist_ok=True)
        for source, page in candidate_pages.items():
            target = form_output / Path(source).name
            page.save(target)
            page_records.append({'source': source, 'candidate': str(target), 'candidate_sha256': sha(target)})
        bounds = (min(manifest['packed_frames'][n]['offset'][0] for n in names),
                  min(manifest['packed_frames'][n]['offset'][1] for n in names),
                  max(manifest['packed_frames'][n]['offset'][0]+original[n].width for n in names),
                  max(manifest['packed_frames'][n]['offset'][1]+original[n].height for n in names))
        panels = [compare_panel(original[n], candidates[n], manifest['packed_frames'][n]['offset'], bounds, form+'/'+n) for n in names]
        # 无损APNG保留每帧；预览时长取整毫秒，JSON保留登记时长的完整精度。
        animation_path = output / f'{form}-{action_name}-comparison.png'
        panels[0].save(animation_path, save_all=True, append_images=panels[1:], duration=action['durations_ms'], loop=0, optimize=False)
        selected = sorted(set([0, len(names)//2, len(names)-1] +
                              [max(range(len(names)), key=lambda i: per_frame[names[i]]['change'][key])
                               for key in ('rgb_changed_pixels', 'alpha_changed_pixels')]))
        for index in selected:
            panels[index].save(output / f'compare-{form}-{names[index]}.png')
        worst_index = max(range(len(names)), key=lambda i: per_frame[names[i]]['change']['rgb_changed_pixels'])
        nearby = sorted({max(0, worst_index-1), worst_index, min(len(names)-1, worst_index+1)})
        strip = Image.new('RGB', (panels[0].width, panels[0].height*len(nearby)))
        for row, index in enumerate(nearby):
            strip.paste(panels[index], (0, row*panels[0].height))
        strip.save(output / f'temporal-{form}-{action_name}.png')
        pairs = []
        for i in range(1, len(names)):
            a, b = per_frame[names[i-1]], per_frame[names[i]]
            pairs.append({'from': names[i-1], 'to': names[i], 'duration_ms': action['durations_ms'][i-1],
                          'before': temporal_pair(a['before'], b['before']), 'after': temporal_pair(a['after'], b['after'])})
        record = {'form': form, 'action': action_name, 'manifest': str(manifest_path), 'canvas': manifest['canvas'],
                  'sequence': names, 'durations_ms': action['durations_ms'], 'loop': action.get('loop'),
                  'frames': per_frame, 'pages': page_records, 'pairs': pairs,
                  'review_status': '仅候选；数值及画面复核不自动批准生产接入'}
        dump(output / f'{form}-{action_name}-refinement.json', record)
        records.append(record)
        print(form, action_name, len(names), 'frames, RGB pixels', sum(f['change']['rgb_changed_pixels'] for f in per_frame.values()),
              'alpha pixels', sum(f['change']['alpha_changed_pixels'] for f in per_frame.values()), flush=True)
    changed_sources = [path for path, expected in source_hashes.items() if sha(Path(path)) != expected]
    violations = []
    for record in records:
        for name, frame in record['frames'].items():
            c = frame['change']
            if ((profile == 'v1' and c['opaque_pixels_changed']) or
                (profile == 'v2' and c['alpha_changed_pixels']) or
                c['interior_pixels_changed'] or c['protected_pixels_changed'] or not c['solid_mask_unchanged']):
                violations.append(record['form']+'/'+name)
    result = {'schema_version': 1, 'tool_sha256': sha(Path(__file__)), 'config': CONFIG,
              'profile': profile, 'v2_overrides': {'core_erosion_px': 3, 'maximum_color_alpha': 255,
                                                 'reference': 'nearest_core', 'alpha_changes_allowed': False},
              'clean_specks': clean_specks and profile == 'v1', 'source_hashes': source_hashes, 'changed_sources': changed_sources,
              'integrity_violations': violations, 'forms': list(SELECTIONS),
              'frames': sum(len(r['sequence']) for r in records), 'candidate_only': True,
              'rgb_changed_pixels': sum(f['change']['rgb_changed_pixels'] for r in records for f in r['frames'].values()),
              'alpha_changed_pixels': sum(f['change']['alpha_changed_pixels'] for r in records for f in r['frames'].values())}
    dump(output / 'refinement-summary.json', result)
    if changed_sources or violations:
        raise ValueError('原文件或实体／保护区完整性检查失败')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--no-speck-cleanup', action='store_true')
    parser.add_argument('--profile', choices=('v1', 'v2'), default='v1')
    args = parser.parse_args()
    result = build_candidates(args.root, args.output_dir, not args.no_speck_cleanup, args.profile)
    print(json.dumps({k: result[k] for k in ('frames', 'rgb_changed_pixels', 'alpha_changed_pixels', 'changed_sources', 'integrity_violations')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
