# 动画/特效帧表后处理：去水印 → **轮廓抠图** → **精灵注册**（等高 + 脚区锚点对齐）
# 用法: python tools/postprocess_rinne_anims.py [--diag docs/reference/_check_reg.png]
#
# 背景：AI 生成的网格图不是标准精灵表——角色姿势经常画出格界（裙摆/刀光/飘带跨界），
# 任何「按格子硬切」的切法（含带余量切格+连通域过滤）都会把姿势劈断或吃进邻格残片。
# 正确做法是**按轮廓抠图**：全图连通域分析，每个角色是一个连通块，整块抠出、
# 与网格线无关；块按质心归属最近格，人物粘连（一块跨两格）时按格心 Voronoi 劈分。
# 注册管线（标准 sprite 做法）：
#   1) alpha 阈值化（清掉 <24 的水彩雾边，包围盒=真实剪影）
#   2) 等高归一：每帧按 最大剪影高/本帧剪影高 缩放——帧间身高一致
#   3) 脚区锚点：缩放后剪影底部 18% 脚区的横重心贴到统一画布固定轴——飘带刀剑再甩，脚是稳的
# 约定：角色帧表统一规格化为**面向右**（与我方一致），敌方由 _make_actor flip 镜像成面向左；
# 生成结果面向左的帧表在 JOBS 里标 flip=True（如纸人形待机）。
import os
import sys

import numpy as np
from PIL import Image

SRC = "assets/chars/anims"
FX_SRC = "assets/fx"
# (源表, 输出前缀, 列数, 行数, 是否镜像, 输出目录, 身高组)——按先行后列（从左到右、从上到下）读帧
# 身高组：同角色多张表（待机/走路/施法）共用一个基准剪影高，保证各动画播放时角色一样大；
# 不同角色/特效之间不共享（各自独立表则本表最高为准）。
JOBS = [
    ("_raw_rinne_idle_sheet.png", "rinne_idle_f", 4, 1, False, SRC, "rinne"),
    ("_raw_rinne_walk_sheet.png", "rinne_walk_f", 6, 1, False, SRC, "rinne"),
    ("_raw_rinne_cast_sheet.png", "rinne_cast_f", 5, 1, False, SRC, "rinne"),
    ("_raw_paperdoll_idle_sheet.png", "paperdoll_idle_f", 4, 1, True, SRC, "paperdoll"),  # 生成图面向左 → 镜像归一
    ("_raw_fire_burst_sheet.png", "fire_burst_f", 3, 2, False, FX_SRC, None),
    ("_raw_bell_wave_sheet.png", "bell_wave_f", 2, 2, False, FX_SRC, None),
    ("_raw_seal_burst_sheet.png", "seal_burst_f", 3, 2, False, FX_SRC, None),
]
# 「AI生成」水印固定在左下角：按图比例取左下 9%×8% 区域清纯白像素
WM_FRAC = (0.0, 0.92, 0.09, 1.0)
ALPHA_FLOOR = 24   # 低于此透明度视为水彩雾边 → 清零（包围盒才咬得住真实剪影）
PAD = 8            # 画布底部留白（防抗锯齿裁脚）


def clean_watermark(im: Image.Image) -> Image.Image:
    a = np.array(im)
    h, w = a.shape[:2]
    fx0, fy0, fx1, fy1 = WM_FRAC
    x0, y0, x1, y1 = int(w * fx0), int(h * fy0), int(w * fx1), int(h * fy1)
    box = a[y0:y1, x0:x1]
    rgb = box[..., :3].astype(int)
    white = (rgb[..., 0] > 210) & (rgb[..., 1] > 210) & (rgb[..., 2] > 210)
    box[..., 3] = np.where(white, 0, box[..., 3])
    a[y0:y1, x0:x1] = box
    return Image.fromarray(a)


def threshold_alpha(im: Image.Image) -> Image.Image:
    a = np.array(im)
    a[..., 3] = np.where(a[..., 3] < ALPHA_FLOOR, 0, a[..., 3])
    return Image.fromarray(a)


