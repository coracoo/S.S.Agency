# -*- coding: utf-8 -*-
"""战斗绘卷试装图合成（验证用）：背景画 + 敌我立绘 + 场景槽高亮 + 手牌区"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, math

REF = os.path.join(os.path.dirname(os.path.abspath(__file__)))
W, H = 1920, 1080

INK = (20, 17, 14)
PAPER = (242, 237, 228)
VERMILION = (199, 62, 58)
GOLD = (201, 162, 39)
FUJI = (122, 111, 240)
HI = (232, 163, 61)
GREEN = (111, 168, 111)
WOOD = (64, 50, 38)

def font(sz, bold=True):
    for p in [r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc",
              r"C:\Windows\Fonts\msyh.ttc"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

def load(name):
    return Image.open(os.path.join(REF, name))

# ---- 背景画 ----
bg = load("bg_val_corridor_battle_v1.png").convert("RGB").resize((W, H), Image.LANCZOS)
cv = bg.convert("RGBA")

# ---- 场景槽高亮（灯火橙呼吸描边 + 蔓延连线）----
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
slots = [(1095, 400, 70, 110), (1760, 520, 60, 100)]  # 吊钟槽 / 石灯槽（1920 坐标）
for (x, y, rx, ry) in slots:
    for i in range(3):
        gd.ellipse([x-rx-i*14, y-ry-i*14, x+rx+i*14, y+ry+i*14],
                   outline=(HI[0], HI[1], HI[2], 90-i*25), width=5)
gd.line([slots[0][0]+55, slots[0][1]+60, slots[1][0]-40, slots[1][1]+30],
        fill=(HI[0], HI[1], HI[2], 160), width=4)
glow = glow.filter(ImageFilter.GaussianBlur(3))
cv.alpha_composite(glow)

d = ImageDraw.Draw(cv)

# ---- 敌方立绘（右侧深处，55% 画高）+ 心意气泡 ----
enemy = load("enemy_val_paper_doll.png").convert("RGBA")
eh = 620
ew = int(enemy.width * eh / enemy.height)
enemy_r = enemy.resize((ew, eh), Image.LANCZOS)
cv.alpha_composite(enemy_r, (1400, 800 - eh))
# 心意气泡：朱红圆 + 白爪痕
bx, by, br = 1560, 110, 34
d.ellipse([bx-br, by-br, bx+br, by+br], fill=(VERMILION[0], VERMILION[1], VERMILION[2], 235),
          outline=(242, 237, 228, 255), width=3)
for i in range(3):
    x0 = bx - 16 + i * 12
    d.line([x0, by - 12, x0 + 8, by + 12], fill=(242, 237, 228, 255), width=4)
# 敌方 HP 条
d.rounded_rectangle([1400, 830, 1400 + ew, 842], 4, fill=(20, 17, 14, 200))
d.rounded_rectangle([1400, 830, 1400 + int(ew*0.7), 842], 4, fill=(*VERMILION, 255))

# ---- 我方立绘（左侧，45% 画高）+ HP/恐惧 ----
hero = load("char_val_rinne_idle_v1.png").convert("RGBA")
hh = 500
hw = int(hero.width * hh / hero.height)
hero_r = hero.resize((hw, hh), Image.LANCZOS)
cv.alpha_composite(hero_r, (150, 930 - hh))
d.rounded_rectangle([150, 950, 150+400, 962], 4, fill=(20, 17, 14, 200))
d.rounded_rectangle([150, 950, 150+int(400*0.82), 962], 4, fill=(*GREEN, 255))
d.rounded_rectangle([150, 968, 150+400, 975], 3, fill=(20, 17, 14, 200))
d.rounded_rectangle([150, 968, 150+int(400*0.25), 975], 3, fill=(*FUJI, 255))
d.text((150, 985), "凛音", font=font(20), fill=(*PAPER, 255))

# ---- 顶部信息 ----
f_top = font(22)
d.text((60, 28), "回合 7 · 惊醒", font=f_top, fill=(*PAPER, 255))
for i in range(10):  # 灵墨刻度
    x = 60 + i * 22
    eye = i < 6
    d.ellipse([x, 66, x+12, 78], fill=(*INK, 255), outline=(*PAPER, 160), width=1)
    if eye and i >= 4:
        d.ellipse([x+3, 69, x+9, 75], fill=(*PAPER, 255))

# ---- 手牌区（4 张扇形）----
cards = [
    ("cardart_val_ignite.png", "引燃", 1),
    ("cardart_val_bell.png",   "鸣钟", 1),
    ("cardart_val_slash.png",  "居合斩", 2),
    ("cardart_val_seal.png",   "结界符", 3),
]
CW, CH = 210, 300
def make_card(art_name, cname, cost):
    card = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    # 深木边框 + 金缮内线 + 纸底
    cd.rounded_rectangle([0, 0, CW-1, CH-1], 12, fill=(*WOOD, 255))
    cd.rounded_rectangle([5, 5, CW-6, CH-6], 9, outline=(*GOLD, 255), width=2)
    cd.rounded_rectangle([10, 10, CW-11, CH-11], 7, fill=(*PAPER, 255))
    # 插画区
    art = load(art_name).convert("RGB").resize((CW-24, 190), Image.LANCZOS)
    card.paste(art, (12, 14))
    # 名称 + 费用勾玉
    cd.text((CW//2, 222), cname, font=font(24), fill=(*INK, 255), anchor="mm")
    cd.ellipse([CW-52, 14, CW-16, 50], fill=(*GOLD, 255), outline=(*INK, 255), width=2)
    cd.text((CW-34, 32), str(cost), font=font(20), fill=(*INK, 255), anchor="mm")
    return card

start_x, y0, gap = 640, 830, 150
angles = [-7, -2, 3, 8]
for i, (art, cname, cost) in enumerate(cards):
    c = make_card(art, cname, cost).rotate(angles[i], expand=True, resample=Image.BICUBIC)
    cv.alpha_composite(c, (start_x + i * gap - c.width // 2 + 100, y0 - c.height // 2 + 60))

# ---- AP 勾玉 + 结束回合木牌 ----
for i in range(6):
    x = 1560 + i * 28
    fill = (*GOLD, 255) if i < 3 else (0, 0, 0, 0)
    d.ellipse([x, 960, x+20, 980], fill=fill, outline=(*GOLD, 255), width=2)
d.rounded_rectangle([1560, 1000, 1800, 1050], 6, fill=(*WOOD, 255), outline=(*GOLD, 255), width=2)
d.text((1680, 1025), "结束回合", font=font(22), fill=(*PAPER, 255), anchor="mm")

cv.convert("RGB").save(os.path.join(REF, "composite_val_battle_screen_v1.png"))
print("saved composite_val_battle_screen_v1.png")
