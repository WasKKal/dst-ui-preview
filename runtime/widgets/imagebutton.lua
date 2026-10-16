-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- widgets/imagebutton.lua — ImageButton（预览 mock）
-- 内部结构：self.image（Image 子控件，显示各状态纹理）
--           + 继承自 Button 的 self.text（标签）
-- 焦点/按下时切换纹理，点击（OnControl up）触发 onclick。
-- ============================================================

ImageButton = Class(Button, function(self, atlas, normal, focus, disabled, down, selected, scale, offset)
    Button._ctor(self, "ImageButton")
    self.className = "ImageButton"

    self.image = self:AddChild(Image())
    self.image:MoveToBack()

    self.scale_on_focus = true
    self.move_on_click = true
    self.focus_scale = { 1.2, 1.2, 1.2 }
    self.normal_scale = { 1, 1, 1 }
    self.focus_sound = nil
    self.hover_overlay = nil
    self.size_x = nil
    self.size_y = nil

    self:SetTextures(atlas, normal, focus, disabled, down, selected, scale, offset)
end)

function ImageButton:SetTextures(atlas, normal, focus, disabled, down, selected, image_scale, image_offset)
    local default_textures = false
    if not atlas then
        atlas = "images/frontend.xml"
        normal = normal or "button_long.tex"
        focus = focus or "button_long_halfshadow.tex"
        disabled = disabled or "button_long_disabled.tex"
        down = down or "button_long_halfshadow.tex"
        selected = selected or "button_long_disabled.tex"
        default_textures = true
    end

    self.atlas = atlas
    self.image_normal = normal
    self.image_focus = focus or normal
    self.image_disabled = disabled or normal
    self.image_down = down or self.image_focus
    self.image_selected = selected or disabled
    self.has_image_down = down ~= nil

    local scale = { .7, .7 }
    local offset = { 3, -7 }
    if not default_textures then
        scale = { 1, 1 }
        offset = { 0, 0 }
    end
    scale = image_scale or self.normal_scale or scale
    offset = image_offset or offset
    self.image_scale = scale
    self.image_offset = offset

    if self.image then
        self.image:SetPosition(offset[1], offset[2])
        self.image:SetScale(scale[1], scale[2] or scale[1])
        if normal then
            self.image:SetTexture(atlas, normal)
        end
        self.contentSize.w = self.image.contentSize.w * (scale[2] or scale[1])
        self.contentSize.h = self.image.contentSize.h * (scale[2] or scale[1])
    end
end

function ImageButton:ForceImageSize(x, y)
    self.size_x = x
    self.size_y = y
    if self.image then
        self.image:ScaleToSize(x, y)
        self.contentSize.w = x
        self.contentSize.h = y
    end
end

function ImageButton:UseFocusOverlay(focus_selected_texture)
    if not self.hover_overlay and self.image then
        self.hover_overlay = self.image:AddChild(Image())
    end
    if self.hover_overlay then
        self.hover_overlay:SetTexture(self.atlas, focus_selected_texture)
        self.hover_overlay:Hide()
    end
end

function ImageButton:OnGainFocus()
    Button.OnGainFocus(self)
    if self.hover_overlay then self.hover_overlay:Show() end
    if self:IsSelected() or self:IsDisabledState() then return end
    if self:IsEnabled() and self.image then
        self.image:SetTexture(self.atlas, self.image_focus)
        if self.size_x and self.size_y then
            self.image:ScaleToSize(self.size_x, self.size_y)
        end
        if not self.ignore_standard_scaling and self.image_focus == self.image_normal
            and self.scale_on_focus and self.focus_scale then
            self.image:SetScale(self.focus_scale[1], self.focus_scale[2], self.focus_scale[3])
        end
        if self.imagefocuscolour then
            self.image:SetTint(self.imagefocuscolour[1], self.imagefocuscolour[2],
                self.imagefocuscolour[3], self.imagefocuscolour[4])
        end
    end
end

function ImageButton:OnLoseFocus()
    Button.OnLoseFocus(self)
    if self.hover_overlay then self.hover_overlay:Hide() end
    if self:IsSelected() or self:IsDisabledState() then return end
    if self:IsEnabled() and self.image then
        self.image:SetTexture(self.atlas, self.image_normal)
        if self.size_x and self.size_y then
            self.image:ScaleToSize(self.size_x, self.size_y)
        end
    end
    if not self.ignore_standard_scaling and self.image_focus == self.image_normal
        and self.scale_on_focus and self.normal_scale then
        self.image:SetScale(self.normal_scale[1], self.normal_scale[2], self.normal_scale[3])
    end
    if self.imagenormalcolour then
        self.image:SetTint(self.imagenormalcolour[1], self.imagenormalcolour[2],
            self.imagenormalcolour[3], self.imagenormalcolour[4])
    end
