# Godot 4.7.2 升级与影响评估

日期：2026-10-05。原版本4.6.3，新版本4.7.2 stable（4.7系列当前稳定维护版）。

## 结论

开发环境与本项目启动入口已升级到4.7.2。当前对照未发现新增脚本/逻辑失败，检查过的源项目场景可正常渲染。**这不是全项目测试通过，也不是可发布包验收通过**：两条既有RPG流程断言、缺失插件/前景引用、打包后的高清标题人物与音效加载问题，在4.6.3中同样存在。

本次没有改角色素材、战斗规则、存档格式、xlsx源表或插件代码。原默认主场景仍是`res://scenes/v3/title.tscn`；既有两个试玩启动器仍直达山道。

## 安装与入口

- 引擎：`J:\godot\Godot_v4.7.2-stable_win64.exe`。
- 命令行：`J:\godot\Godot_v4.7.2-stable_win64_console.exe`。
- Windows x86_64 debug/release导出模板：`C:\Users\kin\AppData\Roaming\Godot\export_templates\4.7.2.stable`。只安装了本项目使用的Windows x86_64模板，未展开其他平台模板。
- `play.bat`、`启动游戏.bat`及桌面`game.lnk`已指向4.7.2；桌面的参道试玩快捷方式指向`play.bat`，自动沿用新引擎。
- 新增`打开编辑器.bat`；`play-4.6.3.bat`保留旧引擎运行入口。旧引擎与旧模板未删除。
- 项目`config/features`更新为4.7；当前AGENTS引擎说明和RPG运行说明同步更新，历史验证记录中的4.6.3事实保留。

官方Windows引擎ZIP SHA256：`731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`。

官方模板TPZ SHA256：`f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`。

完整下载已逐字节计算哈希并匹配官方发行资产。记录见`build/godot47_assessment/engine_installation.json`与`templates_installation.json`。

五个技能安装在`C:\Users\kin\.codex\skills`：`game-ui-ux`、`game-feel`、`game-design-theory`、`godot-ui-control`、`godot-animation`，均通过技能格式检查。`game-design-theory`的非标准头字段另存于其`references/upstream-frontmatter.yaml`，仅适配frontmatter，正文保留。未安装其他榜单条目、未接入付费生成服务。技能不覆盖项目和用户规则。

## 验证方法与结果

以Git `8d5e429b2272905518c9b56ae8867b9764ea4a76`为基础，在隔离工作树复制当前AGENTS与四张行走遮罩的未提交版本。所有游戏测试从现有`tools/rpg/run_checks.py`开始；补充图形与导出探针也独立核验临时`user://`。没有对真实玩家档执行新建、覆写或清理回归。

| 检查 | 4.6.3 | 4.7.2 |
|---|---|---|
| 项目资源导入 | 无SCRIPT ERROR/ERROR，存在既有警告 | 同左 |
| RPG全部10组 | 8组通过，campaign/ui各1条断言失败 | 同样8组通过、同样2条失败 |
| 旧v4规则、凛音时序、独立3D预览 | 3项均通过 | 3项均通过 |
| 标题、山道、旧卡牌战、RPG准备、RPG战斗、3D预览、窄屏准备页 | 7个真实图形探针完成 | 7个真实图形探针完成 |
| E/空格与ui_interact的映射 | 通过 | 通过 |
| Windows导出 | EXE生成成功 | EXE生成成功 |
| 导出包标题人物 | 缺失高清idle1，验收失败 | 同样缺失，验收失败 |
| 导出包音效 | bell.mp3读取警告 | 同样警告 |

完整组在失败后会阻止legacy组，因此额外通过`--suite data --legacy`分别完成两版legacy验证；没有绕过隔离检查。

当前原工作区切换4.7.2后，又运行了`--suite data --import --legacy`（通过）以及标题和RPG战斗实际渲染（通过）。完整10组对照是在隔离工作树运行的，不把这两种范围混写。旧4.6.3对当前工作区标题的回退启动探针也通过。

