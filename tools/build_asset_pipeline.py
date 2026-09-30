"""
v2 资产管线：生成 → 切割 → manifest 一条龙
=================================================
流程（素材切割 + 投入系统）：
  1. 生成源图（"建模"）：图块集源图 atlas、UI 9-slice 源图 sheet、道具精灵
  2. 按切割配置 slice：源图 → 独立资产 PNG（tiles/ ui9/ sprites/）
  3. 产出资产清单 data/v2/asset_manifest.json（游戏内 AssetRegistry 数据驱动加载）
  4. 生成 64×64 程序化地图 data/v2/maps/map_64.json（房间/走廊/门/陷阱/物件）
  5. 生成 UI 主题 data/v2/ui_theme.json（9-slice 边距像素级配置）

全部确定性（seed 固定），可重复运行。
"""
import os
import json
import random
from PIL import Image, ImageDraw

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(BASE, "assets", "v2")
DATA = os.path.join(BASE, "data", "v2")

TILE = 32  # 图块尺寸
COLS, ROWS = 8, 2  # 图块集源图网格

# 蒸汽道术色板
C = {
    "jet": (26, 26, 26, 255), "brass": (184, 134, 11, 255),
    "brass_light": (218, 165, 32, 255), "brass_dark": (120, 88, 8, 255),
    "cinnabar": (194, 59, 59, 255), "copper": (80, 160, 160, 255),
    "copper_dark": (40, 100, 100, 255), "steam": (232, 224, 208, 255),
    "ink": (42, 92, 107, 255), "phosphor": (127, 255, 80, 255),
    "paper": (212, 175, 55, 255), "purple": (107, 47, 160, 255),
}


# ============================================================
# 1. 图块绘制（每个 32×32）
# ============================================================

def t_wall(d, ox, oy):
    # 砖墙：深底 + 黄铜勾缝
    d.rectangle([ox, oy, ox+31, oy+31], fill=(50, 38, 26, 255))
    for j in range(4):
        y = oy + j * 8
        d.line([(ox, y), (ox+31, y)], fill=(28, 20, 14, 255))
        off = 8 if j % 2 else 0
        for i in range(3):
            x = ox + ((i * 12 + off) % 32)
            d.line([(x, y), (x, min(y+8, oy+31))], fill=(28, 20, 14, 255))
    d.rectangle([ox, oy, ox+31, oy+1], fill=C["brass_dark"])
    d.rectangle([ox, oy+30, ox+31, oy+31], fill=(20, 14, 10, 255))


def t_floor(d, ox, oy, variant=0):
    base = (44, 33, 24, 255) if variant == 0 else (38, 30, 22, 255)
    d.rectangle([ox, oy, ox+31, oy+31], fill=base)
    # 石板缝
    d.line([(ox, oy+15), (ox+31, oy+15)], fill=(30, 22, 16, 255))
    d.line([(ox+15, oy), (ox+15, oy+15)], fill=(30, 22, 16, 255))
    d.line([(ox+7, oy+16), (ox+7, oy+31)], fill=(30, 22, 16, 255))
    d.line([(ox+23, oy+16), (ox+23, oy+31)], fill=(30, 22, 16, 255))
    if variant == 2:  # 裂纹变体
        d.line([(ox+6, oy+6), (ox+12, oy+13), (ox+10, oy+22)], fill=(24, 17, 12, 255))
    if variant == 3:  # 符文地板
        d.rectangle([ox+12, oy+12, ox+19, oy+19], outline=C["cinnabar"])
        d.rectangle([ox+14, oy+14, ox+17, oy+17], fill=C["cinnabar"])


def t_pit(d, ox, oy):
    # 陷阱/深坑：黑底 + 警示边
    d.rectangle([ox, oy, ox+31, oy+31], fill=(8, 6, 10, 255))
    d.rectangle([ox, oy, ox+31, oy+31], outline=(60, 40, 24, 255))
    for i in range(0, 32, 8):
        d.line([(ox+i, oy+4), (ox+i+4, oy+4)], fill=(40, 30, 20, 255))


def t_door(d, ox, oy):
    # 黄铜封印门
    d.rectangle([ox+2, oy, ox+29, oy+31], fill=(70, 52, 26, 255))
    d.rectangle([ox+2, oy, ox+29, oy+31], outline=C["brass_dark"])
    d.rectangle([ox+6, oy+4, ox+25, oy+28], outline=C["brass"])
    # 中心八卦锁
    d.ellipse([ox+11, oy+11, ox+20, oy+20], outline=C["cinnabar"], width=2)
    d.rectangle([ox+15, oy+8, ox+16, oy+23], fill=C["cinnabar"])
    d.rectangle([ox+9, oy+15, ox+22, oy+16], fill=C["cinnabar"])
    # 铆钉
    for px_, py_ in [(5, 3), (26, 3), (5, 28), (26, 28)]:
        d.ellipse([ox+px_, oy+py_, ox+px_+2, oy+py_+2], fill=C["brass_light"])


