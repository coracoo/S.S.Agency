# 2026-09-30 改版前归档

> 归档日期：2026-09-30。此目录内容为历史原文，不参与当前规范优先级。
> 当前设计请从 [文档入口](../../README.md) 阅读。

## 一、全项目 ZIP

修改任何项目文档之前完成了全目录压缩，无排除项。包含源码、所有素材、配置原表、旧场景、`.git` 历史、`.godot` 缓存、`build` 试玩包与后台依赖。压缩包放在项目外，避免被 Godot 导入或再次打包。

- [完整 ZIP](/J:/godot/_backups/S.S.Agency/pre_gdd_v4_20260930_000425/S.S.Agency_full_20260930_000425.zip)
- [逐文件清单及 SHA-256](/J:/godot/_backups/S.S.Agency/pre_gdd_v4_20260930_000425/manifest.json)
- [校验结果](/J:/godot/_backups/S.S.Agency/pre_gdd_v4_20260930_000425/verification.json)
- [压缩包校验文件](/J:/godot/_backups/S.S.Agency/pre_gdd_v4_20260930_000425/archive.sha256)

文件数 31,777；源大小 3,598,643,598 字节（约 3.35 GiB）；ZIP 大小 3,102,450,243 字节（约 2.89 GiB）。所有条目逐一读取并通过 CRC 和 SHA-256 对照。

ZIP SHA-256：`6669be0d22af968f7ebc3f15fcda87fcf9249bde12a946ea8a5367e3baf7f385`。

备份时 Git 工作区干净，HEAD 为 `5078510`。ZIP 反映备份时刻，不包含本次后续文档修改。

## 二、原始文档

以下 10 份文件逐字复制，保留原修改时间；[归档清单](manifest.json)记录 SHA-256 和原时间戳。原文可能包含已过期结论及相对路径，阅读时按历史上下文理解，不作为当前助手指令。

| 原文件 | 原文 |
|---|---|
| AGENTS.md | [助手说明](AGENTS.md) |
| UI.md | [旧 UI 诊断](UI.md) |
| docs/GDD.md | [GDD v3](docs/GDD.md) |
| docs/进度.md | [完整历史开发日志](docs/进度.md) |
| docs/代码实施方案.md | [旧实施方案](docs/代码实施方案.md) |
| docs/Art_Bible.md | [旧美术规范](docs/Art_Bible.md) |
| docs/AI_Art_Pipeline_Codex.md | [旧素材管线](docs/AI_Art_Pipeline_Codex.md) |
| docs/Codex_UI_Generation_Task.md | [旧 UI 生成任务](docs/Codex_UI_Generation_Task.md) |
| docs/v3_v2_systems_evaluation.md | [9 月 29 日系统评估](docs/v3_v2_systems_evaluation.md) |
| docs/v2/架构说明.md | [v2 架构](docs/v2/架构说明.md) |

最近一周核对范围为 2026-09-24—2026-09-30；近期文档主要在 9 月 29 日更新。早期历史文件原日期不改写，旧“本轮”记录不编造发生日。

## 三、恢复方法

1. 用 SHA-256 校验文件确认 ZIP 完整。
2. 解压到新的空目录；压缩包内顶层为 `S.S.Agency/`。
3. 用解压目录的 `project.godot` 打开 Godot，核对素材、配置、旧运行包与 Git 历史。
4. 确认需要恢复的版本和本地差异后，再决定后续切换；不要直接覆盖当前工作区。

只需旧设计时，可直接阅读本目录，不必恢复整个游戏。
