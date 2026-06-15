# AGENTS.md — 封灵事务所（Godnot Tactics）

> 本文档供 AI 编码助手阅读。项目所有技术文档、代码注释、数据文件均以中文为主，请使用中文进行沟通和修改。

## 一、项目概述

**《封灵事务所》** 是一款基于 **Godot 4.6 + GDScript** 开发的港式民俗题材回合制战术 RPG。核心体验是“规则模拟器”：玩家利用环境（火、水、糯米、符纸、铃铛噪音等）与敌人行为规则进行连锁反应，而非单纯依赖角色数值。

- **项目根目录**: `/home/corain/godness/godot-game/`
- **引擎版本**: Godot 4.6（`project.godot` 中 `config/features=PackedStringArray("4.6")`）
- **主场景**: `scenes/main.tscn` → `scripts/scenes/main_scene.gd`
- **战斗场景**: `scenes/battle.tscn` → `scripts/scenes/battle_scene.gd`（4500+ 行，渲染/UI/输入/动画集中在此）
- **运行方式**: 使用 Godot 编辑器打开 `project.godot`，或命令行 `godot --path .` 运行。

## 二、技术栈与运行时架构

### 2.1 技术栈

| 层级 | 技术 |
|------|------|
| 引擎 | Godot 4.6 |
| 脚本语言 | GDScript（全部核心逻辑） |
| 数据配置 | JSON（`data/*.json`） |
| 美术资源 | PNG 精灵表、等距瓦片、AI 生成 UI 素材 |
| 辅助工具 | Python 3 + Pillow（`tools/*.py`）处理素材切分 |
| 版本控制 | Git（当前仅 1 个初始提交） |

### 2.2 核心架构

```
scenes/           # Godot 场景文件
scripts/
  core/           # 纯逻辑层（RefCounted 类，可在编辑器外实例化测试）
  scenes/         # 场景脚本（Node2D/Control 派生，负责渲染和输入）
data/             # 全部数据配置（JSON）
assets/           # 图片、精灵表、瓦片、UI 素材
tools/            # Python 素材处理脚本
docs/             # GDD、实施方案、进度文档
```

### 2.3 Autoload 单例

- `EventBus`（`scripts/core/event_bus.gd`）已在 `project.godot` 中注册为全局 Autoload。所有系统间通信优先通过 EventBus 事件完成，避免直接调用。
- 当前使用的事件名包括：`effect:added`、`object:pushed`、`object:pushed_over`、`object:bell_rung`、`coffin:opened`、`noise:created`、`noise:propagated`、`unit:terrain_damage`、`terrain:apply_status`、`terrain:ai_state` 等。

### 2.4 核心系统职责

| 文件 | 职责 |
|------|------|
| `scripts/core/game_state.gd` | 全局战斗状态：单位、地图、AP、灵气密度、噪音事件、胜负判定 |
| `scripts/core/game_map.gd` | 多层地图（地面/效果/物体/碰撞）+ 标签系统，支持 v1/v2 两种地图格式 |
| `scripts/core/terrain_system.gd` | 读取 `data/rules.json`，按标签匹配触发环境连锁反应（火引燃油、水灭火、爆炸桶等） |
| `scripts/core/interaction_system.gd` | 推/拉/推倒/拾取/放置/互动（铃铛/门/点燃）等环境互动 |
| `scripts/core/noise_system.gd` | 噪音 BFS 传播，影响 AI 状态（search/fear） |
| `scripts/core/spirit_system.gd` | 灵气密度 0-10 管理，分 5 个档位影响敌人属性；棺材开启会大幅涨灵气 |
| `scripts/core/ai_controller.gd` | 敌人 AI：状态机（patrol/search/chase/attack/fear）+ Utility 选点 |
| `scripts/core/turn_manager.gd` | 玩家回合开始/结束、抽牌、状态 tick |
| `scripts/core/card_resolver.gd` | 卡牌目标选择、效果执行、AOE/推拉/地形效果 |
| `scripts/core/card_effect_parser.gd` | 单条卡牌效果的数值解析 |
| `scripts/core/status_effect_manager.gd` | 燃烧/冰冻/中毒/眩晕/减速/护盾等状态效果 |
| `scripts/core/pathfinding.gd` | A* 寻路 + 可达格子计算 |
| `scripts/core/unit.gd` | 单位数据模型（HP/AP/移动/护盾/状态/面向/AI 状态） |
| `scripts/core/unit_factory.gd` | 从 `data/units.json` 和 `data/enemies.json` 创建单位 |
| `scripts/core/deck.gd` / `hand.gd` / `card.gd` / `inventory.gd` | 牌组、手牌、卡牌定义、背包 |
| `scripts/scenes/battle_scene.gd` | 渲染、输入、相机、HUD、动画、音效占位、胜利/失败界面 |

