#!/usr/bin/env python3
"""Рисует иконку приложения QP VPN и раскладывает её в Resources/AppIcon.iconset.

Запуск:  python3 scripts/make-icon.py
Дальше сборка на macOS превращает iconset в AppIcon.icns утилитой iconutil.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
PREVIEW = ROOT / "Resources" / "icon-preview.png"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"

SIZE = 1024
MARGIN = 88                       # поле вокруг плашки, как в системных иконках
RADIUS = 200                      # скругление «скруглённого квадрата» macOS

# Небо Казахстана: от светлой лазури к глубокой воде.
TOP_COLOR = (58, 190, 232)
BOTTOM_COLOR = (8, 74, 106)

FONT_CANDIDATES = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def rounded_mask(box: int, radius: int) -> Image.Image:
    mask = Image.new("L", (box, box), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, box - 1, box - 1), radius=radius, fill=255)
    return mask


def build_plate(box: int) -> Image.Image:
    """Плашка с вертикальным градиентом и мягким бликом сверху."""
    gradient = ImageOps.colorize(
        Image.linear_gradient("L").resize((box, box)),
        black=TOP_COLOR,
        white=BOTTOM_COLOR,
    ).convert("RGBA")

    # Блик: светлая дуга в верхней трети, как на системных иконках.
    glow = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        (-box * 0.25, -box * 0.75, box * 1.25, box * 0.45),
        fill=(255, 255, 255, 46),
    )
    gradient.alpha_composite(glow.filter(ImageFilter.GaussianBlur(box * 0.05)))

    # Тонкий внутренний кант — плашка не выглядит плоской заливкой.
    edge = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        (2, 2, box - 3, box - 3),
        radius=RADIUS - 2,
        outline=(255, 255, 255, 40),
        width=max(2, int(box * 0.006)),
    )
    gradient.alpha_composite(edge)

    gradient.putalpha(rounded_mask(box, RADIUS))
    return gradient


def build_icon() -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    box = SIZE - MARGIN * 2
    plate = build_plate(box)

    # Мягкая тень под плашкой.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (MARGIN, MARGIN + int(box * 0.03)), rounded_mask(box, RADIUS))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(SIZE * 0.022)))
    canvas.alpha_composite(plate, (MARGIN, MARGIN))

    draw = ImageDraw.Draw(canvas)

    # Монограмма QP — главное, что должно читаться даже в 16 пикселей.
    mark_font = load_font(int(SIZE * 0.34))
    draw.text((SIZE / 2, SIZE * 0.415), "QP", font=mark_font, fill=(255, 255, 255, 255), anchor="mm")

    # Подпись под монограммой. Хвост буквы Q доходит до 0.60 высоты,
    # поэтому слово стоит ниже — линии не соприкасаются.
    word_font = load_font(int(SIZE * 0.10))
    draw.text((SIZE / 2, SIZE * 0.695), "V P N", font=word_font, fill=(255, 255, 255, 224), anchor="mm")

    return canvas


def build_android_foreground() -> Image.Image:
    """Слой для адаптивной иконки Android: монограмма на прозрачном фоне.

    Android обрезает иконку маской разной формы, поэтому содержимое должно
    умещаться в центральные две трети холста.
    """
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    mark_font = load_font(int(SIZE * 0.225))
    draw.text((SIZE / 2, SIZE * 0.455), "QP", font=mark_font, fill=(255, 255, 255, 255), anchor="mm")

    word_font = load_font(int(SIZE * 0.068))
    draw.text((SIZE / 2, SIZE * 0.60), "V P N", font=word_font, fill=(255, 255, 255, 224), anchor="mm")
    return canvas


def write_android(icon: Image.Image) -> None:
    if not ANDROID_RES.exists():
        return

    # Обычная иконка по плотностям экрана.
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for suffix, pixels in densities.items():
        folder = ANDROID_RES / f"mipmap-{suffix}"
        folder.mkdir(parents=True, exist_ok=True)
        square = icon.resize((pixels, pixels), Image.LANCZOS)
        square.save(folder / "ic_launcher.png")

        round_icon = square.copy()
        mask = Image.new("L", (pixels, pixels), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, pixels - 1, pixels - 1), fill=255)
        round_icon.putalpha(mask)
        round_icon.save(folder / "ic_launcher_round.png")

    # Адаптивная иконка: отдельно фон, отдельно монограмма.
    foreground = build_android_foreground()
    for suffix, pixels in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        folder = ANDROID_RES / f"mipmap-{suffix}"
        folder.mkdir(parents=True, exist_ok=True)
        foreground.resize((pixels, pixels), Image.LANCZOS).save(folder / "ic_launcher_foreground.png")

    background = ImageOps.colorize(
        Image.linear_gradient("L").resize((432, 432)),
        black=TOP_COLOR,
        white=BOTTOM_COLOR,
    ).convert("RGBA")
    drawable = ANDROID_RES / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    background.save(drawable / "ic_launcher_background.png")
    print(f"Иконки Android разложены в {ANDROID_RES}")


def main() -> None:
    icon = build_icon()
    ICONSET.mkdir(parents=True, exist_ok=True)

    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = base * scale
            name = f"icon_{base}x{base}.png" if scale == 1 else f"icon_{base}x{base}@2x.png"
            icon.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name)

    write_android(icon)

    icon.save(PREVIEW)
    print(f"Иконка разложена в {ICONSET}")
    print(f"Превью: {PREVIEW}")


if __name__ == "__main__":
    main()
