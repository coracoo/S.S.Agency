# 封灵事务所 (S.S.Agency) — 游戏设计文档 (GDD)

## 一、游戏定位

**港式民俗规则模拟器。**

核心体验：玩家利用环境规则（火、水、米、符、声）对抗超自然实体，而非依赖角色数值碾压。每一关都是一个"规则谜题"——理解规则、利用规则、打破规则。

**一句话描述**: 在港式灵异场景中，用风水、符咒、机关和环境互动消灭超自然实体的回合制战术游戏。

**参考作品**: Into the Breach（可预测性）+ 幽灵诡计（环境交互）+ 鬼玩人（恐怖喜剧）

---

## 二、核心循环

```
观察环境+敌方意图 → 规划行动 → 执行（移动/技能/环境互动）→ 观察连锁反应 → 应对后果
```

**环境互动是核心玩法**，不是附庸。推火盆引燃油地、倒水桶灭火流、洒糯米减速僵尸、拉墨线阻挡灵体——这些操作是玩家最主要的"技能"，比角色本身的攻击更重要。

### 玩家回合内可执行操作（按优先级）

1. **环境互动**（1 AP）：推/拉环境物体、拾取道具、开门关门
2. **移动**（1 AP/格）：走到目标位置，地形修正消耗
3. **技能/符咒**（2-3 AP）：角色专属能力，辅助环境操作
4. **攻击**（2 AP）：直接伤害，但效率低于环境连锁

---

## 三、回合结构

```
┌─────────────────────────────────────────────┐
│  1. 玩家回合                                 │
│  - 共享 AP 池（基础 6 AP）                    │
│  - 移动角色 / 技能 / 环境互动                 │
│  - 可随时切换角色                             │
├─────────────────────────────────────────────┤
│  2. 敌方意图预览                              │
│  - 显示每个敌人下一步计划（箭头+图标）          │
│  - 红=攻击，黄=移动，紫=特殊                  │
│  - 玩家通过预览来"读题"                       │
├─────────────────────────────────────────────┤
│  3. 敌方回合                                 │
│  - 按预览执行（除非被打断/恐惧/混乱）           │
│  - AI 由情绪驱动（恐惧/执念/暴走）             │
├─────────────────────────────────────────────┤
│  4. 环境处理                                 │
│  - 火焰蔓延到相邻可燃格（每回合+1格）          │
│  - 水流扩散（每回合向空格流1格）               │
│  - 地形效果更新（燃烧持续时间、水渍蒸发）       │
│  - 灵气密度自然衰减 -1                        │
└─────────────────────────────────────────────┘
```

环境处理回合只负责**自动传播和衰减**，真正的核心是玩家回合内的**环境互动**。

---

## 四、世界观与角色

### 背景设定

"封灵事务所"——一间隐藏在九龙城寨深处的民间机构，专门处理普通人看不见的超自然事件。每一关是一个"委托"——某个地点闹鬼了，去处理它。

### 可操作角色（保留现有角色）

**凛音 / 薄荷 / 焰华 / 钟馗** — 角色人设、外观、美术全部保留，只在世界观上重新定位为封灵事务所成员。

| 角色 | 原定位 | 新定位（叠加环境能力） | 环境互动特长 |
|------|--------|----------------------|-------------|
| **凛音** | 近战坦克 | 前线术士 | 高HP抗恐惧，推拉物体距离+1 |
| **薄荷** | 远程输出 | 侦察射手 | 走路无声（不触发噪音），远程触发机关 |
| **焰华** | 法师 | 驱魔术士 | 火焰亲和（点火不消耗额外AP），净化灵气 |
| **钟馗** | 近战战士 | 封印师 | 吸血续航，可承受灵体接触，布置封印阵 |

### 角色新增属性

- **恐惧值**: 0-100，过高失控1回合（凛音阈值高，薄荷低）
- **灵感知**: 感知隐藏灵体/机关的范围

### 敌人类型（Demo 4种）

| 敌人 | 行为模式 | 恐惧源 | 执念 | 克制手段 |
|------|----------|--------|------|----------|
| **纸人** | 巡逻→发现→追击 | 火、大声 | 保护棺材 | 火=恐惧逃跑，噪音=吸引 |
| **红衣女** | 静止→被注视→瞬移攻击 | 背对她安全 | 被注视时暴走 | 不看她、用环境间接击杀 |
| **水鬼** | 潜伏水中→拖拽 | 远离水域变弱 | 把人拉入水中 | 引离水域、糯米减速 |
| **僵尸** | 直线跳跃→追击 | 糯米、墨线 | 吸阳气 | 糯米减速、墨线阻挡 |

