# 七章新增敌方静态立绘

本目录覆盖 `data/rpg/saga_enemies.json` 的全部 15 个敌方 ID，共 8 张内置 image_gen 生成的原始透明 PNG。现有六敌、玩家七形态和 NPC 素材不变。

## 运行时合同

- 读取 `asset_manifest.json` 的 `enemies[enemy_id]`。
- `sheet` 是原始整张图的 res URI；按 `region: [x, y, width, height]` 创建 AtlasTexture。不要按图片中心猜测分割线，也不要重新裁切或覆盖原稿。
- `anchor` 为 region 内的局部底部锚点，`content_height_px` 为 alpha > 5 的可见主体高度。按所需战场身高统一缩放。
- `content_bounds_px` 是 alpha > 5 的局部内容包围盒 `[left, top, right, bottom]`，右、下边界不包含在内。
- `facing` 表示总体面向。镜具/锁片保持轻微向右的器物视角，不强行添加人脸。
- 每个 ID 只有一幅静态立绘；没有逐帧动画，也不能据此宣称已实现角色动作动画。

所有图均保留生成器输出的原始 PNG 字节及 SHA-256。提示词和生成来源见 `generation_provenance.json`；检查结果见 `art_qa.json`。`provenance/` 保留未采用首稿，以 `.gdignore` 排除运行时导入。

## 与正文对应

借声客为无五官的叠门纸身；背岸将为旧令驱动的锈甲；合面镜为双影合面镜具；百手灯母为托空碗的多臂灯具；无更巡守胸前带发令牌并持联动扣。镜屑侍以镜屑身体捧镜盘；沈烛舟纸躯延续深蓝金纹衣装、半束黑发和执灯身份，但体现纸身及关节，不替换活人/录影 NPC。

左右锁片分别为方孔与菱形铜锁。终章三个反冲节点分别为堵门镜框、三路分流管汇、破裂主镜核心，不复用一般人形纸妖。
