"""从已下载的色幕视频制作无损透明视频候选；不改生产PNG、帧序或时长。"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True)


def media(path):
    return json.loads(run([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
        "stream=width,height,r_frame_rate,nb_frames,pix_fmt,color_range,color_space,color_transfer,color_primaries:format=duration", "-of", "json", str(path)
    ]).stdout)


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inspect_screen(source, width, height):
    raw = run(["ffmpeg", "-v", "error", "-i", str(source), "-frames:v", "1",
               "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]).stdout
    pixels = np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)
    corner = pixels[:height // 8, :width // 8].reshape(-1, 3).astype(float)
    color = np.median(corner, axis=0)
    spread = float(np.percentile(np.linalg.norm(corner - color, axis=1), 95))
    r, g, b = color
    family = "magenta" if min(r, b) > g + 60 else "green" if g > max(r, b) + 60 else "blue" if b > max(r, g) + 60 else "unsupported"
    if family == "unsupported" or spread > 16:
        raise ValueError("没有明确均匀的绿/蓝/品红幕；保留源视频，不能套用色键")
    return [int(round(v)) for v in color], family, spread


def graph(color, crop, family, profile, remove_complement_spill=False):
    key = "0x" + "".join(f"{value:02x}" for value in color)
    x, y, width, height = crop
    gray = ",format=gray" if profile in ("edge_chroma_v3", "edge_chroma_v4", "edge_chroma_v5") else ""
    # 粗轮廓只产生保护内核；软色键只决定边缘。避免用柔和阈值把整片服装挖空。
    branches = [
        f"[0:v]crop={width}:{height}:{x}:{y},format=rgba,split=3[raw][rough][soft]",
        f"[rough]colorkey={key}:0.08:0.12,alphaextract{gray},lut=y='if(gt(val,128),255,0)',erosion,erosion{gray}[core]",
        f"[soft]colorkey={key}:0.14:0.28,alphaextract{gray}[edge]",
        f"[edge][core]blend=all_expr='max(A,B)'{gray}[matte]",
    ]
    if profile.startswith("edge_chroma_"):
        # 不透明像素也可能带幕色；只在可见轮廓内侧三像素修正，内区逐通道原样保留。
        branches += [
            "[raw]split[original][colored]",
            "[matte]split[alphaout][outline]",
            # 软透明晕圈不是实体边界。v5从近实体alpha定义内区，避免彩边躲在低alpha晕圈内侧。
            f"[outline]format=gray,lut=y='if(gte(val,{224 if profile == 'edge_chroma_v5' else 8}),255,0)',erosion,erosion,erosion,negate{gray}[ring_gray]" if gray else "[outline]lut=y='if(gt(val,8),255,0)',erosion,erosion,erosion,negate[ring_gray]",
            # maskedmerge要求三路格式一致；显式在遮罩运算完成后转换，防止上游灰度LUT被协商成RGB。
            "[ring_gray]format=gbrap[ring]" if gray else "[ring_gray]null[ring]",
        ]
        red, green, blue = "r(X,Y)", "g(X,Y)", "b(X,Y)"
        # 透明边可仍含接近整幅值的幕色，96的上限会留下亮色细边；v4只在轮廓环内去掉全部超额。
        limit = 255 if profile in ("edge_chroma_v4", "edge_chroma_v5") else 96
        expressions = {"r": red, "g": green, "b": blue}
        if family == "green":
            expressions["g"] = f"{green}-clip({green}-max({red},{blue})-8,0,{limit})"
        elif family == "blue":
            expressions["b"] = f"{blue}-clip({blue}-max({red},{green})-8,0,{limit})"
        else:
            # 红衣不等于品红污染：两条幕色通道都明显偏高且相近时才处理。
            eligible = f"lt(abs({red}-{blue}),max({red},{blue})*0.45)*gt(min({red},{blue})-{green},24)"
            spill = f"if({eligible},clip(min({red},{blue})-{green}-8,0,{limit}),0)"
            expressions["r"] = f"{red}-{spill}"
            expressions["b"] = f"{blue}-{spill}"
            if remove_complement_spill:
                # 仅为确认含互补色振铃的源片显式开启；不默认处理其他角色的合法绿色发饰/衣料。
                extreme = f"gt({green}-max({red},{blue}),40)*gt({green},1.6*max({red},{blue}))"
                expressions["g"] = f"if({extreme},max({red},{blue})+16,{green})"
        branches += [
            "[colored]geq=" + ":".join(f"{key}='{value}'" for key, value in expressions.items()) + ":a='255'[corrected]",
            "[original][corrected][ring]maskedmerge=planes=7[merged]",
            "[merged][alphaout]alphamerge,format=argb[out]",
        ]
        return ";".join(branches)
    branches.append("[raw][matte]alphamerge[keyed]")
    # 在半透明边按实际幕色反解混色；通道改变量最多40，实体内核RGB保持原值。
    # 不对整个人物做despill，避免把薄荷灰绿头发、苏合绿裤子当背景色抹掉。
    channels = []
    for channel, background in zip("rgb", color):
        old = f"{channel}(X,Y)"
        estimate = f"({old}-{background}*(1-alpha(X,Y)/255))/max(alpha(X,Y)/255,0.1)"
        expression = f"if(lt(alpha(X,Y),1),0,if(lt(alpha(X,Y),250),clip({estimate},max(0,{old}-40),min(255,{old}+40)),{old}))"
        channels.append(f"{channel}='{expression}'")
    branches.append("[keyed]geq=" + ":".join(channels) + ":a='alpha(X,Y)',format=argb[out]")
    return ";".join(branches)


def build(source, destination, profile, remove_complement_spill=False):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    allowed = (ROOT / "build/libtv").resolve()
    if not destination.is_relative_to(allowed) or destination == allowed:
        raise ValueError("候选必须放在build/libtv独立子目录，不能覆盖生产素材")
    if destination.exists() and any(destination.iterdir()):
        raise ValueError("候选目录非空，请使用新版本目录")
    info = media(source)
    stream = info["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    color, family, spread = inspect_screen(source, width, height)
    # 固定保留中部70%横向画面，竖向全高。全片不追人、不逐帧改变画布。
    # 此裁切仅供制作候选；是否包括全部发丝/武器需对动作全程目检后才能登记。
    left = int(width * .15) // 2 * 2
    right = int(width * .85) // 2 * 2
    crop = [left, 0, right - left, height]
    destination.mkdir(parents=True, exist_ok=True)
    (destination / ".gdignore").write_text("", encoding="utf-8")
    filter_graph = graph(color, crop, family, profile, remove_complement_spill)
    (destination / "filter.ffgraph").write_text(filter_graph, encoding="utf-8")
    output = destination / "matte-candidate.mov"
    command = ["ffmpeg", "-v", "error", "-i", str(source), "-filter_complex", filter_graph,
               "-map", "[out]", "-an", "-c:v", "qtrle", "-pix_fmt", "argb", "-fps_mode", "passthrough", str(output)]
    run(command)
    output_info = media(output)
    receipt = {"profile": profile, "remove_complement_spill": remove_complement_spill, "source": str(source), "source_sha256": digest(source), "source_media": info,
               "background_rgb": color, "screen_family": family, "corner_95pct_spread": spread,
               "crop_xywh": crop, "filter_graph": filter_graph, "command": command,
               "output": str(output), "output_sha256": digest(output), "output_media": output_info,
               "production_registered": False,
               "limitations": ["源帧与正式图集选版尚需确认", "两像素保护内核不能代替逐帧细发丝/武器检查", "未做游戏回归或生产替换"]}
    (destination / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"source": source.name, "screen": family, "output": str(output), "media": output_info}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--profile", choices=["soft_v1", "edge_chroma_v2", "edge_chroma_v3", "edge_chroma_v4", "edge_chroma_v5"], default="edge_chroma_v5")
    parser.add_argument("--remove-complement-spill", action="store_true", help="仅对已确认互补色污染的品红幕素材开启")
    arguments = parser.parse_args()
    build(arguments.source, arguments.output_dir, arguments.profile, arguments.remove_complement_spill)
