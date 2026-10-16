-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- widgets/threeslice.lua — ThreeSlice（预览 mock）
-- 三段式拉伸背景：Flow(w, h, center) 设定内容尺寸，
-- 渲染为「首尾段 + 中段拉伸」的占位/真实纹理组合。
-- ============================================================

ThreeSlice = Class(Widget, function(self, atlas, beg, mid, _end)
    Widget._ctor(self, "ThreeSlice")
    self.className = "ThreeSlice"
    self.atlas = atlas
    self.tex_beg = beg
    self.tex_mid = mid
    self.tex_end = _end
    self.tint = { 1, 1, 1, 1 }
end)

function ThreeSlice:Flow(w, h, center)
    self.contentSize.w = w
    self.contentSize.h = h
    self.centered = center
end

function ThreeSlice:SetTint(r, g, b, a)
    if type(r) == "number" then
        self.tint = { r, g or 1, b or 1, a or 1 }
    else
        self.tint = { r[1], r[2], r[3], r[4] }
    end
end

return ThreeSlice
