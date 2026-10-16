-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- widgets/menu.lua — Menu（预览 mock）
-- 纵向/横向排列的按钮列表；每项一个 ImageButton（含 .text 标签）。
-- ============================================================

local menu_styles = {
    small = { atlas = "images/ui.xml", normal = "button_small.tex",
        focus = "button_small_over.tex", disabled = "button_small_disabled.tex" },
    carny_long = { atlas = "images/global_redux.xml", normal = "button_carny_long_normal.tex",
        focus = "button_carny_long_hover.tex", disabled = "button_carny_long_disabled.tex" },
    tabs = { atlas = "images/frontend_redux.xml", normal = "list_tabs_normal.tex",
        selected = "list_tabs_selected.tex" },
}

Menu = Class(Widget, function(self, menuitems, offset, horizontal, style, wrap, text_size)
    Widget._ctor(self, "MENU")
    self.className = "Menu"
    self.offset = offset or 40
    self.style = style
    self.textSize = text_size
    self.items = {}
    self.horizontal = horizontal
    self.wrap_focus = wrap
    self.last_focused_index = 1

    if menuitems ~= nil then
        for _, v in ipairs(menuitems) do
            if v.widget then
                self:AddCustomItem(v.widget, v.offset)
            else
                self:AddItem(v.text, v.cb, v.offset, v.style, nil, v.control)
            end
        end
    end
end)

function Menu:AddCustomItem(widget, offset)
    local pos = Vector3(0, 0, 0)
    if self.horizontal then
        pos.x = pos.x + self.offset * #self.items
    else
        pos.y = pos.y + self.offset * #self.items
    end
    if offset then pos = pos + offset end
    self:AddChild(widget)
    widget:SetPosition(pos)
    table.insert(self.items, widget)
    return widget
end

function Menu:AddItem(text, cb, offset, style, size, control)
    local pos = Vector3(0, 0, 0)
    if self.horizontal then
        pos.x = pos.x + self.offset * #self.items
    else
        pos.y = pos.y + self.offset * #self.items
    end
    if offset then pos = pos + offset end

    style = style or self.style
    local button
    if style == "small" then
        local s = menu_styles.small
        button = self:AddChild(ImageButton(s.atlas, s.normal, s.focus, s.disabled, nil, nil, { 1, 1 }, { 0, 0 }))
        button.image:SetScale(1.1)
        button.text:SetPosition(2, -2)
        button:SetFont(BUTTONFONT)
    elseif style == "carny_long" then
        local s = menu_styles.carny_long
        button = self:AddChild(ImageButton(s.atlas, s.normal, s.focus, s.disabled, nil, nil, { .7, .7 }, { 0, 0 }))
        button:SetFont(CHATFONT)
    elseif style == "tabs" then
        local s = menu_styles.tabs
        button = self:AddChild(ImageButton(s.atlas, s.normal, nil, nil, nil, s.selected, { .7, .7 }, { 0, 4 }))
        button.scale_on_focus = false
        button:SetFont(CHATFONT)
    elseif style == "none" then
        button = self:AddChild(Button())
        button:SetFont(BUTTONFONT)
    else
        button = self:AddChild(ImageButton())
        button:SetFont(NEWFONT)
    end
    button:SetPosition(pos)
    if button.text then button.text:SetColour(0, 0, 0, 1) end
    button:SetOnClick(cb)
    if size == nil then
        size = self.textSize or 40
    end
    button:SetTextSize(size)
    button:SetText(text)

    table.insert(self.items, button)
    return button
end

function Menu:SetVRegPoint(valign)
    local pos = Vector3(0, 0, 0)
    if valign == ANCHOR_MIDDLE then
        pos = Vector3(0, (#self.items - 1) * -0.5, 0)
    elseif valign == ANCHOR_BOTTOM then
        pos = Vector3(0, (#self.items - 1) * -1, 0)
    end
    for i, v in ipairs(self.items) do
        v:SetVAlign(valign)
        v:SetPosition(pos)
        pos.y = pos.y + self.offset
    end
end

function Menu:SetHRegPoint(halign)
    local pos = Vector3(0, 0, 0)
    if halign == ANCHOR_MIDDLE then
        pos = Vector3(self.offset * (#self.items - 1) * -0.5, 0, 0)
    elseif halign == ANCHOR_RIGHT then
        pos = Vector3(self.offset * (#self.items - 1) * -1, 0, 0)
    end
    for _, v in ipairs(self.items) do
        v:SetPosition(pos)
        pos.x = pos.x + self.offset
    end
end

function Menu:SetTextSize(size)
    self.textSize = size
    for _, v in ipairs(self.items) do
        v:SetTextSize(size)
    end
end

function Menu:Clear()
    for _, v in ipairs(self.items) do
        v:Kill()
    end
    self.items = {}
end

function Menu:GetNumberOfItems() return #self.items end

function Menu:GetSize()
    if self.items[1] and self.items[1].GetSize then
        local w, h = self.items[1]:GetSize()
        local height = #self.items * h + self.offset * #self.items
        return w, height
    end
    return nil, nil
end

function Menu:EditItem(num, text, text_size, cb)
    local i = self.items[num]
    if not i then return end
    if text then i:SetText(text) end
    if text_size then i:SetTextSize(text_size) end
    if cb then i:SetOnClick(cb) end
end

function Menu:DisableItem(num)
    if self.items[num] then self.items[num]:Disable() end
end

function Menu:EnableItem(num)
    if self.items[num] then self.items[num]:Enable() end
end

function Menu:UnselectAll()
    for _, v in ipairs(self.items) do v:Unselect() end
end

function Menu:AutoSpaceByText(spacing)
    local x = 0
    for _, v in ipairs(self.items) do
        local w, h = 0, 0
        if v.text and #v.text:GetString() > 0 then
            w, h = v.text:GetRegionSize()
        end
        local len = self.horizontal and w or h
        x = x + len * .5
        local pos = v:GetPosition()
        if self.horizontal then pos.x = x else pos.y = x end
        v:SetPosition(pos)
        x = x + len * .5 + spacing
    end
    return math.max(0, x - spacing)
end

function Menu:RestoreFocusTo(last_focus_widget)
    self:Enable()
    for _, v in ipairs(self.items) do
        if v == last_focus_widget then v:SetFocus() else v:OnLoseFocus() end
    end
end

function Menu:SetMenuIndex(index) self.last_focused_index = index end
function Menu:SetFocus(index)
    index = index or self.last_focused_index or 1
    if self.items[index] then self.items[index]:SetFocus() end
end

return Menu
