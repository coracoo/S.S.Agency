# 七章连续主线实施计划

各段先建立回归用例，再实施并验证。下列复选框记录实际完成范围，不代替最终版本的验收报告。

**Goal:** 将批准七章剧情接成可探索、可战斗、可保存的完整游戏。
**Architecture:** 保留第一章；后六章以场次数据驱动地区与事件，复用正式RPG模型。严格验证saga扩展，所有状态变更走模型事务。
**Tech Stack:** Godot 4.7.2、GDScript、JSON、Python隔离测试。
**Spec:** docs/superpowers/specs/2026-10-05-seven-chapter-campaign-design.md

## Global Constraints
- 不覆盖角色素材、既有玩家档和用户最新更改；不force push。
- 所有写档测试必须核验隔离user目录，导入使用仓库外godot-import.lock。
- 新增技术说明及复杂逻辑注释中文；未验证不报通过。

## Review Focus
- 第一章已结案旧档向下山入口转换，损坏/未知saga版本拒绝。
- 支线暂缓后离章、回访救援及终章可用人手不会凭空出现。
- 战斗失败/退出/重复战果保持原资源和一次性奖励。
- 对话选择、中途保存、关闭菜单/地图后输入不会穿透或卡死。
- 四结局前置、送行不复生、镇守未结责任不会被章节切换丢掉。

## 任务
- [x] 1. 基线导入与既有门禁，保留失败清单；确认4.7.2。
- [x] 2. 剧情数据：后六章137场批准对白、明确条件/选择/战斗分界、事件图验证；Python内容测试RED→GREEN。
- [x] 3. 世界：六个有区别的3D地区、锚点/行走/碰撞/地图；几何与运行测试RED→GREEN。
- [x] 4. 模型：Saga目录、世界与状态校验、旧结案继续、事件与选择、遭遇/奖励/成长、保存恢复；隔离Godot测试RED→GREEN。
- [x] 5. 战斗：章内遭遇与六章Boss、实际机制/预告/反馈、真实指令胜败重试测试RED→GREEN。
- [x] 6. 呈现：实地交互、分支对白、目标/手帖、休息/商店/整备、跨章与终章，图形检查。
- [ ] 7. 全程验收：旧门禁、新游戏两首章分支、后六章全主线、支线回补、四结局、迁移/损坏/重复提交。
- [ ] 8. 独立审查、修复、发布依赖核验，fresh-fetch main后无损发布已测提交并核对远端SHA与CI。

## 接口
数据 `data/campaign/saga.json`: schema_version=1, chapters数组，每章{id:2..7,title,entry,scenes}；scene{id,title,location,kind,lines,choices,next,requires,effects,encounter_id}。lines为{speaker,text,when?}，choices为{id,text,next,effects,requires?}；when/requires都是条件字典，键为全局标记，值为期望标量。
世界 `scripts/campaign/saga_world.gd`: static bounds(chapter:int)->Dictionary, anchors(chapter:int)->Dictionary, build(chapter:int)->Node3D；anchors位置是[x,y,z]，场次location引用锚点键。
后续state.saga={version:1,chapter:int,scene:String,completed:Array,choices:Dictionary,flags:Dictionary,ending:String}；ChapterCatalog按world.night>=6路由至SagaCatalog，world.night=chapter+4。后续地区共用`res://scenes/campaign/saga.tscn`，当前章从会话读取。

## 执行记录
- 基线：830cf52c34b4bef8675f6a94a58cdd498678442f。独立checkout分支feat/seven-chapter-campaign。
- 用户明确自主执行，免逐步设计/实施确认；保留审查与权限边界。

## 2026-10-05 已验证检查点
- 原RPG10组、道具135；首章状态741与双形态53通过。
- 六地区完整物理2779项通过，含真实胶囊实走；图形检查另行记录。
- 后六章26遭遇真实战斗全部胜利；160阵容组合均胜，周期门禁修复后重跑受影响40项。
- 独立审查复现并修复迟救入口、未来战果误写旧事件、重复选择续读、购买入口和周期伤害/反射提示。
- 七章模型真实路线与开发PCK四结局/镇守路线通过；最终新美术和干净提交包仍需统一重建。
- 新增居民24名、敌方15类已完成原图登记和实景检查；最终干净提交包仍须单独核验。

## 2026-10-06 冻结候选
24名独立NPC、15类专属敌图与运行时接线已完成；原图字节保护、图集脚锚、九场敌图实景与最终干净源码包继续按发布报告核验。该报告由构建工具绑定实际提交，不能用本计划的复选框替代验收结论。
