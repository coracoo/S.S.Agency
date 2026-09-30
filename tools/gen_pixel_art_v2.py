"""
v2 像素美术资产 v2（替代之前的简单色块）
生成更精细的像素风资产：可辨识的角色 + 横版场景元素 + UI 装饰。
所有图形纯 Pillow 程序化绘制，无外部依赖。

风格：暗色调蒸汽道术风（黄铜/朱砂/铜绿），像素感（不用抗锯齿）。
"""
import os
from PIL import Image, ImageDraw

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(BASE, "assets", "v2")

# 蒸汽道术色板
COL = {
    "jet": (26, 26, 26, 255),
    "brass": (184, 134, 11, 255),
    "brass_light": (218, 165, 32, 255),
    "brass_dark": (120, 88, 8, 255),
    "cinnabar": (194, 59, 59, 255),
    "copper_green": (80, 160, 160, 255),
    "copper_dark": (40, 100, 100, 255),
    "steam_white": (232, 224, 208, 255),
    "ink_blue": (42, 92, 107, 255),
    "phosphor": (127, 255, 80, 255),
    "paper_yellow": (212, 175, 55, 255),
    "dark_purple": (107, 47, 160, 255),
    "shadow": (10, 8, 12, 200),
    "skin": (210, 175, 140, 255),
    "ground": (45, 30, 22, 255),
    "ground_light": (75, 55, 38, 255),
    "pipe": (60, 45, 30, 255),
    "pipe_light": (110, 80, 45, 255),
    "valve": (140, 90, 40, 255),
    "valve_light": (180, 130, 60, 255),
}


