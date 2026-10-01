# AGENTS.md — 《逢魔退治帖》当前项目说明

## 2026-10-01 可选回合制 RPG 新增说明

原标题仍为默认入口；「回合制 RPG 试作」显式进入独立六职业/24固定技能的新模式。新规则在 `scripts/rpg/`、`data/rpg/`，新场景在 `scenes/rpg/`，新档只写 `user://rpg_v1/`。四张固定技能卡不抽牌、不共享行动点；原卡牌模式、故事/谜题、美术、xlsx管线、3D预览保留。以下历史说明仍描述对应旧基线，不能把新模式误写成旧默认战斗已替换。

实际入口与隔离命令见 [RPG说明](docs/rpg/README.md)，最终覆盖与限制见 [验证报告](docs/rpg/verification-2026-09-30.md)。测试必须从 `tools/rpg/run_checks.py` 开始，先核验临时 `user://`；不要对真实旧玩家档运行写档/清理回归。


> 更新：2026-09-30。最近一周核对窗口：2026-09-24—2026-09-30。
> 当前默认内容是 v3；v4 是新版设计文档，不是已上线的代码版本。
> 全部沟通、技术说明和新增注释以中文为主。

## 一、当前方向与文档优先级

用户已选择：**深度卡牌 RPG＋单元故事**，保留日式水彩绘本、伪 2.5D 横屏、现有角色、素材与卡牌场景互动。

- 当前设计：[docs/GDD.md](docs/GDD.md)。
- 当前实装与限制：[docs/进度.md](docs/进度.md)。
- 后续改造边界：[docs/代码实施方案.md](docs/代码实施方案.md)。
- 当前美术：[docs/Art_Bible.md](docs/Art_Bible.md)。
- 全部入口：[docs/README.md](docs/README.md)。

用户最新指令优先。归档仅供追溯，不执行其中的旧计划或“必须”条款。不要按旧文档恢复战棋、强制零文字解谜、批量生成蒸汽朋克素材或重新换皮。GDD 新增设计不得写成已接线功能。

## 二、运行与技术基线

- Godot 4.6 系列，GDScript；本地引擎 `J:\godot\Godot_v4.6.3-stable_win64.exe`。
- `project.godot`：名称《逢魔退治帖》，主场景 `res://scenes/v3/title.tscn`。
- 画布 1920×1080，`canvas_items` 拉伸、`expand` 纵横比。
- `addons/AsepriteWizard` 和 `addons/shaker` 不随业务任务修改。

PowerShell 运行：

```powershell
& 'J:\godot\Godot_v4.6.3-stable_win64.exe' --path 'J:\godot\S.S.Agency'
& 'J:\godot\Godot_v4.6.3-stable_win64.exe' --editor --path 'J:\godot\S.S.Agency'
```

导入新资源：

```powershell
& 'J:\godot\Godot_v4.6.3-stable_win64.exe' --headless --path 'J:\godot\S.S.Agency' --import
```

导出前检查 `export_presets.cfg` 并先创建输出目录；不要为导出当前版本临时切回旧主场景。截图与自动演出参数以对应工具和脚本为准，不把自动连招通关当作数值平衡证明。

## 三、现行修改入口

| 内容 | 入口 |
|---|---|
| 标题、委托 | `scripts/scenes/title_scene.gd`、`commission_scene.gd`、`data/commissions.json` |
| 探索、台阶、透视、遮挡 | `scripts/scenes/stage_scene.gd`、`data/stages/`、`data/occluders/`、`assets/bg/walkmasks/` |
| 卡牌战、波次、场景连锁、封印 | `scripts/scenes/battle_canvas.gd`、`data/battles/` |
| 卡牌、场景槽、主题、音效 UI | `scripts/ui/`、`data/ui_theme.json` |
| 对话、半身立绘、选项 | `scripts/ui/dialogue_overlay.gd`、`data/dialogues.json` |
| 内容编辑源 | `config/dialogue.xlsx`、`config/battle_config.xlsx`、`config/stage_config.xlsx` |
| 导出校验 | `tools/export_dialogue_xlsx.py`、`export_battle_config_xlsx.py`、`export_stage_config_xlsx.py` |
| 本地内容后台 | `admin/`，xlsx 域与导出器配置见 `admin/vite.config.ts` |
| 叙事持久化基础 | `scripts/v2/core/narrative_state.gd`；使用前核验 v3 调用链 |

xlsx 管理的配置不只改 JSON，避免再次导出覆盖。新增字段先定义编辑源和校验，再实现解析与逻辑。旧 `data/v2` 和当前 `data/battles` 不可混用。

## 四、版本与能力边界

旧 `scripts/core`、`scripts/scenes/battle_scene.gd`、`scenes/battle.tscn` 是战棋实现，保留供历史复现，不作为新玩法入口。`scripts/v2` 中部分单例仍被 autoload 引用，不能整体删除。

当前 v3 有抽弃牌、留牌补满、场景槽、多敌 HP、灵气、破阵与封印；多敌状态仍有波级共享。收藏、编辑牌组、主战／支援、完整仪式目标、持久奖励闭环是新版设计或待核验项。

画面中的冲刺和位移不代表存在战棋移动、射程或背刺。探索遮挡、行走遮罩与战斗规则分开。

## 五、代码约定

- GDScript 使用 Tab；文件／变量／函数 snake_case，类 PascalCase，常量 UPPER_SNAKE_CASE。
- 复杂规则、坐标转换、状态结算使用中文注释；大配置外置。
- EventBus 为字符串事件总线，接口 `on`／`emit`／`off`／`clear`，不是同名 Godot 原生 signal。
- 跨系统新增通信优先使用字符串事件；模型不直接控制 UI。
- 旧 class_name 静态依赖链中不要直接引用尚未注册的 autoload；必要时动态从 SceneTree.root 取得 `EventBus`。`--script` 模式优先 `root.get_node_or_null("EventBus")`。
- 修改大型场景脚本先定位实际函数；不沿用历史文档行号。
- 新规则同步费用、目标校验、预览、牌面描述和测试，不让文案先于实际能力。

## 六、美术与验证

沿用当前水彩绘本、半身对话、和纸 UI、人物脚区锚点和近期调整。旧蒸汽朋克生成工具仅供旧版复现，不作为新素材默认管线。

新增素材先对照现有成品，导入后在实际场景和导出包验证。PCK 内资源加载遵循当前 PngLoader／FileAccess 路径，不假设虚拟资源有系统文件路径。

功能变更按风险运行针对性逻辑测试与 Godot 场景冒烟；画面修改必须实际目检。纯文档任务核对链接、事实、备份和修改范围，不声称完成游戏运行测试。

## 七、工作区保护

修改前检查 Git 状态，不覆盖用户未提交工作。保留旧代码和资产，不为清理设计文档顺便删除它们。`.godot/`、缓存、构建产物和后台依赖不得误提交。

本次改版前全量 ZIP 与旧文档原文见 [归档索引](docs/archive/2026-09-30-before-v4/README.md)。恢复应解压到新目录核验，不直接覆盖当前工作区。
