#!/usr/bin/env python3
"""将批准的后六章137场导出为剧情图；正文不改写，条件、战斗和交互独立标注。

source_index 是各场标题后的零基行号；固定源哈希使审稿更新不能悄悄错配。
lines → choice.lines → 实战 → after_lines → followup_lines → effects。
requires/when 为 AND 等值条件；done:场次 与 battle:场次由运行时提供。
next_routes 按顺序选择第一条匹配；空 next 返回原主线游标。
"""
from __future__ import annotations
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'docs/story/review/v1/逢魔退治帖_七章完整对白_v1.txt'
OUTLINE = ROOT / 'docs/story/review/v1/逢魔退治帖_第二至七章分场大纲_v1.txt'
OUTPUT = ROOT / 'data/campaign/saga.json'
APPROVED_SHA = '46fa0a9c7a6be93d53a54d16d85c638c23dc0bfc134e48e073010b5289d1a1de'
TITLES = {2:'无眠街',3:'逆水渡',4:'镜中双影',5:'借命灯',6:'百夜无更',7:'天明之前'}
LOCATIONS = {
 2:{'gate':'南街入口','inn':'阿杏客栈','square':'南街晒场','shop':'陶婶灯铺','canal':'茶棚与排水口','alley':'后巷旧染坊'},
 3:{'gate':'渡口入口','dock':'主码头','warehouse':'西仓','bay':'内湾第二岸线','shrine':'旧堤小镜结','exit':'外岸灯路'},
 4:{'gate':'镜坊前院','shop':'镜坊柜台','workshop':'抛光间','corridor':'镜廊','archive':'修阵室','echo':'留声小室'},
 5:{'gate':'医馆前堂','shop':'药房柜台','ward':'地下病房','yard':'后院石阶','store':'药库与后药棚','sanctum':'地下静室'},
 6:{'gate':'山门','honden':'本殿','courtyard':'前庭接应处','junction':'北街灯节点','dock':'外撤码头','alley':'后巷','drain':'排水道入口'},
 7:{'gate':'主镜厅准备区','stairs':'休整石阶','hall':'主镜厅','mirror':'主镜台','names':'刻名板','exit':'主镜外口'},
}
LOCATION_ROWS={
 2:('gate inn alley shop alley canal canal inn inn canal square square shop inn square gate inn', {'S01':'square','S02':'alley','S03':'square','R01':'inn','R02':'shop','R03':'alley'}),
 3:('gate bay dock dock warehouse bay bay bay bay bay exit shrine shrine shrine dock dock exit', {'S01':'warehouse','S02':'warehouse','R01':'bay','R02':'bay','R03':'shrine'}),
 4:('gate archive corridor corridor corridor corridor corridor corridor corridor archive archive echo archive gate', {'S01':'workshop','S02':'workshop','S03':'gate','R01':'shop','R02':'gate','R03':'corridor','R04':'gate'}),
 5:('gate ward ward sanctum sanctum ward sanctum ward store sanctum sanctum sanctum yard gate yard yard', {'S01':'yard','S02':'store','S03':'yard','R01':'shop','R02':'yard','R03':'ward','R04':'gate'}),
 6:('gate gate honden honden honden honden courtyard junction courtyard junction junction courtyard drain drain', {'S01':'dock','S02':'dock','S03':'dock','S04':'alley','R01':'courtyard','R02':'courtyard','R03':'courtyard'}),
 7:('gate hall hall hall mirror mirror mirror mirror mirror mirror mirror mirror mirror exit exit exit exit exit exit mirror hall hall', {'S01':'names','R01':'gate','R02':'stairs','R03':'exit','R04':'gate'}),
}
MAIN_ORDER={
 2:[f'C2-{n:02}' for n in range(1,15)]+['C2-17','C2-15','C2-16'],
 3:[f'C3-{n:02}' for n in range(1,18)],
 4:[f'C4-{n:02}' for n in range(1,15)]+['C4-R04'],
 5:[f'C5-{n:02}' for n in range(1,17)]+['C5-R04'],
 6:[f'C6-{n:02}' for n in range(1,15)],
 7:[f'C7-{n:02}' for n in range(1,10)],
}
DAWN={'responsibility_resolved':True,'clinic_awake':True,'evacuation_route_ready':True,'alley_rescued':True,'segment_network_ready':True}
EVAC={'evacuation_route_ready':True,'alley_rescued':True}
NOT_EVAC=[{'evacuation_route_ready':False},{'evacuation_route_ready':True,'alley_rescued':False}]
SENT={'resolution':'sendoff'}
SEALED={'resolution':'seal_monitoring'}
# 同一范围的一组条件是互斥 OR，导出为各带 when 的独立台词，运行时仍只需 AND。
CONDITIONS={
 'C2-01':[(10,11,SENT),(12,13,SEALED)],
 'C2-17':[(4,10,SENT),(11,15,SEALED)],
 'C2-15':[(11,14,{'night_market_rescued':True}),(15,17,{'night_market_rescued':False})],
 'C2-16':[(4,13,{'night_market_rescued':False}),(14,19,{'night_market_rescued':True})],
 'C2-S02':[(1,3,{'done:C2-12':False}),(4,6,{'done:C2-12':True}),(25,99,{'done:C2-12':True})],
 'C2-S03':[(1,8,{'night_market_rescued':True}),(9,99,{'night_market_rescued':False})],
 'C2-R02':[(1,4,{'done:C2-R02':False}),(12,13,{'done:C2-R02':True}),(14,15,{'night_market_rescued':True}),(16,99,{'night_market_rescued':False})],
 'C2-R03':[(1,2,{'done:C2-07':True}),(3,4,{'done:C2-12':False}),(5,6,{'done:C2-09':False}),(7,8,{'night_market_rescued':True}),(9,10,{'done:C2-12':True}),(11,12,{'done:C3-01':True}),(13,99,{'night_market_rescued':False})],
 'C3-07':[(1,3,{'retreat_route':'slope'}),(4,6,{'retreat_route':'tow'})],
 'C3-17':[(3,4,{'ferry_repaired':True}),(5,6,{'ferry_repaired':False}),(7,8,{'warehouse_status':'pending'})],
 'C3-S02':[(1,4,{'warehouse_status':'protected'}),(5,99,{'warehouse_status':'pending'})],
 'C3-R02':[(1,4,{'done:C3-R02':False}),(11,12,{'warehouse_status':'protected'}),(13,14,{'warehouse_status':'recovered'}),(15,99,{'warehouse_status':'pending'})],
 'C3-R03':[(1,2,{'done:C3-10':False}),(3,4,{'done:C3-10':True}),(5,6,{'done:C3-14':True}),(7,8,{'done:C3-13':True}),(9,10,{'ferry_repaired':True}),(11,13,{'ferry_repaired':False}),(14,15,{'warehouse_status':'pending'})],
 'C4-14':[(7,9,SENT),(10,12,SEALED)],
 'C4-S03':[(1,8,{'qiuan_rescued':False}),(9,11,{'qiuan_rescued':True})],
 'C4-R01':[(1,4,{'done:C4-R01':False}),(11,99,{'done:C4-R01':True})],
 'C4-R03':[(3,4,{'qiuan_rescued':False}),(5,6,{'qiuan_rescued':True}),(7,99,{'done:C4-R03':True})],
 'C4-R04':[(4,6,{'qiuan_rescued':False})],
 'C5-08':[(7,9,{'family_rescued':True}),(10,11,{'family_rescued':False})],
 'C5-10':[(1,3,{'clinic_plan':'gentle'}),(4,7,{'clinic_plan':'isolate'})],
 'C5-12':[(11,12,{'clinic_plan':'gentle'}),(13,14,{'clinic_plan':'isolate'})],
 'C5-13':[(1,13,{'clinic_plan':'gentle'}),(14,99,{'clinic_plan':'isolate'})],
 'C5-14':[(5,7,{'clinic_plan':'gentle'}),(8,10,{'clinic_plan':'isolate'})],
 'C5-16':[(3,4,SENT),(5,6,SEALED),(7,8,{'clinic_plan':'gentle'}),(9,10,{'clinic_plan':'isolate'}),(11,12,{'family_rescued':False})],
 'C5-S02':[(10,11,{'done:C5-13':False}),(12,13,{'done:C5-13':True,'clinic_awake':True}),(14,15,{'done:C5-13':True,'clinic_awake':False})],
 'C5-S03':[(1,7,{'clinic_awake':True}),(8,13,{'clinic_awake':False})],
 'C5-R01':[(1,4,{'done:C5-R01':False}),(11,99,{'done:C5-R01':True})],
 'C5-R03':[(1,3,{'clinic_awake':True}),(4,6,{'clinic_awake':False}),(7,8,{'done:C5-R03':False}),(9,99,{'done:C5-R03':True})],
 'C5-R04':[(3,4,{'clinic_awake':False}),(5,6,{'clinic_awake':True}),(7,9,{'family_rescued':False}),(10,10,{'family_rescued':True})],
 'C6-01':[(7,9,{'clinic_awake':True}),(10,12,{'clinic_awake':False})],
 'C6-02':[(6,9,SENT),(10,13,SEALED)],
 'C6-06':[(21,99,{'done:C6-06':True})],
 'C6-07':[(1,3,{'responsibility_resolved':True}),(4,6,{'responsibility_resolved':False})],
 'C6-08':[(5,6,{'clinic_awake':True}),(7,9,{'clinic_awake':False})],
 'C6-12':[(4,5,{'clinic_awake':False}),(6,7,{'clinic_awake':True}),(9,12,{'night_market_rescued':True}),(13,19,{'night_market_rescued':False}),(28,30,{'clinic_awake':False}),(31,33,{'clinic_awake':True})],
 'C6-S02':[(33,99,{'done:C6-S02':True})],
 'C6-S03':[(7,11,{'ferry_repaired':False}),(12,13,{'ferry_repaired':True}),(25,99,{'evacuation_route_ready':True})],
 'C6-S04':[(20,99,{'alley_rescued':True})],
 'C6-13':[(4,5,{'evacuation_route_ready':True}),(6,7,{'evacuation_route_ready':False}),(8,9,EVAC),(10,11,{'alley_rescued':True,'evacuation_route_ready':False}),(12,13,{'alley_rescued':False}),(14,15,{'clinic_awake':True}),(16,17,{'clinic_awake':False}),(18,19,{'responsibility_resolved':True}),(20,21,{'responsibility_resolved':False})],
 'C6-14':[(13,99,{'done:C6-14':True})],
 'C6-R01':[(2,3,{'warehouse_status':'protected'}),(4,5,[{'warehouse_status':'pending'},{'warehouse_status':'recovered'}])],
 'C6-R03':[(1,3,{'responsibility_resolved':True}),(4,6,{'responsibility_resolved':False}),(7,9,{'clinic_awake':True}),(10,12,{'clinic_awake':False}),(13,15,EVAC),(16,99,NOT_EVAC)],
 'C7-08':[(2,3,DAWN),(4,5,{'evacuation_route_ready':False}),(6,7,{'alley_rescued':False}),(8,9,{'clinic_awake':False}),(10,11,{'responsibility_resolved':False})],
 'C7-14':[(16,17,SENT),(18,99,SEALED)],
 'C7-16':[(9,10,{'clinic_awake':False}),(11,12,{'clinic_awake':True}),(13,14,NOT_EVAC)],
 'C7-17':[(1,4,{'responsibility_resolved':False}),(5,7,{'responsibility_resolved':True}),(18,19,{'clinic_awake':False}),(20,21,{'clinic_awake':True})],
 'C7-18':[(4,7,{**EVAC,'clinic_awake':True}),(8,10,{'alley_rescued':False}),(11,12,{'alley_rescued':True,'evacuation_route_ready':False}),(13,13,NOT_EVAC),(14,18,{'clinic_awake':False})],
 'C7-19':[(5,6,NOT_EVAC),(7,8,{'clinic_awake':False}),(14,16,{'clinic_awake':True}),(17,18,{'clinic_awake':False}),(21,22,{'responsibility_resolved':False})],
 'C7-20':[(14,17,{'evacuation_route_ready':True}),(18,99,{'evacuation_route_ready':False})],
 'C7-21':[(5,10,{'evacuation_route_ready':True}),(11,99,{'evacuation_route_ready':False})],
 'C7-22':[(7,8,{'evacuation_route_ready':True}),(9,11,{'evacuation_route_ready':False}),(18,19,{'evacuation_route_ready':False}),(22,24,{'responsibility_resolved':False})],
 'C7-S01':[(1,6,{'done:C7-S01':False}),(7,99,{'done:C7-S01':True})],
 'C7-R03':[(1,2,{'clinic_awake':False}),(3,4,{'evacuation_route_ready':False}),(5,6,{'alley_rescued':False}),(7,8,{'responsibility_resolved':False}),(9,10,DAWN)],
 'C7-R04':[(1,6,{'retry_stage':1}),(7,12,{'retry_stage':2}),(13,99,{'retry_stage':3})],
}
# (战中开始行, 胜利开始行, 失败开始行)；选择战使用同一标注但挂在所选分支上。
BATTLE_RANGES={
 'C2-03':(9,11,None),'C2-07':(5,10,None),'C2-09':(8,15,None),'C2-12':(4,21,24),'C2-S02':(13,16,None),
 'C3-03':(5,11,None),'C3-07':(7,10,None),'C3-10':(4,19,22),'C3-S01':(8,12,None),'C3-S02':(9,12,None),
 'C4-04':(5,12,15),'C4-09':(1,16,18),'C4-S02':(4,10,14),
 'C5-09':(5,11,14),'C5-12':(1,17,20),'C5-S02':(6,8,None),
 'C6-04':(12,20,None),'C6-11':(2,14,None),'C6-S02':(8,10,None),'C6-S04':(8,11,None),
 'C7-05':(4,14,None),'C7-06':(4,14,None),'C7-10':(9,15,None),'C7-11':(3,11,None),'C7-12':(5,11,None),'C7-13':(5,11,None),
}
BRANCH_BATTLES={'C3-S01':'a','C3-S02':'a','C6-04':'a','C6-S04':'a'}
# 顺序与原文一致；重复的A/B会得到a2/b2。共享续对白单列，不混进B回答。
CHOICE_ENDS={'C4-05':14,'C6-S03':25,'C6-S04':20,'C6-14':13,'C6-R01':13,'C7-R01':6}
CHOICE_NEXT={
 'C2-16':['C2-S02','C3-01','C3-01','C2-16'], 'C2-S01':['C2-S02',''],
 'C3-06':['C3-07','C3-07'],'C3-15':['C3-16','C3-17'],'C3-17':['C4-01','C3-17'],
 'C3-S01':['',''],'C3-S02':['',''],'C4-05':['C4-06','C4-06'],
 'C4-S01':['C4-S02',''],'C4-R04':['C5-01','C4-R04'],
 'C5-08':['C5-09','C5-10','C5-08'],'C5-S01':['C5-S02',''],'C5-R04':['C6-01','C5-R04','C5-R04'],
 'C6-04':['C6-05','C6-07'],'C6-05':['C6-06','C6-07'],'C6-S01':['C6-S02',''],
 'C6-S03':['',''],'C6-S04':['',''],'C6-14':['C7-01','C6-12','C6-R02'],
 'C6-R01':['',''],'C7-01':['C7-02','C6-12','C7-R02'],'C7-R01':['C7-01','C7-01'],
 'C7-R04':['C7-05','C7-01','C7-06','C7-01','C7-09','C7-09'],
}
EFFECTS={
 'C2-03':{'street_guests_safe':True},'C2-07':{'tea_wick_recovered':True},'C2-09':{'guide_lamp_repaired':True},
 'C2-10':{'water_echo_verified':True},'C2-13':{'shipping_manifest':True,'shared_mirror_shard':True},
 'C2-17':{'letter_posted':True},'C2-S02':{'night_market_rescued':True},
 'C3-05':{'evacuation_notebook':True},'C3-11':{'ferry_passengers_safe':True},'C3-13':{'wuji_departed':True},
 'C3-14':{'first_array_plan':True,'ferry_shrink_verified':True},'C3-16':{'ferry_repaired':True},
 'C4-11':{'repair_archive':True},'C4-12':{'old_recording':True},'C4-13':{'connection_map':True},
 'C4-S02':{'qiuan_rescued':True},'C4-S03':{'qiuan_rescued':True},
 'C5-05':{'luyun_departed':True},'C5-06':{'clinic_experiment_verified':True},'C5-07':{'maintenance_ledger':True},
 'C5-15':{'segment_plan':True},'C5-S02':{'family_rescued':True},
 'C6-01':{'patients_outside':True},'C6-03':{'letter_receipt_received':True,'responsibility_resolved':True},
 'C6-06':{'responsibility_resolved':True,'relics_posted':True,'late_sendoff_posted':True},
 'C6-08':{'dream_intake_stopped':True,'control_pin_held':True},'C6-09':{'temporary_ward_verified':True},
 'C6-11':{'segment_network_ready':True},'C6-12':{'night_market_rescued':True,'night_market_outside':True,'return_paths_open':True},
 'C6-S02':{'clinic_awake':True},'C7-20':{'dream_intake_stopped':False,'dream_intake_reconnected':True},
}
CHOICE_EFFECTS={
 ('C3-06','a'):{'retreat_route':'slope'},('C3-06','b'):{'retreat_route':'tow'},
 ('C3-S01','a'):{'warehouse_status':'protected'},('C3-S01','b'):{'warehouse_status':'pending'},
 ('C3-S02','a'):{'warehouse_status':'recovered'},
 ('C5-08','a'):{'clinic_plan':'gentle'},('C5-08','b'):{'clinic_plan':'isolate'},
 ('C6-04','a'):{'seal_removed':True},('C6-S03','a'):{'ferry_repaired':True,'evacuation_route_ready':True},
 ('C6-S04','a'):{'alley_rescued':True},
}
REQUIRES={
 'C2-S01':{'done:C2-04':True,'night_market_rescued':False},'C2-S02':{'done:C2-04':True,'night_market_rescued':False},'C2-S03':{'done:C2-04':True},
 'C2-R01':{'done:C2-02':True},'C2-R02':{'done:C2-04':True},'C2-R03':{'done:C2-04':True},
 'C3-S01':{'done:C3-05':True,'done:C3-07':False,'done:C3-S01':False},'C3-S02':{'done:C3-10':True},'C3-16':{'done:C3-14':True,'ferry_repaired':False},
 'C3-R01':{'done:C3-08':True},'C3-R02':{'done:C3-02':True},'C3-R03':{'done:C3-02':True},
 'C4-S01':{'done:C4-01':True,'done:C4-09':False,'qiuan_rescued':False},'C4-S02':{'done:C4-01':True,'done:C4-09':False,'qiuan_rescued':False},'C4-S03':{'done:C4-10':True},
 'C4-R01':{'done:C4-01':True},'C4-R02':{'done:C4-10':True},'C4-R03':{'done:C4-10':True},
 'C5-09':{'clinic_plan':'gentle'},'C5-S01':{'done:C5-01':True,'family_rescued':False},'C5-S02':{'done:C5-01':True,'family_rescued':False},'C5-S03':{'done:C5-13':True,'family_rescued':True},
 'C5-R01':{'done:C5-01':True},'C5-R02':{'done:C5-13':True},'C5-R03':{'done:C5-13':True},
 'C6-03':{**SENT,'letter_posted':True},'C6-04':{**SEALED,'responsibility_resolved':False,'seal_removed':False},
 'C6-05':{**SEALED,'responsibility_resolved':False,'seal_removed':True},'C6-06':{**SEALED,'responsibility_resolved':False,'seal_removed':True},
 'C6-S01':{'done:C6-12':True,'clinic_awake':False},'C6-S02':{'done:C6-12':True,'clinic_awake':False},
 'C6-S03':{'done:C6-12':True},'C6-S04':{'done:C6-12':True},
 'C6-R01':{'done:C6-12':True},'C6-R02':{'done:C6-12':True},'C6-R03':{'done:C6-12':True},
 'C7-S01':{'done:C7-06':True,'done:C7-10':False,'done:C7-11':False,'done:C7-12':False,'done:C7-13':False},
 'C7-R01':{'done:C7-05':False},'C7-R02':{'done:C7-05':False},'C7-R03':{'done:C7-05':False},'C7-R04':{'battle_retry_pending':True},
}
FLAGS={
 'resolution':'sendoff', 'responsibility_resolved':False,'seal_removed':False,'letter_posted':False,'letter_receipt_received':False,
 'relics_posted':False,'late_sendoff_posted':False,'night_market_rescued':False,'night_market_outside':False,
 'ferry_repaired':False,'warehouse_status':'pending','retreat_route':'','qiuan_rescued':False,'family_rescued':False,
 'clinic_plan':'','clinic_awake':False,'patients_outside':False,'dream_intake_stopped':False,'segment_network_ready':False,
 'evacuation_route_ready':False,'alley_rescued':False,'return_paths_open':False,'temporary_ward_verified':False,
 'ending_plan':'','battle_retry_pending':False,'retry_stage':0,
}



