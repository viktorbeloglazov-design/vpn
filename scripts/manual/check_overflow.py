# -*- coding: utf-8 -*-
"""Ищет страницы, содержимое которых не помещается в лист.

Печать молча обрезает лишнее, поэтому проверяем до, а не после.
"""
import os, pathlib, re, subprocess, sys

CHROME = os.environ.get("CHROME", "/opt/pw-browsers/chromium")

PROBE = """
<script>
window.addEventListener('load', () => {
  const bad = [];
  document.querySelectorAll('.page').forEach((p, i) => {
    const pr = p.getBoundingClientRect();
    const foot = p.querySelector('.foot, .foots');
    // Нижняя граница, ниже которой начинается подвал.
    const limit = foot ? foot.getBoundingClientRect().top : pr.bottom;
    let low = pr.top;
    p.querySelectorAll('.page > *').forEach(el => {
      if (el === foot) return;
      low = Math.max(low, el.getBoundingClientRect().bottom);
    });
    const over = Math.round(low - limit);
    if (over > -6) bad.push(`стр.${i + 1}: не влезает на ${over}px`);
  });
  document.title = bad.length ? bad.join(' | ') : 'ВСЁ ВЛЕЗАЕТ';
});
</script>
"""

ROOT = pathlib.Path(__file__).resolve().parents[2]
src = (ROOT / "docs/instrukciya/index.html").read_text(encoding="utf-8")
tmp = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "qpvpn-overflow-check.html"
tmp.write_text(src.replace("</body>", PROBE + "</body>"), encoding="utf-8")

out = subprocess.run(
    [CHROME, "--headless", "--disable-gpu", "--no-sandbox",
     "--window-size=794,1123", "--virtual-time-budget=4000", "--dump-dom",
     f"file://{tmp.resolve()}"],
    capture_output=True, text=True).stdout
title = re.search(r"<title>(.*?)</title>", out, re.S)
print(title.group(1) if title else "не удалось измерить")
sys.exit(0 if title and title.group(1) == "ВСЁ ВЛЕЗАЕТ" else 1)
