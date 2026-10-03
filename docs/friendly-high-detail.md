# 友方高细节逐帧角色

Godot 4.6。六位人物、七种形态：凛音、焰华剑士、焰华术士、薄荷、岑照、苏合、清明。

## 预览

从编辑器打开 `scenes/preview/friendly_high_detail_gallery.tscn` 并运行当前场景，使用顶部形态按钮切换。A/D 移动，J 攻击；其他反应动作见画面按钮。原第一幕入口保持原状。

每套素材在 `assets/chars/pixel/<id>/high_detail_complete/`：透明独立 PNG、各状态图集及 manifest。角色身体参考高度为1024像素，画布由武器与动作范围单独决定；不应按画布高度判断人物身高。世界身高保持原角色值。图集单页不超过4096像素，焰华剑士步行分两页，矩形与页号在 manifest 的 atlas 字段。

## 动作与表现

素材由图像生成后做确定性的尺寸、透明边和脚锚整理，保留高分辨率原图细节，并非传统手工逐像素绘制。

每形态22张真实绘制姿态：4待机、8步行、6攻击/施术、受击/防御/失能/恢复各1张。待机往返3秒，步行0.50302秒，攻击0.460秒；失能保持到恢复。单姿态反应不是多帧过渡。逐帧步行使用左右相位交换，没有骨骼腿替代。

场景融合通过显式可撤销的角色材质与逐帧脚点阴影启用。脚点有PNG校验值，错误或缺少标注时使用保守根部柔影。它是绘制接触点的地面投影，不等同于坡面运动学脚锁。

焰华两形态共用身份，预览只切视觉，不新增HP或行动资源；剧情解锁规则仍由游戏系统管理。苏合的青色不透明长裤属于服装适配候选，尚保留待确认标识。

## 验证

- `python tools/characters/validate_assets.py --all`
- `python tools/characters/run_checks.py --suite all`
- `godot --headless --path . --script res://tools/spikes/test_character_scene_integration.gd`
- `godot --headless --path . --script res://tools/spikes/test_character_contact_routing.gd`
- `godot --headless --path . --script res://tools/spikes/test_character_scene_teardown.gd`
- `godot --headless --path . --script res://tools/spikes/test_cenzhao_high_detail_motion.gd -- guard`（最后参数也接受其余形态ID）

角色测试使用隔离存档；七形态相位覆盖用固定模拟60fps，以避免把同步PNG解码耗时计入测试的相位观察窗口。这不是实际加载速度或性能测试。完整项目回归沿用项目现有测试入口。

## 范围与预算

本版本为可运行的绘制动作候选。个别连续帧仍有衣摆、发梢、盾纹等细节跳变，凛音攻击第三至第四姿态收势较急。没有声称所有动作达到逐帧精修终稿。

仅按所选形态加载纹理，相同PNG字节通过弱引用共享纹理；最后持有者释放后不强留纹理。大尺寸22帧一次加载仍会有同步解码开销。RGBA8显存应按画布宽×高×4×独立帧数估算，不能用压缩PNG文件大小代替；还须额外计算合成视口与驱动开销。当前录屏来自软件渲染环境，以固定模拟时间30fps编码，用于视觉验收，不代表目标硬件性能。