def t_portal(d, ox, oy):
    # 传送门地砖：磷火绿涡纹
    d.rectangle([ox, oy, ox+31, oy+31], fill=(18, 14, 26, 255))
    d.ellipse([ox+4, oy+4, ox+27, oy+27], outline=C["purple"], width=2)
    d.ellipse([ox+8, oy+8, ox+23, oy+23], outline=C["phosphor"], width=2)
    d.ellipse([ox+13, oy+13, ox+18, oy+18], fill=C["phosphor"])
    # 四角符文点
    for px_, py_ in [(3, 3), (26, 3), (3, 26), (26, 26)]:
        d.rectangle([ox+px_, oy+py_, ox+px_+2, oy+py_+2], fill=C["cinnabar"])


def t_corridor(d, ox, oy):
    # 走廊地板（更暗）
    d.rectangle([ox, oy, ox+31, oy+31], fill=(32, 26, 20, 255))
    for i in range(0, 32, 16):
        d.line([(ox+i, oy), (ox+i, oy+31)], fill=(24, 18, 14, 255))
        d.line([(ox, oy+i), (ox+31, oy+i)], fill=(24, 18, 14, 255))


def t_void(d, ox, oy):
    d.rectangle([ox, oy, ox+31, oy+31], fill=(12, 10, 14, 255))


TILE_PAINTERS = {
    "wall": t_wall, "floor": lambda d, x, y: t_floor(d, x, y, 0),
    "floor_var": lambda d, x, y: t_floor(d, x, y, 1),
    "floor_crack": lambda d, x, y: t_floor(d, x, y, 2),
    "floor_rune": lambda d, x, y: t_floor(d, x, y, 3),
    "pit": t_pit, "door": t_door, "portal": t_portal,
    "corridor": t_corridor, "void": t_void,
}

# 图例字符 → 图块名（地图 ground 行用）
LEGEND = {
    "#": "wall", ".": "floor", ",": "floor_var", "*": "floor_crack",
    "R": "floor_rune", "~": "pit", "D": "door", "P": "portal",
    "_": "corridor",
}