end

function ImageButton:OnControl(control, down)
    if Widget.OnControl(self, control, down) then return true end
    if not self:IsEnabled() or not self.focus then return end
    if self:IsSelected() and not self.AllowOnControlWhenSelected then return false end

    if control == self.control then
        if down then
            if not self.down then
                if self.has_image_down and self.image then
                    self.image:SetTexture(self.atlas, self.image_down)
                    if self.size_x and self.size_y then
                        self.image:ScaleToSize(self.size_x, self.size_y)
                    end
                end
                self.o_pos = self:GetLocalPosition()
                if self.move_on_click ~= false then
                    self:SetPosition(self.o_pos + self.clickoffset)
                end
                self.down = true
                if self.ondown then pcall(self.ondown) end
            end
        else
            if self.down then
                if self.has_image_down and self.image then
                    self.image:SetTexture(self.atlas, self.image_focus)
                    if self.size_x and self.size_y then
                        self.image:ScaleToSize(self.size_x, self.size_y)
                    end
                end
                self.down = false
                self:ResetPreClickPosition()
                if self.onclick then pcall(self.onclick) end
            end
        end
        return true
    end
    return false
end

function ImageButton:OnDisable()
    Button.OnDisable(self)
    if self:IsSelected() then return end
    if self.image then
        self.image:SetTexture(self.atlas, self.image_disabled)
        if self.imagedisabledcolour then
            self.image:SetTint(self.imagedisabledcolour[1], self.imagedisabledcolour[2],
                self.imagedisabledcolour[3], self.imagedisabledcolour[4])
        end
        if self.size_x and self.size_y then
            self.image:ScaleToSize(self.size_x, self.size_y)
        end
    end
end

function ImageButton:OnSelect()
    Button.OnSelect(self)
    if self.image_selected and self.image then
        self.image:SetTexture(self.atlas, self.image_selected)
    end
    if self.imageselectedcolour and self.image then
        self.image:SetTint(self.imageselectedcolour[1], self.imageselectedcolour[2],
            self.imageselectedcolour[3], self.imageselectedcolour[4])
    end
end

function ImageButton:GetSize()
    if self.image then return self.image:GetSize() end
    return self.contentSize.w, self.contentSize.h
end

function ImageButton:SetFocusScale(scaleX, scaleY, scaleZ)
    if type(scaleX) == "number" then
        self.focus_scale = { scaleX, scaleY, scaleZ or 1 }
    else
        self.focus_scale = scaleX
    end
    if self.scale_on_focus and self:IsFocusedState() and self.image then
        self.image:SetScale(self.focus_scale[1], self.focus_scale[2], self.focus_scale[3])
    end
end

function ImageButton:SetNormalScale(scaleX, scaleY, scaleZ)
    if type(scaleX) == "number" then
        self.normal_scale = { scaleX, scaleY, scaleZ or 1 }
    else
        self.normal_scale = scaleX
    end
    if not (self.scale_on_focus and self:IsFocusedState()) and self.image then
        self.image:SetScale(self.normal_scale[1], self.normal_scale[2], self.normal_scale[3])
    end
end

function ImageButton:SetImageNormalColour(r, g, b, a)
    if type(r) == "number" then self.imagenormalcolour = { r, g, b, a } else self.imagenormalcolour = r end
    if self:IsNormalState() and self.image then
        self.image:SetTint(self.imagenormalcolour[1], self.imagenormalcolour[2],
            self.imagenormalcolour[3], self.imagenormalcolour[4])
    end
end

function ImageButton:SetImageFocusColour(r, g, b, a)
    if type(r) == "number" then self.imagefocuscolour = { r, g, b, a } else self.imagefocuscolour = r end
    if self:IsFocusedState() and self.image then
        self.image:SetTint(self.imagefocuscolour[1], self.imagefocuscolour[2],
            self.imagefocuscolour[3], self.imagefocuscolour[4])
    end
end

function ImageButton:SetImageDisabledColour(r, g, b, a)
    if type(r) == "number" then self.imagedisabledcolour = { r, g, b, a } else self.imagedisabledcolour = r end
    if self:IsDisabledState() and self.image then
        self.image:SetTint(self.imagedisabledcolour[1], self.imagedisabledcolour[2],
            self.imagedisabledcolour[3], self.imagedisabledcolour[4])
    end
end

function ImageButton:SetImageSelectedColour(r, g, b, a)
    if type(r) == "number" then self.imageselectedcolour = { r, g, b, a } else self.imageselectedcolour = r end
    if self:IsSelected() and self.image then
        self.image:SetTint(self.imageselectedcolour[1], self.imageselectedcolour[2],
            self.imageselectedcolour[3], self.imageselectedcolour[4])
    end
end

function ImageButton:SetFocusSound(sound) self.focus_sound = sound end

return ImageButton
