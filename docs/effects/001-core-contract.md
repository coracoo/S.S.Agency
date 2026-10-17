# FX001 共同参数契约 v1

这一提交提供可独立验证的WebGL/Godot参数计算，尚不改变正式战斗渲染入口。后续每种效果分别添加模块、测试与独立提交。

## 输入输出

`effect_parameters.gd.sample`与`effect_parameters.mjs.sample`参数顺序一致：显示clock、当前hand、target、动作elapsed、launch、impact_at、可选真实hit_age、可选固定flight_origin。

调用者保证时间/坐标有限，launch>0、impact_at>launch；生产适配层负责检查。空间为效果父容器像素，时间为秒。默认hit_age=-1表示尚无真实命中；仅显式非负hit_age进入impact阶段。动作到达预计命中点但没有真实事件时输出idle，绝不借视觉产生规则结果。

输出八个共同uniform：time、hand、target、bolt、charge、phase、impact、flash。阶段0/1/2/3分别表示idle/cast/travel/impact。flight阶段使用冻结的flight_origin（未提供时用hand）；命中年龄与角色动作时钟分离。flash沿用已认可WebGL参考的exp(-13×hit_age)。

`web/effects/contract.json`列出统一生命周期挂点；各效果模块分别实现present_action/present_event/update_positions/update_ground_positions/finish_action/cancel_action/clear，模块清单与实现随各自独立提交提供。

## 独立验收

    python3 tools/effects/run_checks.py --core-only
    node tools/effects/test_parameters.mjs

隔离runner先核验Godot实际user目录，再执行测试。独立验收者另构建完全不含fire运行时的最小树验证通过，避免FX001依赖下一提交才可测试。

已验Godot4.6.3与Node；150组确定性跨语言边界样本（包括固定释放点）全部通过，最大坐标差约0.0001298像素，跨语言全部数值字段采用绝对误差<0.0003（不使用相对误差）；各端自身中点断言另用JS<1e-9、GDScript<0.0001。该结果不代表GPUshader逐像素一致或正式游戏全量回归通过。
