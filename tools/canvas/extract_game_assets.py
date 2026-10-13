#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把《逢魔退治帖》游戏内已接入的素材登记到 Asset Canvas 画布。

只登记 res://assets/ 之下、游戏运行时真实读取的素材：人物原图、敌方原图、
NPC立绘、2D背景与遮罩、3D阶段模型与贴图、战斗特效图集、UI贴图、序列帧与过场视频。
不复制、不移动、不改写任何原始文件；assets.json 只记录项目相对路径。

排除项（不进入画布）：assets/skill_art_exports/（catalog 标注 binding_status=unbound，
游戏未引用）、build/ 下的抠像与生成实验候选（当前游戏未引用）。

用法：
    python tools/canvas/extract_game_assets.py            # 使用 canvas/index.json 里的第一块画板
    python tools/canvas/extract_game_assets.py --dry-run  # 只打印统计，不写文件
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
from typing import Any

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CANVAS = os.path.join(ROOT, "canvas")

DOC_ID = "game-asset-index"
DOC_NODE_ID = "node-game-asset-index"
INTRO_NODE_ID = "node-canvas-readme"

# 本脚本生成的素材ID前缀。重跑时按此前缀回收已下线条目，避免改名后留下重复/失效节点。
GENERATED_PREFIXES = (
	"char-", "enemy-", "npc-", "bg-", "stage-", "tex-",
	"spell-", "ui-", "fx-", "video-",
)

COL_W = 360
COL_H = 300
HEADER_W = 340
HEADER_GAP = 30
MAX_COLS = 7


# --------------------------------------------------------------------------- 文件工具

def rel(path: str) -> str:
	return path.replace("\\", "/")


def strip_res(path: str) -> str:
	"""清单内可能写成 res:// 前缀，统一去掉并转成正斜杠。"""
	return rel(path).replace("res://", "", 1)


def abspath(project_rel: str) -> str:
	return os.path.join(ROOT, project_rel.replace("/", os.sep))


def read_json(project_rel: str) -> Any:
	with open(abspath(project_rel), "r", encoding="utf-8") as handle:
		return json.load(handle)


def read_res_json(res_path: str) -> tuple[str, Any]:
	"""读取清单内以 res:// 开头的路径，返回去掉前缀的项目相对路径。"""
	project_rel = rel(res_path).replace("res://", "", 1)
	return project_rel, read_json(project_rel)


def png_size(project_rel: str) -> tuple[int, int] | None:
	try:
		with open(abspath(project_rel), "rb") as handle:
			head = handle.read(26)
	except OSError:
		return None
	if len(head) < 26 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
		return None
	return struct.unpack(">II", head[16:24])


def file_bytes(project_rel: str) -> int:
	try:
		return os.path.getsize(abspath(project_rel))
	except OSError:
		return 0


def media_type(project_rel: str) -> str:
	ext = os.path.splitext(project_rel)[1].lower()
	if ext in (".glb", ".gltf"):
		return "model"
	if ext in (".ogv", ".mp4", ".webm"):
		return "video"
	return "image"


def fmt_size(width: int, height: int) -> str:
	return f"{width}×{height}"


def fmt_bytes(count: int) -> str:
	if count >= 1024 * 1024:
		return f"{count / (1024 * 1024):.1f} MB"
	if count >= 1024:
		return f"{count / 1024:.0f} KB"
	return f"{count} B"


# --------------------------------------------------------------------------- 采集器

class Collector:
	def __init__(self) -> None:
		self.assets: dict[str, dict[str, Any]] = {}
		self.sections: list[dict[str, Any]] = []

	def add(self, asset_id: str, name: str, path: str, description: str) -> str | None:
		"""登记一个素材；文件缺失时跳过并记录警告。"""
		if not os.path.isfile(abspath(path)):
			missing.append(path)
			return None
		if asset_id in self.assets:
			raise ValueError(f"素材ID重复：{asset_id}")
		if not path.startswith("assets/"):
			raise ValueError(f"素材必须在 assets/ 下：{path}")
		self.assets[asset_id] = {
			"name": name,
			"path": path,
			"description": description,
		}
		return asset_id

	def section(self, title: str, description: str, items: list[dict[str, Any]]) -> None:
		if items:
			self.sections.append({"title": title, "description": description, "items": items})

	def image_item(self, asset_id: str) -> dict[str, Any] | None:
		entry = self.assets.get(asset_id)
		if entry is None:
			return None
		return {"id": asset_id, "kind": "asset", "mediaType": media_type(entry["path"])}


missing: list[str] = []


# --------------------------------------------------------------------------- 各分区

