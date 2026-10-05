# 后四夜环境艺术与复验

当前状态：技术集成与可达性回归已建立。第二至第五夜均已换用首夜/原稿同源材质的可编辑GLB与独立冷暖照明。第二夜另有默认关闭的HD2D呈现试点，视觉构图仍在验证。

第二至第五夜仍使用同一正式五夜主线、角色、默认镜头和存档。环境由独立真实3D网格模块构成，不是背景图；第一夜参道保持原样。

- 第二夜：木制回廊、朱柱格栅、挂铃红线、送行残文、旧物台与引路灯。
- 第三夜：露天石路、神社围垣鸟居、抬杆纸棺与错列折纸队伍。
- 第四夜：半开纸门的棺镜偏殿、铜镜、红布、远处庭院与暖灯。铜镜是几何与材质效果，不是实时反射。
- 第五夜：本殿、台基叠檐、御神木与树洞、注连绳垂纸、石灯和纸人。

## 不变的运行约定

`chapter_geometry.gd` 保留原全部静态碰撞，将第二至第五夜旧占位网格/灯藏在 `LegacyCollision` 下；`EnvironmentArt` 只创建呈现节点。旧柱、箱、棺的实物位置由新艺术覆盖。剧情、交互坐标、三个安全锚点、边界、角色尺寸与存档格式不变。正常镜头不变；仅显式开启第二夜HD2D试点时使用较远、略俯视的独立相机。

每夜模块提供 `static build(parent: Node3D, config: Dictionary) -> void`。不要在艺术模块写档、发奖励、处理输入、添加碰撞或推进剧情。

## 自动回归

```sh
python3 tools/campaign/run_environment_checks.py --scene-flow
python3 tools/campaign/run_checks.py
python3 tools/campaign/run_end_to_end.py --output-dir /absolute/outside/repo/e2e
```

环境检查先核验引擎实际 `user://` 已处于临时目录，再比较修改前记录的五夜碰撞形状、世界变换、层/掩码与锚点/交互登记。第二至第五夜另外测试与正式角色相同尺寸的胶囊、地面、连续中央路径和四向边界。

固定基线在 `tools/campaign/fixtures/environment_collision_baseline.json`。`--record-baseline` 只用于未来另有批准的物理变更之前记录证据，会拒绝覆盖已有文件，不得借更新基线掩盖回归。

## 正式游戏视角截图

在有显示服务的环境中使用：

```sh
python3 tools/campaign/run_environment_checks.py --graphical \
  --snapshot-results /absolute/e2e/sendoff \
  --output-dir /absolute/outside/repo/environment-screenshots \
  --log /absolute/outside/repo/environment-graphical.log
```

可加 `--nights 2` 只检查与截图第二夜，默认是 `2,3,4,5`。`--snapshot-results` 应指向既有通过的模型E2E结果目录；工具只采用 `status=pass` 且真实推进到各夜的安全快照，按正式存档校验写入独立临时user目录后用 `ChapterSession.resume()` 恢复，加载正式场景、人物和HUD。原始E2E来源路径保存在 `render-report.json`。

截图夹具仅关闭开场对白以露出环境，并将玩家放到边界内的左、中、右三个位置；不提交新的剧情或战果。PNG由Godot视口实际渲染后保存，1920×1080，保留正式默认镜头。该夹具不等于新一轮人工全篇通关。

`render-report.json` 记录真实渲染设备/API、镜头、玩家位置、网格数及45帧实测间隔（均值/中位/p95）。软件渲染的帧间隔包含CPU和显示同步，不可当成用户GPU性能认证。主线两结局/52剧情节点由独立E2E覆盖。

图形命令可加 `--record-walk` 额外保存每夜约3秒真实左右行走的JPEG序列（Godot直接保存，避免PNG编码大幅降低采样率）。每帧采集时刻写进报告的 `walk_capture`，编码时应保留这些时间间隔；该采集会额外产生I/O，因此独立45帧性能样本在录制之前测量。

`--overview` 额外输出第四/第五夜 `night_4_overview_not_default.png`、`night_5_overview_not_default.png`，仅在视觉夹具中临时拉远并隐藏HUD以检查叠檐与神木整体。它是艺术全景检查图，不是默认游玩镜头；正式游戏镜头和HUD不做任何更改。

