-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- widgets/widget.lua — DST Widget 基类（预览 mock）
--
-- 记录布局状态（position/scale/anchor/scalemode/可见性/子节点序），
-- 供 vision_dst.lua 生成绘制列表；同时完整模拟：
--   AddChild/RemoveChild/Show/Hide/Enable/Disable/Select
--   SetPosition/SetScale/SetRotation/SetHAnchor/SetVAnchor
--   StartUpdating/StopUpdating（OnUpdate 每帧回调）
--   MoveTo/ScaleTo/RotateTo/TintTo（按虚拟时钟真实插值）
--   焦点（SetFocus/OnGainFocus/OnLoseFocus）与点击（OnControl）
-- ============================================================

local anchorFactor = function(a)
    if a == ANCHOR_MIDDLE then return 0.5 end
    if a == ANCHOR_RIGHT or a == ANCHOR_BOTTOM then return 1 end
    return 0 -- LEFT / TOP
end
__DST.anchorFactor = anchorFactor

local function scalemodeFactor(w)
    local m = w.scalemode or SCALEMODE_NONE
    local VW, VH = __DST.viewport.w, __DST.viewport.h
    if m == SCALEMODE_FILLSCREEN then
        local cw, ch = w.contentSize.w, w.contentSize.h
        if cw > 0 and ch > 0 then return VW / cw, VH / ch end
        return 1, 1
    elseif m == SCALEMODE_PROPORTIONAL or m == SCALEMODE_FIXEDPROPORTIONAL
        or m == SCALEMODE_FIXEDSCREEN_NONDYNAMIC then
        local s = math.min(VW / RESOLUTION_X, VH / RESOLUTION_Y)
        return s, s
    end
    return 1, 1
end
__DST.scalemodeFactor = scalemodeFactor

-- 从根屏幕走到 widget，累积世界坐标（DST 坐标：y 向上）
-- 返回 wx, wy（世界点）, sx, sy（世界缩放）
function __DST.worldTransform(widget)
    local chain = {}
    local w = widget
    while w do
        table.insert(chain, 1, w)
        w = w.parent
    end
    local px, py = 0, 0
    local psx, psy = 1, 1
    local psize = { w = __DST.viewport.w, h = __DST.viewport.h }
    for _, c in ipairs(chain) do
        local hf = anchorFactor(c.hanchor)
        local vf = anchorFactor(c.vanchor)
        local offx = (hf - 0.5) * psize.w
        local offy = (0.5 - vf) * psize.h
        px = px + psx * (offx + (c.pos and c.pos.x or 0))
        py = py + psy * (offy + (c.pos and c.pos.y or 0))
        local smx, smy = scalemodeFactor(c)
        psx = psx * (c.scale and c.scale.x or 1) * smx
        psy = psy * (c.scale and c.scale.y or 1) * smy
        psize = { w = (c.contentSize and c.contentSize.w) or 0, h = (c.contentSize and c.contentSize.h) or 0 }
    end
    return px, py, psx, psy
end

-- 内容锚点（Image 的 reg point / Text 的 align）决定内容盒相对世界点的偏移
-- 返回内容盒（DST y-up 坐标）：bx0, by0, bx1, by1
function __DST.contentRect(widget, px, py, w, h)
    local hreg = widget.hreg or ANCHOR_MIDDLE
    local vreg = widget.vreg or ANCHOR_MIDDLE
    local hf = anchorFactor(hreg)  -- LEFT=0 MIDDLE=.5 RIGHT=1
    local vf = anchorFactor(vreg)
    local bx1 = px + (hf - 0.5) * w + w / 2
    local by1 = py + (0.5 - vf) * h + h / 2
    return bx1 - w, by1 - h, bx1, by1
end

