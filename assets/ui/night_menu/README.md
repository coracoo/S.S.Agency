# 夜巡菜单分层素材

本目录是已确认紧凑旧年代菜单方案的生图生产素材。所有 PNG 由生图生成后机械裁切；透明区域保留 Alpha。没有烘焙文字、数值、角色或稀有度。

- panel / inset：主框与内凹分区
- button / button_selected / button_primary / button_disabled：普通、选中、主动作、禁用状态
- focus：中间完全透明的独立焦点描边
- healing_potion / mana_potion / revival_potion / cleansing_powder / energy_tea / guard_charm / moxa_roll：七件现有道具
- weapon / armor / accessory：现有三槽标准配装
- gauge_track / gauge_hp / gauge_mp：空槽、红血条、蓝灵力条

控件的布局、文字、数量、效果、选中态与输入仍由游戏模型实时驱动。运行时 `night_menu_art.gd` 在内存规范纹理尺寸，再以九宫格或 TextureProgressBar 保留边框厚度；不改写这些原 PNG。

发布脚本只收集本目录直接 PNG 到原始字节与资源闭包。新素材须同时验证运行时状态、透明边缘、文字留白、键鼠命中、三种窗口尺寸及正式导出依赖。