`--nights 1,2 --comparison` 可复验首夜GLB与回廊的风格对照。两夜均保留1920×1080、同一凛音尺寸、正式size8镜头；首夜左右采样采用登记的坡面安全点。另存的 `center_no_hud_default_camera` 只隐藏HUD，绝不改变镜头角度或比例。

视觉迭代可指定 `--round-id`。每次图形运行附带 `capture_metadata.json`，记录开始/结束HEAD、dirty文件、相关场景与3D资产SHA256；若捕获期间相关内容变化，运行记为失败。截图固定idle动画第0帧、朝向1、发丝相位0，角色实际pixel_size和镜头记录在渲染报告。`.dream-loop/` 为不提交、不导入、不发布的轮次工作目录。


## 第二夜原稿照明试点

`night_2_lighting.gd` 仅影响第二夜：冷色环境填光0.18、五个错开实际灯位的暖光池，以及五柱脚/旧箱的小面积静态柔接触暗部。GLB只提供模型/材质，不含灯或相机。第一夜照明保持原值；第三至第五夜分别由对应 `night_3/4/5_lighting.gd` 提供冷色填光与3/4/5盏有界局部光，均不使用动态阴影。

一轮同场景/同中心镜头/同idle0 A/B确认，软件渲染上的方向阴影造成梁、裙板和台沿斜纹，且比无阴影慢约18%；多灯叠加也额外增加约11%帧时间。现保留方向受光，取消该动态阴影与相邻暖灯重复照射。灯位下移到灯罩底边以避免正照自身纸面。

可用 `--nights 2 --graphical --lighting-ab` 在临时场景中对照当前配置、关闭方向阴影、仅最近三盏墙灯；不会保存生产配置。实际选中灯名/位置/能量/范围及三个45帧样本写入渲染报告。该诊断只改变临时场景显示状态，不可冒充默认游玩图。

## 第二夜HD2D可逆试点

第二夜HUD右上新增“HD2D试点：关/开”按钮，默认关闭；进入探索后点击开启，再点关闭恢复。按钮旁提示可能降低帧率；对白、仪式、战斗和转场期间禁用，其他夜不显示。状态只在本次二夜场景内有效，不写入存档。内部沿用 `stage.set_hd2d_experiment(true/false)`：开启完整扩展资产、size9.2/offset(0,6.2,11)正交相机与前后景分层模糊，关闭恢复原R03资产与size8/offset(0,4.8,11)镜头。重复切换复用实例，不改存档或可走区域。该开关只对第二夜有效。

当前Compatibility不支持引擎内置CameraAttributes DOF；此试点使用真实screen/depth纹理重建世界Z，以清晰带覆盖全可走区，九点采样柔化带外的近/远3D环境。它是艺术分层景深，不是物理镜头DOF。清晰区使用discard保留原像素，CanvasLayer HUD正常后绘。人物头发/武器与金环已经通过实际开关像素对照，仍应在资产/相机变化后复验。

```sh
python3 tools/campaign/run_environment_checks.py --nights 2 --hd2d-camera --hd2d-profile
python3 tools/campaign/run_environment_checks.py --nights 2 --graphical \
  --hd2d-experiment --comparison --snapshot-results /absolute/e2e/sendoff \
  --output-dir /absolute/outside/repo/hd2d
```

第二条命令使用真实stage接口并在捕获结束后检查关闭恢复、世界状态与存档字节未变化。无HUD文件明确标记 `no_hud_hd2d_camera`，不冒充原默认镜头。

`run_hd2d_probe.py --snapshot-results /absolute/e2e/sendoff --output-dir /absolute/outside/repo/probe --hd2d-asset` 另存off/identity/depth/blur四张完整场景和明确标记的近/远棋盘诊断图；棋盘诊断图隐藏遮挡美术，不能当游戏美术完成图。像素门禁要求空操作全屏一致、焦内角色一致、近远探针有真实变化。性能样本仅代表记录中的软件渲染设备，不代表用户GPU。
