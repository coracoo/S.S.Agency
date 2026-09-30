# -*- coding: utf-8 -*-
"""战斗配置管线：config/battle_config.xlsx（人工维护的工程化配置源）→ data/battles/*.json（游戏运行时读取）。

覆盖 v3 横版战斗的全部平衡配置：场次（灵气规则/封印规则/玩家/牌组）、敌方波次、
场景槽位、技能卡牌。嵌套结构（anims 帧表/pattern 意图循环/intent_text 等）以 JSON 单元格承载。

用法：
  python tools/export_battle_config_xlsx.py            # 读取 xlsx → 校验 → 导出 JSON
  python tools/export_battle_config_xlsx.py --init     # 用 data/battles 现有 JSON 重建 xlsx

校验（警告当错误，退出码非 0）：
  必填缺失 / 类型不符 / JSON 单元格解析失败 / res:// 资源文件不存在 /
  卡牌类型与槽位状态枚举非法 / 灵气档位与阈值有序性 / 槽位邻接与执念槽悬空引用 /
  同场卡牌 id 重复 / 阵眼数量不足以满足封印规则
"""
import glob
import json
import os
import sys

import openpyxl
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "config", "battle_config.xlsx")
BATTLES_DIR = os.path.join(ROOT, "data", "battles")
RITUALS_DIR = os.path.join(ROOT, "data", "rituals")