def ev(kind, requires=None, **filters):
    return {'type':kind,'requires':requires or {},**filters}


def intent(ability):
    return ev('intent_updated',{'intent.ability_id':ability})


# 事件字典只监听真实战斗结果；相反结果不共用一个“战斗中”触发。
BATTLE_EVENTS={
 'C2-03':[(9,10,ev('battle_started'))],
 'C2-07':[(6,7,intent('saga_shadow_glow')),(8,9,ev('damage',target_side='player'))],
 'C2-09':[(9,10,intent('saga_shadow_glow')),(11,12,ev('status_applied',{'status.id':'taunt'},target_side='enemy')),(13,14,ev('damage',target_side='player'))],
 'C2-12':[(4,6,ev('saga_voice_replay')),(7,8,ev('saga_voice_guarded')),(9,10,ev('charge_interrupted')),
     (11,12,ev('saga_voice_repeated')),(13,14,ev('saga_voice_exploited')),(15,20,intent('saga_voice_rush'))],
 'C2-S02':[(13,15,intent('saga_paper_bind'))],
 'C3-03':[(6,7,ev('actor_defeated',target_side='enemy')),(8,10,intent('saga_paper_bind'))],
 'C3-07':[(7,9,intent('saga_paper_bind'))],
 'C3-10':[(4,5,intent('saga_banner_raise')),(6,7,ev('charge_interrupted')),(8,9,ev('saga_support_returned')),
     (10,11,ev('cover_redirected')),(12,13,ev('command_accepted',actor_side='player',min_targets=2)),
     (14,15,intent('saga_banner_sweep')),(16,18,intent('saga_banner_release'))],
 'C3-S01':[(8,9,ev('battle_started')),(10,11,intent('saga_paper_bind'))],
 'C3-S02':[(9,11,ev('battle_started'))],
 'C4-04':[(5,6,intent('saga_shard_plate')),(7,8,ev('damage',actor_side='enemy')),(9,11,ev('damage',target_side='player'))],
 'C4-09':[(1,2,intent('saga_mirror_edge')),(3,4,intent('saga_mirror_water')),
     (5,6,ev('form_changed',actor_id='p_mage')),(7,8,ev('saga_reflected',excluded_actor='p_mage')),
     (9,11,ev('damage',actor_side='enemy')),(12,13,intent('saga_mirror_open')),(14,15,ev('charge_interrupted'))],
 'C4-S02':[(4,5,ev('battle_started')),(6,9,intent('saga_shard_plate'))],
 'C5-09':[(5,6,intent('saga_paper_bind')),(7,8,intent('saga_shadow_glow')),(9,10,ev('actor_defeated',target_side='enemy'))],
 'C5-12':[(1,4,ev('status_applied',{'status.id':'mark'},target_side='player')),(5,6,intent('saga_lamp_drain')),
     (7,8,ev('charge_interrupted')),(9,10,ev('saga_lamp_drained')),(11,14,ev('saga_cancelled')),(15,16,intent('saga_lamp_open'))],
 'C5-S02':[(6,7,ev('battle_started'))],
 'C6-04':[(12,13,ev('battle_started')),(14,15,intent('saga_paper_bind')),(16,17,intent('saga_shadow_glow')),(18,19,ev('damage',target_side='player'))],
 'C6-11':[(2,3,intent('saga_repair_left_prepare')),(4,5,ev('actor_defeated',target_class='saga_anchor_left')),
     (6,7,intent('saga_warden_sweep')),(8,11,ev('actor_defeated',target_class='saga_anchor_right')),(12,13,ev('saga_anchor_repaired'))],
 'C6-S02':[(8,9,ev('status_applied',{'status.id':'slow'},target_side='player'))],
 'C6-S04':[(8,10,ev('battle_started'))],
 'C7-05':[(4,5,intent('saga_master_shallow')),(6,7,intent('saga_master_deep')),
     (8,9,ev('damage',actor_side='enemy')),(10,13,intent('saga_master_open'))],
 'C7-06':[(4,5,intent('saga_master_raise')),(6,7,intent('saga_master_command')),
     (8,9,intent('saga_master_erosion')),(10,13,ev('charge_interrupted'))],
 'C7-10':[(9,10,intent('saga_exit_crash')),(11,12,ev('actor_defeated',target_class='saga_exit_recoil')),(13,14,intent('saga_relay_wave'))],
 'C7-11':[(3,5,intent('saga_exit_crash')),(6,7,ev('actor_defeated',target_class='saga_exit_recoil')),(8,10,ev('actor_defeated',target_class='saga_relay_recoil'))],
 'C7-12':[(5,6,ev('actor_defeated',target_class='saga_exit_recoil')),(7,8,ev('actor_defeated',target_class='saga_relay_recoil')),(9,10,ev('actor_defeated',target_class='saga_relay_recoil'))],
 'C7-13':[(5,6,intent('saga_exit_crash')),(7,8,intent('saga_relay_wave')),(9,10,ev('actor_defeated',target_class='saga_exit_recoil'))],
}
# 保留导演说明原文在source_blocks；屏幕只显示其明确要求的标签与实际行动。
STAGE_TEXT={
 ('C6-01',5):'众人实际分趟转运六名成人患者；每趟在阵外病棚交接床位和药，最后由赵医工与苏合核对六张床、两位家属。',
 ('C7-21',5):'镜城：保存的薄荷影像。影像翻开手记，笔尖停在空白处。',
 ('C7-21',9):'真实城外。真正的薄荷在另一本手记上写下新的日期和营救路线。',
 ('C7-21',11):'镜城：薄荷本人被困。她坐在桌边，想在空白页写“我要出去”，只写出最初一笔。',
}


