# 2026-10-20 友方纵深与和纸素材接入核验

基于 `effects/webgl-godot-20261017` 的 `ad52292835e5915520fc87c2ed4fa764268f4b7f`。正式接入目录只有原有本地项目；隔离存档、对照场景副本和采证文件位于项目外。现有用户修改不纳入本轮提交。

## 变化与边界

- 真实 3D 战斗的友方按正式活动职业排前后站位。默认凛音、岑照在前，薄荷在后；角色模型、卡片及行动顺序不重排。使用正式相机与双朝向完整动作帧并集计算安全脚点；必要时整队共同横移，保持点击区间距。
- 同场战斗缓存初始职业与脚点，换形和重试不令队伍跳位；绑定另一战斗引擎时清缓存。旧的 2D 演出路径保持原有布局。
- 两张候选 PNG 原始字节直接接入。叶片区域 `(40,84,1968,592)`，逻辑尺寸 `512×192`；摘要区域 `(24,202,2124,316)`，逻辑尺寸 `768×96`。使用 AtlasTexture 区域、内存副本与纹理逻辑尺寸覆盖映射 12px 切片；不重采样或重写原图。真实源切片分别为 `(46.125,37)`、`(33.1875,39.5)`。
- 保留 Flat 样式回退。焦点使用原生 3px 描边、外扩 2px；目标摘要左右留白均为 12px。停靠技能页页眉移至右侧空白处，按可见纸面及滚动裁切统计遮挡，透明菜单外框仍保留为诊断字段。
- 发布依赖收集明确包含两张运行时读取的 PNG。图源身份记录仅留于本地采证；公开清单保存尺寸、区域、大小和 SHA256。

人物身高、相机、原生动作帧时长、命中帧、伤害及敌方事件链未修改。“术士”具体 UI 身份尚待确认，本轮不调整该角色或五入口布局。

## 实测结果

环境为 Godot `4.7.2.stable.official.ed1daf0bf`、Windows、Radeon 8060S，OpenGL Compatibility。全部引擎测试使用独立 `user://` 并持有项目约定的共享锁。

| 检查 | 结果 |
| --- | --- |
| 纵深纯布局 | 39 项，0 失败 |
| 和纸样式契约 | 28 项，0 失败 |
| 实际纸面占区、菜单契约、同场/换引擎脚点缓存 | 0 失败 |
| 指令 GUI | 657 项，0 失败 |
| 实际身高 | 1565 项，0 失败 |
| 近战回位 / 敌方命中 | 32 / 238 项，0 失败 |
| 并行命中（实时） | 1502 项，0 失败 |
| RPG 全组 | 13 组，0 断言失败 |
| 纸面 GPU 网格 | 深浅背景、1080p/720p，138 项，0 失败 |
| 实际战斗 UI | 37 个采证画面通过，纸面遮挡面积为 0 |
| 原始 PNG 打包加载 | 最小独立 PCK 加载通过；依赖收集单测通过 |
| 最终录像 | 7 个关键画面、0 契约失败、0 采证错误；1080p/30fps MP4 解码通过 |

GPU 网格覆盖 `234×70`、`118×70`、`108×70`、`152×70`、386px 可变高技能叶和 `492×70` 摘要条；检查边内外点击、禁用态、焦点和真实文字布局。实际战斗覆盖技能、目标、取消、低 MP/CD 原因以及 1080p、720p、1180×812。细纤维在暗底可见，未观察到宽白边或角部拉坏；美术最终取舍交由用户。

同一正式存档输入与种子下，修复前友方实际接近距离为 0，接入后约 `229.862px`、回位误差 `0`。原生攻击仍为 `1.500000s`，命中时刻 `0.708333s`（零起始第 17 帧），双方实测 HP 扣除均为 `41`。接近用时约 `0.260215s`，位于原生攻击段之外。身体比例仍为 165px/m；凛音/薄荷/岑照分别为 168/158/186cm。

截图与录像输入为 `SceneTree.root.push_input` 的引擎 GUI 注入，不代表物理设备手动游玩。PNG 与 MP4 已分别作为 Library 文件交付；未做整包游戏导出。

## 已有问题与核验限制

原始基线场景副本复现：`test_dual_form_presentation.gd` 有 3 项旧 UI 可见性预期失败；`test_battle_world_backdrop.gd` 有 1 项旧模糊/深度预期失败，未在本轮改写这些预期。RPG 全组退出为 0，但旧探索场景关闭路径仍记录 8 条 `!is_inside_tree` / Transform3D 错误；不能据此声称完整引擎日志无错误。

原身高测试一处把已为 165px/m 的配置按旧 190px/m 硬编码；本轮改为与其他角色独立测量的比例一致，并把同一地面行断言更新为本轮前后站位要求。没有把不相关旧失败改成通过。

全部阵容没有逐一做 GPU 录像；纯布局覆盖镜像、1–3 人、换形安全域，真实默认三人与三近战阵容另有核验。保留 1133 个原有修改文件的字节哈希及 109 个原有未跟踪文件的大小/时间戳基线。

## 复验入口

通过 `tools/characters/run_runtime_recovery_checks.py` 的正式隔离运行器执行：

```text
--realtime --script tools/rpg/test_party_depth_layout.gd
--realtime --script tools/rpg/test_battle_paper_styles.gd
--realtime --script tools/rpg/test_command_paper_footprint.gd
--realtime --script tools/rpg/test_actor_command_menu.gd
--realtime --script tools/campaign/test_actor_command_ui.gd
--realtime --script tools/campaign/test_character_height.gd
--realtime --script tools/campaign/test_party_depth_presentation.gd
--realtime --script tools/characters/test_melee_return_dash.gd
--realtime --script tools/characters/test_enemy_impact_hud.gd
--realtime --script tools/characters/test_parallel_impact_timing.gd
```

PNG 发布依赖检查：`python -m unittest tools/campaign/test_battle_paper_release.py`。只向目标分支普通快进推送，提交前后核对远端 SHA、Actions 工作流与运行数；不启用 Actions，不改 main。