# 字段定义：(key, 表头, 类型)；类型 str/int/float/bool/json；空单元格 = 省略该字段
BATTLE_FIELDS = [
    ("file", "file(输出文件名)", "str"),
    ("id", "id", "str"),
    ("name", "name(战斗名)", "str"),
    ("comment", "comment(备注)", "str"),
    ("bg", "bg(背景图)", "str"),
    ("ap_per_turn", "ap_per_turn", "int"),
    ("spirit", "spirit(灵气规则JSON)", "json"),
    ("seal_rule", "seal_rule(封印规则JSON)", "json"),
    ("player", "player(玩家JSON含anims)", "json"),
    ("deck", "deck(牌组JSON)", "json"),
    ("demo_note", "demo_note(机制说明)", "str"),
]
ENEMY_FIELDS = [
    ("battle", "battle(场次file)", "str"),
    ("idx", "idx(波次)", "int"),
    ("name", "name(波名)", "str"),
    ("comment", "comment(备注)", "str"),
    ("sprite", "sprite(立绘)", "str"),
    ("hp", "hp", "int"),
    ("attack", "attack(攻击)", "int"),
    ("seal_guard", "seal_guard(破阵阈值)", "int"),
    ("comment_guard", "comment_guard(破阵备注)", "str"),
    ("obsession_slot", "obsession_slot(执念槽)", "str"),
    ("obsession_text", "obsession_text(执念文案)", "str"),
    ("comment_obsession", "comment_obsession(执念备注)", "str"),
    ("height_px", "height_px(立绘高)", "int"),
    ("pos", "pos(站位[x,y]JSON)", "json"),
    ("fear_attack_mult", "fear_attack_mult(恐惧攻击倍率)", "float"),
    ("stun_skip", "stun_skip(免疫眩晕)", "bool"),
    ("pattern", "pattern(意图循环JSON)", "json"),
    ("intent_text", "intent_text(意图文案JSON)", "json"),
    ("pounce_mult", "pounce_mult(猛扑倍率)", "float"),
    ("howl_spirit", "howl_spirit(尖啸灵气)", "int"),
    ("anims", "anims(动画JSON)", "json"),
    ("count", "count(同场数量)", "int"),
    ("spacing_px", "spacing_px(站位间距)", "int"),
]
SLOT_FIELDS = [
    ("battle", "battle(场次file)", "str"),
    ("idx", "idx(序)", "int"),
    ("id", "id", "str"),
    ("name", "name(槽名)", "str"),
    ("pos", "pos(归一坐标JSON)", "json"),
    ("state", "state(初始状态)", "str"),
    ("adjacent", "adjacent(相邻槽JSON)", "json"),
    ("seal_point", "seal_point(阵眼)", "bool"),
    ("extinguish", "extinguish(可灭火)", "bool"),
]
CARD_FIELDS = [
    ("battle", "battle(场次file)", "str"),
    ("idx", "idx(序)", "int"),
    ("id", "id", "str"),
    ("name", "name(卡名)", "str"),
    ("cost", "cost(灵墨费用)", "int"),
    ("type", "type(attack/slot/seal/skill)", "str"),
    ("owner", "owner(所属角色)", "str"),
    ("target", "target(目标)", "str"),
    ("power", "power(攻击牌面)", "int"),
    ("slot_state", "slot_state(槽位状态)", "str"),
    ("effects", "effects(效果JSON)", "json"),
    ("tags", "tags(标签JSON)", "json"),
    ("upgrade", "upgrade(升级分支JSON)", "json"),
    ("unlock", "unlock(解锁)", "str"),
    ("art", "art(卡面图)", "str"),
    ("desc", "desc(卡面文案)", "str"),
]
ARTIFACT_FIELDS = [
    ("id", "id", "str"),
    ("name", "name(器物名)", "str"),
    ("icon", "icon(图标)", "str"),
    ("effect", "effect(效果JSON)", "json"),
    ("limit", "limit(每场触发上限)", "int"),
    ("unlock", "unlock(解锁)", "str"),
    ("desc", "desc(描述)", "str"),
]
# 卡库补充卡（GDD §5.2 收藏制）：不进任何场次预设牌组，仅通过案件解锁进入收藏
LIBRARY_CARD_FIELDS = [
    ("idx", "idx(序)", "int"),
    ("id", "id", "str"),
    ("name", "name(卡名)", "str"),
    ("cost", "cost(灵墨费用)", "int"),
    ("type", "type(attack/slot/seal/skill)", "str"),
    ("owner", "owner(所属角色)", "str"),
    ("target", "target(目标)", "str"),
    ("power", "power(攻击牌面)", "int"),
    ("slot_state", "slot_state(槽位状态)", "str"),
    ("effects", "effects(效果JSON)", "json"),
    ("tags", "tags(标签JSON)", "json"),
    ("upgrade", "upgrade(升级分支JSON)", "json"),
    ("unlock", "unlock(解锁)", "str"),
    ("art", "art(卡面图)", "str"),
    ("desc", "desc(卡面文案)", "str"),
]
# 回合仪式（GDD §八）：场次化配置，独立于战斗（无敌方波次/槽位要求）
RITUAL_FIELDS = [
    ("file", "file(输出文件名)", "str"),
    ("id", "id", "str"),
    ("name", "name(仪式名)", "str"),
    ("comment", "comment(备注)", "str"),
    ("bg", "bg(背景图)", "str"),
    ("ap_per_turn", "ap_per_turn", "int"),
    ("max_turns", "max_turns(回合上限)", "int"),
    ("player", "player(玩家JSON含anims)", "json"),
    ("deck", "deck(牌组JSON)", "json"),
    ("cards", "cards(保底牌组JSON)", "json"),
    ("lamp", "lamp(引灯JSON)", "json"),
    ("add_fuel", "add_fuel(内置添灯JSON)", "json"),
    ("items", "items(道具JSON)", "json"),
    ("objectives", "objectives(目标JSON)", "json"),
    ("env_hits", "env_hits(环境冲击JSON)", "json"),
    ("intro", "intro(开场文案)", "str"),
    ("win_text", "win_text(成功文案)", "str"),
    ("lose_text", "lose_text(失败文案)", "str"),
]
SHEETS = {
    "battle": BATTLE_FIELDS,
    "enemy": ENEMY_FIELDS,
    "slot": SLOT_FIELDS,
    "card": CARD_FIELDS,
    "artifact": ARTIFACT_FIELDS,
    "ritual": RITUAL_FIELDS,
    "library_card": LIBRARY_CARD_FIELDS,
}
REQUIRED = {
    "battle": ["file", "id", "name", "bg", "ap_per_turn", "spirit", "seal_rule", "player", "deck"],
    "enemy": ["battle", "name", "sprite", "hp", "attack", "height_px", "pos", "pattern", "intent_text"],
    "slot": ["battle", "id", "name", "pos", "adjacent"],
    "card": ["battle", "id", "name", "cost", "type", "art", "desc"],
    "artifact": ["id", "name", "effect", "limit", "desc"],
    "ritual": ["file", "id", "name", "bg", "ap_per_turn", "max_turns", "player", "lamp", "objectives"],
}
CARD_TYPES = {"attack", "slot", "seal", "skill"}
SLOT_STATES = {"", "burning", "ringing", "spilled", "sealed"}
CARD_TYPE_NEEDS_SLOT_STATE = {"slot": True, "seal": True, "attack": False, "skill": False}
CARD_OWNERS = {"", "rinne", "mint", "homura", "zhongkui", "generic"} # 与 data/units.json 角色 id 一致（hakka/qingming 为旧名，已弃）
CARD_TARGETS = {"", "enemy"}
# effects 效果 JSON 白名单（GDD §5.6 起步机制；新键先扩这里再接运行时）
CARD_EFFECT_KEYS = {"shield", "cleanse", "mark", "consume_mark", "bonus", "spirit", "draw"}
# 器物效果 JSON 白名单（GDD §7：主战配置 1 件器物；运行时消费在 C 期接，先落数据）
ARTIFACT_EFFECT_KEYS = {"first_turn_ap", "shield_bonus", "seal_cost_discount", "tidy_free_once"}


