#!/usr/bin/env python3
"""每次建立临时用户目录；核验失败绝不启动测试或旧写档脚本。"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

SUITES = ("data", "rules", "engine", "ai", "campaign", "ui", "roster", "approach", "acceptance", "all")


def run(engine: str, project: Path, env: dict, arguments: list[str], headless: bool = True) -> tuple[int, str]:
    result = subprocess.run([engine, *(["--headless"] if headless else []), "--path", str(project), *arguments],
                            env=env, text=True, encoding="utf-8", errors="replace",
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="", flush=True)
    return result.returncode, result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, default="all")
    parser.add_argument("--approach-visual", action="store_true", help="隔离预检后启动仅人工操作的参道图形验收，F12截图、F10结束")
    parser.add_argument("--legacy", action="store_true", help="核验后依次执行旧 v4、凛音时序、3D预览测试")
    parser.add_argument("--legacy-contracts", action="store_true", help="诊断旧默认入口/左向敌图/回廊直本殿契约；当前五夜版本预期报告这些历史差异")
    parser.add_argument("--import", dest="do_import", action="store_true", help="隔离目录中导入资源")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--sweep", choices=("chain", "boss_only", "both"), help="固定20组合×3策略×3种子批测")
    parser.add_argument("--output-dir", type=Path, help="批测完整重放与结果持久目录（仓库外）")
    args = parser.parse_args()
    if args.approach_visual and (not args.output_dir or args.suite not in ("approach", "all") or args.sweep):
        parser.error("--approach-visual 需指定仓库外 --output-dir，suite 为 approach/all，不能与 sweep 同用")
    if args.sweep and not args.output_dir:
        parser.error("--sweep 必须指定 --output-dir 保留全部失败/超时和重放证据")
    if args.sweep and args.suite not in ("all", "acceptance"):
        parser.error("--sweep 需使用 all 或 acceptance 组")
    engine = shutil.which(args.godot)
    if not engine:
        print(f"FAIL: 未找到 Godot：{args.godot}", file=sys.stderr)
        return 1
    project = Path(__file__).resolve().parents[2]
    if args.approach_visual and args.output_dir.resolve().is_relative_to(project):
        parser.error("图形证据必须保存在项目仓库之外")
    with tempfile.TemporaryDirectory(prefix="ssa-rpg-tests-") as directory:
        root = Path(directory).resolve()
        env = os.environ.copy()
        for variable, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                               ("XDG_CACHE_HOME", "cache"), ("APPDATA", "appdata"),
                               ("LOCALAPPDATA", "localappdata")):
            location = root / name
            location.mkdir()
            env[variable] = str(location)
        env["RPG_TEST_ROOT"] = str(root)
        env["RPG_TEST_ISOLATED"] = "0"
        env["RPG_TEST_LEGACY_CONTRACTS"] = "1" if args.legacy_contracts else "0"
        env.pop("RPG_SWEEP_MODE", None)
        env.pop("RPG_SWEEP_OUTPUT", None)
        env.pop("RPG_APPROACH_OUTPUT", None)
        if args.approach_visual:
            args.output_dir.resolve().mkdir(parents=True, exist_ok=True)
            env["RPG_APPROACH_OUTPUT"] = str(args.output_dir.resolve())
        if args.sweep:
            args.output_dir.resolve().mkdir(parents=True, exist_ok=True)
            env["RPG_SWEEP_MODE"] = args.sweep
            env["RPG_SWEEP_OUTPUT"] = str(args.output_dir.resolve())
        code, output = run(engine, project, env, ["--script", "res://tools/rpg/test_environment.gd"])
        verified = [line.removeprefix("RPG_ISOLATION_OK:").strip() for line in output.splitlines()
                    if line.startswith("RPG_ISOLATION_OK:")]
        if (code != 0 or re.search(r"(^|\n)(?:SCRIPT ERROR|ERROR):", output) or len(verified) != 1
                or Path(verified[0]).resolve() == root or not Path(verified[0]).resolve().is_relative_to(root)):
            print("FAIL: 实际 user:// 未获验证，已阻止全部测试", file=sys.stderr)
            return 1
        env["RPG_TEST_ISOLATED"] = "1"
        if args.do_import or args.legacy or args.approach_visual:
            code, output = run(engine, project, env, ["--editor", "--import"])
            if code or re.search(r"(^|\n)(?:SCRIPT ERROR|ERROR):", output):
                print("FAIL: 导入包含错误，已阻止后续测试", file=sys.stderr)
                return 1
        code, output = run(engine, project, env, ["--script", "res://tools/rpg/run_tests.gd", "--", "--suite", args.suite])
        if code or re.search(r"(^|\n)(?:SCRIPT ERROR|ERROR):", output):
            return 1
        # 道具效果回归复用同一已核验的隔离目录，纳入常规引擎与全量门禁。
        if args.suite in ("engine", "all"):
            code, output = run(engine, project, env, ["--script", "res://tools/rpg/test_item_effectiveness.gd"])
            if code or re.search(r"(^|\n)(?:SCRIPT ERROR|ERROR):", output):
                return 1
        if args.legacy:
            failed = False
            for script in ("tools/test_v4_battle_rules.gd", "tools/test_rinne_v3_timing.gd",
                           "tools/preview/test_act01_approach_preview.gd"):
                code, output = run(engine, project, env, ["--script", "res://" + script])
                broken = bool(code or re.search(r"(^|\n)(?:SCRIPT ERROR|ERROR):", output))
                print(f"LEGACY {script}: {'FAIL' if broken else 'PASS'} (exit={code})", flush=True)
                failed |= broken
            if failed:
                return 1
        if args.approach_visual:
            code, output = run(engine, project, env, ["--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--script", "res://tools/rpg/capture_approach.gd"], headless=False)
            (args.output_dir.resolve() / "godot.log").write_text(output, encoding="utf-8")
            if code or re.search(r"(^|\n)(?:SCRIPT ERROR|ERROR):", output):
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
