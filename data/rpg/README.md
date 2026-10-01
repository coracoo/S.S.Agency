# RPG 独立规则数据

本目录是标准回合制规则的独立 JSON 源，不接入旧卡牌 xlsx 导出器，也不修改旧配置与素材。数值来源：`docs/superpowers/specs/2026-09-30-rpg-combat-design.md`。

## 修改与验证

修改这里的 JSON 后运行：

```sh
python3 tools/rpg/run_checks.py --suite data --import
python3 tools/rpg/run_checks.py --suite all --legacy --import
```

引擎不在 PATH 时加 `--godot /实际路径/godot`，或设置 `GODOT_BIN`。运行器为每次运行创建新的临时目录，隔离 XDG 数据／配置／缓存与 APPDATA／LOCALAPPDATA。先用引擎验证实际 `user://` 位于该目录，失败即停止；旧写档测试只允许在验证成功后执行。临时目录退出后清理，不触碰玩家存档。不要直接运行旧回归脚本。

## 文件与查询协议

七份数据使用相同封套：`schema_version: 1`、`rules_version: "rpg-0.1"`、`definitions: [...]`。ID 在各定义种类内唯一；玩家技能与敌方技能在统一 `abilities` 查询中也必须唯一。

- 职业 ID：`guard`、`swordsman`、`ranger`、`mage`、`healer`、`controller`
- `classes` 含五级标准装 `base_stats`、固定 `growth`、四个有序 `skill_ids` 与默认普攻类型
- `skills` 恰含 24 个玩家技能。字段为 `mp_cost`、`cooldown`、`target_rule`、`damage_type`、`element`、`single_direct`、`unlock_level`、有序 `effects`；分支数值也入库；`Catalog.skill_for(actor, skill_id)` 按角色等级和所选分支返回有效技能定义的深复制，供预览、费用校验与执行共同使用
- `enemies` 含五级属性、弱点／抗性、目标策略及有序 `abilities`；Boss 六步顺序和第二阶段数值公开存放在 `boss` 中
- `statuses` 定义时钟、效果分类、负面与可驱散性；运行中状态实例另保存来源、强度、generation 和快照
- `equipment` 按 `weapon`／`armor`／`accessory` 槽替换。空字典表示无装备；空字符串表示该槽未装备。属性先减全部标准装，再加实际装，避免重复计算标准加值
- `items` 保存初始库存与有序效果；`encounters` 保存固定等级、敌人、经验、下一场及休息标志

`RpgCatalog.new().load_all()` 返回错误数组；空数组才表示目录可查询。失败时全部查询为空，避免半加载数据。`get_definition(kind, id)`、`get_all(kind)` 返回深复制；`get_ids(kind)` 按 ID 排序。kind 使用复数文件名，敌我技能统一查询使用 `abilities`。需要角色分支生效后的玩家技能时使用 `skill_for`，不要直接用基础 `skills` 定义替代有效技能。

## 效果与时钟

目标枚举：`self`、`other_ally`、`single_ally`、`all_allies`、`single_enemy`、`all_enemies`、`fallen_ally`。单敌／单友只针对存活者；复苏道具专用 `fallen_ally`。

元素枚举：`neutral`、`fire`、`ice`、`lightning`、`spirit`。伤害类型为 `physical`／`magic`，辅助技能元数据为 `none`。

效果数组按顺序执行，例如破甲斩先 `damage` 再 `apply_status`，猎杀先按标记计算 `damage` 再 `consume_status`。伤害效果自身保存系数、类型、元素、单体直接标志与可暴击性。Boss 的全部直接伤害设置 `can_crit: false`。

`apply_status` 保存 `status_id`、`magnitude`、`duration`、`clock`；灼烧另保存来源 MATK 与输出／虚弱快照要求。`shield`／`heal` 使用固定项、系数和取值属性。条件伤害用 `condition`、`conditional_coefficient` 表达，不能新增随机闪避或额外行动。

时钟仅 `target_slot`、`round_snapshot`、`next_owner_slot`。冰矢与迟滞术共用 `slow`，分别影响未来 1／2 次轮序快照。`cover`、`defend` 下一次来源自身槽开始到期；护盾持续目标槽，不与其他护盾叠层。清醒 `awake` 不可驱散；Boss 失衡 `stagger` 使用目标槽时钟，到承诺释放槽结束。

## 演进边界

角色创建始终保存四个固定卡位；`unlocked_skill_ids()` 决定当前可用项，不删除锁定卡位。六级／九级分支由 `Catalog.skill_for()` 解析为有效数据；`EffectResolver`／`BattleEngine` 执行技能与伤害／状态，`EnemyPolicy` 决定敌人行动，`Campaign` 原子提交经验和安全进度。数据目录负责定义与校验，不直接修改战斗或存档。存档只能使用新 `user://rpg_v1/` 空间，不能读写旧 `user://progress.json`。