### Boss（Demo 1个）

**棺材主** — 纸人抬着的棺材中苏醒的强大灵体。两阶段：
- 阶段1：被纸人保护，指挥纸人进攻
- 阶段2：棺材破坏后脱离，全图追击，但畏惧封印阵

---

## 五、核心系统

### 5.1 地形系统（第一优先级，所有系统的基础）

#### 多层地图结构

```
┌─────────────────────────────────────────┐
│  地面层 (Ground)                         │
│  基础地形：地板、泥土、水面、油地、草地     │
│  JSON定义，含标签、移动消耗、颜色           │
├─────────────────────────────────────────┤
│  效果层 (Effect)                         │
│  动态叠加：火焰、水渍、糯米、墨线、符纸     │
│  每格可有多个效果共存（火+油，水+糯米）     │
├─────────────────────────────────────────┤
│  物体层 (Object)                         │
│  可互动物体：火盆、水缸、糯米袋、铃铛、门    │
│  可被推/拉/推倒/拾取                      │
├─────────────────────────────────────────┤
│  碰撞层 (Collision)                      │
│  墙壁、障碍物、不可通行区域                 │
├─────────────────────────────────────────┤
│  实体层 (Entity)                         │
│  角色、敌人、Boss                         │
└─────────────────────────────────────────┘
```

#### 地形标签系统（Tag-based）

每种地形/效果用标签定义属性，系统通过标签查询交互规则，不硬编码地形名。

```json
{
    "oil":     {"tags": ["flammable", "noise_amplify"], "move_cost": 1},
    "water":   {"tags": ["fire_extinguish", "conduct", "liquid"], "move_cost": 2},
    "wood":    {"tags": ["flammable", "breakable"], "move_cost": 1},
    "rice":    {"tags": ["anti_spirit", "slowdown_spirit"], "move_cost": 1},
    "seal":    {"tags": ["seal_point", "spirit_reduce"], "move_cost": 1},
    "stone":   {"tags": ["fireproof", "pushable"], "move_cost": 1},
    "curse":   {"tags": ["spirit_zone", "fear_increase"], "move_cost": 1},
    "elevated":{"tags": ["high_ground", "push_off"], "move_cost": 2}
}
```

#### 效果层定义

```json
{
    "fire":    {"tags": ["burning", "light", "noise_source"], "duration": 3, "damage": 4},
    "water":   {"tags": ["wet", "fire_extinguish"], "duration": 5, "spread": true},
    "rice":    {"tags": ["anti_spirit", "slowdown"], "duration": 99},
    "ink_line":{"tags": ["spirit_block"], "duration": 99, "block_spirit": true},
    "talisman":{"tags": ["seal_component", "spirit_reduce"], "duration": 99}
}
```

#### 环境物体定义

```json
{
    "brazier":   {"pushable": true, "tags": ["fire_source", "flammable"], "interact": "push"},
    "water_barrel":{"pushable": true, "push_over": true, "tags": ["water_source"], "interact": "push/push_over"},
    "rice_bag":  {"pushable": true, "push_over": true, "tags": ["rice_source"], "interact": "push/push_over"},
    "bell":      {"pushable": false, "tags": ["noise_source"], "interact": "ring", "noise_volume": 4},
    "door":      {"pushable": false, "tags": ["blocking"], "interact": "open/close", "noise_volume": 2},
    "coffin":    {"pushable": false, "tags": ["boss_container"], "interact": "none"}
}
```

### 5.2 环境互动系统（核心玩法）

**这是游戏最重要的系统。** 玩家通过操作环境物体和利用地形规则来达成目标。

#### 互动操作

| 操作 | AP消耗 | 说明 |
|------|--------|------|
| 推（Push） | 1 AP | 将物体推向角色面对方向1格 |
| 拉（Pull） | 1 AP | 将相邻物体拉到角色位置，角色后退1格 |
| 推倒（Push Over） | 1 AP | 推倒容器，内容物散落到相邻格子 |
| 拾取（Pick Up） | 1 AP | 拾取小型物品（糯米、符纸）到背包 |
| 放置（Place） | 1 AP | 在脚下/相邻格放置背包物品 |
| 互动（Interact） | 1 AP | 敲铃铛、开门关门等特殊互动 |
| 点燃（Ignite） | 1 AP | 焰华免费，其他人需火源 |

