# 第二至七章战斗

## 数据与兼容边界

- `data/rpg/saga_enemies.json`、`saga_encounters.json`独立追加15个敌方定义、26个遭遇；不改六原敌、角色PNG或XLSX管理字段。
- 新敌的`sprite_id`保留原六图兼容索引；正式后章战斗优先读取`assets/chars/enemies/saga/asset_manifest.json`的15类独立静态原画。原六敌图仍供原遭遇使用，独立静态立绘不冒称Boss动画。
- 固定六身份自由选三，24技能与焰华双形态资源归属不变。机制只存在敌方`saga`战斗快照中，恢复时校验整数、归属、版本与字段。
- 普通遭遇170经验，Boss400，终局分支450；奖励必须由正式主线会话的胜利事务提交，战斗规则不直接发剧情奖励。

## 可执行机制

1. 借声客：下一轮回放上一轮最后行动的类别（物理、术法、防守、补给、控制），并非复制玩家身份或整套技能。防守与补给会实际生效，攻击回放可打断；低血末段追加扑灯高伤单击，可援护、嘲讽或防守应对。
2. 背岸将：举旗后公开补位指令；固定盾击或眩晕可中止。未拦住会让已散纸兵以45%生命补位。本体倒下后纸兵因号令消失而散去，不要求先杀光杂兵。
3. 合面镜：按轮次切换物反、术反、脱面。对应伤害降低80%并反射该次结算伤害的两倍；第三轮通用窗口增伤25%。纯物理队可以防守等窗口。主镜第一阶段沿用已教学规则。
4. 百手灯母：灯印、吸取、散罩三步。吸取可打断，成功时按实际损失生命的一半补血，并获得灯罩；护盾降低实际吸取收益。散罩步提供25%伤害窗口。
5. 无更巡守：左右锁片未隔离时胸牌不受伤。胸牌明确预告将回补哪一侧，打断能阻止；未拦住的锁片以35%生命接回，单战至多两次。两侧隔离后可击破胸牌。门禁同样阻挡已存在的灼烧；每个行动槽按当前锁片重算，保护期间状态次数仍照常消耗。
6. 终战：C7-05护面、C7-06执灯纸躯、所选C7-10/11/12/13收尾分别为真实遭遇，是否允许换队与资源承接由正式会话决定。第三阶段要求依次压住出口反冲、中段分流、主镜余压；前置目标尚在时后层伤害为零，不能只削空核心跳过目标。四方案的器具动作与外侧交接由对应批准场次承接。

## 意图与事件接口

- 敌方`intent.preview.hint`是当前真实策略提示，伤害预览与实际行动共用解析器。
- `saga_phase`、`saga_reflected`、`saga_cancelled`、`saga_lamp_drained`、`saga_anchor_repaired`、`saga_support_returned`、`saga_support_dismissed`、`saga_objective_blocked`、`saga_objective_completed`附`payload.text`。
- `saga_reflected`同时提供`normal`、`critical_damage`返伤量、`normal_hp_loss`、`critical_hp_loss`穿当前护盾后的生命损失和`defeat_normal`、`defeat_critical`致死风险。预测使用角色深副本，实际反射只扣一次；UI不得另造伤害公式。
- 成功打断沿用`charge_interrupted`；不得把“打断成功”“补位成功”两组对白同时顺播。
- 借声客专用事件为`saga_voice_replay`（`memory`类别）、`saga_voice_repeated`、`saga_voice_guarded`、`saga_voice_exploited`，均由真实换轮/玩家行动判定。
- 预览副本剥离不可写的`event_log`和`command_log`，其余字段仍全部深复制，包括库存、行动token、队列与RNG字段。纯度回归比较完整原快照，不能为性能牺牲只读边界。

## 隔离验证

使用当前Godot4.7.2路径并由隔离入口先确认实际`user://`：

```sh
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_battles.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_party_matrix.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_replay.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_periodic_guard.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_reflection_preview.gd
python3 tools/rpg/run_checks.py --suite all
```

`test_saga_battles.gd`覆盖26遭遇的真实行动胜利、六章机制、目标前置、快照往返、损坏状态与完整预览纯度。测试专用`saga_battle_strategy.gd`只使用公开预览挑选合法指令，不能改生命、随机数、行动机会或胜负。

矩阵按六职业20组合，逐一验证七Boss遭遇与收尾目标链；同遭遇等级、标准装、六恢复药/四法力药/三复苏药/四净化粉是公开的准备条件，不等同零消耗或任意策略必胜。`SAGA_ENCOUNTER`可选单一遭遇，`SAGA_MATRIX_START`支持跳过已保存证据的前缀继续。

2026-10-05已完成26遭遇真实胜利（211断言、失败0），八组Boss/目标链的内存与JSON逐事件重放（16断言、失败0），RPG十组回归（失败0）及道具135断言。历史预览场景仍报告缺少`test_approach_fg2.png`、`corridor_act_fg2.png`警告。160项队伍矩阵以30+122+8条不中断已完成证据的分段运行确认160个唯一组合全部获胜。周期门禁审查修复后，受影响的巡守与收尾目标链40组合均重新跑过并全胜，与未受影响的120组合组成最终160个唯一组合全胜证据。修复后26实战再跑仍211断言通过，新增周期门禁92断言与反射预览25断言通过。周期回归覆盖合法灼印、巡守真实接回锁片后旧灼烧失效、状态照常到期及JSON逐事件重放；反射回归覆盖穿盾普通存活/暴击KO与足量护盾两种情况。模型回归不冒充人工图形全通。
