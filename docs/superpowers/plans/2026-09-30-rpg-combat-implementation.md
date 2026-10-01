# 标准回合制 RPG 核心战斗 Implementation Plan

**Goal:** 完整实装六职业、24 个固定技能、可重放的标准回合制战斗与全部六选三组合。守卫／剑士／治疗的两场普通战＋休息＋Boss 连战只是内部开发验收节点，不单独推送，也不算完成。

**Architecture:** 新规则独立放在 `scripts/rpg/`，使用不依赖场景树的 `RefCounted` 模型与外置 JSON。唯一战斗模型负责费用、伤害、状态、意图、日志和胜负；视图只消费模型预览与事件。新存档与旧卡牌存档隔离，现有标题及探索场景通过薄适配器选择性接入，不恢复已删除的 v1/v2 系统。

**Tech Stack:** Godot 4.6 系列、GDScript、JSON、项目现有 `SceneTree --script` 测试方式；Python 3 仅用于隔离测试运行。无需新增 Godot 插件或服务。

**Spec:** `docs/superpowers/specs/2026-09-30-rpg-combat-design.md`。执行前从已评审的 `rpg_design/2026-09-30-rpg-combat-design.md` 原样复制；本计划不替代该规格的全部数值表。

**已核验基线:** `coracoo/S.S.Agency` 的 `db84bb001bad31d7e43efc021b52fe1bd6ec8100`。本计划基于其只读快照，而不是旧工作副本。执行时从最新远端建立隔离工作分支；现有隔离 worktree 可在保留原分支与文档提交后切到新分支，不必重复建目录。若基线变动，先核对本计划列出的接线函数。已有基线验证在隔离目录运行 Godot 4.6.3 导入（退出0，但存在失效主题错误）及旧v4规则测试（全部PASS）；这不代表新战斗或全项目已验证。计划本身尚未实现或运行任何新战斗代码。

## Global Constraints

- “六名固定职业角色中选三人出战，每人有独立 HP、MP，每轮按速度各行动一次。”
- “四张常驻技能卡只是技能按钮，没有抽牌、共享牌库或共享行动点。”
- “现有故事、场景、谜题与演出保持原设定，敌人名称在接入时映射现有角色。”
- “等级为 1–10”；“六人共享队伍等级”；“从 L 升 L+1 需要 100L 经验”。
- “标准武器提供 ATK+5、MATK+5；标准护甲提供 HP+20、DEF+5、MDEF+5；标准饰品提供 MP+5，已计入五级表。”
- “首测固定五级守卫、剑士、治疗，标准装备、完整四技能、无分支。”
- “顺序为猎犬＋盾兵，随后猎犬＋咒徒，休息准备点，再单体 Boss。”
- “两场普通战分别给 40 经验，Boss 给 120”；库存为治疗药 3、魔力药 1、复苏药 1、净化粉 1。
- “相同版本、输入与种子必须重放一致”；“界面只显示状态，不另写一套计算结果。”
- “不得在重试时额外赠药或暗降难度”；没有隐藏补给、锁血、追加行动或为了轮数目标改变结算。
- 新增注释与说明以中文为主，GDScript 使用 Tab。保留现有美术、素材、xlsx 管线、3D 预览和动画；新 `data/rpg/` 为独立 JSON 源，不修改旧 xlsx 管理的数据。
- 新模式初期是标题页明确标注的可选入口，旧入口保持可用；全套验收前不把新模式替换为默认章节战斗。
- 新进度只写 `user://rpg_v1/`；不迁移、不覆盖、不删除 `user://progress.json`、旧构筑或其他玩家存档。

## Review Focus

1. 确认按钮双击、过期预览、取消后重选：一次合法行动只收费一次，非法输入不改变状态或 RNG（任务 3、6）
2. 蓄力期间目标倒地后复活、队友被眩晕、Boss 变速与跨阶段：承诺目标不漂移，仍有真实反应窗口（任务 4）
3. 刷新较弱状态、清醒期间封缄、群体控制部分免疫：按有效效果决定合法性，不能暗收费或无限续强状态（任务 2、7）
4. 战果保存失败、重复交付战果、损坏或未来版本存档：不丢旧档、不重复发经验或触发剧情，错误可见且可重试（任务 5）
5. 自动测试和真实游玩的存档目录混用：测试先验证隔离目录，不得执行会删除真实旧档的回归脚本（任务 1、8）

---

## 文件边界与共用协议

所有新规则只依赖下列新文件；显式 `preload`，不依赖已删除的 EventBus／NarrativeState autoload。

