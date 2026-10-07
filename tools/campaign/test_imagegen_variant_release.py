"""二十八形态公开素材：冻结运行字节、独立分组、形态选择和发布闭包。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "assets/effects/imagegen_spells"

def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

release = module("release_pack")
projection = module("sanitize_runtime_metadata")
verification = module("verify_runtime_projection")
fixture = module("test_runtime_projection_release")
EXPECTED = {'rinne-heavy_slash': {'skill': 'heavy_slash', 'form': 'rinne', 'name': '重斩', 'atlas_sha256': 'fcf4e1aea2686ad582b82b7485b62626c62fa95bfc5fb6288953d97b2f5ab932', 'frame_values_sha256': 'a562d0a71e63cb6c1c807ddac4296e913e93005b5632cc08e21592c9656d24cb', 'phases': {'cast': [1, 2, 3, 4], 'contact_damage': [5, 6, 7, 8], 'recovery': [9, 10, 11, 12], 'conditional_precision': [13, 14, 15, 16]}}, 'rinne-armor_break': {'skill': 'armor_break', 'form': 'rinne', 'name': '破甲斩', 'atlas_sha256': '02d8cba8edec9528cb1273c83cfc00c953995d5d00b63aa1a2ebee75a74b3886', 'frame_values_sha256': 'd3d469c5953f0f27dd23413d223227de3813c43d363ebfb31017e43ed77f03e0', 'phases': {'cast': [1, 2, 3, 4], 'contact_damage': [5, 6, 7, 8], 'armor_break_status': [9, 10, 11, 12], 'conditional_weaken': [13, 14, 15, 16]}}, 'rinne-sweep': {'skill': 'sweep', 'form': 'rinne', 'name': '横扫', 'atlas_sha256': 'e974bba0b531b7e79d7e4118e4276c92935cee45b702cbf2c27de0aceed7966f', 'frame_values_sha256': 'd3d469c5953f0f27dd23413d223227de3813c43d363ebfb31017e43ed77f03e0', 'phases': {'cast_sweep': [1, 2, 3, 4], 'contact_damage': [5, 6, 7, 8], 'conditional_slow': [9, 10, 11, 12], 'armor_break_consumed': [13, 14, 15, 16]}}, 'rinne-battle_spirit': {'skill': 'battle_spirit', 'form': 'rinne', 'name': '战意', 'atlas_sha256': 'c1756fb2686f1fe8a46360032eed806751f261892a3a4346845d044ad2259000', 'frame_values_sha256': '32f326cb625ac6fa10639d0e4258399c8834159405a09e3aec27df2eb91ab6b9', 'phases': {'cast': [1, 2, 3, 4], 'battle_spirit_apply': [5, 6, 7, 8], 'recovery': [9, 10, 11, 12], 'battle_spirit_status': [13, 14, 15, 16]}}, 'homura_sword-heavy_slash': {'skill': 'heavy_slash', 'form': 'homura_sword', 'name': '重斩', 'atlas_sha256': 'b9c93c51f87a57fec689332cec0a39793af3059631f02cd6c2b79f35d06f5781', 'frame_values_sha256': 'e48e4578c8dca83d9f32b1e6dcd5e07987ca6a69d15b5772edae49e5ed962d91', 'phases': {'cast': [1, 2, 3, 4], 'contact_damage': [5, 6, 7, 8], 'recovery': [9, 10, 11, 12, 13, 14, 15, 16]}}, 'homura_sword-armor_break': {'skill': 'armor_break', 'form': 'homura_sword', 'name': '破甲斩', 'atlas_sha256': '9abc4b4443e7454b265f11a4d3573eb912684b9780342ed08b3c987c7d0bdb0f', 'frame_values_sha256': 'd3d469c5953f0f27dd23413d223227de3813c43d363ebfb31017e43ed77f03e0', 'phases': {'cast': [1, 2, 3, 4], 'contact_damage': [5, 6, 7, 8], 'armor_break_status': [9, 10, 11, 12], 'conditional_burn': [13, 14, 15, 16]}}, 'homura_sword-sweep': {'skill': 'sweep', 'form': 'homura_sword', 'name': '横扫', 'atlas_sha256': '794e9bb72c0fd393dfe2629c8c1fbdfc4f8468f1bae8abac1c904d8d23b1ac18', 'frame_values_sha256': '2c2c7ed7c2cafc31de63e602e58db98dc4482a47ad509a73aac814d5a32871b8', 'phases': {'cast_sweep': [1, 2, 3, 4], 'contact_damage': [5, 6, 7, 8], 'recovery': [9, 10, 11, 12], 'conditional_armor_break': [13, 14, 15, 16]}}, 'homura_sword-battle_spirit': {'skill': 'battle_spirit', 'form': 'homura_sword', 'name': '战意', 'atlas_sha256': '4ae8a79434e1fd99bbefade75b3b0741eb0887db50e7db9a4bf75ab01ab9dd4f', 'frame_values_sha256': 'f11d2a8c794c987293d09eee23d2372a3a52e31674f98a4cc6ba744ee09a1b4a', 'phases': {'cast': [1, 2, 3, 4], 'battle_spirit_apply': [5, 6, 7, 8], 'battle_spirit_status': [9, 10, 11, 12], 'conditional_shield': [13, 14, 15, 16]}}, 'cover': {'skill': 'cover', 'form': 'guard', 'name': '掩护', 'atlas_sha256': 'eea7ba89d4f65a3ea6205b062ab093dc1b1b00809c0005dbc31af681befe187b', 'frame_values_sha256': 'bf1763b032ce88c79e8f1d46f5330e4d10d582729daf66650be97484f9c85ae9', 'phases': {'cast': [1, 2, 3, 4], 'cover_link': [5, 6, 7, 8], 'cover_status': [9, 10, 11, 12], 'cover_redirected': [13, 14, 15, 16]}}, 'shield_bash': {'skill': 'shield_bash', 'form': 'guard', 'name': '盾击', 'atlas_sha256': '1b9de7ed66088cdd915e7e4d44a90dadab2b2a09855182b85e6454cd00225083', 'frame_values_sha256': '80ad122f2770085c7504392a4438bbda24ff6fa2b4adac000305382869fcc047', 'phases': {'cast': [1, 2, 3, 4], 'damage_recovery': [5, 6, 7, 8], 'charge_interrupt': [9, 10, 11, 12], 'weaken_status': [13, 14, 15, 16]}}, 'iron_wall': {'skill': 'iron_wall', 'form': 'guard', 'name': '铁壁', 'atlas_sha256': 'ccd7ea29448e748f6674bb5ec3568788056f8cd6e7a949687db8b75c9d63f7be', 'frame_values_sha256': 'd0d3bdb3d66c4259ac41edcad7a86f15b3c50a4bcf6e6e510425d314ed4583cd', 'phases': {'cast': [1, 2, 3, 4], 'shield_apply': [5, 6, 7, 8], 'shield_sustain': [9, 10, 11, 12], 'cleanse': [13, 14, 15, 16]}}, 'taunt': {'skill': 'taunt', 'form': 'guard', 'name': '挑衅', 'atlas_sha256': 'ae922b66f9b278e5bc6c18dce9b42a55ae52847333f5f91be4bb27e27b4a34e2', 'frame_values_sha256': '48cc673bf8dc28e152f2f90263c03e8e11523f4a7a91cc8d909a4333ceb9d7c6', 'phases': {'cast': [1, 2, 3, 4], 'sound_travel': [5, 6, 7, 8], 'taunt_status': [9, 10, 11, 12], 'conditional_weaken': [13, 14, 15, 16]}}, 'mark': {'skill': 'mark', 'form': 'mint', 'name': '标记', 'atlas_sha256': 'a65bad0bc509f48aabe2604b80fcb0d11555eabcc3d60d7c2becbf7680ea0e93', 'frame_values_sha256': '687a79351074bb7ac8a0bde422075ae77b193e62b0d0c6e54e6ead2db5b3dc81', 'phases': {'cast': [1, 2, 3, 4], 'travel': [5, 6, 7, 8], 'mark_apply': [9, 10, 11, 12], 'mark_sustain': [13, 14, 15, 16]}}, 'hunt': {'skill': 'hunt', 'form': 'mint', 'name': '猎杀', 'atlas_sha256': '261deeeff4991ce8814bd70c03505fbe1c44c2457fcb6ded4146ae6b05281653', 'frame_values_sha256': 'd6ff6a6f0aa61cfa7f252f4e37ff9c94e30706402c25519d7fe9125520386eb1', 'phases': {'cast': [1, 2, 3, 4], 'travel': [5, 6, 7, 8], 'damage_recovery': [9, 10, 11, 12], 'mark_consumed': [13, 14], 'mp_refund': [15, 16]}}, 'ambush': {'skill': 'ambush', 'form': 'mint', 'name': '奇袭', 'atlas_sha256': '91f9f28831a52cb6e06eb15ff40402bfcda64e9eabaaca568ea1c83aa49fcc48', 'frame_values_sha256': '687a79351074bb7ac8a0bde422075ae77b193e62b0d0c6e54e6ead2db5b3dc81', 'phases': {'cast': [1, 2, 3, 4], 'travel': [5, 6, 7, 8], 'damage_recovery': [9, 10, 11, 12], 'mark_apply_sustain': [13, 14, 15, 16]}}, 'smoke_screen': {'skill': 'smoke_screen', 'form': 'mint', 'name': '烟幕', 'atlas_sha256': 'ce700ab240c48b42bac8745ec094a468b973665641381f44985d94916fc98e77', 'frame_values_sha256': '44bbf0fce2d5eb9878b94bb7c0801ab35a2709dd647bc5df968c5d760f181434', 'phases': {'cast': [1, 2, 3, 4], 'shield_apply': [5, 6, 7, 8], 'shield_sustain': [9, 10, 11, 12], 'battle_spirit': [13, 14, 15, 16]}}}

def entries(registry):
    for skill, entry in registry["effects"].items():
        for form, variant in entry.get("variants", {"": entry}).items():
            yield skill, form, variant

def read(path):
    return json.loads(path.read_text())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

class ImagegenVariantRelease(unittest.TestCase):
    def test_twenty_four_skills_have_twenty_eight_explicit_variants(self):
        registry = read(FOLDER / "registry.json")
        self.assertEqual(24, len(registry["effects"]))
        self.assertEqual(28, len(list(entries(registry))))
        self.assertIs(registry["production_renderer_enabled"], False)
        for skill in ("heavy_slash", "armor_break", "sweep", "battle_spirit"):
            self.assertEqual({"variants"}, set(registry["effects"][skill]))
            self.assertEqual({"rinne", "homura_sword"}, set(registry["effects"][skill]["variants"]))
        for skill, form, entry in entries(registry):
            self.assertIs(entry["approved_for_runtime"], True)
            self.assertIs(entry["gameplay_qa_pending"], True)
            self.assertEqual(.5, entry["runtime_scale"])
            self.assertEqual(256, entry["display_size_px"])

    def test_sixteen_frozen_variants_keep_atlas_registration_and_separate_phase_pixels(self):
        registry = read(FOLDER / "registry.json")
        for key, expected in EXPECTED.items():
            with self.subTest(variant=key):
                path = FOLDER / key / "manifest.json"
                self.assertTrue(path.exists(), "缺少已冻结形态运行清单")
                if not path.exists(): continue
                value = read(path)
                self.assertEqual(expected["skill"], value["skill_id"])
                self.assertEqual(expected["form"], value["form_id"])
                self.assertEqual(expected["name"], value["skill_name"])
                self.assertEqual(expected["phases"], value["phases"])
                self.assertEqual(set(value["phases"]), set(value["required_phases"]))
                self.assertEqual(set(value["phases"]), set(value["phase_groups"]))
                self.assertEqual({"id":"physical_skill_visual_v1", "version":1, "form":expected["form"], "ability_id":expected["skill"], "variant_key":key}, value["visual_event_contract"])
                self.assertTrue(value["event_layers"], "已绑定层须有完整有限事件合同")
                self.assertEqual({"cover_redirected"} if key == "cover" else set(), set(value["reaction_layers"]))
                self.assertEqual(expected["atlas_sha256"], digest(FOLDER / value["runtime_atlas"]))
                self.assertEqual(expected["atlas_sha256"], value["runtime_atlas_sha256"])
                fields = [{k:f[k] for k in ("frame","anchor_runtime_px","atlas_native_xywh","nominal_duration_ms")} for f in value["frames"]]
                self.assertEqual(expected["frame_values_sha256"], hashlib.sha256(json.dumps(fields,sort_keys=True,separators=(",",":")).encode()).hexdigest())
                atlas = Image.open(FOLDER / value["runtime_atlas"]).convert("RGBA")
                self.assertEqual((1024, 1024), atlas.size)
                for phase, ids in value["phases"].items():
                    group = value["phase_groups"][phase]
                    self.assertEqual(ids, group["activation_frames"] + group["loop_frames"])
                    self.assertEqual("physical_skill_visual_v1", group["binding"])
                    for index in ids:
                        frame = value["frames"][index-1]
                        self.assertEqual(phase, frame["phase"])
                        x,y,w,h = [int(v*.5) for v in frame["atlas_native_xywh"]]
                        self.assertIsNotNone(atlas.crop((x,y,x+w,y+h)).getchannel("A").getbbox())
                entry = registry["effects"][expected["skill"]]
                if "variants" in entry: entry = entry["variants"][expected["form"]]
                self.assertEqual(digest(path), entry["manifest_sha256"])

    def test_dependency_closure_contains_only_registered_variants(self):
        registry = read(FOLDER / "registry.json")
        self.assertEqual(28, len(list(entries(registry))))
        expected = {"assets/effects/imagegen_spells/registry.json"}
        for _, _, entry in entries(registry):
            path = entry["manifest"].removeprefix("res://")
            manifest = read(ROOT / path)
            expected.update({path, "assets/effects/imagegen_spells/" + manifest["runtime_atlas"]})
        self.assertEqual(57, len(expected))
        self.assertEqual(expected, release.imagegen_effect_sources(ROOT))

    def test_projection_roundtrip_keeps_variants_and_drops_nested_private_extras(self):
        registry = read(FOLDER / "registry.json")
        self.assertEqual(28, len(list(entries(registry))))
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fixture.RuntimeProjectionRelease().raw_source(root / "source")
            source = root / "source"
            target = source / FOLDER.relative_to(ROOT)
            shutil.rmtree(target)
            shutil.copytree(FOLDER, target)
            registry["effects"]["heavy_slash"]["private_note"] = "private fixture"
            for skill, form, entry in entries(registry):
                path = source / entry["manifest"].removeprefix("res://")
                manifest = read(path)
                manifest["source_prompt"] = "private fixture"
                if "visual_event_contract" in manifest:
                    manifest["visual_event_contract"]["private_note"] = "private fixture"
                    for layer in manifest["event_layers"].values():
                        layer["private_note"] = "private fixture"
                        for segment in layer["phase_segments"]:
                            segment["private_note"] = "private fixture"
                        if "precast_evidence" in layer:
                            layer["precast_evidence"]["private_note"] = "private fixture"
                    for layer in manifest["reaction_layers"].values():
                        layer["private_note"] = "private fixture"
                if "phase_groups" in manifest:
                    next(iter(manifest["phase_groups"].values()))["private_note"] = "private fixture"
                fixture.write(path, manifest)
                entry["manifest_sha256"] = digest(path)
                entry["private_note"] = "private fixture"
            fixture.write(target / "registry.json", registry)
            (target / "unregistered-export.png").write_bytes(b"private fixture")
            candidate = root / "candidate"
            shutil.copytree(source, candidate)
            before = fixture.snapshot(source)
            result = projection.sanitize(source, candidate)
            self.assertEqual(before, fixture.snapshot(source))
            self.assertEqual(28, len(result["effects"]))
            self.assertTrue(verification.verify(source, candidate)["passed"])
            self.assertFalse((candidate / target.relative_to(source) / "unregistered-export.png").exists())
            public_registry = read(candidate / target.relative_to(source) / "registry.json")
            self.assertEqual({"variants"}, set(public_registry["effects"]["heavy_slash"]))
            for _, _, entry in entries(public_registry):
                self.assertNotIn("private_note", entry)
                manifest = read(candidate / entry["manifest"].removeprefix("res://"))
                self.assertNotIn("source_prompt", manifest)
                original = read(FOLDER / Path(entry["manifest"]).parent.name / "manifest.json")
                if "visual_event_contract" in original:
                    for field in ("visual_event_contract", "event_layers", "reaction_layers"):
                        self.assertEqual(original[field], manifest.get(field), "运行合同不能丢失或携带制作旁记：" + field)
                for group in manifest.get("phase_groups", {}).values():
                    self.assertEqual({"activation_frames", "loop_frames", "binding"}, set(group))
            again = root / "again"
            shutil.copytree(candidate, again)
            projection.sanitize(candidate, again)
            self.assertEqual(fixture.snapshot(candidate), fixture.snapshot(again))
            self.assertEqual(57, len(release.imagegen_effect_sources(candidate)))
            path = candidate / "assets/effects/imagegen_spells/rinne-heavy_slash/manifest.json"
            value = read(path); value["form_id"] = "homura_sword"; fixture.write(path, value)
            with self.assertRaises(ValueError): verification.verify(source, candidate)

    def test_projection_verifier_rejects_missing_physical_semantics(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            fixture.RuntimeProjectionRelease().raw_source(source)
            target = source / FOLDER.relative_to(ROOT)
            shutil.rmtree(target)
            shutil.copytree(FOLDER, target)
            candidate = Path(temp) / "candidate"
            shutil.copytree(source, candidate)
            projection.sanitize(source, candidate)
            self.assertTrue(verification.verify(source, candidate)["passed"])
            cases = [("hunt", "event_layers", "mp_refund", "positive_actual"),
                     ("rinne-heavy_slash", "event_layers", "conditional_precision", "precast_evidence"),
                     ("cover", "reaction_layers", "cover_redirected", "requires")]
            for variant, field, layer, attribute in cases:
                with self.subTest(variant=variant):
                    path = candidate / FOLDER.relative_to(ROOT) / variant / "manifest.json"
                    original = read(path)
                    changed = json.loads(json.dumps(original))
                    self.assertIn(field, changed)
                    self.assertIn(attribute, changed[field][layer])
                    changed[field][layer].pop(attribute)
                    fixture.write(path, changed)
                    with self.assertRaises(ValueError): verification.verify(source, candidate)
                    fixture.write(path, original)
            path = candidate / FOLDER.relative_to(ROOT) / "cover/manifest.json"
            original = read(path)
            self.assertIn("visual_event_contract", original)
            original.pop("visual_event_contract")
            fixture.write(path, original)
            with self.assertRaises(ValueError): verification.verify(source, candidate)

    def test_variant_dependency_closure_rejects_missing_wrong_or_swapped_forms(self):
        for change in ("missing", "wrong", "swapped", "atlas_escape", "skill_as_default"):
            with tempfile.TemporaryDirectory() as temp, self.subTest(change=change):
                root = Path(temp)
                folder = root / FOLDER.relative_to(ROOT)
                shutil.copytree(FOLDER, folder)
                registry = read(folder / "registry.json")
                shared = registry["effects"]["heavy_slash"]
                if change == "missing": shared["variants"].pop("homura_sword")
                elif change == "wrong": shared["variants"]["guard"] = shared["variants"].pop("rinne")
                elif change == "swapped": shared["variants"]["rinne"] = shared["variants"]["homura_sword"]
                elif change == "skill_as_default": registry["effects"]["heavy_slash"] = shared["variants"]["rinne"]
                else:
                    path = folder / "rinne-heavy_slash/manifest.json"
                    value = read(path); value["runtime_atlas"] = "rinne-heavy_slash/../unregistered.png"
                    fixture.write(path, value)
                    shared["variants"]["rinne"]["manifest_sha256"] = digest(path)
                fixture.write(folder / "registry.json", registry)
                with self.assertRaises(ValueError): release.imagegen_effect_sources(root)

if __name__ == "__main__":
    unittest.main()
