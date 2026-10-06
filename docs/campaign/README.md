# 七章正式3D主线

后六章内容、操作、保存扩展和统一测试入口见[七章说明](seven-chapters.md)。下文保留第一章连续寺域与既有发布管线的细节；当前发布目标升级为官方4.7.2/PCK v4。

## 第一章流程

唯一标题：`scenes/campaign/title.tscn`。第一幕使用一张连续寺域：原上山参道与石阶连接山门前庭、回廊、中庭、镜殿支院、纸棺庭和本殿。物理道路可双向探索，走到别处不会自动跳夜或替玩家完成剧情。五夜只更新当前调查点与故事状态；已收齐本夜记录后在记事点确认，原地进入下一夜，再实地走到对应区域开始剧情。

每夜调查与对白仍触发原登记RPG遭遇。战果成功保存后回同一夜的战前位置，无法安全落脚时退到本夜安全锚点。守灯仍为三步探索互动，第五夜后进入原结案链与送行/镇守分支。各 `night_*.tscn` 薄入口保留用于继续/战斗返场，它们均建立同一地图，不用于普通走路分区切换。

正式存档仅使用 `user://campaign_v1/slot_01.json`（schema2）。新世界带 `map_layout=act_one_connected_v1`。上一版正式五夜局部坐标档先按旧边界/事件校验，再一次性转为全图坐标，包含历史与战前检查点。未知布局、越界旧坐标和损坏档明确拒绝；旧卡牌、独立RPG与参道试玩档原样保留，不自动迁移或覆盖。

## 启动与输入

官方Godot4.7.2：`godot --path .`。项目默认Compatibility；Windows启动脚本支持`GODOT_BIN`与项目相对路径，详细版本验证边界见[UI与场景精修](ui-atmosphere.md)。不再传旧v3/试玩场景。

A/D左右、W/S纵深、E调查/推进、M寺域总览、Esc整备。总览显示实际可走区域、当前位置和本夜调查点，不提供传送。屏幕方向与距离提示只指示目标方向，需按道路绕行建筑/植床。对白、地图、菜单和转场锁住行动，关闭后先释放移动键再恢复。

山门前庭新增守山人老梁、扫庭人阿诚，以及未出战的岑照、薄荷、清明。靠近按E闲谈，青点显示于总览；五夜路引随夜次刷新，换队后驻场同伴立即同步。闲谈不消费主线、不给奖励、不增加交易或支线。居民使用匹配身份的全身地图图与独立半身对白图；原七形态只调整对白上身取景，不改地图、战斗或原人物PNG。详见[人物交谈](act-one-npcs.md)。

整备保留六身份选三人与焰华双形态。全图镜头保持正交中景人物尺寸，双轴与地形高度柔和跟随；暂停菜单可开关随人物位置移动的空间景深，选择在本次会话跨战斗/舞台保留，关闭不会改地图/存档。远区只裁剪美术和灯光，碰撞不销毁。

正式战斗现复用当前地区的独立3D寺域舞台，既有动作帧受光并按原脚点投影；详见[本轮骨架整合与验证](../verification/2026-10-05-game-skeleton.md)。

## 正式验证

```sh
python3 tools/rpg/run_checks.py --suite all
python3 tools/campaign/run_checks.py
python3 tools/campaign/run_act_one_checks.py
python3 tools/campaign/run_act_one_geometry_checks.py
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_act_one_runtime.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_act_one_ending_resume.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_act_one_npcs.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_act_one_npc_runtime.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_half_portraits.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_scene_flow.gd
python3 tools/campaign/run_presentation_checks.py
python3 tools/campaign/run_presentation_checks.py --dual
python3 tools/campaign/run_end_to_end.py --output-dir /absolute/outside/repo/e2e
python3 -m unittest tools.rpg.test_run_checks
python3 -m unittest discover -s tools/campaign -p 'test_*release*.py'
```

所有入口核验引擎实际隔离user目录；证据保存在仓库外。

