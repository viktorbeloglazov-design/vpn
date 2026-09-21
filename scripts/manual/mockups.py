# -*- coding: utf-8 -*-
"""Макеты экранов приложения.

Нарисованы по вёрстке самих приложений: цвета, подписи и порядок карточек
взяты из кода, а не по памяти. Это схемы экранов, а не фотографии.
"""


def icon(name, color, size="3.2mm"):
    """Иконка в один цвет.

    Эмодзи здесь не годятся: шрифт подставляет то жёлтый ключик, то контур,
    и макет перестаёт походить на приложение, где иконки одноцветные.
    """
    paths = {
        "shield": "M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5l-8-3z",
        "key": ("M14 6a4 4 0 1 0-3.9 5L9 12l-1.5 1.5L9 15l-1.5 1.5L9 18l-2 2-2-2 5.1-5.1"
                "A4 4 0 0 0 14 6zm1.2-1.2a2 2 0 1 1 2.8 2.8 2 2 0 0 1-2.8-2.8z"),
        "gear": ("M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm9 4-2.1-.6a7 7 0 0 0-.7-1.7l1-1.9-1.9-2"
                 "-1.9 1a7 7 0 0 0-1.8-.7L12.8 4h-2.6l-.6 2.1a7 7 0 0 0-1.7.7l-1.9-1-2 1.9"
                 "1 1.9a7 7 0 0 0-.7 1.8L2 12.8v2.6l2.1.6a7 7 0 0 0 .7 1.7l-1 1.9 1.9 2 1.9-1"
                 "a7 7 0 0 0 1.8.7l.6 2.1h2.6l.6-2.1a7 7 0 0 0 1.7-.7l1.9 1 2-1.9-1-1.9"
                 "a7 7 0 0 0 .7-1.8L22 12.8V12z"),
        "globe": ("M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 2c1.3 0 2.6 2.2 3.1 5H8.9"
                  "C9.4 6.2 10.7 4 12 4zM4.3 11h3.3c0-.7.1-1.4.2-2H4.8c-.2.6-.4 1.3-.5 2z"
                  "M12 20c-1.3 0-2.6-2.2-3.1-5h6.2c-.5 2.8-1.8 5-3.1 5zm4.4-7H7.6"
                  "a17 17 0 0 1 0-2h8.8a17 17 0 0 1 0 2z"),
        "power": "M11 3h2v9h-2V3zm-4 3.3 1.4 1.4a6 6 0 1 0 7.2 0L17 6.3a8 8 0 1 1-10 0z",
        "down": "M12 3v12l4-4 1.4 1.4L12 18l-5.4-5.6L8 11l4 4V3z",
    }
    return (f'<svg viewBox="0 0 24 24" width="{size}" height="{size}" '
            f'style="vertical-align:-0.5mm"><path fill="{color}" d="{paths[name]}"/></svg>')


STATUS_BAR = ('<div class="sbar"><span>9:41</span>'
              '<span class="icons">{extra}<span>&#9679;</span><span>&#9650;</span>'
              '<span>&#9632;</span><span>82%</span></span></div>')

VPN_KEY = ('<span style="color:#3ABEE8;font-weight:bold">'
           + icon("key", "#3ABEE8", "2.2mm") + ' VPN</span>')


def phone_home():
    """Главный экран Android: подключено, значок VPN в строке состояния."""
    return f"""
<div class="phone">
  {STATUS_BAR.format(extra=VPN_KEY)}
  <div class="hero">
    <div class="brand">KUPIBAS</div>
    <div style="color:#fff;font-size:8.4pt;font-weight:bold;margin-top:1.6mm">Premium VPN</div>
    <div class="brand-sub">SPECIAL FOR KUPIBAS GROUP</div>
    <div class="pwr on">{icon("power", "#FFFFFF", "6mm")}</div>
    <div class="state ok">Подключён</div>
    <div class="state-sub">91.201.xx.xx:51820</div>
    <div class="stats">
      <div><div class="k">В СЕТИ</div><div class="v">12 мин</div></div>
      <div><div class="k">ПРИНЯТО</div><div class="v">412 МБ</div></div>
      <div><div class="k">ОТПРАВЛЕНО</div><div class="v">38 МБ</div></div>
    </div>
  </div>
  <div class="body">
    <div class="sechdr">Как идёт трафик<span class="hint">Настраивать ничего не нужно</span></div>
    <div class="card">
      <div class="row"><div class="dot sky"></div><div>
        <div class="t">Заблокированные сервисы</div>
        <div class="d">Идут через VPN, казахстанский адрес</div></div></div>
      <div class="row"><div class="dot grn"></div><div>
        <div class="t">Российские сайты</div>
        <div class="d">МАХ, госуслуги, банки, маркетплейсы — напрямую</div></div></div>
      <div class="row"><div class="dot grn"></div><div>
        <div class="t">Мимо VPN целиком</div>
        <div class="d">MAX, Сбербанк, Госуслуги, ВТБ, Ozon, Wildberries и ещё 21</div></div></div>
      <div class="kv"><div class="t">Маршрутов в туннеле</div><div class="v">2617</div></div>
    </div>
    <div class="card">
      <div class="row" style="align-items:center">
        <div style="flex:1"><div class="t">Рабочие ресурсы</div>
        <div class="d">4 адреса · заложены в приложение</div></div>
        <div class="sw"></div>
      </div>
    </div>
  </div>
  <div class="nav">
    <div class="act"><span class="ic">{icon("shield", "#3ABEE8")}</span>Главная</div>
    <div><span class="ic">{icon("key", "#7D93A2")}</span>Профиль</div>
    <div><span class="ic">{icon("gear", "#7D93A2")}</span>Ещё</div>
  </div>
</div>"""