- `scripts/rpg/catalog.gd`：加载、校验及查询规则数据
- `scripts/rpg/actor_factory.gd`：六人属性、装备差值、解锁、成长
- `scripts/rpg/battle_state.gd`：模型快照、版本、稳定 actorId、硬约束校验
- `scripts/rpg/damage_rules.gd`、`status_rules.gd`：纯计算、伤害吸收、状态时钟
- `scripts/rpg/command_rules.gd`：目标、费用与可执行性；`effect_resolver.gd`：按数据顺序执行效果
- `scripts/rpg/battle_engine.gd`：轮序、行动槽、提交、单一 RNG、胜负批次
- `scripts/rpg/enemy_policy.gd`、`boss_policy.gd`：公开意图和 Boss 六步承诺
- `scripts/rpg/replay.gd`：规范化日志、重放及逐事件校验
- `scripts/rpg/campaign.gd`、`save_store.gd`：六人跨战状态、库存、重试快照及安全存档
- `scripts/rpg/encounter_router.gd`：现有场景映射、进出战上下文；不承载伤害规则
- `scripts/rpg/ui/battle_presenter.gd`、`battle_view.gd`、`launcher_view.gd`：模型投影、战斗画面、战前与休息操作
- `scenes/rpg/battle.tscn`、`launcher.tscn`：独立可玩入口
- `data/rpg/{classes,skills,statuses,enemies,items,equipment,encounters,presentation}.json`：新规则与现有素材引用
- `tools/rpg/run_checks.py`、`run_tests.gd`、`test_environment.gd`、`fixtures.gd`、`test_*.gd`：隔离运行与分组测试

### Dictionary 协议（字段类型固定，不把 Node／Resource 放入快照）

`BattleState` 保存 `schema_version:int=1, rules_version:String, revision:int, seed:int, rng_state:String, round:int, phase:String, queue:Array[String], queue_index:int, active_actor_id:String, actors:Dictionary, inventory:Dictionary, outcome:String, accepted_commands:Dictionary`。`rng_state` 用十进制字符串保存 64 位状态，避免 JSON 数字精度损失。

`Actor` 保存规格第八节字段，代码使用 snake_case：`actor_id, side, class_id, level, stats, hp, mp, equipment, skill_ids, branch, slot_count, opportunity_count`，另有 `statuses:Array[Dictionary], shield:Dictionary, cooldown_until:Dictionary, revived_round:int, intent:Dictionary, boss:Dictionary`。七项基础属性键固定为 `hp, mp, atk, matk, def, mdef, spd`，`stats.hp/mp` 是上限。

`Status`：`id, source_id, magnitude:float, clock:String, remaining:int, generation:int, applied_slot:int, dispellable:bool, snapshot:Dictionary`。时钟只有 `target_slot, round_snapshot, next_owner_slot`；槽开始记录状态 generation，槽末只扣仍是同一 generation 的既存状态。较弱施加不改 generation。

`Command`：`command_id:String, expected_revision:int, actor_id:String, kind:String, ability_id:String, target_ids:Array[String]`；kind 为 `attack_physical, attack_magic, defend, skill, item`。`Preview`：`legal:bool, reasons:Array[String], effective_target_ids:Array[String], mp_cost:int, item_cost:int, cooldown:int, effects:Array[Dictionary], damage_ranges:Array[Dictionary], revision:int`；预览显示非暴击／暴击范围及控制无效原因，不偷看或推进 RNG。

`Event`：`sequence:int, type:String, actor_id:String, target_id:String, payload:Dictionary`；payload 按类型保留队列、资源前后、乘区、暴击抽样、护盾、状态变动或胜负。事件不含时间戳作为规则输入。所有数组顺序明确；全体目标按 actorId 排序。

`BattleResult`：`battle_id:String, outcome:String, roster:Array[Dictionary], inventory:Dictionary, xp:int, story_patch:Dictionary, replay:Dictionary`。`story_patch` 只含原场景需要的已解决线索／下一场景等，不发明新剧情事件。

### 技能 ID 与实现顺序

- 守卫：`cover, shield_bash, iron_wall, taunt`
- 剑士：`heavy_slash, armor_break, sweep, battle_spirit`
- 治疗：`heal, group_heal, cleanse, holy_shield`
- 游侠：`mark, hunt, ambush, smoke_screen`
- 法师：`firebolt, flame_wave, ice_arrow, burn_brand`
- 控制：`weaken, slow, seal, magic_break`

