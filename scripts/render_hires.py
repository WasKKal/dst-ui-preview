#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
render_hires.py — 把 DST widget 树的绘制列表渲染成【清晰】的 PNG

消费 vision_dst.lua 输出的「每个 widget 的屏幕矩形 + 样式」，用 PIL 以
【超采样 + 真实字体】矢量绘制：

  · 纹理：--textures 提供图集 XML+PNG 时按真实像素裁剪贴图并按 SetTint 着色；
          没有纹理时画「占位块 + 纹理名标注」，便于定位是哪个 .tex 没拿到
  · 文本：DST 字体别名 → 本机字体族；textAutoBox 时用真实字体测量后按
          内容锚点（xa/ya）摆盒；outline 字体自动描边
  · 旋转：DST 为 y 向上、逆时针为正 → PIL 用 +rotation（与 Roblox 版相反）
  · 层级：按绘制序（先序）叠加、alpha 合成

用法（一般由 run_dst_ui.py 调用）：
    from render_hires import render_hires
    render_hires(report, "out.png", scale=2)
    render_apng(report, "anim.png", scale=2)      # 多帧 → 动画 PNG
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
_ASSETS = os.path.join(os.path.dirname(HERE), "assets", "fonts")

# ------------------------------------------------------------
# 字体：DST 字体别名 → 本机字体族
#   DEFAULTFONT=opensans  UIFONT=bp50   TITLEFONT=bp100  BUTTONFONT=buttonfont
#   NEWFONT=spirequal     NUMBERFONT/BODYTEXTFONT=stint-ucr  TALKINGFONT=talkingfont
#   CHATFONT=bellefair    HEADERFONT=hammerhead   CODEFONT=ptmono
# 拉丁用 Source Sans 3 / Inter（与 DST 通用无衬线观感接近），CJK 回退 Noto Sans CJK
# ------------------------------------------------------------
_FAMILY_FILES = {
    "sans": os.path.join(_ASSETS, "SourceSans3-400.ttf"),
    "inter": os.path.join(_ASSETS, "Inter-400.ttf"),
}
_SYS_FAMILY_FILES = {
    "mono": ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"],
    "serif": ["/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"],
    "sans": ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
}
_CJK_REGULAR = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]
_CJK_BOLD = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

# DST 字体别名 → (族, 是否粗体)
_DST_FONTS = {
    "ptmono": ("mono", False),
    "bellefair": ("serif", False),
    "hammerhead": ("sans", True),
    "bp100": ("inter", True),      # TITLEFONT：大标题，笔画粗
    "bp50": ("inter", False),      # UIFONT
    "buttonfont": ("sans", True),  # BUTTONFONT
    "spirequal": ("sans", False),  # NEWFONT
    "stint-ucr": ("sans", False),  # NUMBERFONT / BODYTEXTFONT（窄体，用普通体近似）
    "talkingfont": ("sans", False),
    "opensans": ("sans", False),   # DEFAULTFONT
}

_font_cache = {}


def font_of(fontname):
    """DST 字体别名 → (family, bold)"""
    n = (fontname or "").lower()
    if n in _DST_FONTS:
        return _DST_FONTS[n]
    for key, val in _DST_FONTS.items():
        if key in n:
            return val
    bold = ("bold" in n) or ("outline" in n)
    return ("sans", bold)


def load_font(size, bold=False, family="sans"):
    size = max(4, int(round(size)))
    key = (size, bool(bold), family)
    if key in _font_cache:
        return _font_cache[key]
    font = None
    if family == "cjk":
        for p in (_CJK_BOLD if bold else _CJK_REGULAR):
            if os.path.exists(p):
                try:
                    font = ImageFont.truetype(p, size)
                    break
                except Exception:
                    font = None
    if font is None and family == "symbol":
        # 符号：优先 DejaVu（✓ ★ → 等覆盖广），失败再回 CJK
        for p in (_SYS_FAMILY_FILES["sans"][1 if bold else 0],) + tuple(_CJK_REGULAR):
            if os.path.exists(p):
                try:
                    font = ImageFont.truetype(p, size)
                    break
                except Exception:
                    font = None
    if font is None and family not in ("cjk", "symbol"):
        path = _FAMILY_FILES.get(family)
        if path and os.path.exists(path):
            try:
                font = ImageFont.truetype(path, size)  # 可变字体：一份覆盖全字重
                if bold:
                    try:
                        font.set_variation_by_axes([700])
                    except Exception:
                        pass
            except Exception:
                font = None
        if font is None:
            for p in _SYS_FAMILY_FILES.get(family, _SYS_FAMILY_FILES["sans"])[1 if bold else 0:]:
                if os.path.exists(p):
                    try:
                        font = ImageFont.truetype(p, size)
                        break
                    except Exception:
                        font = None
    if font is None:                                    # 兜底（含 CJK 字体缺失时）
        for p in (_CJK_BOLD if bold else _CJK_REGULAR):
            if os.path.exists(p):
                try:
                    font = ImageFont.truetype(p, size)
                    break
                except Exception:
                    font = None
    if font is None:
        try:
            font = ImageFont.load_default(size=size)
        except TypeError:
            font = ImageFont.load_default()
    _font_cache[key] = font
    return font