图形检查使用本机GTX970、Forward+，包括1280×720和960×720窗口。第一轮标题/探索截图受鼠标视差干扰，因此另做固定相机对照；固定后山道像素一致，标题仍有少量动态画面差异。旧卡牌战、独立3D预览和窄屏准备页的对应截图像素一致；RPG战斗差异很小。已人工查看截图，没有观察到新增缺材质、文字乱码或明显布局破坏。未覆盖所有剧情、全部技能动画、其他GPU、其他渲染后端与手柄实机。

4.7.2首轮RPG战斗图形探针出现约2分半的首次启动间隔；随后计时复测约4.71秒，4.6.3约4.53秒，实际原工作区4.7.2约4.58秒。这提示首次缓存/预热成本可能较高，但未做性能归因，也不能由这些加载探针得出帧率提升结论。

正式release EXE还通过Movie Maker模式实际启动并输出45帧，退出码0；截图同样显示原有标题人物缺失。包内RPG战斗和3D资源另用编辑器引擎加载同一内嵌PCK验证。官方导出模板不支持任意`--path`/`--script`覆写，不能把受限参数当成游戏功能失败，也不能把资源探针等同于完整真人游玩。

## 已有问题，不归因于本次升级

1. `原本殿出口可继续，不重复钟鸣战斗`断言失败。
2. `保留原仪式/本殿顺序进入Boss`断言失败。
3. `addons`当前为空，配置仍列出AsepriteWizard和shaker；两版导入均警告并在编辑器会话中禁用，无法声称这两个插件已兼容4.7。
4. 四张被引用前景缺失：`test_approach_fg2.png`、`corridor_act_fg2.png`、`night3_procession_fg1.png`、`night3_procession_fg2.png`。
5. 导出包中高清标题人物报告`高清待机帧缺失：idle1`，`Sfx`直接文件读取MP3失败。4.6.3与4.7.2同样复现；这是需另行修复的资源打包/读取问题，本次没有修改加载器或将验收包作为可发布版本。

## 官方迁移项对照

- 未检出项目使用BlendSpace旧sync字段、Jolt世界边界/软体、频谱分析tap_back_pos、设备ID数值判断、XR/VCS扩展等对应项。
- 字体导入已有明确`hinting=1`，不会仅因新默认值变成3；实际中文界面已目检。
- 项目本身已设置`canvas_items`与`expand`，无需跟随新项目默认值另改拉伸策略。
- 没有发现C#工程或GDExtension二进制；插件兼容性的限制见上文。
- Canvas线条与动画API变化通过实际图形和时序检查覆盖了当前常用路径，不代表全部边界行为均已穷尽。

## 回退

旧引擎仍位于`J:\godot\Godot_v4.6.3-stable_win64.exe`，可用`play-4.6.3.bat`临时回到旧引擎运行。完整撤回本次版本切换时，将`project.godot`的4.7声明和启动器引擎路径恢复为4.6/4.6.3，并恢复桌面快捷方式；必要时用旧引擎重新导入资源。原内容备份在`build/godot47_assessment/before/`。

不要整体覆盖后续编辑过的AGENTS或使用`git reset --hard`回退。四张用户行走遮罩的哈希在升级前后完全一致；AGENTS的原用户内容已通过逆向还原本次版本变更逐字核对。

## 证据与来源

本机日志、截图、对照JSON和验收包统一保存在`build/godot47_assessment/`（Git忽略）。主要文件：`baseline_463.log`、`upgrade_472.log`、`legacy_463.log`、`legacy_472.log`、`actual_workspace_472.log`、`baseline_comparison.json`、`visual_comparison.jpg`、`fixed_camera_comparison.json`、`pack_resource_463/title.json`、`pack_resource_472_checked/title.json`、`release_native_472/release_result.json`。

- [Godot 4.7.2官方发行资产](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
- [4.6→4.7官方迁移说明](https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html)
- [命令行参数适用范围](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

## 最终独立复核

只读独立复核未发现本次新增的Critical/Important/Minor问题；检查了启动与回退、主入口、用户改动保留、技能安装记录、版本对照日志、截图与存档隔离证据。未重跑全部测试或真实存档迁移，未扩展到其他GPU/手柄。升级按开发环境交付，已知失败与导出限制继续保留。
