# AGENTS.md — 封灵事务所（Godnot Tactics）

> 本文档供 AI 编码助手阅读。由代码扫描重新生成,以**实际代码接线状态**为准(非照搬进度文档)。
> 项目所有技术文档、代码注释、数据文件均以中文为主,请使用中文沟通与修改。

## 一、项目概述

**《封灵事务所》** 是一款基于 **Godot 4.6 + GDScript** 的港式民俗题材回合制战术 RPG。核心体验是"规则模拟器":玩家利用环境(火、水、糯米、符纸、铃铛噪音等)与敌人行为规则进行连锁反应,而非单纯比拼数值。

- **引擎版本**: Godot 4.6(`project.godot` 中 `config/features=PackedStringArray("4.6")`,渲染器 `gl_compatibility`)
- **项目名**: `Godnot Tactics`(见 `project.godot` `config/name`),描述"卡牌战棋 RPG"
- **主场景**: `scenes/main.tscn` → `scripts/scenes/main_scene.gd`(标题屏,2026-07 重写为蒸汽朋克+国风道教风格,点击进入战斗)
- **战斗场景**: `scenes/battle.tscn` → `scripts/scenes/battle_scene.gd`(**5604 行**,渲染/UI/输入/动画/回合编排全部集中,典型上帝类)
- **分辨率**: 1536×1024,`canvas_items` 拉伸 + `expand` 纵横比
- **第三方插件**: `addons/AsepriteWizard`(精灵表导入)、`addons/shaker`(震屏)

## 二、如何运行

本地 Godot 4.6.3 已安装在 `J:\godot\Godot_v4.6.3-stable_win64.exe`。两种方式:

```bash
# 命令行运行(注意 --path 指向项目根)
"J:\godot\Godot_v4.6.3-stable_win64.exe" --path "J:\godot\S.S.Agency"

# 或打开编辑器导入 project.godot 后 F5 运行
"J:\godot\Godot_v4.6.3-stable_win64.exe" -e --path "J:\godot\S.S.Agency"
```

辅助工具(Python 3 + Pillow,用于切分/生成/后处理 AI 素材):

```bash
cd /d "J:\godot\S.S.Agency"
python tools\build_hires_battle_assets.py    # 切分高清精灵表与世界物体贴图
python tools\slice_ui_atlas.py               # 从 UI 边框大图切出 7 个边框
python tools\slice_battle_action_ui_v2.py    # 切分战斗动作 UI v2
python tools\export_codex_prompts.py         # 导出 Codex 生成任务为 csv/txt/json
python tools\gen_steampunk_assets.py 0 30    # 按 manifest 批量生成蒸汽朋克素材(断点续跑)
python tools\postprocess_steampunk.py        # 素材后处理:去水印/alpha 裁剪/按类别缩放
# 无头截图(第三参数可选场景路径):
"J:\godot\Godot_v4.6.3-stable_win64.exe" --path "J:\godot\S.S.Agency" --script res://tools/capture_screenshot.gd -- tmp.png 3.0 res://scenes/battle.tscn
# 新增 PNG 若用 load() 加载需先导入:
"J:\godot\Godot_v4.6.3-stable_win64.exe" --path "J:\godot\S.S.Agency" --import
```

依赖: `pip install Pillow`

