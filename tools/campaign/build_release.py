#!/usr/bin/env python3
"""官方4.7.2七章导出、精确源依赖追加、空目录PCK验收和可回退源码交付。"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[2]
BASE = "6c14f659613d7eafb769441dde8e173ee533341a"
ERRORS = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")


def valid_release_engine(version):
    return version.startswith("4.7.2.stable.official.")


def verification_status(skip_e2e, dirty, missing, source_changed):
    if skip_e2e:
        return "partial_no_e2e"
    return "development_pass_dirty_source" if dirty or missing or source_changed else "pass"


def saga_e2e_command(engine, pack, evidence):
    return [sys.executable, str(PROJECT / "tools/campaign/run_saga_checks.py"),
            "--godot", str(engine), "--pack", str(pack), "--output-dir", str(evidence), "--mode", "real"]


def write_launchers(output):
    (output / "launch_campaign.sh").write_text('#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\nexec "${GODOT_BIN:-godot}" --main-pack ssa-seven-chapter-formal.pck "$@"\n')
    (output / "launch_campaign.bat").write_text('@echo off\ncd /d "%~dp0"\nif not defined GODOT_BIN set "GODOT_BIN=godot"\n"%GODOT_BIN%" --main-pack ssa-seven-chapter-formal.pck %*\n', encoding="utf-8")
    (output / "launch_campaign.sh").chmod(0o755)


def packed_command(engine, empty, pack, script=None):
    return [str(engine), "--headless", "--path", str(empty), "--main-pack", str(pack),
            *(["--script", str(script)] if script else ["--quit-after", "5"])]


def packed_smoke_commands(engine, empty, pack, project=PROJECT):
    commands = [packed_command(engine, empty, pack, project / "tools/campaign" / name)
                for name in ("test_packed_assets.gd", "test_packed_scenes.gd")]
    commands.append(packed_command(engine, empty, pack))
    modal = project / "tools/campaign/test_modal_layout.gd"
    if modal.is_file():
        commands.append(packed_command(engine, empty, pack, modal))
    # 身高检查会建立测试正式档；先证明无该档的真正干净用户标题启动。
    height = project / "tools/campaign/test_character_height.gd"
    if height.is_file():
        commands.append(packed_command(engine, empty, pack, height))
    saga = project / "tools/campaign/test_saga_release_packed.gd"
    if saga.is_file():
        commands.append(packed_command(engine, empty, pack, saga))
    return commands


def valid_isolation(code, output, root):
    matches = [line.split(":", 1)[1].strip() for line in output.splitlines() if line.startswith("RPG_ISOLATION_OK:")]
    return (code == 0 and not ERRORS.search(output) and len(matches) == 1
            and Path(matches[0]).resolve() != root and Path(matches[0]).resolve().is_relative_to(root))


def untracked_dependencies(required, tracked):
    return sorted(set(required) - set(tracked))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--import-lock", type=Path)
    parser.add_argument("--source", action="store_true", help="clean tracked树时额外交付Git源码ZIP与相对批准基线的binary patch")
    parser.add_argument("--skip-e2e", action="store_true", help="仅供开发迭代；跳过时不得宣称正式发布验收完成")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.is_relative_to(PROJECT):
        parser.error("发布包/证据必须放仓库外")
    output.mkdir(parents=True, exist_ok=True)
    engine = shutil.which(args.godot)
    if not engine:
        parser.error("找不到指定官方Godot")
    version = subprocess.check_output([engine, "--version"], text=True).strip()
    if not valid_release_engine(version):
        parser.error("七章发布必须使用已批准的官方Godot4.7.2，不能换引擎")
    head = subprocess.check_output(["git", "-C", str(PROJECT), "rev-parse", "HEAD"], text=True).strip()
    dirty = subprocess.check_output(["git", "-C", str(PROJECT), "diff", "HEAD", "--name-only"], text=True).splitlines()
    if args.source and dirty:
        parser.error("源码交付要求tracked树已提交；当前未提交：" + ", ".join(dirty))
    pack = output / "ssa-seven-chapter-formal.pck"
    logs = []
    report = {"started_utc": datetime.now(timezone.utc).isoformat(), "engine_version": version,
              "commit": head, "dirty_tracked": dirty, "e2e": "not_run", "saga_e2e": "not_run", "status": "running",
              "standalone_executable": "not_generated", "manual_gui": "not_run_by_this_builder"}

    def invoke(command, env=None, timeout=600):
        result = subprocess.run(command, env=env, text=True, encoding="utf-8", errors="replace",
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        print(result.stdout, end="", flush=True)
        logs.append({"argv": command, "exit": result.returncode, "output": result.stdout})
        if result.returncode or ERRORS.search(result.stdout):
            raise RuntimeError("发布步骤失败/包含引擎错误：" + " ".join(map(str, command)))
        return result.returncode, result.stdout

    try:
        invoke([sys.executable, str(PROJECT / "tools/campaign/release_pack.py"), "--pack", str(pack), "--output-dir", str(output), "--configure-export"])
        dependencies = json.loads((output / "formal-dependencies.json").read_text())
        tracked = subprocess.check_output(["git", "-C", str(PROJECT), "ls-files", "-z"]).decode().split("\0")
        missing = untracked_dependencies(dependencies["sources"] + dependencies["resource_roots"], tracked)
        current_dirty = subprocess.check_output(["git", "-C", str(PROJECT), "diff", "HEAD", "--name-only"], text=True).splitlines()
        source_diff = subprocess.check_output(["git", "-C", str(PROJECT), "diff", "--binary", "HEAD"])
        report["dirty_tracked"] = current_dirty
        report["untracked_runtime_dependencies"] = missing
        if args.source:
            if missing or current_dirty:
                raise RuntimeError("源码ZIP前必需依赖和精确export设置须提交：untracked=" + str(missing) + ", dirty=" + str(current_dirty))
        with tempfile.TemporaryDirectory(prefix="ssa-release-") as directory:
            root = Path(directory).resolve()
            empty = root / "empty-project"
            empty.mkdir()
            env = os.environ.copy()
            for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")):
                location = root / name
                location.mkdir()
                env[key] = str(location)
            env.update(RPG_TEST_ROOT=str(root), RPG_TEST_ISOLATED="0", GODOT_SILENCE_ROOT_WARNING="1")
            env.pop("CAMPAIGN_PRESENTATION_OUTPUT", None)
            code, text = invoke([engine, "--headless", "--path", str(PROJECT), "--script", str(PROJECT / "tools/rpg/test_environment.gd")], env)
            if not valid_isolation(code, text, root):
                raise RuntimeError("实际user://隔离未获验证，已阻止导出/测试")
            env["RPG_TEST_ISOLATED"] = "1"
            lock = args.import_lock.resolve() if args.import_lock else output.parent / "godot-import.lock"
            with lock.open("a") as stream:
                fcntl.flock(stream, fcntl.LOCK_EX)
                invoke([engine, "--headless", "--path", str(PROJECT), "--export-pack", "Windows Desktop", str(pack)], env)
            invoke([sys.executable, str(PROJECT / "tools/campaign/release_pack.py"), "--pack", str(pack), "--output-dir", str(output), "--append-originals"])
            code, text = invoke(packed_command(engine, empty, pack, PROJECT / "tools/rpg/test_environment.gd"), env)
            if not valid_isolation(code, text, root):
                raise RuntimeError("PCK实际user://隔离核验失败")
            for command in packed_smoke_commands(engine, empty, pack):
                invoke(command, env)
        if not args.skip_e2e:
            evidence = output / ("packed-e2e-" + datetime.now(timezone.utc).strftime("%H%M%S"))
            invoke([sys.executable, str(PROJECT / "tools/campaign/run_end_to_end.py"), "--godot", engine,
                    "--pack", str(pack), "--output-dir", str(evidence)])
            report["e2e"] = json.loads((evidence / "summary.json").read_text())
            saga_evidence = output / ("packed-saga-e2e-" + datetime.now(timezone.utc).strftime("%H%M%S"))
            invoke(saga_e2e_command(engine, pack, saga_evidence), timeout=3600)
            report["saga_e2e"] = json.loads((saga_evidence / "saga-verification.json").read_text())
        final_head = subprocess.check_output(["git", "-C", str(PROJECT), "rev-parse", "HEAD"], text=True).strip()
        final_diff = subprocess.check_output(["git", "-C", str(PROJECT), "diff", "--binary", "HEAD"])
        report["final_commit"] = final_head
        report["source_changed_during_build"] = final_head != head or final_diff != source_diff
        report["exact_source_commit"] = head if not current_dirty and not missing and not report["source_changed_during_build"] else None
        if args.source and report["exact_source_commit"] is None:
            raise RuntimeError("构建期间源码提交或工作树改变，禁止交付不匹配的源码ZIP")
        if args.source:
            invoke(["git", "-C", str(PROJECT), "archive", "--format=zip", "--prefix=ssa-seven-chapter-source/", "--output=" + str(output / "ssa-seven-chapter-source.zip"), head])
            patch = subprocess.check_output(["git", "-C", str(PROJECT), "diff", "--binary", BASE, head])
            (output / "ssa-seven-chapter-from-baseline.patch").write_bytes(patch)
        write_launchers(output)
        (output / "RELEASE_README.txt").write_text("逢魔退治帖：七章3D主线\n使用官方Godot4.7.2启动launch_campaign.bat/sh，或运行：godot --main-pack ssa-seven-chapter-formal.pck\n此PCK已含七章动态JSON、154原PNG帧、六敌图、3D模型和字体；不依赖源码目录。\n本机未安装export templates，因此未生成独立Windows EXE。请通过GODOT_BIN指定已有官方4.7.2引擎。\n正式档仅写campaign_v1，不迁移/覆盖旧试玩档。\n构建基准提交（精确对应见release-verification.json）：" + head + "\npatch相对基线：" + BASE + "\n历史归档恢复：参见源码archive/2026-10-04-retired/manifest.json，以独立归档提交git revert。\n", encoding="utf-8")
        report["status"] = verification_status(args.skip_e2e, current_dirty, missing, report["source_changed_during_build"])
        report["pack_sha256"] = hashlib.sha256(pack.read_bytes()).hexdigest()
        report["pack_size_bytes"] = pack.stat().st_size
    except (RuntimeError, subprocess.TimeoutExpired, OSError, ValueError) as error:
        report["status"] = "fail"
        report["error"] = str(error)
        print("FAIL:", error)
    finally:
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        (output / "release-verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        (output / "release-commands.json").write_text(json.dumps(logs, ensure_ascii=False, indent=2) + "\n")
    return 0 if report["status"] in ("pass", "partial_no_e2e", "development_pass_dirty_source") else 1


if __name__ == "__main__":
    raise SystemExit(main())
