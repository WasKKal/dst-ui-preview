#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WasKKal · DST UI Preview
"""
make_sample_atlas.py — 生成一张【示例图集】（XML + PNG），用于试用 --textures

真实游戏用 DST 安装目录 data/images/*.xml + *.png（或 mod 自带的图集）。
本脚本造一份同等结构的假图集，里面画了配置面板示例会用到的纹理名，
方便对比「占位块」与「真实纹理」两种渲染效果：

    python3 scripts/make_sample_atlas.py examples/textures
    python3 scripts/run_dst_ui.py --screen examples/mod_config_panel.lua \
        --textures examples/textures --style both --out /workspace/panel_tex.png
"""

import os
import sys

from PIL import Image, ImageDraw

W = H = 512
CELL = 64
NAMES = [
    # (纹理名, 画法)
    ("bg_plain.tex", "flat"),
    ("panel_backdrop.tex", "panel"),
    ("divider.tex", "divider"),
    ("button_medium_locked.tex", "button"),
    ("button_medium_hover.tex", "button_hover"),
    ("button_medium_pressed.tex", "button_down"),
    ("checkbox_default.tex", "box"),
    ("checkbox_focus.tex", "box_focus"),
    ("checkbox_disabled.tex", "box_disabled"),
    ("checkbox_selected.tex", "box_sel"),
    ("checkbox_checked.tex", "check"),
    ("spinner_short.tex", "spinner"),
    ("spin_arrow.tex", "arrow"),
    ("button_long.tex", "button_wide"),
    ("button_long_focus.tex", "button_wide_hover"),
]


def draw_cell(d, kind, box):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0

    def rrect(inset, fill, outline=None, width=2, radius=6):
        d.rounded_rectangle([x0 + inset, y0 + inset, x1 - inset, y1 - inset],
                            radius=radius, fill=fill, outline=outline, width=width)

    if kind == "flat":
        rrect(0, (150, 132, 104, 255))
    elif kind == "panel":
        rrect(0, (86, 74, 56, 255), (176, 152, 108, 255), 3, 10)
        rrect(6, (68, 58, 44, 255), None, 0, 8)
    elif kind == "divider":
        d.rectangle([x0, y0 + h // 2 - 1, x1, y0 + h // 2 + 1], fill=(186, 160, 108, 255))
    elif kind in ("button", "button_hover", "button_down", "button_wide",
                  "button_wide_hover"):
        # DST 的按钮牌是浅色骨白/羊皮纸色，配黑色文字（Button 默认 textcolour 为黑）
        top = {"button": (188, 172, 138), "button_hover": (214, 198, 162),
               "button_down": (146, 132, 104), "button_wide": (188, 172, 138),
               "button_wide_hover": (214, 198, 162)}[kind]
        rrect(0, (top[0], top[1], top[2], 255), (104, 92, 68, 255), 3, 8)
        d.rounded_rectangle([x0 + 5, y0 + 5, x1 - 5, y1 - 5], radius=6,
                            outline=(240, 230, 200, 150), width=2)
    elif kind in ("box", "box_focus", "box_disabled", "box_sel"):
        fill = {"box": (58, 52, 42), "box_focus": (74, 66, 50),
                "box_disabled": (44, 42, 38), "box_sel": (58, 52, 42)}[kind]
        out = {"box": (168, 148, 108), "box_focus": (226, 206, 150),
               "box_disabled": (94, 88, 76), "box_sel": (168, 148, 108)}[kind]
        rrect(2, (fill[0], fill[1], fill[2], 255), (out[0], out[1], out[2], 255), 2, 5)
    elif kind == "check":
        rrect(2, (0, 0, 0, 0), None, 0, 5)
        d.line([(x0 + 14, y0 + 32), (x0 + 26, y0 + 46), (x0 + 50, y0 + 16)],
               fill=(122, 214, 110, 255), width=7, joint="curve")
    elif kind == "spinner":
        rrect(0, (54, 48, 40, 255), (170, 148, 108, 255), 2, 6)
    elif kind == "arrow":
        rrect(0, (0, 0, 0, 0), None, 0, 0)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        d.polygon([(cx - 12, cy - 6), (cx + 12, cy - 6), (cx, cy + 12)],
                  fill=(230, 212, 160, 255))


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "examples/textures"
    imgdir = os.path.join(outdir, "images")
    os.makedirs(imgdir, exist_ok=True)

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cols = W // CELL
    elements = []
    for i, (name, kind) in enumerate(NAMES):
        col, row = i % cols, i // cols
        x0, y0 = col * CELL, row * CELL
        # 上下留边，模拟图集里加了 padding 的排布
        box = (x0 + 2, y0 + 2, x0 + CELL - 2, y0 + CELL - 2)
        draw_cell(d, kind, box)
        # DST 图集 XML 的 v 轴为 OpenGL 底原点 → 换算
        u1, u2 = x0 / W, (x0 + CELL) / W
        v1, v2 = 1.0 - (y0 + CELL) / H, 1.0 - y0 / H
        elements.append((name, u1, v1, u2, v2))

    png_path = os.path.join(imgdir, "frontend.png")
    img.save(png_path)

    lines = ['<Atlas>', '  <Texture filename="images/frontend.tex"/>', '  <Elements>']
    for name, u1, v1, u2, v2 in elements:
        lines.append('    <Element name="%s" u1="%f" v1="%f" u2="%f" v2="%f"/>'
                     % (name, u1, v1, u2, v2))
    lines += ['  </Elements>', '</Atlas>', '']
    xml_body = "\n".join(lines)
    xml_path = os.path.join(imgdir, "frontend.xml")
    with open(xml_path, "w", encoding="utf-8") as f:
        f.write(xml_body)

    # 同一份图集再出一份 global_redux 名字：DST 里控件纹理多来自
    # images/global_redux.xml，示例屏幕两种引用都有，方便一次跑通
    with open(os.path.join(imgdir, "global_redux.xml"), "w", encoding="utf-8") as f:
        f.write(xml_body.replace("images/frontend.tex", "images/global_redux.tex"))
    img.save(os.path.join(imgdir, "global_redux.png"))

    print("已生成示例图集:")
    print("  " + png_path + "（同名 global_redux.* 亦已生成）")
    print("  " + xml_path)
    print("  %d 个纹理: %s" % (len(NAMES), ", ".join(n for n, _ in NAMES[:6]) + ", ..."))
    print("\n试用:")
    print("  python3 scripts/run_dst_ui.py --screen examples/mod_config_panel.lua \\")
    print("      --textures %s --style both --out /workspace/panel_real.png" % outdir)


if __name__ == "__main__":
    main()
