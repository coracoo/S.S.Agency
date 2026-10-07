"""发布投影可读取完整暂存源、已公开源及两者混合，校验失败时不落盘。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("projection", Path(__file__).with_name("sanitize_runtime_metadata.py"))
projection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(projection)
verify_spec = importlib.util.spec_from_file_location("verify_projection", Path(__file__).with_name("verify_runtime_projection.py"))
verify_projection = importlib.util.module_from_spec(verify_spec)
verify_spec.loader.exec_module(verify_projection)
FORMS = ("controller", "guard", "healer", "homura_mage", "homura_sword", "mint", "rinne")
SKILLS = ("firebolt", "flame_wave", "ice_arrow", "burn_brand")


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def snapshot(root):
    return {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob("*") if path.is_file()}


class RuntimeProjectionRelease(unittest.TestCase):
    def raw_source(self, root):
        root.mkdir()
        (root / "project.godot").write_text("config_version=5\n")
        for form in FORMS:
            prefix = "assets/chars/pixel/" + form + "/video_actions/"
            atlas = root / (prefix + "sheets/runtime.png")
            atlas.parent.mkdir(parents=True)
            atlas.write_bytes(("runtime atlas fixture " + form).encode())
            value = {"character_id":form, "identity_id":form, "form_id":form, "dir":"res://" + prefix + "frames/",
                     "canvas":{"w":8,"h":8,"anchor":[4,7],"content_height_px":6,"height_m":1.7},
                     "move_speed_mps":2.6,"layers":[],"mirror_allowed":True,
                     "anims":{action:{"frames":["idle"],"durations_ms":[100],"loop":action != "attack"}
                              for action in ("idle","walk","attack")},
                     "packed_frames":{"idle":{"atlas":"res://"+prefix+"sheets/runtime.png","atlas_size":[8,8],"region":[0,0,8,8],"offset":[0,0]}},
                     "scene_integration":{"contact_metadata":"res://"+prefix+"contacts.json"},
                     "runtime_derivative":{"target_body_height_px":6,"fixed_scale":1,"fixed_offset":[0,0],"logical_canvas":[8,8],"anchor":[4,7],"source_manifest":"private fixture"},
                     "texture_groups":{"shared":["res://"+prefix+"sheets/runtime.png"]}}
            write(root / (prefix + "manifest.json"), value)
            write(root / (prefix + "contacts.json"), {"schema_version":1,"character_id":form,"canvas":[8,8],"anchor":[4,7],
                  "frames":{"idle":{"sha256":projection.sha(atlas),"contacts":[{"point":[4,7],"width_px":2,"strength":.55,"kind":"root"}]}}})
        folder = root / "assets/effects/imagegen_spells"
        registry = {"schema_version":1,"asset_root":"res://assets/effects/imagegen_spells","generation_route":"image_gen.imagegen",
                    "production_renderer_enabled":False,"effects":{}}
        receipt = {"skills":[]}
        for skill in SKILLS:
            atlas = folder / skill / "runtime.png"
            atlas.parent.mkdir(parents=True)
            atlas.write_bytes(("effect atlas fixture " + skill).encode())
            path = folder / skill / "manifest.json"
            value = {"skill_id":skill,"generator":"image_gen.imagegen","source_prompt":"private fixture",
                     "runtime_atlas":skill+"/runtime.png","runtime_atlas_sha256":projection.sha(atlas),"frame_count":1,
                     "phases":{"cast":[1],"travel":[1],"hit":[1]},
                     "frames":[{"frame":1,"phase":"cast","recovery_tail":False,"anchor_runtime_px":[4,4],
                                "atlas_native_xywh":[0,0,16,16],"nominal_duration_ms":100}]}
            write(path, value)
            registry["effects"][skill] = {"manifest":"res://assets/effects/imagegen_spells/"+skill+"/manifest.json",
                                          "qa_receipt":"res://assets/effects/imagegen_spells/qa_acceptance.json",
                                          "approved_for_runtime":True,"gameplay_qa_pending":True,"runtime_scale":.5,"display_size_px":8,"particles":[]}
            receipt["skills"].append({"skill_id":skill,"manifest_sha256":projection.sha(path),"runtime_atlas_sha256":projection.sha(atlas),"runtime_grid_cells_match_export":True})
        write(folder / "registry.json", registry)
        write(folder / "qa_acceptance.json", receipt)
        return root

    def public_source(self, root):
        raw = self.raw_source(root / "raw")
        public = root / "public"
        shutil.copytree(raw, public)
        before = snapshot(raw)
        result = projection.sanitize(raw, public)
        self.assertTrue(result["source_receipts_verified"])
        self.assertEqual(before, snapshot(raw))
        return raw, public

    def test_complete_public_tree_projects_again_without_new_independent_qa(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _raw, source = self.public_source(root)
            candidate = root / "candidate"
            shutil.copytree(source, candidate)
            before = snapshot(source)
            result = projection.sanitize(source, candidate)
            self.assertEqual(before, snapshot(source))
            self.assertEqual(before, snapshot(candidate))
            self.assertFalse(result["source_receipts_verified"])
            self.assertEqual(2, result["source_registry_schema"])
            self.assertEqual(sorted(SKILLS), result["source_integrity_verified_skills"])
            self.assertTrue(verify_projection.verify(source, candidate)["passed"])

    def test_mixed_public_tree_and_one_new_character_stage_preserves_action(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw, source = self.public_source(root)
            name = "assets/chars/pixel/controller/video_actions/manifest.json"
            staged = projection.read(raw / name)
            staged["anims"]["attack"]["durations_ms"] = [321]
            staged["anims"]["attack"]["events"] = {"impact":123}
            write(source / name, staged)
            candidate = root / "candidate"
            shutil.copytree(source, candidate)
            before = snapshot(source)
            result = projection.sanitize(source, candidate)
            self.assertEqual(before, snapshot(source))
            public = projection.read(candidate / name)
            self.assertEqual([321], public["anims"]["attack"]["durations_ms"])
            self.assertEqual({"impact":123}, public["anims"]["attack"]["events"])
            self.assertNotIn("runtime_derivative", public)
            self.assertIn("runtime_registration", public)
            self.assertFalse(result["source_receipts_verified"])
            self.assertTrue(verify_projection.verify(source, candidate)["passed"])
            for form in FORMS[1:]:
                path = "assets/chars/pixel/"+form+"/video_actions/manifest.json"
                self.assertEqual((source/path).read_bytes(), (candidate/path).read_bytes())

    def test_schema2_mixed_effects_preserve_structured_layers_and_omit_private_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw, source = self.public_source(root)
            prefix = "assets/effects/imagegen_spells/"
            registry = projection.read(source / (prefix + "registry.json"))
            path = source / (prefix + "firebolt/manifest.json")
            manifest = projection.read(raw / (prefix + "firebolt/manifest.json"))
            manifest["schema_version"] = 1
            manifest["required_phases"] = ["cast", "travel", "hit"]
            manifest["placement"] = {"cast":"caster_focus", "travel_origin":"caster_focus", "travel_target":"target_body", "travel_mode":"projectile", "private_note":"omit"}
            layer = {"phase":"hit", "event_type":"damage", "target":"event_target", "placement":"target_body", "lifetime":"action", "activation_frames":[1], "loop_frames":[]}
            manifest["event_layers"] = {"damage":dict(layer, private_note="omit")}
            write(path, manifest)
            registry["effects"]["firebolt"]["manifest_sha256"] = projection.sha(path)
            write(source / (prefix + "registry.json"), registry)
            candidate = root / "candidate"
            shutil.copytree(source, candidate)
            before = snapshot(source)
            result = projection.sanitize(source, candidate)
            public = projection.read(candidate / path.relative_to(source))
            self.assertEqual(manifest["required_phases"], public.get("required_phases"))
            self.assertEqual({k:v for k,v in manifest["placement"].items() if k != "private_note"}, public.get("placement"))
            self.assertEqual({"damage":layer}, public.get("event_layers"))
            self.assertNotIn("source_prompt", public)
            self.assertNotIn("generator", public)
            self.assertFalse(result["source_receipts_verified"])
            self.assertEqual(before, snapshot(source))
            self.assertTrue(verify_projection.verify(source, candidate)["passed"])
            for field in ("required_phases", "placement", "event_layers"):
                with self.subTest(field=field):
                    changed = json.loads(json.dumps(public))
                    changed.pop(field)
                    write(candidate / path.relative_to(source), changed)
                    with self.assertRaisesRegex(ValueError, "运行投影改变"):
                        verify_projection.verify(source, candidate)
            write(candidate / path.relative_to(source), public)

    def test_schema2_mixes_receipt_backed_full_entry_with_minimal_entries(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw, source = self.public_source(root)
            prefix = "assets/effects/imagegen_spells/"
            registry = projection.read(source / (prefix + "registry.json"))
            raw_registry = projection.read(raw / (prefix + "registry.json"))
            registry["effects"]["firebolt"] = raw_registry["effects"]["firebolt"]
            write(source / (prefix + "registry.json"), registry)
            for name in ("firebolt/manifest.json", "qa_acceptance.json"):
                shutil.copyfile(raw / (prefix + name), source / (prefix + name))
            candidate = root / "candidate"
            shutil.copytree(source, candidate)
            before = snapshot(source)
            try:
                result = projection.sanitize(source, candidate)
            except ValueError as error:
                self.fail("schema2须接受有独立收据的完整条目：" + str(error))
            self.assertEqual(["firebolt"], result["source_receipt_verified_skills"])
            self.assertFalse(result["source_receipts_verified"], "不能把部分收据复验说成全体重新QA")
            self.assertEqual(before, snapshot(source))
            self.assertTrue(verify_projection.verify(source, candidate)["passed"])
            self.assertFalse((candidate / (prefix + "qa_acceptance.json")).exists())

    def test_schema2_manifest_and_atlas_tampering_fail_before_any_write(self):
        for target in ("manifest.json", "runtime.png"):
            with tempfile.TemporaryDirectory() as temporary, self.subTest(target=target):
                root = Path(temporary)
                _raw, source = self.public_source(root)
                path = source / "assets/effects/imagegen_spells/firebolt" / target
                if target.endswith("json"):
                    value = projection.read(path); value["frames"][0]["nominal_duration_ms"] += 1
                    write(path, value)
                else:
                    path.write_bytes(path.read_bytes()+b"changed")
                candidate = root / "candidate"
                shutil.copytree(source, candidate)
                before = snapshot(source)
                with self.assertRaises(ValueError):
                    projection.sanitize(source, candidate)
                self.assertEqual(before, snapshot(source))
                self.assertEqual(before, snapshot(candidate))

    def test_v1_independent_receipt_remains_mandatory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.raw_source(root / "raw")
            path = source / "assets/effects/imagegen_spells/qa_acceptance.json"
            receipt = projection.read(path); receipt["skills"][0]["manifest_sha256"] = "changed"
            write(path, receipt)
            candidate = root / "candidate"
            shutil.copytree(source, candidate)
            before = snapshot(source)
            with self.assertRaisesRegex(ValueError, "收据不匹配"):
                projection.sanitize(source, candidate)
            self.assertEqual(before, snapshot(source))
            self.assertEqual(before, snapshot(candidate))

    def test_nested_production_fields_are_removed_from_canvas_contacts_and_layers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.raw_source(root / "raw")
            folder = source / "assets/chars/pixel/controller/video_actions"
            manifest = projection.read(folder / "manifest.json")
            manifest["canvas"]["source_path"] = "private canvas fixture"
            manifest["layers"] = [{"frames":[manifest["packed_frames"]["idle"]["atlas"]],
                                   "amplitude_px":0,"period_s":1,"root_y":1,"full_motion_y":7,"z_index":0,
                                   "note":"private layer fixture"}]
            write(folder / "manifest.json", manifest)
            contacts = projection.read(folder / "contacts.json")
            contacts["frames"]["idle"]["contacts"][0]["note"] = "private contact fixture"
            write(folder / "contacts.json", contacts)
            candidate = root / "candidate"
            shutil.copytree(source, candidate)
            before = snapshot(source)
            projection.sanitize(source, candidate)
            output = candidate / folder.relative_to(source)
            public = projection.read(output / "manifest.json")
            self.assertEqual({"w":8,"h":8,"anchor":[4,7],"content_height_px":6,"height_m":1.7}, public["canvas"])
            self.assertEqual({key:value for key,value in manifest["layers"][0].items() if key != "note"}, public["layers"][0])
            self.assertEqual({"point":[4,7],"width_px":2,"strength":.55,"kind":"root"},
                             projection.read(output / "contacts.json")["frames"]["idle"]["contacts"][0])
            self.assertEqual(before, snapshot(source))
            self.assertTrue(verify_projection.verify(source, candidate)["passed"])

    def test_both_source_contracts_preserve_production_off_requirement(self):
        for schema in (1, 2):
            with tempfile.TemporaryDirectory() as temporary, self.subTest(schema=schema):
                root = Path(temporary)
                raw, public = self.public_source(root)
                source = raw if schema == 1 else public
                path = source / "assets/effects/imagegen_spells/registry.json"
                registry = projection.read(path); registry["production_renderer_enabled"] = True
                write(path, registry)
                candidate = root / "candidate"
                shutil.copytree(source, candidate)
                before = snapshot(source)
                with self.assertRaises(ValueError):
                    projection.sanitize(source, candidate)
                self.assertEqual(before, snapshot(source))
                self.assertEqual(before, snapshot(candidate))


if __name__ == "__main__":
    unittest.main()
