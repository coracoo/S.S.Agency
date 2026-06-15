# AI 美术管线 — Codex（gpt-image2）使用指南

> 本项目 AI 生成风格化素材统一使用 **OpenAI Codex（gpt-image2）**。本文件规定 prompt 模板、输出规范、验收标准。

---

## 一、通用风格前缀

所有 Codex 生成请求必须附加这段前缀，确保风格统一：

```
Chinese folk horror, Hong Kong supernatural, Taoist exorcism,
dark gold (#B8954E) and cinnabar red (#C23B3B) accents,
xuan black (#1A1A1A) background,
old paper texture, ink wash, talisman paper, bronze patina.
NO western fantasy, NO magic gem, NO blue crystal, NO ornate gold filigree,
NO European swords, NO skull motifs.
```

## 二、素材类型与专用 Prompt

### 2.1 UI 底板 / 边框（NinePatchRect 用）

**输出要求**：PNG，透明背景，带可切分边框，推荐 `512 × 512`

**Prompt 示例**：
```
Chinese folk horror UI panel border, Taoist talisman-inspired frame,
xuan black interior, dark gold (#B8954E) thin border, cinnabar red corner accents,
old paper texture, subtle ink wash stains,
symmetrical, 9-slice ready, transparent background,
minimalist, game UI asset, 512x512.
```

**必须生成**：
- `ui_status_panel.png` — 左上角角色状态面板底板
- `ui_bottom_hand_panel.png` — 底部技能栏底板
- `ui_card_frame.png` — 卡牌/技能按钮边框
- `ui_diamond_button.png` — 菱形待机按钮
- `ui_party_frame.png` — 队伍角色头像框

### 2.2 技能图标（48×48 / 64×64 / 128×128）

**输出要求**：PNG，透明背景，三个尺寸各一份

| 技能 | Prompt 主体 | 风格关键词 |
|------|------------|-----------|
| 火焰 | 三昧真火 / 符咒火焰 | orange-red flame, talisman paper ash |
| 斩击 | 桃木剑 / 铜钱剑 | peach wood sword, copper coins |
| 灵魂 | 钟馗判官笔 / 勾魂锁 | judge brush, soul-locking chain |
| 符纸 | 黄符纸 + 朱砂符文 | yellow talisman, cinnabar rune |
| 糯米 | 糯米袋散落 | scattered glutinous rice |
| 墨线 | 墨斗弹线 | ink line, carpenter's ink marker |
| 铃铛 | 铜铃 + 音波 | bronze bell, sound wave |

**Prompt 示例（火焰）**：
```
Skill icon, Chinese Taoist flame, 三昧真火,
yellow talisman paper burning, orange-red fire,
ink line art style, minimal flat icon,
transparent background, 64x64, game UI asset.
```

### 2.3 角色半身立绘（256×256）

**输出要求**：PNG，透明背景，半身像，港式民俗风格

**Prompt 示例（凛音）**：
```
Character portrait, Hong Kong female exorcist,
short black hair, serious expression, dark jacket,
Taoist talisman earrings, dark gold and cinnabar red accents,
Chinese folk horror, 90s Hong Kong movie vibe,
half-body portrait, transparent background, 256x256.
```

### 2.4 环境物体贴图（64×64 / 128×64）

**输出要求**：等距视角，PNG，透明背景

| 物体 | Prompt 主体 |
|------|------------|
| 火盆 | 中式青铜火盆，燃烧木炭 |
| 水桶 | 木桶，水面反光 |
| 米袋 | 麻袋，散落糯米 |
| 铃铛 | 铜铃挂架 |
| 棺材 | 朱漆棺材，墨斗线缠绕 |
| 门 | 旧木门，符纸封条 |

### 2.5 特效精灵表（64×64 × 4帧）

**输出要求**：水平或垂直排列的 4 帧动画，PNG，透明背景

**Prompt 示例（火焰）**：
```
Sprite sheet, 4 frames, 64x64 each, Chinese Taoist fire,
orange-red flame flickering, upward movement,
transparent background, pixel-art-friendly, game VFX.
```

## 三、输出验收清单

- [ ] 透明背景（PNG）
- [ ] 无西幻元素
- [ ] 颜色符合 Art Bible 色板
- [ ] 尺寸符合要求
- [ ] 对于 UI 边框：四边可 9-slice 切分
- [ ] 对于动画：帧数正确，循环无跳帧

## 四、与项目对接

1. 使用 `docs/Codex_UI_Generation_Task.md` 中的清单批量生成 UI 素材，**覆盖同名文件**
2. 生成后图片放入 `assets/ui/generated/` 或 `assets/effects/sprites/`
3. 在 `data/ui_atlas.json` 中登记 9-slice 边距
4. 在 `Aseprite` 中重绘/精修动画帧（如需像素级调整）
5. 通过 `Godot Aseprite Wizard` 插件导入 `.ase` 文件