def _is_cjk(ch):
    o = ord(ch)
    return (0x2E80 <= o <= 0x9FFF) or (0xF900 <= o <= 0xFAFF) or (0xFF00 <= o <= 0xFFEF) \
        or (0x3000 <= o <= 0x303F) or (0x20000 <= o <= 0x3FFFF)


def _is_symbol(ch):
    """非拉丁、非 CJK 的符号区（✓ ★ ● → 箭头/装饰符/制表符…）
    DST 界面里这些字符来自游戏自带字体；本地用 DejaVu Sans 兜底覆盖。"""
    o = ord(ch)
    return (0x2000 <= o <= 0x2BFF) or (0x0250 <= o <= 0x02FF) or (0x2190 <= o <= 0x21FF) \
        or (0x2500 <= o <= 0x257F) or (0x25A0 <= o <= 0x25FF) or (0x2600 <= o <= 0x27BF) \
        or (0xFE00 <= o <= 0xFE0F)


def runs_of(text, size, bold, family):
    """按字符切段：拉丁→DST 同源字体，CJK→Noto CJK，符号→DejaVu（覆盖更广）"""
    out = []
    for ch in text:
        if _is_cjk(ch):
            fam = "cjk"
        elif _is_symbol(ch):
            fam = "symbol"
        else:
            fam = family
        if out and out[-1][1] == fam:
            out[-1][0] += ch
        else:
            out.append([ch, fam])
    return [(s, load_font(size, bold, fam)) for s, fam in out]


def measure(text, size, bold, family, draw):
    return sum(draw.textlength(s, font=f) for s, f in runs_of(text, size, bold, family))


def _clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def _rgb(c):
    if not c:
        return (0, 0, 0)
    return (int(round(_clamp(c.get("r", 0), 0, 1) * 255)),
            int(round(_clamp(c.get("g", 0), 0, 1) * 255)),
            int(round(_clamp(c.get("b", 0), 0, 1) * 255)))


def _a255(x):
    return int(round(_clamp(x, 0, 1) * 255))


def _wrap(lines, size, bold, family, max_w):
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    out = []
    for line in lines:
        if line == "":
            out.append("")
            continue
        cur = ""
        for ch in line:
            if cur == "" or measure(cur + ch, size, bold, family, d) <= max_w:
                cur += ch
            else:
                out.append(cur)
                cur = ch
        out.append(cur)
    return out


# ------------------------------------------------------------
# 纹理：DST 图集（由 report["texmap"] 注入）→ 真实裁剪 / 占位块
# ------------------------------------------------------------
_TEXMAP = {}
_crop_cache = {}


def _texmap_get(ref):
    return _TEXMAP.get(ref) if ref else None


def _crop_image(entry):
    png = entry.get("png")
    crop = entry.get("crop")
    if not png or not crop:
        return None
    key = (png, tuple(crop))
    if key in _crop_cache:
        return _crop_cache[key]
    im = None
    try:
        with Image.open(png) as src:
            src = src.convert("RGBA")
            x0, y0, x1, y1 = [int(v) for v in crop]
            x0 = max(0, min(x0, src.width - 1))
            y0 = max(0, min(y0, src.height - 1))
            x1 = max(x0 + 1, min(x1, src.width))
            y1 = max(y0 + 1, min(y1, src.height))
            im = src.crop((x0, y0, x1, y1))
    except Exception:
        im = None
    _crop_cache[key] = im
    return im