def fail(msg: str) -> None:
    print(f"[校验失败] {msg}")
    sys.exit(1)


def cell_to_value(raw, kind: str, sheet: str, rowno: int, key: str):
    if raw is None or (isinstance(raw, str) and raw.strip() == ""):
        return None, True
    where = f"{sheet} 第{rowno}行 {key}"
    try:
        if kind == "str":
            return str(raw), False
        if kind == "int":
            return int(raw), False
        if kind == "float":
            return float(raw), False
        if kind == "bool":
            if isinstance(raw, bool):
                return raw, False
            s = str(raw).strip().lower()
            if s in ("true", "1", "是"):
                return True, False
            if s in ("false", "0", "否"):
                return False, False
            fail(f"{where}: 非法布尔值 '{raw}'")
        if kind == "json":
            v = json.loads(str(raw))
            return v, False
    except (ValueError, TypeError, json.JSONDecodeError) as e:
        fail(f"{where}: 解析失败（{e}）")


def read_sheet(ws, fields) -> list:
    headers = [c.value for c in ws[1]]
    col_of = {}
    for i, h in enumerate(headers):
        if h is None:
            continue
        for key, header, _kind in fields:
            if str(h).strip() == header:
                col_of[key] = i
    missing = [k for k, _h, _k in fields if k not in col_of]
    if missing:
        fail(f"sheet[{ws.title}] 缺列: {missing}")
    rows = []
    for rno, row in enumerate(ws.iter_rows(min_row=2, values_only=True), 2):
        if all(v is None or str(v).strip() == "" for v in row):
            continue
        rec = {}
        empty_keys = set()
        for key, _header, kind in fields:
            v, was_empty = cell_to_value(row[col_of[key]] if col_of[key] < len(row) else None,
                                         kind, ws.title, rno, key)
            if was_empty:
                empty_keys.add(key)
            else:
                rec[key] = v
        rec["_empty"] = empty_keys
        rec["_row"] = rno
        rows.append(rec)
    return rows


