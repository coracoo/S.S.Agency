# Codex 生成任务 — UI 美术素材批量替换

> 用 OpenAI Codex（gpt-image2）生成以下素材，**直接覆盖项目内同名文件**，使 UI 从西幻风格转为港式民俗/中式灵异风格。

---

## 通用 Prompt 前缀（每个请求都必须加）

```text
Chinese folk horror, Hong Kong supernatural, Taoist exorcism,
dark gold (#B8954E) and cinnabar red (#C23B3B) accents,
xuan black (#1A1A1A) background,
old paper texture, ink wash, talisman paper, bronze patina.
NO western fantasy, NO magic gem, NO blue crystal, NO ornate gold filigree,
NO European swords, NO skull motifs.
Game UI asset, transparent background, PNG.
```

---

## 一、UI 底板 / 边框（NinePatchRect 用）

所有底板都需要 **9-slice 可切分边框**：四边和四个角纹理连续，中间区域可拉伸。

### 1. `assets/ui/generated/ui_status_panel.png`

- **尺寸**：512 × 512
- **用途**：左上角角色状态面板（280 × 300）
- **9-slice 边距**：左 58 / 上 88 / 右 58 / 下 88
- **Prompt**：
```text
Chinese folk horror UI character status panel, Taoist talisman frame,
xuan black interior, dark gold thin border, cinnabar red corner accents,
old paper texture, symmetrical, 9-slice ready, transparent background,
minimalist, 512x512.
```

### 2. `assets/ui/generated/ui_bottom_hand_panel.png`

- **尺寸**：512 × 256
- **用途**：底部技能/卡牌栏底板
- **9-slice 边距**：左 100 / 上 78 / 右 100 / 下 78
- **Prompt**：
```text
Chinese folk horror bottom action bar panel, dark gold border,
xuan black interior, subtle talisman paper texture,
horizontal layout, 9-slice ready, transparent background,
minimalist, 512x256.
```

### 3. `assets/ui/generated/ui_info_panel.png`

- **尺寸**：512 × 256
- **用途**：技能描述/信息提示面板
- **9-slice 边距**：左 58 / 上 78 / 右 58 / 下 82
- **Prompt**：
```text
Chinese folk horror info tooltip panel, xuan black interior,
dark gold border, old paper texture, 9-slice ready,
transparent background, minimalist, 512x256.
```

### 4. `assets/ui/generated/ui_card_frame.png`

- **尺寸**：256 × 256
- **用途**：卡牌/技能按钮边框（82 × 102）
- **9-slice 边距**：左 58 / 上 78 / 右 58 / 下 82
- **Prompt**：
```text
Chinese folk horror card frame, yellow talisman paper edge,
dark gold thin line, cinnabar red seal accent,
rectangular, 9-slice ready, transparent background, 256x256.
```

### 5. `assets/ui/generated/ui_tab_button_frame.png`

- **尺寸**：256 × 128
- **用途**：技能/道具 Tab 按钮边框
- **9-slice 边距**：左 76 / 上 32 / 右 76 / 下 32
- **Prompt**：
```text
Chinese folk horror tab button frame, dark gold border,
xuan black interior, active state has cinnabar red top accent,
9-slice ready, transparent background, 256x128.
```

### 6. `assets/ui/generated/ui_diamond_button.png` ⭐ 重要

- **尺寸**：256 × 256
- **用途**：菱形待机按钮（外接 96 × 96）
- **9-slice 边距**：左 72 / 上 72 / 右 72 / 下 72（菱形中心可拉伸）
- **Prompt**：
```text
Chinese folk horror diamond shaped wait/end-turn button,
dark gold and indigo window lattice pattern,
xuan black center, cinnabar red edge accent,
rotated 45 degrees diamond frame, 9-slice ready,
transparent background, 256x256.
```

### 7. `assets/ui/generated/ui_top_button_frame.png`

- **尺寸**：128 × 128
- **用途**：右上角系统按钮（设置/自动/结束回合）
- **9-slice 边距**：左 34 / 上 34 / 右 34 / 下 34
- **Prompt**：
```text
Chinese folk horror small square icon button frame,
minimal dark gold border, xuan black interior,
transparent background, 9-slice ready, 128x128.
```

---

## 二、技能图标（48 × 48 / 64 × 64 / 128 × 128）

每个图标输出 **三个尺寸** 或一个 128×128 让程序缩放。推荐直接输出 128×128，程序会缩放。

### 8. `assets/ui/generated/skill_icon_slash.png`

- **主体**：桃木剑 / 铜钱剑斩击
- **Prompt**：`Skill icon, Chinese peach wood sword slash, copper coins, ink line art, transparent background, 128x128.`

### 9. `assets/ui/generated/skill_icon_soul.png`

- **主体**：钟馗判官笔 / 勾魂锁
- **Prompt**：`Skill icon, Chinese judge brush and soul-locking chain, ink line art, transparent background, 128x128.`

### 10. `assets/ui/generated/skill_icon_talisman.png`