def bind_battle_events(scene):
    for line in scene['battle_lines']:
        if line['cue']=='defeat':
            binding=ev('battle_defeat')
        else:
            binding=next((event for start,end,event in BATTLE_EVENTS.get(scene['id'],[]) if start<=line['source_index']<=end),None)
            if binding is None: raise ValueError(f"未配置真实战斗事件：{scene['id']}:{line['source_index']}")
        line['event']=deepcopy(binding)
        line['once_per_battle']=True


def read_scenes():
    raw=SOURCE.read_text(encoding='utf-8')
    digest=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if digest != APPROVED_SHA:
        raise ValueError('批准对白已改变，必须重新核对分支行号及黄金测试后更新哈希')
    parts=re.split(r'(?m)^(C[2-7]-[A-Z]?\d+)｜([^\n]+)\n',raw)
    result=[]
    for pos in range(1,len(parts),3):
        sid,title,body=parts[pos:pos+3]
        body=body.split('附录 共用对白与交互文字')[0]
        body=re.split(r'(?m)^第[一二三四五六七]章 ',body)[0].rstrip()
        blocks=[]
        for n,text in enumerate(body.splitlines()):
            if not text.strip():
                continue
            kind='directive' if text.startswith('［') else 'choice' if re.match(r'^(选择|确认|取消)[A-D]\d?：',text) else 'dialogue' if '：' in text else 'heading'
            blocks.append({'source_index':n,'kind':kind,'text':text})
        result.append((sid,title,blocks))
    return result