def _short_label(ref, max_px, size, bold, family, draw):
    """把 atlas:tex 缩成适合放进占位块的短标签（优先 tex 名）"""
    label = ref or "?"
    if ":" in label:
        label = label.split(":", 1)[1]
    if measure(label, size, bold, family, draw) <= max_px:
        return label
    ell = "…"
    while label and measure(label + ell, size, bold, family, draw) > max_px:
        label = label[:-1]
    return (label + ell) if label else ""


def _draw_placeholder(L, S, x, y, w, h, ref, kind, tint=(255, 255, 255), alpha=1.0):
    """无真实纹理时的占位：斜纹底 + 左上角纹理名标注（按 SetTint 着色，肉眼可辨）"""
    d = ImageDraw.Draw(L)
    box = [x, y, x + w - 1, y + h - 1]
    base = (74, 86, 104) if kind == "image" else (96, 88, 64)
    # 与 SetTint 相乘后再抬底，保证暗色 tint 也能看见块
    tr, tg, tb = [c / 255.0 for c in tint]
    fill = (int(40 + base[0] * tr * 0.85), int(40 + base[1] * tg * 0.85), int(40 + base[2] * tb * 0.85))
    a = int(round(_clamp(alpha, 0, 1) * 150))
    d.rectangle(box, fill=(fill[0], fill[1], fill[2], a))
    lw = max(1, int(round(1 * S)))
    edge = (min(255, fill[0] + 80), min(255, fill[1] + 80), min(255, fill[2] + 90), 190)
    d.rectangle(box, outline=edge, width=lw)

    step = max(6, int(round(9 * S)))                     # 45° 斜纹
    x0, y0, x1, y1 = x, y, x + w - 1, y + h - 1
    xx = x0 - (y1 - y0)
    while xx < x1:
        d.line([(xx, y1), (xx + (y1 - y0), y0)], fill=(160, 172, 192, 42), width=lw)
        xx += step

    # 纹理名：放左上角，避免压住真实内容；块够大才写
    if w >= 44 * S and h >= 16 * S:
        fs = max(7, min(int(round(h * 0.20 / max(S, 1))), 13)) * S
        label = _short_label(ref, w - 8 * S, fs, False, "mono", d)
        if label:
            f = load_font(fs, False, "mono")
            try:
                asc, desc = f.getmetrics()
                lh = asc + desc
            except Exception:
                lh = fs * 1.25
            ty = y + 3 * S
            if h - lh - 3 * S < ty:                       # 太扁就居中
                ty = y + (h - lh) / 2
            d.text((x + 4 * S, ty), label, font=f, fill=(240, 244, 250, 240))


def _draw_image(L, S, op, ox, oy, w, h):
    """DST Image / ThreeSlice / UIAnim：真实裁剪优先，其次占位块"""
    ref = op.get("imageRef") or ""
    ic = _rgb(op.get("imageColor") or {"r": 1, "g": 1, "b": 1})
    ia = _clamp(float(op.get("imageAlpha", 1)), 0.0, 1.0)
    tw = max(1, int(round(w)))
    th = max(1, int(round(h)))
    if ia <= 0.004 or tw <= 0 or th <= 0:
        return

    entry = None if op.get("placeholder") else _texmap_get(ref)
    im = _crop_image(entry) if entry else None
    if im is not None:
        if im.size != (tw, th):
            im = im.resize((tw, th), Image.LANCZOS)
        if ic != (255, 255, 255):                        # SetTint：乘算着色
            im = ImageChops.multiply(im, Image.new("RGBA", im.size, (ic[0], ic[1], ic[2], 255)))
        if ia < 0.999:
            im.putalpha(im.split()[3].point(lambda v: int(v * ia)))
        L.alpha_composite(im, (int(round(ox)), int(round(oy))))
        return

    _draw_placeholder(L, S, ox, oy, w, h, ref, "image", tint=ic, alpha=ia)


# ------------------------------------------------------------
# 文本
# ------------------------------------------------------------
def _measure_lines(op, S):
    """按字体真实度量算出行、行高、文本块尺寸（scaled 坐标）"""
    family, bold = font_of(op.get("font"))
    size = float(op.get("textSize", 30)) * S
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    lines = (op.get("text") or "").split("\n")
    max_w = float(op.get("w", 0)) * S
    if op.get("wrapped") and max_w > 1:
        lines = _wrap(lines, size, bold, family, max_w)
    f0 = load_font(size, bold, family)
    try:
        asc, desc = f0.getmetrics()
    except Exception:
        asc, desc = size, size * 0.25
    lh = asc + desc
    tw = max((measure(s, size, bold, family, d) for s in lines), default=0)
    return family, bold, size, lines, lh, tw, lh * len(lines)