#### 交互链示例（核心乐趣）

```
示例1：火盆连锁
推火盆到油地格 → 油地引燃（EVENT_FIRE_IGNITED）
→ 火焰蔓延到相邻纸人 → 纸人进入Fear状态逃跑
→ 纸人撞倒糯米袋 → 糯米散落 → 经过的僵尸减速
→ 纸人跑到墨线处被阻挡 → 玩家趁机击杀

示例2：水+电
推倒水缸 → 水流扩散3格
→ 焰华对水面施放闪电符 → 水面导电 → 范围伤害
→ 水面上的火被浇灭 → 火焰熄灭

示例3：诱导击杀
薄荷射箭打铃铛 → 噪音4扩散
→ 纸人被吸引走向铃铛 → 路过预洒的糯米
→ 纸人减速 → 凛音推纸人入水中 → 水鬼+纸人互相攻击
```

### 5.3 交互规则表

系统通过标签查询自动处理交互，不硬编码：

```
[fire] + [flammable]     → 点燃，EVENT_FIRE_IGNITED
[fire] + [liquid]        → 灭火，EVENT_FIRE_EXTINGUISHED
[fire] + [noise_amplify] → 爆燃（范围+1，噪音+2）
[anti_spirit] + spirit   → 减速，伤害
[spirit_block] + spirit  → 阻挡移动
[seal_component] + [seal_point] + spirit_density≥6 → 封印激活（特殊击杀）
[high_ground] + push     → 推落，坠落伤害
[breakable] + fire       → 破坏，掉落内容物
[wet] + electric         → 导电，范围伤害
```

### 5.4 噪音系统

噪音是战术工具也是风险。

**传播规则**：
- 曼哈顿距离扩散，音量每格 -1
- 穿墙衰减 -2
- 水面放大 +1 格

**关键噪音值**：

| 动作 | 音量 | 动作 | 音量 |
|------|------|------|------|
| 走路 | 1 | 跑步 | 3 |
| 推物体 | 2 | 推倒容器 | 3 |
| 开/关门 | 2 | 敲铃铛 | 4 |
| 爆燃 | 5 | 普通攻击 | 2 |
| 薄荷移动 | 0 | 技能施放 | 2 |

### 5.5 灵气系统

全局状态（0-10），影响超自然规则强度：

| 灵气密度 | 效果 |
|----------|------|
| 0-2 | 灵体虚弱，纸人移速-1 |
| 3-5 | 灵体正常活动 |
| 6-7 | 灵体强化，封印阵可激活 |
| 8-9 | 灵体暴走，环境异变 |
| 10 | 百鬼夜行 |

**灵气变化**：击杀灵体 -2 / 角色死亡 +3 / 符纸净化 -1 / 棺材开启 +5 / 每回合自然 -1

### 5.6 封印击杀

封印不是独立系统，是**特殊击杀手段**。和用火把纸人烧死、把水鬼引离水域打死一样，封印是对 Boss 的高效击杀方式。

**封印击杀条件**：
1. 阵眼格子放置符纸（3个以上）
2. 灵气密度 ≥ 6
3. 目标在阵内
4. 角色激活阵眼

满足条件 = 击杀 Boss，和用伤害打到 0 HP 本质相同。

---

## 六、AI 系统

### 设计哲学

**AI 是谜题的一部分，必须可预测。** 玩家读意图、规划反制、利用 AI 行为达成目的。

### AI 参数

```json
{
    "fear_fire": 0.9,
    "fear_noise": 0.4,
    "aggression": 0.3,
    "intelligence": 0.5,
    "obsession": "protect_coffin",
    "hearing_range": 5,
    "sight_range": 4
}
```

### AI 状态机

```
Idle → Patrol → Search（被噪音吸引）→ Chase → Attack
  ↓                       ↑
  Fear（看到火/巨响）     │
  Rage（执念被威胁）      │
  Confused（被符纸影响）  │
```

- **Fear**: 远离恐惧源。纸人看到火 → 远离火。玩家利用这点驱赶纸人走位。
- **Rage**: 直奔执念目标，无视一切。纸人棺材被碰 → 冲过来。
- **Confused**: 随机移动1-2回合。

### 意图预览