def check_res_file(path: str, where: str) -> None:
    if not isinstance(path, str) or not path.startswith("res://"):
        fail(f"{where}: 资源路径必须是 res:// 开头: {path!r}")
    fs = os.path.join(ROOT, path.replace("res://", "").replace("/", os.sep))
    if not os.path.isfile(fs):
        fail(f"{where}: 资源文件不存在 {path}")


def check_anim_frames(anims: dict, where: str) -> None:
    if not isinstance(anims, dict):
        fail(f"{where}: anims 必须是 JSON 对象")
    for state, frames in anims.items():
        if state == "fps":
            continue
        if not isinstance(frames, list) or not frames:
            fail(f"{where}: anims.{state} 必须是非空帧数组")
        for p in frames:
            check_res_file(p, where)


def export() -> None:
    if not os.path.isfile(XLSX):
        fail(f"找不到配置源 {XLSX}，请先运行 --init")
    wb = openpyxl.load_workbook(XLSX, data_only=True)
    for name in ("battle", "enemy", "slot", "card"):
        if name not in wb.sheetnames:
            fail(f"缺少 sheet[{name}]")
    battles = read_sheet(wb["battle"], BATTLE_FIELDS)
    enemies = read_sheet(wb["enemy"], ENEMY_FIELDS)
    slots = read_sheet(wb["slot"], SLOT_FIELDS)
    cards = read_sheet(wb["card"], CARD_FIELDS)
    # 器物表可选：缺 sheet 时导出一个空表占位（旧 xlsx 兼容），有表则全量校验
    artifacts = read_sheet(wb["artifact"], ARTIFACT_FIELDS) if "artifact" in wb.sheetnames else []
    # 仪式表可选：同上（GDD §八）
    rituals = read_sheet(wb["ritual"], RITUAL_FIELDS) if "ritual" in wb.sheetnames else []
    # 卡库补充卡可选：data/battles/_extra.json（卡库扫描一并读入）
    library_cards = read_sheet(wb["library_card"], LIBRARY_CARD_FIELDS) \
        if "library_card" in wb.sheetnames else []

    out_files = []
    for b in battles:
        rowno = b["_row"]
        for k in REQUIRED["battle"]:
            if k in b["_empty"]:
                fail(f"battle 第{rowno}行: 必填缺失 {k}")
        fname = b["file"]
        where = f"战斗[{fname}]"
        check_res_file(b["bg"], where)
        # 灵气规则：档位倍率齐全 + 阈值有序
        spirit = b["spirit"]
        tiers = spirit.get("tier_attack_mult", {})
        for t in ("weak", "normal", "empowered", "berserk"):
            if t not in tiers:
                fail(f"{where}: spirit.tier_attack_mult 缺档位 {t}")
        if not (spirit.get("weak_below", 0) < spirit.get("empowered_from", 0)
                <= spirit.get("berserk_from", 0)):
            fail(f"{where}: spirit 阈值必须 weak_below < empowered_from <= berserk_from")
        player = b["player"]
        check_res_file(player.get("sprite", ""), where)
        check_anim_frames(player.get("anims", {}), where)
        deck = b["deck"]
        if int(deck.get("copies", 0)) <= 0 or int(deck.get("hand_limit", 0)) <= 0:
            fail(f"{where}: deck.copies/hand_limit 必须为正整数")

        benemies = [e for e in enemies if e.get("battle") == fname]
        bslots = [s for s in slots if s.get("battle") == fname]
        bcards = [c for c in cards if c.get("battle") == fname]
        if not benemies:
            fail(f"{where}: 无任何敌方波次")
        if not bslots:
            fail(f"{where}: 无任何场景槽位")
        if not bcards:
            fail(f"{where}: 无任何卡牌")

        out_enemies = []
        for e in benemies:
            w = f"{where}/敌[{e.get('name','?')}] 第{e['_row']}行"
            for k in REQUIRED["enemy"]:
                if k in e["_empty"]:
                    fail(f"{w}: 必填缺失 {k}")
            if e["hp"] <= 0 or e["attack"] <= 0:
                fail(f"{w}: hp/attack 必须为正")
            check_res_file(e["sprite"], w)
            if "anims" in e:
                check_anim_frames(e["anims"], w)
            if not isinstance(e["pattern"], list) or not e["pattern"]:
                fail(f"{w}: pattern 必须是非空意图循环数组")
            for act in e["pattern"]:
                if act not in e["intent_text"]:
                    fail(f"{w}: pattern 动作 '{act}' 在 intent_text 中无文案")
            rec = {k: v for k, v in e.items() if not k.startswith("_")}
            rec.pop("battle", None)
            rec.pop("idx", None)
            out_enemies.append(rec)

        slot_ids = set()
        for s in bslots:
            w = f"{where}/槽[{s.get('id','?')}] 第{s['_row']}行"
            for k in REQUIRED["slot"]:
                if k in s["_empty"]:
                    fail(f"{w}: 必填缺失 {k}")
            if s["id"] in slot_ids:
                fail(f"{w}: 槽位 id 重复 {s['id']}")
            slot_ids.add(s["id"])
        for s in bslots:
            for adj in s["adjacent"]:
                if adj not in slot_ids:
                    fail(f"{where}/槽[{s['id']}]: 邻接悬空引用 {adj}")
        out_slots = []
        for s in bslots:
            rec = {k: v for k, v in s.items() if not k.startswith("_")}
            rec.pop("battle", None)
            rec.pop("idx", None)
            out_slots.append(rec)

        card_ids = set()
        out_cards = []
        for c in bcards:
            w = f"{where}/卡[{c.get('id','?')}] 第{c['_row']}行"
            for k in REQUIRED["card"]:
                if k in c["_empty"]:
                    fail(f"{w}: 必填缺失 {k}")
            if c["id"] in card_ids:
                fail(f"{w}: 卡牌 id 重复 {c['id']}")
            card_ids.add(c["id"])
            if c["type"] not in CARD_TYPES:
                fail(f"{w}: 非法卡牌类型 {c['type']}（{CARD_TYPES}）")
            if c.get("slot_state", "") not in SLOT_STATES:
                fail(f"{w}: 非法槽位状态 {c.get('slot_state','')}（{SLOT_STATES}）")
            if CARD_TYPE_NEEDS_SLOT_STATE[c["type"]] and not c.get("slot_state", ""):
                fail(f"{w}: {c['type']} 卡必须填 slot_state")
            if c["cost"] < 0:
                fail(f"{w}: cost 不能为负")
            if c.get("owner", "") not in CARD_OWNERS:
                fail(f"{w}: 非法所属角色 {c.get('owner','')}（{CARD_OWNERS}）")
            if c.get("target", "") not in CARD_TARGETS:
                fail(f"{w}: 非法目标 {c.get('target','')}（{CARD_TARGETS}）")
            fx = c.get("effects", {})
            if fx:
                if not isinstance(fx, dict):
                    fail(f"{w}: effects 必须是 JSON 对象")
                bad_keys = set(fx.keys()) - CARD_EFFECT_KEYS
                if bad_keys:
                    fail(f"{w}: effects 含未登记键 {sorted(bad_keys)}（白名单 {sorted(CARD_EFFECT_KEYS)}）")
                if int(fx.get("consume_mark", 0)) > 0 and int(fx.get("bonus", 0)) <= 0:
                    fail(f"{w}: consume_mark 必须搭配正数 bonus")
            check_res_file(c["art"], w)
            rec = {k: v for k, v in c.items() if not k.startswith("_")}
            rec.pop("battle", None)
            rec.pop("idx", None)
            out_cards.append(rec)

        # 封印规则 vs 阵眼数量
        n_seal = sum(1 for s in out_slots if s.get("seal_point"))
        need = b["seal_rule"].get("min_seal_points", 99)
        if n_seal < need:
            fail(f"{where}: 阵眼数量 {n_seal} < 封印规则要求 {need}")
        # 敌方执念槽引用
        for e in out_enemies:
            obs = e.get("obsession_slot", "")
            if obs and obs not in slot_ids:
                fail(f"{where}/敌[{e.get('name')}]: 执念槽悬空引用 {obs}")

        out = {k: v for k, v in b.items() if not k.startswith("_")}
        out.pop("file", None)
        out["enemies"] = out_enemies
        out["slots"] = out_slots
        out["cards"] = out_cards
        path = os.path.join(BATTLES_DIR, fname + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
        out_files.append((fname, len(out_enemies), len(out_slots), len(out_cards)))

    # 器物：主战配置 1 件（GDD §7），全局一份 data/artifacts.json
    out_artifacts = []
    seen_artifacts = set()
    for a in artifacts:
        w = f"器物[{a.get('id','?')}] 第{a['_row']}行"
        for k in REQUIRED["artifact"]:
            if k in a["_empty"]:
                fail(f"{w}: 必填缺失 {k}")
        if a["id"] in seen_artifacts:
            fail(f"{w}: 器物 id 重复 {a['id']}")
        seen_artifacts.add(a["id"])
        if a["limit"] <= 0:
            fail(f"{w}: limit 必须为正整数")
        fx = a["effect"]
        if not isinstance(fx, dict) or not fx:
            fail(f"{w}: effect 必须是非空 JSON 对象")
        bad_keys = set(fx.keys()) - ARTIFACT_EFFECT_KEYS
        if bad_keys:
            fail(f"{w}: effect 含未登记键 {sorted(bad_keys)}（白名单 {sorted(ARTIFACT_EFFECT_KEYS)}）")
        if a.get("icon"):
            check_res_file(a["icon"], w)
        out_artifacts.append({k: v for k, v in a.items() if not k.startswith("_")})
    art_path = os.path.join(ROOT, "data", "artifacts.json")
    with open(art_path, "w", encoding="utf-8") as f:
        json.dump(out_artifacts, f, ensure_ascii=False, indent=1)

    # 卡库补充卡：data/battles/_extra.json（CardLibraryV4 扫描 battles 目录时一并入库）
    out_lib_cards = []
    seen_lib = set()
    for c in library_cards:
        w = f"卡库补充卡[{c.get('id','?')}] 第{c['_row']}行"
        for key in ("id", "name", "cost", "type", "art", "desc"):
            if key in c["_empty"]:
                fail(f"{w}: 必填缺失 {key}")
        if c["id"] in seen_lib:
            fail(f"{w}: id 重复 {c['id']}")
        seen_lib.add(c["id"])
        if c["type"] not in CARD_TYPES:
            fail(f"{w}: 非法卡牌类型 {c['type']}（{CARD_TYPES}）")
        if c.get("unlock", "") in ("", "start"):
            fail(f"{w}: 补充卡必须登记非 start 的 unlock（如案件 id），否则应放进场次卡表")
        fx = c.get("effects", {})
        if fx:
            bad_keys = set(fx.keys()) - CARD_EFFECT_KEYS
            if bad_keys:
                fail(f"{w}: effects 含未登记键 {sorted(bad_keys)}")
        check_res_file(c["art"], w)
        rec = {k: v for k, v in c.items() if not k.startswith("_")}
        rec.pop("idx", None)
        out_lib_cards.append(rec)
    if library_cards:
        extra_path = os.path.join(BATTLES_DIR, "_extra.json")
        with open(extra_path, "w", encoding="utf-8") as f:
            json.dump({"comment": "卡库补充卡（案件解锁奖励，不进任何场次预设牌组）",
                       "cards": out_lib_cards}, f, ensure_ascii=False, indent=1)

    # 仪式：data/rituals/<file>.json（GDD §八；无敌方/槽位要求，独立校验）
    ritual_files = []
    by_file = {}
    for r in rituals:
        w = f"仪式[{r.get('file','?')}] 第{r['_row']}行"
        for k in REQUIRED["ritual"]:
            if k in r["_empty"]:
                fail(f"{w}: 必填缺失 {k}")
        fname = r["file"]
        if fname in by_file:
            fail(f"{w}: 同一 file 多行 {fname}（仪式一场一行）")
        lamp = r["lamp"]
        if int(lamp.get("max", 0)) <= 0 or int(lamp.get("start", -1)) < 0 \
                or int(lamp.get("decay_per_turn", 0)) < 0:
            fail(f"{w}: lamp.max/decay_per_turn 非负、start≥0")
        if int(lamp.get("start", 0)) > int(lamp.get("max", 0)):
            fail(f"{w}: lamp.start 不能超过 max")
        if not isinstance(r["objectives"], list) or not r["objectives"]:
            fail(f"{w}: objectives 必须是非空数组")
        obj_ids = set()
        for o in r["objectives"]:
            if not isinstance(o, dict) or not o.get("id") or not o.get("name"):
                fail(f"{w}: objective 缺 id/name")
            if o["id"] in obj_ids:
                fail(f"{w}: objective id 重复 {o['id']}")
            obj_ids.add(o["id"])
            if int(o.get("cost", 0)) < 0:
                fail(f"{w}: objective {o['id']} cost 不能为负")
            for req in o.get("requires", []):
                if req not in obj_ids:
                    fail(f"{w}: objective {o['id']} 前提悬空引用 {req}（须按依赖顺序排列）")
        for it in r.get("items", []) or []:
            if not isinstance(it, dict) or not it.get("id") or not it.get("name"):
                fail(f"{w}: item 缺 id/name")
            if int(it.get("cost", 0)) < 0 or int(it.get("amount", 0)) <= 0 \
                    or int(it.get("uses", 0)) <= 0:
                fail(f"{w}: item {it.get('id','?')} cost≥0/amount/uses 必须为正")
        for hit in r.get("env_hits", []) or []:
            if int(hit.get("from_turn", 0)) < 1 or int(hit.get("damage", 0)) <= 0:
                fail(f"{w}: env_hit from_turn≥1/damage 必须为正")
        check_res_file(r["bg"], w)
        check_anim_frames(r["player"].get("anims", {}), w)
        # 保底牌组（GDD §8.2「仪式提供基础防护/维持手段」）：无构筑存档时也能完成仪式
        if not isinstance(r.get("cards", []), list) or not r["cards"]:
            fail(f"{w}: cards 保底牌组必须是非空数组")
        base_ids = set()
        for c in r["cards"]:
            if not isinstance(c, dict) or not c.get("id") or not c.get("name") \
                    or not c.get("type"):
                fail(f"{w}: 保底卡缺 id/name/type")
            if c["id"] in base_ids:
                fail(f"{w}: 保底卡 id 重复 {c['id']}")
            base_ids.add(c["id"])
            if c["type"] not in CARD_TYPES:
                fail(f"{w}: 保底卡非法类型 {c['type']}（{CARD_TYPES}）")
            check_res_file(c.get("art", ""), w)
        rec = {k: v for k, v in r.items() if not k.startswith("_")}
        rec.pop("file", None)
        by_file[fname] = rec
    os.makedirs(RITUALS_DIR, exist_ok=True)
    for fname, rec in sorted(by_file.items()):
        path = os.path.join(RITUALS_DIR, fname + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(rec, f, ensure_ascii=False, indent=1)
        ritual_files.append(fname)

    print(f"[导出] {XLSX} → data/battles/：")
    for fname, ne, ns, nc in out_files:
        print(f"  {fname}.json：{ne} 波敌人 / {ns} 槽位 / {nc} 卡牌")
    print(f"  artifacts.json：{len(out_artifacts)} 件器物")
    if out_lib_cards:
        print(f"  battles/_extra.json：{len(out_lib_cards)} 张卡库补充卡")
    for fname in ritual_files:
        print(f"  rituals/{fname}.json")


def build_xlsx() -> None:
    """从 data/battles/*.json 反向生成 xlsx（首次迁移/重置用，保证无损）"""
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    head_font = Font(bold=True, color="FFFFFF")
    head_fill = PatternFill("solid", fgColor="3B3B58")

    def put(ws, fields, rows):
        for ci, (_k, header, _t) in enumerate(fields, 1):
            cell = ws.cell(1, ci, header)
            cell.font = head_font
            cell.fill = head_fill
            cell.alignment = Alignment(horizontal="center")
            ws.column_dimensions[get_column_letter(ci)].width = max(12, min(46, len(header) + 6))
        for ri, rec in enumerate(rows, 2):
            for ci, (key, _h, kind) in enumerate(fields, 1):
                if key not in rec:
                    continue
                v = rec[key]
                if kind == "json":
                    v = json.dumps(v, ensure_ascii=False)
                cell = ws.cell(ri, ci, v)
                if isinstance(v, str) and len(v) > 24:
                    cell.alignment = Alignment(vertical="top", wrap_text=True)
        ws.freeze_panes = "A2"

    battle_rows, enemy_rows, slot_rows, card_rows, artifact_rows = [], [], [], [], []
    for path in sorted(glob.glob(os.path.join(BATTLES_DIR, "*.json"))):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        fname = os.path.splitext(os.path.basename(path))[0]
        brow = {"file": fname}
        for key, _h, kind in BATTLE_FIELDS:
            if key in ("file",):
                continue
            if key in data:
                brow[key] = data[key]
        battle_rows.append(brow)
        for i, e in enumerate(data.get("enemies", [])):
            row = {"battle": fname, "idx": i}
            row.update(e)
            enemy_rows.append(row)
        for i, s in enumerate(data.get("slots", [])):
            row = {"battle": fname, "idx": i}
            row.update(s)
            slot_rows.append(row)
        for i, c in enumerate(data.get("cards", [])):
            row = {"battle": fname, "idx": i}
            row.update(c)
            card_rows.append(row)

    lib_card_rows = []
    extra_path = os.path.join(BATTLES_DIR, "_extra.json")
    if os.path.isfile(extra_path):
        with open(extra_path, encoding="utf-8") as f:
            for i, c in enumerate(json.load(f).get("cards", [])):
                row = {"idx": i}
                row.update(c)
                lib_card_rows.append(row)

    art_path = os.path.join(ROOT, "data", "artifacts.json")
    if os.path.isfile(art_path):
        with open(art_path, encoding="utf-8") as f:
            artifact_rows = json.load(f)
    ritual_rows = []
    for path in sorted(glob.glob(os.path.join(RITUALS_DIR, "*.json"))):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        row = {"file": os.path.splitext(os.path.basename(path))[0]}
        row.update(data)
        ritual_rows.append(row)

    for name, fields, rows in (("battle", BATTLE_FIELDS, battle_rows),
                               ("enemy", ENEMY_FIELDS, enemy_rows),
                               ("slot", SLOT_FIELDS, slot_rows),
                               ("card", CARD_FIELDS, card_rows),
                               ("artifact", ARTIFACT_FIELDS, artifact_rows),
                               ("ritual", RITUAL_FIELDS, ritual_rows),
                               ("library_card", LIBRARY_CARD_FIELDS, lib_card_rows)):
        ws = wb.create_sheet(name)
        put(ws, fields, rows)
    os.makedirs(os.path.dirname(XLSX), exist_ok=True)
    wb.save(XLSX)
    print(f"[init] 已生成 {XLSX}：{len(battle_rows)} 场次 / {len(enemy_rows)} 波 / "
          f"{len(slot_rows)} 槽 / {len(card_rows)} 卡 / {len(artifact_rows)} 器物 / "
          f"{len(ritual_rows)} 仪式 / {len(lib_card_rows)} 补充卡")


if __name__ == "__main__":
    if "--init" in sys.argv:
        build_xlsx()
    else:
        export()
