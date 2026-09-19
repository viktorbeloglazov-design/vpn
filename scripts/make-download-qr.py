#!/usr/bin/env python3
"""QR-коды на загрузку самих приложений.

Человек наводит камеру телефона на код в инструкции и скачивает программу,
не перепечатывая ссылку руками. К ключу доступа эти коды отношения не имеют.

    scripts/make-download-qr.py <папка-комплекта>
"""
import sys

try:
    import segno
except ImportError:
    print("  библиотеки segno нет — QR-коды на загрузку пропущены")
    raise SystemExit(0)

stage = sys.argv[1]
apk = "https://github.com/viktorbeloglazov-design/vpn/releases/download/latest/QPVPN-android.apk"

links = {
    "Android/QR-скачать-приложение.png": apk,
    "iPhone/QR-скачать-приложение.png": "https://apps.apple.com/app/defaultvpn/id6744725017",
    "Windows/QR-скачать-AmneziaVPN.png": "https://amnezia.org/ru/downloads",
}

for name, url in links.items():
    segno.make(url, error="m").save(f"{stage}/{name}", scale=7, border=2)
    print(f"  {name}")