敌人回合前显示下一步计划：
- 红箭头 = 攻击
- 黄箭头 = 移动
- 橙问号 = 搜索（被噪音吸引）
- 紫箭头 = 恐惧逃跑

---

## 七、卡牌/技能系统

**保留现有卡牌系统框架**，但降低其重要性——环境互动是主要手段，卡牌技能是辅助。

### 调整方向

| 现有 | 调整 |
|------|------|
| 卡牌决定战斗 | 环境互动决定战斗，卡牌辅助 |
| 抽牌随机性 | 可选：改为固定技能栏，或保留轻度随机 |
| 纯伤害卡 | 部分改为环境互动能力 |

### 环境互动技能（叠加在现有卡牌上）

每个角色增加环境互动被动/主动能力：

- **凛音**: 推拉距离+1，可推动重物
- **薄荷**: 移动无噪音，远程触发机关（射箭打铃铛）
- **焰华**: 点火免费，火焰伤害+50%，可净化灵气
- **钟馗**: 布置封印阵（放置符纸到阵眼），承受灵体接触不死

### 现有卡牌保留，新增环境互动类卡牌

```json
{
    "id": "push_strike",
    "name": "推击",
    "description": "攻击并推动敌人1格",
    "cost": 1,
    "targetType": "adjacent_enemy",
    "effects": [
        {"type": "deal_damage", "value": 5, "damageType": "physical"},
        {"type": "push", "distance": 1}
    ]
}
```

---

## 八、Demo 关卡："纸人抬棺"

### 场景

废弃祠堂，10x8 格。中央棺材由四个纸人抬着。

### 关卡布局

```
门    空  空  阵眼 空  空  阵眼 空  门
空    空  油  空  空  空  空  水  空
空    空  空  空  棺  材  空  空  空
阵眼  空  空  纸人 纸人 纸人 纸人 空  阵眼
空    糯  空  空  空  空  空  火  空
空    米  空  空  空  空  空  盆  空
空    空  空  阵眼 空  空  阵眼 空  空
窗    空  空  空  空  空  空  空  窗
```

### 胜利/失败

- **胜利**: 击杀棺材主（通过封印或伤害）
- **失败**: 全灭 / 棺材主逃脱

### 三阶段流程

**阶段1：侦查（回合1-3）** — 纸人巡逻不攻击，玩家熟悉地形、收集糯米、布置墨线
**阶段2：惊醒（回合4-6）** — 棺材震动，纸人开始追击，灵气密度上升
**阶段3：决战（回合7+）** — Boss 苏醒，利用环境连锁+封印击杀

### 教学设计

关卡本身教会核心机制：
1. 移动+AP → 开局走位
2. 推物体 → 推火盆
3. 火焰蔓延 → 点燃油地
4. 噪音吸引 → 敲铃铛引纸人
5. 糯米/墨线 → 减速+阻挡
6. 封印击杀 → 最终Boss

---

## 九、UI 设计

```
┌──────────────────────────────────────────────────┐
│  回合: 5   玩家阶段   AP: 4/6   灵气: ●●●○○○○○○○    │
├──────────────────────────────────────────────────┤
│                                                  │
│              等距地图                              │
│    （含地形颜色、效果层、敌方意图箭头、噪音波纹）    │
│                                                  │
├──────────────────────────────────────────────────┤
│ [凛音] [薄荷] [焰华] [钟馗]                        │
│ HP: ████████░░  恐惧: ██░░░░░░                    │
│ 技能1 技能2 技能3 | 推 拉 推倒 拾取 放置 互动        │
│ 背包: 符纸x2 糯米x1                               │
└──────────────────────────────────────────────────┘
```

关键 UI：
- **地形高亮**: 悬停显示标签（可燃/可推/水深）
- **意图箭头**: 敌人下一行动可视化
- **噪音波纹**: 声音扩散动画
- **灵气条**: 顶部实时显示
- **环境互动栏**: 推/拉/推倒/拾取/放置/互动 按钮

---

## 十、技术架构

### 系统分层（Godot GDScript）

