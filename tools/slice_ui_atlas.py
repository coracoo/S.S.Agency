#!/usr/bin/env python3
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets/ui/generated/ui_frame_atlas_source.png"
OUT_DIR = ROOT / "assets/ui/generated"


# Rects are detected from the non-green connected components in ui_frame_atlas_source.png.
# Each crop keeps transparent padding so outer crests, diamonds, and corners are not clipped.
SLICES = {
    "ui_bottom_hand_panel.png": {"bbox": (41, 962, 1207, 1225), "pad": 18},
    "ui_status_panel.png": {"bbox": (47, 427, 298, 816), "pad": 18},
    "ui_info_panel.png": {"bbox": (327, 438, 574, 814), "pad": 18},
    "ui_card_frame.png": {"bbox": (327, 438, 574, 814), "pad": 18},
    "ui_diamond_button.png": {"bbox": (910, 653, 1219, 969), "pad": 18},
    "ui_tab_button_frame.png": {"bbox": (597, 696, 922, 784), "pad": 14},
    "ui_top_button_frame.png": {"bbox": (768, 46, 859, 143), "pad": 14},
}


def is_key_green(r: int, g: int, b: int) -> bool:
    return g > 150 and g - r > 80 and g - b > 80


def chroma_to_alpha(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if is_key_green(r, g, b):
                pixels[x, y] = (r, g, b, 0)
    return rgba


def expand_bbox(bbox: tuple[int, int, int, int], pad: int, size: tuple[int, int]) -> tuple[int, int, int, int]:
    x0, y0, x1, y1 = bbox
    width, height = size
    return (
        max(0, x0 - pad),
        max(0, y0 - pad),
        min(width, x1 + pad),
        min(height, y1 + pad),
    )


def main() -> None:
    atlas = Image.open(ATLAS).convert("RGB")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, spec in SLICES.items():
        crop_rect = expand_bbox(spec["bbox"], int(spec["pad"]), atlas.size)
        cropped = atlas.crop(crop_rect)
        output = chroma_to_alpha(cropped)
        out_path = OUT_DIR / name
        output.save(out_path)
        print(f"{name}: {crop_rect} -> {output.size}")


if __name__ == "__main__":
    main()
