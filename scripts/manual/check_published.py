# -*- coding: utf-8 -*-
"""Сверяет выложенную инструкцию с той, что собирается из кода.

Три дня инструкция выкладывалась без правок. Правился
docs/instrukciya/index.html, а это результат работы build_manual.py:
сборка переписывала файл заново. Снаружи всё выглядело исправно —
PDF обновлялся через полминуты после коммита, проверки были зелёные.
Единственным признаком был размер: 476925 байт три выпуска подряд.

Поэтому сверяется не размер и не время, а текст: что человек читает
в скачанной инструкции против того, что сейчас в коде. Расхождение
означает, что правка до людей не дошла.
"""
import pathlib, subprocess, sys, tempfile, urllib.request

LINK = ("https://github.com/viktorbeloglazov-design/vpn/releases/"
        "download/latest/QPVPN-instrukciya.pdf")
ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent


def text_of(path):
    import pypdfium2 as pdfium
    pdf = pdfium.PdfDocument(str(path))
    return "\n".join(pdf[i].get_textpage().get_text_range() for i in range(len(pdf)))


def words(text):
    """Слова без переносов и пробелов: вёрстка рвёт строки по-разному."""
    return "".join(text.split())


def main():
    try:
        import pypdfium2  # noqa: F401
    except ImportError:
        print("пропущена: нет pypdfium2")
        return 2

    tmp = pathlib.Path(tempfile.mkdtemp())
    published = tmp / "vylozhennaya.pdf"
    try:
        with urllib.request.urlopen(LINK, timeout=120) as answer:
            published.write_bytes(answer.read())
    except Exception as beda:
        print(f"пропущена: не скачалась выложенная инструкция ({beda})")
        return 2

    # Собираем заново из кода — то, что получили бы люди при выпуске сейчас.
    built = subprocess.run(["bash", str(HERE / "build.sh")],
                           capture_output=True, text=True)
    if built.returncode != 0:
        print("не собирается:", built.stderr.strip()[-400:])
        return 1

    ours = ROOT / "docs/instrukciya/QPVPN-instrukciya.pdf"
    if words(text_of(published)) == words(text_of(ours)):
        print("выложенная инструкция совпадает с кодом")
        return 0

    print("ВЫЛОЖЕНА НЕ ТА ИНСТРУКЦИЯ: текст расходится с тем, что в коде")
    print("Значит правки до людей не дошли. Пересоберите и выложите.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
