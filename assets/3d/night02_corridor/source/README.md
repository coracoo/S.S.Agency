# 第二夜原回廊派生资产

本目录是2026-10-04获批的单场景质量试点。只改变第二夜艺术；角色、镜头、交互登记、旧碰撞与存档均不变。

## 来源与安全

- 原稿：用户Library中的 `Omagatoki_Corridor.blend`，原始2026-09-30回廊试样；来源SHA-256见manifest。
- 原稿提供旧杉木、和纸、青瓦、石材与灰泥五张内嵌底色图，以及真实可旋转的门扇/编绳/铜铃/屋檐/石灯/水钵/自然岩层。
- 不执行原文件内嵌文本；使用 `--disable-autoexec` 与 `use_scripts=False` 打开。派生文件内已移除全部Text数据块。
- 原文件不写回。没有下载第三方资产、安装软件、调用FAL或修改贴图图像。
- `night02_corridor_editable.blend` 保留逻辑父级、原材质槽与UV；合批只发生在同逻辑部件内。该目录用 `.gdignore` 排除运行时导入。

## 重建

在仓库根目录执行：

```sh
blender --background --disable-autoexec --python assets/3d/night02_corridor/source/build_corridor.py -- /absolute/path/Omagatoki_Corridor.blend
```

需要现有Blender 4.3.2。产物 `../night02_corridor.glb` 使用glTF Y-up，Godot wrapper直接载入，无额外缩放。纹理全内嵌。Godot首次导入自动产生五张图像文件和 `.import` 元数据；这些是引擎从原嵌入图解包的逐像素副本，不是新贴图创作。

## 空间与组织

- 实木长板横向铺设，钉、端缝、磨损棱线来自原稿；地板顶面约0.03m。
- 五根场内后柱与原物理柱中心对位：x=-5.35/-2.6/0/2.6/5.35，z=-2.65；横向延伸构件仅用于默认镜头左右移动连续性。
- 纸门及门把位于后墙物理内沿之外；屋檐、编绳与灯在角色头顶以外。
- 铜铃x=-2.5、残文x=-0.6、旧物组x=1、引路灯x=2.5。旧物箱实体足迹x=1.1..2.1、z=-2.325..-1.775。
- 可达区不放新实体阻挡；灯柱/水钵放界外，所有GLB不包含碰撞。
- 不导出相机或灯。灯光由Godot集成层独立控制。

## 验证

```sh
python3 -m unittest tools/campaign/test_night02_source_asset.py
python3 tools/campaign/run_corridor_procession_art_checks.py --night 2
python3 tools/campaign/run_environment_checks.py --nights 2
```

轻量资源/空间测试不能代替画面验收。正式stage、固定默认镜头、1920×1080、原角色的每轮真实截图由集成线生成，再交独立图像评审。

## 后续场景复用接口（第三至第五夜）

`adaptation_helpers.py` 可直接加入Blender脚本搜索路径后导入，无顶层场景副作用：

- `affine(scale, offset)`：只在明确需要改变尺寸的平面建筑件上使用非均匀缩放。不可用整组x/y/z拉伸来铺排石、灯、铜器；布局中心应独立移动。
- `uniform_grounded_transform(mesh, center_xy, uniform_scale, bottom_z)`：输入已烘成世界坐标的源Mesh，保持器物/石体比例，将真实最低点对齐指定地面。地面起伏时逐个指定bottom_z；不要让物体在远处统一平面上悬浮。
- `planar_uv(mesh, metres_per_repeat, axes, offset)`：用实际米制调整原图UV，不画图、不处理图像。木地板长向对应木纹U，短向对应V，必须按默认镜头检视纹理尺度。纸门、铃等异形物体优先保留原UV。
- `mesh_bounds(mesh)`：读取世界化源网格范围，供比例/最低点/对位检测使用。

本构建脚本里的 `batch(name, source_names, transform, parent)` 和 `join(name, objects, parent)` 是逻辑合批范例。复用时按场景提供自己的原网格字典，不要直接import会执行构建的build_corridor.py。

必须保留的约束：

1. 安全读取原blend（--disable-autoexec/use_scripts=False），先烘到世界坐标再脱离父级；源文件不写回。派生源中清掉嵌入Text，所有纹理继续pack。
2. 合批以逻辑部件/材质/相同安全高度区为界。后柱不能合成跨越可走间隙的大AABB；地板与零散高叶分批，否则会产生金环/可达性假阳性。材质槽与UV不可用纯色override覆盖。
3. 本工程Blender Z-up导出glTF Y-up后，Godot(x,y,z)=(Blender x,z,-y)。可走区内新实体只能匹配旧碰撞足迹，或在角色头顶之外；不能为了模型补新collider。
4. 旧碰撞/锚点/bounds/交互哈希保持不变。使用真实0.22m×1.4m胶囊全bounds采样，不只中央走线和锚点。
5. 导出后递归检查所有材质纹理引用（包括pbrMetallicRoughness/normal/emissive及扩展），确保每个texture/image/bufferView有效，图片内嵌；导出不含相机灯。
6. `source/.gdignore` 排除可编辑源；Godot导入和Git提交使用外部共享锁。只stage自己拥有的资源。运行性能报告必须注明渲染器，mesh数不等同draw-call数。
7. 每轮先实机默认center/left/right图，再按最大差距调整。不要依节点数、Blender美图或技术断言宣布美术完成。固定角色、相机和已有交互信息，别通过改它们迎合生成目标。
