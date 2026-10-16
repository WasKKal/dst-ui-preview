-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- widgets/screen.lua — Screen（预览 mock）
-- Screen 继承 Widget；harness 渲染的根就是一个 Screen 实例。
-- ============================================================

Screen = Class(Widget, function(self, name)
    Widget._ctor(self, name or "screen")
    self.className = "Screen"
    self.is_screen = true
    self.handlers = {}
    self.default_focus = nil
end)

-- 兼容旧 mod 的全局调用方式
Screen_ctor = function(self, name)
    Widget._ctor(self, name)
end

function Screen:OnCreate() end
function Screen:GetHelpText() return "" end

function Screen:OnDestroy()
    self:Kill()
end

function Screen:OnUpdate(dt) return true end
function Screen:OnBecomeInactive() end

function Screen:OnBecomeActive()
    if self.last_focus then
        self.last_focus:SetFocus()
    elseif self.default_focus then
        self.default_focus:SetFocus()
    end
end

function Screen:AddEventHandler(event, fn)
    self.handlers[event] = self.handlers[event] or {}
    self.handlers[event][fn] = true
    return fn
end

function Screen:RemoveEventHandler(event, fn)
    if self.handlers[event] then
        self.handlers[event][fn] = nil
    end
end

function Screen:HandleEvent(type, ...)
    local handlers = self.handlers[type]
    if handlers then
        for fn in pairs(handlers) do
            pcall(fn, ...)
        end
    end
end

function Screen:SetDefaultFocus() end

function Screen:OnControl(control, down) return false end
function Screen:OnRawKey(key, down) return false end

return Screen