def conditions_at(sid,n):
    result=[{}]
    for start,end,when in CONDITIONS.get(sid,[]):
        if start<=n<=end:
            candidates=when if isinstance(when,list) else [when]
            result=[{**before,**after} for before in result for after in candidates]
    return result


def playable_stage(text):
    # 作者的条件、实现指令留在source_blocks，避免被旁白误报成已发生事实。
    if any(word in text for word in ('玩家','出战','战斗','败北','胜利','战胜','战后','开战','重试','首次','再访','重复调查','路线','分支','汇合','进入C','进入 C','返回','登记','触发','变体','替换','追加','条件','若','时。','已修','待修','未修','已救','未救','救援完成','续监','已送行','送行时','已结','未结','已完成','完成后','选择','第七章','第一阶段','第二阶段','第三阶段','不改变','不新增','不记','不强制','不虚记','必须','应当','界面','本场','本段','两状态','两入口','两路','两线','购买','成交','钱不足','离开。','医馆待醒','医馆已救','患者','准备充分','全部准备','首次','神奇','固定已完成','地面撤离不足','保护目标','目标未完成','直接判','自由选','任选','自由组成','此救人步骤','转第三章','可进入第三章','本章可用交互','互斥回应','这句重复出于','不描写重症','画面不提前','不足时','提前在镜结','已获救者','取决于此前','不能写','第二段，')):
        return False
    return len(text)>14 and not text.startswith(('地点','浅面','深面','第一章','第五章','第三章','刀光镜面','水纹镜面','破罩窗口','压制成功','撑木即将','纸束收紧','纸束解开','灯影被击散','撤离完成','药械取齐'))