导出 Windows 试玩包(模板已装于 `%APPDATA%\Godot\export_templates\4.6.3.stable\`):

```bash
mkdir -p "build/S.S.Agency_试玩版_v0.7"   # 导出目录必须预先存在
"J:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "J:\godot\S.S.Agency" --export-release "Windows Desktop" "build\S.S.Agency_试玩版_v0.7\S.S.Agency.exe"
```

⚠️ **v1/v2 并存警告(2026-07-23 发现)**:当前 `project.godot` 指向 **v2 重构版**(config/name "封魂·蒸汽道术",main_scene `scenes/v2/title.tscn`,v2 autoloads NarrativeState/GameBridge/SceneRouter/DebugLog);本文档描述的 v1(封灵事务所,`scenes/main.tscn`+`battle_scene.gd`)仍完整存在但**不是默认启动场景**。导出 v1 试玩包需临时把 `run/main_scene` 改为 `res://scenes/main.tscn`、`config/name` 改为 封灵事务所,导出后恢复(见 docs/进度.md Phase 6)。另注意:导出包里 `DirAccess` 列目录只返回 `.import` 重映射条目,目录扫描须 `trim_suffix(".import")`(battle_scene 精灵表扫描已处理)。

## 三、技术栈与运行时架构

### 3.1 目录结构

```
scenes/           Godot 场景文件(.tscn)
scripts/
  core/           纯逻辑层(RefCounted 类,编辑器外可实例化测试)
  scenes/         场景脚本(Node2D 派生,负责渲染与输入)
data/             全部数据配置(13 个 JSON)
assets/           图片、精灵表、瓦片、UI 素材;`assets/ui/steampunk/`(18 张 HUD/标题贴图)与 `assets/tiles/steampunk/`(13 张物体+效果)为蒸汽朋克 AI 素材;`assets/audio/sfx/`(10 个 AI 生成音效 mp3)
addons/           第三方插件(AsepriteWizard / shaker)— 不要改
tools/            7 个 Python 素材脚本 + `capture_screenshot.gd` 无头截图 + `gen_steampunk_manifest.json` 生成清单
docs/             GDD、实施方案、进度、美术规范(6 个 md)
```

### 3.2 Autoload 单例

`project.godot` 仅注册一个 autoload:

- **`EventBus`**(`scripts/core/event_bus.gd`)→ 全局节点 `/root/EventBus`

⚠️ **重要架构事实**:`EventBus` **不是**用 Godot `signal` 实现的,而是一个**手写字符串键事件总线**。API 为 `EventBus.on(event_name, callable)` / `EventBus.emit(event_name, data_dict)` / `EventBus.off(...)` / `EventBus.clear()`。所有跨系统通信走字符串事件名 + `Dictionary` 数据。

**当前实际使用的事件名**(emit 出去且/或被 on 订阅):

| 事件名 | 发出方 | 主要订阅方 | data 关键字段 |
|---|---|---|---|
| `effect:added` | interaction/terrain/card_resolver | terrain_system、battle_scene(视觉) | `{map, pos, effect?}` |
| `object:pushed` | interaction_system | noise_system | `{map, object_id, from, to, pusher_id}` |
| `object:pushed_over` | interaction_system | terrain_system、noise_system、battle_scene | `{map, object_id, pos, unit_id}` |
| `object:bell_rung` | interaction_system | noise_system | `{map, pos, volume, unit_id}` |
| `coffin:opened` | interaction_system | spirit_system | `{map, pos, unit_id}` |
| `noise:created` | card_resolver 等 | noise_system | `{pos, volume, source_id, source_type, duration}` |
| `noise:propagated` | noise_system | battle_scene(噪音可视化) | `{origin, pos, volume, noise_map, ...}` |
| `unit:terrain_damage` | terrain_system | battle_scene(飘字) | `{unit_id, damage, pos}` |
| `object:pulled` | interaction_system | (预留:noise 等可订阅) | `{map, object_id, from, to, unit_from, unit_to, puller_id}` |
| `seal:activated` | spirit_system | battle_scene(封印特效) | `{map, target_id, target_pos, points, method:"seal"}` |
| `turn:phase_changed` | turn_manager.set_phase | (预留:UI/音效可订阅) | `{from, to, turn}` 阶段:player/intent/enemy/environment/spirit |
| `ai:state_changed` | ai_controller(`_enter_rage`/confused 恢复等) | battle_scene(视觉)、(预留:音效) | `{unit_id, from, to, pos, target_pos?}` |
| `boss:phase_changed` | ai_controller(Boss HP≤phase2HpFrac) | battle_scene(觉醒飘字+暗红闪) | `{unit_id, phase, pos, hp_frac}` |
| `boss:escaped` | level_director.report_boss_escaped | battle_scene(逃脱失败画面) | `{unit_id, pos, reason_text}` |
| `unit:panicked` | unit.modify_fear(fear≥阈值) | battle_scene("失控!"飘字+头像染紫) | `{unit_id, pos, fear}` |
| `unit:fear_changed` | unit.modify_fear/apply_turn_end_fear | battle_scene(恐惧条刷新) | `{unit_id, fear, delta, pos, recovered?}` |
| `unit:undying_survived` | unit.take_damage(钟馗镇邪体魄) | battle_scene("镇邪体魄!"飘字) | `{unit_id, pos}` |

**预留/未接线事件**(有定义但无发出方或无订阅方,改代码时注意):
`object:door_opened`、`object:door_closed`、`inventory:item_picked_up`、`inventory:item_placed`、`terrain:apply_status`、`terrain:ai_state`、`effect:barrel_explode`、`effect:ignite_oil`

> GameState 仍保留若干原生 Godot `signal`(turn_start/unit_moved/unit_damaged/battle_won 等)用于 UI 刷新,这是另一套通道,与 EventBus 并存。

## 四、核心代码清单(`scripts/core/` + `scripts/scenes/`)

### 4.1 纯逻辑层 `scripts/core/`(均为 `class_name X` + `RefCounted`)

| 文件 | 行数 | 职责 |
|---|---|---|
| `game_state.gd` | 211 | 战斗中央数据模型:map、单位、牌组/手牌/物品、AP、灵气密度、噪音事件、胜负判定(含 `lose_reason` 特殊失败)、`move_noise_volume`(薄荷无声步)、`level_flow`/`level_stage`(关卡三阶段)。原生 signal:`turn_start`/`turn_end`/`unit_*`/`battle_won/lost` |
| `game_map.gd` | 240 | 多层 2D 地图(ground/effects/objects/collision)+ occupants 字典;支持 v1(老 terrain)+ v2(layers)格式;标签系统 `{tag:true}` |
| `terrain_system.gd` | 227 | 地形规则引擎。监听 `effect:added`/`object:pushed_over`,按 `rules.json` 触发连锁(点燃/湿灭/爆炸/蔓延/伤害/状态/AI 状态)。带重入保护 |
| `interaction_system.gd` | 247 | 玩家与物体交互:push(支持凛音重推 2 格+heavy 重物)/pull/push_over/pickup/place_from_inventory/interact(ring/open/close/ignite,焰华 ignite 免 AP)。除免费 ignite 外每次扣 1 AP,广播事件 |
| `card_resolver.gd` | 522 | 卡牌打出总调度。计算合法目标(`get_valid_targets`,支持 self/adjacent_enemy/enemy_in_range/direction/area_3x3/tile_in_range),`play_card` 应用全部效果并广播 `effect:added`/`noise:created`;焰华火系卡(含 fire/burn 效果)伤害 ×1.5(`_fire_damage_mult`,adjacent_all/area_3x3/单目标三分支) |
| `ai_controller.gd` | 770 | 敌方 AI(2026-07 大扩展)。按 aiProfile 生成回合计划:状态机 patrol/confused/rage/fear/search/chase/attack + Boss 两阶段与逃脱 + 关卡阶段联动(侦查期 minion 强制巡逻) + 听觉阈值(GDD §12.1:音量 ≥3→search、≥5 且 fear_noise≥0.5→fear) + Utility 选点 + Pathfinding 寻路,输出 intent 与扁平 action 列表(move/attack/teleport/drag/leap,含 damage_mult)。差异化参数全部走 enemies.json aiProfile 与 maps.json levelFlow,**函数顶格无缩进** |
| `spirit_system.gd` | 304 | 灵气密度系统(0–10,5 档 tier)+ 封印判定(check_seal_activation/activate_seal)。原生 signal `density_changed`/`tier_changed`。监听 `effect:added`/`coffin:opened`;百鬼夜行(density 10)由 battle_scene 接 tier_changed 调 `ai.set_all_spirits_rage()`。已接线(见 §4.2 注) |
| `noise_system.gd` | 145 | 噪音传播引擎。监听 bell_rung/pushed/noise:created 等,BFS 蔓延:每格 -1、blocking 格额外 -2、liquid 格(水面/油地)-0(放大 +1,GDD §5.4),广播 `noise:propagated`。已接线(见 §4.2 注) |
| `card_effect_parser.gd` | 61 | 解析卡牌 effects 数组为统一 result 字典(deal_damage/heal/move/buff/draw/gain_energy/apply_status/lifesteal/pull/retreat/add_terrain_effect/create_noise/push_unit)。处理属性缩放与地形闪避 |
| `status_effect_manager.gd` | 68 | 状态效果库(从 `statuses.json` 加载)+ apply/tick。支持 stacking、turn_start/turn_end tickTiming |
| `pathfinding.gd` | 75 | 网格寻路:`get_reachable_tiles`(BFS,考虑 move_cost 与占位)、`find_path`(A*) |
| `unit.gd` | 207 | 单位数据与战斗行为(hp/属性/护盾/朝向/AI 状态/状态数组)+ AI 扩展字段(rage/confused/patrol/boss_phase/tags)+ 恐惧值(fear/fear_threshold/panicked/modify_fear/apply_turn_end_fear)+ 特性查询 has_trait + 钟馗镇邪体魄不死钩子。伤害结算含防御/魔抗/方向修正。⚠️ **class_name 静态依赖链上不得直接写 `EventBus` 标识符**(编译期 autoload 未注册),用 `_bus_emit()` 动态获取,且 --script 模式下 `/root/*` 绝对路径失效,必须相对路径 `root.get_node_or_null("EventBus")` |
| `unit_factory.gd` | 30 | 从 `units.json`+`enemies.json` 创建 Unit,查询初始牌组/物品 |
| `inventory.gd` | 61 | 物品栏(固定 4 槽),支持物体类与卡牌类物品,带使用次数 |
| `deck.gd` | 41 | 抽牌堆/弃牌堆,自动洗牌与耗尽重洗 |
| `hand.gd` | 28 | 手牌容器,带最大上限与溢出处理 |
| `card.gd` | 17 | 卡牌静态仓库,从 `data/cards.json` 加载(15 张) |
| `turn_manager.gd` | 109 | 回合流程+阶段机:4 阶段 player/intent/enemy/environment(+spirit 子阶段),`set_phase()` 广播 `turn:phase_changed`;首回合抽 5 张、之后 2 张、跳过处理;恐惧源(回合开始诅咒格/百鬼夜行)与回合结束恐惧结算(失控恢复+自然 -5) |
| `level_director.gd` | 112 | 关卡导演(GDD §八,2026-07 新增,**无 class_name,引用 EventBus 须动态 load/preload**)。三阶段阶段机(侦查/惊醒/决战,maps.json `levelFlow` 外置)、门格扫描、Boss 逃脱判定(到门边相邻格)+`report_boss_escaped`(置 lose_reason+广播 `boss:escaped` 含失败文案) |
| `tutorial_director.gd` | 53 | 教学导演(2026-07 新增)。加载 `data/tutorial.json`,turn/event/spirit 三种触发器,每条提示一次性;UI 显示在 battle_scene 横幅队列 |
| `json_loader.gd` | 20 | JSON 加载 + 内存缓存 + deep clone |
| `ui_atlas_loader.gd` | 78 | UI 图集配置加载器(`data/ui_atlas.json`)。⚠️ **疑似死代码:battle_scene 未引用它,UI 贴图路径/margin 硬编码在常量里** |

### 4.2 场景层 `scripts/scenes/`

| 文件 | 行数 | 职责 |
|---|---|---|
| `main_scene.gd` | ~170 | 标题屏(2026-07 重写)。预加载卡/单位/状态数据;全屏 AI 背景+八卦徽章+阿里普惠体标题+黄铜九图按钮,点击任意处进入战斗 |
| `battle_scene.gd` | **5357** | 战斗视图+控制器(上帝类)。见下方 §4.3 |

> **关于 noise/spirit 接线**:battle_scene.gd 通过 `const NoiseSystemScript = preload("res://scripts/core/noise_system.gd")` 和 `const SpiritSystemScript = preload("res://scripts/core/spirit_system.gd")` 这两个**脚本常量别名**实例化(`noise_system = NoiseSystemScript.new(state)` / `spirit_system = SpiritSystemScript.new(state)`,在 `_ready` 第 406-407 行)。**这两个系统是接上线的**,只是用了 preload 常量别名而非裸类名,搜 `NoiseSystem.new()` 会漏判。`ui_atlas_loader.gd` 则确属未引用的死代码(UI 贴图路径硬编码在 battle_scene 常量中)。

### 4.3 `battle_scene.gd` 内部分区(5604 行,~218 个函数)

按职责划分为以下区段(行号为近似,2026-07 UI 改造后整体有偏移):

| 区段 | 行号范围 | 关键方法 |
|---|---|---|
| 内嵌绘图类 + 常量 + 成员变量 | 1–271 | `OverlayLayer`、`CardArtLayer`;TILE/UI/字体/贴图常量;state 与各系统成员 |
| 生命周期 + 资源加载 | 272–524 | `_ready`(~170 行装配)、`_load_generated_ui_textures`、`_load_map_background` |
| UI 样式工厂(StyleBox/NinePatch) | 518–838 | `_make_*_panel_style`、**`_make_tex_panel_style`(九图 StyleBoxTexture 工厂,注意 Godot4 用 `texture_margin_*` 而非 patch_margin)**、`_make_card_style`、`_apply_button_frame`、`_apply_chinese_font` |
| HUD 布局搭建 | 854–998 | `_style_battle_ui`、`_setup_reference_side_panels` |
| 清理 + 坐标变换 + 相机 | 988–1117 | `cart_to_iso`、`screen_to_grid`、`_tile_center`、`_init_camera`、`_rotate_view` |
| 每帧 + 地图渲染 | 1119–1521 | `_process`、**`_draw`(~270 行巨型绘制)**、`_draw_exterior_tiles` |
| Overlay 层(噪音/意图/危险范围) | 1531–1745 | `_draw_overlay`、`_draw_noise_fields`、`_draw_enemy_intents` |
| 输入 + 悬停信息 | 1746–2063 | `_input`、`_update_hover_info`(~85 行)、`_calc_damage_preview` |
| 玩家行动 | 2065–2361 | `on_tile_click`、`select_unit`、`move_unit`、`play_selected_card`、`_on_end_turn_pressed` |
| 敌方回合执行 | 2362–2696 | `_execute_next_enemy`、`_animate_enemy_move`、`_enemy_attack`、`_calc_damage`、`_try_dodge` |
| EventBus 回调 + 交互菜单 | 2704–2870 | `_on_terrain_damage`、`_on_noise_propagated`、`_show_interaction_menu`、`_execute_interaction` |
| 飘字 + signal 回调 + 胜负/奖励 | 2871–3161 | `_on_unit_*`、`_show_result`、`_show_reward_screen`(~80 行)、`_pick_reward_cards` |
| 单位状态面板 + 精灵渲染 | 3162–3689 | `_show_stats_panel`、**`_update_sprite`(~240 行)**、`_create_or_update_sprite` |
| 手牌 UI 池 | 3690–3718 | `_get_card_panel`、`_on_card_panel_gui_input` |
| 物品栏 UI + 使用 | 3719–4063 | `refresh_inventory_ui`(~105 行)、`_use_selected_inventory_item`、`_execute_pickup` |
| 卡牌 UI(卡面/tooltip) | 4033–4465 | `refresh_card_ui`(~90 行)、`_init_turn_order_bar`、`_refresh_turn_order_bar`、`_show_card_tooltip` |
| 灵体条 UI | 4490–4542 | `_build_spirit_bar`、`_refresh_spirit_bar`、`_on_spirit_density_changed` |

## 五、数据文件说明(`data/`,13 个 JSON)

所有游戏规则配置化。**核心约定:新增环境交互必须优先进 `data/rules.json`,禁止在代码中硬编码地形名**;标签系统用 `Dictionary` 模拟集合(`{tag:true}`),`has()` 为 O(1)。

| 文件 | 内容 | 规模 |
|---|---|---|
| `balance.json` | 全局平衡:手牌/能量/AP 上限、地形闪避、状态效果参数 + `fear` 节(恐惧源/恢复/失控恢复系数/移动噪音) | ~10 数值 + 6 地形效果 + 6 状态 + 8 恐惧参数 |
| `cards.json` | 卡牌定义(cost/targetType/effects[]/rarity) | 15 张 |
| `units.json` | 4 名玩家角色(凛音/薄荷/焰华/钟馗):stats(含 fearThreshold)/初始牌组/道具/特性(traits id 驱动被动:heavy_push/silent_step/remote_trigger/fire_affinity/seal_master/spirit_body) | 4 角色 |
| `enemies.json` | 敌人(纸人/水鬼/僵尸/红衣女/棺材主)+ aiProfile(behavior/fearTags/noiseHearing/fear_noise/obsession + 差异化字段 patrolPath/teleportWhenWatched/waterLurk/leapMove/bossPhases 等) | 5 种(棺材主 `boss:true`) |
| `maps.json` | 地图 v2 多层格式(ground/effects/objects/collision)+ 出生点 + `levelFlow`(三阶段/逃脱配置) | 1 张(纸人抬棺 14×10) |
| `terrains.json` | 地形标签/移动消耗/颜色 | 15 种 |
| `effects.json` | 地形效果(火/水/糯米/墨线/符纸/诅咒/爆炸) | 7 种 |
| `objects.json` | 环境物体(火盆/水缸/米袋/铃铛/门/棺材/炸药桶) | 7 种 |
| `rules.json` | 交互规则表,驱动 TerrainSystem 连锁 | 10 条 |
| `statuses.json` | 状态效果(burn/freeze/stun/poison/slow/shield/taunt) | 7 种 |
| `ui_atlas.json` | UI 图集 9-slice 切分配置(**明确禁止在 GDScript 硬编码 patch_margin**)| 2 源 + 7 面板 + 6 图标 |
| `codex_ui_generation_tasks.json` | OpenAI Codex 生成 UI 素材的任务清单 | 23 任务 |
| `tutorial.json` | 教学提示文案与触发器(turn/event/spirit) | 5 条 |

## 六、实际完成状态(基于代码接线,非进度文档)

> ⚠️ **注意**:`docs/进度.md` 与旧文档的描述与代码有出入。本节以**代码是否在 battle_scene.gd 中实际实例化并接上线**为准。

### 6.1 已接线上线的系统

在 `battle_scene.gd` 中有引用并工作:`GameState`、`GameMap`、`TurnManager`、`CardResolver`、`InteractionSystem`、`TerrainSystem`、`AIController`、`Pathfinding`、`StatusEffectManager`。

- 多层地图 + 标签系统(GameMap v2)
- 地形交互规则引擎(TerrainSystem,10 条规则)
- 推/拉/推倒/拾取/放置/互动/点燃(InteractionSystem + battle_scene 互动栏七模式按钮,高亮相邻目标格)
- 卡牌战斗 + 手牌/牌组/背包
- 敌人 AI 状态机(patrol/confused/rage/fear/search/chase/attack)+ Utility 选点
- **AI 差异化行为(2026-07)**:巡逻路径(patrolPath+sightRange)、rage(执念威胁触发,无视恐惧,广播 `ai:state_changed`)、confused(符纸触发随机移动 1-2 回合)、红衣女被注视瞬移背刺/背对静止、水鬼水域半透明+相邻拖拽入水+离水变弱(伤害×0.5)、僵尸直线跳 2 格越障、Boss 两阶段(HP≤50% 广播 `boss:phase_changed`,阶段 1 固守+每 3 回合指挥 minion 进 rage,阶段 2 全图追击+无视噪音+规避激活阵眼)、百鬼夜行(灵气 10 全体 rage)。单测 `tools/test_ai_behaviors.gd` 40 断言
- **封印击杀判定(2026-07)**:spirit_system `check_seal_activation`/`activate_seal`(阵眼≥3 带 talisman + 灵气≥6 + 目标在阵区[射线法多边形+邻接]+灵体),互动栏「互动」模式激活,扣 1 AP 即死,广播 `seal:activated`,金色符文浮起特效
- **灵气密度效果(2026-07)**:tier 修正敌人 strength/move_range(weak 移速-1/强化 ×1.3/暴走 ×1.5);HUD 10 圆点灵气条(回合顺序面板下方)
- **恐惧值机制(2026-07)**:unit `fear` 0-100+阈值(units.json fearThreshold:凛音 80/薄荷 50/其他 65),恐惧源与恢复数值全部外置 balance.json `fear` 节;≥阈值失控 1 回合(操作拦截+紫"失控!"飘字+头像染紫),回合结束降阈值 60%;角色面板恐惧条真实值
- **角色环境被动(2026-07)**:凛音推距+1 且可推 heavy 重物;薄荷移动零噪音+卡牌远程摇铃;焰华 ignite 免 AP+火系卡伤害 ×1.5;钟馗阵眼格金色放置提示+致命伤留 1 HP(限 1 次)。单测 `tools/test_fear_passives.gd` 40 断言
- **三阶段关卡流程+逃脱+教学(2026-07)**:level_director 阶段机(侦查 1-3/惊醒 4-6 灵气+2/决战 7+ 强制破棺)、Boss 逃脱(灵气<6 时向门移动,到门边→"棺材主逃脱了…"失败,倒计时进胜利条件面板)、tutorial_director 5 条教学提示(turn/event/spirit 触发,一次性,顶部横幅)。单测 `tools/test_level_flow.gd` 43 断言
- **音效系统(2026-07-23)**:AudioStreamPlayer 池(4 个轮用,-8dB)+ `SFX_FILES` 映射(10 个 AI 生成 mp3,`assets/audio/sfx/`),`_play_sfx_placeholder` 实装;挂钩 object:pushed/pushed_over→push、object:bell_rung→bell、effect:added fire/explosion→ignite/explosion、出牌→card_play、seal:activated→seal、unit_damaged→hurt、玩家回合开始→turn_end、open/close→door、拾取→pickup、阶段切换复用 seal/explosion。验收 `tools/test_noise_spirit_accept.gd` 35 断言(噪音 BFS/听觉阈值/灵气变化/tier 端到端)
- EventBus 事件:`effect:added`、`object:pushed*/pulled`、`bell_rung`、`coffin:opened`、`noise:created/propagated`、`unit:terrain_damage`、`seal:activated`、`turn:phase_changed`、`ai:state_changed`、`boss:phase_changed`、`boss:escaped`、`unit:panicked/fear_changed/undying_survived` 已接线
- 14×10 Demo 地图"纸人抬棺"
- **渲染层升级(2026-07)**:规范化高亮配色(淡蓝移动/紫色目标/红色脉冲伤害/白色悬停)、我方 70px 翠绿/敌方 80px 朱红 HP 条、选中绿色发光菱形光环、单位椭圆阴影、敌人意图箭头化(红攻击/黄移动/紫恐惧/橙搜索)、噪音 3 层同心扩散环、v2 瓦片 4 帧动画(`_load_v2_frame_textures`/`_v2_anim_frame`,idle 6fps)
- **蒸汽朋克+国风道教 UI 全套(2026-07)**:34 张 AI 素材(`assets/ui/steampunk/` 18 张 + `assets/tiles/steampunk/` 13 张物体效果 + 标题 3 张);7 处 HUD 面板(状态/技能描述/胜利条件/悬停/tooltip/回合条/手牌底板)经 `_make_tex_panel_style()` 九图贴图化;`UI_TEXTURE_FILES`/`UI_PATCH_MARGINS` 全部指向 steampunk;物体渲染宽度收窄
- **标题屏重写(2026-07)**:全屏 AI 背景 + 八卦徽章 + 阿里普惠体标题 + 黄铜九图按钮

### 6.2 已接线但仅部分功能生效 / 死代码

- **`noise_system.gd` / `spirit_system.gd`**:已通过 preload 常量别名(`NoiseSystemScript`/`SpiritSystemScript`)在 battle_scene `_ready` 实例化并接 EventBus/signal(见 §4.2 注)。规则效果(BFS 衰减/听觉阈值/tier 影响移速与伤害)2026-07-23 经 `tools/test_noise_spirit_accept.gd` 35 断言运行验收通过。
- **`ui_atlas_loader.gd`(78 行)**:确属**死代码** —— battle_scene 未引用它,UI 贴图路径与 patch_margin 硬编码在常量 `UI_TEXTURE_FILES`/`UI_PATCH_MARGINS` 中。

### 6.3 主要技术债务

| 问题 | 说明 |
|---|---|
| `battle_scene.gd` 5604 行 | 渲染/UI/输入/动画/回合编排全集中,`_draw`(~270行)、`_update_sprite`(~240行)等巨方法。应逐步拆为独立 Control 节点/模块 |
| ~~拉(Pull)操作~~ | ✅ 2026-07 已补 `pull()`(1 AP,物体拉到角色位,角色后退 1 格),单测 tools/test_pull.gd |
| ~~敌方意图预览阶段~~ | ✅ 2026-07 已完成:计划锁定+1.8s 预览(INTENT_PREVIEW_SECONDS)+语义图标+死亡/恐惧打断 |
| ~~AI 差异化~~ | ✅ 2026-07 已完成:四敌特化+Boss 两阶段+rage/confused/巡逻,单测 tools/test_ai_behaviors.gd(40 断言)。遗留:糯米/墨线克制僵尸、僵尸弧线跳跃动画 |
| EventBus 事件未对齐 GDD | GDD 定义约 24 事件,实际接线的约 13 个;多个预留事件无发出方/订阅方 |
| ~~音效~~ | ✅ 2026-07-23 已补:10 个 AI 生成音效(`assets/audio/sfx/`)+ AudioStreamPlayer 池,10 处挂钩 |
| ~~UI 风格~~ | ✅ 2026-07 已由蒸汽朋克+国风道教全套替换解决(见 §6.1) |

## 七、代码风格约定

### 7.1 命名
- GDScript 文件 `snake_case.gd`;类名 `PascalCase`(`class_name Unit`);函数/变量 `snake_case`;私有 `_` 开头;常量 `UPPER_SNAKE_CASE`。

### 7.2 缩进与格式
- **Tab 缩进**(Godot 默认)。长参数列表换行对齐。大字典/数组放 JSON,不在 GDScript 里写死。

### 7.3 系统间通信
- **优先 EventBus 字符串事件**,禁止系统间直接强耦合调用。
- GameState 的原生 Godot `signal` 仅用于 UI 刷新;新功能优先经 EventBus 再由 battle_scene 监听更新 UI。

### 7.4 数据先行
据 `docs/代码实施方案.md`:1) 先定义 JSON Schema/字段 → 2) 写解析代码 → 3) 写逻辑 → 4) 运行验收。