```
Core Layer（纯逻辑，scripts/core/）
├── event_bus.gd           # 全局事件总线（extends Node，autoload）
├── turn_manager.gd        # 回合阶段管理
├── game_state.gd          # 全局状态容器
├── game_map.gd            # 多层地图数据 + 标签查询
├── terrain_system.gd      # 地形交互规则引擎 ★新增
├── interaction_system.gd  # 推/拉/推倒/拾取/放置 ★新增
├── noise_system.gd        # 噪音传播计算 ★新增
├── ai_controller.gd       # AI 决策 + 状态机 + 意图生成
├── spirit_system.gd       # 灵气密度 + 封印规则 ★新增
├── card_resolver.gd       # 卡牌效果 + 环境互动效果
└── card_effect_parser.gd  # 效果解析

Data Layer（JSON 配置，data/）
├── maps.json       # 多层地图 + 初始物体 + 初始效果
├── terrains.json   # 地形标签定义 ★新增
├── effects.json    # 地形效果定义 ★新增
├── objects.json    # 环境物体定义 ★新增
├── rules.json      # 交互规则表 ★新增
├── cards.json      # 卡牌定义（含环境互动效果）
├── units.json      # 角色定义（含环境被动）
└── enemies.json    # 敌人定义（含 AI 参数）

Rendering Layer（scripts/scenes/）
├── battle_scene.gd # 主场景：地图渲染 + 输入 + UI
└── main_scene.gd   # 场景管理
```

### 完整事件规范

| 事件名 | 参数 | 触发时机 | 监听方 |
|--------|------|----------|--------|
| `interaction:push` | `{entity_id, object_id, from, to}` | 推动物体 | TerrainSystem, NoiseSystem |
| `interaction:push_over` | `{entity_id, object_id, pos}` | 推倒物体 | TerrainSystem, NoiseSystem |
| `interaction:ignite` | `{entity_id, pos}` | 点燃操作 | TerrainSystem |
| `interaction:ring` | `{entity_id, object_id, pos}` | 敲铃铛 | NoiseSystem |
| `fire:ignited` | `{pos, source}` | 火焰被点燃 | TerrainSystem, AISystem |
| `fire:spread` | `{pos, from_pos}` | 火焰蔓延 | TerrainSystem, AISystem |
| `fire:extinguished` | `{pos, reason}` | 火焰熄灭 | TerrainSystem |
| `water:spread` | `{pos, from_pos}` | 水流扩散 | TerrainSystem |
| `object:pushed` | `{object_id, from, to, pusher_id}` | 物体被推动 | NoiseSystem, AISystem |
| `object:pushed_over` | `{object_id, pos, contents}` | 物体被推倒 | TerrainSystem, NoiseSystem |
| `noise:created` | `{pos, volume, source, source_type}` | 产生噪音 | AISystem, BattleScene |
| `terrain:tag_added` | `{pos, tag}` | 地形标签新增 | TerrainSystem |
| `terrain:tag_removed` | `{pos, tag}` | 地形标签移除 | TerrainSystem |
| `entity:pushed` | `{entity_id, from, to, pusher_id}` | 单位被推动 | GameState, AISystem |
| `entity:damaged` | `{entity_id, amount, type, source}` | 单位受伤 | BattleScene |
| `entity:killed` | `{entity_id, method}` | 单位死亡 (damage/seal/fire/fall) | SpiritSystem, GameState |
| `spirit:density_changed` | `{old, new}` | 灵气变化 | AISystem, BattleScene |
| `ai:state_changed` | `{entity_id, old_state, new_state, reason}` | AI 状态变化 | BattleScene |
| `seal:activated` | `{positions, target_id}` | 封印激活 | SpiritSystem |
| `turn:phase_changed` | `{phase}` | 回合阶段切换 | 全局 |
| `boss:awakened` | `{}` | Boss 苏醒 | 全局 |

---

## 十一、数据格式规范

### 11.1 多层地图数据 (`maps.json`)

```json
{
    "id": "abandoned_shrine",
    "name": "废弃祠堂",
    "cols": 10,
    "rows": 8,
    "layers": {
        "ground": [
            ["stone","stone","seal","stone","stone","stone","seal","stone","stone","stone"],
            ["stone","stone","oil","stone","stone","stone","stone","water","stone","stone"]
        ],
        "effects": [
            [[],[],[],[],[],[],[],[],[],[]],
            [[],[],[],[],[],[],[],[],[],[]]
        ],
        "objects": [
            [null,null,null,null,null,null,null,null,null,null],
            [null,null,null,null,null,null,null,null,null,null]
        ],
        "collision": [
            [false,false,false,false,true,false,false,false,false,false],
            [false,false,false,false,true,false,false,false,false,false]
        ]
    },
    "initial_spirit_density": 2,
    "spawn_points": {
        "players": [
            {"template": "rinne", "pos": [1, 7]},
            {"template": "mint", "pos": [2, 7]}
        ],
        "enemies": [
            {"template": "paper_person", "pos": [3, 3], "patrol_path": [[3,3],[6,3],[6,5],[3,5]]}
        ]
    }
}
```

