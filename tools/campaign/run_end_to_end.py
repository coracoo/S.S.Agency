#!/usr/bin/env python3
"""独立模型E2E；先核验临时user://，每个安全检查点启动新的Godot进程。"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

PROJECT = Path(__file__).resolve().parents[2]
SCRIPT = "res://tools/campaign/test_end_to_end.gd"
ERRORS = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")
PREFIX = "CAMPAIGN_E2E_RESULT:"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path, help="证据必须放在仓库外")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--policy", choices=("direct_damage", "defensive_counter", "control_burst"), default="direct_damage")
    parser.add_argument("--timeout", type=int, default=120, help="单一进程安全超时，不能作为通过")
    parser.add_argument("--pack", type=Path, help="从空目录只加载指定发布PCK；测试工具留在包外")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output == PROJECT or output.is_relative_to(PROJECT):
        parser.error("E2E证据不得写进仓库")
    engine = shutil.which(args.godot)
    if not engine:
        parser.error(f"未找到Godot：{args.godot}")
    output.mkdir(parents=True, exist_ok=True)
    pack = args.pack.resolve() if args.pack else None
    if pack and not pack.is_file():
        parser.error("指定发布PCK不存在")
    # 包外测试仅替换测试工具依赖，不复制/覆盖任何生产资源到res://。
    runtime_project = output / "empty-runtime" if pack else PROJECT
    e2e_script = SCRIPT
    isolation_script = "res://tools/rpg/test_environment.gd"
    if pack:
        runtime_project.mkdir(exist_ok=True)
        if any(runtime_project.iterdir()):
            parser.error("PCK运行根必须为空，防止宿主资源回退")
        helper_root = output / "external-test-tools"
        helper_root.mkdir(exist_ok=True)
        policies = helper_root / "strategy_policies.gd"
        policies.write_text((PROJECT / "tools/rpg/strategy_policies.gd").read_text().replace("class_name RpgStrategyPolicies\n", ""))
        helper = helper_root / "test_end_to_end.gd"
        helper.write_text((PROJECT / "tools/campaign/test_end_to_end.gd").read_text().replace("res://tools/rpg/strategy_policies.gd", policies.as_posix()))
        e2e_script = helper.as_posix()
        isolation_script = (PROJECT / "tools/rpg/test_environment.gd").as_posix()
    commands = []
    report = {"kind": "packed_model_driven_e2e" if pack else "model_driven_e2e", "pack": str(pack) if pack else None, "manual_gui": "not_run_by_this_runner", "status": "pass", "started_utc": datetime.now(timezone.utc).isoformat(), "policy": args.policy, "scenarios": {}, "commands": commands}

    def invoke(env: dict, arguments: list[str], destination: Path) -> tuple[int, str]:
        command = [engine, "--headless", "--path", str(runtime_project), *(["--main-pack", str(pack)] if pack else []), *arguments]
        started = time.monotonic()
        try:
            process = subprocess.run(command, env=env, encoding="utf-8", errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout)
            code, text = process.returncode, process.stdout
        except subprocess.TimeoutExpired as exc:
            code = 124
            text = (exc.stdout or b"").decode("utf-8", errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
            text += "\nFAIL: Godot process timeout; incomplete, no success claim\n"
        destination.write_text(text, encoding="utf-8")
        commands.append({"argv": command, "exit": code, "seconds": round(time.monotonic() - started, 3), "log": str(destination)})
        return code, text

    @contextmanager
    def isolated(name: str):
        location = output / name
        location.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="ssa-campaign-e2e-") as directory:
            root = Path(directory).resolve()
            env = os.environ.copy()
            for variable, relative in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")):
                target = root / relative
                target.mkdir()
                env[variable] = str(target)
            env["RPG_TEST_ROOT"] = str(root)
            env["RPG_TEST_ISOLATED"] = "0"
            for variable in ("RPG_SWEEP_MODE", "RPG_SWEEP_OUTPUT", "RPG_APPROACH_OUTPUT"):
                env.pop(variable, None)
            code, text = invoke(env, ["--script", isolation_script], location / "00-isolation.log")
            matches = [line.removeprefix("RPG_ISOLATION_OK:").strip() for line in text.splitlines() if line.startswith("RPG_ISOLATION_OK:")]
            valid = code == 0 and not ERRORS.search(text) and len(matches) == 1 and Path(matches[0]).resolve() != root and Path(matches[0]).resolve().is_relative_to(root)
            if not valid:
                yield None, location, {"status": "blocked", "blockers": ["实际user://未获验证，已阻止测试"], "steps": []}
                return
            env["RPG_TEST_ISOLATED"] = "1"
            scenario = {"status": "pass", "verified_user_dir": matches[0], "steps": []}
            try:
                yield env, location, scenario
            finally:
                save = Path(matches[0]) / "campaign_v1" / "slot_01.json"
                if save.exists():
                    shutil.copyfile(save, location / "final-slot.json")

    def run_mode(env: dict, directory: Path, mode: str, resolution: str = "sendoff", force_defeat: bool = False, replay_result: str | None = None) -> dict:
        sequence = len(list(directory.glob("*-result.json"))) + 1
        artifact = directory / f"{sequence:02d}-{mode}-result.json"
        arguments = ["--script", e2e_script, "--", "--mode", mode, "--resolution", resolution, "--policy", args.policy, "--evidence-file", str(artifact)]
        if force_defeat:
            arguments.append("--force-defeat")
        if replay_result:
            arguments.extend(["--replay-result-file", replay_result])
        code, text = invoke(env, arguments, directory / f"{sequence:02d}-{mode}.log")
        markers = [line.removeprefix(PREFIX).strip() for line in text.splitlines() if line.startswith(PREFIX)]
        if ERRORS.search(text) or len(markers) != 1 or not artifact.exists():
            summary = {"status": "fail", "mode": mode, "action": "runtime_error", "failures": ["Godot脚本/引擎错误或缺少完整结果"], "exit": code}
        else:
            summary = json.loads(markers[0])
            if code != (0 if summary["status"] == "pass" else 2 if summary["status"] == "blocked" else 1):
                summary["status"] = "fail"
                summary.setdefault("failures", []).append("进程退出与结果状态不符")
        summary["artifact"] = str(artifact)
        print(f"{directory.name} {mode} {summary.get('action', '')}: {summary['status']} ({summary.get('assertions', 0)} assertions)", flush=True)
        return summary

    for name, mode in (("graph", "graph"), ("roster", "roster")):
        with isolated(name) as (env, directory, scenario):
            if env is not None:
                result = run_mode(env, directory, mode)
                scenario["steps"].append(result)
                scenario["status"] = result["status"]
            report["scenarios"][name] = scenario

    visits = set()
    completed = []
    for resolution in ("sendoff", "seal_monitoring"):
        with isolated(resolution) as (env, directory, scenario):
            if env is not None:
                result = run_mode(env, directory, "new", resolution)
                scenario["steps"].append(result)
                defeated = False
                for _ in range(64):
                    if result["status"] != "pass":
                        break
                    previous = json.loads(Path(result["artifact"]).read_text(encoding="utf-8"))
                    pending = bool(previous.get("after", {}).get("pending_battle"))
                    force_defeat = resolution == "sendoff" and pending and not defeated
                    result = run_mode(env, directory, "step", resolution, force_defeat)
                    scenario["steps"].append(result)
                    if force_defeat:
                        defeated = result.get("action") == "defeat_retry" and result["status"] == "pass"
                    if Path(result["artifact"]).exists():
                        evidence = json.loads(Path(result["artifact"]).read_text(encoding="utf-8"))
                        visits.update(item["node"] for item in evidence.get("dialogue_visits", []))
                        if evidence.get("before") != previous.get("after"):
                            result["status"] = "fail"
                            result.setdefault("failures", []).append("新Godot进程恢复快照与上一检查点不一致")
                    if result.get("action") == "win_battle" and result["status"] == "pass":
                        previous = json.loads(Path(result["artifact"]).read_text(encoding="utf-8"))
                        result = run_mode(env, directory, "repeat", resolution, replay_result=result["artifact"])
                        scenario["steps"].append(result)
                        if Path(result["artifact"]).exists():
                            repeated = json.loads(Path(result["artifact"]).read_text(encoding="utf-8"))
                            if repeated.get("before") != previous.get("after"):
                                result["status"] = "fail"
                                result.setdefault("failures", []).append("重复结算进程恢复快照与胜利检查点不一致")
                    if result.get("action") == "complete" and result["status"] == "pass":
                        completed.append(resolution)
                        break
                else:
                    result = {"status": "fail", "action": "incomplete", "failures": ["有限五夜流程超出64检查点；不得当完成"]}
                    scenario["steps"].append(result)
                scenario["status"] = result["status"]
                if result["status"] == "pass" and resolution not in completed:
                    scenario["status"] = "fail"
                    scenario["steps"].append({"status": "fail", "failures": ["未达到complete终止条件"]})
                scenario["actual_process_restarts"] = len(scenario["steps"]) - 1
                scenario["defeat_retry_exercised"] = defeated
            report["scenarios"][resolution] = scenario

    report["completed_endings"] = completed
    report["traversed_dialogue_nodes"] = sorted(visits)
    report["traversed_node_count"] = len(visits)
    statuses = [item["status"] for item in report["scenarios"].values()]
    report["status"] = "fail" if "fail" in statuses else "blocked" if "blocked" in statuses else "pass"
    if report["status"] == "pass" and (len(visits) != 52 or completed != ["sendoff", "seal_monitoring"]):
        report["status"] = "fail"
        report["coverage_failure"] = "两次真实完整流程未遍历全部52节点或两结局"
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    (output / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "commands.json").write_text(json.dumps(commands, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CAMPAIGN MODEL E2E: {report['status']}; endings={completed}; traversed={len(visits)}/52; evidence={output}")
    return 0 if report["status"] == "pass" else 2 if report["status"] == "blocked" else 1


if __name__ == "__main__":
    raise SystemExit(main())
