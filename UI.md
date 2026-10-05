# 当前 UI 设计入口

> WIP开发检查点：用户要求先push本地检查，整体画面风格尚未最终验收。

更新：2026-10-05。正式入口为 `scenes/campaign/title.tscn` 的五夜夜巡 RPG；旧 v3 标题、扇形手牌与“新的委托”不是当前入口。

当前 UI 采用墨青底、米白主字、灰绿次级、暗朱主动作与少量赭金焦点。共享语义色见 `data/ui_theme.json` 的 `ui_*` 字段，共享控件见 `scripts/rpg/ui/ui_kit.gd` 与 `scripts/ui/theme.gd`。

- [本轮界面与环境说明](docs/campaign/ui-atmosphere.md)
- [五夜主线与验证](docs/campaign/README.md)
- [2026-10-05实测记录](docs/verification/2026-10-05-ui-atmosphere-polish.md)
- [历史 UI 诊断](docs/archive/2026-09-30-before-v4/UI.md)，仅供追溯

验收须同时看实际画面与真实输入：normal/hover/pressed/disabled/focus、标题/编队/对白/地图/战斗、模态 Tab 与四向焦点、关闭后的按键释放保护。目标是在1920×1080与1280×720保持中文可读、不截字、不压人物或控件。