## 三、数据文件说明

所有游戏规则尽量配置化，存放于 `data/` 目录：

| 文件 | 说明 |
|------|------|
| `data/balance.json` | 手牌大小、抽牌数、AP 上限、地形闪避/状态效果参数 |
| `data/cards.json` | 卡牌定义（费用、目标类型、效果、稀有度） |
| `data/units.json` | 4 名玩家角色（凛音/薄荷/焰华/钟馗）的属性、初始牌组、道具、特性 |
| `data/enemies.json` | 敌人定义（纸人/水鬼/僵尸/红衣女/棺材主）+ AI Profile |
| `data/maps.json` | 地图 v2 格式（多层：ground/effects/objects/collision）+ 出生点 |
| `data/terrains.json` | 15 种地形标签、移动消耗、颜色 |
| `data/effects.json` | 7 种地形效果（火焰/水渍/糯米/墨线/符纸/诅咒/爆炸） |
| `data/objects.json` | 7 种环境物体（火盆/水桶/米袋/铃铛/门/棺材/炸药桶） |
| `data/rules.json` | 交互规则表，驱动 TerrainSystem 的连锁反应 |
| `data/statuses.json` | 状态效果定义（伤害/跳过回合/减速等） |

**重要约定**：
- 新增环境交互必须优先进入 `data/rules.json`，禁止在代码中硬编码具体地形名。
- 标签系统使用 `Dictionary` 模拟集合（`{tag: true}`），查询 `has()` 为 O(1)。

## 四、如何运行与测试

### 4.1 运行游戏

1. 确保已安装 Godot 4.6。
2. 打开 Godot 编辑器 → 导入 `project.godot` → 运行主场景。
3. 或命令行：
   ```bash
   godot --path /home/corain/godness/godot-game
   ```

### 4.2 辅助工具

```bash
# 切分高精度精灵表和物体贴图（需要 Pillow）
cd /home/corain/godness/godot-game
python3 tools/build_hires_battle_assets.py

# 从 UI 大图切出独立 UI 素材
python3 tools/slice_ui_atlas.py

# 切分战斗行动 UI v2
python3 tools/slice_battle_action_ui_v2.py
```

依赖：`pip install Pillow`

### 4.3 测试

- **当前没有自动化测试框架**。
- 核心逻辑类（`GameMap`、`TerrainSystem`、`InteractionSystem`、`NoiseSystem`、`SpiritSystem`、`Pathfinding`、`CardResolver` 等）均为 `RefCounted`，可在 GDScript 中直接 `new()` 实例化进行单元测试。
- 验收方式以“运行游戏验证”为主，参考 `docs/进度.md` 中的 Phase 验收标准。

## 五、代码风格约定

### 5.1 命名

- GDScript 文件使用 `snake_case.gd`。
- 类名使用 `PascalCase`（`class_name Unit`）。
- 函数/变量使用 `snake_case`。
- 私有函数/变量以下划线开头（`_private_func`、`_private_var`）。
- 常量使用 `UPPER_SNAKE_CASE`。

### 5.2 缩进与格式

- 使用 Tab 缩进（Godot 默认）。
- 函数参数过多时换行并对齐。
- 字典/数组较长的数据配置放在 JSON 中，不在 GDScript 里写死。

### 5.3 注释

- 复杂算法、规则匹配、坐标转换需要中文注释说明。
- `battle_scene.gd` 中已有较多内联注释；新增 UI/渲染代码请保持类似粒度。

### 5.4 系统间通信

