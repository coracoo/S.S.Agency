"""
占位美术资产生成器 v2
生成带辨识度的人形剪影（不是色块）+ 横版背景渐变。
用于在 AI 美术到位前让画面有"形状"和"场景感"。

生成的资产：
  assets/v2/sprites/rinne.png          玩家：道袍立姿人形（黄铜色）
  assets/v2/sprites/paper_effigy.png   纸扎义体：僵立人形（米黄色）
  assets/v2/sprites/steam_jiangshi.png 蒸汽僵尸：双臂前伸（铜绿色）
  assets/v2/sprites/npc_mechanist.png  NPC：受伤坐姿（暗灰）
  assets/v2/sprites/portal.png         出口：发光圆环（紫黑）
  assets/v2/bg/chapter1_corridor.png   背景：蒸汽道观走廊渐变（深色 + 远处管道轮廓）
  assets/v2/bg/temple_inner_hall.png   背景：内殿渐变
  assets/v2/portraits/rinne.png        立绘占位（大尺寸人形）
  assets/v2/portraits/paper_effigy.png
  assets/v2/portraits/steam_jiangshi.png
"""
import os
from PIL import Image, ImageDraw, ImageFilter

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # S.S.Agency/
ASSETS = os.path.join(BASE, "assets", "v2")

# 蒸汽道术色板
JET_BLACK = (26, 26, 26, 255)
BRASS = (184, 134, 11, 255)
CINNABAR = (194, 59, 59, 255)
COPPER_GREEN = (80, 160, 160, 255)
STEAM_WHITE = (232, 224, 208, 255)
INK_BLUE = (42, 92, 107, 255)
PHOSPHOR_GREEN = (127, 255, 80, 255)
PAPER_YELLOW = (212, 175, 55, 255)
DARK_PURPLE = (107, 47, 160, 255)


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def new_image(w, h, bg=None):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0) if bg is None else bg)
    return img, ImageDraw.Draw(img)


def draw_humanoid(draw, cx, feet_y, scale, color, pose="stand"):
    """画一个简单人形。pose: stand / arms_forward / sitting / hurt"""
    s = scale
    # 身体（道袍梯形）
    body_top = feet_y - int(110 * s)
    body_w_top = int(18 * s)
    body_w_bot = int(28 * s)
    body_pts = [
        (cx - body_w_top, body_top + int(20 * s)),
        (cx + body_w_top, body_top + int(20 * s)),
        (cx + body_w_bot, feet_y),
        (cx - body_w_bot, feet_y),
    ]
    draw.polygon(body_pts, fill=color)
    # 头（圆）
    head_r = int(16 * s)
    head_cy = body_top - head_r + int(6 * s)
    draw.ellipse([cx - head_r, head_cy - head_r, cx + head_r, head_cy + head_r], fill=color)
    # 手臂
    arm_y = body_top + int(28 * s)
    arm_len = int(40 * s)
    arm_thick = max(int(6 * s), 3)
    if pose == "arms_forward":
        # 僵尸双臂前伸
        draw.rectangle([cx - body_w_top - arm_thick, arm_y, cx + body_w_top + arm_thick, arm_y + int(10*s)], fill=color)
        draw.rectangle([cx - body_w_top - int(20*s), arm_y, cx + body_w_top + int(20*s), arm_y + arm_len], fill=color)
    elif pose == "sitting" or pose == "hurt":
        # 手臂下垂贴身
        draw.rectangle([cx - body_w_top - arm_thick, arm_y, cx - body_w_top, arm_y + int(60*s)], fill=color)
        draw.rectangle([cx + body_w_top, arm_y, cx + body_w_top + arm_thick, arm_y + int(60*s)], fill=color)
    else:
        # 站立，手臂略张
        draw.rectangle([cx - body_w_top - int(14*s), arm_y, cx - body_w_top, arm_y + int(55*s)], fill=color)
        draw.rectangle([cx + body_w_top, arm_y, cx + body_w_top + int(14*s), arm_y + int(55*s)], fill=color)
    # 眼睛（小亮点，让立绘有"活气"）
    if pose != "hurt":
        eye_r = max(int(2 * s), 1)
        draw.ellipse([cx - 6, head_cy - 2, cx - 6 + eye_r*2, head_cy - 2 + eye_r*2], fill=PHOSPHOR_GREEN)
        draw.ellipse([cx + 4, head_cy - 2, cx + 4 + eye_r*2, head_cy - 2 + eye_r*2], fill=PHOSPHOR_GREEN)


def draw_player_sprite(path, color):
    """玩家立绘（透明背景）"""
    img, d = new_image(120, 200)
    draw_humanoid(d, 60, 185, 1.2, color, pose="stand")
    img.save(path)


