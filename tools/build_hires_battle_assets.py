from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GREEN_KEY = (0, 255, 0)


def keyed_alpha(img: Image.Image, tolerance: int = 28) -> Image.Image:
    rgba = img.convert("RGBA")
    pix = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if g > 150 and g > r * 1.55 and g > b * 1.55:
                pix[x, y] = (r, g, b, 0)
            elif g > r * 1.18 and g > b * 1.18:
                despilled_g = min(g, max(r, b) + 18)
                pix[x, y] = (r, despilled_g, b, a)
    return rgba


def content_bbox(img: Image.Image, pad: int = 10) -> tuple[int, int, int, int]:
    alpha = img.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return (0, 0, img.width, img.height)
    x0, y0, x1, y1 = bbox
    return (
        max(0, x0 - pad),
        max(0, y0 - pad),
        min(img.width, x1 + pad),
        min(img.height, y1 + pad),
    )


def remove_green_fringe(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    pix = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a <= 80 and g > 35 and g > r * 1.15 and g > b * 1.15:
                pix[x, y] = (r, g, b, 0)
    return rgba


def remove_small_alpha_components(img: Image.Image, min_area: int = 90) -> Image.Image:
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A")
    w, h = rgba.size
    pix = alpha.load()
    seen = set()
    remove_points = []
    for y in range(h):
        for x in range(w):
            if pix[x, y] == 0 or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            points = []
            min_x = x
            max_x = x
            min_y = y
            max_y = y
            while stack:
                px, py = stack.pop()
                points.append((px, py))
                min_x = min(min_x, px)
                max_x = max(max_x, px)
                min_y = min(min_y, py)
                max_y = max(max_y, py)
                for nx in range(px - 1, px + 2):
                    for ny in range(py - 1, py + 2):
                        if nx == px and ny == py:
                            continue
                        if nx < 0 or ny < 0 or nx >= w or ny >= h:
                            continue
                        if pix[nx, ny] > 0 and (nx, ny) not in seen:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
            comp_w = max_x - min_x + 1
            comp_h = max_y - min_y + 1
            is_tiny = len(points) < min_area
            is_narrow_sliver = comp_w <= 5 and comp_h >= 16
            is_bottom_slice = comp_h <= 7 and comp_w >= 12 and min_y >= int(h * 0.72)
            if is_tiny or is_narrow_sliver or is_bottom_slice:
                remove_points += points
    out_pix = rgba.load()
    for x, y in remove_points:
        r, g, b, _a = out_pix[x, y]
        out_pix[x, y] = (r, g, b, 0)
    return rgba


def fit_on_canvas(
    img: Image.Image,
    size: int,
    fill_ratio: float = 0.90,
    min_component_area: int = 90,
) -> Image.Image:
    bbox = content_bbox(img)
    cropped = img.crop(bbox)
    scale = min((size * fill_ratio) / max(cropped.width, 1), (size * fill_ratio) / max(cropped.height, 1))
    new_size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
    resized = remove_small_alpha_components(
        remove_green_fringe(cropped.resize(new_size, Image.Resampling.LANCZOS)),
        min_component_area,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((size - resized.width) // 2, (size - resized.height) // 2))
    return remove_small_alpha_components(remove_green_fringe(canvas), min_component_area)


def slice_player_sheets() -> None:
    src = keyed_alpha(Image.open(ROOT / "assets/sprites/generated/player_sprite_atlas_v1_source.png"))
    out_dir = ROOT / "assets/sprites/hires"
    out_dir.mkdir(parents=True, exist_ok=True)
    names = ["rinne", "mint", "homura", "zhongkui"]
    cell_w = src.width / 4.0
    cell_h = src.height / 4.0
    for row, name in enumerate(names):
        sheet = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        for direction in range(4):
            for frame in range(4):
                # Source rows are characters, source columns are subtle idle frames.
                x0 = round(frame * cell_w)
                y0 = round(row * cell_h)
                x1 = round((frame + 1) * cell_w)
                y1 = round((row + 1) * cell_h)
                frame_img = fit_on_canvas(src.crop((x0, y0, x1, y1)), 128, 0.92, 350)
                sheet.alpha_composite(frame_img, (frame * 128, direction * 128))
        sheet.save(out_dir / f"{name}_idle.png")


def slice_world_assets() -> None:
    src = Image.open(ROOT / "assets/generated/atlas/world_actions_atlas_v1_alpha.png").convert("RGBA")
    out_dir = ROOT / "assets/tiles/generated_v4"
    out_dir.mkdir(parents=True, exist_ok=True)
    cells = {
        "effect_fire": (0, 0),
        "effect_water": (1, 0),
        "effect_explosion": (2, 0),
        "effect_curse": (3, 0),
        "effect_talisman": (0, 1),
        "effect_rice": (1, 1),
        "object_brazier": (2, 1),
        "object_water_barrel": (3, 1),
        "object_rice_bag": (0, 2),
        "object_bell": (1, 2),
        "object_door": (2, 2),
        "object_coffin": (3, 2),
        "object_explosive_barrel": (0, 3),
    }
    cell_w = src.width / 4.0
    cell_h = src.height / 4.0
    for name, (col, row) in cells.items():
        x0 = round(col * cell_w)
        y0 = round(row * cell_h)
        x1 = round((col + 1) * cell_w)
        y1 = round((row + 1) * cell_h)
        asset = fit_on_canvas(src.crop((x0, y0, x1, y1)), 512, 0.92)
        asset.save(out_dir / f"{name}.png")


def non_key_components(img: Image.Image) -> list[tuple[int, int, int, int, int]]:
    rgb = img.convert("RGB")
    pix = rgb.load()
    w, h = rgb.size
    mask = set()
    for y in range(h):
        for x in range(w):
            r, g, b = pix[x, y]
            if not (g > 150 and g > r * 1.5 and g > b * 1.5):
                mask.add((x, y))
    seen = set()
    comps = []
    for point in list(mask):
        if point in seen:
            continue
        stack = [point]
        seen.add(point)
        xs = []
        ys = []
        while stack:
            x, y = stack.pop()
            xs.append(x)
            ys.append(y)
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) in mask and (nx, ny) not in seen:
                    seen.add((nx, ny))
                    stack.append((nx, ny))
        if len(xs) > 1000:
            comps.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1, len(xs)))
    return comps


