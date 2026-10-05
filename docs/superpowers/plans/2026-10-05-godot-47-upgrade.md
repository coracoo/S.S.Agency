# Godot 4.7 升级与影响评估计划

> 执行方式：本会话使用 superpowers:executing-plans；用户已授权安装推荐技能、升级 Godot 4.7 并评估影响。

**Goal:** 安装五项推荐技能，将项目运行入口升级到官方 Godot 4.7 系列稳定维护版，并给出可复核的兼容性结论。

**Architecture:** 新旧引擎并存；在隔离工作树中复制用户当前未提交文件，先建立4.6.3测试基线，再用4.7.2导入和执行同组测试。验证通过后更新原工作区的版本声明和启动路径，保存回退依据。

**Tech Stack:** Windows、Godot 4.6.3/4.7.2、GDScript、Python项目隔离测试入口。

**Spec:** 用户本轮明确请求；项目约束见 `AGENTS.md` 与 `docs/rpg/README.md`。

## 全局约束

- 默认入口保留 `res://scenes/v3/title.tscn`；可选RPG模式和旧模式的隔离不变。
- 不覆盖用户对AGENTS.md及四张行走遮罩的未提交改动。
- 首次项目测试必须从 `tools/rpg/run_checks.py` 开始并验证临时 `user://`。
- 不为了升级重新制作角色、美术、规则或覆盖旧导出包。
- Godot 4.6.3 与其启动方式保留作为回退；技能文档不能覆盖用户/项目规则。

## 重点检查

1. 资源导入及编辑器插件：新旧版本对照导入，不把已有失败误判成升级回归。
2. 脚本与旧/新战斗：运行完整RPG检查及既有legacy组。
3. 字体、线宽、角色动画、输入与窗口比例：对照真实引擎截图和场景冒烟。
4. 存档和回放：只在已核验的临时用户目录执行，不触碰真实玩家档。
5. Windows导出及模板：采用匹配4.7.2模板，导出到新目录并检查PCK内资源启动。

## 执行任务

- [x] 安装并校验 `game-ui-ux`、`game-feel`、`game-design-theory`、`godot-ui-control`、`godot-animation`。不安装榜单其余条目。
- [x] 下载官方4.7.2 Windows引擎与模板，核对发行资产SHA256，保留旧版本。
- [x] 保存原配置与用户改动快照；在 `C:/Users/kin/.codex/worktrees/godot-47-compat/S.S.Agency` 建立等价输入。
- [x] 在隔离工作树运行 `python tools/rpg/run_checks.py --godot J:/godot/Godot_v4.6.3-stable_win64_console.exe --suite all --import --legacy`，保存基线日志。
- [x] 扫描官方迁移项；使用4.7.2运行同组命令。发现失败时按相同输入对照4.6.3，仅修正可归因的兼容性问题。
- [x] 验证实际画面、主要场景以及Windows导出；将未覆盖项明确写入报告。
- [x] 确认无新增失败并记录既有缺陷后更新 `project.godot`、两个 `.bat` 启动器和当前引擎说明；保留回退启动器与原内容备份。
- [x] 写 `docs/godot-4.7-upgrade-report.md`，记录安装、测试、差异、限制及回退方式，复核修改范围。

## 完成判据

引擎实际版本为4.7.2 stable，五个技能可被读取；同组新旧验证结果可比较；当前工作区能够以新引擎导入/启动。任何原有失败、升级回归或无法验证的项目均单列，不笼统宣称“升级零影响”。
