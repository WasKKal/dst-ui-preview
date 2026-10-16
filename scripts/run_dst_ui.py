#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_dst_ui.py — 无头预览 Don't Starve Together mod UI 并渲染出 PNG / HTML

把 DST 的 widget 树（Screen → Widget → Image/Text/Button/...）在【无游戏】环境下
实例化执行，产出与 Roblox 版同构的「绘制列表」JSON，再用矢量渲染器画成真实像素图。

执行链：
  1. Lua 运行时（lupa，真实 Lua VM）加载 bootstrap + widgets mock + harness + vision
     （base64 内联，模块间靠裸全局共享；DST mod 本身是 Lua 5.1 风格代码）
  2. 入口屏幕模块被 require 并实例化（类 / 工厂函数 / 类名字表均可）
  3. 虚拟时钟推进（DoTaskInTime / 补间 / StartUpdating 真实求值）
  4. 可选：在指定坐标命中并派发点击（走 OnControl 完整点击流）
  5. Vision.buildDrawList() 输出绘制列表 → JSON 报告
  6. render_hires.py 画高清 PNG；render_html.py 出自交互网页；--anim 出 APNG

用法：
    # 只跑引擎、出 JSON 报告（调试 Lua 管线用）
    python3 run_dst_ui.py --screen examples/mod_config_panel.lua --style none

    # 高清 PNG + 可交互 HTML
    python3 run_dst_ui.py --screen examples/mod_config_panel.lua \
        --out /workspace/preview.png --style both

    # 带游戏图集（真实纹理像素尺寸 + PNG 裁剪）
    python3 run_dst_ui.py --screen examples/hud_widget.lua \
        --textures /path/to/DST/data/images --out /workspace/hud.png --style both

    # 动画：每 0.1 虚拟秒采一帧，导出 APNG
    python3 run_dst_ui.py --screen examples/hud_widget.lua \
        --out /workspace/anim.png --capture 0.1 --anim

    # 交互：实例化后点击两个坐标（命中测试走真实矩形）
    python3 run_dst_ui.py --screen examples/mod_config_panel.lua \
        --out /workspace/clicked.png --click 640,200 --click 640,300

参数：
    --screen FILE       入口屏幕模块（必填）：返回类/工厂函数/类名字表的 .lua 文件
    --mod NAME=PATH     额外注册到 require 的本地模块（可多次，供多文件屏幕使用）
    --class NAME        入口模块返回类名字表时，指定要实例化的类名
    --out FILE          输出路径（默认 ./dst_ui.png；html 用同名 .html）
    --viewport WxH      视口（默认 1280x720，即 DST PROPORTIONAL 基准）
    --bg COLOR          画布背景色 #RRGGBB（默认 #171512，DST 暗色）
    --style S           none=只出引擎报告 | hires=高清 PNG | html=网页 | both=两者
    --textures PATH     DST 图集 XML 或其所在目录（可多次）；提供后按真实像素
                       尺寸渲染，并从同名 PNG 裁剪出真实纹理
    --default-tex-size WxH   无图集信息时纹理占位尺寸（默认 100x100）
    --pump SECONDS      实例化后推进的虚拟秒数（默认 1.0）
    --pump-dt SECONDS   虚拟时钟步长（默认 1/30）
    --click X,Y         在该点命中并派发点击（可多次）
    --hover X,Y         在该点派发悬停（获得焦点，可多次）
    --capture SEC       动画：按该间隔采样绘制帧，0=关闭
    --max-frames N      动画帧上限（默认 240）
    --anim              额外导出 APNG（需 --capture）
    --fps N             APNG 帧率，0=按采样间隔推算
    --dump-json FILE    把引擎报告 JSON 落盘（可离线重渲染）
    --scale N           输出放大倍数（默认 2）
    --ss N              超采样倍数（默认 3）
    --no-glyphs         不绘制文字（只看几何与纹理）
