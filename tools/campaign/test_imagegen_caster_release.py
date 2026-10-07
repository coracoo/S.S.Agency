"""十二法术公开运行合同：批准字节、独立事件层、发布闭包和生产门禁。"""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "assets/effects/imagegen_spells"
# 只保留已审核运行PNG与帧数值的完整性指纹，不公开原稿或制作记录。
EXPECTED = {'heal': {'atlas_sha256': 'e2375e60e3b677b3069624381467922ecef3633136929e9286898281f740668d', 'frame_values_sha256': '9e6e54fc60012b63ed0dc64cc166d407bb33b8f254204bcb6bb40c251ab6dae8', 'frame_count': 16}, 'cleanse': {'atlas_sha256': 'e1388bd968cf7bac1fb97dbffade5b5545fe7dd2abbf72d9859699f776ea2b6a', 'frame_values_sha256': '94a67488e8e439f7c1a1fe36fbaf8dfe79bcf172635d6dc4d279b8c33ccbe53b', 'frame_count': 16}, 'holy_shield': {'atlas_sha256': '397d11916057e683fd344a13fbecb20d915ed487259a135f6daeb569f07d0610', 'frame_values_sha256': '964e451e4555e403d5d2ef88ce6cdcd045bb7b1d1acc2fe432e3f4e6afa911b0', 'frame_count': 16}, 'group_heal': {'atlas_sha256': 'c8ace0021461d9dc22991fe852a5737a1e69f6b5532b1c0d949960a8b7aac763', 'frame_values_sha256': '7552790b08a1773d2791e6a8ee076894b8062a9704734b1d076f8fcc4546efe2', 'frame_count': 12}, 'slow': {'atlas_sha256': 'c4c7c8c49e182d38b48b23afbf453224b981dc15bd29bb268faf5cdeea28576f', 'frame_values_sha256': '21f23525653422c786dc16e2f671860d7bf054045ac164cb67066e418e699766', 'frame_count': 16}, 'seal': {'atlas_sha256': 'a63abff0b442093bc6bf62e4112b1fe565d5b26111f973cbaae188129536d90f', 'frame_values_sha256': '3d7d75c5570e735f08e3f54773d331177c55edd47ae4fb87b0eb65ccd1fff0d0', 'frame_count': 16}, 'weaken': {'atlas_sha256': '3b912a6f8e96c10c5d289329b9f7d5f5ec88ae5540f5654bd95e077ec165bcf4', 'frame_values_sha256': '29c37c78b31e78929a830484a13d88ed1a48037920ca973516922131055d91ec', 'frame_count': 16}, 'magic_break': {'atlas_sha256': 'dc4dc7e0deb8324ef62ad1f250e1d4c3848e36fcd28107be6f20ca0769912f41', 'frame_values_sha256': '29c37c78b31e78929a830484a13d88ed1a48037920ca973516922131055d91ec', 'frame_count': 16}}
MAGE_MANIFESTS = {"firebolt":"6a5cecd39b858bb3595649e05b88f1c185d6e398f017a4990d7d03ac5a28defd", "flame_wave":"538909cc19d0bd5634e0168e5f54149831cba609ac84996a32b47fd39e2ddb84", "ice_arrow":"5216ca26b3f6f9e46e861ac6f871f07994931725c58870e335244612490f932b", "burn_brand":"c6ead7fa245cd92f87d7d56c15f5fc97a6e0cb08dea8b36c18d46e358d34b294"}


def read(skill):
    return json.loads((FOLDER / skill / "manifest.json").read_text())


