"""终章连续实战专用隔离入口；共享引擎锁、先验user目录，失败清理完整进程树。"""
import argparse
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT / "tools"))
from verification_support import exclusive_file_lock, run_captured


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(PROJECT.parent / "Godot_v4.7.2-stable_win64_console.exe"))
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, default=PROJECT.parent / "ssa-campaign-evidence/goal-loadouts-20261008/saga/sendoff-gentle-dawn/checkpoints/chapter_7.json")
    parser.add_argument("--cases", default="")
    parser.add_argument("--require-completion", action="store_true", help="将选定构筑未完成连续三阶段视为验收失败")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.is_relative_to(PROJECT) or not args.checkpoint.is_file():
        parser.error("证据须在仓库外，且真实检查点必须存在")
    output.mkdir(parents=True, exist_ok=True)
    source_output = output / "test-source"
    source_output.mkdir(exist_ok=True)
    for name in ("test_final_gauntlet.gd", "final_gauntlet_strategy.gd", "run_final_gauntlet.py"):
        shutil.copy2(PROJECT / "tools/campaign" / name, source_output / name)
    with exclusive_file_lock(PROJECT.parent / "godot-import.lock", timeout=1200):
        with tempfile.TemporaryDirectory(prefix="ssa-final-gauntlet-") as directory:
            isolated = Path(directory).resolve()
            env = os.environ.copy()
            for key, name in [("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"), ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
                (isolated / name).mkdir()
                env[key] = str(isolated / name)
            env.update(RPG_TEST_ROOT=str(isolated), RPG_TEST_ISOLATED="0", GAUNTLET_OUTPUT=str(output), GAUNTLET_CHECKPOINT=str(args.checkpoint.resolve()), GAUNTLET_CASES=args.cases)
            env["GAUNTLET_REQUIRE_COMPLETION"] = "1" if args.require_completion else "0"
            command = [args.godot, "--headless", "--path", str(PROJECT)]
            probe = run_captured(command + ["--script", "res://tools/rpg/test_environment.gd"], env=env, timeout=60)
            (output / "00-isolation.log").write_text(probe.stdout, encoding="utf-8")
            paths = re.findall(r"^RPG_ISOLATION_OK:(.*)$", probe.stdout, re.M)
            print(probe.stdout, end="", flush=True)
            if probe.returncode or len(paths) != 1 or not Path(paths[0].strip()).resolve().is_relative_to(isolated) or Path(paths[0].strip()).resolve() == isolated:
                raise RuntimeError("隔离目录核验失败，未运行写档实战")
            env["RPG_TEST_ISOLATED"] = "1"
            result = run_captured(command + ["--script", "res://tools/campaign/test_final_gauntlet.gd"], env=env, timeout=1200)
            (output / "10-gauntlet.log").write_text(result.stdout, encoding="utf-8")
            print(result.stdout, end="", flush=True)
            return int(bool(result.returncode or re.search(r"(^|\n)(?:SCRIPT ERROR|ERROR|FAIL):", result.stdout)))


if __name__ == "__main__":
    raise SystemExit(main())