这 24 个 ID 在任务 1 入库；先让前三职业的 12 技能可玩，任务 7 完成其余 12 个效果及六级／九级分支。冰矢影响下一次轮序快照，迟滞影响后续两次，直接照规格实现。

## Task 1：隔离测试入口、数据与成长

**Files**
- Create：`data/rpg/classes.json`, `skills.json`, `statuses.json`, `enemies.json`, `items.json`, `equipment.json`, `encounters.json`
- Create：`scripts/rpg/catalog.gd`, `actor_factory.gd`, `battle_state.gd`
- Create：`tools/rpg/run_checks.py`, `run_tests.gd`, `test_environment.gd`, `fixtures.gd`, `test_data.gd`
- Modify：`project.godot` 的 `[gui] theme/custom`；只移除已指向不存在 `resources/v2/default_theme.tres` 的引用，不恢复 v2 文件
- Create：`docs/superpowers/specs/2026-09-30-rpg-combat-design.md`（原样复制已审规格）

**Interfaces**
- `RpgCatalog.load_all(root_path: String = "res://data/rpg") -> Array[String]`：空数组表示验证通过
- `RpgCatalog.get_definition(kind: String, id: String) -> Dictionary`：深复制定义
- `RpgActorFactory.create(class_id: String, actor_id: String, level: int, equipment: Dictionary) -> Dictionary`
- `RpgActorFactory.stats_for(class_id: String, level: int, equipment: Dictionary) -> Dictionary`
- `RpgBattleState.validate(state: Dictionary) -> Array[String]`
- 各测试文件 `static func run() -> Array[String]` 返回失败断言；runner `--suite data|rules|engine|ai|campaign|ui|roster|all`，成功退出 0，失败退出 1

- [ ] **Step 1：写失败测试**。`test_data.gd` 检查六个职业、每职业四个唯一 skillId、七属性与表完全一致；守卫 L1 HP/MP=224/22、L5=320/30、L10=440/40；无装备的 L5 守卫 HP=300、MP=25、ATK=37、MATK=13、DEF=45、MDEF=25；重复 ID、缺引用、非法等级、负库存被拒绝而非静默修复。
- [ ] **Step 2：运行并确认失败**。`python3 tools/rpg/run_checks.py --suite data`；首轮只允许因模型未实现失败，不能访问真实用户目录。
- [ ] **Step 3：实现隔离运行器**。每次建立临时目录，设置测试进程 XDG_DATA_HOME、XDG_CONFIG_HOME、XDG_CACHE_HOME／APPDATA／LOCALAPPDATA，并先用 `test_environment.gd` 校验 `OS.get_user_data_dir()` 确实位于此目录；不符合即退出，禁止开始写档测试。运行器支持 `--legacy`，只有该校验成功才运行旧测试。不得假定引擎支持未经验证的命令行用户目录参数。
- [ ] **Step 4：实现目录、数据与属性接口**。逐格迁入规格所有数值，技能效果为有序数组；数据校验同时检查目标、元素、single_direct、CD、解锁等级及状态时钟。属性计算先减标准装备再加实际装备；最大 HP≥1，其余≥0。新 JSON 的修改说明写在 `data/rpg/README.md`，不接旧卡牌导出器。
- [ ] **Step 5：修复失效主题引用，验证并提交**。再次运行 data；在隔离目录执行 Godot headless import，确认失效主题错误消失，记录任何其余警告，不能把退出0等同于没有错误。仅提交本任务文件：`feat(rpg): add validated combat data and isolated tests`。

## Task 2：统一伤害、护盾与状态时钟

**Files**
- Create：`scripts/rpg/damage_rules.gd`, `status_rules.gd`, `tools/rpg/test_rules.gd`
- Modify：`tools/rpg/fixtures.gd`, `run_tests.gd`

**Interfaces**
- Consumes：任务 1 Actor／Status／Catalog
- `RpgDamageRules.direct(source: Dictionary, target: Dictionary, effect: Dictionary, modifiers: Dictionary, critical: bool) -> Dictionary`：返回 `damage:int, factors:Dictionary`
- `RpgDamageRules.periodic(status: Dictionary, target: Dictionary) -> Dictionary`；`heal_amount(fixed: float, coefficient: float, matk: float) -> int`
- `RpgDamageRules.absorb(target: Dictionary, amount: int) -> Dictionary`：原地更新 HP／盾，返回 `absorbed, hp_loss, defeated`
- `RpgStatusRules.apply(actor: Dictionary, status: Dictionary) -> Dictionary`；`begin_slot(actor: Dictionary) -> Dictionary`；`end_slot(actor: Dictionary, token: Dictionary) -> Array[Dictionary]`
- `RpgStatusRules.begin_round(actors: Dictionary) -> Array[Dictionary]`；`end_round(actors: Dictionary) -> Array[Dictionary]`；`cleanse(actor: Dictionary) -> Array[Dictionary]`
- `RpgStatusRules.immunity(actor: Dictionary, effect: Dictionary) -> String`：空字符串表示可施加；不把“打断”和“眩晕”合并成一种免疫