def collect_characters(col: Collector) -> None:
	roster = read_json("assets/chars/pixel/roster.json")
	forms = {form["id"]: form for form in roster["forms"]}
	display = {identity["id"]: identity["display_name"] for identity in roster["identities"]}
	form_label = {
		"rinne": "凛音",
		"homura_sword": "焰华·剑形态",
		"homura_mage": "焰华·法师形态",
		"mint": "薄荷",
		"guard": "岑照",
		"healer": "苏合",
		"controller": "清明",
	}
	items: list[dict[str, Any]] = []
	for form_id, form in forms.items():
		manifest_path = form["manifest"].replace("res://", "")
		manifest = read_json(manifest_path)
		frames_dir = manifest["dir"].replace("res://", "")
		canvas = manifest["canvas"]
		who = form_label.get(form_id, display.get(form.get("identity_id", ""), form_id))
		identity_id = form.get("identity_id", form_id)
		for anim_key, suffix, role in (
			("idle", "idle", "待机首帧（对话半身取景来源）"),
			("attack", "attack", "攻击动作首帧"),
			("down", "down", "倒地单帧"),
		):
			anim = manifest.get("anims", {}).get(anim_key)
			if not anim or not anim.get("frames"):
				continue
			frame = anim["frames"][0]
			path = rel(os.path.join(frames_dir, frame + ".png"))
			asset_id = f"char-{form_id.replace('_', '-')}-{suffix}"
			size = png_size(path)
			desc = (
				f"生产素材｜游戏内实际读取。\n"
				f"身份 {who}（{identity_id}），形态 {form_id}。\n"
				f"角色：{role}；动作清单见 {rel(manifest_path)} 的 anims.{anim_key}。\n"
				f"逐帧画布 {fmt_size(canvas['w'], canvas['h'])}，脚锚 {canvas['anchor']}，"
				f"身高标尺 {canvas.get('height_m')} m；动作图集在同级 atlases/ 下。"
			)
			if size:
				desc += f"\n本帧像素 {fmt_size(*size)}，{fmt_bytes(file_bytes(path))}。"
			if col.add(asset_id, f"{who}·{role}", path, desc):
				items.append(col.image_item(asset_id))
	col.section(
		"主角七形态逐帧",
		"六身份七形态的高清逐帧动画原图。每个形态取待机首帧、攻击首帧、倒地单帧三张，"
		"帧号与时长以各形态 manifest.json 为准；同目录 atlases/ 是运行时合成的图集。",
		items,
	)


def collect_ch1_enemies(col: Collector) -> None:
	manifest = read_json("assets/chars/enemies/current/asset_manifest.json")
	items: list[dict[str, Any]] = []
	for asset in manifest["assets"]:
		enemy_id = asset["enemy_id"]
		path = rel(os.path.join("assets/chars/enemies/current", asset["image"]))
		width, height = asset["dimensions"]
		asset_id = f"enemy-ch1-{enemy_id.replace('_', '-')}"
		desc = (
			f"生产素材｜游戏内实际读取的第一章敌方原图（approved static art）。\n"
			f"{asset.get('display_name', enemy_id)}，敌人ID {enemy_id}，朝向 {asset.get('direction')}。\n"
			f"{width}×{height} RGBA，透明像素 {asset.get('transparent_pixel_count')}；"
			f"来源与哈希见 assets/chars/enemies/current/asset_manifest.json（sha256 前16位 {asset['sha256'][:16]}）。\n"
			f"实际提示词：{asset.get('actual_prompt', '')}。"
		)
		if col.add(asset_id, f"第一章敌方·{asset.get('display_name', enemy_id)}", path, desc):
			items.append(col.image_item(asset_id))
	col.section(
		"第一章敌方原图",
		"六张已批准的最终静态敌方图，RGBA 透明底、朝右，战斗与地图共用同一批字节。",
		items,
	)


def collect_saga_enemies(col: Collector) -> None:
	manifest_path = "assets/chars/enemies/saga/asset_manifest.json"
	manifest = read_json(manifest_path)
	groups: dict[str, list[tuple[str, str]]] = {}
	for enemy_id, entry in manifest["enemies"].items():
		sheet = strip_res(entry["sheet"])
		groups.setdefault(sheet, []).append((enemy_id, entry.get("speaker", enemy_id)))
	items: list[dict[str, Any]] = []
	for sheet in sorted(groups):
		names = groups[sheet]
		size = png_size(sheet)
		region_text = "；".join(
			"%s=%s" % (speaker, manifest["enemies"][enemy_id]["region"]) for enemy_id, speaker in names
		)
		asset_id = "enemy-saga-" + os.path.splitext(os.path.basename(sheet))[0].replace("_", "-")
		title = "／".join(speaker for _, speaker in names)
		desc = (
			f"生产素材｜游戏内实际读取的后六章敌方图集。\n"
			f"同一张图集内按 region 切出 {len(names)} 个敌种：{title}。\n"
			f"切分区域与脚锚：{region_text}。\n"
			f"图集像素 {fmt_size(*size) if size else '未知'}；登记来源见 {manifest_path}。"
		)
		if col.add(asset_id, f"后六章敌方·{title}", sheet, desc):
			items.append(col.image_item(asset_id))
	col.section(
		"后六章敌方图集",
		"八张图集，每张承载一到两个敌种；运行时按 asset_manifest.json 的 region/anchor 局部取用，不整张拉伸。",
		items,
	)


