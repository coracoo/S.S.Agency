# 验收矩阵 E 项操作清单：存档迁移矩阵（交给测试执行者）

2026-10-13。对应[试玩反馈验收矩阵](2026-10-08-playtest-remediation.md) §5 E 项。**前置：A–D 项已通过，代码为 `main` ≥ `4708878`。** 隔离、外部锁与证据目录约定同 [A项操作清单](2026-10-11-parse-check-runbook.md)。

本项验收角色专属迁移（build1→build2）。规则要点：合法旧档先严格校验 → 原字节备份 → 生成 v2 候选（外人物卡卸下但收藏保留、焰华剑卡四张换本人别名、新基础卡按拥有数取最大值补入）→ 派生新属性 → 当前 HP/MP 只向新上限截断（不回满、不复活）→ 原子提交。备份后缀 `.schema3-role-loadout-v1-<hash12>.bak`。剧情、战果、银钱、商人账本、机关操作与奖励一律不重发。

## 第 1 步 合法迁移矩阵

对下列每种合法旧档在**已核验的隔离 user 目录**中各执行一次迁移（先复制字节，不直接动夹具原档）：

| 场景 | 必查预期 |
|---|---|
| schema2 旧档 | 先按原规则校验、原字节备份，再投影为当前构筑 |
| schema3/progression 1、2、3 | 各代扩展按序投影 |
| schema3/progression 4 + build1 | 角色专属迁移触发，备份后缀为 `.schema3-role-loadout-v1-*` |
| 首章进行 / 后章进行 | 两段落各至少一例 |
| 安全探索 / 战前待战 | pending battle 重建读当前数值，不重发已胜奖励 |
| 焰华法形解锁前 / 后 | 解锁前只迁移剑式备用组，不解锁法形 |
| 装配含外人物卡 | 外人物主动/被动卸下，收藏数量保留 |
| 商人已购卡 | 已收录卡保留收藏；商人账本与库存不变 |
| 受伤 / 缺蓝 / 倒地 | HP/MP 只截断不回满，倒地状态不变 |
| 空卡组 / 未装配 | 按初始专属候选装配，不报错 |

每次迁移后核对：备份字节与原件逐字节一致；机关历史、账本、已结算战果、剧情 flags 未变；新卡按拥有数取最大值补入且不重复；继续读档两次只迁移一次。

## 第 2 步 拒绝与保护路径

以下每种都必须**不覆盖原档**并给出明确错误：

- 损坏字段、未知 schema/progression/build 版本、错误身份
- 混合非法卡（模型层直接提交 build1 也拒绝）
- 备份写入失败/冲突、原档在迁移期间被并发改变、最终写入失败
- 迁移派生失败（`upgrade_role_builds` 返回错误时整体拒绝）

## 第 3 步 既有回归重跑

```sh
# 事务/夹具（含跨进程续档）
python tools/campaign/run_saga_checks.py --mode all --output-dir <证据目录>

# 商人/机关迁移既有断言
python tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_merchant_migration.gd --output-dir <证据>
python tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_mechanism_migration.gd --output-dir <证据>

# 存档校验成本基准（对比商人账本加入前后的校验开销，只读不写）
# 经 run_act_one_checks.py --script res://tools/campaign/benchmark_save_validation.gd 运行，归档耗时数据
```

既有夹具：`tools/campaign/fixtures/loadout-schema2-chapter7.json`。新迁移场景的夹具由改造方按第 1 步矩阵补齐；执行者不得手改夹具字节来凑通过。

## 第 4 步 发布包依赖

- 正式发布闭包必须包含 `legacy_loadout_rules.gd` 与 `data/rpg/loadouts_legacy_v1.json`（静态 preload 已被 `loadout_rules.gd` 引用，发布器 formal_dependencies 收录 `data/rpg/*.json`）。
- 包内迁移同样要在隔离目录验证（复制字节后迁移，不碰真实玩家档）。
- 新回放与旧指纹（`SKILL_DERIVATION_VERSION` ≤2）明确区分，不得互认。

## 通过标准（全部满足才进 F 项）

- [ ] 第 1 步 11 类场景全部按预期迁移，核对项全过
- [ ] 第 2 步 4 类保护路径全部不覆盖原档
- [ ] 第 3 步回归全绿，校验成本数据归档
- [ ] 第 4 步发布依赖确认（或与发布认证一并执行并记录）

任何失败：原档字节与证据归档，回报改造方；修复后从第 1 步重跑。
