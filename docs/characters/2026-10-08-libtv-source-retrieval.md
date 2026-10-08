# LibTV 历史动作视频取回

2026-10-08，按用户指示，从 LibTV 的 **SSA逢魔退治帖** 工作区（10569123）查找此前制作的角色视频。通过官方 CLI 查询节点和下载，未触发新生成。

**结果：84个视频节点均已下载，84个文件，共106,868,928字节（约101.9 MiB），失败0。** 没有转码、抠图、改写人物运行资源或执行游戏测试。

本地目录：`J:/godot/S.S.Agency/build/libtv/source-retrieval-20261008/`。

**后续更新：优先使用会员原链。** 确认账号会员有效后，已用官方CLI的`--vip --without-ai-watermark`另取84份原链文件到上述目录的`member-original/`，共320,227,563字节（约305.4 MiB）。84份SHA256全部与节点URL资源名一致，失败0。首次下载的106,868,928字节版本保留作编码对照，不再作为重抠的首选输入；不能将两版文件的字节混写成同一来源。`member-original/guard-jump/`另有首次诊断补取的重复样本，84份唯一节点原链以该目录索引为准。

| 批次 | 画布 | 视频数 |
|---|---|---:|
| P0 | [rinne_P0_凛音首批](https://www.liblib.tv/canvas?projectId=23b7a6a214ba422fa1b4ef14851e4d34) | 6 |
| P1 | [others_P1_其余角色动作_20261006](https://www.liblib.tv/canvas?projectId=72d7bd362e6e4b4a87067fd6cccd70d8) | 22 |
| P2 | [expanded_P2_跑互动跳物品战败_20261006](https://www.liblib.tv/canvas?projectId=4ecf7ae1c282451da033ab50270728d1) | 36 |
| P3 | [compact_P3_六形态跳跃_20261006](https://www.liblib.tv/canvas?projectId=31b008e7dd724a25b8fbb87d6689f7d3) | 7 |
| P4 | [revision_P4_焰华术节奏修正_20261007](https://www.liblib.tv/canvas?projectId=5ce630568f9545dabc243c959d8ccfd3) | 13 |

按节点名初步归类：凛音12、薄荷13、岑照11、焰华剑11、焰华术19、苏合8、清明8；另2条为过场视频和通用名称节点。这是候选分类，不是生产采用数量。

历史模型记录为Minimax H3 5条、Seedance 2.0 Fast VIP 23条、Seedance 2.0 VIP 56条。它们作为旧素材原样保存；不因此改变后续新视频使用H3/768P的约定。

每个节点目录包含视频和`node.json`，保留提示词、模型参数、参考输入、任务ID与输出链接。`download-manifest.json`记录下载文件大小和SHA256，`source-index.csv`提供角色/动作候选索引。目录带`.gdignore`，不加入Godot导入或发布包。

原先“本地只有历史凛音试片、未取回其余形态源视频”的限制现已推进：七形态相关平台视频已在本地。仍需核对选用版本、截取时间码、抽帧/裁切/缩放与运行图集的逐帧关系，不能仅按同名或最新版本自动替换生产PNG。此次未证明具体视频由哪个助手创建，也未宣称所有运行帧的源链已经完全还原。
