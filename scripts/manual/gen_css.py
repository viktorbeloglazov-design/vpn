CSS = r"""
@page { size: A4; margin: 0; }
* { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
html, body { margin: 0; padding: 0; }
body {
  font-family: "Liberation Sans", "DejaVu Sans", sans-serif;
  color: #14202A; background: #fff; font-size: 10.2pt; line-height: 1.45;
}
.page {
  width: 210mm; height: 297mm; padding: 14mm 15mm 12mm; page-break-after: always;
  position: relative; overflow: hidden; background: #fff;
}
.page:last-child { page-break-after: auto; }

/* Шапка и подвал */
.head { display: flex; align-items: baseline; justify-content: space-between;
        border-bottom: 0.5mm solid #0E7FA8; padding-bottom: 2.5mm; margin-bottom: 6mm; }
.head .who { font-size: 9pt; color: #0E7FA8; font-weight: bold; letter-spacing: .3px; }
.head .num { font-size: 9pt; color: #7D8E9B; }
.foot { position: absolute; left: 15mm; right: 15mm; bottom: 7mm;
        font-size: 7.6pt; color: #94A4B0; display: flex; justify-content: space-between;
        border-top: 0.2mm solid #DFE6EC; padding-top: 2mm; }

h1 { font-size: 20pt; margin: 0 0 2mm; line-height: 1.15; }
h2 { font-size: 15pt; margin: 0 0 1.5mm; }
.sub { color: #5B6C78; font-size: 10pt; margin: 0 0 6mm; }

/* Двухколоночная раскладка «макет + шаги» */
.split { display: flex; gap: 8mm; align-items: flex-start; }
.split .left { flex: 0 0 64mm; }
.split .wide { flex: 0 0 96mm; }
.split .mid { flex: 0 0 80mm; }
.split .right { flex: 1; min-width: 0; }

ol.steps { margin: 0; padding: 0; list-style: none; counter-reset: s; }
ol.steps > li { counter-increment: s; position: relative; padding-left: 9mm; margin-bottom: 3.4mm; }
ol.steps > li::before {
  content: counter(s); position: absolute; left: 0; top: 0.2mm;
  width: 6.2mm; height: 6.2mm; border-radius: 50%; background: #0E7FA8; color: #fff;
  font-size: 8.4pt; font-weight: bold; display: flex; align-items: center; justify-content: center;
}
ol.steps b { color: #0B2B3A; }
.note { background: #EAF6FB; border-left: 1mm solid #0E7FA8; padding: 3mm 4mm; margin-top: 4mm; font-size: 9.2pt; }
.warn { background: #FDF1EE; border-left: 1mm solid #D9634F; padding: 3mm 4mm; margin-top: 4mm; font-size: 9.2pt; }
/* Имена файлов не переносим: «QPVPN.exe», разорванное на «Q» и «PVPN.exe»,
   читается как два разных файла. */
.mono { font-family: "Liberation Mono", "DejaVu Sans Mono", monospace; font-size: 8.6pt;
        background: #F2F6F9; padding: 0.6mm 1.4mm; border-radius: 1mm; white-space: nowrap; }
.cmd { font-family: "Liberation Mono", "DejaVu Sans Mono", monospace; font-size: 8.2pt;
       background: #0B1720; color: #CFE6F2; padding: 2.6mm 3mm; border-radius: 1.5mm;
       margin-top: 2mm; word-break: break-all; line-height: 1.35; }
.cap { font-size: 7.8pt; color: #94A4B0; text-align: center; margin-top: 2mm; }

/* Ссылки. В PDF они кликаются, поэтому их должно быть видно: читатель
   не догадается нажать на слово, которое выглядит как обычный текст. */
a { text-decoration: none; }
.lnk { color: #0E7FA8; border-bottom: 0.3mm solid #9AD3EA; font-weight: bold; }
.plain { color: inherit; }
.dl a.item { display: block; color: inherit; }
.dl .tap { font-size: 6.6pt; color: #3ABEE8; margin-top: 1.6mm; letter-spacing: .2px; }

table { width: 100%; border-collapse: collapse; font-size: 9.2pt; }
th { text-align: left; background: #0E7FA8; color: #fff; padding: 2.2mm 3mm; font-size: 8.8pt; }
td { padding: 2.4mm 3mm; border-bottom: 0.2mm solid #E3EAEF; vertical-align: top; }
tr:nth-child(even) td { background: #F7FAFC; }

/* ─────────── Макеты экранов ─────────── */
.phone { width: 62mm; border-radius: 6mm; background: #0A1015;
         border: 1.1mm solid #263543; overflow: hidden; margin: 0 auto;
         box-shadow: 0 1mm 3mm rgba(10,25,35,.16); }
.sbar { display: flex; justify-content: space-between; align-items: center;
        padding: 1.4mm 3mm 0.8mm; font-size: 6pt; color: #DCE7EF; background: #0A2534; }
.sbar .icons { display: flex; gap: 1.2mm; align-items: center; }
.hero { background: linear-gradient(#10506E, #0A2534); padding: 4mm 4mm 5mm; text-align: center; }
.brand { color: #fff; font-size: 11pt; font-weight: bold; letter-spacing: .4px; }
.brand-sub { color: #9FC4D6; font-size: 5.6pt; letter-spacing: .6px; margin-top: .6mm; }
.pwr { width: 20mm; height: 20mm; border-radius: 50%; margin: 3.5mm auto 2.5mm;
       display: flex; align-items: center; justify-content: center;
       color: #fff; font-size: 7pt; font-weight: bold; }
.pwr.on  { background: #0E7FA8; border: 1mm solid #3ABEE8; }
.pwr.off { background: #1E2932; border: 1mm solid #32424E; color: #9FB2BF; }
.state { color: #fff; font-size: 9pt; font-weight: bold; }
.state.ok { color: #7FE3BD; }
.state-sub { color: #9FC4D6; font-size: 6pt; margin-top: .5mm; }
.stats { display: flex; justify-content: space-around; margin-top: 3.5mm; }
.stats div { text-align: center; }
.stats .k { color: #7FA6BC; font-size: 4.8pt; letter-spacing: .5px; }
.stats .v { color: #fff; font-size: 7.4pt; font-weight: bold; margin-top: .4mm; }
.body { padding: 3mm; background: #0A1015; }
.sechdr { color: #E6EDF3; font-size: 7.2pt; font-weight: bold; margin: 2.5mm 0 .4mm; }
.sechdr .hint { display: block; color: #7D93A2; font-size: 5.8pt; font-weight: normal; }
.card { background: #141C24; border-radius: 2.6mm; padding: 2.6mm; margin-bottom: 2mm; }
.row { display: flex; gap: 2mm; align-items: flex-start; margin-bottom: 1.6mm; }
.row:last-child { margin-bottom: 0; }
.dot { width: 3.4mm; height: 3.4mm; border-radius: 1mm; flex: 0 0 auto; margin-top: .4mm; }
.dot.sky { background: #3ABEE8; } .dot.grn { background: #2FBF87; } .dot.amb { background: #E2A33C; }
.t { color: #E6EDF3; font-size: 6.6pt; font-weight: bold; }
.d { color: #9FB2BF; font-size: 5.6pt; line-height: 1.35; }
.kv { display: flex; justify-content: space-between; margin-top: 1.4mm;
      border-top: .2mm solid #22303B; padding-top: 1.4mm; }
.kv .t { font-weight: normal; }
.kv .v { color: #3ABEE8; font-size: 6.4pt; font-weight: bold; }
.sw { width: 8.5mm; height: 4.8mm; border-radius: 2.4mm; background: #0E7FA8; position: relative; flex: 0 0 auto; }
.sw::after { content: ""; position: absolute; right: .7mm; top: .7mm; width: 3.4mm; height: 3.4mm;
             border-radius: 50%; background: #fff; }
.sw.off { background: #32424E; }
.sw.off::after { left: .7mm; right: auto; background: #9FB2BF; }
.btn { background: #0E7FA8; color: #fff; font-size: 6.2pt; text-align: center;
       padding: 1.8mm; border-radius: 2mm; margin-bottom: 1.4mm; }
.btn.ghost { background: transparent; border: .3mm solid #32424E; color: #CFE0EA; }
.nav { display: flex; background: #141C24; border-top: .2mm solid #22303B; }
.nav div { flex: 1; text-align: center; padding: 2mm 0 2.4mm; font-size: 5.4pt; color: #7D93A2; }
.nav div.act { color: #3ABEE8; }
.nav .ic { font-size: 7pt; display: block; margin-bottom: .4mm; }

/* Окно компьютера */
.win { width: 100%; background: #0A1015; border-radius: 2.4mm; overflow: hidden;
       border: .4mm solid #263543; box-shadow: 0 1mm 3mm rgba(10,25,35,.16); }
.titlebar { display: flex; align-items: center; gap: 1.6mm; padding: 2mm 3mm;
            background: #141C24; border-bottom: .2mm solid #22303B; }
.tl { width: 2.4mm; height: 2.4mm; border-radius: 50%; }
.titlebar .name { color: #9FB2BF; font-size: 6pt; margin-left: 2mm; }
.tabs { display: flex; gap: 1mm; padding: 2mm 3mm 0; background: #0A1015; }
.tabs div { font-size: 6pt; color: #7D93A2; padding: 1.4mm 3mm; border-radius: 2mm 2mm 0 0; }
.tabs div.act { color: #3ABEE8; background: #141C24; }
.wbody { padding: 3mm; }
.mtu { display: flex; gap: 2.4mm; margin-top: 1.4mm; }
.mtu span { font-size: 5.8pt; color: #9FB2BF; }
.mtu span.on { color: #3ABEE8; font-weight: bold; }
.mtu span::before { content: "\25CB  "; }
.mtu span.on::before { content: "\25C9  "; }

/* Обложка */
.cover { background: linear-gradient(160deg, #10506E, #071C28); color: #fff;
         padding: 22mm 18mm; height: 297mm; }
.cover h1 { font-size: 30pt; margin: 0 0 3mm; }
.cover .lead { font-size: 12pt; color: #B8D6E6; max-width: 130mm; line-height: 1.5; }
.cover .logo { width: 70mm; margin-bottom: 10mm; }
.dl { display: flex; gap: 4mm; margin-top: 9mm; }
.dl .item { flex: 1; background: rgba(255,255,255,.07); border: .3mm solid rgba(255,255,255,.16);
            border-radius: 3mm; padding: 4mm; text-align: center; }
.dl .os { font-size: 10.5pt; font-weight: bold; }
.dl .ver { font-size: 7.6pt; color: #8FB6CB; margin-bottom: 2.5mm; }
.dl .qr { background: #fff; padding: 1.6mm; border-radius: 1.6mm; display: inline-block; }
.dl .qr svg { width: 30mm; height: 30mm; display: block; }
.dl .url { font-family: "Liberation Mono", monospace; font-size: 5.4pt; color: #9FC4D6;
           margin-top: 2.5mm; word-break: break-all; line-height: 1.3; }
.cover .perm { margin-top: 9mm; background: rgba(58,190,232,.12);
               border-left: 1mm solid #3ABEE8; padding: 4mm 5mm; font-size: 9.6pt; color: #DCEEF7; }
.toc { margin-top: 9mm; }
.toc-h { font-size: 9.4pt; color: #8FB6CB; margin-bottom: 3mm; letter-spacing: .3px; }
.toc-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 2.2mm 8mm; }
.toc-grid div { font-size: 9.6pt; color: #DCEEF7;
                border-bottom: .2mm solid rgba(255,255,255,.1); padding-bottom: 1.4mm; }
.toc-grid b { color: #3ABEE8; display: inline-block; width: 6mm; }
.cover .foots { position: absolute; bottom: 14mm; left: 18mm; right: 18mm;
                font-size: 8pt; color: #6F93A8; border-top: .2mm solid rgba(255,255,255,.14); padding-top: 3mm; }
"""
