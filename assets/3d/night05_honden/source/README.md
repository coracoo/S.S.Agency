# 第五夜本殿与开放神木庭

同源真实3D资源。只改变美术及独立灯层，不改原角色、镜头、交互、剧情、全bounds、碰撞或存档。第五夜target仅是目标，最终判断使用正式Godot stage固定镜头及无HUD全景。

## 来源与重建

复用授权`Omagatoki_Corridor.blend`的旧杉木/和纸/青瓦/石/灰泥五张原图，以及真实木构、格扇、曲瓦、石灯、自然岩。两侧杉叶取同游戏首夜`act01_approach.glb`，两个源文件hash记录在manifest；未下载或创作新纹理。

```sh
blender --background --disable-autoexec --python assets/3d/night05_honden/source/build_honden.py -- /absolute/path/Omagatoki_Corridor.blend
```

构建只读原稿，`use_scripts=False`，派生源移除全部Text。脚本通过相邻第四夜`source/shrine_source_helpers.py`复用无顶层文件副作用的构建工具；两个目录共同保留。GLB五图内嵌，无外部纹理URI、相机、灯或碰撞。

## 真实空间

- 前庭石板最高0.021m，原调查金环仍在其上
- 五根前柱与原碰撞对齐；左石灯高基和右木牌仅占原实体足迹
- 神木是连续树干上的真实布尔凹洞，洞内原蓝色棺纹为细实体嵌线，没有面向镜头的背景图
- 双檐本殿整体退在神木后，树/绳/枝与完整屋面真实间隔>0.2m；禁止用HUD遮盖相交
- 原纸人列队全在后墙之外，薄折纸几何，脚底与后平台0.61m表面真实接触
- 空棺位于原(0.8,0,-1.6)足迹，棺纹语义沿用既有剧情
- 石、石灯等器物保持原比例并按最低点贴地；无新增collider

## 轻量复验

```sh
python3 -m unittest tools/campaign/test_night04_05_source_assets.py
python3 tools/campaign/test_night04_05_source_assets.py --spatial
python3 tools/campaign/run_environment_checks.py --nights 4,5
```

`--spatial`先核验Godot真实user目录隔离，然后使用0.22m×1.4m胶囊采样两夜完整bounds。第五夜5883采样/4779可站点；原14碰撞hash必须保持不变。资源测试递归检查图像引用、实际地板高度、真实树屋间距、洞心射线深度、纸人承托。

`night_5_lighting.gd`只添加五盏无阴影局部灯与冷环境，不改变摄像机。性能应引用实际renderer数据，三角/mesh计数不能代表目标GPU帧率。已拍的R03展示几何与光照；R04仅修界外纸人承托并移除保留坡地高差的浮草组，需对应最终固定镜头图复核。
