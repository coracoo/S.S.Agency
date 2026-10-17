# 第001项：共同契约与完整程序火焰

基线：45a837d6d371f3a41edfcb22cc6f7b768eb43c8d。用户要求先列计划，再逐项完成、验收、归档和提交。

## 边界

首项仅接入 firebolt 的掌心、发射和真实命中；其他技能和持续燃烧仍由现有生产渲染器负责。保持最新跳跃残留修正、人物原图、模型、RNG、存档与动作窗口。不会拿12秒研究样片的长蓄力覆盖正式时序。

## 结构

- scripts/effects/core：与WebGL共用的确定性参数采样，时间以秒、坐标为效果父容器像素；输入launch/impact/duration，输出time/hand/target/bolt/charge/phase/impact/flash。
- scripts/effects/fire：已认可程序shader及火焰生命周期；动作结束只释放施法/飞行，真实命中后的1.1秒余烬独立存活。取消、死亡、清场立即释放相关视觉。
- scripts/rpg/ui/procedural_battle_effects.gd：继承旧生产渲染器，路由firebolt；不更改旧文件，其他效果走原接口。项目开关可回退，进行中的动作不混用新旧渲染。
- web/effects：同参数采样JavaScript与原WebGL火焰公式，供逐帧对比及后续模块扩展。

## 验收与实施

1. 先写并运行失败测试：动作时序、命中事件门禁、重复/伪造事件、取消/死亡/清场、尾焰与收招解耦。
2. 实现纯参数契约和WebGL镜像，接入完整shader，提供回退路由。
3. 运行专项、既有RPG全量隔离回归，保留所有失败及环境限制。
4. 真实Compatibility图形运行，生成同轴预览与逐帧证据；不以headless代替图形验收。
5. 源码、README、报告与视频归档后由协调者发布独立提交。本执行分支不推送、不触发Actions。