- [ ] **Step 1：写失败断言**。重斩=72、愈合=86、火弹对 MDEF25=73、灼印基础跳伤=13；100×0.6×0.7=42，再扣30盾只损12HP；仅最终四舍五入，非零直接伤害≥1；治疗不受虚弱／战意影响。
- [ ] **Step 2：补充时钟断言并跑红**。自身新增战意仍剩2槽；虚弱准确作用未来2槽；较弱状态不延长强状态；同强取较长、强替换；较弱盾不续强盾，零伤害不损盾；防御先过期再灼烧；净化移除规格列出的8种负面而不移除清醒／蓄力／阶段。运行 `python3 tools/rpg/run_checks.py --suite rules`，预期失败。
- [ ] **Step 3：实现伤害接口**。物理／魔法共用乘区管线，元素只有一项；输出增益封顶+50%、易伤+25%、同类减伤只取最强、掩护另乘。持续伤害保存源 MATK 和适用持续伤害的增益／虚弱，战意不进入灼烧快照；跳伤只读当前目标火抗、减伤和盾。
- [ ] **Step 4：实现状态接口**。用 generation 防止自身槽刷新后立刻减时长；缓速在下一次／下两次排序生效，最后一次受影响轮结束移除。成功眩晕消耗槽后生成2槽清醒，提前净化眩晕不产生清醒；强度比较字段固定为 magnitude，灼烧 magnitude 是保存后的每跳源基础量。
- [ ] **Step 5：跑绿并提交**。rules 全部通过，再跑 data，提交 `feat(rpg): add shared damage and status resolution`。

## Task 3：确定性行动引擎与前三职业完整命令

**Files**
- Create：`scripts/rpg/command_rules.gd`, `effect_resolver.gd`, `battle_engine.gd`, `replay.gd`
- Create：`tools/rpg/test_engine.gd`, `test_replay.gd`
- Modify：`scripts/rpg/battle_state.gd`, `tools/rpg/run_tests.gd`, `fixtures.gd`

**Interfaces**
- Consumes：任务 1–2
- `RpgBattleEngine.start(setup: Dictionary, seed: int) -> Dictionary`
- `RpgBattleEngine.advance() -> Array[Dictionary]`：处理自动槽，停在需要玩家选择或终局
- `RpgBattleEngine.preview(command: Dictionary) -> Dictionary`
- `RpgBattleEngine.submit(command: Dictionary) -> Dictionary`：返回 `accepted:bool, reasons:Array[String], events:Array[Dictionary], revision:int`
- `RpgBattleEngine.snapshot() -> Dictionary`；`restore(snapshot: Dictionary) -> void`
- `RpgCommandRules.preview(state: Dictionary, command: Dictionary, catalog: RefCounted) -> Dictionary`
- `RpgEffectResolver.resolve(state: Dictionary, command: Dictionary, catalog: RefCounted, rng: RandomNumberGenerator) -> Array[Dictionary]`
- `RpgReplay.record(initial: Dictionary, commands: Array[Dictionary], events: Array[Dictionary]) -> Dictionary`；`verify(recording: Dictionary, catalog: RefCounted) -> Dictionary` 返回 `matches, first_difference`