def collect_ch1_npcs(col: Collector) -> None:
	manifest_path = "assets/chars/npcs/act_one/asset_manifest.json"
	manifest = read_json(manifest_path)
	items: list[dict[str, Any]] = []
	for asset in manifest["assets"]:
		npc_id = asset["id"]
		label = asset.get("label", npc_id)
		width, height = asset["canvas"]
		for suffix, role in (("world", "地图全身精灵"), ("half", "对白半身立绘")):
			file_name = asset["file"] if suffix == "world" else f"{npc_id}_half.png"
			path = rel(os.path.join("assets/chars/npcs/act_one", file_name))
			asset_id = f"npc-ch1-{npc_id}-{suffix}"
			size = png_size(path)
			desc = (
				f"生产素材｜游戏内实际读取。\n"
				f"{label}（{npc_id}）的{role}。\n"
				f"画布 {width}×{height}，身高标尺 {asset.get('height_cm')} cm，"
				f"头顶 {asset.get('crown_px')}，脚底 {asset.get('sole_pixel_px')}，落地锚 {asset.get('anchor_px')}。\n"
				f"来源与审阅记录见 {manifest_path}（sha256 前16位 {asset.get('sha256', '')[:16]}）。"
			)
			if size:
				desc += f"\n本图像素 {fmt_size(*size)}。"
			if col.add(asset_id, f"{label}·{role}", path, desc):
				items.append(col.image_item(asset_id))
	col.section(
		"第一章 NPC",
		"两名普通成年NPC，地图全身与对白半身分离绘制，独立生成、未复用敌图或主角素材。",
		items,
	)


def collect_saga_npcs(col: Collector) -> None:
	manifest_path = "assets/chars/npcs/saga/asset_manifest.json"
	manifest = read_json(manifest_path)
	groups: dict[str, list[str]] = {}
	for speaker, entry in manifest["characters"].items():
		groups.setdefault(strip_res(entry["sheet"]), []).append(speaker)
	items: list[dict[str, Any]] = []
	for sheet in sorted(groups):
		speakers = sorted(groups[sheet])
		entries = [
			manifest["characters"][name]
			for name in manifest["characters"]
			if strip_res(manifest["characters"][name]["sheet"]) == sheet
		]
		width, height = entries[0]["canvas"]
		region_text = "；".join(
			"%s 地图%s / 半身%s" % (name, entry["world_region"], entry["portrait_region"])
			for name, entry in zip(
				[name for name in manifest["characters"] if strip_res(manifest["characters"][name]["sheet"]) == sheet],
				entries,
			)
		)
		asset_id = "npc-saga-" + os.path.splitext(os.path.basename(sheet))[0].replace("_", "-")
		title = "／".join(speakers)
		desc = (
			f"生产素材｜游戏内实际读取的后六章NPC图集。\n"
			f"同图集内含 {len(speakers)} 名角色：{title}。\n"
			f"每人分地图全身区域与对白半身区域：{region_text}。\n"
			f"图集画布 {width}×{height}；坐标约定与目检记录见 {manifest_path}。"
		)
		if col.add(asset_id, f"后六章NPC·{title}", sheet, desc):
			items.append(col.image_item(asset_id))
	col.section(
		"后六章 NPC 图集",
		"十二张图集，每张两名角色的双视图；运行时按 world_region / portrait_region 局部取用。",
		items,
	)