### 11.2 交互规则表 (`rules.json`)

```json
{
    "rules": [
        {
            "id": "fire_ignites_flammable",
            "trigger": {"source_tags": ["burning"], "target_tags": ["flammable"]},
            "results": [
                {"spawn_effect": {"type": "fire", "duration": 3}, "event": "fire:ignited"}
            ]
        },
        {
            "id": "fire_extinguished_by_water",
            "trigger": {"source_tags": ["wet"], "target_tags": ["burning"]},
            "results": [
                {"remove_effect": "fire", "event": "fire:extinguished"}
            ]
        },
        {
            "id": "fire_oil_explosion",
            "trigger": {"source_tags": ["burning"], "target_tags": ["noise_amplify"]},
            "results": [
                {"spawn_effect": {"type": "fire", "duration": 3, "intensity": 2}, "noise": 5, "event": "fire:ignited"}
            ]
        },
        {
            "id": "rice_slows_spirit",
            "trigger": {"source_tags": ["anti_spirit"], "target_entity_tags": ["spirit"]},
            "results": [
                {"apply_status": "slow", "duration": 2}
            ]
        },
        {
            "id": "ink_line_blocks_spirit",
            "trigger": {"source_tags": ["spirit_block"], "target_entity_tags": ["spirit"]},
            "results": [
                {"block_movement": true}
            ]
        },
        {
            "id": "seal_activation",
            "trigger": {"source_tags": ["seal_component"], "target_tags": ["seal_point"]},
            "conditions": {"min_spirit_density": 6, "min_seal_points": 3, "target_in_seal": true},
            "results": [
                {"kill_method": "seal", "event": "seal:activated"}
            ]
        },
        {
            "id": "fire_scares_spirit",
            "trigger": {"source_tags": ["burning"], "target_entity_tags": ["spirit"]},
            "results": [
                {"ai_state": "fear", "event": "ai:state_changed"}
            ]
        }
    ]
}
```

---

## 十二、算法细节

### 12.1 噪音传播算法

```
func propagate_noise(origin: Vector2i, volume: int) -> Dictionary:
    var result = {}  # pos -> volume
    var queue = [{pos = origin, vol = volume}]
    var visited = {}

    while not queue.is_empty():
        var item = queue.pop_front()
        var pos = item.pos
        var vol = item.vol
        var key = "%d,%d" % [pos.x, pos.y]
        if visited.has(key) or vol <= 0:
            continue
        visited[key] = true
        result[pos] = maxi(result.get(pos, 0), vol)

        for neighbor in get_neighbors(pos):
            var decay = 1
            if has_wall_between(pos, neighbor):
                decay += 2
            if has_tag(neighbor, "liquid"):
                decay -= 1
            queue.append({pos = neighbor, vol = vol - decay})
    return result
```

**阈值**：音量 ≥ 3 吸引 Search AI，≥ 5 触发 Fear（对 fear_noise 高的 AI）

### 12.2 灵气变化公式

```
每回合自然衰减: density = maxf(0, density - 1)
击杀灵体:       density = maxf(0, density - 2)
角色死亡:       density = minf(10, density + 3)
符纸净化:       density = maxf(0, density - 1)
焰华净化技能:   density = maxf(0, density - 2)
棺材开启:       density = minf(10, density + 5)

密度效果:
0-2:  灵体虚弱 (move_range -1)
3-5:  正常
6-7:  灵体强化 (damage +30%), 封印可激活
8-9:  灵体暴走 (每回合额外行动)
10:   百鬼夜行 (所有灵体进入 Rage)
```

### 12.3 封印击杀判定

```
条件（需同时满足）:
1. 阵眼格子数量 >= 3
2. 每个阵眼格有 talisman 效果
3. spirit_density >= 6
4. 目标在阵眼包围区域内（或相邻）
5. 角色执行"激活阵眼"互动（1 AP）

满足 → 目标立即死亡, method = "seal"
```

### 12.4 AI 状态转换条件