- [ ] **Step 1：写失败测试**。同速玩家优先、同阵营 actorId 升序；轮内变速不改 queue；每轮最多一槽；倒地不增长 slot_count，眩晕增长但不增长 opportunity_count；复活同轮没有行动。CD1 在槽2施放，槽3不可用、槽4可用；眩晕推进CD，倒地不推进。
- [ ] **Step 2：写事务与职业断言并跑红**。取消／错误目标／不足MP／空库存完全不变；同 command_id 重交不得第二次收费，旧 revision 被拒绝；治疗不能复活、复苏药保留原MP且恢复30%HP。验证前三职业12技能：护卫转伤重算守卫防御且无链、群攻不转移、盾击仅打断、破甲在伤害后、战意不加治疗、圣盾与净化正确。运行 engine，预期失败。
- [ ] **Step 3：实现提交与队列**。合法性在收费前完整验证；只在被接受的提交推进 RNG 与 revision。冷却使用 `cooldown_until[skill_id] = 当前slot_count + CD + 1`。槽顺序严格采用规格①–⑥；自动推进不可忙循环，遇玩家输入即返回。
- [ ] **Step 4：实现效果批次、倒地与道具**。数据效果顺序驱动；掩护只拦敌方 single_direct 的首个命中并立刻消费，负面随转移；倒地立即清状态、盾、掩护、待释放意图，致死命中不再挂状态。一次群攻全部目标处理后统一判胜负；双方同时全倒为失败。
- [ ] **Step 5：实现 RNG 与重放验证**。每目标直接伤害独立5%暴击，Boss技能显式禁暴击；预览、治疗、盾、持续伤害不抽随机数。记录版本、初始快照、种子、队列、指令与全部结算事件；相同输入种子逐事件相同，插入任意次预览不改变结果，修改一条输入能定位首个不同事件。
- [ ] **Step 6：跑绿并提交**。`python3 tools/rpg/run_checks.py --suite engine` 同时运行 replay 测试，再回归 data/rules；提交 `feat(rpg): implement deterministic turns and core party actions`。

## Task 4：普通敌人预告与 Boss 六步循环

**Files**
- Create：`scripts/rpg/enemy_policy.gd`, `boss_policy.gd`, `tools/rpg/test_ai.gd`
- Modify：`scripts/rpg/battle_engine.gd`, `effect_resolver.gd`, `status_rules.gd`, `tools/rpg/run_tests.gd`

**Interfaces**
- `RpgEnemyPolicy.plan(state: Dictionary, enemy_id: String, catalog: RefCounted) -> Dictionary`
- `RpgEnemyPolicy.refresh_target(state: Dictionary, intent: Dictionary) -> Dictionary`：保留招式，只在规则允许时换目标
- `RpgBossPolicy.plan(state: Dictionary, boss_id: String, catalog: RefCounted) -> Dictionary`
- `RpgBossPolicy.on_slot_end(state: Dictionary, boss_id: String, skipped: bool) -> Array[Dictionary]`
- `RpgBossPolicy.interrupt(state: Dictionary, boss_id: String) -> Array[Dictionary]`
- `RpgBossPolicy.on_round_start(state: Dictionary, boss_id: String) -> Array[Dictionary]`
- Intent 固定字段：`ability_id, target_ids, damage_type, element, added_statuses, interruptible, locked, preview`。Boss 另存 `step, charge_valid, locked_targets, opportunity_thresholds, committed_coefficient, committed_phase_multiplier, phase, pending_phase`。

- [ ] **Step 1：写普通 AI 失败测试**。战前及敌方槽末有下一招预告；猎犬／火灵最低HP比例，盾兵最高当前HP，咒徒最高ATK，同值actorId；精英独立遭遇，不加入首测连战。MP不足改免费普攻；目标未倒地不偷换，挑衅立即刷新普通单体意图而不改锁定蓄力。
- [ ] **Step 2：写 Boss 边界并跑红**。循环1–6、蓄力分别只扣6/12MP一次；穿刺目标倒地时空放、复活后仍攻击原目标；盾击造成失衡到释放槽末；封缄取消并跳过释放槽不额外多罚一槽；跳过准备则对应释放空行动；MP不足的准备和释放各自变普攻。运行 ai，预期失败。
- [ ] **Step 3：实现普通与 Boss 接口**。敌我共用引擎与效果解析，政策只决定已公开的命令。持续展示招式、目标、类型和附加状态，伤害范围由模型随状态刷新。
- [ ] **Step 4：实现反应窗口和阶段边界**。每次蓄力对当时存活队员记 `opportunity_count+1`，复活者加入检查；未达门槛的仍存活队员存在时继续蓄力，不收费、不推进步骤。脉冲成功蓄力到释放期间拒绝眩晕与打断，软控照常。首次≤40%HP只预约，下轮+20%直接伤害、SPD+5；已承诺蓄力保留目标、系数、阶段倍率，命中时重新应用虚弱和目标减伤。
- [ ] **Step 5：补测、跑绿并提交**。加速、眩晕导致未获选择机会、倒地/复活、跨阶段蓄力都覆盖；Boss 非保护步骤可正常眩晕，清醒不阻挡单独打断；运行 ai＋engine，提交 `feat(rpg): add visible enemy intents and committed boss cycle`。

## Task 5：跨战资源、安全存档与现有场景接线