def collect_backgrounds(col: Collector) -> None:
	groups = [
		(
			"战斗/行走背景",
			"res://assets/bg/ 根目录的直接舞台背景，战斗背景由 data/battles/*.json 的 bg 字段引用。",
			[
				("bg-approach-battle", "参道·战斗背景", "assets/bg/approach_battle.png", "第一章参道战斗背景"),
				("bg-approach-l2-test", "参道·l2 分层试样", "assets/bg/approach/l2_test.png", "参道分层背景试样层"),
				("bg-corridor-battle", "回廊·战斗背景", "assets/bg/corridor_battle_test.png", "回廊战斗背景"),
				("bg-corridor-walk", "回廊·行走背景", "assets/bg/corridor_walk.png", "回廊行走舞台背景"),
				("bg-honden-battle", "本殿·战斗背景", "assets/bg/honden_battle.png", "本殿战斗背景"),
				("bg-honden-dusk", "本殿·黄昏背景", "assets/bg/honden_dusk.png", "本殿黄昏氛围背景"),
				("bg-mountain-far", "参道·远景", "assets/bg/mountain_path/far.png", "上山路远景层"),
				("bg-mountain-arch", "参道·鸟居", "assets/bg/mountain_path/arch.png", "上山路鸟居前景层"),
			],
		),
		(
			"前景视差层",
			"scripts/scenes/stage_scene.gd 按 res://assets/bg/parallax/<舞台id>_fg1.png 约定加载的透明前景层。",
			[
				("bg-parallax-approach-fg1", "参道·前景层", "assets/bg/parallax/test_approach_fg1.png", "舞台 test_approach 的 fg1"),
				("bg-parallax-corridor-fg1", "回廊·前景层", "assets/bg/parallax/corridor_act_fg1.png", "舞台 corridor_act 的 fg1"),
				("bg-parallax-honden-fg1", "本殿·前景层", "assets/bg/parallax/honden_act_fg1.png", "舞台 honden_act 的 fg1"),
				("bg-parallax-mountain-fg1", "上山路·前景层", "assets/bg/parallax/mountain_path_fg1.png", "舞台 mountain_path 的 fg1"),
			],
		),
		(
			"遮挡层",
			"场景内用于遮挡角色的透明遮挡图，由舞台配置指定层级。",
			[
				("bg-occluder-honden", "本殿遮挡 o0", "assets/bg/occluders/honden_act_o0.png", "本殿舞台遮挡层"),
				("bg-occluder-approach-o0", "参道遮挡 o0", "assets/bg/occluders/test_approach_o0.png", "参道舞台遮挡层 o0"),
				("bg-occluder-approach-o1", "参道遮挡 o1", "assets/bg/occluders/test_approach_o1.png", "参道舞台遮挡层 o1"),
			],
		),
		(
			"可行走遮罩",
			"scripts/scenes/stage_scene.gd 按 res://assets/bg/walkmasks/<舞台id>.png 读取：白色为可行走面，顶缘高度即落脚高度。",
			[
				("bg-walkmask-approach", "参道可行走遮罩", "assets/bg/walkmasks/test_approach.png", "舞台 test_approach 行走遮罩"),
				("bg-walkmask-corridor", "回廊可行走遮罩", "assets/bg/walkmasks/corridor_act.png", "舞台 corridor_act 行走遮罩"),
				("bg-walkmask-honden", "本殿可行走遮罩", "assets/bg/walkmasks/honden_act.png", "舞台 honden_act 行走遮罩"),
				("bg-walkmask-mountain", "上山路可行走遮罩", "assets/bg/walkmasks/mountain_path.png", "舞台 mountain_path 行走遮罩"),
			],
		),
	]
	for title, description, entries in groups:
		items = []
		for asset_id, name, path, role in entries:
			size = png_size(path)
			desc = (
				f"生产素材｜游戏内实际读取：{role}。\n"
				f"分组说明：{description}\n"
				f"路径 {path}。"
			)
			if size:
				desc += f"像素 {fmt_size(*size)}。"
			if col.add(asset_id, name, path, desc):
				items.append(col.image_item(asset_id))
		col.section(title, description, items)


def collect_stages(col: Collector) -> None:
	model_items: list[dict[str, Any]] = []
	stage_names = {
		"act01_approach": "第一幕 参道",
		"night02_corridor": "第二夜 回廊",
		"night02_corridor_hd2d": "第二夜 回廊 HD2D 变体",
		"night03_procession": "第三夜 送葬行列",
		"night04_mirror": "第四夜 镜殿",
		"night05_honden": "第五夜 本殿",
	}
	for stage, label in stage_names.items():
		path = f"assets/3d/{stage}/{stage}.glb"
		asset_id = f"stage-{stage.replace('_', '-')}-glb"
		desc = (
			f"生产素材｜游戏内实际导入的 3D 阶段模型。\n"
			f"{label}，目录 assets/3d/{stage}/。\n"
			f"GLB 内嵌 PBR 材质与打包纹理，Blender 源与构建脚本在同级 source/（带 .gdignore，不参与导出）。\n"
			f"尺寸 {fmt_bytes(file_bytes(path))}；坐标、锚点与实测预算见目录内 README.md。"
		)
		if col.add(asset_id, f"{label}·GLB", path, desc):
			model_items.append(col.image_item(asset_id))
	col.section(
		"3D 阶段模型",
		"第一章连续寺域的六个 glTF 阶段：上山路、回廊、回廊 HD2D 变体、送葬行列、镜殿、本殿。",
		model_items,
	)

	material_names = {"paper": "和纸", "plaster": "灰泥", "roof": "瓦", "stone": "石", "wood": "木"}
	tex_items: list[dict[str, Any]] = []
	for stage, label in stage_names.items():
		stage_dir = abspath(f"assets/3d/{stage}")
		if not os.path.isdir(stage_dir):
			continue
		for name in sorted(os.listdir(stage_dir)):
			if not name.endswith(".png"):
				continue
			key = name[len(stage) + 1:-4] if name.startswith(stage + "_") else os.path.splitext(name)[0]
			material = material_names.get(key, key)
			path = f"assets/3d/{stage}/{name}"
			asset_id = f"tex-{stage.replace('_', '-')}-{key.replace('_', '-')}"
			size = png_size(path)
			desc = (
				f"生产素材｜3D 阶段贴图：{label}的{material}材质。\n"
				f"路径 {path}；scripts/campaign/act_one_geometry.gd 等脚本按名 preload，"
				f"与同名 GLB 的内嵌贴图对应同一套材质设定。"
			)
			if size:
				desc += f"\n像素 {fmt_size(*size)}，{fmt_bytes(file_bytes(path))}。"
			if col.add(asset_id, f"{label}·{material}贴图", path, desc):
				tex_items.append(col.image_item(asset_id))
	col.section(
		"3D 阶段贴图",
		"各阶段按材质导出的独立贴图（和纸/灰泥/瓦/石/木）；参道阶段只导出 GLB，贴图内嵌在模型内。",
		tex_items,
	)


