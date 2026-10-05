# 第一幕连续寺域大地图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在既有五夜主线上交付从上山路到本殿的连续HD2D可行走大地图。
**Architecture:** 共享地图登记与独立几何模块；原入口/会话继续管理剧情，舞台内推进夜次而无需重建世界。旧档显式一次性坐标迁移，战斗正常往返。
**Tech Stack:** Godot4.6.3 Compatibility、GDScript、既有GLB/Blender原材质。
**Spec:** docs/superpowers/specs/2026-10-05-act-one-connected-world-design.md

## Global Constraints
- 不发布、不合并、不强推、不删除原资产或旧档。
- 原52节点/五战/双结局与六身份选三保留，角色真实身高不变。
- user://隔离验证先于所有写档测试；导入/提交使用原共享外部锁。
- 地图连续行走为验收目标，不能用传送与小地图切换代替。

## Review Focus
- 旧战斗中存档被迁移后返回正确区且不会重复奖励。
- 早于剧情进入后区再返回，夜次不误跳、故事不自动消费。
- 大地图边缘、坡接平台和建筑侧门可双向通行且胶囊不落空。
- 横纵镜头和动态景深不把人物脚点/头发、调查提示模糊裁掉。
- 暂停/关闭菜单、连续按键和战斗返场不会传承移动或重触发。

### Task 1: 统一地图登记与存档兼容
**Files:** 新scripts/campaign/act_one_layout.gd；修改chapter_catalog.gd和必要rpg规范化层；新tests。
**Interfaces:** Layout.ID、Layout.bounds()、Layout.night_offset(id)、Layout.region_at(Vector3)、Layout.surface_height(Vector3)、Layout.walk_rects()；Catalog.night提供全图配置，legacy_night保留旧边界迁移依据。
- [ ] 先写并跑失败测试：新世界有地图标志，各夜interaction/anchors变换正确，旧档合法迁移且重复normalize不二次偏移，非法旧/未来布局拒绝。
- [ ] 实现登记与迁移；保存/战斗pending世界均保持事件、奖励与正式schema。
- [ ] 跑campaign state及真实五夜E2E，修正坐标假设而不弱化剧情断言；提交。

### Task 2: 连续几何与庭院表现
**Files:** 新scripts/campaign/act_one_geometry.gd及专属美术辅助，必要GLB派生仅新增目录；新物理/可达性检查。
**Interfaces:** ActOneGeometry.build(config:Dictionary)->Node3D，根名ChapterGeometry；update_visibility(position:Vector3)供舞台调用；不可依赖剧情锁物理。
- [ ] 先写失败验证：原坡道出口不封、前庭有地面、区域之间连通且保留原资产。
- [ ] 构建原山路→山门→前庭，复用原纹理与构件；原地形口开放并加坡/台阶连续碰撞。
- [ ] 真实凛音走第一段并截图/短录屏给父任务，确认无落空/悬浮后补回廊/纸棺庭/镜殿/本殿和返程路。
- [ ] 分块距离裁剪保留物理；检测门口、外沿、碰撞与可见基座；提交。

### Task 3: 世界舞台与镜头整合
**Files:** chapter_stage.gd；新presentation/act_one_camera.gd、act_one_depth.gd；布局/物理集成测试和独立隔离采集runner。
**Interfaces:** 相机follow(actor,delta)、snapshot、restore与旧舞台一致；set_hd2d_experiment允许全部夜次。
- [ ] 先写失败测试：双轴跟随、清晰焦带跟随玩家、故事推进不更换场景/玩家、同地图回溯不触发未授权剧情。
- [ ] 接入连续几何、共同相机、当前地区与下一目标方向；出口仅推进时间，互动点随夜次刷新。
- [ ] 返场/存档可达性按真实射线与胶囊安全校验，战斗保留原位置；菜单输入保护不改。
- [ ] 运行所有正式回归、真实GUI首段与全环路、两结局E2E；记录软件渲染性能局限。

### Task 4: 复审与交付
- [ ] 新上下文复审状态迁移、几何物理、可自由返程与全图镜头。
- [ ] 用红→绿测试修正重大问题；最终各关键区实拍和连续步行短片解码目检。
- [ ] 文档同步唯一入口/地图玩法/实测边界；提交本地分支，向父任务提供commit、真图/短片与未验证内容。

## 实施判定记录
- 第一轮实际可走片已证明原山路/坡道/山门/前庭连续，但大片平板与蓝幕不满足美术验收；独立视觉baseline4.4/10，按同源参考适配继续返修，不能当最终。
- 地图扩至约77米，增加只读寺域总览与当前位置/本夜目标，避免单方向文字在支路处使玩家迷失；它不提供传送、不提前提交剧情，关闭沿用输入释放保护。
- 新地图换夜仍保留原场景入口作为战斗/继续游戏路由；当前场景内只刷新故事，且递增generation使前夜回调失效。
- 独立运行复审发现结案出口距本夜spawn超过6米，错误触发入口门槛导致继续结案卡住；新增t1/送行/镇守三种真实结案点恢复测试，9断言6失败→9通过，已提交检查点恢复先于地理门槛。
- 直接Godot resources导出也须携带完整地图；舞台改用静态WorldGeometry preload，庭院五种外部PNG亦显式preload。原发布烟测改为实际构建连续寺域，不再仅实例化旧单块。
- 本轮未push、合并或重新制作/分发PCK；PCK路径检查的本地源码运行通过不宣称已完成新包验证。原远端admin更新仍须未来发布前单独保留。

## 最终收口（2026-10-05 UTC）

上述任务已按现行用户追加范围完成实现与复核：人物交谈、统一居民画风、全员上身对白取景和前景遮挡修正一并纳入。最终验证事实、此前红色日志的关闭依据、截图来源及未验证边界见[连续寺域与人物交谈：最终收口](../../verification/2026-10-05-act-one-connected-npcs.md)。保留原计划清单作为当时的实施步骤记录；不把模型E2E或真实控制器采集改称完整人工GUI通关。
