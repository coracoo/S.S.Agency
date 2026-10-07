#!/usr/bin/env python3
"""恢复组件统一门禁：所有引擎调用持锁，核验4.7.2与临时user://，不占GUI。"""
from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import re
import selectors
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")
CORE = [
    ("tools/characters/test_melee_return_dash.gd", r"MELEE_RETURN_DASH: \d+ assertions, 0 failures"),
    ("tools/characters/test_melee_production_gate.gd", r"MELEE_PRODUCTION_GATE: \d+ assertions, 0 failures"),
    ("tools/characters/test_texture_contexts.gd", r"TEXTURE_CONTEXTS: \d+ assertions, 0 failures"),
    ("tools/characters/test_tight_sprite_render.gd", r"TIGHT_SPRITE_RENDER: \d+ assertions, 0 failures"),
    ("tools/characters/test_snapshot_ghost_trail.gd", r"SNAPSHOT_GHOST_TRAIL: \d+ assertions, 0 failures"),
    ("tools/characters/test_melee_approach.gd", r"MELEE_APPROACH: \d+ assertions, 0 failures"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--script", action="append", help="相对res://路径；可重复指定")
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--import", dest="do_import", action="store_true")
    parser.add_argument("--realtime", action="store_true", help="墙钟时序测试不强制模拟60fps")
    args = parser.parse_args()
    if args.log.resolve().is_relative_to(ROOT):
        parser.error("验证日志须存放仓库外")
    args.log.parent.mkdir(parents=True, exist_ok=True)
    logs: list[str] = []
    try:
        with (ROOT.parent / "godot-import.lock").open("a") as lock, tempfile.TemporaryDirectory(prefix="ssa-runtime-recovery-") as temporary:
            fcntl.flock(lock, fcntl.LOCK_EX)
            isolated = Path(temporary).resolve()
            env = os.environ.copy()
            for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                folder = isolated / key
                folder.mkdir()
                env[key] = str(folder)
            env.update(RPG_TEST_ROOT=str(isolated), RPG_TEST_ISOLATED="0")

            def run(arguments: list[str], timeout: int = 300) -> tuple[int, str]:
                command = [args.godot, "--headless", "--path", str(ROOT), *arguments]
                output = b""
                with subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
                    with selectors.DefaultSelector() as selector:
                        selector.register(process.stdout, selectors.EVENT_READ)
                        deadline = time.monotonic() + timeout
                        while process.poll() is None:
                            if time.monotonic() >= deadline:
                                process.kill()
                                tail, _ = process.communicate()
                                raise subprocess.TimeoutExpired(command, timeout, output=output + tail)
                            for key, _ in selector.select(.1):
                                output += os.read(key.fd, 65536)
                            # 解析/运行错误后的SceneTree常继续空转；立即终止本次失败，释放共享锁。
                            if ERROR.search(output.decode("utf-8", errors="replace")):
                                process.terminate()
                                break
                        try:
                            tail, _ = process.communicate(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            tail, _ = process.communicate()
                        output += tail
                    text = output.decode("utf-8", errors="replace")
                    print(text, end="", flush=True)
                    logs.append(text)
                    return process.returncode, text

            code, output = run(["--script", "res://tools/rpg/test_environment.gd"], 60)
            matches = re.findall(r"^RPG_ISOLATION_OK:(.+)$", output, re.M)
            if code or ERROR.search(output) or "Godot Engine v4.7.2.stable" not in output or len(matches) != 1:
                raise RuntimeError("实际4.7.2/user://预检未通过")
            actual = Path(matches[0]).resolve()
            if actual == isolated or not actual.is_relative_to(isolated):
                raise RuntimeError("user://不在临时隔离目录")
            env["RPG_TEST_ISOLATED"] = "1"
            if args.do_import:
                code, output = run(["--editor", "--import"], 900)
                if code or ERROR.search(output):
                    return 1
            cases = [(path.removeprefix("res://"), None) for path in args.script] if args.script else CORE
            failed = False
            for path, marker in cases:
                print("RECOVERY_CASE:", path, flush=True)
                logs.append("\nRECOVERY_CASE: " + path + "\n")
                timing = [] if args.realtime else ["--fixed-fps", "60"]
                code, output = run(timing + ["--script", "res://" + path])
                failed |= bool(code or ERROR.search(output) or (marker and not re.search(marker, output)))
            return int(failed)
    except (subprocess.TimeoutExpired, RuntimeError) as error:
        partial = getattr(error, "stdout", "") or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        message = "\nFAIL: " + str(error) + "\n"
        logs.extend([partial, message])
        print(message, end="", flush=True)
        return 1
    finally:
        args.log.write_text("".join(logs), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
