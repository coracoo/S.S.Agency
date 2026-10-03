# 第一章「棺女」— 五夜新手章节设计（v1.0, 2026-10-04）

> 样章「逢魔神社 · 夜巡」扩展为完整五夜章节。核心真相：**棺女小夜**——七十年前未婚而亡、
> 因乡俗不得入祖坟、被暂厝于御神木树洞、等待一场再未举行的送葬礼的少女。
> 棺守 = 誓言守到她落葬的老祭主死后执念，附于守棺纸人形。

## 一、五夜结构（每夜 = 委托 + 探索对话 + 一场战斗）

| 夜 | 委托 | 舞台 | 战斗（敌方） | 教学点 |
|---|---|---|---|---|
| 一 | 石钵的倒影 | 参道 test_approach | battle_night1：纸人形×2（低数值） | 移动/E 调查/出牌攻击/灵墨 |
| 二 | 无风之钟 | 回廊 corridor_act | battle.tscn（demo_corridor）：纸人形→残响两波 | 环境槽（引燃/水钵）/火势蔓延 |
| 三 | 纸人抬棺 | 回廊深处 night3_procession（新） | battle_night3（新）：抬棺纸人→残响 | 猛扑应对/尖啸灵气/封印（阵眼+符+灵气≥6） |
| 四 | 棺中镜 | 本殿黄昏 night4_mirror（新） | battle_night4（新）：残响×2→执棺精英 | 护体破除（seal_guard）/执念槽 |
| 五 | 逢魔刻 | 本殿 honden_act | battle_honden（现有 Boss）：棺守·试验棺 | 综合 Boss 战 |

舞台链：test_approach → stage_corridor → stage_night3 → stage_night4 → stage_honden → truth.tscn

## 二、棺女（小夜）设定

- 七十年前山下村子的少女，替亡兄守孝三年；孝期满、婚约既定前夜染时疫病逝。
- 乡俗：未婚而亡者不得入祖坟，须待「聘礼之灯」送到夫家、灵前补全婚礼方可落葬。
- 家人将她暂厝本殿御神木树洞，只等战乱平息。村子迁空，再无人来。
- 老祭主誓言守到她落葬，死后执念附于守棺纸人形——即 Boss「棺守」。
- 她的执念不害人：异象（灯笼倒影/无风钟鸣/棺纹冷光）全是「催促」与「路标」。
- 第五夜真相场景双分支：
  - **送行**（念引路词）：她随灯而去，棺守执念得释。奖励「安魂烛」。
  - **镇守**（立朱印）：强镇异象，但朱印之下仍有轻叩——第二章伏笔。奖励「镇魂钉」。

## 三、对话配置位置

- 探索对话：`config/dialogue.xlsx`（stage 段：corridor_act / night3_procession / night4_mirror / honden_act）
- 结案真相：`config/stage_config.xlsx` case 表（night_patrol nodes 扩展至 16 节点，含棺女现身与双分支结局）
- 棺女台词：speaker=sayo，无半身立绘（portrait 留空，以留白造氛围），color=paper_300

## 四、配置落地

- 战斗：`config/battle_config.xlsx` 新增 3 场（ch1_night1 / ch1_night3 / ch1_night4）→ `data/battles/*.json`
- 舞台/线索：`config/stage_config.xlsx` 新增 2 舞台 + 2 线索 → `data/stages/*.json` + `data/clues/*.json`
- 委托：`data/commissions.json` 5 条（后台「委托仪式」簿可维护）
- 新场景文件：`scenes/v3/battle_night{1,3,4}.tscn` + `scenes/v3/stage_night{3,4}.tscn`（覆写 data 路径）
- 代码修复：battle_canvas.gd 胜利返回路径由硬编码 stage.tscn 改为 NextBattleV4.return_path（多幕章节必改）
- 卡面/背景图：本批次复用现有素材（corridor_battle_test / honden_battle / corridor_walk / honden_dusk），
  美术升级（参道战斗图、棺女立绘）列入后续批次

## 五、新手教学节奏

夜一只给 8 张基础卡（攻击/引燃/鸣钟/水钵/结界符×2/守势/护身符），敌方仅会扑击+尖啸；
夜二全卡池开放环境连锁；夜三引入封印斩杀；夜四引入护体/执念；夜五 Boss 综合考核。
灵气起始 3→4→5→6→4（Boss 战规则沿用 honden_boss）。