def phone_profile():
    """Вкладка «Профиль» — сюда загружается конфигурация."""
    return f"""
<div class="phone">
  {STATUS_BAR.format(extra='')}
  <div style="background:#0A2534;padding:3.5mm 3mm">
    <div style="color:#fff;font-size:9pt;font-weight:bold">Профиль</div>
    <div style="color:#9FC4D6;font-size:5.8pt">Ключ от вашего сервера</div>
  </div>
  <div class="body" style="padding-top:3mm">
    <div class="card" style="border:.3mm dashed #32424E;background:#101922">
      <div class="t" style="color:#E2A33C">Профиль не загружен</div>
      <div class="d">Загрузите файл .conf от вашего сервера — Amnezia, WireGuard
        или любой другой, который выдаёт конфигурацию WireGuard.</div>
    </div>
    <div class="btn">Сканировать QR из Amnezia</div>
    <div class="btn ghost">QR со снимка экрана</div>
    <div class="btn ghost">Вставить ссылку vpn://</div>
    <div class="btn ghost">Выбрать файл .conf</div>
    <div class="card" style="margin-top:2.5mm">
      <div class="t">Как поделиться из Amnezia</div>
      <div class="d">Amnezia &#8594; ваш сервер &#8594; «Поделиться» &#8594; QR-код
        или ссылка vpn://. Наведите камеру или скопируйте ссылку и вернитесь сюда.</div>
    </div>
  </div>
  <div class="nav">
    <div><span class="ic">{icon("shield", "#7D93A2")}</span>Главная</div>
    <div class="act"><span class="ic">{icon("key", "#3ABEE8")}</span>Профиль</div>
    <div><span class="ic">{icon("gear", "#7D93A2")}</span>Ещё</div>
  </div>
</div>"""


def _titlebar(mac=True, name="QP VPN"):
    if mac:
        dots = ('<div class="tl" style="background:#FF5F57"></div>'
                '<div class="tl" style="background:#FEBC2E"></div>'
                '<div class="tl" style="background:#28C840"></div>')
        return f'<div class="titlebar">{dots}<span class="name">{name}</span></div>'
    ctrl = ('<span style="color:#9FB2BF;font-size:6pt;letter-spacing:2mm">'
            '&#8212; &#9633; &#10005;</span>')
    return ('<div class="titlebar"><span class="name" style="margin-left:0;flex:1">'
            f'{name}</span>{ctrl}</div>')


def mac_home():
    return f"""
<div class="win">
  {_titlebar(mac=True, name="QP VPN — строка меню: " + icon("shield", "#3ABEE8", "2.4mm"))}
  <div class="tabs"><div class="act">Главная</div><div>Сервер</div><div>Ещё</div></div>
  <div class="wbody" style="background:#141C24">
    <div style="display:flex;gap:5mm;align-items:center">
      <div class="pwr on" style="margin:0">{icon("power", "#FFFFFF", "6mm")}</div>
      <div style="flex:1">
        <div class="state ok" style="font-size:10pt">Подключён</div>
        <div class="state-sub" style="font-size:6.4pt">KZ-Алматы · 91.201.xx.xx:51820</div>
        <div class="d" style="margin-top:1.2mm">Обход блокировок — мимо VPN:
          российская зона · маршрутов: 8649 · пакет 1420</div>
      </div>
      <div style="text-align:right">
        <div class="k" style="color:#7FA6BC;font-size:5.4pt">ПРИНЯТО</div>
        <div class="v" style="color:#fff;font-size:8pt;font-weight:bold">412,3 МБ</div>
        <div class="k" style="color:#7FA6BC;font-size:5.4pt;margin-top:1.4mm">ОТПРАВЛЕНО</div>
        <div class="v" style="color:#fff;font-size:8pt;font-weight:bold">38,1 МБ</div>
      </div>
    </div>
    <div class="card" style="margin-top:3mm">
      <div class="row" style="align-items:center">
        <div style="flex:1"><div class="t">Рабочие ресурсы</div>
          <div class="d">Единственный переключатель. Остальное зашито</div></div>
        <div class="sw"></div>
      </div>
    </div>
    <div class="btn ghost" style="margin-top:2mm">{icon("globe", "#3ABEE8", "2.6mm")}  Проверить мой IP
      &#8594; 91.201.xx.xx · KZ, Almaty</div>
  </div>
</div>"""