退出码：0 = 无错误；1 = 运行错误/断言失败；2 = 用法/加载错误
"""

import argparse
import base64
import json
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))

# 模块加载顺序（bootstrap 定义全局设施 → widgets 依赖序 → harness → vision）
MODULES = [
    ("bootstrap", "runtime/bootstrap.lua"),
    ("widgets/widget", "runtime/widgets/widget.lua"),
    ("widgets/image", "runtime/widgets/image.lua"),
    ("widgets/text", "runtime/widgets/text.lua"),
    ("widgets/screen", "runtime/widgets/screen.lua"),
    ("widgets/button", "runtime/widgets/button.lua"),
    ("widgets/imagebutton", "runtime/widgets/imagebutton.lua"),
    ("widgets/threeslice", "runtime/widgets/threeslice.lua"),
    ("widgets/spinner", "runtime/widgets/spinner.lua"),
    ("widgets/menu", "runtime/widgets/menu.lua"),
    ("widgets/textedit", "runtime/widgets/textedit.lua"),
    ("widgets/uianim", "runtime/widgets/uianim.lua"),
    ("harness", "runtime/harness.lua"),
    ("vision", "vision/vision_dst.lua"),
]

# 内置 widget 模块 → 全局类名（供 require "widgets/image" 返回真实类）
BUILTIN_GLOBALS = {
    "widget": "Widget",
    "image": "Image",
    "text": "Text",
    "screen": "Screen",
    "button": "Button",
    "imagebutton": "ImageButton",
    "threeslice": "ThreeSlice",
    "spinner": "Spinner",
    "menu": "Menu",
    "textedit": "TextEdit",
    "uianim": "UIAnim",
}

SENTINEL_BEGIN = "--DSTUI_JSON_BEGIN--"
SENTINEL_END = "--DSTUI_JSON_END--"

# 内联入口：b64 解码 + loadsrc（各模块在同一全局环境执行，裸全局互通）
LUA_HEADER = r"""
local REAL_LOAD = load or loadstring
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64rev = {}
for i = 1, #b64chars do b64rev[string.sub(b64chars, i, i)] = i - 1 end
local function b64decode(s)
  s = string.gsub(s, "[^A-Za-z0-9%+%/%=]", "")
  local out = {}
  local acc = 0
  local bits = 0
  for i = 1, #s do
    local c = string.sub(s, i, i)
    if c == "=" then break end          -- 填充符：解码终止（否则会多吐 \x00）
    local v = b64rev[c]
    if v == nil then v = 0 end
    acc = (acc * 64) + v
    bits = bits + 6
    if bits >= 8 then
      bits = bits - 8
      local byte = math.floor(acc / (2 ^ bits)) % 256
      out[#out + 1] = string.char(byte)
      acc = acc % (2 ^ bits)
    end
  end
  return table.concat(out)
end
local function loadsrc(name, b64)
  local src = b64decode(b64)
  local c, err = REAL_LOAD(src, "@" .. name)
  if not c then error("加载 " .. name .. " 失败: " .. tostring(err)) end
  return c()
end
"""


def fail(msg, code=2):
    print("[run_dst_ui] " + msg, file=sys.stderr)
    sys.exit(code)


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    return data.decode("utf-8").lstrip("\ufeff\ufffc")


def b64(s):
    return base64.b64encode(s.encode("utf-8")).decode("ascii")


def lua_str(s):
    """Python 字符串 → Lua 字符串字面量（含引号）。"""
    out = ['"']
    for ch in str(s):
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif 32 <= o < 127:
            out.append(ch)
        else:
            out.append("\\u{%x}" % o if o <= 0x10FFFF else "?")
    out.append('"')
    return "".join(out)


def hex_to_rgb(s):
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    if len(s) != 6:
        fail("--bg 应为 #RRGGBB")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


# ------------------------------------------------------------
# DST 图集解析：XML（Elements/Element u1 v1 u2 v2）+ 同名 PNG
# ------------------------------------------------------------
def parse_atlas_xml(xml_path):
    """解析单个 DST 图集 XML → {texname: (u1, v1, u2, v2)}"""
    try:
        tree = ET.parse(xml_path)
    except Exception as e:
        print("[run_dst_ui] 图集解析失败 %s: %s" % (xml_path, e), file=sys.stderr)
        return {}
    out = {}
    for el in tree.getroot().iter("Element"):
        name = el.get("name")
        if not name:
            continue
        try:
            uv = (float(el.get("u1", 0)), float(el.get("v1", 0)),
                  float(el.get("u2", 0)), float(el.get("v2", 0)))
        except (TypeError, ValueError):
            continue
        out[name] = uv
    return out


def build_texmap(paths, warn_fn):
    """--textures 指向 XML 或目录 → {"atlas:tex": {w,h,png,crop}}"""
    xml_files = []
    for p in paths:
        if not os.path.exists(p):
            warn_fn("--textures 路径不存在: " + p)
            continue
        if os.path.isfile(p):
            if p.lower().endswith(".xml"):
                xml_files.append(p)
        else:
            for root, _dirs, files in os.walk(p):
                for fn in sorted(files):
                    if fn.lower().endswith(".xml"):
                        xml_files.append(os.path.join(root, fn))
    if not xml_files:
        if paths:
            warn_fn("--textures 未找到任何 .xml 图集")
        return {}

    texmap = {}
    for xp in xml_files:
        parent = os.path.dirname(xp)            # .../images
        grand = os.path.dirname(parent)         # .../data（DST 惯例：data/images/foo.xml）
        rel = os.path.relpath(xp, grand).replace(os.sep, "/")
        if rel.startswith(".."):
            rel = os.path.basename(xp)          # 非 data/images 结构 → 退化为 basename
        atlas_keys = [rel]
        base = os.path.basename(xp)
        if base not in atlas_keys:
            atlas_keys.append(base)
        # 同目录同名 PNG（DST: images/foo.xml ↔ images/foo.png）
        png_path = os.path.splitext(xp)[0] + ".png"
        if not os.path.exists(png_path):
            png_path = ""
        png_w = png_h = 0
        if png_path:
            try:
                from PIL import Image
                with Image.open(png_path) as im:
                    png_w, png_h = im.size
            except Exception:
                png_path = ""
        for tex, (u1, v1, u2, v2) in parse_atlas_xml(xp).items():
            entry = {"w": 100, "h": 100}
            if png_path and png_w > 0:
                w = int(round((u2 - u1) * png_w))
                h = int(round((v2 - v1) * png_h))
                entry["w"] = max(1, w)
                entry["h"] = max(1, h)
                # DST 图集 v 轴为 OpenGL 底原点 → 翻转为 PIL 顶原点裁剪盒
                x0 = int(round(u1 * png_w))
                x1 = int(round(u2 * png_w))
                y0 = int(round((1.0 - v2) * png_h))
                y1 = int(round((1.0 - v1) * png_h))
                entry["png"] = png_path
                entry["crop"] = [x0, y0, x1, y1]
            for ak in atlas_keys:
                texmap[ak + ":" + tex] = entry
    return texmap


def texmap_lua_literal(texmap):
    lines = ["{"]
    for key in sorted(texmap):
        e = texmap[key]
        parts = ["w = %d" % int(e["w"]), "h = %d" % int(e["h"])]
        if e.get("png"):
            parts.append("png = %s" % lua_str(e["png"]))
        if e.get("crop"):
            parts.append("crop = {%d, %d, %d, %d}" % tuple(int(v) for v in e["crop"]))
        lines.append("  [%s] = { %s }," % (lua_str(key), ", ".join(parts)))
    lines.append("}")
    return "\n".join(lines)


def parse_xy(spec, what):
    try:
        x, y = (float(t) for t in spec.split(","))
        return x, y
    except ValueError:
        fail("%s 格式应为 X,Y（如 640,300）" % what)


def hires_path(out_path):
    root, ext = os.path.splitext(out_path)
    return root + "_hires" + (ext or ".png")


def html_path(out_path):
    root, _ = os.path.splitext(out_path)
    return root + ".html"


def anim_path(out_path):
    root, _ = os.path.splitext(out_path)
    return root + "_anim.png"


def build_main_src(args, mod_b64, screen_modname, screen_src, extra_mods, vw, vh, texmap,
                   default_tex_w, default_tex_h, clicks=(), hovers=()):
    """生成主入口 Lua：加载模块 → 注入配置 → 实例化入口 → pump → 点击 → 报告"""
    lines = [LUA_HEADER]
    for name, _rel in MODULES:
        lines.append("loadsrc([[%s]], [[%s]])" % (name, mod_b64[name]))

    # 内置 widget 类注册给 require mock
    lines.append("do")
    lines.append("  local __builtins = {")
    for mod, gname in BUILTIN_GLOBALS.items():
        lines.append('    ["widgets/%s"] = %s,' % (mod, gname))
    lines.append("  }")
    lines.append("  for k, v in pairs(__builtins) do __DST_MODS[k] = v end")
    lines.append("end")

    # 用户模块注册（入口屏幕 + --mod 额外模块）
    lines.append("__DST_MODS[%s] = b64decode([[%s]])" % (lua_str(screen_modname), b64(screen_src)))
    for name, src in extra_mods:
        lines.append("__DST_MODS[%s] = b64decode([[%s]])" % (lua_str(name), b64(src)))

    # 配置注入
    lines.append("__DST.viewport = { w = %d, h = %d }" % (vw, vh))
    lines.append("__DST.defaultTexSize = { w = %d, h = %d }" % (default_tex_w, default_tex_h))
    lines.append("__DST.texmap = %s" % texmap_lua_literal(texmap))
    # --style none（调试用）时把完整报告打到 stdout，渲染模式只打一行摘要
    lines.append("__DST.emit_stdout = %s" % ("true" if args.style == "none" else "false"))
    if args.cls:
        lines.append("Harness.className = %s" % lua_str(args.cls))

    # 实例化入口屏幕
    lines.append("Harness.runEntry(%s)" % lua_str(screen_modname))

    # 动画捕获（实例化后即可开始，覆盖 pump 与点击全过程）
    if args.capture > 0:
        lines.append("Harness.startCapture(%r, %d)" % (args.capture, max(2, args.max_frames)))

    # 推进虚拟时钟
    lines.append("Harness.pump(%r, %r)" % (args.pump, args.pump_dt))

    # 点击 / 悬停
    for x, y in clicks:
        lines.append("Harness.click(%r, %r)" % (x, y))
        lines.append("Harness.pump(%r, %r)" % (args.pump_dt * 2, args.pump_dt))
    for x, y in hovers:
        lines.append("Harness.hover(%r, %r)" % (x, y))
        lines.append("Harness.pump(%r, %r)" % (args.pump_dt * 2, args.pump_dt))

    if args.capture > 0:
        lines.append("Harness.stopCapture()")
    lines.append("Harness.summary()")
    lines.append("Harness.emitReport()")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--screen", required=True, help="入口屏幕模块 .lua 文件")
    ap.add_argument("--mod", action="append", default=[],
                    help="NAME=PATH：额外注册到 require 的本地模块（可多次）")
    ap.add_argument("--class", dest="cls", default="",
                    help="入口模块返回类名字表时指定类名")
    ap.add_argument("--out", default="./dst_ui.png", help="输出路径")
    ap.add_argument("--viewport", default="1280x720")
    ap.add_argument("--bg", default="#171512", help="画布背景色 #RRGGBB")
    ap.add_argument("--style", choices=["none", "hires", "html", "both"], default="hires")
    ap.add_argument("--textures", action="append", default=[],
                    help="DST 图集 XML 或目录（可多次）")
    ap.add_argument("--default-tex-size", default="100x100")
    ap.add_argument("--pump", type=float, default=1.0, help="实例化后推进的虚拟秒数")
    ap.add_argument("--pump-dt", type=float, default=1.0 / 30.0)
    ap.add_argument("--click", action="append", default=[], help="X,Y 派发点击（可多次）")
    ap.add_argument("--hover", action="append", default=[], help="X,Y 派发悬停（可多次）")
    ap.add_argument("--capture", type=float, default=0.0, help="动画采样间隔（虚拟秒）")
    ap.add_argument("--max-frames", type=int, default=240)
    ap.add_argument("--anim", action="store_true", help="额外导出 APNG（需 --capture）")
    ap.add_argument("--fps", type=float, default=0.0)
    ap.add_argument("--dump-json", default="")
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--ss", type=int, default=3)
    ap.add_argument("--no-glyphs", action="store_true")
    args = ap.parse_args()

    # ---- 参数校验 ----
    try:
        vw, vh = (int(x) for x in args.viewport.lower().split("x"))
    except ValueError:
        fail("--viewport 格式应为 WxH")
    if vw <= 0 or vh <= 0:
        fail("视口必须为正数")
    try:
        dtw, dth = (int(x) for x in args.default_tex_size.lower().split("x"))
    except ValueError:
        fail("--default-tex-size 格式应为 WxH")
    clicks = [parse_xy(s, "--click") for s in args.click]
    hovers = [parse_xy(s, "--hover") for s in args.hover]

    if not os.path.exists(args.screen):
        fail("入口屏幕文件不存在: " + args.screen)
    screen_src = read_text(args.screen)
    screen_modname = os.path.splitext(os.path.basename(args.screen))[0]

    extra_mods = []
    for spec in args.mod:
        if "=" not in spec:
            fail("--mod 格式应为 NAME=PATH")
        name, _, path = spec.partition("=")
        if not os.path.exists(path):
            fail("--mod 文件不存在: " + path)
        extra_mods.append((name, read_text(path)))

    for name, rel in MODULES:
        p = os.path.join(os.path.dirname(HERE), rel)
        if not os.path.exists(p):
            fail("缺少运行时模块: " + p)

    texmap = build_texmap(args.textures, lambda m: print("[run_dst_ui] " + m, file=sys.stderr))
    bg = hex_to_rgb(args.bg)

    # ---- 运行时（lupa：真实 Lua VM；DST mod 为 Lua 5.1 风格，语义最接近） ----
    try:
        import lupa as _lupa
    except ImportError:
        fail("需要 lupa 来执行 Lua（pip install lupa）", 2)
    lupa = _lupa

    mod_b64 = {}
    for name, rel in MODULES:
        mod_b64[name] = b64(read_text(os.path.join(os.path.dirname(HERE), rel)))

    main_src = build_main_src(args, mod_b64, screen_modname, screen_src, extra_mods,
                              vw, vh, texmap, dtw, dth, clicks, hovers)

    rep = None
    engine = "lupa(Lua %s)" % (".".join(str(v) for v in (getattr(lupa, "LUA_VERSION", None) or ("5.x",))),)
    try:
        L = lupa.LuaRuntime(unpack_returned_tuples=True)
        L.execute(main_src)
        g = L.eval("type(__REPORT_JSON) == 'string' and __REPORT_JSON or ''")
        rep_text = str(g)
        rep = json.loads(rep_text) if rep_text.strip() else None
    except Exception as e:
        # 语法错误/未捕获的 Lua 异常：直接给出可读原因（widget 内部错误已被 harness 收集）
        print("[run_dst_ui] Lua 执行失败:\n%s" % e, file=sys.stderr)
        rep = None

    if rep is None:
        fail("未能获取引擎报告（入口屏幕可能未正常实例化，见上方输出）", 1)
    rep["engine"] = engine

    if args.dump_json:
        with open(args.dump_json, "w", encoding="utf-8") as f:
            json.dump(rep, f, ensure_ascii=False)
        print("[run_dst_ui] 报告已落盘 %s" % args.dump_json)

    frames = rep.get("frames") or []
    if frames:
        print("[run_dst_ui] 动画帧 %d（采样间隔 %.2fs）"
              % (len(frames), float(rep.get("frameInterval", 0.2))))

    if args.style in ("hires", "both"):
        from render_hires import render_hires
        hp = args.out if args.style == "hires" else hires_path(args.out)
        himg = render_hires(rep, hp, bg=bg, scale=max(1, args.scale),
                            ss=max(1, args.ss), show_text=not args.no_glyphs)
        print("[run_dst_ui] 已导出(hires) %s  (%dx%d px, 放大 x%d · 超采样 x%d)"
              % (hp, himg.width, himg.height, max(1, args.scale), max(1, args.ss)))
        if args.anim and len(frames) > 1:
            from render_hires import render_apng
            ap = anim_path(hp)
            aimg = render_apng(rep, ap, bg=bg, scale=max(1, args.scale),
                               ss=max(1, args.ss), show_text=not args.no_glyphs,
                               fps=args.fps)
            if aimg:
                print("[run_dst_ui] 已导出(apng)  %s  (%d 帧)" % (ap, len(frames)))
    if args.style in ("html", "both"):
        from render_html import render_html
        pp = args.out if args.style == "html" else html_path(args.out)
        render_html(rep, pp, title=os.path.basename(args.screen))
        print("[run_dst_ui] 已导出(html)  %s  (可交互预览%s)"
              % (pp, "，含动画时间轴" if len(frames) > 1 else ""))

    nerr = len(rep.get("errors") or [])
    nwarn = len(rep.get("warnings") or [])
    st = (rep.get("widgets") or {})
    print("[run_dst_ui] 引擎 %s | widget %d（图 %d / 文 %d / 占位 %d）| 点击 %d | 警告 %d | 错误 %d"
          % (engine, int(st.get("count", 0)), int(st.get("images", 0)),
             int(st.get("texts", 0)), int(st.get("placeholders", 0)),
             len(rep.get("clicks") or []), nwarn, nerr))
    if nerr:
        for e in (rep.get("errors") or [])[:10]:
            print("  [error] " + str(e), file=sys.stderr)
    sys.exit(0 if nerr == 0 else 1)


if __name__ == "__main__":
    main()
