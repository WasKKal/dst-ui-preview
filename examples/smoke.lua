-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- 冒烟测试：最小屏幕（Image + Text + Button）
-- 用法：python3 scripts/run_dst_ui.py --screen examples/smoke.lua --style both
-- 交互：--click 640,300 命中的是「点我」按钮
local Image = require "widgets/image"
local Text = require "widgets/text"
local Widget = require "widgets/widget"
local Button = require "widgets/button"

local SmokeScreen = Class(Widget, function(self)
    Widget._ctor(self, "SmokeScreen")

    -- 全屏底色（无图集时渲染为占位块，可用 --textures 提供真实纹理）
    local bg = self:AddChild(Image("images/frontend.xml", "bg_plain.tex"))
    bg:SetSize(1280, 720)
    bg:SetTint(0.16, 0.14, 0.12, 1)

    local title = self:AddChild(Text(TITLEFONT, 48, "冒烟测试 SMOKE"))
    title:SetPosition(0, 240)
    title:SetColour(1, 0.9, 0.7, 1)

    local sub = self:AddChild(Text(UIFONT, 26, "DST UI 预览工具 · 管线验证"))
    sub:SetPosition(0, 180)

    -- DST 的 Button 自身没有尺寸：必须 SetSize 才有可点击区域（预览工具会提示）
    local btn = self:AddChild(Button())
    btn:SetSize(240, 60)
    btn:SetPosition(0, 60)
    btn:SetText("点我")
    btn.onclick = function()
        sub:SetString(string.format("点击已派发 · %.2fs", TheSim:GetRealTime()))
    end

    self.btn = btn
end)

return SmokeScreen