### 7.5 注释
- 复杂算法、规则匹配、坐标转换需中文注释。battle_scene.gd 已有较多内联注释,新增 UI/渲染保持类似粒度。

### 7.6 UI 素材风格
- **新 UI/环境素材一律走蒸汽朋克生成管线**:`tools/gen_steampunk_manifest.json` 加条目 → `gen_steampunk_assets.py` 生成 → `postprocess_steampunk.py` 后处理(去水印/alpha 裁剪/缩放)。
- **禁止西幻风**(无蓝宝石/无西式宝石/无魔幻水晶),prompt 统一以蒸汽朋克+国风道教基调开头( brass/齿轮/朱砂红/符纸黄/玄黑,见 manifest 与 AGENTS §6.1)。
- 生成后必须人工目检(ReadMediaFile),有文字/人物/风格跑偏就重生成。
- 新 PNG 若用 `load()` 加载,需先 `--import` 生成 .import;或走 `Image.load_from_file` 绕过(如 battle_scene `_load_image_texture`)。

## 八、常用修改入口

| 想改什么 | 先看这里 |
|---|---|
| 角色属性/初始牌组 | `data/units.json` |
| 敌人属性/AI 参数 | `data/enemies.json` + `scripts/core/ai_controller.gd` |
| 地图布局 | `data/maps.json` |
| 地形规则/连锁反应 | `data/rules.json` + `data/terrains.json` + `scripts/core/terrain_system.gd` |
| 卡牌效果 | `data/cards.json` + `scripts/core/card_resolver.gd` + `card_effect_parser.gd` |
| 状态效果 | `data/statuses.json` + `scripts/core/status_effect_manager.gd` |
| 环境互动(推/拉/拾取) | `scripts/core/interaction_system.gd` |
| 新系统通信事件 | `scripts/core/event_bus.gd`(字符串事件) |
| UI 布局/颜色/字体 | `scripts/scenes/battle_scene.gd`:`_style_battle_ui`、`_make_*_style`、HUD 节点、`_draw_*` |
| UI 贴图/九图边距/面板样式 | `assets/ui/steampunk/` + battle_scene 的 `UI_TEXTURE_FILES`/`UI_PATCH_MARGINS` 常量与 `_make_tex_panel_style()` |
| 新 UI/物体素材生成 | `tools/gen_steampunk_manifest.json` + `gen_steampunk_assets.py` + `postprocess_steampunk.py`(见 §7.6) |
| 标题屏 | `scripts/scenes/main_scene.gd`(UI 全部脚本搭建)+ `scenes/main.tscn` |
| 噪音传播算法 | `scripts/core/noise_system.gd`(已接线,见 §4.2 注) |
| 音效文件/映射/挂钩 | `assets/audio/sfx/` + battle_scene `SFX_FILES`/`_play_sfx_placeholder`/`_build_sfx_pool` |
| 灵气密度机制 | `scripts/core/spirit_system.gd`(已接线,见 §4.2 注) |