新地图几何/运行门禁取代原单块环境的“碰撞与bounds完全不变”美术基线。旧 `run_environment_checks.py` / Night2HD2D试点检查仍是上一版独立场景的历史对照，不能把它的固定局部位置截图当新地图实拍。新连续采集入口为 `run_act_one_checks.py --graphical --script res://tools/campaign/capture_act_one_walk.gd --output-dir <仓库外目录>`；加环境变量 `ACT_ONE_FULL_ROUTE=1` 记录20点全环路真实控制器往返。夹具仅跳过对白播放，不手改行走位置，报告明确区别于人工通关。

RPG all门禁继续检查规则、引擎、重放、AI、存档、UI、六职业与兼容会话。正式state/scene/presentation/E2E替代旧默认入口、旧左向敌图与旧回廊直接本殿契约。4条原断言保留为 `--legacy-contracts` 诊断，当前版本预期失败；`--legacy`是另一个参数，运行保留的v4/凛音时序/预览回归。复现原始行为应在独立基线checkout运行，不覆盖当前树。

模型E2E使用真实合法战斗指令、五战与检查点重启，覆盖52节点/两结局、失败重试和重复战果。它不代替用户等价人工GUI通关；人工操作、视觉裁切与中断检查由单独记录证明。

## 可复现PCK发布

```sh
python3 tools/campaign/build_release.py --output-dir /absolute/outside/repo/release --import-lock /absolute/outside/repo/godot-import.lock
```

默认依次执行：官方4.7.2 resources导出、原始依赖追加、按实际PCK目标过滤生成class/UID缓存、逐条MD5和源SHA256校验、空项目根隔离核验、七形态/六敌原图加载、五夜几何/八场景生产脚本实例化、真实人物身高节点测量（若存在当前测量测试）、正式标题启动、发布包完整两结局E2E。

发布目录内有PCK、Windows/Linux启动脚本、清单、hash与验证日志。必须检查 `release-verification.json` 为pass，任何退出码0的SCRIPT ERROR仍是失败。`--skip-e2e`只适用于迭代，不能当正式验收。

七形态154原PNG逐帧按manifest纳入，未使用atlas与重复导入ctex排除。动态JSON/脚锚/roster、六最终敌图、各夜背景、共享UI、字体、GLB和音频明确纳入。保留TrialSession/TrialProfile/WorldSnapshot硬preload代码，但旧profile场景/旧玩家入口不随包发出。开发目录、XLSX、raw sheet、Blender源稿和历史归档不发包，仓库原稿保留。

只写include_filter不足以保留已导入PNG源字节，所以发布后处理使用已测试的PCK v3/v4追加目录流程，不重新编译脚本或修改素材import。清单与原字节hash是发布事实依据。Godot选择导出仍携带全项目class/UID注册缓存；后处理仅过滤这两份生成索引，保留实际发包路径及原UID，不修改生产脚本或项目源码缓存。

当前构建环境有官方4.7.2引擎，没有完整平台export templates；可启动PCK已支持，未生成独立Windows EXE。用户使用已有同版官方引擎运行 `godot --main-pack ssa-five-night-formal.pck`，或设置GODOT_BIN后运行启动脚本。

## 源码、patch与恢复

最终tracked树提交干净后，给构建命令加 `--source`，额外交付该HEAD的源码ZIP与相对批准基线 `6c14f659613d7eafb769441dde8e173ee533341a` 的binary patch。构建元数据记录commit与dirty文件；dirty构建只作开发证据，不作为精确源码交付。源码ZIP前还核验所有必需资源/动态源都已Git-tracked，阻止新文件静默遗漏。

历史移动使用单独可反向撤销commit、manifest与 `.gdignore`；源文件和SHA256保留，不永久删除、不改任何玩家存档。归档范围与仍保留的兼容消费者须按实际清单说明。优先 `git revert <归档提交>`；旧版本复现使用独立checkout，禁止从旧树直接覆盖dirty或untracked资料。
