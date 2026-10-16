-- ============================================================
-- widgets/button.lua — Button 基类（预览 mock）
-- ImageButton / AnimButton 的基类：持有 .text 子控件与点击回调。
-- ============================================================

Button = Class(Widget, function(self)
    Widget._ctor(self, "BUTTON")
    self.className = "Button"

    self.font = NEWFONT
    self.fontdisabled = NEWFONT

    self.textcolour = { 0, 0, 0, 1 }
    self.textfocuscolour = { 0, 0, 0, 1 }
    self.textdisabledcolour = { 0, 0, 0, 1 }
    self.textselectedcolour = { 0, 0, 0, 1 }

    self.text = self:AddChild(Text(self.font, 40))
    self.text:SetVAlign(ANCHOR_MIDDLE)
    self.text:SetColour(self.textcolour)
    self.text:Hide()

    self.clickoffset = Vector3(0, -3, 0)
    self.selected = false
    self.control = CONTROL_ACCEPT
    self.mouseonly = false
    self.help_message = ""
end)

function Button:SetControl(ctrl)
    if ctrl == CONTROL_PRIMARY then
        self.control = CONTROL_ACCEPT
    elseif ctrl then
        self.control = ctrl
    end
    self.mouseonly = ctrl == CONTROL_PRIMARY
end

-- 点击派发：down 记录按下并偏移，up 复位并触发 onclick
function Button:OnControl(control, down)
    if Widget.OnControl(self, control, down) then return true end
    if not self:IsEnabled() or not self.focus then return false end
    if self:IsSelected() and not self.AllowOnControlWhenSelected then return false end

    if control == self.control then
        if down then
            if not self.down then
                self.o_pos = self:GetLocalPosition()
                if self.move_on_click ~= false then
                    self:SetPosition(self.o_pos + self.clickoffset)
                end
                self.down = true
                if self.ondown then pcall(self.ondown) end
            end
        else
            if self.down then
                self.down = false
                self:ResetPreClickPosition()
                if self.onclick then pcall(self.onclick) end
            end
        end
        return true
    end
    return false
end

function Button:OnUpdate(dt)
    if self.down and self.whiledown then pcall(self.whiledown) end
end

function Button:OnGainFocus()
    Widget.OnGainFocus(self)
    if self:IsEnabled() and not self:IsSelected() then
        if self.text then self.text:SetColour(self.textfocuscolour) end
    end
    if self.ongainfocus then pcall(self.ongainfocus, self:IsEnabled()) end
end

function Button:ResetPreClickPosition()
    if self.o_pos then
        self:SetPosition(self.o_pos)
        self.o_pos = nil
    end
end

function Button:OnLoseFocus()
    Widget.OnLoseFocus(self)
    if self.down then
        self.down = false
        self:ResetPreClickPosition()
        self:StopUpdating()
    end
    if not (self:IsDisabledState() or self:IsSelected()) then
        if self.text then self.text:SetColour(self.textcolour) end
    end
    if self.onlosefocus then pcall(self.onlosefocus, self:IsEnabled()) end
end

function Button:OnEnable()
    if not self:IsSelected() then
        if self.text then self.text:SetFont(self.font) end
        if self:IsFocusedState() then self:OnGainFocus() else self:OnLoseFocus() end
    end
end

function Button:OnDisable()
    if self.down then
        self.down = false
        self:ResetPreClickPosition()
        self:StopUpdating()
    end
    if not self:IsSelected() and self.text then
        self.text:SetColour(self.textdisabledcolour)
        self.text:SetFont(self.fontdisabled)
    end
end

function Button:Select()
    self.selected = true
    if self.OnSelect then pcall(self.OnSelect, self) end
end

function Button:Unselect()
    self.selected = false
    if self.OnUnselect then pcall(self.OnUnselect, self) end
end

function Button:IsSelected() return self.selected end
function Button:IsDisabledState() return not self:IsEnabled() end
function Button:IsFocusedState() return self.focus and self:IsEnabled() and not self:IsSelected() end
function Button:IsNormalState() return self:IsEnabled() and not (self.focus and self:IsEnabled()) and not self:IsSelected() end

function Button:OnSelect()
    if self.down and not self.AllowOnControlWhenSelected then
        self.down = false
        self:ResetPreClickPosition()
        self:StopUpdating()
    end
    if self.text then self.text:SetColour(self.textselectedcolour) end
    if self.onselect then pcall(self.onselect) end
end

function Button:OnUnselect()
    if self:IsDisabledState() then self:OnDisable() else self:OnEnable() end
    if self.onunselect then pcall(self.onunselect) end
end

function Button:SetOnClick(fn) self.onclick = fn end
function Button:SetOnSelect(fn) self.onselect = fn end
function Button:SetOnUnSelect(fn) self.onunselect = fn end
function Button:SetOnUnselect(fn) self.onunselect = fn end
function Button:SetOnDown(fn) self.ondown = fn end
function Button:SetWhileDown(fn) self.whiledown = fn end

function Button:SetFont(font)
    self.font = font
    if not self:IsDisabledState() then
        if self.text then self.text:SetFont(font) end
    end
end

function Button:SetDisabledFont(font)
    self.fontdisabled = font
    if self:IsDisabledState() and self.text then self.text:SetFont(font) end
end

function Button:SetTextColour(r, g, b, a)
    if type(r) == "number" then self.textcolour = { r, g, b, a } else self.textcolour = r end
    if self:IsNormalState() and self.text then self.text:SetColour(self.textcolour) end
end

function Button:SetTextFocusColour(r, g, b, a)
    if type(r) == "number" then self.textfocuscolour = { r, g, b, a } else self.textfocuscolour = r end
    if self:IsFocusedState() and self.text then self.text:SetColour(self.textfocuscolour) end
end

function Button:SetTextDisabledColour(r, g, b, a)
    if type(r) == "number" then self.textdisabledcolour = { r, g, b, a } else self.textdisabledcolour = r end
    if self:IsDisabledState() and self.text then self.text:SetColour(self.textdisabledcolour) end
end

function Button:SetTextSelectedColour(r, g, b, a)
    if type(r) == "number" then self.textselectedcolour = { r, g, b, a } else self.textselectedcolour = r end
    if self:IsSelected() and self.text then self.text:SetColour(self.textselectedcolour) end
end

function Button:SetTextSize(sz)
    self.size = sz
    if self.text then self.text:SetSize(sz) end
end

function Button:GetText()
    return self.text and self.text:GetString() or ""
end

function Button:SetText(msg, dropShadow, dropShadowOffset)
    if not self.text then return end
    if msg then
        self.text:SetString(msg)
        self.text:Show()
        if self:IsDisabledState() then
            self.text:SetColour(self.textdisabledcolour)
        else
            self.text:SetColour(self.textcolour)
        end
    else
        self.text:Hide()
    end
end

function Button:SetHelpTextMessage(str) self.help_message = str end

function Button:GetHelpText() return self.help_message end

return Button