- **优先使用 EventBus 事件**，禁止系统间直接强耦合调用。
- `GameState` 仍保留若干 Godot `signal` 用于 UI 刷新，新功能优先通过 EventBus 后再由 `battle_scene.gd` 监听更新 UI。

### 5.5 数据先行

根据 `docs/代码实施方案.md`，开发流程应为：
1. 先定义 JSON Schema / 数据字段
2. 再写解析代码
3. 最后写逻辑
4. 运行游戏验收

## 六、当前开发进度与已知问题

> 来源：`docs/进度.md`（最后更新 2026-05-31），整体完成度约 37%。

### 6.1 已完成

- 多层地图 + 标签系统（GameMap v2）
- 地形交互规则引擎（TerrainSystem）
- 推/推倒/拾取/放置/互动（InteractionSystem，拉操作仍缺失）
- 噪音传播 BFS（NoiseSystem）
- 灵气密度档位效果（SpiritSystem）
- 卡牌战斗 + 手牌/牌组/背包系统
- 敌人 AI 基础状态机（fear/search/chase/attack）
- 14×10 Demo 地图“纸人抬棺”

### 6.2 主要未完成 / 技术债务

| 问题 | 说明 |
|------|------|
| `battle_scene.gd` 过大 | 4500+ 行，渲染/UI/输入/动画全部集中，应逐步拆分为独立 Control 节点或模块 |
| 拉（Pull）操作 | InteractionSystem 缺少 `pull` |
| 敌方意图预览阶段 | 当前从“敌方回合”直接执行，缺少独立的 intent preview 阶段和箭头渲染规范 |
| AI 差异化 | 红衣女/水鬼/僵尸/棺材主的特殊行为未完整实现 |
| 背包与角色被动 | 恐惧值、灵感知、环境被动（凛音推拉+1、薄荷无声步等）未完全接入 |
| Boss 两阶段 | 棺材主阶段切换未完成 |
| UI 风格偏离 | 当前 AI 生成 UI 偏西幻，与港式民俗主题不符；详见 `UI.md` |
| 音效 | 全部缺失 |
| 字体 | 使用系统回退字体，未引入指定中文字体 |

### 6.3 最近修改中的文件

以下文件在工作区有未提交改动，修改前请先 `git diff` 确认：

```
data/balance.json
data/effects.json
data/enemies.json
data/maps.json
data/rules.json
data/statuses.json
data/terrains.json
scripts/core/card_effect_parser.gd
scripts/core/card_resolver.gd
scripts/core/status_effect_manager.gd
scripts/core/terrain_system.gd
scripts/core/unit.gd
```

## 七、安全与注意事项

- 本项目为本地 Godot 游戏项目，无网络服务、无敏感凭据文件。
- `.godot/` 和 `__pycache__/` 已加入 `.gitignore`，不应提交。
- 工具脚本默认只读写项目内 `assets/` 目录，不会修改项目外文件。
- 修改 JSON 数据前建议先备份或确认 Git 状态，避免误改地图/规则导致游戏无法运行。

## 八、常用修改入口

| 想改什么 | 先看这里 |
|----------|----------|
| 角色属性/初始牌组 | `data/units.json` |
| 敌人属性/AI 参数 | `data/enemies.json` |
| 地图布局 | `data/maps.json` |
| 地形规则 | `data/terrains.json` + `data/rules.json` |
| 卡牌效果 | `data/cards.json` + `scripts/core/card_resolver.gd` |
| UI 布局/颜色 | `scripts/scenes/battle_scene.gd` 中的 `_style_battle_ui`、HUD 节点、`_draw_*` 函数 |
| 敌人 AI 行为 | `scripts/core/ai_controller.gd` |
| 环境连锁反应 | `scripts/core/terrain_system.gd` |
| 新系统通信 | `scripts/core/event_bus.gd` |

## 九、文档索引

- `docs/GDD.md` — 游戏设计文档（世界观、核心循环、系统规则）
- `docs/代码实施方案.md` — 分 Phase 重构方案、文件清单、数据迁移指南
- `docs/进度.md` — 当前完成度、技术债务、下一步优先级
- `UI.md` — UI 风格问题诊断报告（与 GDD 目标差距较大）
