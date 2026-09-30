# -*- coding: utf-8 -*-
"""批量生成蒸汽朋克素材。用法:
python tools/gen_steampunk_assets.py <起始索引> <结束索引(不含)>
按 manifest 顺序串行调用 image_generation 插件脚本,每个失败重试一次。
已存在且非空的文件自动跳过(便于断点续跑)。
"""
import json
import os
import subprocess
import sys

STYLE = (
    "Steampunk meets Chinese Taoist exorcism aesthetic, dark bronze and brass metal, "
    "small gears, rivets and copper pipes, cinnabar red lacquer, talisman-yellow paper, "
    "xuan black, aged patina, ink-wash shading, subtle Chinese lattice motifs, game asset, "
    "no text, no watermark, no characters, no western fantasy gems, no blue crystals."
)

PLUGIN_DIR = os.path.join(
    os.environ.get("APPDATA", ""),
    "kimi-desktop", "daimon-share", "daimon", "runtime", "kimi-code",
    "home", "plugins", "managed", "image_generation",
)
TOOL = os.path.join(PLUGIN_DIR, "scripts", "image_generation_tool.py")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "gen_steampunk_manifest.json")


def generate_one(entry):
    out_path = os.path.join(ROOT, entry["file"].replace("/", os.sep))
    if os.path.exists(out_path) and os.path.getsize(out_path) > 10240:
        print("[SKIP] 已存在: %s" % entry["file"], flush=True)
        return True
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    desc = STYLE + " " + entry["subject"]
    cmd = [
        sys.executable, TOOL, "generate",
        "--description", desc,
        "--ratio", entry["ratio"],
        "--resolution", "1K",
        "--background", "transparent",
        "--output", out_path,
    ]
    for attempt in (1, 2):
        print("[GEN] %s (尝试 %d)" % (entry["file"], attempt), flush=True)
        try:
            proc = subprocess.run(cmd, cwd=PLUGIN_DIR, capture_output=True, text=True, timeout=240)
        except subprocess.TimeoutExpired:
            print("[FAIL] 超时: %s" % entry["file"], flush=True)
            continue
        if proc.returncode == 0 and os.path.exists(out_path) and os.path.getsize(out_path) > 10240:
            print("[OK] %s" % entry["file"], flush=True)
            return True
        tail = (proc.stdout or "")[-400:] + (proc.stderr or "")[-400:]
        print("[FAIL] %s -> %s" % (entry["file"], tail), flush=True)
    return False


def main():
    start = int(sys.argv[1])
    end = int(sys.argv[2])
    with open(MANIFEST, encoding="utf-8") as f:
        entries = json.load(f)
    failed = []
    for i, entry in enumerate(entries[start:end], start):
        if not generate_one(entry):
            failed.append(entry["file"])
    print("== 本批完成,失败: %d ==" % len(failed), flush=True)
    for f in failed:
        print("  FAILED: " + f, flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