# 图块名 → 图集坐标
TILE_ATLAS = {}
for i, name in enumerate(TILE_PAINTERS.keys()):
    TILE_ATLAS[name] = [i % COLS, i // COLS]


# ============================================================
# 2. UI 9-slice 源图
# ============================================================

def build_ui_source(path):
    """192×96：三个 64×64 面板（main / dark / button），供 9-slice 切割"""
    img = Image.new("RGBA", (192, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def panel(x, y, bg, border, inner_glow=None):
        d.rounded_rectangle([x, y, x+63, y+63], radius=6, fill=bg, outline=border, width=3)
        d.rounded_rectangle([x+3, y+3, x+60, y+60], radius=4, outline=(*border[:3], 90), width=1)
        if inner_glow:
            d.rounded_rectangle([x+6, y+6, x+57, y+57], radius=3, outline=(*inner_glow[:3], 60), width=1)
        # 四角铆钉
        for px_, py_ in [(7, 7), (53, 7), (7, 53), (53, 53)]:
            d.ellipse([x+px_-2, y+py_-2, x+px_+2, y+py_+2], fill=border)

    # main 面板：深底黄铜边
    panel(0, 0, (20, 17, 12, 235), C["brass"], C["cinnabar"])
    # dark 面板：黑底铜绿边
    panel(64, 0, (12, 12, 16, 240), C["copper"])
    # button：黄铜底（normal 样式，hover/pressed 由主题 tint）
    panel(128, 0, (48, 36, 18, 255), C["brass_light"])
    img.save(path)
    return img


def build_item_sprites(out_dir):
    """道具精灵 16×16"""
    os.makedirs(out_dir, exist_ok=True)
    # 钥匙
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, 8, 8], outline=C["brass_light"], width=2)
    d.line([(8, 8), (13, 13)], fill=C["brass_light"], width=2)
    d.line([(11, 11), (13, 9)], fill=C["brass_light"], width=1)
    d.line([(9, 13), (11, 15)], fill=C["brass_light"], width=1)
    img.save(os.path.join(out_dir, "item_key.png"))
    # 卡牌卷轴
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([3, 2, 12, 13], fill=(212, 195, 160, 255), outline=C["brass_dark"])
    d.rectangle([5, 5, 10, 6], fill=C["cinnabar"])
    d.rectangle([5, 8, 10, 9], fill=(90, 70, 40, 255))
    img.save(os.path.join(out_dir, "item_scroll.png"))


# ============================================================
# 3. 64×64 程序化地图生成
# ============================================================

def gen_map(w=64, h=64, seed=20260903):
    rng = random.Random(seed)
    grid = [["#"] * w for _ in range(h)]

    # --- 房间 ---
    rooms = []
    attempts = 0
    while len(rooms) < 10 and attempts < 300:
        attempts += 1
        rw, rh = rng.randint(9, 15), rng.randint(8, 13)
        rx, ry = rng.randint(2, w - rw - 2), rng.randint(2, h - rh - 2)
        r = (rx, ry, rw, rh)
        # 与已有房间保持间距（简单重叠检测，扩 2 格）
        ok = True
        for (ox, oy, ow, oh) in rooms:
            if rx < ox + ow + 2 and rx + rw + 2 > ox and ry < oy + oh + 2 and ry + rh + 2 > oy:
                ok = False
                break
        if not ok:
            continue
        rooms.append(r)
        for yy in range(ry, ry + rh):
            for xx in range(rx, rx + rw):
                grid[yy][xx] = "."

    def center(r):
        rx, ry, rw, rh = r
        return (rx + rw // 2, ry + rh // 2)

    # --- 走廊（顺序连接，宽 2） ---
    for i in range(len(rooms) - 1):
        x1, y1 = center(rooms[i])
        x2, y2 = center(rooms[i + 1])
        if rng.random() < 0.5:  # 先横后竖
            for xx in range(min(x1, x2), max(x1, x2) + 1):
                for dy in (0, 1):
                    if grid[y1 + dy][xx] == "#":
                        grid[y1 + dy][xx] = "_"
            for yy in range(min(y1, y2), max(y1, y2) + 1):
                for dx in (0, 1):
                    if grid[yy][x2 + dx] == "#":
                        grid[yy][x2 + dx] = "_"
        else:
            for yy in range(min(y1, y2), max(y1, y2) + 1):
                for dx in (0, 1):
                    if grid[yy][x1 + dx] == "#":
                        grid[yy][x1 + dx] = "_"
            for xx in range(min(x1, x2), max(x1, x2) + 1):
                for dy in (0, 1):
                    if grid[y2 + dy][xx] == "#":
                        grid[y2 + dy][xx] = "_"

    # --- 地板装饰（变体/裂纹/符文） ---
    for yy in range(h):
        for xx in range(w):
            if grid[yy][xx] == ".":
                roll = rng.random()
                if roll < 0.10:
                    grid[yy][xx] = ","
                elif roll < 0.15:
                    grid[yy][xx] = "*"
                elif roll < 0.17:
                    grid[yy][xx] = "R"

    # --- 陷阱坑（放几个房间内部 2×2） ---
    pits = []
    for r in rooms[2:6]:
        rx, ry, rw, rh = r
        px_, py_ = rx + rng.randint(1, rw - 3), ry + rng.randint(1, rh - 3)
        for yy in range(py_, py_ + 2):
            for xx in range(px_, px_ + 2):
                grid[yy][xx] = "~"
                pits.append([xx, yy])

    # --- 玩家出生点：房间 0 中心 ---
    start = list(center(rooms[0]))

    def free_tile_in(r, avoid=()):
        rx, ry, rw, rh = r
        for _ in range(60):
            x, y = rx + rng.randint(1, rw - 2), ry + rng.randint(1, rh - 2)
            if grid[y][x] in ".,*R_" and [x, y] not in avoid and [x, y] != start:
                return [x, y]
        return None

    objects = []

    # --- 钥匙（房间 2）+ 黄铜封印门（房间 0→后续走廊必经处放 D 不现实；
    #     简化：门 D 放在最后一个房间（传送门房）的入口格，需要 has_key） ---
    key_pos = free_tile_in(rooms[2]) or free_tile_in(rooms[1])
    if key_pos:
        objects.append({
            "id": "brass_key", "type": "item", "tile": key_pos,
            "sprite": "res://assets/v2/sprites/item_key.png",
            "set_flag": "has_key", "pickup_text": "获得黄铜钥匙",
            "give_card": ""
        })

    # --- NPC：机械师（房间 1） ---
    npc_pos = free_tile_in(rooms[1]) or free_tile_in(rooms[2])
    if npc_pos:
        objects.append({
            "id": "mechanist", "type": "npc", "tile": npc_pos,
            "sprite": "res://assets/v2/sprites/npc_mechanist.png",
            "name": "受伤的机械师", "on_trigger": "mechanist_dialog"
        })

    # --- 敌人 ×3（房间 3/4/5） ---
    enemy_defs = [
        ("paper_effigy", "paper_effigy_defeated"),
        ("steam_jiangshi", "steam_jiangshi_defeated"),
        ("paper_effigy", "guard_defeated"),
    ]
    used = [key_pos, npc_pos]
    for i, (tmpl, flag) in enumerate(enemy_defs):
        room = rooms[3 + i] if 3 + i < len(rooms) else rooms[-1]
        pos = free_tile_in(room, avoid=used)
        if pos:
            used.append(pos)
            objects.append({
                "id": f"enemy_{tmpl}_{i}", "type": "enemy", "tile": pos,
                "sprite": f"res://assets/v2/sprites/{tmpl}.png",
                "enemy_template": tmpl, "on_defeat_flag": flag
            })

    # --- 卡牌卷轴 ×2（拾取给卡） ---
    card_loot = [("talisman_yinlei", "card_talisman_yinlei"), ("steam_valve_release", "card_steam_valve_release")]
    for i, (card, flag) in enumerate(card_loot):
        room = rooms[6 + i] if 6 + i < len(rooms) else rooms[-1]
        pos = free_tile_in(room, avoid=used)
        if pos:
            used.append(pos)
            objects.append({
                "id": f"scroll_{card}", "type": "item", "tile": pos,
                "sprite": "res://assets/v2/sprites/item_scroll.png",
                "set_flag": flag, "pickup_text": "获得符卷：%s" % card,
                "give_card": card
            })

    # --- 传送门房间（最后一个房间中心）：P 地砖 + 守门 D ---
    prx, pry = center(rooms[-1])
    grid[pry][prx] = "P"
    # 门放在传送门房间入口：找房间边缘上与走廊相连的格子 → 找房间周围第一块走廊地砖
    door_pos = None
    rx, ry, rw, rh = rooms[-1]
    for yy in range(ry - 1, ry + rh + 1):
        for xx in range(rx - 1, rx + rw + 1):
            if 0 <= xx < w and 0 <= yy < h and grid[yy][xx] == "_":
                door_pos = [xx, yy]
                break
        if door_pos:
            break
    if not door_pos:
        # 兜底：房间内部边缘
        door_pos = [rx, ry]
    grid[door_pos[1]][door_pos[0]] = "D"
    objects.append({
        "id": "seal_door", "type": "door", "tile": door_pos,
        "requires_flag": "has_key", "locked_text": "黄铜封印门紧锁——需要黄铜钥匙"
    })
    objects.append({
        "id": "exit_portal", "type": "portal", "tile": [prx, pry],
        "requires_flag": "paper_effigy_defeated",
        "locked_text": "封魂之力未净——先击败守门的纸扎义体"
    })

    ground_rows = ["".join(row) for row in grid]
    return {
        "id": "map_64",
        "_comment": "64×64 程序化地图。ground 行字符见 legend；objects 为地图玩法物件（npc/enemy/item/door/portal）。",
        "width": w, "height": h, "tile_size": TILE,
        "tileset": {"atlas": "res://assets/v2/tiles/tileset_atlas.png"},
        "legend": LEGEND,
        "player_start": start,
        "ground": ground_rows,
        "objects": objects,
        "meta": {"rooms": len(rooms), "seed": seed, "pits": len(pits)}
    }


# ============================================================
# 4. 执行管线
# ============================================================

def main():
    rng = random.Random(42)
    tiles_dir = os.path.join(ASSETS, "tiles")
    ui9_dir = os.path.join(ASSETS, "ui9")
    sprites_dir = os.path.join(ASSETS, "sprites")
    maps_dir = os.path.join(DATA, "maps")
    for p in (tiles_dir, ui9_dir, sprites_dir, maps_dir):
        os.makedirs(p, exist_ok=True)

    manifest = {"tiles": {}, "ui9": {}, "sprites": {}, "tileset_atlas": "", "tile_atlas_coords": {}}

    # --- 1) 生成图块集源图（atlas） ---
    atlas = Image.new("RGBA", (COLS * TILE, ROWS * TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(atlas)
    names = list(TILE_PAINTERS.keys())
    for i, name in enumerate(names):
        ox, oy = (i % COLS) * TILE, (i // COLS) * TILE
        TILE_PAINTERS[name](d, ox, oy)
        TILE_ATLAS[name] = [i % COLS, i // COLS]
    atlas_path = os.path.join(tiles_dir, "tileset_atlas.png")
    atlas.save(atlas_path)
    manifest["tileset_atlas"] = "res://assets/v2/tiles/tileset_atlas.png"
    manifest["tile_atlas_coords"] = TILE_ATLAS

    # --- 2) 切割：每个图块也切出独立 PNG（供清单/独立引用） ---
    for i, name in enumerate(names):
        ox, oy = (i % COLS) * TILE, (i // COLS) * TILE
        tile_img = atlas.crop((ox, oy, ox + TILE, oy + TILE))
        p = os.path.join(tiles_dir, "%s.png" % name)
        tile_img.save(p)
        manifest["tiles"][name] = "res://assets/v2/tiles/%s.png" % name

    # --- 3) UI 源图 + 9-slice 切割 ---
    ui_src_path = os.path.join(ASSETS, "ui_source_sheet.png")
    build_ui_source(ui_src_path)
    ui_src = Image.open(ui_src_path)
    ui_names = ["panel_main", "panel_dark", "button"]
    ui_cfg = {}
    for i, name in enumerate(ui_names):
        crop = ui_src.crop((i * 64, 0, i * 64 + 64, 64))
        p = os.path.join(ui9_dir, "%s.png" % name)
        crop.save(p)
        manifest["ui9"][name] = "res://assets/v2/ui9/%s.png" % name
        ui_cfg[name] = {"source": "res://assets/v2/ui9/%s.png" % name,
                        "margins": [10, 10, 10, 10], "content": [12, 8, 12, 8]}
    os.remove(ui_src_path)  # 源图用完即弃（切割产物才是资产）

    # --- 4) 道具精灵 ---
    build_item_sprites(sprites_dir)
    manifest["sprites"]["item_key"] = "res://assets/v2/sprites/item_key.png"
    manifest["sprites"]["item_scroll"] = "res://assets/v2/sprites/item_scroll.png"

    # --- 5) 写 manifest ---
    with open(os.path.join(DATA, "asset_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent="\t")

    # --- 6) 写 UI 主题（9-slice 像素级配置） ---
    ui_theme = {
        "_comment": "高精度 UI 主题：9-slice 边距/内容边距逐像素配置，UIThemeFactory 读取此文件构建 StyleBoxTexture。",
        "colors": {
            "brass": "#B8860B", "cinnabar": "#C23B3B", "copper": "#50A0A0",
            "steam": "#E8E0D0", "phosphor": "#7FFF50", "ink": "#2A5C6B"
        },
        "font_size": {"default": 16, "title": 24, "small": 13},
        "panels": {
            "main": dict(ui_cfg["panel_main"]),
            "dark": dict(ui_cfg["panel_dark"])
        },
        "buttons": {
            "normal": dict(ui_cfg["button"]),
            "hover": {"source": ui_cfg["button"]["source"], "margins": ui_cfg["button"]["margins"],
                      "content": ui_cfg["button"]["content"], "modulate": "#DAB520"},
            "pressed": {"source": ui_cfg["button"]["source"], "margins": ui_cfg["button"]["margins"],
                        "content": ui_cfg["button"]["content"], "modulate": "#785808"}
        }
    }
    with open(os.path.join(DATA, "ui_theme.json"), "w", encoding="utf-8") as f:
        json.dump(ui_theme, f, ensure_ascii=False, indent="\t")

    # --- 7) 生成 64×64 地图 ---
    map_data = gen_map(64, 64)
    with open(os.path.join(maps_dir, "map_64.json"), "w", encoding="utf-8") as f:
        json.dump(map_data, f, ensure_ascii=False, indent="\t")

    # 摘要
    n_floor = sum(row.count(".") + row.count(",") + row.count("*") + row.count("R") + row.count("_") for row in map_data["ground"])
    print("[PIPELINE] 图块 %d 种（atlas %dx%d）| ui9 %d | 地图 %dx%d 可走格 %d | 物件 %d" % (
        len(names), COLS, ROWS, len(ui_names), 64, 64, n_floor, len(map_data["objects"])))
    print("[PIPELINE] manifest -> data/v2/asset_manifest.json")
    print("[PIPELINE] ui_theme -> data/v2/ui_theme.json")
    print("[PIPELINE] map -> data/v2/maps/map_64.json")


if __name__ == "__main__":
    main()
