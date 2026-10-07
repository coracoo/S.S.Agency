#!/usr/bin/env python3
"""残影专用门禁：共享导入锁，验证实际 4.7.2 和临时 user:// 后运行。"""
from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--log", type=Path)
    parser.add_argument("--proof", type=Path, help="仓库外的无头检查 JSON；不冒充渲染截图")
    args = parser.parse_args()
    for path in (args.log, args.proof):
        if path and path.resolve().is_relative_to(ROOT):
            parser.error("证据必须放在仓库外")
        if path:
            path.resolve().parent.mkdir(parents=True, exist_ok=True)
    logs: list[str] = []
    try:
        with (ROOT.parent / "godot-import.lock").open("a") as lock, tempfile.TemporaryDirectory(prefix="ssa-snapshot-ghost-") as temporary:
            fcntl.flock(lock, fcntl.LOCK_EX)
            isolation = Path(temporary).resolve()
            env = os.environ.copy()
            for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                path = isolation / key
                path.mkdir()
                env[key] = str(path)
            env.update(RPG_TEST_ROOT=str(isolation), RPG_TEST_ISOLATED="0")
            if args.proof:
                env["SNAPSHOT_GHOST_PROOF"] = str(args.proof.resolve())

            def run(script: str) -> tuple[int, str]:
                result = subprocess.run(
                    [args.godot, "--headless", "--path", str(ROOT), "--fixed-fps", "60", "--script", script],
                    env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
                )
                print(result.stdout, end="", flush=True)
                logs.append(result.stdout)
                return result.returncode, result.stdout

            code, out = run("res://tools/rpg/test_environment.gd")
            paths = re.findall(r"^RPG_ISOLATION_OK:(.+)$", out, re.M)
            if code or ERROR.search(out) or "Godot Engine v4.7.2.stable" not in out or len(paths) != 1 or Path(paths[0]).resolve() == isolation or not Path(paths[0]).resolve().is_relative_to(isolation):
                print("FAIL: 4.7.2/user:// 隔离核验失败")
                return 1
            env["RPG_TEST_ISOLATED"] = "1"
            code, out = run("res://tools/characters/test_snapshot_ghost_trail.gd")
            return int(bool(code or ERROR.search(out) or not re.search(r"SNAPSHOT_GHOST_TRAIL: \d+ assertions, 0 failures", out)))
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        logs.extend([partial, "\nFAIL: 残影检查超时\n"])
        print("FAIL: 残影检查超时")
        return 1
    finally:
        if args.log:
            args.log.write_text("".join(logs), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