def collect_spell_atlases(col: Collector) -> None:
	registry_path = "assets/effects/imagegen_spells/registry.json"
	registry = read_json(registry_path)
	root = registry["asset_root"].replace("res://", "")
	form_labels = {
		"rinne": "凛音",
		"homura_sword": "焰华·剑形态",
		"mint": "薄荷",
		"guard": "岑照",
		"healer": "苏合",
		"controller": "清明",
		"homura_mage": "焰华·法师形态",
	}
	items: list[dict[str, Any]] = []

	def register(entry: dict[str, Any], variant_key: str, label: str, note: str) -> None:
		manifest_rel, manifest = read_res_json(entry["manifest"])
		atlas_rel = rel(os.path.join(root, manifest["runtime_atlas"]))
		size = png_size(atlas_rel)
		form_id = manifest.get("form_id", "")
		owner = form_labels.get(form_id, form_id) if form_id else "通用"
		asset_id = "spell-atlas-" + variant_key.replace("_", "-")
		phases = manifest.get("phases", {})
		desc = (
			f"生产素材｜战斗运行时技能图集（registry.json 登记，approved_for_runtime=true，"
			f"gameplay_qa_pending=false）。\n"
			f"技能 {manifest.get('skill_id')}「{manifest.get('skill_name', '')}」，归属 {owner}。\n"
			f"{note}\n"
			f"运行时图集 {atlas_rel}（显示 {entry.get('display_size_px')} px，缩放 {entry.get('runtime_scale')}），"
			f"{manifest.get('frame_count')} 帧。\n"
			f"分相：{'、'.join('%s %s' % (k, v) for k, v in phases.items()) or '无'}；"
			f"清单 {manifest_rel}（sha256 前16位 {entry.get('manifest_sha256', '')[:16]}）。"
		)
		if size:
			desc += f"\n图集像素 {fmt_size(*size)}。"
		if col.add(asset_id, f"{manifest.get('skill_name') or manifest.get('skill_id')}·{owner}图集", atlas_rel, desc):
			items.append(col.image_item(asset_id))

	for skill_id in sorted(registry["effects"]):
		entry = registry["effects"][skill_id]
		variants = entry.get("variants")
		if variants:
			for form_id in sorted(variants):
				owner = form_labels.get(form_id, form_id)
				register(
					variants[form_id],
					f"{form_id}-{skill_id}",
					owner,
					f"近战形态变体：{owner}专属版，与另一近战形态各自独立，不共用美术。",
				)
			continue
		register(entry, skill_id, form_labels.get(entry.get("form_id", ""), "通用"), "单形态通用图集。")
	col.section(
		"技能战斗图集（已接运行时）",
		"imagegen_spells 下 24 个技能、28 个形态变体的运行时图集，全部在 registry.json 中获批并已通过玩法验收。",
		items,
	)


def collect_illustrated_spells(col: Collector) -> None:
	base = "assets/effects/illustrated_spells"
	manifest = read_json(f"{base}/manifest.json")
	columns = manifest["columns"]
	cell_w, cell_h = manifest["cell_size"]
	items: list[dict[str, Any]] = []
	for skill_id in sorted(manifest["actions"]):
		path = f"{base}/{skill_id}.png"
		asset_id = f"spell-illustrated-{skill_id.replace('_', '-')}"
		size = png_size(path)
		desc = (
			f"生产素材｜矢量插画技能序列（scripts/rpg/ui/battle_effects.gd 读取）。\n"
			f"技能 {skill_id}；{manifest['frame_count']} 帧 × {columns} 列，单格 {cell_w}×{cell_h}，"
			f"{manifest['frame_rate']} fps 播放。\n"
			f"来源：{manifest['source']}；alpha {manifest['alpha_mode']}；逐帧哈希见 {base}/manifest.json。"
		)
		if size:
			desc += f"\n图集像素 {fmt_size(*size)}。"
		if col.add(asset_id, f"{skill_id}·插画序列", path, desc):
			items.append(col.image_item(asset_id))
	painterly = f"{base}/../fire_painterly.png"
	if os.path.isfile(abspath("assets/effects/fire_painterly.png")):
		size = png_size("assets/effects/fire_painterly.png")
		desc = "生产素材｜通用火焰笔触贴图。\n路径 assets/effects/fire_painterly.png。"
		if size:
			desc += f"像素 {fmt_size(*size)}。"
		if col.add("fx-fire-painterly", "火焰笔触贴图", "assets/effects/fire_painterly.png", desc):
			items.append(col.image_item("fx-fire-painterly"))
	del painterly
	col.section(
		"矢量插画技能序列",
		"作者矢量曲线直接栅格化的透明技能序列，与上方运行时图集是两套并存的表现素材。",
		items,
	)


