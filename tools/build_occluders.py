# -*- coding: utf-8 -*-
"""遮挡体提取工具：从背景画抠出「人物应走在其后面」的中景物体 →
assets/bg/occluders/<stage_id>_o<N>.png（RGBA 裁剪到包围盒）+
data/occluders/<stage_id>.json（运行时装载清单）。

原理：抠出的遮挡体与背景同位置同缩放世界锁定（视差系数 1.0），运行时
按玩家脚点深度逐帧切换 visible——脚点在物体基线以上=走到物体后面(遮挡)，
否则玩家盖在物体上。切换无跳变：遮挡体像素与原画完全一致。

锚点多边形为全分辨率坐标，按画手调（docs/reference/_poly_*.png 参考）。

用法：python tools/build_occluders.py
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 多边形顶点（全分辨率，顺时针无所谓）+ base_y（该物体「地面接触线」，
# 玩家脚点 y < base_y 即判定为走到物体后方）
STAGES = {
    "test_approach": {
        "bg": "assets/bg/approach/l2_test.png",
        "items": [
            {"name": "planks", "base_y": 975, "poly":
                [(1305, 975), (1312, 715), (1345, 725), (1385, 745),
                 (1425, 758), (1428, 975)]},
            {"name": "pillar_stub", "base_y": 975, "poly":
                [(1375, 520), (1440, 520), (1440, 655), (1425, 700),
                 (1405, 688), (1390, 715), (1378, 688)]},
        ],
    },
    "honden_act": {
        "bg": "assets/bg/honden_dusk.png",
        "items": [
            {"name": "stair_cheek", "base_y": 1055, "poly":
                [(1420, 1060), (1445, 900), (1475, 825), (1505, 785),
                 (1545, 755), (1580, 740), (1582, 1060)]},
        ],
    },
}

OUT_DIR = "assets/bg/occluders"
MANIFEST_DIR = "data/occluders"
MARGIN = 6


def main() -> None:
    os.makedirs(os.path.join(ROOT, OUT_DIR), exist_ok=True)
    os.makedirs(os.path.join(ROOT, MANIFEST_DIR), exist_ok=True)
    for stage_id, cfg in STAGES.items():
        bg = Image.open(os.path.join(ROOT, cfg["bg"])).convert("RGBA")
        manifest = []
        diag = bg.copy()
        dr = ImageDraw.Draw(diag)
        for i, item in enumerate(cfg["items"]):
            poly = item["poly"]
            xs = [p[0] for p in poly]
            ys = [p[1] for p in poly]
            x0 = max(0, min(xs) - MARGIN)
            y0 = max(0, min(ys) - MARGIN)
            x1 = min(bg.width, max(xs) + MARGIN)
            y1 = min(bg.height, max(ys) + MARGIN)
            # 抠图：包围盒 + 多边形 alpha
            mask = Image.new("L", (x1 - x0, y1 - y0), 0)
            md = ImageDraw.Draw(mask)
            md.polygon([(x - x0, y - y0) for x, y in poly], fill=255)
            mask = mask.filter(__import__("PIL.ImageFilter", fromlist=["GaussianBlur"]
                                           ).GaussianBlur(1.2))  # 1px 羽化抗锯齿
            crop = bg.crop((x0, y0, x1, y1))
            crop.putalpha(mask)
            tex_name = f"{stage_id}_o{i}.png"
            crop.save(os.path.join(ROOT, OUT_DIR, tex_name))
            manifest.append({
                "tex": f"res://{OUT_DIR}/{tex_name}",
                "offset": [x0, y0],          # 裁剪原点（世界坐标）
                "base_y": float(item["base_y"]),
                "xmin": float(min(xs)),
                "xmax": float(max(xs)),
            })
            dr.line(poly + [poly[0]], fill=(0, 255, 60), width=3)
        mpath = os.path.join(ROOT, MANIFEST_DIR, f"{stage_id}.json")
        with open(mpath, "w", encoding="utf-8") as f:
            json.dump({"stage": stage_id, "occluders": manifest}, f,
                      ensure_ascii=False, indent=1)
        diag.convert("RGB").resize((1600, int(diag.height * 1600 / diag.width)),
                    Image.LANCZOS).save(
            os.path.join(ROOT, f"docs/reference/_occluder_{stage_id}.jpg"),
            quality=88)
        print(f"[{stage_id}] {len(manifest)} 个遮挡体 → {mpath}")


if __name__ == "__main__":
    main()
