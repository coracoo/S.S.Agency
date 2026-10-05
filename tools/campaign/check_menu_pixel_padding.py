#!/usr/bin/env python3
"""比较实际有字/无字的Godot成对截图，检查字形像素不侵入装饰边框。"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops


def inspect(directory: Path):
    rows, errors = [], []
    for metadata in sorted(directory.glob('*_text_bounds.json')):
        data = json.loads(metadata.read_text())
        path = directory / data['image']
        visible = Image.open(path).convert('RGB')
        hidden = Image.open(path.with_name(path.stem + '_notext.png')).convert('RGB')
        difference = ImageChops.difference(visible, hidden)
        red, green, blue = difference.split()
        mask = ImageChops.lighter(ImageChops.lighter(red, green), blue).point(lambda v: 255 if v > 30 else 0)
        for button in data['buttons']:
            if not button['text']:
                continue
            x, y, width, height = button['rect']
            box = (round(x), round(y), round(x + width), round(y + height))
            ink = mask.crop(box).getbbox()
            if ink is None:
                errors.append(f"{path.name}: 没有捕获文字 {button['text']}")
                continue
            left, top, right, bottom = ink
            scale = data['scale']
            margins = [left / scale, top / scale, (box[2] - box[0] - right) / scale, (box[3] - box[1] - bottom) / scale]
            rows.append({'image': path.name, 'text': button['text'], 'ink_margins_1920': [round(v, 1) for v in margins]})
            # 规范化纹理的铜框/斜切角占约20px，实际文字像素再留至少2px净空。
            if min(margins[1], margins[3]) < 22 - 1 / scale or min(margins[0], margins[2]) < 20 - 1 / scale:
                errors.append(f"{path.name}: 字形侵入安全边距 {button['text']} {margins}")
    if not rows:
        errors.append('没有有效成对截图，不能把缺少图形证据当作通过')
    return rows, errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    rows, errors = inspect(args.directory)
    (args.directory / 'pixel-padding-report.json').write_text(json.dumps({'checked': len(rows), 'errors': errors, 'buttons': rows}, ensure_ascii=False, indent=2))
    print(f'MENU_PIXEL_PADDING: {len(rows)} buttons, {len(errors)} failures')
    for error in errors:
        print('FAIL:', error)
    raise SystemExit(bool(errors))
