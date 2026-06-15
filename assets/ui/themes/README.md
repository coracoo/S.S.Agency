# UI 主题资源

本目录存放 Godot `Theme` 资源（.tres），统一全局 UI 样式。

## 计划创建的资源

| 资源 | 用途 |
|------|------|
| `battle_theme.tres` | 战斗场景全局主题：字体、颜色、按钮样式 |
| `menu_theme.tres` | 主菜单 / 设置界面主题 |

## 字体引用

- 正文字体：`res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf`
- 强调字体：`res://assets/fonts/Alibaba-PuHuiTi-Medium.ttf`
- 标题字体：`res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf`

## 颜色常量

参考 `docs/Art_Bible.md` 色板。

## 使用方式

在 `battle_scene.tscn` 的根 Control 节点上设置 `theme = battle_theme.tres`，所有子节点自动继承。
