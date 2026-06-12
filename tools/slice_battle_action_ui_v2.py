from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/ui/art_sources/battle_action_ui_sheet_v2_alpha.png"
OUTPUT = ROOT / "assets/ui/mockup_v2"

ASSETS = [
    ("action_bar_base", 0, 0),
    ("card_slot_frame", 1, 0),
    ("action_mode_frame", 0, 1),
    ("wait_button_frame", 1, 1),
]


def keep_largest_component(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel("A")
    pixels = alpha.load()
    seen: set[tuple[int, int]] = set()
    largest: list[tuple[int, int]] = []
    for y in range(cell.height):
        for x in range(cell.width):
            if pixels[x, y] <= 5 or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while stack:
                px, py = stack.pop()
                component.append((px, py))
                for nx in range(max(0, px - 1), min(cell.width, px + 2)):
                    for ny in range(max(0, py - 1), min(cell.height, py + 2)):
                        if pixels[nx, ny] > 5 and (nx, ny) not in seen:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
            if len(component) > len(largest):
                largest = component
    if not largest:
        return cell
    keep = set(largest)
    result = cell.copy()
    out = result.load()
    for y in range(cell.height):
        for x in range(cell.width):
            if (x, y) not in keep:
                r, g, b, _a = out[x, y]
                out[x, y] = (r, g, b, 0)
    return result


def crop_asset(source: Image.Image, col: int, row: int, padding: int = 18) -> Image.Image:
    cell_w = source.width // 2
    cell_h = source.height // 2
    cell = source.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
    cell = keep_largest_component(cell)
    bbox = cell.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError(f"Empty alpha region at cell ({col}, {row})")
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - padding)
    y0 = max(0, y0 - padding)
    x1 = min(cell.width, x1 + padding)
    y1 = min(cell.height, y1 + padding)
    return cell.crop((x0, y0, x1, y1))


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, col, row in ASSETS:
        asset = crop_asset(source, col, row)
        asset.save(OUTPUT / f"{name}.png")
        print(f"{name}: {asset.width}x{asset.height}")


if __name__ == "__main__":
    main()
