# 字体资源说明

本目录的字体仅用于**渲染预览图**（PNG/HTML），不参与游戏运行。

| 文件 | 字体 | 许可证 | 用途 |
| --- | --- | --- | --- |
| `SourceSans3-400.ttf` / `.woff2` | [Source Sans 3](https://github.com/adobe-fonts/source-sans) | SIL Open Font License 1.1 | 近似 DST 的 `DEFAULTFONT`(opensans)/`NEWFONT`(spirequal)/`BUTTONFONT` |
| `Inter-400.ttf` / `.woff2` | [Inter](https://github.com/rsms/inter) | SIL Open Font License 1.1 | 近似 DST 的 `UIFONT`(bp50)/`TITLEFONT`(bp100) |

两者都是可变字体（variable font），`render_hires.py` 通过 `set_variation_by_axes`
调整字重；`render_html.py` 以 woff2 data URI 内嵌，保证网页离线自包含。

CJK 与符号（✓ ★ → 等）在渲染时回退到系统字体 **Noto Sans CJK** 与 **DejaVu Sans**
（均为本机系统字体，不随本仓库分发）。

> 游戏内的位图字体由 DST 自带，本工具不复制、不分发任何 Klei 资源。
