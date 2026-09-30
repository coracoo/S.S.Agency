# -*- coding: utf-8 -*-
"""行走遮罩生成工具：锚点折线 + 边缘吸附 → assets/bg/walkmasks/<stage_id>.png

遮罩为灰度图：白色=可行走面，顶缘=该列落脚高度（已含 stand_offset 站姿偏移）。
运行时 stage_scene._load_walk_mask 逐列取顶缘作 _ground_y，比 ground_profile
折线贴画——脚精确踩在画出来的石阶棱线/地板缝上。

原理：
  1. 锚点折线（人工按画定的粗略可行走面，全分辨率坐标）逐列插值出基准线；
  2. 在 ±snap_radius 窗口内找水平边缘最强（垂直梯度×水平高斯平滑）的行，
     加权偏好距锚点近的边缘，吸附过去——石阶棱线、地板压条都是强水平边缘；
  3. 站姿偏移（回廊等地板纵深大的场景，落脚点离远缘线往下站一点）；
  4. 中值滤波去毛刺后写遮罩 + 诊断图（绿线=最终落脚线，蓝点=锚点）。

用法：
  python tools/build_walk_masks.py            # 生成全部舞台遮罩 + 诊断图
  python tools/build_walk_masks.py honden_act # 只生成指定舞台
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- 舞台配置
# anchors: 全分辨率 [x, y]（y 向下），粗略即可，边缘吸附负责细部
STAGES = {
    "test_approach": {
        "bg": "assets/bg/approach/l2_test.png",
        # 复用之前手调剖面：平地 y=930，x=960 起上石阶
        "anchors": [[0, 930], [960, 930], [960, 896], [1055, 896], [1055, 862],
                    [1150, 862], [1150, 828], [1245, 828], [1245, 794],
                    [1340, 794], [1340, 760], [1435, 760], [1435, 726],
                    [1530, 726], [1530, 692], [1625, 692], [1625, 658],
                    [1720, 658], [1720, 624], [1815, 624], [1815, 590],
                    [1910, 590], [2048, 590]],
        "stand_offset": 0,
        "snap_radius": 26,
    },
    "corridor_act": {
        "bg": "assets/bg/corridor_walk.png",
        # 木地板远缘线：左起庭院水缘 → 走廊尽头消失点 → 右侧纸门墙脚线
        "anchors": [[0, 965], [293, 932], [600, 912], [819, 903], [1024, 852],
                    [1287, 735], [1390, 735], [1609, 808], [1829, 881],
                    [2048, 962]],
        "stand_offset": 120,  # 站在地板纵深中部，不贴远缘线
        "snap_radius": 26,
    },
    "honden_act": {
        "bg": "assets/bg/honden_dusk.png",
        # 前庭石板地 → 中央石阶（粗锚点，吸附锁棱线）→ 顶平台 → 沿侧翼下右庭
        "anchors": [[0, 968], [400, 972], [700, 975], [761, 990], [900, 950],
                    [1050, 890], [1200, 835], [1371, 780], [1480, 782],
                    [1520, 890], [1560, 985], [1700, 978], [2048, 978]],
        "stand_offset": 0,
        "snap_radius": 26,
    },
    "mountain_path": {
        "bg": "assets/bg/mountain_path/arch.png",
        # 山道：左下石板平地（远缘 y≈990）→ x≈1080 起石阶一路上行到右上平台
        "anchors": [[0, 990], [900, 990], [1080, 978], [1250, 810], [1450, 640],
                    [1650, 460], [1850, 310], [2048, 245]],
        "stand_offset": 0,
        "snap_radius": 30,
    },
}

OUT_DIR = "assets/bg/walkmasks"
DIAG_DIR = "docs/reference"


def anchor_line(anchors: list, w: int) -> np.ndarray:
    """锚点折线 → 每列基准 y"""
    xs = np.array([a[0] for a in anchors], dtype=np.float64)
    ys = np.array([a[1] for a in anchors], dtype=np.float64)
    grid = np.arange(w, dtype=np.float64)
    return np.interp(grid, xs, ys)


def edge_strength(img: np.ndarray) -> np.ndarray:
    """水平边缘强度：垂直梯度绝对值 × 水平高斯平滑（ consolidation 棱线）"""
    lum = img.astype(np.float64) @ np.array([0.299, 0.587, 0.114])
    grad = np.abs(np.gradient(lum, axis=0))
    # 水平高斯核（σ≈8，半宽 25）：石阶棱线横跨上百像素，压噪点
    k = np.exp(-(np.arange(-25, 26) / 8.0) ** 2)
    k /= k.sum()
    sm = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, grad)
    return sm


def build_ground_line(bg: np.ndarray, anchors: list, snap_radius: int,
                      stand_offset: float):
    """逐列：锚点基准 → ±snap_radius 窗口内吸附最强水平边缘 → +站姿偏移"""
    h, w, _ = bg.shape
    base = anchor_line(anchors, w)
    edges = edge_strength(bg)
    out = np.empty(w, dtype=np.float64)
    weak = 0
    for x in range(w):
        ay = base[x]
        y0 = max(0, int(ay) - snap_radius)
        y1 = min(h, int(ay) + snap_radius + 1)
        win = edges[y0:y1, x]
        if win.size == 0 or win.max() < 6.0:  # 无可靠边缘：退回锚点
            out[x] = ay
            weak += 1
            continue
        # 距离加权：越偏离锚点代价越大，防吸附到灯笼沿等干扰棱线
        rows = np.arange(y0, y1, dtype=np.float64)
        dist = np.abs(rows - ay)
        score = win / (1.0 + (dist / 10.0) ** 2)
        out[x] = rows[int(np.argmax(score))]
    # 中值滤波去毛刺（核 5），不抹平台阶沿（棱线宽 > 5 列）
    pad = np.pad(out, 2, mode="edge")
    med = np.median(np.stack([pad[i:i + w] for i in range(5)]), axis=0)
    ground = med + stand_offset
    return np.clip(ground, 0, h - 1), weak


def main() -> None:
    only = sys.argv[1] if len(sys.argv) > 1 else None
    os.makedirs(os.path.join(ROOT, OUT_DIR), exist_ok=True)
    for stage_id, cfg in STAGES.items():
        if only and stage_id != only:
            continue
        bg_path = os.path.join(ROOT, cfg["bg"])
        bg = np.array(Image.open(bg_path).convert("RGB"))
        h, w, _ = bg.shape
        ground, weak = build_ground_line(bg, cfg["anchors"],
                                         cfg["snap_radius"],
                                         float(cfg["stand_offset"]))
        # 遮罩：落脚线以下全白
        mask = np.zeros((h, w), dtype=np.uint8)
        for x in range(w):
            mask[int(ground[x]):, x] = 255
        out_path = os.path.join(ROOT, OUT_DIR, f"{stage_id}.png")
        Image.fromarray(mask, "L").save(out_path)
        # 诊断图：绿线=落脚线，蓝点=锚点
        diag = Image.open(bg_path).convert("RGB").resize(
            (1600, int(h * 1600 / w)), Image.LANCZOS)
        dr = ImageDraw.Draw(diag)
        sx = 1600.0 / w
        sy = diag.height / h
        for x in range(0, w, 4):
            gy = float(ground[x]) * sy
            dr.line([(x * sx, gy), ((x + 4) * sx, gy)], fill=(0, 255, 60),
                    width=2)
        for a in cfg["anchors"]:
            ax, ay = a[0] * sx, a[1] * sy
            dr.ellipse([ax - 4, ay - 4, ax + 4, ay + 4], fill=(60, 120, 255))
        diag_path = os.path.join(ROOT, DIAG_DIR, f"_walkmask_{stage_id}.jpg")
        diag.save(diag_path, quality=88)
        print(f"[{stage_id}] 遮罩 {out_path}  落脚线 y "
              f"{ground.min():.0f}~{ground.max():.0f}  弱边缘列 {weak}/{w}  "
              f"诊断 {diag_path}")


if __name__ == "__main__":
    main()
