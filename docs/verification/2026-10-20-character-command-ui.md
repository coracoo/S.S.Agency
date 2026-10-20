# 2026-10-20 角色旁和纸战斗指令簇

在既有 `effects/webgl-godot-20261017` 上替换固定底部操作板。根命令用角色旁两列纸页，四技能按真实字体测量排版；选择技能后收成目标与费用单行，必须独立确认。Esc／手柄B逐层取消并恢复原焦点；表现期间隐藏菜单。现有六字段命令、费用、命中反馈和回位时序仍由原引擎与事件队列负责。

位置计算只处理逻辑画布矩形。打开时冻结角色锚点与保护区，避开实际角色投影、意图和状态卡；页面或内容尺寸改变时重排，必要时紧凑停靠。没有空位时返回实际遮挡量，不把碰撞报告成成功。窗口缩放保留逻辑布局，震屏叠加居中偏移。

纸色 `#F3EFE5`、墨色 `#252B29`、朱色 `#A64234`。命令30px、技能27px、费用／原因24px；按真实字体高度与换行扩展纸页。MP、CD与禁用原因读取引擎预览，剩余CD以演员自己的 `slot_count` 计算。键盘F／手柄Y调用原有焰华换形协议；战斗期间补齐缺失的A/B默认映射，退出时移除本视图所加项。

战斗背景停用覆盖整个视口的深度模糊。仅复制远景几何的 StandardMaterial3D 并轻调色；近景、演员、ShaderMaterial、灯光和遮挡器管理材质保持原处理。这是材质层次，不是原生景深，也不处理纹理RGB去饱和。

本机参考目录中的脚本副本注册了重复 `PartyAssetBundle` 全局类。正式代码均按固定路径加载；移除正式文件未使用的 `class_name` 声明，保留全部路径接口，未改参考副本或缓存。

## 本次验证

Godot 4.7.2 `ed1daf0bf`，Windows，Radeon 8060S，OpenGL 3.3 Compatibility。所有运行先核验隔离 `user://`，使用共享导入锁。没有改原角色素材、帧时长、清单或玩家存档。

| 检查 | 结果 |
| --- | --- |
| 角色命令真实GUI事件回归 | 657断言，0失败 |
| 纯布局计算 | 85断言，0失败 |
| 菜单字体／长原因／多目标契约 | 0失败 |
| 原UI组，按新布局更新失效美术断言 | 327断言，0失败 |
| roster | 1692断言，0失败 |
| campaign／旧存档隔离夹具 | 532断言，0失败 |
| engine／replay | 196／41断言，0失败 |
| 近战回程 | 32断言，0失败 |
| 敌方命中与HUD | 238断言，0失败 |
| 并行命中时序 | 677断言，0失败 |

GUI回归覆盖四技能、真实MP/CD、失效目标、分层取消、重复确认、精确焦点恢复、同角色下一槽、键盘／鼠标／手柄映射与四种窗口尺寸。正式战役API创建的新测试档实拍覆盖三位角色及1920×1080、1280×720、1180×812，记录真实事件的命中和回位。录像输入来自Godot事件注入，不是人工键鼠／实体手柄实操；OS硬件输入仍未验证。

旧 `test_battle_view_motion.gd` 有7项失败：既有特效开关假设、近战位移夹具与反射中心假设。对照保存的修改前 View／Backdrop 源码，同一76断言仍是完全相同7项失败；未通过改断言消除这组既有问题。旧探索画面缺失 `corridor_act_fg2.png` 的警告亦保留。

可用现有隔离入口重跑：

```powershell
python -B tools/campaign/run_act_one_checks.py --godot <Godot4.7.2_console.exe> --script res://tools/campaign/test_actor_command_ui.gd
python -B tools/campaign/run_act_one_checks.py --godot <Godot4.7.2_console.exe> --script res://tools/rpg/test_actor_command_menu.gd
python -B tools/rpg/run_checks.py --godot <Godot4.7.2_console.exe> --suite ui
python -B tools/rpg/run_checks.py --godot <Godot4.7.2_console.exe> --suite roster
```

复核包另含截图、录像、模型事件／费用记录、运行日志与SHA256清单。已有用户导入／配置差异和109个未跟踪文件独立保留，不纳入提交。源码提交与远端目标分支对齐不代表这些用户工作树差异被清除。
