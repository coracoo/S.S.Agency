# 夜巡菜单、行囊与武具

当前版本以已确认的紧凑旧年代生图方案为准。正式界面使用 `assets/ui/night_menu/` 中分离的透明 PNG：外框、内框、普通/已选/主要/禁用按钮、独立焦点框，以及道具、武器、护甲和饰品图标。没有把概念图当作可交互界面，也不把文字、数值或人物烘焙进图片。

## 使用

- 探索时按 Esc 或右上角「菜单」，打开夜巡菜单；原地图仍在周围可见。
- 面板按 1920×1080 的 1344×780 区域居中，等比适配宽屏和较窄窗口。字体与命中区保持真实 Godot 控件。
- 行囊：选择道具与左侧队员，查看效果、恢复前后数值和库存变化，再确认使用。满 HP/MP、倒地规则不符、库存不足或没有可净化状态时禁用，并说明原因。
- 武具：选择队员、槽位和当前目录的标准装备/卸下，查看七项属性前后比较后确认。降低上限会截短当前资源，装回不免费治疗。
- 队伍：六人选三人的草稿需点「保存三人编队」；未保存草稿持续提醒。焰华解锁规则、形态与技能分支沿用现有模型。
- 子页 Esc / 返回按钮回菜单；菜单 Esc / 返回探索继续行走。关闭期间加载资源有忙碌锁，释放移动键后恢复控制。
- 成功使用道具、更换装备与保存编队仍走模型原子存档。保存失败不伪报成功；重进保留库存、装备和当前资源。

本轮不增加商店、掉落、稀有度或装备库存系统。三件标准装备仍是现有固定配装数据。

## 分层与发布

`night_menu_art.gd` 仅负责加载生成纹理、在内存规范九宫格边框尺寸与设置真实控件样式。无程序重绘框架的替代皮肤；角色 PNG、动画帧、人物图集不变。原始 PNG 保持仓库内高分辨率；数字、中文与状态文字由字体实时显示。

正式 PCK 依赖闭包显式收集菜单目录的直接 PNG，同时保留 FileAccess 所需原始字节。嵌套草稿和无关目录不进入发布。

## 验证入口

所有测试先核验隔离 user 目录，不写真实玩家存档：

```sh
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_inventory_menu.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_night_menu_entry.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_scene_flow.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_ui_polish.gd
python3 tools/campaign/run_presentation_checks.py
python3 tools/rpg/run_checks.py --suite all
python3 -m unittest tools.rpg.test_run_checks
python3 -m unittest discover -s tools/campaign -p 'test_*release*.py'
python3 tools/campaign/run_act_one_checks.py --graphical --script res://tools/campaign/capture_inventory_menu.gd --output-dir /absolute/outside/repo/menu-captures
```

菜单测试包含真实鼠标输入、Tab/Esc、重复点击、禁用动作、属性预览、消耗、保存/读取及三种窗口比例。截图来自实际 Godot 图形渲染，采集使用已隔离的场景位置夹具，不声称替代人工五夜全流程通关。
