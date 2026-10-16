-- ============================================================
-- widgets/spinner.lua — Spinner（预览 mock）
-- 默认 150x40；左右箭头 ImageButton + 中央 Text/TextEdit。
-- ============================================================

local default_width = 150
local default_height = 40

local spinner_images = {
    arrow_normal = "spin_arrow.tex",
    arrow_over = "spin_arrow_over.tex",
    arrow_disabled = "spin_arrow_disabled.tex",
    arrow_down = "spin_arrow_down.tex",
    bg_middle = "spinner_short.tex",
    bg_middle_focus = "spinner_short_focus.tex",
    bg_middle_changing = "spinner_short_changing.tex",
    bg_end = "spinner_end.tex",
    bg_end_focus = "spinner_end_focus.tex",
    bg_end_changing = "spinner_end_changing.tex",
}

Spinner = Class(Widget, function(self, options, width, height, textinfo, editable, atlas, textures, lean, textwidth, textheight)
    Widget._ctor(self, "SPINNER")
    self.className = "Spinner"

    textures = textures or spinner_images
    atlas = atlas or "images/frontend.xml"
    textinfo = textinfo or { font = BUTTONFONT, size = 30 }

    self.width = width or default_width
    self.height = height or default_height
    self.lean = lean
    self.options = options or { { text = "", data = nil } }
    self.selectedIndex = 1
    self.editable = editable or false
    self.textsize = { width = textwidth or self.width, height = textheight or self.height }
    self.textcolour = { 1, 1, 1, 1 }
    self.control_prev = CONTROL_PREVVALUE
    self.control_next = CONTROL_NEXTVALUE
    self.auto_shrink_text = false
    self.contentSize.w = self.width
    self.contentSize.h = self.height

    if self.lean then
        self.background = self:AddChild(Image(atlas, textures.bg_middle_focus))
        self.background:ScaleToSize(self.width, self.height)
        self.background:SetTint(1, 1, 1, 0)
        self.leftimage = self:AddChild(ImageButton(atlas, textures.arrow_left_normal or textures.arrow_normal,
            textures.arrow_left_over or textures.arrow_over, textures.arrow_left_disabled or textures.arrow_disabled,
            textures.arrow_left_down or textures.arrow_down, nil, { 1, 1 }, { 0, 0 }))
        self.rightimage = self:AddChild(ImageButton(atlas, textures.arrow_right_normal or textures.arrow_normal,
            textures.arrow_right_over or textures.arrow_over, textures.arrow_right_disabled or textures.arrow_disabled,
            textures.arrow_right_down or textures.arrow_down, nil, { 1, 1 }, { 0, 0 }))
    else
        self.background = self:AddChild(ThreeSlice(atlas, textures.bg_end, textures.bg_middle))
        self.background:Flow(self.width, self.height, true)
        self.leftimage = self:AddChild(ImageButton(atlas, textures.arrow_normal, textures.arrow_over,
            textures.arrow_disabled, textures.arrow_down, nil, { 1, 1 }, { 0, 0 }))
        self.rightimage = self:AddChild(ImageButton(atlas, textures.arrow_normal, textures.arrow_over,
            textures.arrow_disabled, textures.arrow_down, nil, { 1, 1 }, { 0, 0 }))
    end
    self.leftimage.silent = true
    self.rightimage.silent = true
    self.leftimage:SetOnClick(function() self:Prev(true) end)
    self.rightimage:SetOnClick(function() self:Next(true) end)

    -- 箭头缩放到与高度匹配
    local aw, ah = self.leftimage:GetSize()
    self.arrow_scale = ah > 0 and (self.height / ah) or 1
    self.leftimage:SetScale(self.arrow_scale, self.arrow_scale, 1)
    self.rightimage:SetScale(self.arrow_scale, self.arrow_scale, 1)

    self.fgimage = self:AddChild(Image())
    if self.editable then
        self.text = self:AddChild(TextEdit(textinfo.font, textinfo.size))
    else
        self.text = self:AddChild(Text(textinfo.font, textinfo.size))
    end
    if self.lean then
        self.text:SetPosition(2, 0)
    end

    self:Layout()
    self:SetSelectedIndex(1)
end)

function Spinner:Layout()
    local aw = self.rightimage:GetSize() * self.arrow_scale
    self.rightimage:SetPosition(self.width / 2 - aw / 2, 0, 0)
    self.leftimage:SetPosition(-self.width / 2 + aw / 2, 0, 0)
end

function Spinner:UpdateText(msg)
    local _msg = tostring(msg)
    local width = self.textsize.width - 50
    local chars = width / 4
    if chars > 5 and width > 10 then
        if self.auto_shrink_text then
            self.text:SetMultilineTruncatedString(_msg, 1, width, nil, nil, true)
        else
            self.text:SetTruncatedString(_msg, width, chars, true)
        end
    else
        self.text:SetString(_msg)
    end
end

function Spinner:SetTextSize(sz)
    self.text:SetSize(sz)
end

function Spinner:SetTextColour(r, g, b, a)
    if type(r) == "number" then self.textcolour = { r, g, b, a } else self.textcolour = r end
    self.text:SetColour(self.textcolour)
end

function Spinner:SetTextHAlign(align) self.text:SetHAlign(align) end
function Spinner:SetTextVAlign(align) self.text:SetVAlign(align) end
function Spinner:GetText() return self.text:GetString() end

function Spinner:MinIndex() return 1 end
function Spinner:MaxIndex() return #self.options end

function Spinner:GetSelectedText()
    local o = self.options[self.selectedIndex]
    if not o then return "" end
    return o.text or "", o.colour
end

function Spinner:GetSelectedImage()
    local o = self.options[self.selectedIndex]
    return o and o.image
end

function Spinner:SetSelectedIndex(idx)
    self.selectedIndex = math.max(self:MinIndex(), math.min(self:MaxIndex(), idx))
    local txt, colour = self:GetSelectedText()
    self:UpdateText(txt)
    if colour then
        self:SetTextColour(colour[1], colour[2], colour[3], colour[4])
    else
        self:SetTextColour(self.textcolour[1], self.textcolour[2], self.textcolour[3], self.textcolour[4])
    end
end

function Spinner:GetSelectedIndex() return self.selectedIndex end

function Spinner:SetSelected(data)
    for k, v in ipairs(self.options) do
        if v.data == data then
            self:SetSelectedIndex(k)
            return
        end
    end
end

function Spinner:Next(silent)
    self:SetSelectedIndex(self:GetSelectedIndex() + 1)
    if not silent and self.changed then self:Changed() end
end

function Spinner:Prev(silent)
    self:SetSelectedIndex(self:GetSelectedIndex() - 1)
    if not silent and self.changed then self:Changed() end
end

function Spinner:Changed() end

function Spinner:OnControl(control, down)
    if Widget.OnControl(self, control, down) then return true end
    if down then
        if control == self.control_prev then
            self:Prev()
            return true
        elseif control == self.control_next then
            self:Next()
            return true
        end
    end
    return false
end

function Spinner:Enable()
    Widget.Enable(self)
    self.leftimage:Enable()
    self.rightimage:Enable()
end

function Spinner:Disable()
    Widget.Disable(self)
    self.leftimage:Disable()
    self.rightimage:Disable()
end

return Spinner