**Files**
- Create：`scripts/rpg/campaign.gd`, `save_store.gd`, `encounter_router.gd`, `tools/rpg/test_campaign.gd`
- Modify：`scripts/scenes/stage_scene.gd` 的 `_go_battle`、`_show_clue_closeup` 和 `_ready` 恢复点
- Modify：`tools/rpg/run_tests.gd`, `data/rpg/encounters.json`

**Interfaces**
- `RpgCampaign.new_run(class_ids: Array[String], level: int = 5) -> Dictionary`
- `RpgCampaign.begin_battle(encounter_id: String, world: Dictionary) -> Dictionary`：保存完整战前快照后返回 engine setup
- `RpgCampaign.apply_result(result: Dictionary) -> Dictionary`：`ok, already_applied, error`
- `RpgCampaign.retry_battle() -> Dictionary`；`rest() -> Dictionary`；`use_item_outside(item_id: String, target_id: String) -> Dictionary`
- `RpgCampaign.set_party(actor_ids: Array[String]) -> Dictionary`；`equip(actor_id: String, slot: String, item_id: String) -> Dictionary`；`set_branch(actor_id: String, branch_id: String) -> Dictionary`
- `RpgSaveStore.load_safe(path: String = "user://rpg_v1/slot_01.json") -> Dictionary`；`write_safe(snapshot: Dictionary, path: String = "user://rpg_v1/slot_01.json") -> Error`
- `RpgEncounterRouter.begin(source_scene: String, battle_scene: String, world: Dictionary, pending_clue_id: String = "") -> Dictionary`；`finish(result: Dictionary) -> Dictionary`
- 新 Stage 方法 `export_rpg_world() -> Dictionary` 与 `restore_rpg_world(world: Dictionary) -> void`；world 保存 scene_path、player_x、facing、resolved、dlg_fired、exit_prompted、spirit、party_index，不保存 Node 引用

- [ ] **Step 1：写跨战失败测试**。第一场→第二场 HP/MP/库存/倒地保留，状态/盾/CD清零；休息复活并回满六人但库存不变；80/20/30%药物效果正确。两场40＋Boss120只得200XP，仍L5；100L升级阈值、不自动回血、L10停止累计。
- [ ] **Step 2：写安全失败测试并跑红**。败北重试完整恢复进战快照与物资，结果重复提交只给一次经验；战中／过场中存档被拒绝；损坏／未来 schema 文件报错并保留原文件。模拟写入失败：奖励、剧情和当前安全档全都不部分提交。运行 campaign，预期失败。
- [ ] **Step 3：实现 campaign 和 save_store**。安全档为同一版本化快照，包含六人、编队、装备、分支、经验、库存、world、已提交 battle_id；同目录临时文件写入与校验后原子替换，失败保留旧安全档。胜利结果先构造完整下一快照，持久提交成功才公布对应世界补丁；重复交付读已提交ID。退出标题只读最后安全档，不把失败战状态另写为新进度。
- [ ] **Step 4：接薄场景适配器**。采用显式静态 session 持有新模式上下文，未启用时 `_go_battle` 原逻辑完全保留。新模式在触发战斗前取得 world，线索的已解决标记延迟至胜利原子提交；失败重试恢复原 snapshot，不能提前永久解决谜题。胜利只应用原有场景出口和线索结果；不调用旧卡牌奖励模块，不添加 autoload。
- [ ] **Step 5：跑绿并提交**。覆盖两次重复battle_id、失败写档后重试、目录无权限、存档未知字段保留策略（同schema原样保留未识别扩展字段）、旧 progress.json 哨兵文件内容不变；运行 campaign＋all已有组，提交 `feat(rpg): preserve campaign resources and atomic safe saves`。

## Task 6：前三职业真实可玩连战与薄 UI

**Files**
- Create：`scenes/rpg/battle.tscn`, `launcher.tscn`
- Create：`scripts/rpg/ui/battle_presenter.gd`, `battle_view.gd`, `launcher_view.gd`, `data/rpg/presentation.json`
- Create：`tools/rpg/test_ui.gd`, `tools/rpg/capture_rpg.gd`
- Modify：`scripts/scenes/title_scene.gd` 的 `_build_menu` 及新增 `_on_rpg_prototype`

**Interfaces**
- `RpgBattlePresenter.present(state: Dictionary, catalog: RefCounted) -> Dictionary`
- `RpgBattlePresenter.preview(engine: RefCounted, command: Dictionary) -> Dictionary`
- `RpgBattleView.bind(engine: RefCounted, campaign: RefCounted) -> void`
- `RpgBattleView.select_command(kind: String, ability_id: String = "") -> void`；`select_target(actor_id: String) -> void`；`confirm_command() -> void`；`cancel_command() -> void`
- `RpgLauncherView.open(session: Dictionary) -> void`；接线逻辑不得实现新的伤害／概率计算