class CasterRuntimeRelease(unittest.TestCase):
    def test_all_twelve_registered_with_unchanged_mage_contracts_and_closed_gates(self):
        registry = json.loads((FOLDER / "registry.json").read_text())
        self.assertTrue(set(EXPECTED) | set(MAGE_MANIFESTS) <= set(registry["effects"]))
        self.assertIs(registry["production_renderer_enabled"], False)
        for skill in set(EXPECTED) | set(MAGE_MANIFESTS):
            entry = registry["effects"][skill]
            self.assertIs(entry["gameplay_qa_pending"], True)
            self.assertIs(entry["approved_for_runtime"], True)
            self.assertEqual(.5, entry["runtime_scale"])
            self.assertEqual(256, entry["display_size_px"])
            if skill in MAGE_MANIFESTS:
                self.assertEqual(MAGE_MANIFESTS[skill], hashlib.sha256((FOLDER/skill/"manifest.json").read_bytes()).hexdigest())

    def test_new_atlases_and_each_ordered_region_anchor_duration_match_approved_values(self):
        for skill, expected in EXPECTED.items():
            with self.subTest(skill=skill):
                self.assertTrue((FOLDER/skill/"manifest.json").is_file(), "缺少已审核运行登记")
                if not (FOLDER/skill/"manifest.json").is_file(): continue
                value = read(skill)
                self.assertEqual(expected["frame_count"], value["frame_count"])
                self.assertEqual(expected["atlas_sha256"], hashlib.sha256((FOLDER/value["runtime_atlas"]).read_bytes()).hexdigest())
                fields = [{k:f[k] for k in ["frame","anchor_runtime_px","atlas_native_xywh","nominal_duration_ms"]} for f in value["frames"]]
                self.assertEqual(expected["frame_values_sha256"], hashlib.sha256(json.dumps(fields,sort_keys=True,separators=(",",":")).encode()).hexdigest())

    def test_conditional_layers_have_independent_actual_event_gates_and_clocks(self):
        for skill in EXPECTED:
            self.assertTrue((FOLDER/skill/"manifest.json").is_file(), "缺少独立事件层")
            if not (FOLDER/skill/"manifest.json").is_file(): return
        shield = read("holy_shield")
        self.assertNotIn("hit", shield["phases"])
        self.assertEqual([9,10,11,12], shield["phases"]["holy_shield_edge"])
        self.assertEqual([13,14,15,16], shield["phases"]["awake_clarity"])
        self.assertEqual("shield_applied", shield["event_layers"]["holy_shield_edge"]["event_type"])
        self.assertEqual("shield", shield["event_layers"]["holy_shield_edge"]["lifetime"])
        self.assertEqual("awake", shield["event_layers"]["awake_clarity"]["status_id"])
        self.assertEqual("status", shield["event_layers"]["awake_clarity"]["lifetime"])
        heal = read("heal")["event_layers"]
        self.assertEqual("actual", heal["heal_impact"]["positive_payload"])
        self.assertEqual("shield_applied", heal["guard_life_shield"]["event_type"])
        cleanse = read("cleanse")["event_layers"]
        self.assertEqual({"reason":"cleanse"}, cleanse["cleanse_removal"]["payload_equals"])
        self.assertEqual("actual", cleanse["rejuvenation_heal"]["positive_payload"])
        self.assertEqual("status_removed", cleanse["rejuvenation_heal"]["requires_event"]["event_type"])
        self.assertTrue(cleanse["rejuvenation_heal"]["requires_event"]["same_action"])
        self.assertTrue(cleanse["rejuvenation_heal"]["requires_event"]["same_target"])
        slow = read("slow")["event_layers"]
        self.assertEqual("slow", slow["slow_apply_sustain"]["status_id"])
        self.assertEqual("magic_break", slow["conditional_magic_break"]["status_id"])
        seal = read("seal")["event_layers"]
        self.assertEqual({"stun_apply_sustain","charge_interrupt","mp_refund"}, set(seal))
        self.assertEqual("stun", seal["stun_apply_sustain"]["status_id"])
        self.assertEqual("charge_interrupted", seal["charge_interrupt"]["event_type"])
        self.assertEqual("mp_restored", seal["mp_refund"]["event_type"])
        self.assertEqual("source", seal["mp_refund"]["target"])
        self.assertEqual("actual", seal["mp_refund"]["positive_payload"])
        self.assertEqual(1, seal["mp_refund"]["max_instances_per_action"])
        for skill in ["weaken","slow","seal"]:
            self.assertNotIn("hit", read(skill)["phases"])
            self.assertFalse(any(layer["event_type"] == "damage" for layer in read(skill)["event_layers"].values()))
        magic = read("magic_break")["event_layers"]
        self.assertEqual("damage", magic["damage_recovery"]["event_type"])
        self.assertEqual("status_applied", magic["magic_break_status"]["event_type"])

    def test_normalized_layers_partition_source_frames_and_preserve_tail_flags(self):
        for skill in EXPECTED:
            with self.subTest(skill=skill):
                self.assertTrue((FOLDER/skill/"manifest.json").is_file())
                if not (FOLDER/skill/"manifest.json").is_file(): continue
                value = read(skill)
                phases = value["phases"]
                sequence = [i for phase, ids in phases.items() if phase != "recovery_tail" for i in ids]
                self.assertEqual(list(range(1,value["frame_count"]+1)), sequence)
                self.assertEqual([i["frame"] for i in value["frames"] if i["recovery_tail"]], phases.get("recovery_tail", []))
                self.assertEqual(set(phases)-{"recovery_tail"}, set(value["required_phases"]))
                for name, layer in value["event_layers"].items():
                    self.assertEqual(name, layer["phase"])
                    self.assertEqual(phases[name], layer["activation_frames"]+layer["loop_frames"])
                    self.assertNotIn("effect_ignored", layer.values())
                    if layer["lifetime"] == "status": self.assertTrue(layer["status_id"])
                self.assertEqual("caster_focus", value["placement"]["cast"])
                if skill in ("heal","group_heal"):
                    self.assertEqual("target_ground", value["event_layers"]["heal_impact"]["placement"])


if __name__ == "__main__":
    unittest.main()