def register(frames, h_ref=None):
    """等高归一 + **脚区锚点**注册。返回 (注册后的帧列表, 逐帧诊断信息, 画布尺寸)。
    h_ref 传 None 时取本表最大剪影高；同角色多表调用方应传**组内共享**的 h_ref，
    保证待机/走路/施法各动画播放时角色一样大（用户复核：站立与运动角色尺寸不一）。
    横向锚点不用剪影包围盒中点（施法斩击/纸人飘带会把它带偏导致帧间横跳），
    改用剪影底部 18% 脚区的透明像素横重心——飘带刀剑再甩，脚区是稳的。"""
    infos = []
    prepped = []
    for f in frames:
        bbox = f.getbbox()
        if bbox is None:
            prepped.append(None)
            infos.append(None)
            continue
        prepped.append((f, bbox))
        infos.append({"bbox": bbox})
    valid = [p for p in prepped if p]
    if not valid:
        return [], infos, (0, 0)
    # 等高归一：以最大剪影高为基准（大小帧都拉到同一剪影高，帧间身高一致）
    if h_ref is None:
        h_ref = max(b[3] - b[1] for _f, b in valid)
    scaled = []
    for item in prepped:
        if item is None:
            scaled.append(None)
            continue
        f, b = item
        fh = b[3] - b[1]
        s = h_ref / float(fh)  # 等高归一：大小帧都拉到同一剪影高（帧间身高一致）
        nw, nh = max(1, round(f.width * s)), max(1, round(f.height * s))
        g = f.resize((nw, nh), Image.LANCZOS) if abs(s - 1.0) > 1e-3 else f
        gb = g.getbbox()
        scaled.append((g, gb, s))
        infos[len(scaled) - 1].update(scale=round(s, 4), h=fh)
    # 画布尺寸必须按**锚定后的实际伸展**计算：脚区重心为横向轴、底边为纵向轴，
    # 每帧相对轴的左右/上伸展取全集双倍加余量——曾按最大剪影宽算画布，
    # 居合突刺的刀尖/深鞠躬的头部横向远超半边宽，贴画布右缘被静默裁断。
    needs = []  # 与 scaled 对齐的 (foot_x, bottom)；None 占位
    for item in scaled:
        if item is None:
            needs.append(None)
            continue
        g, gb, s = item
        bottom = gb[3]
        band_top = max(gb[1], int(bottom - (bottom - gb[1]) * 0.18))
        a = np.array(g)[..., 3]
        band = a[band_top:bottom + 1, gb[0]:gb[2] + 1]
        cols = np.where(band > 0)[1]
        foot_x = gb[0] + float(np.mean(cols)) if cols.size else (gb[0] + gb[2]) / 2.0
        needs.append((foot_x, bottom))
    span = max(max(n[0] - (item[1][0]), item[1][2] - n[0]) for n, item in zip(needs, scaled) if n)
    top_span = max(n[1] - item[1][1] for n, item in zip(needs, scaled) if n)
    canvas_w = int(np.ceil(span)) * 2 + PAD * 2
    canvas_h = int(np.ceil(top_span)) + PAD * 2
    out_frames = []
    ax_x, ax_y = canvas_w / 2.0, canvas_h - PAD  # 脚区锚点（固定）
    for item, n in zip(scaled, needs):
        if item is None:
            out_frames.append(None)
            continue
        g, gb, s = item
        foot_x, bottom = n
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        canvas.alpha_composite(g, (round(ax_x - foot_x), round(ax_y - bottom)))
        out_frames.append(canvas)
        infos[len(out_frames) - 1].update(anchor=(round(ax_x - foot_x), round(ax_y - bottom)))
    return out_frames, infos, (canvas_w, canvas_h)


def crop_to_mask(a: np.ndarray, sel: np.ndarray):
    """按布尔掩码抠图：裁到掩码包围盒，掩码外 alpha 清零。无内容返回 None。"""
    ys, xs = np.where(sel)
    if ys.size == 0:
        return None
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    out = a[y0:y1, x0:x1].copy()
    out[..., 3] = np.where(sel[y0:y1, x0:x1], out[..., 3], 0)
    return Image.fromarray(out)


