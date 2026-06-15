# 特效资源管线

本目录存放所有环境连锁反应和战斗反馈的特效资源。

## 目录结构

```
assets/effects/
├── particles/      # GPUParticles2D 预制场景（.tscn）
├── shaders/        # ShaderMaterial 用 .gdshader
└── sprites/        # AnimatedSprite2D 用精灵表（.png）
```

## 使用方式

1. **一次性爆发特效**（爆燃、受击、水缸倾倒）使用 `GPUParticles2D` 预制体实例化
2. **持续循环特效**（火焰、水波、灵气雾气）使用 `AnimatedSprite2D` 或 `ShaderMaterial`
3. **移动动画**（推/拉物体、单位行走）使用 `Tween` + `AnimatedSprite2D`

## 必备特效清单

| 特效 | 类型 | 状态 | 备注 |
|------|------|------|------|
| 火焰持续 | AnimatedSprite2D | 待制作 | 64×64 × 4帧 |
| 水波持续 | AnimatedSprite2D | 待制作 | 64×64 × 4帧 |
| 糯米散落 | GPUParticles2D | 待制作 | 米白颗粒 |
| 符纸浮动 | AnimatedSprite2D | 待制作 | 金黄，轻微旋转 |
| 墨线发光 | Line2D + Shader | 待制作 | 纯黑连线 |
| 灵气雾气 | ShaderMaterial | 待制作 | 紫黑半透明 |
| 点燃爆发 | GPUParticles2D | 待制作 | 橙红粒子向上 |
| 爆燃冲击 | GPUParticles2D + 屏幕震动 | 待制作 | 配合 Shaker 插件 |
| 受击闪烁 | Tween + GPUParticles2D | 待制作 | 白色闪烁 100ms |
| 封印升起 | GPUParticles2D | 待制作 | 金色符文旋转 |

## 制作工具

- **Aseprite**：绘制 64×64 多帧动画精灵表
- **Godot Aseprite Wizard 插件**：自动导入 `.ase`/`.aseprite` 为 `SpriteFrames`
- **Shaker 插件**：屏幕震动
- **Material Maker**（可选）：程序化生成烟雾/雾气纹理
