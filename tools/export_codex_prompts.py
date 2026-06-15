#!/usr/bin/env python3
"""
导出 Codex UI 生成任务为 CSV 或纯文本列表，方便批量提交给 OpenAI Codex。

用法:
    python3 tools/export_codex_prompts.py --format csv > codex_tasks.csv
    python3 tools/export_codex_prompts.py --format txt > codex_prompts.txt
    python3 tools/export_codex_prompts.py --priority P0 --format json > codex_p0.json
"""

import argparse
import csv
import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
JSON_PATH = PROJECT_ROOT / "data" / "codex_ui_generation_tasks.json"


def load_tasks():
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def export_csv(tasks, out):
    writer = csv.writer(out)
    writer.writerow(["id", "priority", "category", "output_path", "size", "nine_slice", "prompt"])
    for t in tasks:
        writer.writerow([
            t["id"],
            t["priority"],
            t["category"],
            t["output_path"],
            "x".join(str(x) for x in t["size"]),
            "/".join(str(x) for x in t.get("nine_slice", [])),
            t["prompt"],
        ])


def export_txt(tasks, out):
    for t in tasks:
        out.write(f"--- {t['id']} ({t['priority']}) -> {t['output_path']} ---\n")
        out.write(t["prompt"] + "\n\n")


def export_json(tasks, out):
    json.dump({"tasks": tasks}, out, ensure_ascii=False, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Export Codex UI generation tasks")
    parser.add_argument("--format", choices=["csv", "txt", "json"], default="txt")
    parser.add_argument("--priority", choices=["P0", "P1", "P2", "all"], default="all")
    args = parser.parse_args()

    data = load_tasks()
    tasks = data["tasks"]

    if args.priority != "all":
        tasks = [t for t in tasks if t["priority"] == args.priority]

    exporters = {
        "csv": export_csv,
        "txt": export_txt,
        "json": export_json,
    }

    exporters[args.format](tasks, sys.stdout)


if __name__ == "__main__":
    main()