def render_block(sid,block):
    if block['kind']=='dialogue':
        speaker,text=block['text'].split('：',1)
    elif (sid,block['source_index']) in STAGE_TEXT:
        speaker,text='旁白',STAGE_TEXT[(sid,block['source_index'])]
    elif block['kind']=='directive' and block['source_index'] and playable_stage(block['text'][1:-1]):
        speaker,text='旁白',block['text'][1:-1]
    else:
        return []
    base={'speaker':speaker,'text':text,'source_index':block['source_index'],'source_kind':block['kind']}
    return [{**base,**({'when':when} if when else {})} for when in conditions_at(sid,block['source_index'])]


def make_scene(sid,title,blocks):
    chapter=int(sid[1]); suffix=sid.split('-')[1]
    numeric=suffix.isdigit()
    location=LOCATION_ROWS[chapter][0].split()[int(suffix)-1] if numeric else LOCATION_ROWS[chapter][1][suffix]
    kind='main' if sid in MAIN_ORDER[chapter] else 'side' if suffix.startswith('S') else 'ending' if numeric else 'revisit'
    metadata=blocks[0]['text'][1:-1]
    info=dict(part.split('：',1) for part in metadata.split('｜') if '：' in part)
    return {'id':sid,'title':title,'location':location,'source_location':info.get('地点',''),'kind':kind,
        'lines':[],'after_lines':[],'followup_lines':[],'battle_lines':[],'event_lines':{},'choices':[],
        'next':'','next_routes':[],'requires':deepcopy(REQUIRES.get(sid,{})),'effects':deepcopy(EFFECTS.get(sid,{})),
        'encounter_id':'','source_blocks':blocks,'source_metadata':info}