def collect_ui(col: Collector) -> None:
	card_ids = []
	card_files = sorted(
		name for name in os.listdir(abspath("assets/ui")) if name.startswith("cardart") and name.endswith(".png")
	)
	items: list[dict[str, Any]] = []
	for name in card_files:
		key = os.path.splitext(name)[0]
		path = f"assets/ui/{name}"
		asset_id = "ui-cardart-" + key.replace("cardart_", "").replace("_", "-")
		size = png_size(path)
		kind = "常驻卡面" if key.startswith("cardart_e") else "遗物/道具卡面"
		desc = (
			f"生产素材｜游戏内实际读取的卡面。\n"
			f"{kind}：{key}；由 data/battles/*.json 与 data/artifacts.json 的 art/icon 字段按 res:// 路径引用。\n"
			f"路径 {path}。"
		)
		if size:
			desc += f"像素 {fmt_size(*size)}。"
		if col.add(asset_id, f"卡面·{key}", path, desc):
			items.append(col.image_item(asset_id))
			card_ids.append(key)
	col.section(
		"战斗卡面",
		f"{len(card_ids)} 张卡面贴图：cardart_e_* 为常驻招式卡，cardart_val_* 为遗物/道具卡。",
		items,
	)

	menu_dir = abspath("assets/ui/night_menu")
	menu_files = sorted(name for name in os.listdir(menu_dir) if name.endswith(".png"))
	items = []
	for name in menu_files:
		key = os.path.splitext(name)[0]
		path = f"assets/ui/night_menu/{name}"
		asset_id = "ui-night-" + key.replace("_", "-")
		size = png_size(path)
		desc = (
			f"生产素材｜夜菜单 UI 贴图。\n"
			f"由 scripts/campaign/presentation/night_menu_art.gd 以 ROOT=res://assets/ui/night_menu/ 统一加载，"
			f"供章节舞台、结案、装配面板、商人面板与队伍面板共用。\n"
			f"贴图名 {key}；路径 {path}。"
		)
		if size:
			desc += f"像素 {fmt_size(*size)}。"
		if col.add(asset_id, f"夜菜单·{key}", path, desc):
			items.append(col.image_item(asset_id))
	col.section(
		"夜菜单 UI",
		f"夜间准备/装配/商人界面的 {len(menu_files)} 张贴图：面板、按钮态、槽位、道具图标与血蓝条。",
		items,
	)

	items = []
	for asset_id, name, path, role in (
		("ui-panel-washi", "和纸九宫格面板", "assets/ui/panel_washi_9slice.png", "通用和纸九宫格面板底"),
		("tex-washi-full", "和纸底纹·整幅", "assets/textures/washi_full.png", "和纸底纹整幅贴图"),
		("tex-washi-overlay", "和纸覆盖层", "assets/textures/washi_overlay.png", "和纸覆盖/做旧层"),
	):
		size = png_size(path)
		desc = f"生产素材｜游戏内实际读取：{role}。\n路径 {path}。"
		if size:
			desc += f"像素 {fmt_size(*size)}。"
		if col.add(asset_id, name, path, desc):
			items.append(col.image_item(asset_id))
	col.section(
		"和纸与面板底纹",
		"界面统一使用的和纸底纹与九宫格面板，供各面板共用同一套纸质观感。",
		items,
	)


def collect_fx(col: Collector) -> None:
	groups = [
		("bell", "钟波", "bell_wave"),
		("fire", "火焰爆裂", "fire_burst"),
		("seal", "封印爆裂", "seal_burst"),
	]
	items: list[dict[str, Any]] = []
	for prefix, label, base in groups:
		for name in sorted(os.listdir(abspath("assets/fx"))):
			if not name.startswith(base) or not name.endswith(".png") or name.startswith("_raw"):
				continue
			suffix = name[len(base):].replace(".png", "").strip("_")
			path = f"assets/fx/{name}"
			asset_id = f"fx-{base.replace('_', '-')}-{suffix.lower()}"
			size = png_size(path)
			desc = (
				f"生产素材｜战斗序列帧特效（scripts/scenes/battle_canvas.gd 按 res://assets/fx/ + 文件名 加载）。\n"
				f"{label}序列第 {suffix[1:]} 帧。\n"
				f"路径 {path}；原始合表保留在同目录 _raw_{base}_sheet.png。"
			)
			if size:
				desc += f"像素 {fmt_size(*size)}。"
			if col.add(asset_id, f"{label}·帧{suffix[1:]}", path, desc):
				items.append(col.image_item(asset_id))
		for name in sorted(os.listdir(abspath("assets/fx"))):
			if name != f"_raw_{base}_sheet.png":
				continue
			path = f"assets/fx/{name}"
			asset_id = f"fx-raw-{base.replace('_', '-')}-sheet"
			size = png_size(path)
			desc = (
				f"生产素材｜{label}序列的原始合表留档。\n"
				f"路径 {path}；运行时使用拆出的单帧文件，本图仅供对照与回溯。"
			)
			if size:
				desc += f"像素 {fmt_size(*size)}。"
			if col.add(asset_id, f"{label}·原始合表", path, desc):
				items.append(col.image_item(asset_id))
	col.section(
		"战斗序列帧特效",
		"钟波、火焰爆裂、封印爆裂三组逐帧特效；运行时按帧名加载，原始合表一并留档。",
		items,
	)


