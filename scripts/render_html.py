#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
render_html.py — 把 DST widget 树的绘制列表渲染成【自包含、可交互的 HTML】

思路：DST 的 widget 模型（Position/Scale/Anchor + 内容锚点）与浏览器盒模型同构，
把每个 widget 映射成一个绝对定位 <div>：
  · 纹理：从图集 PNG 裁出用到的纹理，内嵌为 data URI，用 background-position/size
          还原裁剪；SetTint 用 mix-blend-mode: multiply 叠加
  · 占位块：斜纹底 + 纹理名（该 .tex 没有图集数据时）
  · 文本：textAutoBox 时用 transform: translate(-50%,-50%) 按内容锚点摆位（矢量、无限清晰）
  · 旋转：DST 为 y 向上、逆时针为正 → CSS rotate(-deg)（CSS 正角度是顺时针）
  · 交互：悬停探针（查看控件信息）、缩放、边界框、绘制序、浅色底、动画时间轴

用法：
    from render_html import render_html
    render_html(report, "preview.html", title="ModConfigPanel")
"""

import base64
import html
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_FONT_DIR = os.path.join(os.path.dirname(HERE), "assets", "fonts")
_FONT_FILES = [
    ("DST Sans", "SourceSans3-400.woff2"),     # ≈ DEFAULTFONT(opensans)/NEWFONT
    ("DST Display", "Inter-400.woff2"),        # ≈ UIFONT(bp50)/TITLEFONT(bp100)
]


def _build_font_face_css():
    out = []
    for family, fn in _FONT_FILES:
        p = os.path.join(_FONT_DIR, fn)
        if not os.path.exists(p):
            continue
        with open(p, "rb") as f:
            b64 = base64.b64encode(f.read()).decode("ascii")
        out.append(
            "@font-face{font-family:'%s';font-style:normal;font-weight:100 900;"
            "font-display:swap;src:url(data:font/woff2;base64,%s) format('woff2');}"
            % (family, b64))
    return "\n".join(out)


FONT_FACE_CSS = _build_font_face_css()


# DST 字体别名 → CSS 字体栈
_FONT_STACKS = {
    "ptmono": "ui-monospace,'DejaVu Sans Mono',monospace",
    "bellefair": "'DejaVu Serif',Georgia,serif",
    "hammerhead": "'DST Display','Noto Sans SC',sans-serif",
    "bp100": "'DST Display','Noto Sans SC',sans-serif",
    "bp50": "'DST Display','Noto Sans SC',sans-serif",
    "buttonfont": "'DST Display','Noto Sans SC',sans-serif",
    "spirequal": "'DST Sans','Noto Sans SC',sans-serif",
    "stint-ucr": "'DST Sans','Noto Sans SC',sans-serif",
    "talkingfont": "'DST Sans','Noto Sans SC',sans-serif",
    "opensans": "'DST Sans','Noto Sans SC',sans-serif",
}


def _esc_json(obj):
    s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    return s.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


# ------------------------------------------------------------
# 纹理：把用到的图集裁剪片内嵌成 data URI（避免整张图集进 HTML）
# ------------------------------------------------------------
def collect_textures(report):
    """{ref: {"url": dataURI, "crop":[x0,y0,x1,y1], "aw":atlas_w, "ah":atlas_h}}"""
    texmap = report.get("texmap") or {}
    out = {}
    seen = set()
    for op in (report.get("draws") or []):
        ref = op.get("imageRef")
        if not ref or ref in seen:
            continue
        e = texmap.get(ref)
        if not e or not e.get("png") or not e.get("crop"):
            continue
        seen.add(ref)
        try:
            from PIL import Image
            with Image.open(e["png"]) as src:
                src = src.convert("RGBA")
                x0, y0, x1, y1 = [int(v) for v in e["crop"]]
                x0 = max(0, min(x0, src.width - 1))
                y0 = max(0, min(y0, src.height - 1))
                x1 = max(x0 + 1, min(x1, src.width))
                y1 = max(y0 + 1, min(y1, src.height))
                buf = io.BytesIO()
                src.crop((x0, y0, x1, y1)).save(buf, "PNG")
                out[ref] = {
                    "url": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii"),
                    "crop": [x0, y0, x1, y1],
                    "aw": src.width, "ah": src.height,
                }
        except Exception:
            continue
    return out


_CSS = r"""
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: #14131a; color: #d8d2c4;
  font-family: "DST Sans", "Noto Sans SC", system-ui, sans-serif;
  min-height: 100vh; display: flex; flex-direction: column;
}
header {
  display: flex; align-items: center; gap: 14px; flex-wrap: wrap;
  padding: 10px 16px; background: #1d1b17; border-bottom: 1px solid #322d24;
  position: sticky; top: 0; z-index: 9999;
}
header .title { font-weight: 700; font-size: 14px; color: #f0e6d2; }
header .meta { font-size: 12px; color: #a2988a; }
header .ok { color: #6fbf5a; } header .bad { color: #d4574e; }
header .spacer { flex: 1; }
header input[type=range] { width: 130px; accent-color: #c8a24a; }
header .frame { font-size: 12px; color: #a2988a; min-width: 56px; text-align: center; }
button {
  background: #262119; color: #d8d2c4; border: 1px solid #3d3527; border-radius: 6px;
  padding: 5px 10px; font-size: 12px; cursor: pointer; font-family: inherit;
}
button:hover { background: #322b20; }
button.on { background: #c8a24a33; border-color: #c8a24a; color: #e8cf8a; }
.stage { flex: 1; padding: 20px; overflow: auto; }
.wrap { margin: 0 auto; position: relative; }
.viewport {
  position: relative; overflow: hidden;
  background: #171512;
  box-shadow: 0 24px 64px rgba(0,0,0,.6);
  outline: 1px solid #322d24;
}
.gui { position: absolute; }
.gui .tint { position: absolute; inset: 0; mix-blend-mode: multiply; pointer-events: none; }
.gui .ph {                     /* 占位块：斜纹 + 纹理名 */
  position: absolute; inset: 0; pointer-events: none;
  background-image: repeating-linear-gradient(45deg, rgba(170,182,200,.20) 0 6px, rgba(170,182,200,0) 6px 12px);
  border: 1px solid rgba(170,182,200,.45);
}
.gui .ph span {
  position: absolute; left: 3px; top: 2px; font: 10px/1.3 ui-monospace, monospace;
  color: #e6ebf4; opacity: .9; white-space: nowrap; overflow: hidden; max-width: calc(100% - 6px);
}
.gui.hl { outline: 2px solid #e8cf8a !important; outline-offset: 0; }
.badges .gui[data-name]::after {
  content: attr(data-badge); position: absolute; left: 0; top: 0;
  transform: translateY(-100%); background: #c8a24a; color: #1b1712;
  font: 10px/1.4 ui-monospace, monospace; padding: 0 4px; border-radius: 3px 3px 0 0;
  pointer-events: none; white-space: nowrap;
}
.boxes .gui { outline: 1px dashed rgba(232,207,138,.4); }
.txt { position: absolute; white-space: pre; }
#tip {
  position: fixed; pointer-events: none; z-index: 100000; display: none;
  background: #0f0e0bf2; border: 1px solid #3d3527; border-radius: 6px;
  padding: 6px 9px; font: 11px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace;
  color: #d8d2c4; white-space: pre; box-shadow: 0 8px 24px rgba(0,0,0,.55);
}
"""

_JS = r"""
let REPORT = (typeof REPORT_DATA !== 'undefined' && REPORT_DATA) ? REPORT_DATA : { viewport:{w:1280,h:720}, draws: [] };
let V = REPORT.viewport || {w:1280,h:720};
let OPS = REPORT.draws || [];
let TEX = (typeof TEXMAP_DATA !== 'undefined' && TEXMAP_DATA) ? TEXMAP_DATA : {};
const vp = document.getElementById('vp');

function c255(x){ return Math.max(0, Math.min(255, Math.round((x||0)*255))); }
function rgba(c,a){ return `rgba(${c255(c&&c.r)},${c255(c&&c.g)},${c255(c&&c.b)},${a})`; }

const FONT_STACKS = {
  ptmono: "ui-monospace,'DejaVu Sans Mono',monospace",
  bellefair: "'DejaVu Serif',Georgia,serif",
  hammerhead: "'DST Display','Noto Sans SC',sans-serif",
  bp100: "'DST Display','Noto Sans SC',sans-serif",
  bp50: "'DST Display','Noto Sans SC',sans-serif",
  buttonfont: "'DST Display','Noto Sans SC',sans-serif",
  spirequal: "'DST Sans','Noto Sans SC',sans-serif",
  'stint-ucr': "'DST Sans','Noto Sans SC',sans-serif",
  talkingfont: "'DST Sans','Noto Sans SC',sans-serif",
  opensans: "'DST Sans','Noto Sans SC',sans-serif",
};
function fontStack(name){
  const n = (name||'').toLowerCase();
  for (const k in FONT_STACKS) if (n === k || n.indexOf(k) >= 0) return FONT_STACKS[k];
  return "'DST Sans','Noto Sans SC',sans-serif";
}
function isBold(name){ const n=(name||'').toLowerCase();
  return n.indexOf('bp100')>=0 || n.indexOf('hammerhead')>=0 || n.indexOf('buttonfont')>=0 || n.indexOf('bold')>=0; }

function mkText(op){
  const sp = document.createElement('span');
  sp.className = 'txt';
  sp.textContent = op.text;
  const size = op.textSize || 30;
  sp.style.fontFamily = fontStack(op.font);
  sp.style.fontSize = size + 'px';
  sp.style.fontWeight = isBold(op.font) ? '700' : '400';
  sp.style.lineHeight = '1.15';
  sp.style.color = rgba(op.textColor, op.textAlpha==null?1:op.textAlpha);
  sp.style.whiteSpace = op.wrapped ? 'pre-wrap' : 'pre';
  sp.style.wordBreak = op.wrapped ? 'break-word' : 'normal';
  if (op.textStroke){
    const w = Math.max(1, Math.round(size*0.06));
    sp.style.webkitTextStroke = `${w}px ${rgba(op.textStroke, op.textStroke.a==null?1:op.textStroke.a)}`;
  }
  return sp;
}

function placeText(el, op){
  const xa = op.xa||'Center', ya = op.ya||'Center';
  el.style.left = op.x + 'px';
  el.style.top  = op.y + 'px';
  if (op.textAutoBox){
    // 内容锚点：把盒子按 xa/ya 对齐到位置上（与 DST 的 hreg/vreg 语义一致）
    const tx = xa==='Center' ? '-50%' : (xa==='Right' ? '-100%' : '0');
    const ty = ya==='Center' ? '-50%' : (ya==='Bottom' ? '-100%' : '0');
    el.style.transform = (tx==='0' && ty==='0') ? '' : `translate(${tx},${ty})`;
    el.style.width = 'auto'; el.style.height = 'auto';
  } else {
    el.style.width = op.w + 'px'; el.style.height = op.h + 'px';
    el.style.display = 'flex';
    el.style.justifyContent = xa==='Center'?'center':(xa==='Right'?'flex-end':'flex-start');
    el.style.alignItems = ya==='Center'?'center':(ya==='Bottom'?'flex-end':'flex-start');
    el.style.overflow = 'hidden';
  }
}

function texBackground(el, op){
  const ref = op.imageRef;
  const e = ref ? TEX[ref] : null;
  const ic = op.imageColor || {r:1,g:1,b:1};
  const ia = op.imageAlpha==null?1:op.imageAlpha;
  if (e){
    const cw = e.crop[2]-e.crop[0], ch = e.crop[3]-e.crop[1];
    const kx = cw>0 ? (op.w / cw) : 1, ky = ch>0 ? (op.h / ch) : 1;
    el.style.backgroundImage = `url(${e.url})`;
    el.style.backgroundRepeat = 'no-repeat';
    el.style.backgroundSize = `${e.aw*kx}px ${e.ah*ky}px`;
    el.style.backgroundPosition = `${-e.crop[0]*kx}px ${-e.crop[1]*ky}px`;
    if (c255(ic.r)!==255 || c255(ic.g)!==255 || c255(ic.b)!==255){
      const t = document.createElement('i');
      t.className = 'tint';
      t.style.background = rgba(ic, 1);
      t.style.opacity = ia;
      el.appendChild(t);
    } else if (ia < 0.999){
      el.style.opacity = ia;
    }
  } else {
    const ph = document.createElement('i');
    ph.className = 'ph';
    ph.style.background = rgba(ic, 0.12);
    const label = ref ? (ref.indexOf(':')>=0 ? ref.split(':')[1] : ref) : '?';
    const s = document.createElement('span');
    s.textContent = label;
    ph.appendChild(s);
    el.appendChild(ph);
  }
}

function build(){
  vp.style.width = V.w+'px'; vp.style.height = V.h+'px';
  OPS.forEach(op=>{
    const isText = op.class === 'Text' || op.class === 'TextEdit';
    if (!isText && (op.w<0.5 || op.h<0.5)) return;
    if (isText && !(op.text||'').length) return;

    if (isText){
      const sp = mkText(op);
      placeText(sp, op);
      sp.dataset.name = (op.class||'') + ' " ' + (op.name||'') + ' "';
      sp.dataset.badge = '#'+op.seq;
      sp.addEventListener('mouseenter', ()=>showTip(op, sp));
      sp.addEventListener('mouseleave', hideTip);
      vp.appendChild(sp);
      return;
    }

    const el = document.createElement('div');
    el.className='gui';
    el.dataset.name = (op.class||'') + ' " ' + (op.name||'') + ' "';
    el.dataset.badge = '#'+op.seq;
    const st = el.style;
    st.left = op.x+'px'; st.top = op.y+'px';
    st.width = op.w+'px'; st.height = op.h+'px';
    if (op.image) texBackground(el, op);
    if (op.rotation) st.transform = `rotate(${-op.rotation}deg)`;
    // 裁剪：父级 clip 矩形（画布内）
    if (op.clip){
      const c = op.clip;
      const top=Math.max(0,c.y-op.y), left=Math.max(0,c.x-op.x);
      const right=Math.max(0,(op.x+op.w)-(c.x+c.w)), bottom=Math.max(0,(op.y+op.h)-(c.y+c.h));
      st.clipPath = `inset(${top}px ${right}px ${bottom}px ${left}px)`;
    }
    el.addEventListener('mouseenter', ()=>showTip(op, el));
    el.addEventListener('mouseleave', hideTip);
    vp.appendChild(el);
  });
  fitScaled();
}

function fitScaled(){ /* DST Text 无 TextScaled，占位保留 */ }

const tip = document.getElementById('tip');
function showTip(op, el){
  const r = el.getBoundingClientRect();
  el.classList.add('hl');
  const e = op.imageRef ? TEX[op.imageRef] : null;
  tip.textContent =
    `${op.class}  ${op.name||''}\n`+
    `x=${Math.round(op.x)} y=${Math.round(op.y)} w=${Math.round(op.w)} h=${Math.round(op.h)}\n`+
    `z=${op.zindex}  seq=${op.seq}`+
    (op.imageRef ? `\ntex=${op.imageRef}${e?'  (真实纹理)':'  (无图集 → 占位)'}` : '')+
    (op.font ? `\nfont=${op.font} size=${op.textSize}` : '')+
    (op.text ? `\ntext=${JSON.stringify(op.text).slice(0,48)}` : '');
  tip.style.display='block';
  tip.style.left = Math.min(window.innerWidth-280, r.left)+'px';
  tip.style.top  = Math.min(window.innerHeight-80, r.bottom+6)+'px';
}
function hideTip(){ tip.style.display='none';
  vp.querySelectorAll('.gui.hl,.txt.hl').forEach(e=>e.classList.remove('hl')); }

let zoom = 1, userZoomed = false;
function applyZoom(){
  const wrap = document.getElementById('wrap');
  const el = document.getElementById('vp');
  el.style.width = V.w + 'px'; el.style.height = V.h + 'px';
  el.style.transformOrigin = 'top left';
  el.style.transform = `scale(${zoom})`;
  wrap.style.width = (V.w*zoom)+'px'; wrap.style.height = (V.h*zoom)+'px';
}
function autoFitZoom(){
  const st = document.getElementById('stage');
  if (!st) return 1;
  const aw = st.clientWidth - 44, ah = st.clientHeight - 44;
  if (aw <= 60 || ah <= 60) return 1;
  return Math.max(0.2, Math.min(1, aw/V.w, ah/V.h));
}
document.getElementById('zin').onclick  = ()=>{ userZoomed=true; zoom=Math.min(6,zoom+0.25); applyZoom(); };
document.getElementById('zout').onclick = ()=>{ userZoomed=true; zoom=Math.max(0.2,zoom-0.25); applyZoom(); };
document.getElementById('z1').onclick   = ()=>{ userZoomed=true; zoom=1; applyZoom(); };
document.getElementById('tbox').onclick = e=>{ vp.classList.toggle('boxes'); e.target.classList.toggle('on'); };
document.getElementById('tseq').onclick = e=>{ vp.classList.toggle('badges'); e.target.classList.toggle('on'); };
document.getElementById('tx').onclick   = e=>{
  document.querySelectorAll('.txt').forEach(t=>t.style.visibility =
    (t.style.visibility==='hidden'?'visible':'hidden'));
  e.target.classList.toggle('on');
};
document.getElementById('tbg').onclick  = e=>{
  const cur = vp.style.background;
  vp.style.background = cur==='rgb(23, 21, 18)' ? '#f3efe4' : '#171512';
  e.target.classList.toggle('on');
};

const FRAMES = (typeof FRAMES_DATA !== 'undefined' && FRAMES_DATA) ? FRAMES_DATA : [];
const FINTERVAL = (typeof FRAME_INTERVAL !== 'undefined') ? FRAME_INTERVAL : 0.1;
let fIdx = 0, playTimer = null, playing = false;
function frameDuration(){ return Math.max(40, FINTERVAL*1000); }

function showFrame(i){
  if(!FRAMES.length) return;
  i = Math.max(0, Math.min(FRAMES.length-1, i|0));
  fIdx = i; OPS = FRAMES[i].draws || [];
  vp.innerHTML=''; hideTip(); build(); applyZoom();
  const fn=document.getElementById('fnum'); if(fn) fn.textContent=(i+1)+'/'+FRAMES.length;
  const rg=document.getElementById('frange'); if(rg) rg.value=i;
  const hc=document.getElementById('hcount'); if(hc) hc.textContent='元素 '+OPS.length+' · 帧 '+(i+1)+'/'+FRAMES.length;
}
window.showFrame = showFrame;
function tickPlay(){
  if(!playing) return;
  playTimer = setTimeout(()=>{ if(!playing) return; showFrame((fIdx+1)%FRAMES.length); tickPlay(); }, frameDuration());
}
function togglePlay(){
  if(!FRAMES.length) return;
  playing = !playing;
  const b=document.getElementById('play'); if(b) b.textContent = playing?'❚❚':'▶';
  if(playing){ if(fIdx>=FRAMES.length-1) showFrame(0); tickPlay(); }
  else if(playTimer){ clearTimeout(playTimer); playTimer=null; }
}
if(FRAMES.length > 1){
  const pb=document.getElementById('play'); if(pb) pb.onclick=togglePlay;
  const rg=document.getElementById('frange');
  if(rg){ rg.max=FRAMES.length-1; rg.oninput=()=>{ if(playing) togglePlay(); showFrame(parseInt(rg.value,10)||0); }; }
}
if (typeof REPORT_DATA !== 'undefined' && REPORT_DATA) {
  if (FRAMES.length > 1) { showFrame(FRAMES.length-1); }
  else { build(); zoom = autoFitZoom(); applyZoom(); }
}
"""


def _header(meta):
    nerr = meta.get("errors", 0)
    nframes = int(meta.get("frames", 0))
    cls = "ok" if nerr == 0 else "bad"
    anim = ""
    if nframes > 1:
        anim = ('<button id="play" title="播放/暂停动画">▶</button>'
                '<input type="range" id="frange" min="0" max="%d" value="%d" title="动画帧">'
                '<span class="frame" id="fnum"></span>' % (nframes - 1, nframes - 1))
    return ((
        '<header>'
        '<span class="title">DST UI 预览 · %s</span>'
        '<span class="meta">视口 %dx%d</span>'
        '<span class="meta" id="hcount">元素 %d</span>'
        '<span class="meta">纹理 %d / 占位 %d</span>'
        '<span class="meta %s">错误 %d</span>'
        '<span class="spacer"></span>'
    ) + anim + (
        '<button id="zout">−</button><button id="z1">100%%</button><button id="zin">＋</button>'
        '<button id="tbox">边界框</button>'
        '<button id="tseq">绘制序</button>'
        '<button id="tx">隐藏文字</button>'
        '<button id="tbg">浅色底</button>'
        '</header>'
    )) % (
        html.escape(str(meta.get("title", ""))),
        int(meta.get("vw", 1280)), int(meta.get("vh", 720)), int(meta.get("count", 0)),
        int(meta.get("tex", 0)), int(meta.get("ph", 0)),
        cls, nerr,
    )


def render_html(report, out_path, title="DST UI"):
    vp = report.get("viewport") or {}
    draws = report.get("draws") or []
    frames = report.get("frames") or []
    finterval = float(report.get("frameInterval") or 0.1)
    widgets = report.get("widgets") or {}
    textures = collect_textures(report)
    meta = {
        "title": title,
        "vw": vp.get("w", 1280), "vh": vp.get("h", 720),
        "count": len(draws),
        "tex": len(textures),
        "ph": int(widgets.get("placeholders", 0)),
        "errors": len(report.get("errors") or []),
        "frames": len(frames),
    }
    payload = {"viewport": vp, "draws": draws}
    frames_payload = [{"t": f.get("t", 0), "draws": f.get("draws") or []} for f in frames]
    doc = (
        "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n"
        "<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<title>" + html.escape(title) + "</title>\n"
        "<style>" + FONT_FACE_CSS + "\n" + _CSS + "</style>\n</head>\n<body>\n"
        + _header(meta) +
        "\n<div class=\"stage\" id=\"stage\"><div class=\"wrap\" id=\"wrap\">"
        "<div class=\"viewport\" id=\"vp\"></div></div></div>\n"
        "<div id=\"tip\"></div>\n"
        "<script>const REPORT_DATA=" + _esc_json(payload) + ";\n"
        "const TEXMAP_DATA=" + _esc_json(textures) + ";\n"
        "const FRAMES_DATA=" + _esc_json(frames_payload) + ";\n"
        "const FRAME_INTERVAL=" + repr(finterval) + ";</script>\n"
        "<script>" + _JS + "</script>\n"
        "</body>\n</html>\n"
    )
    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(doc)
    return out_path


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 3:
        print("用法: render_html.py <report.json> <out.html>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        rep = json.load(f)
    p = render_html(rep, sys.argv[2])
    print("已导出", p)
