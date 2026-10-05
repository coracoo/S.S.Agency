# 退役角色素材原件

本目录基于 main `46c37bbce0e5609e5e781f63114d9b2c450794d8` 整理。

- 共迁移 210 个 Git 跟踪文件，其中 103 张 PNG；PNG、JSON、`.import` 全部保持迁移前原字节。
- 对照 `manifest.json` 的 `from`、`to`、SHA256 和 Git blob 可逐项恢复。Git 历史没有重写；推荐用本归档提交的 `git revert` 撤销整次搬迁。
- 正式七形态高清动作帧、当前六敌图、NPC 与半身素材保留原位。仍被正式3D参道源场景引用的 `assets/chars/anims/rinne_idle_f1.png` 及导入文件也保留原位。
- 归档清单内部的旧 URI 保留。开发环境通过 `scripts/characters/legacy_asset_paths.gd` 兼容读取；原路径有效时永远优先使用原路径，不替换正式素材。
- `old/.gdignore` 阻止 Godot 导入旧原件，正式导出配置及 PCK 审核排除 `old/`。历史预览从源码目录读取 PNG 原字节，不依赖旧导入缓存。
- 本次不合入其他开发分支，不修改玩法、动画、人物尺寸或玩家存档。尚未合入 main 的骨架分支可由本地另行合并。

验证：`python3 -m unittest discover -s tools/characters -p 'test_*.py'`；`python3 tools/characters/run_checks.py --godot <Godot4.7.2> --suite all`。归档专项运行 `tools/campaign/run_act_one_checks.py --script res://tools/characters/test_legacy_archive.gd`。

## 本次验证结果与边界

官方 Godot 4.7.2：归档专项10断言、历史定义/动画/世界/分层/纹理共享/场景融合/高清展示通过；Python角色11项、发布工具16项通过；主线状态741、双形态53、主线表现76断言通过。RPG旧角色时序14断言通过。

历史角色总测仍有9个身高/脚锚断言失败，未改基线用同一引擎可逐项复现：旧断言直接比较 manifest 身高/锚点，但当前 CharacterStature 已使用身体参考高与新脚点。本次不更改这些历史断言或正式人物表现。旧3D预览还保留一条“默认入口仍是原版标题”的过期断言；正式入口已是 campaign 标题。

Godot 4.7.2 的实际导出PCK已从空项目根挂载检查，260个条目中没有old文件，也没有210个归档原件对应的旧ctex缓存泄漏。本次只交付源码归档分支，不交付可独立运行发行包：现有发布追加/审包工具仅支持PCK v2/v3，4.7.2输出v4，仍需单独升级工具才能追加完整动态原PNG；没有把这次排除检查当成4.7.2发行认证。
