#!/usr/bin/env python3
"""从权威技能/专精数据生成七形态完整目录和逐招美术委托；不修改运行时数值。"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/characters'
FORMS = {
 'rinne_swordsman': ('凛音·剑士', 'rinne', '木剑挥痕与冷青灵光，强调精确破绽'),
 'mint_ranger': ('薄荷·游侠', 'mint', '翠绿追踪记号、单枚弹丸的短轨迹、灰绿烟雾'),
 'guard_guard': ('岑照·守卫', 'guard', '铜金盾面冲击、厚重护阵、短促压制波'),
 'homura_swordsman': ('焰华·剑形', 'homura_sword', '橙红刃缘火星；只有触发灼烧才出现持续火种'),
 'homura_mage': ('焰华·法形', 'homura_mage', '赤金火焰与蓝白冰晶有明确轮廓，冰火转换可读'),
 'healer_healer': ('苏合·治疗', 'healer', '铃声带起青白生命光、柔和光纹、清晰护盾边缘'),
 'controller_controller': ('清明·控制', 'controller', '扇面与卷轴引出紫蓝符纹、束缚墨纹、破印时清晰碎裂')
}
# 四阶段均为演员动作/附着点语义；持续秒数留待动作素材批准后定标，不改变结算时钟。
BRIEFS = {
 'cover': ('侧身举盾朝被护队友', '从盾缘伸出一道保护联系', '敌方单体直击到来时在守卫盾前接击', '守卫短退后站稳', '无攻击弹道；联系守卫与一名其他队友', '单友绑定，命中转移落点在守卫', 'status_applied(id=cover)后显示绑定；cover_redirected时收束一次；下次守卫行动或绑定倒地即移除'),
 'shield_bash': ('重心降低，盾收于胸侧', '向单敌作短距离盾冲', '盾面接触处厚重撞击，伤害之后显示打断/虚弱', '收盾回到保护姿态', '极短盾冲轨迹，不横穿其他敌人', '单敌胸前扁平冲击', 'charge_interrupted才画蓄力破碎；weaken成功才画压制纹，免疫不画眩晕星'),
 'iron_wall': ('双足稳住，盾正面立起', '盾前展开厚护壁', '无攻击命中；护盾落在自身', '收势时护壁缩为状态边缘', '无远程弹道', '自身轮廓护壁', 'shield_applied显示新剩余量；整阵净化按实际status_removed逐项消散'),
 'taunt': ('举盾敲击并朝敌人挑衅', '短促声纹指向目标', '目标出现朝守卫的敌意连线', '守卫保持戒备', '不造成伤害的短声纹传递', '单敌头顶/脚下小型指向标记', 'taunt只改变适用单体选择；镇锋仅有盾时追加虚弱，不画全敌被强迫转向'),
 'heavy_slash': ('沉肩蓄剑，刃侧收紧', '向单敌落下厚重斜斩', '命中时一道主剑痕与目标受击反馈', '剑锋抽回并复位', '近战剑弧，无飞行法术', '单敌斜向狭长切痕', '单次物理伤害，不增加第二次伤害数字'),
 'armor_break': ('压低剑尖瞄准防护缝隙', '短而锐的突斩', '伤害后碎甲纹裂开', '拔剑收回', '短刺击/切线', '单敌护甲位置小范围碎裂', 'armor_break成功后保留减防提示'),
 'sweep': ('肩腰转动，剑横向拉开', '横扫弧依次覆盖全部存活敌人', '每个目标独立受击；条件附效各自显示', '转身止势回到原位', '可用连续横弧；不能表现站位闪避/近远范围', '规则是全体敌人，不是几何锥体筛选', '全体存活敌人各自按实际damage事件受击'),
 'battle_spirit': ('收剑凝神，胸口短促吸气', '向自身聚拢战意光', '无攻击命中；力量纹附着自身', '转为进攻待机', '无弹道', '自身上半身与武器附着', '战意只增强直接伤害，不提高灼烧快照'),
 'mark': ('抬起同一把Y形弹弓稳定瞄准，轻拉皮筋', '松开皮筋送出一枚带追踪光记的弹丸', '无伤害爆炸；追踪记号落定', '皮筋回弹后放松握持，仍持同一把弹弓', '一枚弹丸的短弹道与细小追踪光记', '单敌单点记号', 'mark成功才常驻记号；猎杀消耗时收拢，不能误画为持续伤害'),
 'hunt': ('锁定标记处，拉满同一把Y形弹弓的皮筋', '释放一枚集中劲力的弹丸', '单次集中撞击；已有标记时印记随命中破碎', '皮筋回弹后短停，再放低同一把弹弓', '单枚弹丸明确从弹弓弹道飞向目标', '单敌集中撞击', 'status_removed(reason=skill_consumed)或actor_defeated时清理记号；回收mp_restored只在自身显示一次小回流'),
 'ambush': ('压低身形，快速拉开同一把弹弓的皮筋', '迅速松开皮筋，抢射一枚弹丸', '快速点状命中后附追踪标记', '迅速退回警戒姿态', '比猎杀更短促的单枚弹丸轨迹', '单敌精准一点', '先手条件影响同一击强度；L3追踪标记在伤害后显示，不能伪装额外行动'),
 'smoke_screen': ('身形压低，以空闲手短促掩护示意；同一把弹弓保持原有握持', '灰绿烟幕包住自身', '无敌方命中；自身护盾成形', '从烟中恢复待机轮廓', '自身近地扩散，不遮住全屏', '自身局部烟团和盾边缘', '规则是护盾而非闪避/隐身；伏弓战意图标保留至下一次出手结束'),
 'firebolt': ('空手在掌前凝起紧凑火核', '向单敌推出一枚火弹', '单次紧凑火爆，不附送灼烧', '手臂收回，火星迅速熄灭', '单弹道，从施法点到目标', '单敌小圆火爆', '续焰只读取已有burn加强伤害，不重新施加或消耗burn'),
 'flame_wave': ('双手引火，火沿前方铺开', '一股低平火浪扫过全敌', '各目标独立火焰冲击', '火浪退去，施法者回稳', '横向波前，可共享浪头与各目标命中特效', '全体敌人，各自独立命中位置', '续燎仅已有burn者发生status_applied；未点燃者不得留下火种；更强灼烧保持原样'),
 'ice_arrow': ('以空手凝聚细长冰晶矢形', '射出蓝白冰矢', '冰晶单点破碎，霜纹随后落下', '散去手中余霜', '单枚细长冰矢', '单敌尖锐冰裂', 'slow表示未来轮序，不是当场冻结跳过行动；熄焰先伤害，再出现虚弱及火种熄灭'),
 'burn_brand': ('以空手指尖划出火印', '将火印压向目标', '小火伤后符印灼亮', '收掌，保留目标火种', '短符印投射', '单敌小型烙印', '后续periodic_damage在目标每次行动开始单独跳火，不播放角色再次施法，不暴击'),
 'heal': ('轻摇既有铃，铃边聚起青白生命光', '治疗光轻送单友', '目标生命光向上舒展', '铃边余光退去，持铃手复位', '短柔和光流', '单友躯干与脚边局部环绕', 'healed显示实际HP而非总量；护生盾有独立边缘，强盾拒绝替换时不画新盾变薄'),
 'group_heal': ('持铃手轻摇既有铃，另一手展开引导生命光', '向每名存活队员分出一道柔光', '各队员独立治疗光', '光路淡出，回到待机', '多目标分流，不连接倒地队员', '全体存活队友，包括自身', '每人按实际治疗量反馈；不复活，不免费附护生盾'),
 'cleanse': ('轻振既有铃，朝队友引导清净铃纹', '青白清流扫过目标', '实际负面标记逐项溶解', '清流收束，角色收手', '短清流到单友', '单友附着清洁波', '仅status_removed reason=cleanse显示净化；回春只有真实移除后才显healed，空放不画回血'),
 'holy_shield': ('持铃手抬起既有铃，空闲手托起护盾光纹', '铃纹引出的光膜在队友面前展开', '无攻击命中；透明护盾覆盖目标', '铃边收光，盾边缘留下', '短铃纹光流到目标', '单友全身窄边护膜', 'awake为清醒防新眩晕提示，不能画已有眩晕被净化；盾数值与清醒各自结束'),
 'weaken': ('以既有扇面合拢咒纹，既有卷轴留在原有位置', '暗紫符束落到单敌', '无伤害冲击；压制纹缓慢收紧', '扇面收势回到待机', '从既有扇面引出的短咒线', '单敌躯干束纹', 'weaken降低输出，不能显示扣血；已有更强虚弱不变弱或续时'),
 'slow': ('展开既有扇面，借既有卷轴符纹指向敌群', '卷轴引出的符线在全敌脚边落成', '无直接伤害；每个敌人独立出现迟滞纹', '扇面与卷轴恢复既有持用姿势', '多点光质符纹落位，不增加实体符纸道具', '全体敌人脚下局部阵纹', '只影响之后轮序快照；蚀阵仅已有weaken者附magic_break，不伪造当轮重排'),
 'seal': ('合拢既有扇面，配合卷轴符纹锁住单敌蓄力点', '光质封缄符纹快速压下', '成功眩晕才显示束缚停顿；可打断蓄力才碎去蓄力光', '持扇回身，卷轴保持原有位置', '一枚高速光质符纹', '单敌紧贴封印', 'stun与interrupt分别判免疫；清醒/不可打断时不画成功眩晕；解印回MP只在施法者显示一次'),
 'magic_break': ('以既有扇尖指向灵力节点，卷轴符纹呼应', '灵属性印记刺向单敌', '小型灵光命中后护法纹破裂', '扇尖回收，卷轴保持原有位置', '短灵印投射', '单敌魔防破口', '解咒先读取weaken增强该次伤害，magic_break随后落定；不驱散目标已有正面状态')
}

PROP_CONSTRAINTS = {
 'rinne': '仅使用既有木剑，保留木质外观；不新增金属剑或第二把武器。',
 'mint': '仅使用既有同一把Y形弹弓；持用与腰挂对应同一把，不复制第二把；攻击释放单枚弹丸。',
 'guard': '保留既有盾与长戟；盾动作期间长戟保持既有持用/支撑关系，不新增武器。',
 'homura_sword': '保留既有剑刃与剑鞘，出手使用同一把剑；剑鞘保持既有位置，不复制剑。',
 'homura_mage': '双手空手施法，火核/冰晶是法术而非道具；不新增法杖、法器或武器。',
 'healer': '只使用既有铃作为施法道具；光纹是特效，不新增草叶、符纸或其他手持物。',
 'controller': '保留既有扇与卷轴；符纹为光效，不新增符笔、独立符纸或其他手持物。'
}
FORM_FEEDBACK = {
 ('rinne', 'heavy_slash'): '已有armor_break才表现破隙强化；保留破甲，不增加第二次伤害数字',
 ('rinne', 'armor_break'): 'armor_break成功后保留减防提示；崩刃只在施法前自身有battle_spirit且weaken实际施加成功时显示压制纹',
 ('rinne', 'sweep'): '断阵仅施法前已有armor_break者施加slow并消耗破甲；逐目标按status_applied/status_removed反馈',
 ('rinne', 'battle_spirit'): 'battle_spirit只增强直接伤害；按实际status_applied出现，在对应status_removed时消退',
 ('homura_sword', 'heavy_slash'): '按实际damage播放单次物理剑击；已有状态按其自身时钟继续',
 ('homura_sword', 'armor_break'): 'armor_break成功后保留减防提示；引火仅在burn实际施加成功时留下火种，更强旧灼烧不被替换',
 ('homura_sword', 'sweep'): '燎阵只在施法前已有burn的目标成功施加armor_break时显示碎甲；此招不消耗破甲或附加缓速',
 ('homura_sword', 'battle_spirit'): 'battle_spirit增强直接伤害；焰衣只在shield_applied时新增短盾，切形不重新领取或重播'
}
EFFECT_EVENTS = {'damage':'damage', 'apply_status':'status_applied', 'consume_status':'status_removed', 'interrupt':'charge_interrupted', 'shield':'shield_applied', 'heal':'healed', 'cleanse':'status_removed', 'restore_mp':'mp_restored'}

def art_stages(form, sid):
 stages=dict(zip(['cast','release','hit','recovery','travel','target_shape','status_feedback'],BRIEFS[sid]))
 if form=='rinne':
  for key in ['cast','release','hit','recovery','travel','target_shape']:
   stages[key]=stages[key].replace('剑锋','木剑').replace('剑尖','木剑尖').replace('蓄剑','蓄木剑').replace('剑痕','木剑挥痕').replace('剑横','木剑横').replace('收剑','收木剑').replace('拔剑','收木剑').replace('剑弧','木剑挥弧')
 if form=='rinne' and sid=='armor_break': stages['recovery']='木剑短促抽回并复位'
 if (form,sid) in FORM_FEEDBACK: stages['status_feedback']=FORM_FEEDBACK[(form,sid)]
 stages['prop_constraints']=PROP_CONSTRAINTS[form]
 return stages

def event_cues(effects):
 cues=[{'event':'resources_changed','when':'成功确认后mp_before>mp_after','target':'施法者','feedback':'按mp_before与mp_after的真实差显示扣费；失败指令不播放扣费或释放'}]
 for effect in effects:
  event=EFFECT_EVENTS[effect['type']]
  cue={'event':event, 'target':'施法者' if effect.get('recipient')=='source' else '该事件的实际target_id', 'when':'仅实际结算出现该事件时', 'effect_type':effect['type']}
  if effect.get('status_id'):cue['status_id']=effect['status_id']
  if effect.get('requires'):cue['requires']=copy.deepcopy(effect['requires'])
  if effect['type']=='consume_status':cue['reason']='skill_consumed'
  if effect['type']=='cleanse':cue['reason']='cleanse'
  if effect['type'] in ['heal','restore_mp']:cue['when']='事件payload.actual>0时才显示真实回复；回复为0时不画领取收益'
  if cue not in cues:cues.append(cue)
 return cues

PRESENTATION_CONTRACT = {
 'version': 1,
 'status': '供下一阶段美术与接入使用；本轮仅冻结委托，不重新启用FX',
 'clock': '以该角色本次实际attack动作起点S、已批准资源的impact marker M及动作完成E为准；不固定旧法形毫秒值',
 'acceptance': '只在command_accepted后启动本次attack；以resources_changed确认真实MP扣费。失败/过期/重复指令不播释放、不播扣费',
 'impact_binding': '实际damage/healed/shield_applied/status_applied等生效反馈绑定同一次attack的impact marker M；M是表现落点，不重新计算或再次提交战斗效果',
 'travel_binding': '有飞行段时满足S<=launch<arrival<=M；弹丸/火弹/冰矢必须在M前到达实际target_id的命中位置，M处切换命中层。动作变快时重采样/压缩飞行，不推迟M',
 'ordered_feedback': '同一M下按权威事件顺序表现先damage，再附状态/消耗/回馈；全体技能逐个读取实际目标事件，每目标只播一次已有伤害，不因波浪经过再造成第二击',
 'cast_layer': {'suggested_frames': [4, 6], 'interval': 'S到launch；无飞行时S到M', 'end': '到launch或M淡出，不在命中后继续蓄力，不等待旧慢动作的固定时长'},
 'travel_layer': {'suggested_frames': [3, 4], 'interval': 'launch到arrival<=M', 'end': '抵达目标即交给命中层；同一单发弹道只有一枚投射物，全体波独立命中层不增加伤害次数'},
 'hit_layer': {'suggested_frames': [4, 6], 'interval': '从M起播一次，建议占M到E恢复区间的35%至65%', 'end': '不晚于本次动作完成/下一命令开放；快速动作压缩帧时长，不延长结算，不循环伤害'},
 'recovery_layer': {'suggested_frames': [2, 3], 'interval': '命中层末段到E', 'end': '在实际attack完成时清除一次性残影；角色回到已有待机，不新增第二次释放'},
 'status_layer': {'suggested_frames': [2, 4], 'interval': '实际status_applied或shield_applied后可低频循环；actual>0的治疗/MP回复只播一次短反馈', 'end': '相应status_removed、shield_removed、倒地或场景退出时立即清除；所有携带absorption的承伤事件（含damage、periodic_damage、saga_reflected）的shield_after为空也须清除耗尽护盾，有余量则更新显示；不能按特效秒数提前移除规则状态'},
 'immunity': 'effect_ignored不播放成功附加层；只读实际事件，不能按静态技能说明伪造灼烧、护盾、治疗或MP回收',
 'scope': '建议帧数是下一阶段图稿拆层约定，不改角色attack已批准时序、规则时钟、伤害次数或资源'
}
PRESENTATION_CATEGORIES = {
 'cover':'single_support', 'shield_bash':'melee_contact', 'iron_wall':'self_support', 'taunt':'single_status',
 'heavy_slash':'melee_contact', 'armor_break':'melee_contact', 'sweep':'melee_area', 'battle_spirit':'self_support',
 'mark':'single_projectile', 'hunt':'single_projectile', 'ambush':'single_projectile', 'smoke_screen':'self_support',
 'firebolt':'single_projectile', 'flame_wave':'area_wave', 'ice_arrow':'single_projectile', 'burn_brand':'single_projectile',
 'heal':'single_support', 'group_heal':'group_support', 'cleanse':'single_support', 'holy_shield':'single_support',
 'weaken':'single_status', 'slow':'area_status', 'seal':'single_status', 'magic_break':'single_projectile'
}
CATEGORY_NAMES = {'single_support':'单体支援', 'melee_contact':'近战接近/接触', 'self_support':'自身支援', 'single_status':'单体状态', 'melee_area':'全体近战横扫', 'single_projectile':'单发投射', 'area_wave':'全体波', 'group_support':'全体支援', 'area_status':'全体状态'}

STATUS_NAMES = {'cover':'掩护','defend':'防御','armor_break':'破甲','magic_break':'破魔','battle_spirit':'战意','mark':'标记','weaken':'虚弱','slow':'缓速','burn':'灼烧','stun':'眩晕','awake':'清醒','taunt':'挑衅','stagger':'失衡'}
TARGETS = {'self':'自身','other_ally':'一名其他存活队友','single_ally':'一名存活队员（含自己）','all_allies':'全部存活队员（含自己）','single_enemy':'一名存活敌人','all_enemies':'全部存活敌人'}
STATS = {'atk':'物攻','matk':'术攻','def':'防御','mdef':'魔防'}

def timing(effect):
 n=effect['duration']; clock=effect['clock']
 return '至施法者下次行动开始（只接一次单体直接攻击）' if clock=='next_owner_slot' else (f'之后{n}次轮序快照' if clock=='round_snapshot' else f'{n}次持有者行动')
def describe(e):
 t=e['type']
 if t=='damage':
  out=f"{e['coefficient']*100:g}%{'物攻' if e['damage_type']=='physical' else '术攻'}系数的{ {'neutral':'中性','fire':'火','ice':'冰','spirit':'灵'}[e['element']]}{'物理' if e['damage_type']=='physical' else '魔法'}伤害"
  if e.get('condition'):out+=f"；{'目标已有'+STATUS_NAMES[e['status_id']] if e['condition']=='target_has_status' else '目标本轮尚未获得行动槽'}时改为{e['conditional_coefficient']*100:g}%"
  return out
 if t=='apply_status':return f"{STATUS_NAMES[e['status_id']]}"+(f" {e['magnitude']*100:g}%"+('术攻快照' if e['status_id']=='burn' else '') if e['status_id'] not in ['mark','stun','awake','taunt'] else '')+'，'+timing(e)
 if t in ['heal','shield']:return f"{'回复生命' if t=='heal' else '护盾'} {e['fixed']}+{e['coefficient']*100:g}%{STATS[e['stat']]}"+('，'+timing(e) if t=='shield' else '')
 if t=='consume_status':return '消耗'+STATUS_NAMES[e['status_id']]
 if t=='interrupt':return '打断可打断的现有蓄力；无蓄力或不可打断时此项无效'
 if t=='cleanse':return '移除全部可净化负面（burn/weaken/armor_break/magic_break/slow/mark/taunt/stun）'
 if t=='restore_mp':return f"施法者回复{e['fixed']}MP，每次施放最多一次"
 raise ValueError(t)
def derived(base, refinement, level, branch=''):
 result=copy.deepcopy(base)
 if level>=6:
  for key,value in result.get('branches',{}).get(branch,{}).get('9' if level>=9 else '6',{}).items():
   if key=='mp_cost':result[key]=value
   else:
    for effect in result['effects']:
     if key in effect:effect[key]=value
 if level>=3 and refinement['skill_id']==base['id']:
  result['mp_cost']+=refinement['mp_cost_add'];result['cooldown']+=refinement['cooldown_add']
  cond=refinement['damage_condition']
  if cond:
   for effect in result['effects']:
    if effect['type']=='damage':effect.update(condition='target_has_status',status_id=cond['status_id'],conditional_coefficient=effect['coefficient']+cond['coefficient_add'])
  result['effects']+=copy.deepcopy(refinement['extra_effects'])
 for t in refinement['techniques']:
  if t['skill_id']==base['id'] and level>=t['unlock_level']:
   result['mp_cost']+=t['mp_cost_add'];result['cooldown']+=t['cooldown_add'];result['effects']+=copy.deepcopy(t['extra_effects'])
 return result

def outputs():
 sources={n:json.loads((ROOT/f'data/rpg/{n}.json').read_text()) for n in ['skills','classes','character_refinements']}
 skills={s['id']:s for s in sources['skills']['definitions']}
 classes={s['id']:s for s in sources['classes']['definitions']}
 digest=hashlib.sha256(json.dumps(sources,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
 brief={'schema_version':1,'source_sha256':digest,'generation_policy':'仅使用内置ChatGPT imagegen生成独立法术素材；本委托未生成图片；几何替代FX仍禁用；火/冰试片风格未获批准。','presentation_contract':PRESENTATION_CONTRACT,'records':[]}
 lines=['# 七形态技能目录与逐招动作/特效委托','', '本目录由 tools/rpg/build_skill_catalog.py 从当前权威数据生成。24个基础技能ID不变，七形态共28个卡位记录；保留7项L3专精，新增14项L4/L5技法。所有增强仍占原卡位，自动随等级开放。', '', '## 统一结算与表现约束','', '- 数字“150%物攻”等是伤害公式系数，不是最终HP扣除；还经过物防/魔防、元素、增伤、虚弱、防御、掩护及护盾。直接伤害允许5%暴击，暴击倍率1.5；灼烧不暴击。', '- target_slot持续N次持有者行动；新施加/刷新状态不在当前正在结算的槽立即减时。自身1行动增益覆盖下一次出手并在其结束时消退。round_snapshot只影响之后N次轮序，不重排当前轮。', '- CD N表示施放后该角色接下来的N个行动槽不可再用；须先付全额MP，回馈不能预支。重复/过期/非法目标指令零副作用。', '- 除净化回春外，技法条件读取施法开始时快照；伤害先结算，再附效/消耗。回春必须本次实际移除负面才回复。所有施法者MP回馈每命令最多一次、最多3MP，不向敌人回MP。', '- 同名状态不叠加：弱者不覆盖或续时，等强保留较长时间，强者替换。护盾是唯一池，按当前剩余量比较；较弱新盾不覆盖/续时，等强或更强采用新盾时长。', '- 净化IDs：burn、weaken、armor_break、magic_break、slow、mark、taunt、stun。岑照铁壁可行动时清除其中已有项；已经被眩晕跳过的行动不能追回，也不能在失去的选择机会施法。', '- 清醒awake仅拒绝新眩晕，不净化已有眩晕；打断和眩晕分别判断。不可打断蓄力免疫打断及眩晕，清醒不免疫打断。封缄在全部控制无效且没有条件回馈时不应消费行动。', '- 焰华是同一p_mage：两形态共享现有属性、HP、MP、状态、护盾、行动槽及冷却字典。切形不重新领取任何技法收益，不使用第二套职业基础属性，不改变剧情解锁。', '- L6/L9先应用原分支再追加专精/技法；本次不改装备、药品、经验、掉落、关卡或商店经济。无身份旧试作角色继续使用基础技能。', '- 旧存档正常读入；新重放封套携带实际目录内容SHA256，指纹不匹配直接报错。旧无指纹重放继续严格逐事件验证，并标记legacy_unfingerprinted；不承诺旧规则事件在新规则下相同。', '- 美术只响应实际结算事件；免疫/未满足条件不画“成功附加”。持续状态用独立附着提示，不把一次施法循环当作持续伤害。全体目标按规则名单，不依据画面几何距离重新筛选。', '- 后续法术图片仅用内置ChatGPT imagegen，透明底、可分离施放/弹道/命中/状态层；本轮不生成图、不接回被否决的几何FX。现有火/冰试片风格仍待批准。', '']
 lines += ['## 统一表现时间契约', '', *['- '+PRESENTATION_CONTRACT[key]+'。' for key in ['clock','acceptance','impact_binding','travel_binding','ordered_feedback','immunity','scope']], '']
 for key,label in [('cast_layer','施法层'),('travel_layer','飞行层'),('hit_layer','命中层'),('recovery_layer','收势层'),('status_layer','状态层')]:
  layer=PRESENTATION_CONTRACT[key]
  lines += [f"- {label}：建议{layer['suggested_frames'][0]}–{layer['suggested_frames'][1]}帧；{layer['interval']}；结束条件：{layer['end']}。"]
 lines += ['']
 for refinement in sources['character_refinements']['definitions']:
  title,form,palette=FORMS[refinement['id']]
  lines += [f'## {title}', '', f"战术：{refinement['tactic']}", f'视觉区分：{palette}。', '']
  for sid in classes[refinement['active_class_id']]['skill_ids']:
   base=skills[sid];current=derived(base,refinement,5);r=refinement if refinement['skill_id']==sid else None;t=next((x for x in refinement['techniques'] if x['skill_id']==sid),None)
   stages=art_stages(form,sid)
   record={'form_id':form,'identity_id':refinement['identity_id'],'class_id':refinement['active_class_id'],'skill_id':sid,'name':base['name'],'unlock_level':base['unlock_level'],'target_rule':base['target_rule'],'base_cost':base['mp_cost'],'base_cooldown':base['cooldown'],'level5_cost':current['mp_cost'],'level5_cooldown':current['cooldown'],'level5_effects':current['effects'],'refinement':{k:r[k] for k in ['name','summary','unlock_level']} if r else {},'technique':t or {},'palette':palette,'presentation_category':PRESENTATION_CATEGORIES[sid],'presentation_contract_version':1,'event_cues':event_cues(current['effects']),**stages}
   brief['records'].append(record)
   lines += [f"### {base['name']} · {form}/{sid}", '', f"- 卡位：L{base['unlock_level']}开放；目标：{TARGETS[base['target_rule']]}。基础MP{base['mp_cost']}/CD{base['cooldown']}；本形态L5为MP{current['mp_cost']}/CD{current['cooldown']}。", '- 基础顺序：'+' → '.join(describe(e) for e in base['effects'])+'。']
   if r:lines += [f"- L3专精·{r['name']}：{r['summary']} 额外MP+{r['mp_cost_add']}，CD+{r['cooldown_add']}。"]
   if t:lines += [f"- L{t['unlock_level']}技法·{t['name']}：{t['summary']} 额外MP+{t['mp_cost_add']}，CD+{t['cooldown_add']}。"]
   for branch in base.get('branches',{}):
    for level in [6,9]:
     value=derived(base,refinement,level,branch)
     lines += [f"- L{level}·{ {'economy':'节约','power':'强度','duration':'持续'}[branch]}：MP{value['mp_cost']}/CD{value['cooldown']}；"+' → '.join(describe(e) for e in value['effects'] if not e.get('requires'))+'。']
   lines += ['- 表现类别：'+CATEGORY_NAMES[PRESENTATION_CATEGORIES[sid]]+'；遵守统一presentation_contract v1，以本次实际attack的impact marker生效。']
   for key,label in [('prop_constraints','既有道具约束'),('cast','起手'),('release','释放'),('hit','命中/生效'),('recovery','收势'),('travel','运动需求'),('target_shape','范围形状'),('status_feedback','状态反馈')]:lines += [f'- {label}：{stages[key]}。']
   if t: lines += [f"- 技法特效条件：{t['summary']} 只在相应{'/'.join(dict.fromkeys(EFFECT_EVENTS[e['type']] for e in t['extra_effects']))}事件成功时加这一层。"]
   lines += ['- 资源反馈：resources_changed记录确认后的真实MP扣费；条件回馈仅在mp_restored且actual>0时向施法者显示实际回复。']
   lines+=['']
 lines+=['## 队伍连携与取舍','', '- 凛音 + 薄荷：凛音破甲后自己重斩保留破甲吃单体收益，或横扫把破甲转为下一轮缓速；薄荷标记/奇袭→猎杀仍是自己的爆发与MP回收链。两类铺垫不能互换。', '- 岑照 + 清明 + 焰华：铁壁留盾→挑衅镇锋给短虚弱；清明可接迟滞蚀阵挂破魔或破魔印解咒追伤，焰华接法术。护盾一旦提前耗尽，镇锋条件也消失。', '- 焰华剑/法：引火破甲→切法形续焰；多目标已有火种时续燎刷新，或剑形燎阵给物理队开破甲。冰矢熄焰以失去未来灼烧为代价压低反击，不能同时保留两份收益。', '- 苏合 + 岑照/薄荷：单疗护生保低血，净化回春处理真实负面，圣盾定神预防接下来的眩晕。强盾优先规则避免小治疗盾覆盖厚盾；群疗不附带个人单疗专精。', '- 技法额外MP通常+1或+2，凛音断阵额外CD+1；自动成长意味着新增控制/衔接需付出持续战斗资源，不能当作免费全体增益。', '', f'源数据校验：{digest}', '']
 return {'skill-catalog-2026-10-07.md':'\n'.join(lines), 'skill-art-briefs-2026-10-07.json':json.dumps(brief,ensure_ascii=False,indent=2)+'\n'}

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
 for name,contents in outputs().items():
  path=OUT/name
  if args.check:
   if not path.exists() or path.read_text()!=contents:raise SystemExit('FAIL: 技能委托与权威数据不同步：'+str(path))
  else:path.write_text(contents)
 print('PASS: 28个形态技能目录与逐招动作/VFX委托'+('同步' if args.check else '已生成'))
if __name__=='__main__':main()