def split_choices(scene):
    sid=scene['id']; blocks=scene['source_blocks']
    headers=[b for b in blocks if re.match(r'^选择[A-D]：',b['text'])]
    spans=[]; seen={}
    for i,header in enumerate(headers):
        letter=header['text'][2].lower(); seen[letter]=seen.get(letter,0)+1
        cid=letter if seen[letter]==1 else letter+str(seen[letter])
        start=header['source_index']
        end=headers[i+1]['source_index'] if i+1<len(headers) else CHOICE_ENDS.get(sid,10000)
        if sid=='C2-16' and i==1: end=14
        if sid=='C7-R04': end={0:5,1:7,2:11,3:13,4:17,5:10000}[i]
        choice={'id':cid,'text':header['text'].split('：',1)[1],'source_index':start,
            'lines':[],'after_lines':[],'next':CHOICE_NEXT.get(sid,['']*len(headers))[i],
            'effects':deepcopy(CHOICE_EFFECTS.get((sid,cid),{})),'requires':conditions_at(sid,start)[0]}
        scene['choices'].append(choice); spans.append((start,end,choice))
    return spans


def route_lines(scene):
    sid=scene['id']; spans=split_choices(scene)
    battle=BATTLE_RANGES.get(sid)
    if battle and sid not in BRANCH_BATTLES:
        scene['encounter_id']='saga_'+sid.lower().replace('-','_')
    if sid in BRANCH_BATTLES:
        choice=next(c for c in scene['choices'] if c['id']==BRANCH_BATTLES[sid])
        choice['encounter_id']='saga_'+sid.lower().replace('-','_')
    cue='开战'; active_branch=None
    for block in scene['source_blocks']:
        n=block['source_index']
        if block['kind']=='directive': cue=block['text'][1:-1]
        if sid=='C6-04' and n>=12: active_branch=scene['choices'][0]
        else: active_branch=next((c for start,end,c in spans if start<n<end),None)
        if block['kind']=='choice': continue
        lines=render_block(sid,block)
        if not lines: continue
        target=active_branch or scene
        in_battle=battle and (sid not in BRANCH_BATTLES or (active_branch and active_branch['id']==BRANCH_BATTLES[sid]))
        if in_battle and battle[2] is not None and n>=battle[2]:
            scene['battle_lines'].extend({**line,'cue':'defeat','source_cue':cue} for line in lines)
        elif in_battle and n>=battle[1]:
            target['after_lines'].extend(lines)
        elif in_battle and n>=battle[0]:
            scene['battle_lines'].extend({**line,'cue':cue,'choice_id':active_branch['id'] if active_branch else ''} for line in lines)
        elif spans and n>=CHOICE_ENDS.get(sid,10000):
            scene['followup_lines'].extend(lines)
        else:
            target['lines'].extend(lines)
    return scene


def move_event_ranges(scene, ranges):
    for start,end,event in ranges:
        extracted=[]
        for field in ('lines','after_lines','followup_lines'):
            keep=[]
            for line in scene[field]:
                (extracted if start<=line['source_index']<=end else keep).append(line)
            scene[field]=keep
        scene['event_lines'].setdefault(event,[]).extend(extracted)


def make_chat(scene, groups):
    sid=scene['id']; all_lines=scene['lines']; scene['lines']=[]; scene['choices']=[]
    for i,(text,start,end,repeat_start,repeat_end) in enumerate(groups):
        flag='chat_seen_'+sid.lower().replace('-','_')+'_'+str(i+1)
        FLAGS[flag]=False
        lines=[]
        for line in all_lines:
            n=line['source_index']
            if start<=n<=end: lines.append({**line,'when':{**line.get('when',{}),flag:False}})
            if repeat_start<=n<=repeat_end: lines.append({**line,'when':{**line.get('when',{}),flag:True}})
        scene['choices'].append({'id':chr(97+i),'text':text,'lines':lines,'after_lines':[],'next':'','effects':{flag:True},'requires':{}})
    used={x['source_index'] for c in scene['choices'] for x in c['lines']}
    scene['lines']=[x for x in all_lines if x['source_index'] not in used]


