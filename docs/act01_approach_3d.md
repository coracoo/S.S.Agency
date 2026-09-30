# 第一幕「参道」3D 美术预览

这是第一幕的独立场景试样：把现有参道的平地、向右上升的石阶、鸟居和「水钵冷光」做成立体可检查的场景。正式游戏仍从 `scenes/v3/title.tscn` 启动；探索、卡牌、对话、存档、xlsx 和关卡 JSON 均未改动。

## 打开预览

使用 Godot 4.6 系列，首次打开项目后等待 GLB 导入。在编辑器打开 `scenes/preview/act01_approach_3d.tscn`，按 **F6** 运行当前场景。这里的“独立”指独立运行的场景文件，不是独立安装包；本次未生成或验证 Windows 可执行文件／PCK，也未改导出预设。

也可从项目目录执行：

```sh
godot --path . --rendering-method gl_compatibility res://scenes/preview/act01_approach_3d.tscn
```

Windows 现有安装示例：

```powershell
& 'J:\godot\Godot_v4.6.3-stable_win64.exe' --path 'J:\godot\S.S.Agency' --rendering-method gl_compatibility 'res://scenes/preview/act01_approach_3d.tscn'
```

按键和左上角按钮：

- `1`：固定画卷镜头
- `2`：斜侧空间检查镜头
- `C`：显示／隐藏现有凛音二维站姿，作为比例参照；默认隐藏
- `H`：隐藏／恢复全部预览说明
- `R`：回到初始镜头、隐藏人物、恢复说明
- `Esc`：退出预览

这是静态美术预览，没有新写故事或接入调查、行走、碰撞、导航、战斗。人物使用现有 `assets/chars/anims/rinne_idle_f1.png`，不是新增 3D 角色。

## 实际 Godot 截图

以下图片来自 Godot 4.6.3 Compatibility / OpenGL 的 1920×1080 真实视口，并非 Blender 渲染或合成图：

![参道固定画卷镜头](reference/act01_approach_3d/hero.png)

[无说明画面](reference/act01_approach_3d/hero_clean.png) · [空间检查角度](reference/act01_approach_3d/inspection.png) · [原角色比例参照](reference/act01_approach_3d/character_scale.png) · [原版标题回归截图](reference/act01_approach_3d/original_title.png)

## 文件与来源

- `assets/3d/act01_approach/act01_approach.glb`：运行资产，包含材质与 5 张内嵌纹理
- `assets/3d/act01_approach/source/act01_approach.blend`：Blender 4.3.2 可编辑源文件，纹理全部 packed
- `source/.gdignore`：阻止 Godot 再次导入 Blender 源文件；运行预览无需安装 Blender
- `scenes/preview/act01_approach_3d.tscn`：模型实例、实际三维灯光、环境、两个镜头和说明 UI
- `scripts/preview/act01_approach_preview.gd`：仅处理检查镜头和显示状态
- `tools/preview/`：场景契约回归及截图工具

第一幕构图来自当前 `assets/bg/approach/l2_test.png`；层级、暖旧木／和纸／靛青石瓦的方向遵循 `docs/Art_Bible.md`。材质与部分道具细节来自用户提供的 `Omagatoki_Corridor.blend`，重新构成参道，而非把第二幕回廊直接接到游戏中。没有新增第三方模型、付费素材或外部贴图依赖。

最终 GLB：67 个逻辑网格、129,038 三角面、27 个材质、5 张内嵌 PNG、一个内嵌二进制 buffer、0 外部 URI、0 导入相机／灯光。体积约 10.4 MiB。相对于参考原型的 1,066 个网格对象，按地形、石阶、鸟居、注连绳、器物与植物合组；这不等于已完成目标硬件性能验收。

Blender 使用 Z 轴向上，GLB/Godot 使用 Y 轴向上，1 单位约 1 米。主要路径左侧为平地，16 级石阶向右上升至约 2.88 米。模型边界约 `(-10.73,-0.92,-4.55)` → `(11.25,7.74,3.46)`。

保留的定位空节点及其 Godot 坐标：

- `BasinReflectionAnchor`：`(0.12, 0.714, 1.94)`
- `LanternLightAnchorLeft`：`(-6.25, 1.7716, 0.30)`
- `LanternLightAnchorStairs`：`(4.80, 3.4898, 1.62)`
- `LanternLightAnchorUpper`：`(8.50, 4.0548, -1.88)`
- `ShrineLightAnchor`：`(7.16, 4.15, -1.07)`

水面冷色是美术线索表达，尚未连接 `basin_reflection` 的调查触发或实时反射。预览灯光在 `.tscn` 内独立配置；Blender 灯光不会当作运行灯光导出。

Godot 的 GLB 导入设置将内嵌图片保留在导入场景中，避免旁边生成五份重复 PNG；其含义见 [Godot 4.6 的内嵌图像导入说明](https://docs.godotengine.org/en/4.6/classes/class_gltfstate.html#enum-gltfstate-handlebinaryimagemode)。

## 验证与已知限制

复现导入和回归：

```sh
godot --headless --path . --import
godot --headless --path . --script res://tools/preview/test_act01_approach_preview.gd
```

复现四张预览截图（需要图形显示，不能加 `--headless`）：

```sh
godot --path . --rendering-method gl_compatibility --script res://tools/preview/capture_act01_approach.gd
```

- Blender 源文件重新打开、5 张 packed 图片像素可读、无链接库／嵌入脚本
- 空场景独立回导 GLB，核对网格、材质、纹理及锚点
- Godot 导入与预览脚本解析；19 项节点／按键处理器／按钮信号回归断言
- 图形界面实际点击镜头／人物按钮，验证按钮焦点下 C、H、R、1／2 与 Esc；窄窗口保持完整横向路线
- 原有 `tools/test_*.gd` 共 9 项测试，新增预览测试另计
- 图形运行原版默认入口，点击「继续退治」进入参道并显示既有开场对话

云验收机使用 Mesa llvmpipe 软件渲染，不作为目标平台帧率保证。其 Vulkan 环境缺少 `VK_KHR_surface`，Forward+ 尝试自动回退为 Compatibility，因此未验证 Forward+ 专用的 SSAO／Glow 效果；本页截图均按 Compatibility 标注。

基线已存在且本次未修改的警告：标题和遮挡测试请求不存在的 `assets/bg/parallax/test_approach_fg2.png`；遮挡测试退出时报告 ObjectDB 实例泄漏。其他测试仍需按各自日志判断，不能将本预览验收当作整场通关或游戏平衡验证。
