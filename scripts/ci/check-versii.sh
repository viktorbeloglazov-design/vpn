#!/usr/bin/env bash
# Сверяет версию внутри выложенной сборки с номером, лежащим рядом.
#
# Приложения обновляются сами: читают файл вида android-version.txt
# и сравнивают с собственным номером. Если номер рядом со сборкой
# новее, чем номер внутри неё, обновление предлагается бесконечно:
# программа скачивает 60 мегабайт, ставит их, снова видит себя
# старой и снова качает. На Mac это уже случалось — в release.yml
# с тех пор стоит проверка при сборке.
#
# Но проверка при сборке говорит только про момент сборки. Файлы
# выкладываются по одному, и рассинхрон возникает при выкладке:
# номер обновился, а сама сборка не перезалилась. Поэтому смотрим
# на то, что человек скачивает.
set -uo pipefail

python3 - <<'PY'
import re, shutil, subprocess, sys, tempfile, urllib.request, zipfile

BASE = ("https://github.com/viktorbeloglazov-design/vpn/releases/"
        "download/latest")

bed = 0
propuscheno = 0


def skachat(name, to=None):
    with urllib.request.urlopen(f"{BASE}/{name}", timeout=300) as answer:
        data = answer.read()
    if to:
        with open(to, "wb") as f:
            f.write(data)
        return to
    return data


def ryadom(name):
    return skachat(name).decode("utf-8", "replace").strip()


def skazat(chto, vnutri, zayavleno):
    global bed
    if vnutri == zayavleno:
        print(f"{chto}: внутри {vnutri}, рядом {zayavleno} — сходится")
    else:
        print(f"{chto}: ВНУТРИ {vnutri}, А РЯДОМ {zayavleno}")
        print("    Обновление будет предлагаться бесконечно: программа "
              "скачает сборку и снова увидит себя старой.")
        bed += 1


def propustit(chto, pochemu):
    global propuscheno
    print(f"{chto}: пропущена ({pochemu})")
    propuscheno += 1


# ── Windows ──────────────────────────────────────────────────────────
# Версия стоит в имени папки внутри архива — её видно в оглавлении.
try:
    zayavleno = ryadom("windows-version.txt")
    with tempfile.TemporaryDirectory() as papka:
        arhiv = skachat("QPVPN-windows.zip", f"{papka}/win.zip")
        imena = zipfile.ZipFile(arhiv).namelist()
    nashli = {m.group(1) for name in imena
              if (m := re.match(r"QPVPN-windows-([0-9][0-9.]*)/", name))}
    if len(nashli) == 1:
        skazat("Windows", nashli.pop(), zayavleno)
    else:
        propustit("Windows", f"в архиве папки {sorted(imena)[:3]}")
except Exception as beda:
    propustit("Windows", str(beda)[:80])

# ── Android ──────────────────────────────────────────────────────────
try:
    from pyaxmlparser import APK
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet",
                    "pyaxmlparser"], capture_output=True)
    try:
        from pyaxmlparser import APK
    except ImportError:
        APK = None

if APK is None:
    propustit("Android", "нет pyaxmlparser")
else:
    try:
        zayavleno = ryadom("android-version.txt")
        with tempfile.TemporaryDirectory() as papka:
            путь = skachat("QPVPN-android.apk", f"{papka}/app.apk")
            skazat("Android", APK(путь).version_name, zayavleno)
    except Exception as beda:
        propustit("Android", str(beda)[:80])

# ── Mac ──────────────────────────────────────────────────────────────
if shutil.which("7z") is None:
    propustit("Mac", "нет 7z — образ .dmg не открыть")
else:
    try:
        zayavleno = ryadom("mac-version.txt")
        with tempfile.TemporaryDirectory() as papka:
            obraz = skachat("QPVPN-mac.dmg", f"{papka}/mac.dmg")
            subprocess.run(["7z", "e", "-y", f"-o{papka}", obraz,
                            "QPVPN.app/Contents/Info.plist"],
                           capture_output=True, check=True)
            plist = open(f"{papka}/Info.plist", "rb").read()
            nayden = re.search(
                rb"CFBundleShortVersionString</key>\s*<string>"
                rb"([0-9][0-9.]*)</string>", plist)
            if nayden:
                skazat("Mac", nayden.group(1).decode(), zayavleno)
            else:
                propustit("Mac", "в Info.plist нет номера версии")
    except Exception as beda:
        propustit("Mac", str(beda)[:80])

if bed:
    raise SystemExit(1)
if propuscheno:
    print(f"пропущена: проверено не всё, {propuscheno} из 3 не удалось")
    raise SystemExit(2)
raise SystemExit(0)
PY