- [ ] **Step 1：写 UI 契约失败测试**。每位当前行动角色恒有4个技能卡位＋普攻／防御／道具；点击卡只预览，取消不收费；双击确认只提交同一command_id一次，处理中的按钮锁定；低MP／CD／锁定／免疫原因可读。运行 ui，预期失败。
- [ ] **Step 2：实现布局与交互**。沿用 `scripts/ui/theme.gd`、`png_loader.gd`、现有水彩背景与和纸样式，1920×1080；显示各角色真实HP/MP/盾、状态剩余、队列、敌方意图、库存和简明结算日志。全体技能显示全部受影响目标，部分免疫逐目标标注；魔法普攻职业可切中性物理普攻。没有抽牌、弃牌、公共行动点或伪演示。
- [ ] **Step 3：接首测流程**。标题新增“回合制 RPG 试作”；默认固定守卫／剑士／治疗L5，按两场普通战→休息准备点→Boss执行，胜负后只能走 campaign 的真实结果。独立满状态Boss测试入口必须标注“独立测试”，与连战剩余库存不混用。人物职业标签与素材映射分开，未有确认的角色职业配对用职业标签，不改写角色设定；Boss 复用现有棺守素材与名字。
- [ ] **Step 4：验证交互与画面**。运行 ui；在可视Godot中实际操作取消、连点、目标死亡、重试、返回标题、重新进入、窗口缩放，检查完整两普通战＋Boss能由合法输入推进。保存三张截图：命令预览、Boss蓄力、连战结果；记录实际胜负，自动脚本不算真人平衡试玩。
- [ ] **Step 5：提交首个可玩门槛**。前三职业12技能、普通敌人、完整Boss、药物与重试全部走真实模型；提交 `feat(rpg): ship playable three-role combat prototype`。此门槛只用于内部验证，不是六职业任务完成，也不提前推送半成品或开远端PR。

## Task 7：其余职业、分支、编队与装备完成

**Files**
- Modify：`scripts/rpg/effect_resolver.gd`, `command_rules.gd`, `actor_factory.gd`, `catalog.gd`, `campaign.gd`
- Modify：`scripts/rpg/ui/launcher_view.gd`, `battle_presenter.gd`, `data/rpg/classes.json`, `skills.json`, `equipment.json`
- Create：`tools/rpg/test_roster.gd`

**Interfaces**
- Consumes：任务 1–6 的全部既定接口，不改变 Command／Preview 形状
- `RpgCatalog.skill_for(actor: Dictionary, skill_id: String) -> Dictionary`：按等级及分支返回有效技能深复制
- 任务 5 的 `set_party/equip/set_branch` 在休息点开放，战内返回拒绝；战前已确定的技能和装备不能被UI直接改写

- [ ] **Step 1：写游侠／法师／控制失败测试**。标记＋猎杀两行动总系数2.8并消耗标记，无标记1.3；奇袭看“本轮是否已获得行动槽”，不看是否执行成功指令；烟幕20＋0.6ATK。火弹／炎浪／冰矢／灼印逐项核规格，冰缓1轮、群缓2轮；虚弱20%、封缄眩晕＋独立打断、破魔先伤后减MDEF。
- [ ] **Step 2：写控制与分支测试并跑红**。纯控制对所有效果均无效的目标不可确认；清醒但存在可打断蓄力时封缄仍允许有效打断，明确眩晕无效；不可打断脉冲期间封缄不可确认；群体纯控全免疫拒绝、部分可用则只作用合法者。逐项断言规格六职业L6/L9两分支数值，不能混选两个分支，卡位/CD不变。运行 roster，预期失败。
- [ ] **Step 3：完成12技能效果与分支解析**。所有效果复用现有 resolver/status/damage；狩猎分支二选一影响标记持续4/5槽或标记猎杀3.00/3.20，其他分支严格照规格表。不增加第五技能、候选池、随机闪避或额外行动。
- [ ] **Step 4：开放六选三与成长界面**。支持20种无重复三人组合；L1前2技能，L2第三、L3第四；L6选择、L9强化，休息点免费改选。装备仅武器／护甲／饰品三槽且按差值重算，升上限不治疗、降上限钳制；未定义的新装备不自动编造奖励，可用标准装备与测试夹具验证接口。
- [ ] **Step 5：跑绿并提交**。roster＋all已有组通过；截图六人选择及一个分支的实际预览，提交 `feat(rpg): complete six classes and fixed skill progression`。

