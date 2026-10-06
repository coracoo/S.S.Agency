# 七章连续主线

## 内容与入口

唯一入口仍为 `scenes/campaign/title.tscn`，开始、继续、退出。第一章保留既有五夜连续寺域和送行/镇守；结案后可下山进入无眠街。后续六章共用 `scenes/campaign/saga.tscn` 的呈现层，每章加载独立地区，完整尾声后进入 `saga_ending.tscn`。

| 章节 | 地区与推进重点 |
|---|---|
| 一·棺女 | 连续参道/寺域、五夜夜巡、三步守灯、送行或镇守 |
| 二·无眠街 | 客栈、灯铺、水口和染坊；护送、回收旧芯、借声客、寄信与夜市救援 |
| 三·逆水渡 | 主码头、西仓与第二岸；实际撤离、护仓/回收、背岸将和修渡 |
| 四·镜中双影 | 镜坊、抛光间、镜廊与修阵室；邱安早救/迟救、合面镜和旧录音 |
| 五·借命灯 | 医馆、病房、药库与静室；稳灯/隔离、家属接回、百手灯母和真实唤醒状态 |
| 六·百夜无更 | 山门、本殿、接应处、码头与后巷；回执、旧案补办、分段镜结与居民撤离 |
| 七·天明之前 | 镜厅、刻名板与外口；三阶段战斗、四种方案、相应后日谈及六人尾声 |

后六章137场、1567句批准对白由确定性导出工具读取评审原稿。主线、补救、闲谈、交易、战前/胜利后及真实战斗事件提示分别登记，不将互斥台词拼在一起。任务工具与物证不要求购买。缺少救援不会被自动写成已经安全，第一章已经送行的小夜不会在第六章重新出现。

## 操作与可玩循环

- WASD行走，E靠近调查/对白推进，M地区地图，Esc行旅手帖
- 地图只显示路线、实际位置与调查目标；不能通过地图传送
- 实地调查→原文对白/处理选择→独立RPG遭遇→原战前位置返场→战后对白→保存责任与物证
- 歇脚处恢复六人；行旅补给用银钱购买已有道具；队伍、装备、技能分支与道具仍使用现有菜单
- 已开启遭遇可以暂缓，保留选择后走到休息/补给点；不能借暂缓预先发救援或战利品
- 败北可同条件重试，或回到战前资源整备。终战三阶段使用C7-R04的对应失败短聊；已赢阶段不重复发奖励
- 出口连接已开放章节，保留往返进度；可返回旧地补救仍可处理的事项

六身份任意三人出战，固定24技能。焰华剑/术仍是同一身份，HP/MP/技能冷却归属沿用原规则。新增15敌方定义、26遭遇；机制与验证见[后六章战斗](saga-battles.md)。

## 保存、旧档和审查修复

正式槽保持 `user://campaign_v1/slot_01.json`、schema2与原campaign_id，避免破坏现有五夜档。旧局继续原五夜；只有从已提交的第一章结案选择下山时，才新增版本化 `saga` 子记录。旧卡牌、RPG试玩和参道试玩档不迁移、不覆盖。

后章记录包含完成事件、具体选项、每章游标、实际战斗来源、银钱交易与导航事务。导航包含未完成正文的绕路，因此能区分“先修渡/先救人”与离章，不能把稳灯分支游标改到药库之后。条件战斗按事件当时状态重放；稍早选择暂缓、后来再次作战的场次，不会把未来胜利错误归给旧记录。

所有位置/对白/选择/战斗/购物/跨章提交都核对已读持久基线，再验证临时文件并原子替换。失败保留原档和原资源；未知版本、损坏记录、非法游标/世界镜像/胜利来源明确报错。结局二次确认可以取消；确认后的中断继续恢复原方案。四结局只有在相应最后尾声提交后才算完整结束。

## 美术边界

原六人七形态、原六敌PNG和已有NPC不改字节。后六章复用原寺域纹理、自然树石和曲瓦檐，并有独立布局/地区道具。新增居民全身静态图与半身图由独立NPC manifest登记；新增敌图由独立敌方manifest登记。图集使用AtlasTexture区域与局部脚锚，原稿保留，静态原画不冒称动画。

新原图使用FileAccess路径读取，因此发布后处理必须追加并校验原PNG字节，不能只依赖import后的纹理。完整发布检查核齐23名新居民与15类新敌。

## 可复现验证

目标Godot为4.7.2 stable。所有写档检查首先核验实际隔离的user目录。

```sh
python3 tools/rpg/run_checks.py --suite all
python3 tools/campaign/run_checks.py
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_runtime.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_geometry.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_battles.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_periodic_guard.gd
python3 tools/campaign/run_act_one_checks.py --script res://tools/campaign/test_saga_reflection_preview.gd
python3 tools/campaign/run_saga_checks.py --godot /path/to/godot-4.7.2 --mode all --output-dir /outside/repo/verification
python3 -m unittest discover -s tools/campaign -p 'test_*.py'
```

统一七章入口输出 `saga-verification.json`。state组用战果夹具专测持久事务；real组从第一夜开始使用合法战斗指令，覆盖四结局与镇守/隔离/迟送行路线，并保存战斗重放。章间、终战战前及已确认终局方案另由全新Godot进程续读，核验路由、ID、种子与资源。

图形采集、截图目检、人工按键验证另记，模型通关不等于人工GUI全通。原历史试玩测试仍可能报告缺失前景PNG；需区别于当前正式场景错误。最终结果以对应提交的检查记录为准，文档中的命令和范围不替代实际运行证据。

## 发布

发布工具使用官方4.7.2，支持其PCK v4。包内保留实际场景/数据/素材闭包，原PNG追加后逐hash验证，测试工具、截图、开发证据和未登记原稿不随包发布。先完成内容，再刷新并提交导出配置；从干净提交运行完整构建，方能将源码ZIP、patch与PCK绑定到同一提交。

```sh
python3 tools/campaign/build_release.py --godot /path/to/godot-4.7.2 --output-dir /outside/repo/release --import-lock /outside/repo/godot-import.lock --source
```

`--skip-e2e`仅是开发检查点，不是正式七章包验收。最终报告必须同时核验首章与后六章E2E。未安装平台导出模板时，提供由同版官方引擎启动的PCK，不把它写成独立Windows EXE。