def px(img, x, y, color):
    """画单个像素"""
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def rect(img, x, y, w, h, color):
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def draw_player(path):
    """玩家：道袍角色（黄铜色），32×48 像素"""
    img = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
    # 头（skin 色，6×6）
    rect(img, 13, 4, 6, 6, COL["skin"])
    # 头发/帽子（黑色顶）
    rect(img, 12, 3, 8, 2, COL["jet"])
    # 眼睛（磷火绿点）
    px(img, 14, 7, COL["phosphor"])
    px(img, 17, 7, COL["phosphor"])
    # 身体（道袍，黄铜色梯形）
    rect(img, 11, 11, 10, 16, COL["brass"])
    rect(img, 10, 22, 12, 4, COL["brass_dark"])  # 下摆加宽
    # 道袍领口（朱砂红 V 字）
    rect(img, 15, 11, 2, 4, COL["cinnabar"])
    # 腰带（深色）
    rect(img, 10, 19, 12, 2, COL["jet"])
    # 腰带金属扣（黄铜亮色）
    rect(img, 15, 19, 2, 2, COL["brass_light"])
    # 手臂（两侧，黄铜色）
    rect(img, 8, 12, 3, 10, COL["brass_dark"])
    rect(img, 21, 12, 3, 10, COL["brass_dark"])
    # 手（skin 色）
    rect(img, 8, 22, 3, 2, COL["skin"])
    rect(img, 21, 22, 3, 2, COL["skin"])
    # 腿（黑色裤子）
    rect(img, 12, 26, 3, 12, COL["jet"])
    rect(img, 17, 26, 3, 12, COL["jet"])
    # 鞋（深棕）
    rect(img, 11, 38, 5, 3, COL["ground"])
    rect(img, 16, 38, 5, 3, COL["ground"])
    # 桃木剑背在身后（朱砂剑柄 + 木色剑身，斜挂在背部）
    for i in range(8):
        px(img, 22 + i // 2, 12 + i, COL["brass_dark"])
    rect(img, 22, 11, 2, 2, COL["cinnabar"])  # 剑柄红穗
    img.save(path)


def draw_enemy_jiangshi(path):
    """蒸汽僵尸：双臂前伸，铜绿色，32×48"""
    img = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
    # 头（青灰皮肤）
    rect(img, 13, 4, 6, 6, COL["copper_green"])
    # 道帽（黑色）
    rect(img, 12, 2, 8, 3, COL["jet"])
    # 僵尸眼（红色，没有瞳孔）
    rect(img, 14, 7, 1, 1, COL["cinnabar"])
    rect(img, 17, 7, 1, 1, COL["cinnabar"])
    # 嘴（朱砂牙缝）
    rect(img, 15, 9, 2, 1, COL["cinnabar"])
    # 身体（破道袍，铜绿色 + 黑色破口）
    rect(img, 10, 11, 12, 18, COL["copper_dark"])
    rect(img, 14, 14, 2, 3, COL["jet"])  # 破洞
    rect(img, 18, 20, 2, 2, COL["jet"])  # 破洞
    # 朱砂符纸贴额头（标志性）
    rect(img, 14, 3, 4, 2, COL["cinnabar"])
    # 双臂前伸（僵尸经典姿势）
    rect(img, 4, 13, 8, 3, COL["copper_green"])  # 左臂
    rect(img, 20, 13, 8, 3, COL["copper_green"])  # 右臂
    # 手（青灰）
    rect(img, 2, 13, 3, 3, COL["copper_green"])
    rect(img, 27, 13, 3, 3, COL["copper_green"])
    # 腿（僵直）
    rect(img, 12, 29, 3, 12, COL["jet"])
    rect(img, 17, 29, 3, 12, COL["jet"])
    # 鞋
    rect(img, 11, 41, 5, 3, COL["ground"])
    rect(img, 16, 41, 5, 3, COL["ground"])
    # 蒸汽阀（胸口，黄铜色机械装置）
    rect(img, 14, 16, 4, 4, COL["brass"])
    px(img, 16, 18, COL["brass_light"])
    img.save(path)


def draw_enemy_paper(path):
    """纸扎义体：黄纸色，32×48"""
    img = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
    # 头（黄纸）
    rect(img, 13, 4, 6, 6, COL["paper_yellow"])
    # 帽（黑色）
    rect(img, 12, 2, 8, 3, COL["jet"])
    # 眼（黑点）
    px(img, 14, 7, COL["jet"])
    px(img, 17, 7, COL["jet"])
    # 身体（纸扎服装，米黄色 + 黑色骨架线）
    rect(img, 10, 11, 12, 18, COL["paper_yellow"])
    # 竹骨架（黑色细线）
    rect(img, 15, 11, 2, 18, COL["jet"])  # 中柱
    rect(img, 10, 18, 12, 1, COL["jet"])  # 横梁
    # 手臂
    rect(img, 6, 12, 4, 12, COL["paper_yellow"])
    rect(img, 22, 12, 4, 12, COL["paper_yellow"])
    rect(img, 7, 12, 1, 12, COL["jet"])  # 骨架
    rect(img, 24, 12, 1, 12, COL["jet"])
    # 腿
    rect(img, 12, 29, 3, 12, COL["paper_yellow"])
    rect(img, 17, 29, 3, 12, COL["paper_yellow"])
    rect(img, 13, 29, 1, 12, COL["jet"])
    rect(img, 18, 29, 1, 12, COL["jet"])
    # 朱砂符
    rect(img, 14, 14, 4, 2, COL["cinnabar"])
    img.save(path)


def draw_npc_mechanist(path):
    """受伤机械师：灰色工装，32×48"""
    img = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
    # 头
    rect(img, 13, 4, 6, 6, COL["skin"])
    # 工程帽（黄铜色）
    rect(img, 11, 2, 10, 3, COL["brass_dark"])
    rect(img, 13, 1, 6, 2, COL["brass"])
    # 护目镜（黑色）
    rect(img, 13, 6, 6, 2, COL["jet"])
    px(img, 14, 7, COL["phosphor"])  # 镜片反光
    px(img, 17, 7, COL["phosphor"])
    # 嘴
    rect(img, 15, 9, 2, 1, COL["jet"])
    # 工装身体（灰色）
    rect(img, 10, 11, 12, 18, (90, 80, 70, 255))
    # 工装腰带（黑色 + 黄铜工具）
    rect(img, 10, 19, 12, 2, COL["jet"])
    rect(img, 13, 20, 2, 2, COL["brass"])  # 工具
    rect(img, 19, 20, 2, 2, COL["brass"])
    # 受伤绷带（白色，绑在手臂）
    rect(img, 6, 14, 4, 3, COL["steam_white"])
    rect(img, 6, 15, 4, 1, COL["cinnabar"])  # 渗血
    # 另一只手
    rect(img, 22, 12, 4, 12, (90, 80, 70, 255))
    # 腿（坐姿，短）
    rect(img, 12, 29, 8, 8, (60, 55, 50, 255))
    # 鞋
    rect(img, 11, 36, 10, 3, COL["ground"])
    img.save(path)


def draw_portal(path):
    """出口传送门：紫黑发光圆，32×48"""
    img = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 外圈（深紫，发光感）
    for r, alpha in [(14, 80), (12, 160), (10, 220), (8, 255)]:
        d.ellipse([16-r, 24-r, 16+r, 24+r], outline=(*COL["dark_purple"][:3], alpha))
    # 中心磷火绿渐变
    for r in range(7, 0, -1):
        a = int(255 * (1 - r / 8))
        d.ellipse([16-r, 24-r, 16+r, 24+r], fill=(*COL["phosphor"][:3], a // 2))
    img.save(path)


def draw_corridor_bg(path, w=2400, h=1024):
    """横版背景：蒸汽道观走廊（深色，有立柱/管道/地面）"""
    img = Image.new("RGBA", (w, h), COL["jet"])
    d = ImageDraw.Draw(img)
    # 上半部分天空/远景渐变（深紫到深褐）
    for y in range(0, 700):
        t = y / 700
        r = int(20 + t * 15)
        g = int(15 + t * 8)
        b = int(28 + t * 10)
        d.line([(0, y), (w, y)], fill=(r, g, b, 255))
    # 地面
    rect(img, 0, 700, w, 324, COL["ground"])
    # 地面高光（黄铜色边线）
    rect(img, 0, 700, w, 2, COL["brass_dark"])
    # 地面纹理（横向砖纹）
    for i in range(0, w, 80):
        rect(img, i, 720, 1, 280, COL["ground_light"])
    for j in range(740, 1024, 40):
        rect(img, 0, j, w, 1, (35, 22, 16, 255))
    # 远处管道/立柱（每隔 300px 一根）
    for i in range(8):
        x = 200 + i * 300
        # 立柱主体（深色管道）
        rect(img, x - 30, 200, 60, 500, COL["pipe"])
        # 立柱顶部装饰（黄铜色帽）
        rect(img, x - 35, 200, 70, 15, COL["brass_dark"])
        rect(img, x - 35, 200, 70, 3, COL["brass"])
        # 立柱高光（左侧亮色）
        rect(img, x - 30, 215, 4, 485, COL["pipe_light"])
        # 阀门（圆形，黄铜色，在立柱中间）
        d.ellipse([x - 16, 380, x + 16, 412], fill=COL["valve"])
        d.ellipse([x - 10, 386, x + 10, 406], fill=COL["valve_light"])
        # 阀门十字开关
        d.line([(x - 14, 396), (x + 14, 396)], fill=COL["jet"], width=2)
        d.line([(x, 382), (x, 410)], fill=COL["jet"], width=2)
        # 蒸汽喷口（阀门上方冒蒸汽，白色斑点）
        for sy in range(360, 340, -3):
            for sx_off in [-4, 0, 4]:
                px(img, x + sx_off, sy + (sx_off % 2), (200, 195, 180, 80))
    # 顶部蒸汽雾（白色低 alpha）
    mist = Image.new("RGBA", (w, 200), (0, 0, 0, 0))
    md = ImageDraw.Draw(mist)
    import random
    random.seed(42)
    for _ in range(80):
        x = random.randint(0, w)
        y = random.randint(0, 200)
        r = random.randint(30, 80)
        md.ellipse([x - r, y - r, x + r, y + r], fill=(232, 224, 208, 25))
    img.paste(mist, (0, 0), mist)
    # 远处灯笼（朱砂色小圆，挂在立柱旁）
    for i in range(8):
        x = 200 + i * 300
        d.ellipse([x + 40, 240, x + 56, 256], fill=COL["cinnabar"])
        d.line([(x + 48, 200), (x + 48, 240)], fill=(80, 60, 40, 255), width=1)
    img.save(path)


def draw_portrait_pixel(path, draw_func, scale=8):
    """从 32×48 像素角色放大成立绘（用 nearest neighbor）"""
    tmp = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
    # 临时画到 tmp
    tmp_path = path + ".tmp.png"
    draw_func(tmp_path)
    tmp = Image.open(tmp_path).convert("RGBA")
    # 加深色背景
    bg = Image.new("RGBA", (32 * scale, 48 * scale), (20, 18, 14, 255))
    # 放大（无抗锯齿，保持像素感）
    big = tmp.resize((32 * scale, 48 * scale), Image.NEAREST)
    bg.paste(big, (0, 0), big)
    # 加金色光晕（角色身后）
    glow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = bg.size[0] // 2, bg.size[1] // 2
    for r in range(150, 0, -10):
        a = int(40 * (1 - r / 150))
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(184, 134, 11, a))
    bg.paste(glow, (0, 0), glow)
    bg.save(path)
    os.remove(tmp_path)


def main():
    for sub in ["sprites", "bg", "portraits"]:
        os.makedirs(os.path.join(ASSETS, sub), exist_ok=True)

    # 玩家
    draw_player(os.path.join(ASSETS, "sprites", "rinne.png"))
    # 敌人
    draw_enemy_jiangshi(os.path.join(ASSETS, "sprites", "steam_jiangshi.png"))
    draw_enemy_paper(os.path.join(ASSETS, "sprites", "paper_effigy.png"))
    # NPC
    draw_npc_mechanist(os.path.join(ASSETS, "sprites", "npc_mechanist.png"))
    # 出口
    draw_portal(os.path.join(ASSETS, "sprites", "portal.png"))
    # 背景
    draw_corridor_bg(os.path.join(ASSETS, "bg", "chapter1_corridor.png"))
    draw_corridor_bg(os.path.join(ASSETS, "bg", "temple_inner_hall.png"))
    # 立绘（放大版）
    draw_portrait_pixel(os.path.join(ASSETS, "portraits", "rinne.png"), draw_player)
    draw_portrait_pixel(os.path.join(ASSETS, "portraits", "paper_effigy.png"), draw_enemy_paper)
    draw_portrait_pixel(os.path.join(ASSETS, "portraits", "steam_jiangshi.png"), draw_enemy_jiangshi)

    print("[OK] 像素美术资产已生成")


if __name__ == "__main__":
    main()