## Task 8：全组合验证、回归、可审阅推送

**Files**
- Create：`tools/rpg/test_acceptance.gd`, `balance_sweep.gd`, `strategy_policies.gd`
- Create：`docs/rpg/README.md`, `docs/rpg/verification-2026-09-30.md`
- Modify：`tools/rpg/run_checks.py`, `run_tests.gd`, `docs/README.md`, `docs/进度.md`, `AGENTS.md`（仅澄清新可选模式和实际入口，保留历史说明）

**Interfaces**
- `RpgStrategyPolicies.choose(policy_id: String, state: Dictionary, engine: RefCounted) -> Dictionary`：只提交引擎合法命令
- `RpgBalanceSweep.run(class_ids: Array[String], policy_id: String, seed: int, mode: String) -> Dictionary`
- 输出字段固定为 `party, strategy, seed, mode, outcome, rounds_by_battle, knockdowns, hp_remaining, mp_remaining, items_used, decisions, terminal_reason, replay_path`；mode 为 `chain` 或明确独立的 `boss_only`

- [ ] **Step 1：写端到端失败断言**。相同版本/输入/种子重放逐事件一致；连战不私下补资源；初始L5最终200XP；同战果重复提交后场景／谜题／经验均不重复。接受失败也是合法终局，不能把测输样本删除。
- [ ] **Step 2：完成公开策略批测**。全部20组合分别运行直接输出／防御反制／控制爆发三策略、固定种子11/23/47，合计180条连战；独立Boss结果分表标明。策略无可用控制时回退合法普攻；100轮仅是测试失控安全界限，超限报告未完成，不按胜利计。任何数值修改都先改公开数据、补测试并重跑同一组。
- [ ] **Step 3：运行最终代码验证**。`python3 tools/rpg/run_checks.py --suite all`，期望全部PASS、退出0；`python3 tools/rpg/run_checks.py --legacy` 在已校验隔离目录依次执行 `tools/test_v4_battle_rules.gd`、`tools/test_rinne_v3_timing.gd`、`tools/preview/test_act01_approach_preview.gd`。既有失败单独列明，不把“执行过”写成通过；最终代码变动后重跑受影响组。检查 `git diff --check`，确认没有 `.godot/`、缓存、测试存档、生成截图或大额素材误提交。
- [ ] **Step 4：完成可视与报告验收**。实际检查标题→新模式、完整前三职业连战、败北重试、保存恢复、一次其余职业组合及已有探索/3D预览入口。报告分列逻辑测试、自动策略、实际操作结果；保留回合数、伤亡、MP、物品与选择理由。3–5／6–10轮只作诊断，不能把自动策略胜率写成真人体验证据。
- [ ] **Step 5：审核与提交**。做整分支代码审查，特别核对本计划 Review Focus；提交 `test(rpg): verify deterministic combat and playable campaign`。附运行命令、已知限制、截图和未通过项。
- [ ] **Step 6：按已授权范围推送**。六职业24技能及全部约定功能完成、最终验收无新增阻断问题后，才推送独立功能分支并开 draft PR，正文链接规格／计划／验证报告；核验远端确为最终commit，再查看该commit检查状态。报告真实“已推送／CI通过／仍待处理”状态，不自动合并或部署。

## 计划自检与执行门槛

已按规格一至八逐节对应：流程/行动/CD→任务3；属性/装备/分支→任务1/5/7；24技能→任务1/3/7；伤害/状态→任务2/3；敌人/Boss→任务4；跨战/失败/存档→任务5；首测可玩顺序→任务6；日志/重放/20组合验收→任务3/8。Review Focus五项均在所属任务中有明确测试。相邻任务的函数名、字段与返回值以上述接口为准。

此计划没有产品代码修改授权之外的新范围：不新增叙事、不替换默认版本、不恢复已删除旧架构、不覆盖旧存档、不自动合并主分支。数据平衡是可见的一版参数，最终报告必须如实区分规则完成、游戏可玩和体验证据。

**执行前请确认这份计划覆盖预期。** 前三职业仅作内部验证门槛，所有六职业24技能和完整约定范围完成后，才提交最终远端分支及draft PR。不得把文档、三职业切片或尚未完成的部分实现称为交付完成；存在未解释的新失败或尚未实现的规格条目时，必须修复或明确列出阻塞，不能宣称全部完成。