def extract_figures(im: Image.Image, cols: int, rows: int):
    """按轮廓抠图（不做任何网格硬切）：全图 8 连通域 → 碎屑过滤 →
    每块按质心归属最近格 → 整块抠出（跨界内容完整保留）。
    人物粘连（一块横跨多格）时按格心 Voronoi 把该块像素劈给各格。
    返回先行后列的帧列表（None=空格）。"""
    from scipy import ndimage
    a = np.array(im)
    mask = a[..., 3] > 8
    labels, n = ndimage.label(mask, structure=np.ones((3, 3)))
    h, w = mask.shape
    frames = [None] * (cols * rows)
    if n == 0:
        return frames
    sizes = np.bincount(labels.ravel())
    min_sz = max(64, int(sizes[1:].max() * 0.004))  # 去碎屑：过小连通块丢弃
    comps = {}
    for li in range(1, n + 1):
        if sizes[li] < min_sz:
            continue
        ys, xs = np.where(labels == li)
        comps[li] = (ys, xs)
    cw, ch = w / float(cols), h / float(rows)
    centers = [((c + 0.5) * cw, (r + 0.5) * ch) for r in range(rows) for c in range(cols)]
    owner = {}
    for li, (ys, xs) in comps.items():
        cy, cx = ys.mean(), xs.mean()
        owner[li] = min(range(len(centers)),
                        key=lambda i: (cy - centers[i][1]) ** 2 + (cx - centers[i][0]) ** 2)
    for k in range(len(centers)):
        lis = [li for li, kk in owner.items() if kk == k]
        if lis:
            frames[k] = crop_to_mask(a, np.isin(labels, lis))
    # 粘连补救：某格为空但其格心落在某连通块包围盒内 → 该块按格心 Voronoi 劈分
    for k in range(len(centers)):
        if frames[k] is not None:
            continue
        cx0, cy0 = centers[k]
        for li, (ys, xs) in comps.items():
            if not (xs.min() <= cx0 <= xs.max() and ys.min() <= cy0 <= ys.max()):
                continue
            k2 = owner[li]
            d1 = (xs - centers[k][0]) ** 2 + (ys - centers[k][1]) ** 2
            d2 = (xs - centers[k2][0]) ** 2 + (ys - centers[k2][1]) ** 2
            frames[k] = crop_to_mask(a, (labels == li) & _vor_mask(labels.shape, ys, xs, d1 < d2))
            rest = (labels == li) & _vor_mask(labels.shape, ys, xs, d1 >= d2)
            if np.any(rest):
                frames[k2] = crop_to_mask(a, rest)
            else:
                frames[k2] = None
            print("warn: 连通块#%d 横跨 %d/%d 两格，已按格心劈分" % (li, k, k2))
            break
    return frames


def _vor_mask(shape, ys, xs, take):
    """把 ys/xs 像素子集(take)展回全图布尔掩码。"""
    sel = np.zeros(shape, dtype=bool)
    sel[ys[take], xs[take]] = True
    return sel


def main() -> None:
    diag_path = None
    if "--diag" in sys.argv:
        diag_path = sys.argv[sys.argv.index("--diag") + 1]
    diag_tiles = []
    # 第一遍：全部抠图/阈值化/镜像，算出各身高组的共享基准（组内所有帧的最大剪影高）
    jobs = []
    group_h = {}
    for sheet_name, prefix, cols, rows, flip, outdir, group in JOBS:
        im = clean_watermark(Image.open(os.path.join(outdir, sheet_name)).convert("RGBA"))
        # 轮廓抠图（不硬切格），再阈值化咬边
        frames = [threshold_alpha(f) if f is not None else None
                  for f in extract_figures(im, cols, rows)]
        if flip:
            frames = [f.transpose(Image.FLIP_LEFT_RIGHT) if f is not None else None
                      for f in frames]
        jobs.append((prefix, frames, outdir, group))
        if group:
            for f in frames:
                if f is None:
                    continue
                b = f.getbbox()
                if b:
                    group_h[group] = max(group_h.get(group, 0), b[3] - b[1])
    # 第二遍：按共享基准注册输出
    for prefix, frames, outdir, group in jobs:
        reg, infos, csize = register(frames, h_ref=group_h.get(group))
        os.makedirs(outdir, exist_ok=True)
        for i, f in enumerate(reg, 1):
            if f is None:
                print("skip %s%d.png（空格）" % (prefix, i))
                continue
            f.save(os.path.join(outdir, "%s%d.png" % (prefix, i)), optimize=True)
        print("saved %s：%d 帧，注册画布 %s" % (prefix, len([f for f in reg if f]), csize))
        # 诊断条：全部帧叠在锚点网格上（肉眼直接看是否钉住）
        if diag_path:
            anchors = [tuple(infos[i]["anchor"]) for i in range(len(reg))
                       if infos[i] and "anchor" in infos[i]]
            tile = Image.new("RGBA", (csize[0] * len(anchors), csize[1] + 24), (40, 40, 48, 255))
            for i, f in enumerate([f for f in reg if f]):
                tile.alpha_composite(f, (i * csize[0], 12))
            diag_tiles.append((prefix, tile))
    if diag_path and diag_tiles:
        W = max(t.width for _n, t in diag_tiles)
        H = sum(t.height + 30 for _n, t in diag_tiles)
        sheet = Image.new("RGB", (W, H), (25, 25, 30))
        y = 0
        from PIL import ImageDraw
        d = ImageDraw.Draw(sheet)
        for name, t in diag_tiles:
            d.text((6, y + 4), name, fill=(120, 255, 140))
            sheet.paste(t.convert("RGB"), (0, y + 24))
            y += t.height + 30
        sheet.save(diag_path)
        print("saved 诊断图 %s" % diag_path)


if __name__ == "__main__":
    main()
