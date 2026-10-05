# 第二夜HD2D完整视觉variant

2026-10-04授权试点：保留3D场景+2D角色，扩大前庭、侧廊和远景的视觉空间。这是完整可关闭替换资产，不是叠在旧建筑上的addon。现可玩矩形、角色/调查坐标、碰撞和剧情不扩张。

## 来源和重建

- 原第二夜R03 GLB SHA256：a95880eeb4ebe20c1c7dd20867273c2ae56fc7b94bfd9d918641d3c6480ec893，构建前后均核对，文件不写。
- 建模源：相邻night02_corridor/source/night02_corridor_editable.blend（R03派生）及首夜act01_approach.glb。各来源hash写入manifest。
- 5张同源图片按实际内嵌字节去重；没有新增、生成、程序重画图片，没有下载模型。
- 可编辑源：night02_hd2d_editable.blend，全部图内嵌；移除文本脚本、灯和相机。source目录以.gdignore排除游戏导入。

```sh
blender --background --disable-autoexec --python assets/3d/night02_corridor_hd2d/source/build_hd2d.py
```

使用现有Blender 4.3.2，源blend以use_scripts=False打开。GLB按glTF Y-up导出，Godot直接加载，不需要额外尺度。

## 接口与五层

开启profile时隐藏原SourceCorridor，再实例化本完整variant；关闭时移除此variant并显示原SourceCorridor。不得同时显示两套中景。

- MidCorridor：原可玩中景，纸门/铃/残文/旧物/引路灯和已校准灯父级名称/坐标保留。只剪掉界外过长直檐并封到侧翼。
- NearFrame：左右界外杉木枝叶，中央x±6.8空。用于很弱的近景边缘虚化，不是全画面模糊层。
- OuterForecourt：真实石板庭院、台基/土坡、岩岸与两座石灯。角色不能进入，原界限不变。
- SideVeranda：源木板/屋檐/梁柱转向组成侧廊，实体x绝对值≥6.8；低栏表达场景边沿，不新增路线。
- DistantGate：右侧空窗里的首夜同源鸟居、左侧神龛、杉林和真实地形承托。允许冷调/弱虚化。

每层真实Godot世界坐标包围盒见manifest.json。HD2D试值是正交size9.2、offset(0,6.2,11)、look_at玩家根+UP1.1；镜头与Compatibility局部深度shader由独立profile负责。本资产不含相机/灯/碰撞。

## 验证

```sh
python3 -m unittest discover -s tools/campaign -p test_night02_hd2d_asset.py
python3 tools/campaign/run_night02_hd2d_checks.py
```

检查独立资源、所有递归纹理索引、5图内嵌、来源/fallback哈希、层名与预算；Godot先核验隔离user目录，然后验证四调查父级坐标与旧场景相同、5883真实胶囊采样没有新可穿实体、NearFrame和SideVeranda逐mesh不进中央x±6.8。

首版107mesh、244115三角、208材质surface、44材质，图片5。surface与材质数包含两份源场景的语义材质，并不等于GPU的最终drawcall。真实性/可读性与性能必须看实际Godot固定镜头图和运行样本，技术通过不等同视觉完成。