```
Idle → Patrol:      回合开始，自动
Patrol → Search:    听到噪音 (noise_at_pos >= hearing_range)
Patrol → Chase:     视野内发现玩家 (distance <= sight_range)
Search → Chase:     搜索位置发现玩家
Search → Idle:      搜索 2 回合未发现目标
Chase → Attack:     与玩家相邻
Chase → Fear:       附近火焰强度 > fear_fire * 10
Attack → Fear:      受伤且附近火焰 > threshold
Attack → Rage:      执念目标被威胁
Fear → Confused:    被符纸影响
Fear → Patrol:      远离恐惧源 3 格以上，1 回合未再遇
Rage → Chase:       执念目标恢复安全
Confused → Patrol:  2 回合后恢复
```

---

## 十三、代码规范

```
规范1: 禁止硬编码地形名
  错: if terrain == "oil": ignite()
  对: if tile.has_tag("flammable"): ignite()

规范2: 禁止系统直接互调
  错: ai_controller.modify_terrain(pos, tag)
  对: event_bus.emit("terrain:tag_added", {pos, tag})

规范3: 所有规则配置化
  错: if fire + oil: spread_range = 2
  对: rules.json 中配置，TerrainSystem 解析执行

规范4: AI 参数必须外置
  错: if enemy.type == "paper_person": fear_fire = 0.9
  对: enemies.json 中定义 ai_profile，AIController 读取

规范5: 效果层与渲染层分离
  效果层数据在 Core Layer 维护
  battle_scene.gd 只读取并渲染，不修改逻辑
```

---

## 十四、美术规范

### 角色美术（保留现有）

凛音/薄荷/焰华/钟馗的人设、精灵图、动画全部保留。只需要：

- 补充敌人美术：纸人、红衣女、水鬼、僵尸
- 环境物体美术：火盆、水缸、糯米袋、铃铛、棺材

### 地形美术

| 元素 | 颜色 | 说明 |
|------|------|------|
| 油地 | 暗黄 #8B7355 | 微光泽感 |
| 水面 | 青蓝 #4488AA | 波纹动画 |
| 火焰 | 橙红 #FF6622 | 闪烁动画 |
| 糯米 | 米白 #F5F5DC | 散落颗粒感 |
| 墨线 | 纯黑 #000000 | 连线+发光 |
| 符纸 | 金黄 #FFD700 | 浮动动画 |
| 灵气 | 紫黑 #6B2FA0 | 雾气效果 |

### 精灵规格

- 角色: 256×256，4×4 格，64×64/帧，等距四方向
- 环境物体: 64×64 单帧，等距视角
- 效果动画: 64×64 多帧（火焰4帧、水波4帧）

---

## 十五、开发路线

> 详细进度追踪见 [进度.md](进度.md)

### Phase 1: 地形系统重构 ✅ ~85%（当前最高优先级 → 基本完成）

**目标**: 验证"规则交互"手感

- [x] 等距地图渲染（已有）
- [x] 回合制框架（已有）
- [x] 基础移动和选择（已有）
- [x] 新增 `data/terrains.json` — 地形标签定义（15种地形）
- [x] 新增 `data/effects.json` — 效果层定义（7种效果）
- [x] 新增 `data/objects.json` — 环境物体定义（7种物体）
- [x] 新增 `data/rules.json` — 交互规则表（6条规则）
- [x] 重构 `game_map.gd` — 多层地图数据结构（Ground/Effect/Object/Collision）
- [x] 新增 `terrain_system.gd` — 标签查询 + 交互规则引擎
- [x] 新增 `interaction_system.gd` — 推/推倒/互动逻辑
- [x] 火焰点燃 + 蔓延规则（spread_per_turn 机制）
- [x] 水流扩散规则（water_spread 有蔓延参数）
- [x] 重构 `maps.json` — 多层地形 + 物体布局 v2（14×10 纸人抬棺）
- [ ] 新增拉（pull）/拾取（pick_up）/放置（place）互动操作

### Phase 2: 回合系统扩展 🔧 ~55%

- [x] 扩展 `turn_manager.gd` — AP 系统、首回合抽牌、状态效果 tick
- [x] 环境处理回合（火焰蔓延/水流/效果衰减）— battle_scene 中实现
- [x] 灵气密度自然衰减 -1 — battle_scene 环境回合中处理
- [ ] 敌方意图预览阶段（箭头+图标渲染）
- [ ] 扩展事件总线（当前约10个，目标20+）

### Phase 3: AI 系统重构 🔧 ~40%