- **主体**：黄符纸 + 朱砂符文
- **Prompt**：`Skill icon, yellow Taoist talisman paper with cinnabar rune, ink line art, transparent background, 128x128.`

### 11. `assets/ui/generated/skill_icon_bell.png`

- **主体**：铜铃 + 音波
- **Prompt**：`Skill icon, Chinese bronze bell with sound wave rings, ink line art, transparent background, 128x128.`

### 12. `assets/ui/generated/skill_icon_fire.png`

- **主体**：三昧真火 / 符咒火焰
- **Prompt**：`Skill icon, Chinese Taoist flame 三昧真火, burning talisman paper, orange-red fire, ink line art, transparent background, 128x128.`

### 13. `assets/ui/generated/skill_icon_rice.png`

- **主体**：糯米袋散落
- **Prompt**：`Skill icon, glutinous rice sack scattering rice grains, anti-spirit, ink line art, transparent background, 128x128.`

### 14. `assets/ui/generated/skill_icon_water.png`

- **主体**：水泼 / 水缸倾倒
- **Prompt**：`Skill icon, water splash from wooden bucket, blue water droplets, ink line art, transparent background, 128x128.`

### 15. `assets/ui/generated/skill_icon_bind.png`

- **主体**：墨线 / 封印锁链
- **Prompt**：`Skill icon, black ink line binding seal, Taoist restraint, ink line art, transparent background, 128x128.`

---

## 三、行动按钮图标（`assets/ui/generated/actions/`）

### 16. `assets/ui/generated/actions/action_wait.png`

- **主体**：沙漏 / 太极圆盘
- **Prompt**：`Chinese folk horror wait icon, bronze hourglass on dark gold circle, transparent background, 128x128.`

### 17. `assets/ui/generated/actions/action_spell.png`

- **主体**：符咒 / 法术卷轴（中式）
- **Prompt**：`Chinese folk horror spell icon, yellow talisman with cinnabar rune, transparent background, 128x128.`

### 18. `assets/ui/generated/actions/action_item.png`

- **主体**：道具袋 / 百宝囊
- **Prompt**：`Chinese folk horror item bag icon, cloth pouch with talisman tag, transparent background, 128x128.`

---

## 四、Mockup V2 框架（`assets/ui/mockup_v2/`）

这些文件目前被 `_configure_action_icon_button` 使用，也需要替换为中式风格。

### 19. `assets/ui/mockup_v2/action_mode_frame.png`

- **用途**：Tab 按钮背板（法术/道具）
- **Prompt**：`Chinese folk horror action mode tab frame, dark gold border, xuan black interior, transparent background, 256x128.`

### 20. `assets/ui/mockup_v2/card_slot_frame.png`

- **用途**：卡牌槽位边框
- **Prompt**：`Chinese folk horror card slot frame, yellow talisman edge, dark gold line, transparent background, 256x256.`

### 21. `assets/ui/mockup_v2/wait_button_frame.png`

- **用途**：待机按钮背板
- **Prompt**：`Chinese folk horror rectangular wait button frame, dark gold border, xuan black interior, transparent background, 256x256.`

---

## 五、可选但推荐：图集源图

### 22. `assets/ui/generated/ui_frame_atlas_source.png`

- **尺寸**：1254 × 1254（保持原尺寸）
- **用途**：UI 边框大图集，供 `data/ui_atlas.json` 切分
- **Prompt**：
```text
Chinese folk horror UI atlas sheet containing:
status panel frame, bottom hand panel frame, card frame,
party member frame, diamond button, tab button frame.
Dark gold and cinnabar red accents, xuan black interior,
old paper texture, 9-slice ready elements, transparent background, 1254x1254.
```

### 23. `assets/ui/generated/skill_icon_atlas_source.png`

- **尺寸**：1254 × 1254
- **用途**：技能图标大图集
- **Prompt**：
```text
Chinese folk horror skill icon atlas sheet containing:
fire, slash, soul, talisman, rice, water, bind, bell icons.
Ink line art style, transparent background, 1254x1254.
```

---

## 六、验收标准

每个生成文件提交前检查：

- [ ] PNG 格式，透明背景
- [ ] 无西幻元素（蓝宝石、魔法阵、卷草纹、欧洲剑、骷髅装饰）
- [ ] 主色调符合 Art Bible（玄黑 `#1A1A1A`、暗金 `#B8954E`、朱红 `#C23B3B`）
- [ ] 9-slice 边框四边连续、四角完整
- [ ] 覆盖到项目正确路径，同名替换旧文件
- [ ] 在 Godot 中运行后无拉伸变形

---

## 七、生成后还需要我做的代码调整

素材替换后，以下参数可能需要微调：

- `UI_PATCH_MARGINS` 中对应素材的边距
- `data/ui_atlas.json` 中的 `region` 和 `patch_margin`
- `_configure_action_icon_button` 中 backplate/icon/caption 的相对位置

这些可以在运行后根据实际显示效果再调。
