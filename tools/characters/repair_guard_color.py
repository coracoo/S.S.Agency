"""岑照专用色点修正候选：只改RGB，沿用透明视频的alpha、帧序与时长。"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def run(command):
    return subprocess.run(command, check=True, capture_output=True)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def build(source: Path, output: Path, chroma_denoise: bool):
    source, output = source.resolve(), output.resolve()
    if not output.is_relative_to((ROOT / "build/libtv").resolve()):
        raise ValueError("只写独立制作目录，不允许直接覆盖生产素材")
    if output.exists() and any(output.iterdir()):
        raise ValueError("目录非空，请选择独立候选目录")
    output.mkdir(parents=True, exist_ok=True)
    (output / ".gdignore").write_text("", encoding="utf-8")

    r, g, b = "r(X,Y)", "g(X,Y)", "b(X,Y)"
    # 保留蓝白衣装、暖肤色、青铜原有的灰绿锈色；只压高饱和且不属原画配色的异常色。
    # 原批准立绘实体内区的色优势上界为绿色24、品红18；从上界之外平滑增加修正，避免跨阈值闪色。
    magenta = f"min({r},{b})-{g}"
    green = f"{g}-max({r},{b})"
    removal = f"clip(({magenta}-20)/24,0,1)*max({magenta}-8,0)"
    green_removal = f"clip(({green}-24)/24,0,1)*max({green}-8,0)"
    expression = f"r='{r}-{removal}':g='{g}-{green_removal}':b='{b}-{removal}':a='alpha(X,Y)'"
    branches = ["[0:v]split[raw][mask]", "[mask]alphaextract,format=gray[alpha]",
                "[raw]format=gbrap,geq=" + expression + "[corrected]"]
    if chroma_denoise:
        # 只平滑色度，不对亮度平面做模糊，不用跨帧混合掩盖姿态或制造拖影。
        branches.append("[corrected]format=yuv444p,bilateral=sigmaS=1.4:sigmaR=0.035:planes=6,format=rgb24[color]")
    else:
        branches.append("[corrected]format=rgb24[color]")
    branches.append("[color][alpha]alphamerge,format=argb[out]")
    graph = ";".join(branches)
    target = output / "guard-color-candidate.mov"
    command = ["ffmpeg", "-v", "error", "-i", str(source), "-filter_complex", graph,
               "-map", "[out]", "-an", "-c:v", "qtrle", "-pix_fmt", "argb", "-fps_mode", "passthrough", str(target)]
    run(command)
    # 这是素材运输记录，不运行Godot或存档测试。逐帧alpha摘要便于人工/后续模型核对。
    hashes = {}
    for label, path in [("before", source), ("after", target)]:
        result = run(["ffmpeg", "-v", "error", "-i", str(path), "-vf", "alphaextract",
                      "-an", "-f", "framemd5", "-"]).stdout.decode("utf-8")
        (output / ("alpha-" + label + ".framemd5")).write_text(result, encoding="utf-8")
        hashes[label] = [line.rsplit(",", 1)[-1].strip() for line in result.splitlines() if line and not line.startswith("#")]
    info = {"source": str(source), "source_sha256": sha(source), "output": str(target), "output_sha256": sha(target),
            "guard_only": True, "method": "guard_palette_soft_v2", "chroma_denoise": chroma_denoise, "filter_graph": graph, "command": command,
            "alpha_frame_count": len(hashes["after"]), "alpha_identical": hashes["before"] == hashes["after"],
            "production_registered": False, "scope": "岑照专用候选，不应用于其他角色"}
    (output / "receipt.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(target), "alpha_frames": len(hashes["after"]), "alpha_identical": info["alpha_identical"]}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--chroma-denoise", action="store_true")
    args = parser.parse_args()
    build(args.source, args.output_dir, args.chroma_denoise)