def _text_box(op, S):
    """文本盒（屏幕 scaled 坐标）：有区域用区域；无区域用真实测量结果按 xa/ya 摆盒"""
    family, bold, size, lines, lh, tw, th = _measure_lines(op, S)
    if op.get("textAutoBox"):
        xa = op.get("xa", "Center")
        ya = op.get("ya", "Center")
        ax = float(op.get("x", 0)) * S - (tw / 2 if xa == "Center" else (tw if xa == "Right" else 0))
        ay = float(op.get("y", 0)) * S - (th / 2 if ya == "Center" else (th if ya == "Bottom" else 0))
        return ax, ay, tw, th, lines, lh, family, bold, size
    return (float(op.get("x", 0)) * S, float(op.get("y", 0)) * S,
            float(op.get("w", 0)) * S, float(op.get("h", 0)) * S,
            lines, lh, family, bold, size)


def _draw_text(layer, op, lx, ly, S, box):
    """把文本画进 layer（layer 原点在 scaled 坐标 (lx, ly)）"""
    bx, by, bw, bh, ls, lh, family, bold, size = box
    text = op.get("text") or ""
    if text == "" or bw <= 0 or bh <= 0:
        return
    tc = _rgb(op.get("textColor") or {"r": 1, "g": 1, "b": 1})
    ta = _a255(op.get("textAlpha", 1))
    if ta <= 6:
        return
    auto = bool(op.get("textAutoBox"))
    xa = op.get("xa", "Center" if auto else "Left")
    ya = op.get("ya", "Center" if auto else "Top")

    kw = {}
    if op.get("textStroke"):
        sc = op["textStroke"]
        kw = {"stroke_width": max(1, int(round(size * 0.06))),
              "stroke_fill": (_rgb(sc)[0], _rgb(sc)[1], _rgb(sc)[2], _a255(sc.get("a", 1)))}

    total_h = lh * len(ls)
    if ya == "Center":
        ty0 = by + (bh - total_h) / 2
    elif ya == "Bottom":
        ty0 = by + bh - total_h
    else:
        ty0 = by

    d = ImageDraw.Draw(layer)
    fill = (tc[0], tc[1], tc[2], ta)
    for i, ln in enumerate(ls):
        if ln == "":
            continue
        lw = measure(ln, size, bold, family, d)
        if xa == "Center":
            tx = bx + (bw - lw) / 2
        elif xa == "Right":
            tx = bx + bw - lw
        else:
            tx = bx
        ty = ty0 + i * lh
        for seg, f in runs_of(ln, size, bold, family):
            d.text((tx - lx, ty - ly), seg, font=f, fill=fill, **kw)
            tx += d.textlength(seg, font=f)