def mac_server():
    return f"""
<div class="win">
  {_titlebar(mac=True)}
  <div class="tabs"><div>Главная</div><div class="act">Сервер</div><div>Ещё</div></div>
  <div class="wbody" style="background:#141C24">
    <div class="btn">Открыть файл или QR-код…</div>
    <div class="btn ghost">Вставить из буфера</div>
    <div class="btn ghost">Вставить текстом…</div>
    <div class="card" style="border:.3mm dashed #32424E;text-align:center;padding:5mm 3mm;margin-top:2.5mm">
      <div class="t">{icon("down", "#3ABEE8", "5mm")}</div>
      <div class="d">Перетащите сюда файл .conf или картинку с QR-кодом —
        прочитаю и то, и другое</div>
    </div>
    <div class="row" style="margin-top:2.5mm">
      <div class="dot grn"></div>
      <div class="t" style="color:#7FE3BD">Конфигурация заполнена</div>
    </div>
  </div>
</div>"""


def win_home():
    return f"""
<div class="win">
  {_titlebar(mac=False, name="QP VPN")}
  <div class="wbody">
    <div style="text-align:center;padding-bottom:1mm">
      <div class="brand">KUPIBAS</div>
      <div class="pwr on" style="margin:2.5mm auto 1.6mm">{icon("power", "#FFFFFF", "6mm")}</div>
      <div class="state ok">Подключён</div>
      <div class="state-sub">Сервер 91.201.xx.xx · маршрутов: 2617 · пакет 1420</div>
      <div class="stats" style="margin-top:2.5mm">
        <div><div class="k">ПРИНЯТО</div><div class="v">412 МБ</div></div>
        <div><div class="k">ОТПРАВЛЕНО</div><div class="v">38 МБ</div></div>
      </div>
    </div>
    <div class="card" style="margin-top:2.5mm">
      <div class="t" style="font-size:7pt">Как идёт трафик</div>
      <div class="d" style="margin-bottom:1.4mm">Российские сайты — МАХ, госуслуги,
        банки, маркетплейсы — напрямую</div>
      <div class="row" style="align-items:center;border-top:.2mm solid #22303B;padding-top:1.8mm">
        <div style="flex:1"><div class="t">Рабочие ресурсы</div></div>
        <div class="sw"></div>
      </div>
    </div>
    <div class="card">
      <div class="t" style="font-size:7pt">Скорость</div>
      <div class="d">Через VPN и без него — на одной и той же закачке</div>
      <div class="btn ghost" style="margin-top:1.6mm">Замерить скорость</div>
      <div class="t" style="font-weight:normal;margin-top:1mm">Размер пакета (MTU)</div>
      <div class="mtu"><span class="on">Авто</span><span>1420</span>
        <span>1380</span><span>1280</span></div>
    </div>
  </div>
</div>"""


def win_profile():
    return f"""
<div class="win">
  {_titlebar(mac=False, name="QP VPN")}
  <div class="wbody">
    <div class="card">
      <div class="t" style="font-size:7pt">Ключ</div>
      <div class="d" style="margin-bottom:1.8mm">Ключа нет. Вставьте ссылку vpn://
        или откройте файл.</div>
      <div class="btn">Вставить ключ vpn:// из буфера</div>
      <div class="btn ghost">Открыть файл .conf или картинку с QR-кодом</div>
    </div>
    <div class="card">
      <div class="t" style="font-size:7pt">Запасной вход</div>
      <div class="d">Необязательно. Адрес узла-пересыльщика в виде адрес:порт.
        Программа пробует сервер напрямую, а если он не ответит — этот узел.</div>
      <div style="background:#1E2932;border-radius:1.4mm;padding:1.6mm;margin-top:1.4mm;
                  color:#7D93A2;font-size:5.8pt">95.213.0.1:31984</div>
    </div>
  </div>
</div>"""
