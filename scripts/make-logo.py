#!/usr/bin/env python3
"""Готовит логотип Kupibas для приложений.

Исходник — тёмно-синий знак с голубой заливкой. На тёмной шапке приложения
синий почти не виден, поэтому делается светлый вариант: синее становится
белым, голубое — светлее, чтобы читалось на градиенте.

Запуск: python3 scripts/make-logo.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources" / "brand" / "kupibas-logo-source.png"

NAVY = (27, 56, 100)       # тёмно-синий знака
CYAN = (41, 196, 240)      # голубая вода

LIGHT_NAVY = (255, 255, 255)
LIGHT_CYAN = (150, 226, 255)


def distance(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def recolor(image: Image.Image) -> Image.Image:
    """Перекрашивает знак под тёмный фон, сохраняя сглаживание краёв."""
    image = image.convert("RGBA")
    pixels = image.load()

    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            source = (r, g, b)
            target = LIGHT_NAVY if distance(source, NAVY) < distance(source, CYAN) else LIGHT_CYAN
            pixels[x, y] = (target[0], target[1], target[2], a)

    return image


def save(image: Image.Image, path: Path, width: int) -> None:
    height = round(image.height * width / image.width)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((width, height), Image.LANCZOS).save(path)
    print(f"  {path.relative_to(ROOT)} — {width}×{height}")


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    light = recolor(source.copy())

    print("Логотип для тёмного фона:")
    android = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi"
    save(light, android / "kupibas_logo.png", 900)

    print("Логотип для приложения Mac:")
    mac = ROOT / "Resources" / "brand"
    save(light, mac / "kupibas-logo-on-dark.png", 900)
    save(source, mac / "kupibas-logo-on-light.png", 900)


if __name__ == "__main__":
    main()