# ------------------------------------------------------------
# 单帧渲染
# ------------------------------------------------------------
def render_image(report, bg=(23, 21, 18), scale=2, ss=3, show_text=True):
    """render report['draws'] → PIL RGB（不落盘）。"""
    global _TEXMAP
    _TEXMAP = report.get("texmap") or {}
    ops = report.get("draws") or []
    vp = report.get("viewport") or {}
    W = int(vp.get("w", 1280))
    H = int(vp.get("h", 720))
    zoom = max(1, int(scale))
    SS = max(1, int(ss))
    MAX_CANVAS_PIXELS = 24000000
    while SS > 1 and (W * zoom * SS) * (H * zoom * SS) > MAX_CANVAS_PIXELS:
        SS -= 1
    if SS != max(1, int(ss)):
        import sys as _sys
        print("[render_hires] 画布 %dx%d 超采样超预算，ss 由 x%d 降为 x%d（输出尺寸不变）"
              % (W * zoom, H * zoom, max(1, int(ss)), SS), file=_sys.stderr)
    S = zoom * SS
    cw, ch = W * S, H * S
    canvas = Image.new("RGBA", (cw, ch), (bg[0], bg[1], bg[2], 255))

    for op in ops:
        cls = op.get("class") or "Widget"
        x = float(op.get("x", 0)) * S
        y = float(op.get("y", 0)) * S
        w = float(op.get("w", 0)) * S
        h = float(op.get("h", 0)) * S
        is_text = cls in ("Text", "TextEdit")

        # 文本：先按真实字体测量出盒子（自动盒由测量结果决定）
        text_box = None
        if is_text and (op.get("text") or "") != "":
            text_box = _text_box(op, S)
            if text_box[2] <= 0.5 or text_box[3] <= 0.5:
                continue
            x, y, w, h = text_box[0], text_box[1], text_box[2], text_box[3]
        if w < 0.5 or h < 0.5:
            continue

        # 描边/边框需要外扩，否则会被裁掉
        pad = 0.0
        if text_box and op.get("textStroke"):
            pad = max(1.0, text_box[8] * 0.06) + 1.0
        rx0, ry0, rx1, ry1 = x - pad, y - pad, x + w + pad, y + h + pad
        clip = op.get("clip")
        if clip:
            rx0 = max(rx0, clip["x"] * S)
            ry0 = max(ry0, clip["y"] * S)
            rx1 = min(rx1, (clip["x"] + clip["w"]) * S)
            ry1 = min(ry1, (clip["y"] + clip["h"]) * S)
        rx0 = max(0.0, rx0)
        ry0 = max(0.0, ry0)
        rx1 = min(float(cw), rx1)
        ry1 = min(float(ch), ry1)
        RW = int(round(rx1 - rx0))
        RH = int(round(ry1 - ry0))
        if RW <= 0 or RH <= 0:
            continue

        ox = rx0 - x
        oy = ry0 - y
        L = Image.new("RGBA", (RW, RH), (0, 0, 0, 0))

        # 1) 纹理 / 占位块
        if op.get("image"):
            _draw_image(L, S, op, ox, oy, w, h)

        # 2) 文本
        if show_text and text_box:
            _draw_text(L, op, rx0, ry0, S, text_box)

        # 3) 旋转（DST：绕元素中心、逆时针为正 → PIL rotate 正值即逆时针）
        rot = float(op.get("rotation", 0) or 0)
        if abs(rot) > 0.01:
            tmp = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            tmp.alpha_composite(L, (int(round(rx0)), int(round(ry0))))
            cx = x + w / 2.0
            cy = y + h / 2.0
            tmp = tmp.rotate(rot, center=(cx, cy), resample=Image.BICUBIC)
            canvas.alpha_composite(tmp)
        else:
            canvas.alpha_composite(L, (int(round(rx0)), int(round(ry0))))

    target = (W * zoom, H * zoom)
    if canvas.size != target:
        canvas = canvas.resize(target, Image.LANCZOS)
    out = Image.new("RGB", canvas.size, bg)
    out.paste(canvas, (0, 0), canvas)
    return out


def _ensure_dir(path):
    d = os.path.dirname(os.path.abspath(path))
    if d:
        os.makedirs(d, exist_ok=True)


def render_hires(report, out_path, bg=(23, 21, 18), scale=2, ss=3, show_text=True):
    """渲染单帧清晰 PNG（= render_image + 落盘）。"""
    out = render_image(report, bg=bg, scale=scale, ss=ss, show_text=show_text)
    _ensure_dir(out_path)
    out.save(out_path, "PNG")
    return out


def render_apng(report, out_path, bg=(23, 21, 18), scale=2, ss=3, show_text=True, fps=0.0):
    """把 report['frames'] 逐帧渲染并合成 APNG（浏览器可直接播放）。"""
    frames = report.get("frames") or []
    if len(frames) < 2:
        return None
    interval = float(report.get("frameInterval") or 0.1)
    duration = (1000.0 / float(fps)) if (fps and float(fps) > 0) else max(20.0, interval * 1000.0)
    vp = report.get("viewport") or {}
    texmap = report.get("texmap") or {}
    imgs = []
    for f in frames:
        sub = {"viewport": vp, "draws": f.get("draws") or [], "texmap": texmap}
        imgs.append(render_image(sub, bg=bg, scale=scale, ss=ss, show_text=show_text))
    _ensure_dir(out_path)
    imgs[0].save(out_path, "PNG", save_all=True, append_images=imgs[1:],
                 duration=int(round(duration)), loop=0)
    return imgs[0]


if __name__ == "__main__":
    import json
    import sys
    if len(sys.argv) < 3:
        print("用法: render_hires.py <report.json> <out.png> [scale] [ss]", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        rep = json.load(f)
    sc = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    ssp = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    img = render_hires(rep, sys.argv[2], scale=sc, ss=ssp)
    print("已导出 %s  (%dx%d)" % (sys.argv[2], img.width, img.height))
