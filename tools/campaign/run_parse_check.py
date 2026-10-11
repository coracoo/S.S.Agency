# -*- coding: utf-8 -*-
"""验收矩阵A项第一步：全部GDScript逐个 --check-only 解析检查。

只解析不运行；共享引擎锁；输出原样归档到仓库外证据目录，失败完整收集。
用法：python tools/campaign/run_parse_check.py --output-dir <仓库外绝对路径>
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT / "tools"))
from verification_support import exclusive_file_lock, run_captured

MARKERS = ("SCRIPT ERROR", "Parse Error", "Function not found")


def isolated_env(root: Path) -> dict:
    env = os.environ.copy()
    for key, name in [("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"), ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        (root / name).mkdir(parents=True, exist_ok=True)
        env[key] = str(root / name)
    return env


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(PROJECT.parent / "Godot_v4.7.2-stable_win64_console.exe"))
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.is_relative_to(PROJECT):
        parser.error("证据目录必须在仓库外")
    output.mkdir(parents=True, exist_ok=True)
    targets = sorted((PROJECT / "scripts").rglob("*.gd")) + sorted((PROJECT / "tools").rglob("*.gd"))
    failures = []
    with exclusive_file_lock(PROJECT.parent / "godot-import.lock", timeout=1200):
        with tempfile.TemporaryDirectory(prefix="ssa-parse-check-") as directory:
            env = isolated_env(Path(directory).resolve())
            for index, path in enumerate(targets):
                rel = path.relative_to(PROJECT).as_posix()
                command = [args.godot, "--headless", "--path", str(PROJECT), "--check-only", "--script", "res://" + rel]
                result = run_captured(command, env=env, timeout=120)
                text = result.stdout + "\n" + result.stderr
                (output / "logs").mkdir(exist_ok=True)
                (output / "logs" / (rel.replace("/", "__") + ".log")).write_text(text, encoding="utf-8")
                if result.returncode or any(marker in text for marker in MARKERS):
                    failures.append((rel, result.returncode, text.strip()[-1500:]))
                if (index + 1) % 50 == 0:
                    print(f"已解析 {index + 1}/{len(targets)}", flush=True)
    summary = ["目标脚本数：%d，失败数：%d" % (len(targets), len(failures))]
    for rel, code, tail in failures:
        summary.append("=" * 24 + "\n" + rel + "（退出码 %d）\n" % code + tail)
    report = "\n".join(summary)
    (output / "parse-check-report.txt").write_text(report, encoding="utf-8")
    print(report)
    if failures:
        print("PARSE_CHECK:FAIL", flush=True)
        return 1
    print("PARSE_CHECK:PASS", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
