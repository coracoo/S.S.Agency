# 验收矩阵 A 项操作清单：全量解析与日志基线（交给测试执行者）

2026-10-11。对应[试玩反馈验收矩阵](2026-10-08-playtest-remediation.md) §5 A 项与[交接方案](2026-10-08-strategy-handoff-plan.md)。**A 项通过前不要执行 B–F 的任何步骤。**

背景：`437e4d8` 之后的全部改造（build2/r4/UI/移动插值批次，现至 `ba08169`）从未被引擎解析或运行过。已知并修复过一类静态类型解析风险，但执行时必须**完整收集**所有解析错误，不要按预设清单逐条核对。

## 0. 前置

| 项 | 要求 |
|---|---|
| 代码 | `main` ≥ `ba08169`，工作区干净；从 GitHub 拉取：`git pull origin main` |
| 引擎 | `..\Godot_v4.7.2-stable_win64_console.exe`（与正式验证同一版本） |
| 证据目录 | 仓库外，如 `..\ssa-campaign-evidence\parse-check-20261011`；stdout/stderr 全部原样归档 |
| 隔离 | 所有引擎调用重定向 APPDATA/LOCALAPPDATA 到临时目录（下方入口已内置）；不得触碰真实玩家存档 |
| 并行 | 所有引擎调用共享仓库外 `godot-import.lock`（下方入口已内置） |

## 1. 全量 GDScript 逐文件解析（最先跑，最可能暴露问题）

```sh
python tools/campaign/run_parse_check.py --output-dir <仓库外证据目录>
```

- 对 `scripts/` 与 `tools/` 下全部 `.gd` 逐个 `--check-only`，只解析不运行。
- 判定：输出 `PARSE_CHECK:PASS`。任一失败输出 `PARSE_CHECK:FAIL`，完整失败清单在 `<证据目录>/parse-check-report.txt`，逐文件日志在 `<证据目录>/logs/`。
- 每个失败都记录并回报，不要自行修复、不要跳过；修复属改造方职责。

## 2. 无头导入

在 `godot-import.lock` 保护下执行（可复用 `tools/verification_support.py` 的 `exclusive_file_lock` + 隔离环境，参照 `tools/campaign/run_final_gauntlet.py` 的写法）：

```sh
godot --headless --path . --import
```

判定：退出码 0，无 `ERROR:` 输出。导入产物不提交。

## 3. 隔离探针与日志基线

1. 运行隔离探针（核验 `user://` 落在临时目录内，参照 `run_final_gauntlet.py` 中 `res://tools/rpg/test_environment.gd` 的调用方式），确认输出 `RPG_ISOLATION_OK:<临时目录路径>` 且该路径在隔离目录内。
2. 无头启动主场景跑 60 秒（超时杀进程属预期，用 `run_captured` 的错误感知等待，保证子进程树终止），归档完整日志。
3. 从日志提取并记录：
   - 实际渲染后端（Forward+ / Mobile / Compatibility）与显卡——本项目历史约定 Compatibility，但最近人工日志为 Forward+（GTX970），需以实测为准并写入验收记录；
   - 不再出现 `rim_color`、`rim_size`、`rim_fade`、`specular` 无效材质属性警告（历史 66 次，来源 `act_one_geometry.gd::_embellish_washi_node`，已修复）；
   - 无 `SCRIPT ERROR`、`Parse Error`、`Function not found`、Shader 编译错误。

## 4. 通过标准（全部满足才进 B 项）

- [ ] 第 1 步 `PARSE_CHECK:PASS`
- [ ] 第 2 步导入退出码 0 且无 `ERROR:`
- [ ] 第 3 步隔离探针确认 `user://` 在临时目录内
- [ ] 第 3 步日志已记录实际渲染后端并归档
- [ ] 旧材质属性警告清零、无脚本/着色器错误

任何一项失败：完整保存证据，回报改造方，修复后从第 1 步重跑。