def collect_video(col: Collector) -> None:
	items: list[dict[str, Any]] = []
	skipped: list[str] = []
	for asset_id, name, path, role in (
		("video-night1-stone-bowl", "第一夜·石钵过场", "assets/cutscenes/night1_stone_bowl.ogv",
			"Ogg Theora 过场，由 scripts/campaign/cutscene_catalog.gd 在导出包中优先读 EXE 旁的 cutscenes/ 目录"),
		("video-night1-quote", "第一夜·15秒引用片段", "assets/cutscenes/night1_cutscene_15s_quote_only.mp4",
		 "第一夜过场的引用片段留档"),
	):
		if not os.path.isfile(abspath(path)):
			skipped.append(f"{path}（文件不存在）")
			continue
		if os.path.splitext(path)[1].lower() == ".ogv":
			# 画布媒体组件不支持 Ogg Theora，只在分区说明里登记路径。
			skipped.append(f"{path}（画布不支持 Ogg Theora 预览，仅登记路径）")
			continue
		desc = f"生产素材｜游戏内过场视频：{role}。\n路径 {path}，{fmt_bytes(file_bytes(path))}。"
		if col.add(asset_id, name, path, desc):
			items.append(col.image_item(asset_id))
	description = "assets/cutscenes/ 下的过场影片；目录内 .gitignore 与 EXE 旁 cutscenes/ 的外置读取约定见 cutscene_catalog.gd。"
	if skipped:
		description += "\n以下文件存在于仓库但未做成画布节点：" + "；".join(skipped) + "。"
	col.section("过场视频", description, items)


# --------------------------------------------------------------------------- 写文件

def build_document(col: Collector, board_name: str) -> str:
	lines = [
		"# 游戏内素材索引",
		"",
		"本文件由 `tools/canvas/extract_game_assets.py` 依据仓库实际文件与各素材自带的清单生成，"
		"只登记 `assets/` 下游戏运行时真实读取的素材；不复制、不移动、不改写原始文件。",
		"",
		f"画板：`{board_name}`。共 {len(col.assets)} 个已登记素材。",
		"",
		"## 排除说明",
		"",
		"- `assets/skill_art_exports/`：其 `catalog.json` 自述 `binding_status: unbound`，游戏代码未引用，故不进画布。",
		"- `build/libtv/` 下的抠像与生成实验候选：当前游戏未引用，按项目约定不作为生产素材登记。",
		"- 各目录的 `*.import`、Blender `source/` 源文件与验收记录：不作为运行时素材登记。",
		"",
	]
	for section in col.sections:
		lines.append(f"## {section['title']}")
		lines.append("")
		lines.append(section["description"])
		lines.append("")
		for item in section["items"]:
			entry = col.assets[item["id"]]
			lines.append(f"### {entry['name']}")
			lines.append("")
			lines.append(f"`{entry['path']}`")
			lines.append("")
			lines.append(entry["description"])
			lines.append("")
			lines.append(f"![{entry['name']}](../../{entry['path']})")
			lines.append("")
	return "\n".join(lines)


def write_json(path: str, payload: Any) -> None:
	with open(path, "w", encoding="utf-8", newline="\n") as handle:
		json.dump(payload, handle, ensure_ascii=False, indent=2)
		handle.write("\n")