## 九、安全与注意事项

- 本地 Godot 游戏项目,无网络服务、无敏感凭据。
- `.godot/`、`__pycache__/` 已在 `.gitignore`,不应提交。
- 工具脚本默认只读写项目内 `assets/`,不碰项目外文件。
- 改 JSON 前建议 `git diff` 确认状态,避免误改地图/规则导致游戏无法运行。
- **改 `battle_scene.gd` 前务必定位到正确区段**(见 §4.3),5604 行容易找错位置。

## 十、文档索引(`docs/`)

| 文档 | 主题 | 关键信息 |
|---|---|---|
| `GDD.md` | 游戏设计文档 | 世界观、核心循环、24 事件规范、噪音BFS/灵气公式/封印判定/AI状态转换、6 阶段开发路线 |
| `代码实施方案.md` | 渐进式重构方案 | 5 原则、4 Phase、文件修改清单(新增15/重写4/扩展7)、maps v1→v2 迁移、M1-M4 里程碑 |
| `进度.md` | 进度追踪 | 最后更新 2026-07-23,整体~45%(Phase1 85%/Phase2 60%/Phase3 40%/Phase4 25%/Phase5 55%/Phase6 0%)。⚠️ 与代码实际接线有出入时,以 §6 为准 |
| `Art_Bible.md` | 美术圣经 v0.1 | 禁西幻元素、核心色板(玄黑/暗金/朱红/符黄/靛青/翠绿/紫黑)、阿里巴巴普惠体、单位/UI 尺寸规范 |
| `AI_Art_Pipeline_Codex.md` | AI 美术管线 | Codex/gpt-image2 风格前缀、5 类素材 Prompt 模板、验收清单 |
| `Codex_UI_Generation_Task.md` | Codex 生成任务 | 23 个 UI 素材任务(与 `data/codex_ui_generation_tasks.json` 对应) |

> 另有项目根 `UI.md` — UI 风格问题诊断报告(当前 UI 与 GDD 目标差距分析)。