- [x] AI 参数配置化（enemies.json 接入 aiProfile）
- [x] 噪音响应基础（bell 事件触发 search 状态）
- [x] fear/search/chase/attack 状态基本实现
- [ ] 重构 `ai_controller.gd` — 完整状态机（缺 rage/confused）
- [ ] 意图预览渲染（箭头/图标）
- [ ] 纸人/红衣女/水鬼/僵尸 行为差异化（红衣女瞬移未实现）
- [ ] 巡逻路径执行（enemies.json 有定义但未接入 AI）

### Phase 4: 噪音 + 灵气 + 封印 ⏳ ~15%

- [x] `game_state.gd` 基础 spirit_density 字段和 modify_spirit_density()
- [x] `game_state.gd` 基础 noise_events 列表
- [ ] 新增 `noise_system.gd` — 噪音传播计算（BFS）
- [ ] 噪音可视化（波纹 UI）
- [ ] 新增 `spirit_system.gd` — 灵气密度管理 + 密度效果
- [ ] 封印击杀判定（阵眼+talisman+density≥6+激活）
- [ ] `unit.gd` 扩展：恐惧值（0-100）、背包、环境互动能力
- [ ] 角色环境被动：凛音推+1、薄荷无声、焰华免费点火、钟馗封印

### Phase 5: 纸人抬棺 Demo ⏳ ~30%

- [x] 14×10 纸人抬棺地图（扩展为 14×10，含棺材+物体布局）
- [x] 5种敌人定义 + Boss（coffin_lord）配置
- [x] 基础胜利/失败判定（全灭检查）
- [ ] 棺材 + 纸人巡逻路径执行
- [ ] Boss 两阶段逻辑（阶段1指挥纸人/阶段2追击）
- [ ] 教学引导（分阶段解锁机制）
- [ ] 完善胜利/失败条件（棺材主逃脱）
- [ ] 敌人美术 + 环境物体美术
- [ ] 音效

### Phase 6: 验证传播性 ⏳ 0%

- [ ] 连锁高光时刻（录屏测试）
- [ ] AI 有趣行为记录
- [ ] 玩家测试反馈

---

## 十六、与现有代码的映射

> ✅=已完成 🔧=部分完成 ⏳=未开始

| 文件 | 状态 | GDD 要求 | 实际状态 |
|------|------|----------|----------|
| `game_map.gd` | ✅ | 多层地图+标签系统 | Ground/Effect/Object/Collision + 标签查询 + remove_tag |
| `terrain_system.gd` | ✅ | 标签查询+交互规则引擎 | 规则匹配+蔓延+damage_unit+add_effect_neighbors |
| `interaction_system.gd` | 🔧 | 推/拉/推倒/拾取/放置 | push/push_over/interact 已完成，缺 pull/pick_up/place |
| `event_bus.gd` | ✅ | 全局事件总线 | Autoload，emit/on/off |
| `battle_scene.gd` | 🔧 | 渲染+回合+UI | 多层渲染+效果动画+物体+环境回合，缺意图预览 |
| `turn_manager.gd` | 🔧 | 四阶段回合 | AP+抽牌+状态tick，缺意图预览阶段 |
| `card_resolver.gd` | ✅ | 环境互动效果 | push/pull/retreat/add_terrain_effect/lethal检查 |
| `ai_controller.gd` | 🔧 | 情绪驱动AI | fear/search/chase基础，缺rage/confused/巡逻 |
| `game_state.gd` | 🔧 | 全局状态 | spirit_density+noise+AP+spawn，缺灵气效果应用 |
| `unit.gd` | 🔧 | Entity扩展 | ai_profile+ai_state+facing，缺恐惧值/背包/环境被动 |
| `maps.json` | ✅ | v2多层格式 | 14×10 纸人抬棺 |
| `terrains.json` | ✅ | 地形标签 | 15种地形含标签 |
| `effects.json` | ✅ | 效果定义 | 7种效果含spread参数 |
| `objects.json` | ✅ | 物体定义 | 7种物体含交互定义 |
| `rules.json` | ✅ | 交互规则 | 6条规则 |
| `enemies.json` | ✅ | 敌人定义 | 5种敌人+Boss含aiProfile |
| `balance.json` | ✅ | 平衡参数 | AP=6/handSize=5/drawPerTurn=2 |
| `noise_system.gd` | ⏳ | 噪音传播计算 | 文件不存在 |
| `spirit_system.gd` | ⏳ | 灵气管理+封印 | 文件不存在 |
