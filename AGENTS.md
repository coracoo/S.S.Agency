# AGENTS.md — 《逢魔退治帖》当前项目说明

## 2026-10-05 引擎升级

当前使用 Godot **4.7.2 stable**，4.6.3 保留用于回退。升级对照与原有失败见 [升级评估](docs/godot-4.7-upgrade-report.md)；不能把“未发现新增回归”写成全项目测试通过。

## 2026-10-03 视频素材试作约定

用户指定后续角色动画视频统一使用 LibTV 的 **Minimax H3、768P**（`MiniMax-Hailuo-H3`），通过 `libtv` CLI 操作。首尾帧模式为 `frames2video`，当前最短 5 秒、比例跟随输入；运行前核验实时模型配置。动作优先快速出手、短停顿和连续衔接。旧 Seedance 样片保留用于对照，不覆盖历史生成记录；生成和抽帧结果先放 `build/libtv/`，经检查后再决定是否接入游戏。

## 2026-10-01 可选回合制 RPG 新增说明

原标题仍为默认入口；「回合制 RPG 试作」显式进入独立六职业/24固定技能的新模式。新规则在 `scripts/rpg/`、`data/rpg/`，新场景在 `scenes/rpg/`，新档只写 `user://rpg_v1/`。四张固定技能卡不抽牌、不共享行动点；原卡牌模式、故事/谜题、美术、xlsx管线、3D预览保留。以下历史说明仍描述对应旧基线，不能把新模式误写成旧默认战斗已替换。

实际入口与隔离命令见 [RPG说明](docs/rpg/README.md)，最终覆盖与限制见 [验证报告](docs/rpg/verification-2026-09-30.md)。测试必须从 `tools/rpg/run_checks.py` 开始，先核验临时 `user://`；不要对真实旧玩家档运行写档/清理回归。

更新：2026-10-05。全部沟通、技术说明与新增注释以中文为主。

## 当前主线与事实优先级

当前唯一玩家入口是 `res://scenes/campaign/title.tscn`：开始新游戏、继续游戏、退出。
第一章五夜共用连续3D寺域，原上山路→山门前庭→回廊/镜殿/纸棺庭/本殿可自由双向行走。调查/对白→RPG战斗→战前原位置返场；本夜完成后原地推进夜次，首次开场按实地抵达触发。第二夜守灯仍为三步场景互动，第五夜后有送行与镇守两结局。
六身份选三人与焰华双形态沿用现有RPG核心。当前实现、已验项目和未验项目分别说明，不把模型E2E当成人工GUI全通。

- 连续地图：[设计](docs/superpowers/specs/2026-10-05-act-one-connected-world-design.md)、[实施与验收](docs/superpowers/plans/2026-10-05-act-one-connected-world.md)
- UI与场景精修：[当前表现与版本说明](docs/campaign/ui-atmosphere.md)
- 原五夜批准范围：[五夜主线规范](docs/superpowers/specs/2026-10-04-five-night-3d-design.md)
- 实施与验收计划：[实施计划](docs/superpowers/plans/2026-10-04-five-night-3d-implementation.md)
- 运行、测试与发布：[主线说明](docs/campaign/README.md)
- 文档入口：[docs/README.md](docs/README.md)

用户最新指令优先。GDD v4、旧v3/2.5D/独立RPG试作说明是设计与历史背景，不再定义默认入口。不要按旧文档恢复卡牌抽牌仪式或试玩菜单。

## 技术基线与代码入口

Godot官方4.6.3基线及4.7.2兼容验证、GDScript；固定Compatibility；1920×1080、canvas_items/expand。启动项目不指定旧场景：

```sh
godot --path .
```

| 内容 | 当前入口 |
|---|---|
| 唯一标题、五夜3D场景、结尾 | `scenes/campaign/`、`scripts/campaign/` |
| 主线唯一登记与会话 | `chapter_catalog.gd`、`chapter_session.gd` |
| RPG规则、路由与存档 | `scripts/rpg/`、`data/rpg/` |
| 3D角色、镜头与共享实现 | `scripts/exploration_3d/player_controller.gd`、`camera_rig.gd`、`scripts/characters/` |
| 七形态原PNG/manifest | `assets/chars/pixel/*/high_detail_complete/` |
| 六最终敌图与来源校验 | `assets/chars/enemies/current/asset_manifest.json` |
| 最新探索/结案正文 | `data/dialogues.json`、`data/cases/night_patrol.json` |
| XLSX编辑源与导出工具 | `config/`、`tools/export_*_xlsx.py` |
| 发布与PCK验证 | `tools/campaign/build_release.py`、`release_pack.py` |

正式档仅用 `user://campaign_v1/slot_01.json`，schema2；新世界map_layout为act_one_connected_v1，旧正式局部世界须先合法校验再一次性坐标迁移。继续只读取正式档。旧卡牌、RPG试作、参道试玩存档不迁移、覆盖或删除。损坏/未知版本必须明确报错，不能当空档覆盖。

## 隔离测试与导入

所有测试从隔离Python入口开始，核验引擎实际user目录之后才写档。不得对真实玩家user目录运行回归或清理。

```sh
python3 tools/rpg/run_checks.py --suite all
python3 tools/campaign/run_checks.py
python3 tools/campaign/run_act_one_checks.py
python3 tools/campaign/run_act_one_geometry_checks.py
python3 tools/campaign/run_presentation_checks.py
python3 tools/campaign/run_presentation_checks.py --dual
python3 tools/campaign/run_end_to_end.py --output-dir /absolute/outside/repo/e2e
python3 -m unittest discover -s tools/campaign -p 'test_*release*.py'
```

`--legacy`用于保留的历史规则/预览检查。`--legacy-contracts`单独诊断已过期的旧默认入口、敌图朝向和回廊直本殿契约；当前版本预期报告契约差异，不作为正式门禁。原断言仍保留，正式替代覆盖见主线说明。

并行Godot导入/导出必须共享外部 `godot-import.lock`；Git提交使用外部 `git-commit.lock`。不要更改其他任务拥有的文件、占用正在人工验收的GUI。

## 发布依赖与历史保护

正式导出采用resources选择，限定campaign场景、RPG battle与解析/实际动态依赖。旧profile兼容脚本有硬preload，保留其代码；旧URI字符串不等同正式资源加载需求。

Godot的include_filter不会自动保留已导入PNG原字节。七形态loader使用FileAccess解码原PNG，必须运行发布工具追加与逐条hash检查。未使用atlas、逐帧ctex重复副本、开发目录/XLSX/raw sheet不随PCK发布，原稿仍留开发仓库。

历史只能按显式manifest移动Git-tracked且已证明无活动依赖的文件；独立可反向撤销commit，禁止永久删除/git clean/移动untracked资料。归档root必须 `.gdignore` 并退出export。

## 代码与内容约定

GDScript使用Tab、snake_case、类PascalCase；复杂状态/坐标逻辑用中文注释。新规则同步真实模型、预览、UI和测试，场景不得直接发奖励或跨夜。

修改前检查Git状态，不覆盖并行/用户dirty文件。不提交`.godot/`、构建包、证据目录、后台依赖。

XLSX管理字段必须同时维护源与JSON，避免以后重导覆盖。当前后台同文件多表写回风险仍保留，本轮不得借后台重写最新对白正文。沿用现有风格和七形态原图，目录名pixel不代表过期。

做3D资源前读[3D管线](docs/3d资产管线规则.md)，检查glTF悬空依赖并实际目检。addons/AsepriteWizard、addons/shaker不随业务任务修改。