def ending_choices(scene):
    scene['choices']=[]; scene['lines']=[]; scene['followup_lines']=[]
    # 每项先听代价，再以原文确认或取消；取消不提交任何状态。
    ranges=[('a',1,3,4,5,6,8,9,10,'C7-10','dawn'),('b',16,17,18,19,20,22,23,24,'C7-11','vigil'),
        ('c',26,27,28,29,30,32,33,34,'C7-12','shatter'),('d',36,37,39,40,42,44,45,46,'C7-13','eternal')]
    by_n={b['source_index']:b for b in scene['source_blocks']}
    def lines(a,b):
        return [line for n in range(a,b+1) if n in by_n for line in render_block(scene['id'],by_n[n])]
    for cid,head,first,last,confirm,accepted,cancel,cfirst,clast,target,ending in ranges:
        scene['choices'].append({'id':cid,'text':by_n[head]['text'].split('：',1)[1],'source_index':head,
            'lines':lines(first,last),'after_lines':[],'next':target,'effects':{'ending_plan':ending},
            'requires':deepcopy(DAWN) if cid=='a' else {},
            'confirmation':{'text':by_n[confirm]['text'].split('：',1)[1],'lines':lines(confirm+1,accepted),
                'cancel_text':by_n[cancel]['text'].split('：',1)[1],'cancel_lines':lines(cfirst,clast)}})
    scene['choices'][0]['locked_lines']=lines(13,14)


def configure_graph(scenes):
    for chapter,order in MAIN_ORDER.items():
        for index,sid in enumerate(order):
            scenes[sid]['next']=order[index+1] if index+1<len(order) else ''
            if index and not scenes[sid]['requires']:
                scenes[sid]['requires']={'done:'+order[index-1]:True}
    # 互斥段与任选实修不能成为共同必经门槛。
    scenes['C3-17']['requires']={'done:C3-15':True}
    scenes['C3-16']['kind']='side';scenes['C3-16']['next']=''
    for choice in scenes['C3-15']['choices']: choice['requires']={'ferry_repaired':False}
    scenes['C3-15']['choices'].append({'id':'c','text':'前往旧镜坊。','lines':[],'after_lines':[],'next':'C3-17','effects':{},'requires':{'ferry_repaired':True}})
    scenes['C3-15']['next']='C3-17'
    scenes['C5-10']['requires']={'done:C5-08':True}
    scenes['C6-02']['next']='C6-07'
    scenes['C6-02']['next_routes']=[{'requires':SENT,'next':'C6-03'},{'requires':SEALED,'next':'C6-04'}]
    scenes['C6-03']['next']='C6-07';scenes['C6-06']['next']='C6-07'
    for sid in ('C6-04','C6-05'):
        scenes[sid]['choices'][1]['next_routes']=[{'requires':{'done:C6-12':True},'next':'C6-12'}]
    scenes['C6-06']['next_routes']=[{'requires':{'done:C6-12':True},'next':'C6-12'}]
    scenes['C6-07']['requires']={'done:C6-02':True}
    scenes['C6-03']['requires']['done:C6-02']=True
    for sid in ('C6-04','C6-05','C6-06'): scenes[sid]['requires']['done:C6-02']=True
    scenes['C2-S02']['next']='C2-S03'
    scenes['C4-S02']['next']=''
    scenes['C4-S03']['next_routes']=[{'requires':{'done:C4-14':True},'next':'C4-R04'}]
    scenes['C5-S02']['next_routes']=[{'requires':{'done:C5-13':True},'next':'C5-S03'}]
    scenes['C5-S03']['next_routes']=[{'requires':{'done:C5-16':True},'next':'C5-R04'}]
    scenes['C4-R04']['choices'][0]['next_routes']=[{'requires':{'qiuan_rescued':False},'next':'C4-S03'}]
    scenes['C5-R04']['choices'][0]['next_routes']=[{'requires':{'family_rescued':False},'next':'C5-S02'}]
    scenes['C5-S02']['encounter_requires']={'done:C5-12':False}
    scenes['C2-17']['conditional_effects']=[{'requires':SENT,'effects':{'relics_posted':True}}]
    scenes['C5-13']['conditional_effects']=[{'requires':{'clinic_plan':'gentle'},'effects':{'clinic_awake':True}}]
    scenes['C7-R03']['next']='C6-12'
    scenes['C7-R02']['next']='C7-01'
    def revisit_action(sid,cid,text,target,requires):
        scenes[sid]['choices'].append({'id':cid,'text':text,'lines':[],'after_lines':[],'next':target,'effects':{},'requires':requires})
    revisit_action('C2-R03','rescue','带上引路灯，回染坊接人。','C2-S02',{'done:C2-12':True,'night_market_rescued':False})
    revisit_action('C3-R03','repair','开始修渡，完成空船试航。','C3-16',{'done:C3-14':True,'ferry_repaired':False})
    revisit_action('C3-R03','recover','回西仓核对物资。','C3-S02',{'done:C3-10':True,'warehouse_status':'pending'})
    revisit_action('C4-R03','rescue','回抛光间接邱安。','C4-S03',{'qiuan_rescued':False})
    revisit_action('C6-R03','temple_seal','回山解除朱印。','C6-04',{'resolution':'seal_monitoring','responsibility_resolved':False,'seal_removed':False})
    revisit_action('C6-R03','temple_sendoff','回山听完小夜的心愿。','C6-05',{'resolution':'seal_monitoring','responsibility_resolved':False,'seal_removed':True})
    revisit_action('C6-R03','clinic','去河外接醒两名患者。','C6-S01',{'clinic_awake':False})
    revisit_action('C6-R03','ferry','复核码头到石坡的退路。','C6-S03',{'evacuation_route_ready':False})
    revisit_action('C6-R03','alley','回后巷接宋婆和杜平。','C6-S04',{'alley_rescued':False})
    scenes['C7-R04']['choices'][4]['next_routes']=[{'requires':{'ending_plan':ending},'next':target} for ending,target in [('dawn','C7-10'),('vigil','C7-11'),('shatter','C7-12'),('eternal','C7-13')]]
    for sid,flag in [('C6-S03','evacuation_route_ready'),('C6-S04','alley_rescued')]:
        for line in scenes[sid]['lines']: line['when']={**line.get('when',{}),flag:False}
        for choice in scenes[sid]['choices']: choice['requires'][flag]=False
    for first,last,ending in [(10,15,'dawn'),(11,17,'vigil'),(12,19,'shatter'),(13,22,'eternal')]:
        path=[first, {10:14,11:16,12:18,13:20}[first], last] if first!=13 else [13,20,21,22]
        for i,n in enumerate(path):
            scene=scenes[f'C7-{n:02}']
            scene['kind']='main' if n==first else 'ending'
            scene['requires']={'ending_plan':ending,'done:C7-09':True} if i==0 else {'done:C7-'+str(path[i-1]).zfill(2):True,'ending_plan':ending}
            scene['next']=f'C7-{path[i+1]:02}' if i+1<len(path) else ''
        scenes[f'C7-{last:02}']['ending_id']=ending
    scenes['C7-10']['requires'].update(DAWN)
    # 重访能够再次选择暂缓事项；结果场只由前置实战/互动兑现一次。
    for sid in ('C3-15','C6-04','C6-05','C6-12','C6-13','C6-14','C7-01','C7-09','C4-R04','C5-R04'):
        scenes[sid]['repeatable']=True
    for chapter in range(2,8):
        for scene in scenes.values():
            if scene['id'].startswith(f'C{chapter}-R'):
                scene['repeatable']=True
    for sid in ('C2-S03','C3-S02','C4-S03','C6-S01','C6-S03','C6-S04'):
        scenes[sid]['repeatable']=True
    for sid in ('C2-S01','C4-S01','C5-S01'):
        scenes[sid]['repeatable']=True
    # 从出口选回访后，不能被已保存的“暂缓”选项永远锁死。
    for scene in scenes.values():
        if scene['choices'] and not scene.get('ending_id'):
            scene['repeatable']=True
    scenes['C3-S01']['repeatable']=False


