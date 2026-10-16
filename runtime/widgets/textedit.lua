-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- widgets/textedit.lua — TextEdit（预览 mock）
-- 继承 Text；录入态由 OnControl(CONTROL_ACCEPT) 切换，
-- 模拟焦点图/文字色变化（无真实文本输入设备，交互以点击为主）。
-- ============================================================

TextEdit = Class(Text, function(self, font, size, text, colour)
    Text._ctor(self, font, size, text, colour)
    self.className = "TextEdit"

    self.limit = nil
    self.regionlimit = false
    self.editing = false
    self.editing_enter_down = false
    self.allow_newline = false
    self.enable_accept_control = true
    self.force_edit = false
    self.validchars = nil
    self.invalidchars = nil
    self.format = nil

    self.idle_text_color = { 0, 0, 0, 1 }
    self.edit_text_color = { 0, 0, 0, 1 }
    self:SetColour(self.idle_text_color[1], self.idle_text_color[2],
        self.idle_text_color[3], self.idle_text_color[4])
end)

function TextEdit:SetForceEdit(force) self.force_edit = force end

function TextEdit:SetAllowNewline(allow_newline)
    self.allow_newline = allow_newline
    self.enable_accept_control = not (allow_newline and self.editing)
end

function TextEdit:SetEditing(editing)
    if editing and not self.editing then
        self.editing = true
        self:SetFocus()
        self:SetColour(self.edit_text_color[1], self.edit_text_color[2],
            self.edit_text_color[3], self.edit_text_color[4])
    elseif not editing and self.editing then
        self.editing = false
        self:SetColour(self.idle_text_color[1], self.idle_text_color[2],
            self.idle_text_color[3], self.idle_text_color[4])
    end
end

function TextEdit:ValidateChar(text)
    local invalidchars = string.char(8, 22, 27)
    if not self.allow_newline then
        invalidchars = invalidchars .. string.char(10, 13)
    end
    return (self.validchars == nil or string.find(self.validchars, text, 1, true))
        and (self.invalidchars == nil or not string.find(self.invalidchars, text, 1, true))
        and not string.find(invalidchars, text, 1, true)
end

function TextEdit:ValidatedString(str)
    local res = ""
    for i = 1, #str do
        local char = str:sub(i, i)
        if self:ValidateChar(char) then res = res .. char end
    end
    return res
end

function TextEdit:SetFormat(format)
    self.format = format
    if format ~= nil then self:SetTextLengthLimit(#format) end
end

function TextEdit:SetCharacterLimit(n) self.limit = n end
function TextEdit:SetTextLengthLimit(n) self.limit = n end
function TextEdit:SetPassword() end
function TextEdit:SetValidChars(chars) self.validchars = chars end
function TextEdit:SetInvalidChars(chars) self.invalidchars = chars end
function TextEdit:SetIdleTextColour(r, g, b, a)
    if type(r) == "number" then self.idle_text_color = { r, g, b, a } else self.idle_text_color = r end
    if not self.editing then
        self:SetColour(self.idle_text_color[1], self.idle_text_color[2],
            self.idle_text_color[3], self.idle_text_color[4])
    end
end

function TextEdit:SetEditTextColour(r, g, b, a)
    if type(r) == "number" then self.edit_text_color = { r, g, b, a } else self.edit_text_color = r end
    if self.editing then
        self:SetColour(self.edit_text_color[1], self.edit_text_color[2],
            self.edit_text_color[3], self.edit_text_color[4])
    end
end

function TextEdit:SetFocusedImage() end
function TextEdit:OnTextInput(text) return true end
function TextEdit:OnProcess()
    if self.ontextentered then self:ontextentered(self:GetString()) end
    return true
end
function TextEdit:SetOnTextEntered(fn) self.ontextentered = fn end
function TextEdit:SetTextPrompt(prompt, colour)
    self.prompt_text = prompt
    self.prompt_colour = colour
end
function TextEdit:EnableWordWrap(v) self.wrapped = v and true or false end
function TextEdit:EnableWhitespaceWrap(v) self.whitespace_wrap = v end
function TextEdit:EnableScrollEditWindow(v) self.scroll_edit_window = v end
function TextEdit:EnableRegionSizeLimit(v) self.regionlimit = v and true or false end
function TextEdit:EnableWordPrediction(...) end
function TextEdit:SetNextTextEditWidget(w) self.nextTextEditWidget = w end

function TextEdit:OnControl(control, down)
    if not self:IsEnabled() then return false end
    if Widget.OnControl(self, control, down) then return true end
    if self.enable_accept_control and not down and control == CONTROL_ACCEPT then
        self:SetEditing(not self.editing)
        return true
    end
    return false
end

function TextEdit:OnGainFocus()
    Widget.OnGainFocus(self)
end

function TextEdit:OnLoseFocus()
    Widget.OnLoseFocus(self)
end

return TextEdit
