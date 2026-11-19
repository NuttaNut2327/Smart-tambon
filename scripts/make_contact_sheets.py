from pathlib import Path
import sys

from PIL import Image, ImageDraw


def main() -> None:
    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    pages = sorted(source.glob("page-*.png"))
    per_sheet = 9
    for start in range(0, len(pages), per_sheet):
        selected = pages[start : start + per_sheet]
        thumbs = []
        for path in selected:
            image = Image.open(path).convert("RGB")
            image.thumbnail((360, 470))
            thumbs.append((path.name, image.copy()))
        sheet = Image.new("RGB", (1140, 1530), "#D9D9D9")
        draw = ImageDraw.Draw(sheet)
        for index, (name, image) in enumerate(thumbs):
            x = 15 + (index % 3) * 375
            y = 35 + (index // 3) * 495
            sheet.paste(image, (x, y))
            draw.text((x, y - 22), name, fill="black")
        sheet.save(output / f"sheet-{start // per_sheet + 1:02d}.png")


if __name__ == "__main__":
    main()
