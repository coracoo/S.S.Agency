# 第三夜同源露天石道与纸列

2026-10-04第二轮。仅替换第三夜艺术模型。目标为露天抬棺石道/神社后侧纸列，沿用首夜与用户认可的第二夜原材质风格。实际画面必须由Godot默认镜头实拍验收，资源/空间测试不能代替画面。

## 来源与安全

- `Omagatoki_Corridor.blend`：用户授权原稿，SHA-256见manifest。复用原和纸、石材、旧木图，石灯和自然岩石。
- `assets/3d/act01_approach/act01_approach.glb`：项目首夜同源石路、木鸟居、杉树、草叶几何。保留真实形体和UV，布局平移与等比缩放。
- 仅纸棺、旧箱、纸列衣袖和折头为原材质补建。纸人采用带实体薄边的多折衣片、袖片、空心折头，原和纸纤维图UV取原图清净区，避免把门纸树影斑缩成迷彩；图像原字节不改。
- 不绘制或处理纹理图像，不下载资产，不安装软件，不使用FAL。GLB仅嵌入实际使用的3张原图，不强行塞入未使用青瓦/灰泥。
- Blender `--disable-autoexec`、`use_scripts=False`读取原稿，派生源删除全部Text数据块；不写回原始来源。
- 灯/相机/碰撞均不导出；原物理、镜头、角色、锚点、返场、剧情/RPG不变。

## 重建

在仓库根目录执行：

```sh
blender --background --disable-autoexec --python assets/3d/night03_procession/source/build_procession.py -- /absolute/path/Omagatoki_Corridor.blend
```

现有Blender 4.3.2。`source/.gdignore`排除可编辑源的运行时导入。原稿world空间快照及首夜glTF网格按逻辑组安全合批；后柱独立，地板/高景独立，避免合批AABB横穿可达空间。

## 空间约束

- 旧bounds x±5.7、z±2.8完整保留；石板最高约0.032m，地表与旧物理对应。
- 五根范围内木柱中心x=-5.35/-2.6/0/2.6/5.35、z=-2.65；柱体0.26×3×0.26m。
- 纸棺中心(0.6,0.32,-1.55)，主体1.845×0.545×0.795m落在原1.85×0.55×0.8m足迹内；抬杆不越出旧足迹。
- 木箱(1.6,0.28,-2.05)，1×0.5×0.55m原足迹。
- 七纸人和4石灯均在旧后墙之外。可见低围垣约0.6m，纸人底部0.6m，后侧真实泥土台顶面0.58m支撑整列。后栅栏退至纸列背后，避免生成目标里的遮躯问题。
- 前岩和草丛在可走边界之外，真实最低点埋土，石体不拉扁。
- 光照锚点`StoneLanternLightAnchor_00..03`供集成层使用；GLB自身不带灯。

## 轻测

```sh
python3 -m unittest tools/campaign/test_night03_source_asset.py
NIGHT03_RUN_GODOT=1 python3 -m unittest tools/campaign/test_night03_source_asset.py
```

Godot测试先实际核验隔离user目录，再运行5883点全bounds真实0.22m半径/1.4m高胶囊采样。导入/导出使用证据上级`godot-import.lock`，提交使用`git-commit.lock`；只提交该资源和对应第三夜wrapper/测试文件。

第二轮同步独立night_3_lighting.gd：冷夜环境、两石灯暖池、一棺缝冷光，3个无阴影局部灯；中央注册由集成线完成。土台侧面按主法线投影UV，前坡接缝采用真实斜土坡，不贴假背景图。
