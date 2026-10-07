#!/usr/bin/env python3
"""人物阶段纹理与会话真实运行验收：先验证临时 user://，再运行无界面测试。"""
from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--import", dest="do_import", action="store_true")
    parser.add_argument("--suite", choices=["loader", "scene", "all"], default="all")
    parser.add_argument("--log", type=Path, help="仓库外的完整测试日志")
    parser.add_argument("--lock", type=Path, default=ROOT.parent / "godot-import.lock")
    args = parser.parse_args()
    engine = shutil.which(args.godot)
    if engine is None:
        parser.error(f"找不到 Godot：{args.godot}")
    if args.log and args.log.resolve().is_relative_to(ROOT):
        parser.error("测试日志必须放在仓库外")
    if args.lock.resolve().is_relative_to(ROOT):
        parser.error("Godot 共用导入锁必须放在仓库外")
    logs: list[str] = []
    try:
        with tempfile.TemporaryDirectory(prefix="ssa-texture-contexts-") as temporary:
            isolation = Path(temporary).resolve()
            env = os.environ.copy()
            for variable in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                location = isolation / variable
                location.mkdir()
                env[variable] = str(location)
            env.update(RPG_TEST_ROOT=str(isolation), RPG_TEST_ISOLATED="0")

            def run(arguments: list[str], timeout: int = 60) -> tuple[int, str]:
                result = subprocess.run(
                    [engine, "--headless", "--path", str(ROOT), *arguments],
                    env=env, text=True, encoding="utf-8", errors="replace",
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
                )
                print(result.stdout, end="", flush=True)
                logs.append(result.stdout)
                return result.returncode, result.stdout

            args.lock.parent.mkdir(parents=True, exist_ok=True)
            with args.lock.open("a") as lock:
                # 隔离预检同样持锁，所有引擎调用共享同一入口。
                fcntl.flock(lock, fcntl.LOCK_EX)
                code, output = run(["--script", "res://tools/rpg/test_environment.gd"])
                verified = re.findall(r"^RPG_ISOLATION_OK:(.+)$", output, re.M)
                if code or ERROR.search(output) or "Godot Engine v4.7.2.stable" not in output or len(verified) != 1:
                    print("FAIL: user:// 隔离预检未通过，已阻止后续运行")
                    return 1
                actual = Path(verified[0].strip()).resolve()
                if actual == isolation or not actual.is_relative_to(isolation):
                    print("FAIL: 引擎 user:// 未落在临时目录，已阻止后续运行")
                    return 1
                env["RPG_TEST_ISOLATED"] = "1"
                if args.do_import:
                    code, output = run(["--editor", "--import"], timeout=900)
                    if code or ERROR.search(output):
                        return 1
                scripts = []
                if args.suite in ("loader", "all"):
                    scripts.append(("test_texture_contexts.gd", "TEXTURE_CONTEXTS:"))
                if args.suite in ("scene", "all"):
                    scripts.append(("test_texture_context_scene_flow.gd", "TEXTURE_CONTEXTS:"))
                for script, marker in scripts:
                    timing = ["--fixed-fps", "60"]
                    code, output = run(timing + ["--script", "res://tools/characters/" + script])
                    if code or ERROR.search(output) or marker not in output:
                        return 1
                    if not re.search(r"TEXTURE_CONTEXTS: \d+ assertions, 0 failures",output):
                        return 1
        return 0
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        logs.append(partial)
        logs.append("\nFAIL: 隔离测试超时\n")
        print(partial, end="")
        print("FAIL: 隔离测试超时")
        return 1
    finally:
        if args.log:
            args.log.resolve().parent.mkdir(parents=True, exist_ok=True)
            args.log.resolve().write_text("".join(logs), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