def slice_enemy_sheets() -> None:
    src = keyed_alpha(Image.open(ROOT / "assets/generated/folk_enemies_source.png"))
    out_dir = ROOT / "assets/sprites/hires"
    out_dir.mkdir(parents=True, exist_ok=True)
    groups = {
        "paper_effigy": [],
        "water_ghost": [],
        "jiangshi": [],
        "red_lady": [],
        "coffin_lord": [],
    }
    for comp in non_key_components(src):
        x0, y0, x1, y1, _area = comp
        cx = (x0 + x1) * 0.5
        if cx < 470:
            groups["paper_effigy"].append(comp)
        elif cx < 900:
            groups["water_ghost"].append(comp)
        elif cx < 1260:
            groups["jiangshi"].append(comp)
        elif cx < 1660:
            groups["red_lady"].append(comp)
        else:
            groups["coffin_lord"].append(comp)

    for name, comps in groups.items():
        rows: list[list[tuple[int, int, int, int, int]]] = []
        for comp in sorted(comps, key=lambda c: ((c[1] + c[3]) * 0.5, (c[0] + c[2]) * 0.5)):
            cy = (comp[1] + comp[3]) * 0.5
            if not rows or abs(((rows[-1][0][1] + rows[-1][0][3]) * 0.5) - cy) > 55:
                rows.append([comp])
            else:
                rows[-1].append(comp)
        rows = rows[:4]
        sheet = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        for row_i in range(4):
            row = sorted(rows[min(row_i, len(rows) - 1)], key=lambda c: (c[0] + c[2]) * 0.5)
            if len(row) == 0:
                continue
            while len(row) < 4:
                row.append(row[-1])
            for frame_i in range(4):
                x0, y0, x1, y1, _area = row[frame_i]
                pad = 14
                crop = src.crop((
                    max(0, x0 - pad),
                    max(0, y0 - pad),
                    min(src.width, x1 + pad),
                    min(src.height, y1 + pad),
                ))
                frame = fit_on_canvas(crop, 128, 0.90 if name != "coffin_lord" else 0.95, 350)
                sheet.alpha_composite(frame, (frame_i * 128, row_i * 128))
        sheet.save(out_dir / f"{name}_idle.png")


def main() -> None:
    slice_player_sheets()
    slice_enemy_sheets()
    slice_world_assets()


if __name__ == "__main__":
    main()