def draw_enemy_sprite(path, color, pose="arms_forward"):
    img, d = new_image(120, 200)
    draw_humanoid(d, 60, 185, 1.2, color, pose=pose)
    img.save(path)


def draw_npc_sprite(path, color):
    img, d = new_image(120, 200)
    draw_humanoid(d, 60, 185, 1.1, color, pose="hurt")
    img.save(path)


def draw_portal(path):
    img, d = new_image(120, 160)
    # 发光圆环
    cx, cy = 60, 80
    for r, alpha in [(50, 60), (40, 120), (30, 200), (20, 255)]:
        d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=(*DARK_PURPLE[:3], alpha), width=4)
    # 中心渐变
    for r in range(18, 0, -2):
        a = int(255 * (1 - r/18))
        d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(*PHOSPHOR_GREEN[:3], a//3))
    img.save(path)


def draw_corridor_bg(path, w=2400, h=1024):
    """横版背景：深色渐变 + 简单管道/柱子轮廓"""
    img, d = new_image(w, h, bg=JET_BLACK)
    # 垂直渐变（顶深底稍亮）
    for y in range(h):
        t = y / h
        r = int(20 + t * 15)
        g = int(15 + t * 10)
        b = int(18 + t * 12)
        d.line([(0, y), (w, y)], fill=(r, g, b, 255))
    # 地面（深棕色横条）
    ground_y = 700
    d.rectangle([0, ground_y, w, h], fill=(35, 25, 18, 255))
    # 地面高光线
    d.line([(0, ground_y), (w, ground_y)], fill=BRASS, width=2)
    # 远处管道轮廓（垂直长方形 + 圆形阀门）
    pipe_color = (45, 35, 25, 255)
    valve_color = (90, 60, 30, 255)
    for i in range(8):
        x = 200 + i * 300
        # 立柱
        d.rectangle([x - 30, 200, x + 30, ground_y], fill=pipe_color)
        d.rectangle([x - 35, 200, x + 35, 220], fill=pipe_color)  # 顶帽
        # 阀门（圆）
        d.ellipse([x - 18, 400, x + 18, 436], fill=valve_color)
        d.ellipse([x - 10, 408, x + 10, 428], fill=(140, 90, 40, 255))
    # 蒸汽雾（顶部白色低透明度模糊）
    mist = Image.new("RGBA", (w, 200), (0, 0, 0, 0))
    md = ImageDraw.Draw(mist)
    for _ in range(60):
        import random
        random.seed(42)
        x = random.randint(0, w)
        y = random.randint(0, 200)
        r = random.randint(30, 80)
        md.ellipse([x-r, y-r, x+r, y+r], fill=(232, 224, 208, 30))
    mist = mist.filter(ImageFilter.GaussianBlur(radius=20))
    img.paste(mist, (0, 0), mist)
    img.save(path)


def draw_portrait(path, color, pose="stand"):
    """立绘（大尺寸，用于战斗场景与对话框）"""
    img, d = new_image(400, 600, bg=(20, 18, 14, 255))
    # 背景光晕
    for r in range(300, 0, -10):
        a = int(40 * (1 - r/300))
        d.ellipse([200-r, 300-r, 200+r, 300+r], fill=(*color[:3], a))
    draw_humanoid(d, 200, 560, 3.0, color, pose=pose)
    img.save(path)


def main():
    # 确保目录存在
    for sub in ["sprites", "bg", "portraits"]:
        ensure_dir(os.path.join(ASSETS, sub))

    # 玩家
    draw_player_sprite(os.path.join(ASSETS, "sprites", "rinne.png"), BRASS)
    # 敌人
    draw_enemy_sprite(os.path.join(ASSETS, "sprites", "paper_effigy.png"), PAPER_YELLOW, pose="arms_forward")
    draw_enemy_sprite(os.path.join(ASSETS, "sprites", "steam_jiangshi.png"), COPPER_GREEN, pose="arms_forward")
    # NPC
    draw_npc_sprite(os.path.join(ASSETS, "sprites", "npc_mechanist.png"), (120, 110, 100, 255))
    # 出口
    draw_portal(os.path.join(ASSETS, "sprites", "portal.png"))
    # 背景
    draw_corridor_bg(os.path.join(ASSETS, "bg", "chapter1_corridor.png"))
    draw_corridor_bg(os.path.join(ASSETS, "bg", "temple_inner_hall.png"))
    # 立绘
    draw_portrait(os.path.join(ASSETS, "portraits", "rinne.png"), BRASS, pose="stand")
    draw_portrait(os.path.join(ASSETS, "portraits", "paper_effigy.png"), PAPER_YELLOW, pose="arms_forward")
    draw_portrait(os.path.join(ASSETS, "portraits", "steam_jiangshi.png"), COPPER_GREEN, pose="arms_forward")

    print("[OK] 占位资产已生成到", ASSETS)


if __name__ == "__main__":
    main()