Widget = Class(function(self, name)
    name = name or "widget"
    self.name = name
    self.className = "Widget"
    self.children = {}
    self.childList = {}
    self.parent = nil

    self.enabled = true
    self.shown = true
    self.focus = false
    self.can_fade_alpha = true

    -- 变换状态（vision 的数据源）
    self.pos = { x = 0, y = 0, z = 0 }
    self.scale = { x = 1, y = 1, z = 1 }
    self.rotation = 0
    self.hanchor = ANCHOR_MIDDLE
    self.vanchor = ANCHOR_MIDDLE
    self.scalemode = SCALEMODE_NONE
    self.maxPropUpscale = MAX_FE_SCALE

    -- 内容尺寸（子类覆盖：Image=纹理尺寸，Text=测量区域，Spinner=显式宽高）
    self.contentSize = { w = 0, h = 0 }
    -- 内容锚点（Image/Text 使用）
    self.hreg = ANCHOR_MIDDLE
    self.vreg = ANCHOR_MIDDLE

    self.clickable = false
    self.updating = false
    self.selected = false
    self.down = false
    self.dead = false
    self.tooltip = nil
    self.hovertext = nil

    self.inst = __DST.Entity(self, name)
    self.inst.widget = self
end)

-- ------------------------------------------------------------
-- 层级
-- ------------------------------------------------------------
function Widget:AddChild(child)
    if child == nil then return nil end
    if child.parent then
        child.parent.children[child] = nil
        for i, c in ipairs(child.parent.childList) do
            if c == child then table.remove(child.parent.childList, i); break end
        end
    end
    self.children[child] = child
    child.parent = self
    self.childList[#self.childList + 1] = child
    return child
end

function Widget:RemoveChild(child)
    if not child then return end
    self.children[child] = nil
    for i, c in ipairs(self.childList) do
        if c == child then table.remove(self.childList, i); break end
    end
    child.parent = nil
end

function Widget:KillAllChildren()
    for _, c in ipairs(self.childList) do
        c.parent = nil
        c.dead = true
    end
    self.children = {}
    self.childList = {}
end

function Widget:Kill()
    if self.parent then
        self.parent:RemoveChild(self)
    end
    self.dead = true
    self:KillAllChildren()
end

function Widget:GetParent() return self.parent end

function Widget:GetChildren()
    return self.childList
end

function Widget:GetNumChildren() return #self.childList end

-- ------------------------------------------------------------
-- 可见性 / 启用
-- ------------------------------------------------------------
-- 可选回调的真实空实现：DST 的 Widget 提供了这些钩子的默认空实现，
-- 这里给出同名空方法，避免 `if self.OnShow then ... end` 因「未知大写成员兜底」
-- 而误判为已实现（那会刷出一堆“未 mock 的调用”警告）。
function Widget:OnShow(instant) end
function Widget:OnHide(instant) end

function Widget:Show()
    local was = self.shown
    self.shown = true
    if not was and self.OnShow then pcall(self.OnShow, self, true) end
end

function Widget:Hide()
    local was = self.shown
    self.shown = false
    if was and self.OnHide then pcall(self.OnHide, self, true) end
end

function Widget:Toggle()
    if self.shown then self:Hide() else self:Show() end
end

function Widget:IsVisible() return self.shown end

function Widget:IsShown() return self.shown end

-- 沿树累积的有效可见性（vision 使用）
function Widget:IsDeepVisible()
    local w = self
    while w do
        if not w.shown then return false end
        w = w.parent
    end
    return true
end

function Widget:Enable()
    local was = self.enabled
    self.enabled = true
    if not was and self.OnEnable then pcall(self.OnEnable, self) end
end

function Widget:Disable()
    local was = self.enabled
    self.enabled = false
    if was and self.OnDisable then pcall(self.OnDisable, self) end
end

function Widget:IsEnabled()
    local w = self
    while w do
        if not w.enabled then return false end
        w = w.parent
    end
    return true
end

function Widget:IsDisabledState() return not self:IsEnabled() end

function Widget:IsFocusedState() return self.focus and self:IsEnabled() end

function Widget:IsNormalState() return self:IsEnabled() and not self.focus end

function Widget:Select()
    self.selected = true
    if self.OnSelect then pcall(self.OnSelect, self) end
end

function Widget:Unselect()
    self.selected = false
    if self.OnUnselect then pcall(self.OnUnselect, self) end
end

function Widget:IsSelected() return self.selected end

-- ------------------------------------------------------------
-- 位置 / 变换
-- ------------------------------------------------------------
function Widget:SetPosition(pos, y, z)
    if type(pos) == "number" then
        self.pos.x, self.pos.y, self.pos.z = pos, y or 0, z or 0
    else
        self.pos.x, self.pos.y, self.pos.z = pos.x or 0, pos.y or 0, pos.z or 0
    end
end

function Widget:GetPosition() return Vector3(self.pos.x, self.pos.y, self.pos.z) end
function Widget:GetLocalPosition() return self:GetPosition() end
function Widget:GetPositionXYZ() return self.pos.x, self.pos.y, self.pos.z end

function Widget:GetWorldPosition()
    local x, y = __DST.worldTransform(self)
    return Vector3(x, y, 0)
end

function Widget:Nudge(offset)
    if type(offset) == "number" then
        self.pos.x = self.pos.x + offset
    else
        self.pos.x = self.pos.x + (offset.x or 0)
        self.pos.y = self.pos.y + (offset.y or 0)
        self.pos.z = self.pos.z + (offset.z or 0)
    end
end

function Widget:SetScale(pos, y, z)
    if type(pos) == "number" then
        self.scale.x = pos
        self.scale.y = y or pos
        self.scale.z = z or pos
    else
        self.scale.x = pos.x or 1
        self.scale.y = pos.y or 1
        self.scale.z = pos.z or 1
    end
end

function Widget:GetScale() return Vector3(self.scale.x, self.scale.y, self.scale.z) end
function Widget:GetLooseScale() return self:GetScale() end

function Widget:GetWorldScale()
    local _, _, sx, sy = __DST.worldTransform(self)
    return Vector3(sx, sy, 1)
end

function Widget:SetRotation(angle) self.rotation = angle or 0 end
function Widget:GetRotation() return self.rotation end

function Widget:SetHAnchor(a) self.hanchor = a end
function Widget:SetVAnchor(a) self.vanchor = a end
function Widget:GetHAnchor() return self.hanchor end
function Widget:GetVAnchor() return self.vanchor end

function Widget:SetScaleMode(m) self.scalemode = m end
function Widget:GetScaleMode() return self.scalemode end
function Widget:SetMaxPropUpscale(v) self.maxPropUpscale = v end

function Widget:SetClickable(v) self.clickable = v and true or false end
function Widget:IsClickable() return self.clickable end

-- 尺寸（contentSize）：DST 的 Widget 也提供，纯 Widget/Button 需显式 SetSize 才有可点击区域
function Widget:SetSize(w, h)
    if w ~= nil then self.contentSize.w = w end
    if h ~= nil then self.contentSize.h = h end
end
function Widget:GetSize() return self.contentSize.w, self.contentSize.h end

function Widget:MoveToFront()
    if self.parent then
        local p = self.parent
        for i, c in ipairs(p.childList) do
            if c == self then table.remove(p.childList, i); break end
        end
        p.childList[#p.childList + 1] = self
    end
end

function Widget:MoveToBack()
    if self.parent then
        local p = self.parent
        for i, c in ipairs(p.childList) do
            if c == self then table.remove(p.childList, i); break end
        end
        table.insert(p.childList, 1, self)
    end
end

function Widget:SendToFront() self:MoveToFront() end
function Widget:SendToBack() self:MoveToBack() end

function Widget:SetTooltip(...) self.tooltip = { ... } end
function Widget:SetHoverText(...) self.hovertext = { ... } end
function Widget:GetTooltip() return self.tooltip end

-- ------------------------------------------------------------
-- 每帧更新（StartUpdating 注册后由 harness.pump 驱动）
-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- 定时任务（虚拟时钟）：Widget 上绕一圈调用全局调度器
--   DoTaskInTime(t, fn, ...)          延迟一次
--   DoPeriodicTask(t, fn, initial, …) 周期执行（initial 为首次延迟）
--   DoStaticTaskInTime(t, fn, ...)    同 DoTaskInTime（DST 的静态版）
-- 返回任务句柄，可用 task:Cancel() 取消（对应 DST 的 task 对象）
-- ------------------------------------------------------------
local function asCancelable(task)
    if type(task) == "table" then
        task.Cancel = function(self) self.cancelled = true end
    end
    return task
end

function Widget:DoTaskInTime(time, fn, ...)
    local args = { ... }
    local task
    task = __DST.after(time or 0, function()
        if task and task.cancelled then return end
        fn(self, unpack(args))
    end)
    return asCancelable(task)
end

function Widget:DoStaticTaskInTime(time, fn, ...)
    return self:DoTaskInTime(time, fn, ...)
end

function Widget:DoPeriodicTask(time, fn, initialdelay, ...)
    local args = { ... }
    local task
    task = __DST.every(time or 0.1, function()
        if task and task.cancelled then return end
        fn(self, unpack(args))
    end)
    if initialdelay then
        task.time = __DST.vclock + initialdelay
    end
    return asCancelable(task)
end

-- 对应 DST 的调度器：TheSim:GetRectOnScreen / 实体任务等无关项在预览中为安全空转
function Widget:Cancel()
    self.dead = true
end

function Widget:StartUpdating()
    if not self.updating then
        self.updating = true
        __DST.updaters[#__DST.updaters + 1] = self
    end
end
function Widget:StopUpdating()
    self.updating = false
    for i, w in ipairs(__DST.updaters) do
        if w == self then table.remove(__DST.updaters, i); break end
    end
end

function Widget:IsUpdating() return self.updating end

function Widget:OnUpdate(dt) return true end

-- ------------------------------------------------------------
-- 焦点
-- ------------------------------------------------------------
function Widget:SetFocus()
    self.focus = true
    if self.OnGainFocus then pcall(self.OnGainFocus, self) end
end

function Widget:OnGainFocus()
    if self.ongainfocus then pcall(self.ongainfocus, self:IsEnabled()) end
end

function Widget:OnLoseFocus()
    self.focus = false
    if self.onlosefocus then pcall(self.onlosefocus, self:IsEnabled()) end
end

function Widget:LoseFocus()
    if self.OnLoseFocus then self:OnLoseFocus() else self.focus = false end
end

function Widget:SetOnGainFocus(fn) self.ongainfocus = fn end
function Widget:SetOnLoseFocus(fn) self.onlosefocus = fn end
function Widget:SetFocusChangeDir() end
function Widget:ClearFocusDirs() end
function Widget:OnFocusMove(dir, down) return false end
function Widget:GetDeepestFocus()
    if self.focus then return self end
    for _, c in ipairs(self.childList) do
        local f = c:GetDeepestFocus()
        if f then return f end
    end
    return nil
end

-- ------------------------------------------------------------
-- 点击 / 控制
-- ------------------------------------------------------------
function Widget:SetOnClick(fn) self.onclick = fn end
function Widget:GetOnClick() return self.onclick end

function Widget:OnControl(control, down) return false end
function Widget:OnRawKey(key, down) return false end
function Widget:OnMouseButton(button, down, x, y) return false end

function Widget:SetFadeAlpha(a, skipChildren)
    self.fadeAlpha = a
    if not skipChildren then
        for _, c in ipairs(self.childList) do
            if c.can_fade_alpha then c:SetFadeAlpha(a) end
        end
    end
end

function Widget:UpdateWhilePaused() end
function Widget:FollowMouse() end
function Widget:StopFollowMouse() end
function Widget:GetHelpText() return "" end

function Widget:GetWidgetByName(name)
    for _, c in ipairs(self.childList) do
        if c.name == name then return c end
        local r = c.GetWidgetByName and c:GetWidgetByName(name)
        if r then return r end
    end
    return nil
end

-- ------------------------------------------------------------
-- 补间动画（按虚拟时钟真实插值）
-- ------------------------------------------------------------
function Widget:MoveTo(from, to, time, fn)
    __DST.tween(time, 0, 1, easing.inOutQuad, function(k)
        self:SetPosition(from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k, from.z + (to.z - from.z) * k)
    end, fn)
end

function Widget:ScaleTo(from, to, time, fn)
    __DST.tween(time, 0, 1, easing.inOutQuad, function(k)
        self:SetScale(from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k, from.z + (to.z - from.z) * k)
    end, fn)
end

function Widget:RotateTo(from, to, time, fn, infinite)
    __DST.tween(time, from, to, easing.inOutQuad, function(v) self:SetRotation(v) end, fn)
end

function Widget:TintTo(from, to, time, fn)
    __DST.tween(time, 0, 1, easing.inOutQuad, function(k)
        local t = self.tint
        if t then
            t[1] = from[1] + (to[1] - from[1]) * k
            t[2] = from[2] + (to[2] - from[2]) * k
            t[3] = from[3] + (to[3] - from[3]) * k
            t[4] = from[4] + (to[4] - from[4]) * k
        end
    end, fn)
end

return Widget