def build_content():
    scenes={sid:route_lines(make_scene(sid,title,blocks)) for sid,title,blocks in read_scenes()}
    ending_choices(scenes['C7-09'])
    shops={'C2-R02':[(5,6,'shop_success'),(7,8,'shop_insufficient'),(9,11,'shop_cancel')],
        'C3-R02':[(5,6,'shop_success'),(7,8,'shop_insufficient'),(9,10,'shop_cancel')],
        'C4-R01':[(5,6,'shop_success'),(7,8,'shop_cancel'),(9,10,'shop_insufficient')],
        'C5-R01':[(5,6,'shop_success'),(7,8,'shop_cancel'),(9,10,'shop_insufficient')],
        'C6-R01':[(13,14,'shop_success'),(15,16,'revisit'),(17,99,'shop_cancel')],
        'C7-R01':[(6,7,'revisit'),(8,99,'shop_cancel')]}
    for sid,ranges in shops.items():
        scenes[sid]['service']='shop';move_event_ranges(scenes[sid],ranges)
        if sid in ('C6-R01','C7-R01'):
            for option in scenes[sid]['choices']:
                option['service']='shop' if option['id']=='a' else 'cancel'
    chats={
        'C2-R01':[('凛音与焰华',1,6,7,8),('薄荷与清明',9,13,14,15),('岑照与苏合',16,19,20,99)],
        'C3-R01':[('岑照与清明',1,5,6,7),('焰华与苏合',8,12,13,14),('凛音与薄荷',15,19,20,99)],
        'C4-R02':[('与姐妹说话',1,7,19,99),('薄荷与清明',8,12,19,99),('岑照与苏合',13,18,19,99)],
        'C5-R02':[('苏合与岑照',1,6,17,99),('焰华与凛音',7,11,17,99),('薄荷与清明',12,16,17,99)]}
    for sid,groups in chats.items():
        scenes[sid]['service']='rest';make_chat(scenes[sid],groups)
    for sid in ('C6-R02','C7-R02'): scenes[sid]['service']='rest'
    configure_graph(scenes)
    for scene in scenes.values(): bind_battle_events(scene)
    chapters=[]
    for n in range(2,8):
        required=[sid for sid in MAIN_ORDER[n] if sid not in ('C3-16','C5-09','C6-03','C6-04','C6-05','C6-06')]
        chapter={'id':n,'title':TITLES[n],'entry':f'C{n}-01','exit':MAIN_ORDER[n][-1],
            'locations':LOCATIONS[n],'main_order':MAIN_ORDER[n],'required_scenes':required,
            'scenes':[scene for sid,scene in scenes.items() if sid.startswith(f'C{n}-')]}
        chapters.append(chapter)
    all_flags=deepcopy(FLAGS)
    for scene in scenes.values():
        for effects in [scene['effects']]+[c['effects'] for c in scene['choices']]:
            for key,value in effects.items():
                all_flags.setdefault(key,False if isinstance(value,bool) else '')
    return {'schema_version':1,'title':'逢魔退治帖：七章连续主线','source':str(SOURCE.relative_to(ROOT)),
        'source_sha256':APPROVED_SHA,'outline_sha256':hashlib.sha256(OUTLINE.read_bytes()).hexdigest(),
        'contract':{'conditions':'AND 等值；缺失布尔=false；done: 与 battle:由模型派生',
            'flow':'lines → choice.lines → confirmation → battle → after_lines → followup_lines → effects',
            'effects':'场次/选项完成且所需战斗胜利后一起提交；conditional_effects按完成前状态判断',
            'routes':'next_routes第一匹配优先；否则next；支线空next返回原主线，不推进章节',
            'events':'event_lines只由对应真实事件触发；battle_lines只由cue对应实战事件触发',
            'source':'source_blocks保留批准原文全部内容；不得直接整体拼接播放'},
        'flags':all_flags,'ending_requirements':{'dawn':DAWN,'vigil':{'dream_intake_stopped':True,'temporary_ward_verified':True},'shatter':{},'eternal':{}},
        'chapters':chapters}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true',help='只核对已提交JSON，不写文件')
    args=parser.parse_args()
    data=build_content(); text=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding='utf-8')!=text:
            raise SystemExit('剧情导出不同步：请运行 tools/campaign/build_saga_story.py')
        print('批准正文137场、条件图及导出字节一致')
    else:
        OUTPUT.parent.mkdir(parents=True,exist_ok=True);OUTPUT.write_text(text,encoding='utf-8')
        print(f'已导出 {sum(len(c["scenes"]) for c in data["chapters"])} 场至 {OUTPUT.relative_to(ROOT)}')

if __name__=='__main__':
    main()
