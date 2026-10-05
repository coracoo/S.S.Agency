# 第四夜棺镜偏殿原稿派生资产

仅改变呈现。原角色、默认相机、完整可走边界、碰撞、交互、剧情及存档不变。目标位于开发证据 `.dream-loop/targets/night_4/`，生成图不作为运行实拍。

## 来源与重建

使用授权的 `Omagatoki_Corridor.blend`，SHA-256记录于manifest。旧杉木、石、和纸、瓦、灰泥五纹理及门格/梁架/曲瓦/自然石直接复用；界外杉叶改取同游戏首夜GLB，其hash另存manifest。纸棺、铜镜及连续树干布尔挖出的真实凹洞用原材质建模；无新贴图、外部包或图像背景。

```sh
blender --background --disable-autoexec --python assets/3d/night04_mirror/source/build_mirror.py -- /absolute/path/Omagatoki_Corridor.blend
```

`use_scripts=False`读取；原稿不写回；派生可编辑Blend移除Text，五图全部内嵌；运行时GLB不含相机、灯或碰撞。Godot仅wrapper载入，光由集成层接入。`shrine_source_helpers.py`供第五夜复用，不应在模块导入时开启或改写源文件。

## 空间

- 地板实际最高面0.022m，低于原调查金环
- 五后柱仍在x=-5.35/-2.6/0/2.6/5.35，z=-2.65；左粗柱占旧0.7m碰撞足迹
- 八角纸棺位于旧(0.8,0,-1.6)占地；斜铜镜下缘接棺底，无实时反射
- 半开门后可见真实凹空树；其前端与屋面后缘有约0.66m真实间隔
- 自然石均匀缩放并贴真实最低点；其他实体在后墙/旧碰撞内或bounds外
- 材质与UV保留，按逻辑合批；不能因网格计数宣称美术通过

## 验证

```sh
python3 -m unittest tools/campaign/test_night04_05_source_assets.py
python3 tools/campaign/run_environment_checks.py --nights 4
python3 tools/campaign/test_night04_05_source_assets.py --spatial
```

全bounds真胶囊采样脚本`tools/campaign/test_night04_05_source_assets.gd`必须先通过`tools/rpg/test_environment.gd`核验隔离user目录才能执行。不得直接写玩家user。

最终资源轻测包含GLB洞心射线、真实树屋间距、原图引用与纸人承托；全bounds为5883采样/4851可站点无新增穿模。美术结论仍须对应实际固定镜头与无HUD全景；此文件不替代实拍审查。

## 明确差距修正

- 放射状拼片树洞改为连续起伏树干上的布尔真凹洞，保留至少0.6m洞深
- 纸棺仅选原和纸图的平缓纤维区；不重绘或换图
- 镜面粗糙度0.58、metallic0.48、低specular，右侧默认镜头不再白盘
- 灯光独立于资产：4个无阴影局部灯；原directional动态阴影关闭
- 移除不适合平地的首夜坡地草组，避免保留高差造成浮草
