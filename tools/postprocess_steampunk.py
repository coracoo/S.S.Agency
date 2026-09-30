# -*- coding: utf-8 -*-
"""蒸汽朋克素材后处理:
1) 左下角 AI 生成水印区域 alpha 置 0(x < 25%宽 且 y > 88%高)
2) 按 alpha 通道裁剪到内容包围盒(留 2px padding)
3) 按类别缩放: UI 面板/卡框长边 512;按钮/图标/物体/效果 256
4) 覆盖保存,并输出最终尺寸表(供 UI_PATCH_MARGINS 计算)
"""
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "gen_steampunk_manifest.json")

# 面板类(九宫格拉伸)长边 512;其余 256
PANEL_FILES = {
    "ui_status_panel.png", "ui_info_panel.png", "ui_card_frame.png",
    "ui_tab_button_frame.png", "ui_bottom_hand_panel.png", "ui_banner_plaque.png",
    "title_emblem.png", "ui_menu_button.png",
}


def target_long_side(filename):
    return 512 if filename in PANEL_FILES else 256


def process(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    # 1) 左下角水印区域抹除
    wm_x = int(w * 0.25)
    wm_y = int(h * 0.88)
    for y in range(wm_y, h):
        for x in range(0, wm_x):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (r, g, b, 0)
    # 2) alpha 包围盒裁剪 + 2px padding
    alpha = im.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        print("[WARN] 全透明: %s" % path)
        return None
    l, t, r, b = bbox
    l = max(0, l - 2)
    t = max(0, t - 2)
    r = min(w, r + 2)
    b = min(h, b + 2)
    im = im.crop((l, t, r, b))
    # 3) 缩放(仅缩小)
    name = os.path.basename(path)
    target = target_long_side(name)
    w2, h2 = im.size
    long_side = max(w2, h2)
    if long_side > target:
        scale = target / long_side
        im = im.resize((max(1, round(w2 * scale)), max(1, round(h2 * scale))), Image.LANCZOS)
    im.save(path)
    return im.size


def main():
    with open(MANIFEST, encoding="utf-8") as f:
        entries = json.load(f)
    print("%-40s %s" % ("文件", "处理后尺寸"))
    for entry in entries:
        path = os.path.join(ROOT, entry["file"].replace("/", os.sep))
        if not os.path.exists(path):
            print("[MISS] %s" % entry["file"])
            continue
        size = process(path)
        print("%-40s %s" % (entry["file"], size))
    # 既有底部手牌面板也一并处理
    extra = os.path.join(ROOT, "assets", "ui", "steampunk", "ui_bottom_hand_panel.png")
    if os.path.exists(extra):
        size = process(extra)
        print("%-40s %s" % ("assets/ui/steampunk/ui_bottom_hand_panel.png", size))


if __name__ == "__main__":
    main()
