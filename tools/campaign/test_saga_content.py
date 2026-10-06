"""七章批准正文与可执行分支的内容契约，不运行/修改玩家存档。"""
import importlib.util
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / 'tools/campaign/build_saga_story.py'
OUTPUT = ROOT / 'data/campaign/saga.json'
SOURCE = ROOT / 'docs/story/review/v1/逢魔退治帖_七章完整对白_v1.txt'
BATTLES = {'C2-03','C2-07','C2-09','C2-12','C2-S02','C3-03','C3-07','C3-10','C3-S01','C3-S02','C4-04','C4-09','C4-S02','C5-09','C5-12','C5-S02','C6-04','C6-11','C6-S02','C6-S04','C7-05','C7-06','C7-10','C7-11','C7-12','C7-13'}


def all_lines(value):
    if isinstance(value, dict):
        if 'speaker' in value and 'text' in value:
            yield value
        for key, child in value.items():
            if key not in ('source_blocks', 'source_text'):
                yield from all_lines(child)
    elif isinstance(value, list):
        for child in value:
            yield from all_lines(child)


def visible(lines, flags):
    return [x['text'] for x in lines if all(flags.get(k, False) == v for k,v in x.get('when', {}).items())]


class SagaContentTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(BUILDER.exists(), '尚未实现批准对白导出器')
        spec = importlib.util.spec_from_file_location('build_saga_story', BUILDER)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.data = self.module.build_content()
        self.scenes = {s['id']:s for c in self.data['chapters'] for s in c['scenes']}

    def test_late_shops_route_purchase_and_decline_to_real_services(self):
        for sid in ("C6-R01", "C7-R01"):
            choices = {option["id"]: option for option in self.scenes[sid]["choices"]}
            self.assertEqual("shop", choices["a"].get("service"), sid)
            self.assertEqual("cancel", choices["b"].get("service"), sid)

    def test_all_137_approved_scene_ids_are_preserved(self):
        expected = set(re.findall(r'(?m)^(C[2-7]-[A-Z]?\d+)｜', SOURCE.read_text()))
        self.assertEqual(137, len(expected))
        self.assertEqual(expected, set(self.scenes))
        self.assertEqual(list(range(2,8)), [c['id'] for c in self.data['chapters']])
        for scene in self.scenes.values():
            self.assertIn(scene['kind'], ['main','side','revisit','ending'])
            for field in ('title','location','lines','choices','next','requires','effects','encounter_id','source_blocks'):
                self.assertIn(field, scene)

    def test_every_approved_spoken_line_has_executable_destination(self):
        for scene in self.scenes.values():
            expected = {x['source_index'] for x in scene['source_blocks'] if x['kind']=='dialogue'}
            actual = {x['source_index'] for x in all_lines(scene) if x.get('source_kind')=='dialogue'}
            self.assertEqual(expected, actual, scene['id'])
            source = {x['source_index']:x['text'] for x in scene['source_blocks']}
            for line in all_lines(scene):
                if line.get('source_kind') == 'dialogue':
                    self.assertEqual(source[line['source_index']], line['speaker']+'：'+line['text'], scene['id'])

    def test_graph_references_and_regions_are_valid(self):
        for chapter in self.data['chapters']:
            self.assertIn(chapter['entry'], self.scenes)
            self.assertIn(chapter['exit'], self.scenes)
            for sid in chapter['required_scenes']:
                self.assertIn(sid,self.scenes)
            for scene in chapter['scenes']:
                self.assertIn(scene['location'], chapter['locations'])
                nodes = [scene]+scene['choices']
                for node in nodes:
                    targets = [node.get('next','')]+[r['next'] for r in node.get('next_routes',[])]
                    for target in targets:
                        self.assertTrue(not target or target in self.scenes,(scene['id'],target))
                    for key, expected in node.get('requires',{}).items():
                        self.assertIsInstance(expected,(str,bool,int,float))
                        if key.startswith('done:'):
                            self.assertIn(key[5:],self.scenes)

    def test_all_real_battles_are_gated_before_victory(self):
        actual=set()
        for sid,scene in self.scenes.items():
            if scene['encounter_id'] or any(c.get('encounter_id') for c in scene['choices']):
                actual.add(sid)
                nodes=[scene]+scene['choices']
                self.assertTrue(any(n.get('after_lines') for n in nodes),sid)
                for n in nodes:
                    if n.get('encounter_id'):
                        self.assertEqual('saga_'+sid.lower().replace('-','_'),n['encounter_id'])
        self.assertEqual(BATTLES,actual)
        self.assertTrue(self.scenes['C2-12']['battle_lines'])
        self.assertNotIn('不用再打了。纸里没有能回答的人。', visible(self.scenes['C2-12']['lines'],{}))
        self.assertIn('不用再打了。纸里没有能回答的人。', visible(self.scenes['C2-12']['after_lines'],{}))

    def test_letters_are_posted_then_receipted_not_inferred(self):
        self.assertEqual('C2-17',self.scenes['C2-14']['next'])
        self.assertEqual('C2-15',self.scenes['C2-17']['next'])
        self.assertTrue(self.scenes['C2-17']['effects']['letter_posted'])
        self.assertNotIn('letter_receipt_received',self.scenes['C2-17']['effects'])
        self.assertTrue(self.scenes['C6-03']['requires']['letter_posted'])
        self.assertTrue(self.scenes['C6-03']['effects']['letter_receipt_received'])

    def test_dead_sayo_cannot_be_resurrected(self):
        for sid in ['C6-04','C6-05','C6-06']:
            self.assertEqual('seal_monitoring',self.scenes[sid]['requires']['resolution'])
            self.assertFalse(self.scenes[sid]['requires']['responsibility_resolved'])
        sent=visible(self.scenes['C2-17']['lines'],{'resolution':'sendoff'})
        sealed=visible(self.scenes['C2-17']['lines'],{'resolution':'seal_monitoring'})
        self.assertFalse(any('小夜仍未获送行' in x for x in sent))
        self.assertFalse(any('送行已完成' in x for x in sealed))
        self.assertEqual([], [x for x in all_lines(self.scenes['C6-03']) if x['speaker']=='小夜'])

    def test_rescue_variants_do_not_play_together(self):
        scene=self.scenes['C2-15']
        saved=''.join(visible(scene['lines'],{'night_market_rescued':True}))
        missing=''.join(visible(scene['lines'],{'night_market_rescued':False}))
        self.assertIn('午后夜市能先开几家',saved)
        self.assertNotIn('还困在后巷',saved)
        self.assertIn('还困在后巷',missing)
        self.assertNotIn('午后夜市能先开几家',missing)
        self.assertTrue(self.scenes['C2-S02']['effects']['night_market_rescued'])
        self.assertNotIn('night_market_rescued',self.scenes['C2-12']['effects'])
        self.assertEqual({'done:C5-12':False},self.scenes['C5-S02']['encounter_requires'])

    def test_four_endings_require_confirmation_and_keep_costs(self):
        choices=self.scenes['C7-09']['choices']
        self.assertEqual(['a','b','c','d'],[c['id'] for c in choices])
        self.assertEqual({'responsibility_resolved':True,'clinic_awake':True,'evacuation_route_ready':True,'alley_rescued':True,'segment_network_ready':True},choices[0]['requires'])
        self.assertEqual(['C7-10','C7-11','C7-12','C7-13'],[c['next'] for c in choices])
        for c in choices:
            self.assertIn('confirmation',c)
            self.assertTrue(c['confirmation']['cancel_lines'])
        self.assertEqual({'dawn','vigil','shatter','eternal'},set(s['ending_id'] for s in self.scenes.values() if s.get('ending_id')))
        yes=''.join(visible(self.scenes['C7-21']['lines'],{'evacuation_route_ready':True}))
        no=''.join(visible(self.scenes['C7-21']['lines'],{'evacuation_route_ready':False}))
        self.assertIn('城里那个不是我',yes)
        self.assertNotIn('别替我',yes)
        self.assertIn('别替我',no)
        self.assertNotIn('城里那个不是我',no)

    def test_mandatory_rescue_exits_and_deferred_ferry(self):
        self.assertEqual('C3-17',self.scenes['C3-15']['choices'][1]['next'])
        self.assertTrue(self.scenes['C3-16']['effects']['ferry_repaired'])
        self.assertEqual('C4-S03',self.scenes['C4-R04']['choices'][0]['next_routes'][0]['next'])
        self.assertEqual('C5-S02',self.scenes['C5-R04']['choices'][0]['next_routes'][0]['next'])
        self.assertEqual('C6-12',self.scenes['C7-01']['choices'][1]['next'])
        self.assertTrue(self.scenes['C6-S03']['choices'][0]['effects']['evacuation_route_ready'])
        self.assertNotIn('evacuation_route_ready',self.scenes['C3-16']['effects'])

    def test_deferred_repairs_and_temple_responsibility_have_revisit_actions(self):
        self.assertEqual('side',self.scenes['C3-16']['kind'])
        self.assertEqual('',self.scenes['C3-16']['next'])
        self.assertTrue(any(c['next']=='C3-16' for c in self.scenes['C3-R03']['choices']))
        self.assertTrue(any(c['next']=='C2-S02' for c in self.scenes['C2-R03']['choices']))
        self.assertTrue(any(c['next']=='C6-04' for c in self.scenes['C6-R03']['choices']))
        self.assertTrue(any(c['next']=='C6-05' for c in self.scenes['C6-R03']['choices']))
        self.assertTrue(any(c['next']=='C3-17' and c['requires']=={'ferry_repaired':True} for c in self.scenes['C3-15']['choices']))

    def test_completed_rescues_only_show_finite_revisit(self):
        for sid,flag in [('C6-S03','evacuation_route_ready'),('C6-S04','alley_rescued')]:
            scene=self.scenes[sid]
            self.assertTrue(all(c['requires'].get(flag) is False for c in scene['choices']))
            self.assertEqual([],visible(scene['lines'],{flag:True}))
            self.assertTrue(visible(scene['followup_lines'],{flag:True}))

    def test_retry_responses_wait_for_player_choice(self):
        scene=self.scenes['C7-R04']
        self.assertNotIn('换好位置，再来。',visible(scene['lines'],{'retry_stage':1}))
        self.assertIn('换好位置，再来。',visible(scene['choices'][0]['lines'],{'retry_stage':1}))
        self.assertTrue(scene['choices'][4].get('next_routes'))

    def test_chat_revisits_do_not_repeat_another_pairs_conversation(self):
        scene=self.scenes['C5-R02'];choice=scene['choices'][0]
        repeated=''.join(visible(choice['lines'],{'chat_seen_c5_r02_1':True}))
        self.assertNotIn('那把本子合上',repeated)
        self.assertIn('该吃的吃',repeated)
        first=''.join(visible(scene['choices'][2]['lines'],{'chat_seen_c5_r02_3':False}))
        self.assertIn('那把本子合上',first)

    def test_author_routing_instructions_are_never_rendered(self):
        forbidden=['转第三章','可进入第三章','本章可用交互','互斥回应','此处为短护送遭遇','这句重复出于','不描写重症','画面不提前']
        for sid,scene in self.scenes.items():
            for line in all_lines(scene):
                if line.get('source_kind')=='directive':
                    self.assertFalse(any(x in line['text'] for x in forbidden),(sid,line['text']))

    def test_all_initial_routes_can_reach_each_ending_without_missing_required_scene(self):
        for resolution in ('sendoff','seal_monitoring'):
            for clinic in ('gentle','isolate'):
                for ending,ending_choice in [('dawn','a'),('vigil','b'),('shatter','c'),('eternal','d')]:
                    flags=dict(self.data['flags']);flags['resolution']=resolution
                    completed=set();current='C2-01';resume='';steps=0
                    def context():
                        return {**flags,**{'done:'+x:True for x in completed}}
                    def matches(req):
                        return all(context().get(k,False)==v for k,v in req.items())
                    def commit(scene,choice=None):
                        before=context()
                        effects=dict(scene['effects'])
                        for rule in scene.get('conditional_effects',[]):
                            if all(before.get(k,False)==v for k,v in rule['requires'].items()):effects.update(rule['effects'])
                        if choice:effects.update(choice['effects'])
                        flags.update(effects);completed.add(scene['id'])
                    while current and steps<250:
                        steps+=1;scene=self.scenes[current]
                        self.assertTrue(matches(scene['requires']),(resolution,clinic,ending,current,scene['requires']))
                        if current=='C6-13' and ending=='dawn':
                            # 终战前实做所有可补救，不凭空添加完成标记。
                            for sid in (['C6-S02'] if not flags['clinic_awake'] else [])+['C6-S03','C6-S04']:
                                side=self.scenes[sid]
                                self.assertTrue(matches(side['requires']),(sid,side['requires']))
                                choice=side['choices'][0] if side['choices'] else None
                                commit(side,choice)
                        available=[c for c in scene['choices'] if matches(c.get('requires',{}))]
                        choice=None
                        if available:
                            want={'C2-16':'b','C3-06':'a','C3-15':'b','C3-17':'a','C4-05':'a','C4-R04':'a',
                                  'C5-08':'a' if clinic=='gentle' else 'b','C5-R04':'a','C6-04':'a' if ending=='dawn' else 'b',
                                  'C6-05':'a','C6-14':'a','C7-01':'a','C7-09':ending_choice}.get(current,available[0]['id'])
                            choice=next((c for c in available if c['id']==want),available[0])
                        target=choice or scene
                        next_id=target.get('next','')
                        for route in target.get('next_routes',[]):
                            if matches(route['requires']):next_id=route['next'];break
                        detour=choice is not None and scene['kind']=='main' and (next_id==current or (next_id and self.scenes[next_id]['kind'] in ('side','revisit')))
                        if detour:resume=current
                        else:commit(scene,choice)
                        if scene.get('ending_id'):
                            self.assertEqual(ending,scene['ending_id']);break
                        if not next_id and scene['kind'] in ('side','revisit'):
                            next_id=resume;resume=''
                        current=next_id
                    self.assertLess(steps,250,(resolution,clinic,ending,current))
                    self.assertTrue(scene.get('ending_id'),(resolution,clinic,ending,current))
                    self.assertTrue(flags['family_rescued'])
                    self.assertTrue(flags['qiuan_rescued'])
                    self.assertTrue(flags['patients_outside'])
                    self.assertTrue(flags['night_market_rescued'])
                    self.assertEqual(ending=='dawn' or resolution=='sendoff',flags['responsibility_resolved'])
                    if resolution=='sendoff':
                        self.assertTrue(flags['letter_receipt_received'])
                        self.assertNotIn('C6-04',completed)
                        self.assertNotIn('C6-05',completed)
                        self.assertNotIn('C6-06',completed)

    def test_battle_dialogue_has_real_event_bindings(self):
        for scene in self.scenes.values():
            for line in scene['battle_lines']:
                self.assertIn('event',line,(scene['id'],line['cue']))
                self.assertTrue(line['event']['type'])
                self.assertTrue(line['once_per_battle'])
        lamp=self.scenes['C5-12']['battle_lines']
        success=next(x for x in lamp if x['cue']=='成功打断。')
        fail=next(x for x in lamp if x['cue']=='未成功打断。')
        self.assertEqual('charge_interrupted',success['event']['type'])
        self.assertEqual('saga_lamp_drained',fail['event']['type'])
        mirror=self.scenes['C4-09']['battle_lines']
        self.assertEqual('p_mage',next(x for x in mirror if '场外' in x['cue'])['event']['excluded_actor'])

    def test_eternal_ending_labels_real_person_and_saved_image_explicitly(self):
        scene=self.scenes['C7-21']
        yes=''.join(visible(scene['lines'],{'evacuation_route_ready':True}))
        no=''.join(visible(scene['lines'],{'evacuation_route_ready':False}))
        self.assertIn('镜城：保存的薄荷影像',yes)
        self.assertNotIn('镜城：薄荷本人被困',yes)
        self.assertIn('镜城：薄荷本人被困',no)
        self.assertNotIn('镜城：保存的薄荷影像',no)

    def test_deferred_rescue_prompts_never_route_to_locked_post_boss_scene(self):
        # 复现：合面镜已胜、邱安未救，旧求援A曾将active_scene导向禁止进入的C4-S02。
        cases=[('C2-S01','C2-04','C2-12','night_market_rescued'),
               ('C4-S01','C4-01','C4-09','qiuan_rescued'),
               ('C5-S01','C5-01','C5-12','family_rescued')]
        for source,unlock,boss,rescued in cases:
            for boss_done in (False,True):
                for after_handoff in (False,True):
                    flags={**self.data['flags'],'done:'+unlock:True,'done:'+boss:boss_done,rescued:False,
                           'done:C4-10':boss_done and after_handoff,'done:C5-13':boss_done and after_handoff}
                    def matches(req):return all(flags.get(k,False)==v for k,v in req.items())
                    scene=self.scenes[source]
                    if not matches(scene['requires']):continue
                    choice=scene['choices'][0]
                    self.assertTrue(matches(choice['requires']))
                    flags.update(choice['effects'])
                    target=choice['next']
                    for route in choice.get('next_routes',[]):
                        if matches(route['requires']):target=route['next'];break
                    self.assertTrue(matches(self.scenes[target]['requires']),(source,boss_done,after_handoff,target))
        # 旧镜廊威胁已消失时，不再播放“镜里刀影”旧求援；战后抬架由S03负责。
        self.assertFalse(self.scenes['C4-S01']['requires'].get('done:C4-09',True))
        self.assertEqual({'done:C4-10':True},self.scenes['C4-S03']['requires'])

    def test_late_temple_rescue_returns_to_city_hub_without_replaying_defeated_boss(self):
        # 城区巡守已胜再回山，补办/再次暂缓都不能倒走07→11卡在已完成Boss。
        flags={**self.data['flags'],'resolution':'seal_monitoring','done:C6-12':True}
        for sid,cid in [('C6-04','b'),('C6-05','b'),('C6-06',None)]:
            scene=self.scenes[sid]
            node=next(c for c in scene['choices'] if c['id']==cid) if cid else scene
            target=node['next']
            for route in node.get('next_routes',[]):
                if all(flags.get(k,False)==v for k,v in route['requires'].items()):target=route['next'];break
            self.assertEqual('C6-12',target,(sid,cid))

    def test_warehouse_choice_cannot_be_replayed_to_undo_saved_supplies(self):
        scene=self.scenes['C3-S01']
        flags={**self.data['flags'],'done:C3-05':True,'done:C3-S01':True,'done:C3-07':False,'warehouse_status':'protected'}
        self.assertFalse(all(flags.get(k,False)==v for k,v in scene['requires'].items()))
        flags['warehouse_status']='pending'
        self.assertFalse(all(flags.get(k,False)==v for k,v in scene['requires'].items()))
        self.assertFalse(scene['repeatable'])
        # 舍货后的清障回收仍是独立有代价的战后入口。
        self.assertEqual({'done:C3-10':True},self.scenes['C3-S02']['requires'])

    def test_committed_output_is_deterministic(self):
        self.assertTrue(OUTPUT.exists(),'尚未生成剧情数据')
        self.assertEqual(self.data,json.loads(OUTPUT.read_text()))
        self.assertEqual(self.data,self.module.build_content())

if __name__ == '__main__':
    unittest.main()