def main() -> int:
	parser = argparse.ArgumentParser(description="把游戏内素材登记到 Asset Canvas 画布")
	parser.add_argument("--board-id", default=None, help="目标画板ID，默认取 index.json 的第一块")
	parser.add_argument("--dry-run", action="store_true", help="只统计不写文件")
	args = parser.parse_args()

	index_path = os.path.join(CANVAS, "index.json")
	index = read_json("canvas/index.json")
	board_id = args.board_id or index["boards"][0]["id"]
	board_name = next((b["name"] for b in index["boards"] if b["id"] == board_id), board_id)

	col = Collector()
	collect_characters(col)
	collect_ch1_enemies(col)
	collect_saga_enemies(col)
	collect_ch1_npcs(col)
	collect_saga_npcs(col)
	collect_backgrounds(col)
	collect_stages(col)
	collect_spell_atlases(col)
	collect_illustrated_spells(col)
	collect_ui(col)
	collect_fx(col)
	collect_video(col)

	total = sum(len(section["items"]) for section in col.sections)
	print(f"画板 {board_id}（{board_name}）")
	for section in col.sections:
		print(f"  {len(section['items']):>3}  {section['title']}")
	print(f"合计 {total} 个素材节点 / {len(col.sections)} 个分区")
	if missing:
		print("缺失文件（已跳过）：")
		for path in sorted(set(missing)):
			print("  -", path)
	if args.dry_run:
		return 0

	# assets.json：只新增/更新本脚本登记的条目，保留其它既有条目。
	assets_path = os.path.join(CANVAS, "assets.json")
	assets = read_json("canvas/assets.json") if os.path.isfile(assets_path) else {"version": 1, "assets": {}}
	produced = set(col.assets)
	retired = sorted(
		asset_id for asset_id in assets["assets"]
		if asset_id not in produced and asset_id.startswith(GENERATED_PREFIXES)
	)
	for asset_id in retired:
		del assets["assets"][asset_id]
	for asset_id, entry in col.assets.items():
		assets["assets"][asset_id] = entry
	write_json(assets_path, assets)
	if retired:
		print("回收本脚本此前生成、现已下线的条目：" + "、".join(retired))

	# 画板节点：保留非本脚本生成的既有节点。
	board_path = os.path.join(CANVAS, "boards", f"{board_id}.json")
	board = read_json(f"canvas/boards/{board_id}.json")
	generated_ids = {INTRO_NODE_ID, DOC_NODE_ID} | produced | set(retired)
	# 分区标题ID带序号，旧版脚本用随机hash生成，这里一并回收，避免重复标题节点。
	kept = [
		node for node in board.get("nodes", [])
		if node.get("id") not in generated_ids and not str(node.get("id", "")).startswith("section-")
	]

	nodes: list[dict[str, Any]] = list(kept)
	nodes.append({
		"id": INTRO_NODE_ID,
		"type": "text",
		"title": "画布说明：游戏内素材提取",
		"description": "本画板由 tools/canvas/extract_game_assets.py 生成，登记 assets/ 下游戏运行时真实读取的素材。",
		"data": {
			"text": (
				"本画板收录《逢魔退治帖》游戏内已接入的素材原文件。\n\n"
				"· 只登记 assets/ 之下、游戏运行时真实读取的素材；不复制、不移动、不改写任何原始文件。\n"
				"· 每个素材节点都是本地文件引用（canvas/assets.json 记录项目相对路径），可直接查看原图。\n"
				"· assets/skill_art_exports/ 与 build/ 下的实验候选未被游戏引用，因此不在画板内。\n"
				"· 详细清单与逐项说明见同画板的《游戏内素材索引》文档。"
			),
			"instruction": "这是素材索引画布的新增说明，保留并与其它分区一同维护。",
		},
	})
	nodes.append({
		"id": DOC_NODE_ID,
		"type": "document",
		"title": "游戏内素材索引",
		"description": "按分区列出的游戏内素材清单：路径、像素尺寸、来源清单与游戏内用途。",
		"data": {"documentId": DOC_ID},
	})

	layout: dict[str, dict[str, float]] = {}
	x, y = 0, 0
	if kept:
		x, y = 0, 0
	layout[INTRO_NODE_ID] = {"x": x, "y": y, "width": 560, "height": 300}
	layout[DOC_NODE_ID] = {"x": x + 600, "y": y, "width": 700, "height": 300}
	y += 340

	for index_section, section in enumerate(col.sections, start=1):
		digest = hashlib.md5(section["title"].encode("utf-8")).hexdigest()[:8]
		header_id = f"section-{index_section}-{digest}"
		nodes.append({
			"id": header_id,
			"type": "text",
			"title": section["title"],
			"description": f"分区说明：{section['description']}",
			"data": {
				"text": f"{section['description']}\n\n本分区共 {len(section['items'])} 个素材节点。",
				"instruction": "分区标题节点，用于在画布上分隔素材组，不生成新素材。",
			},
		})
		layout[header_id] = {"x": x, "y": y, "width": HEADER_W, "height": 260}
		for slot, item in enumerate(section["items"]):
			node_id = item["id"]
			nodes.append({
				"id": node_id,
				"type": "asset",
				"title": col.assets[node_id]["name"],
				"description": col.assets[node_id]["description"],
				"data": {"assetId": node_id, "mediaType": item["mediaType"]},
			})
			row, column = divmod(slot, MAX_COLS)
			layout[node_id] = {
				"x": x + HEADER_W + HEADER_GAP + column * COL_W,
				"y": y + row * COL_H,
				"width": 330,
				"height": 280,
			}
		rows = (len(section["items"]) + MAX_COLS - 1) // MAX_COLS
		y += max(1, rows) * COL_H + 90

	board["nodes"] = nodes
	board.setdefault("edges", [])
	write_json(board_path, board)

	# 文档与画板布局
	os.makedirs(os.path.join(CANVAS, "documents"), exist_ok=True)
	with open(os.path.join(CANVAS, "documents", f"{DOC_ID}.md"), "w", encoding="utf-8", newline="\n") as handle:
		handle.write(build_document(col, board_name))
	if not any(item["id"] == DOC_ID for item in index.get("documents", [])):
		index.setdefault("documents", []).append({"id": DOC_ID, "title": "游戏内素材索引"})
	write_json(index_path, index)

	editor_path = os.path.join(CANVAS, "editor", f"{board_id}.json")
	editor = read_json(f"canvas/editor/{board_id}.json") if os.path.isfile(editor_path) else {
		"version": 1, "nodes": {}, "viewport": {"x": 64, "y": 32, "zoom": 1}, "view": "canvas"
	}
	editor_nodes = {
		k: v for k, v in editor.get("nodes", {}).items()
		if k not in generated_ids and not k.startswith("section-")
	}
	editor_nodes.update(layout)
	editor["nodes"] = editor_nodes
	write_json(editor_path, editor)

	print(f"已写入：canvas/assets.json（{len(assets['assets'])} 条）、"
		f"canvas/boards/{board_id}.json（{len(nodes)} 节点）、"
		f"canvas/documents/{DOC_ID}.md、canvas/editor/{board_id}.json")
	return 0


if __name__ == "__main__":
	sys.exit(main())
