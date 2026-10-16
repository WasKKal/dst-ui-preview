-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- hud_widget.lua — 带动画的 HUD 部件（演示虚拟时钟 / 补间 / 点击）
--
-- 覆盖：DoTaskInTime / DoPeriodicTask（虚拟时钟真实求值）、MoveTo / ScaleTo /
--       RotateTo（按 vclock 逐帧插值）、StartUpdating(OnUpdate)、Image 缩放条、
--       旋转（DST 为 y 向上、逆时针为正）、点击展开/收起。
--
-- 预览（静态）：
--   python3 scripts/run_dst_ui.py --screen examples/hud_widget.lua \
--       --textures examples/textures --style both --out /workspace/hud.png
--
-- 预览（动画：每 0.1 虚拟秒采一帧，导出 APNG + 带时间轴的 HTML）：
--   python3 scripts/run_dst_ui.py --screen examples/hud_widget.lua \
--       --textures examples/textures --style both --out /workspace/hud.png \
--       --capture 0.1 --anim --pump 3
-- ============================================================
local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"
local ImageButton = require "widgets/imagebutton"

local HUDWidget = Class(Widget, function(self, owner)
    Widget._ctor(self, "HUDWidget")
    self.owner = owner
    self.progress = 0
    self.expanded = true

    -- 固定在左上角：锚点跟着父级的左上角计量（左减右加、上加下减）
    self:SetHAnchor(ANCHOR_LEFT)
    self:SetVAnchor(ANCHOR_TOP)
    self:SetPosition(200, -110)
    self:SetSize(300, 84)               -- 根盒尺寸：子控件按它居中/对齐

    local card = self:AddChild(Image("images/global_redux.xml", "panel_backdrop.tex"))
    card:SetSize(300, 84)
    card:SetTint(0.17, 0.16, 0.14, 0.92)
    card:SetScale(0.2, 0.2, 1)          -- 起始很小 → 下面 ScaleTo 弹出
    self.card = card

    local icon = self:AddChild(Image("images/global_redux.xml", "spin_arrow.tex"))
    icon:SetSize(38, 38)
    icon:SetPosition(-118, 0, 0)
    self.icon = icon

    local title = self:AddChild(Text(UIFONT, 24, "自动拾取"))
    title:SetPosition(-40, 16, 0)
    title:SetHAlign(ANCHOR_LEFT)
    self.title = title

    local count = self:AddChild(Text(NUMBERFONT, 26, "0"))
    count:SetPosition(-40, -14, 0)
    count:SetHAlign(ANCHOR_LEFT)
    count:SetColour(0.95, 0.85, 0.55, 1)
    self.count = count

    -- 进度条：底槽 + 填充（用 Scale 表达进度，避免频繁 SetSize）
    local bar_bg = self:AddChild(Image("images/global_redux.xml", "spinner_short.tex"))
    bar_bg:SetSize(180, 14)
    bar_bg:SetPosition(0, -30, 0)
    bar_bg:SetTint(0.10, 0.10, 0.09, 0.9)

    local bar = self:AddChild(Image("images/global_redux.xml", "divider.tex"))
    bar:SetSize(180, 10)
    bar:SetPosition(0, -30, 0.1)
    bar:SetTint(0.55, 0.85, 0.45, 1)
    bar:SetHRegPoint(ANCHOR_LEFT)       -- 从左侧生长（内容锚点在左）
    bar:SetScale(0, 1, 1)
    self.bar = bar
    self.bar_pos = Vector3(0, -30, 0.1)

    -- 右下角的小按钮：点击折叠/展开
    local toggle = self:AddChild(ImageButton("images/global_redux.xml",
                                             "checkbox_default.tex", "checkbox_focus.tex"))
    toggle:ForceImageSize(26, 26)
    toggle:SetPosition(126, 25, 0)
    toggle.onclick = function()
        self.expanded = not self.expanded
        if self.expanded then
            self:Show()
            self.card:ScaleTo(Vector3(0.2, 0.2, 1), Vector3(1, 1, 1), 0.25)
            count:SetString("展开")
        else
            self.card:ScaleTo(Vector3(1, 1, 1), Vector3(0.2, 0.2, 1), 0.2, function()
                self:Hide()
            end)
        end
    end
    self.toggle = toggle

    -- 入场：卡片弹开 + 图标从左侧滑入（补间按虚拟时钟插值）
    card:ScaleTo(Vector3(0.2, 0.2, 1), Vector3(1, 1, 1), 0.35)
    icon:MoveTo(Vector3(-190, 0, 0), Vector3(-118, 0, 0), 0.4)

    -- 延迟任务：0.6s 后把标题换成「已就绪」
    self:DoTaskInTime(0.6, function()
        title:SetString("自动拾取 · 就绪")
    end)

    -- 周期任务：每 0.2s 累积进度，跑满 100 后旋转图标（演示 CCW 正角度）
    self:DoPeriodicTask(0.2, function()
        if not self.expanded then return end
        self.progress = self.progress + 4
        if self.progress > 100 then self.progress = 0 end
        count:SetString(string.format("%d", self.progress))
        bar:SetScale(self.progress / 100, 1, 1)
        if self.progress == 100 then
            self.icon:RotateTo(0, 360, 0.5)
        end
    end)

    -- StartUpdating：每帧回调（可用于平滑跟随）
    self.t = 0
    self:StartUpdating()
end)

function HUDWidget:OnUpdate(dt)
    self.t = self.t + dt
    -- 轻微的呼吸缩放，证明每帧回调在跑（幅度小，不影响布局）
    local k = 1 + 0.02 * math.sin(self.t * 4)
    self.toggle:SetScale(k, k, 1)
    return true
end

return HUDWidget
