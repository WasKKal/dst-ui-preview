-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- widgets/image.lua — Image（预览 mock）
--
-- 纹理尺寸解析顺序：
--   1) --textures 提供的图集登记表（atlas:tex -> 像素尺寸）
--   2) 默认尺寸（--default-tex-size，默认 100x100）
-- 没有纹理时渲染为占位块（渲染器画出纹理名），便于定位。
-- ============================================================

local function texSize(atlas, tex)
    if not atlas or not tex then return nil end
    local key = tostring(atlas) .. ":" .. tostring(tex)
    local e = __DST.texmap[key]
    if e then return e.w, e.h end
    return nil
end

Image = Class(Widget, function(self, atlas, tex, default_tex)
    Widget._ctor(self, "Image")
    self.className = "Image"

    self.atlas = nil
    self.texture = nil
    self.default_tex = default_tex
    self.tint = { 1, 1, 1, 1 }
    self.explicitSize = nil
    self.effect = nil
    self.blendmode = nil
    self.uvmode = nil
    self.uvscale = nil
    self.mouseovertex = nil
    self.disabledtex = nil
    self.alpharange = nil

    if atlas and tex then
        self:SetTexture(atlas, tex, default_tex)
    end
end)

function Image:__tostring()
    return string.format("%s - %s:%s", self.name, self.atlas or "", self.texture or "")
end

function Image:SetTexture(atlas, tex, default_tex)
    assert(atlas ~= nil and tex ~= nil, "Image:SetTexture 需要 atlas 与 tex")
    self.atlas = tostring(atlas)
    self.texture = tostring(tex)
    self.default_tex = default_tex
    local w, h = texSize(self.atlas, self.texture)
    if not w and default_tex then
        w, h = texSize(self.atlas, tostring(default_tex))
    end
    if not w then
        w, h = __DST.defaultTexSize.w, __DST.defaultTexSize.h
    end
    self.contentSize.w = w
    self.contentSize.h = h
    __DST.stats.images = __DST.stats.images + 1
end

function Image:SetSize(w, h)
    if type(w) == "number" then
        self.explicitSize = { w = w, h = h or w }
    else
        self.explicitSize = { w = w[1], h = w[2] }
    end
    self.contentSize.w = self.explicitSize.w
    self.contentSize.h = self.explicitSize.h
end

function Image:GetSize()
    return self.contentSize.w, self.contentSize.h
end

function Image:GetScaledSize()
    local w, h = self:GetSize()
    local sx = self:GetWorldScale()
    return w * sx.x, h * sx.y
end

function Image:ScaleToSize(w, h)
    local w0, h0 = self:GetSize()
    if w0 > 0 and h0 > 0 then
        self:SetScale(w / w0, h / h0, 1)
    end
end

function Image:ScaleToSizeIgnoreParent(w, h)
    self:ScaleToSize(w, h)
end

function Image:SetTint(r, g, b, a)
    if type(r) == "number" then
        self.tint = { r, g or 1, b or 1, a or 1 }
    else
        self.tint = { r[1], r[2], r[3], r[4] }
    end
end

function Image:SetAlphaRange(min, max) self.alpharange = { min, max } end
function Image:SetEffect(f) self.effect = f end
function Image:SetEffectParams() end
function Image:SetEffectParams2() end
function Image:EnableEffectParams() end
function Image:EnableEffectParams2() end
function Image:SetBlendMode(m) self.blendmode = m end
function Image:SetUVScale(x, y) self.uvscale = { x, y } end
function Image:SetUVMode(m) self.uvmode = m end
function Image:SetRadiusForRayTraces() end

function Image:SetMouseOverTexture(atlas, tex)
    self.atlas = tostring(atlas)
    self.mouseovertex = tostring(tex)
end

function Image:SetDisabledTexture(atlas, tex)
    self.atlas = tostring(atlas)
    self.disabledtex = tostring(tex)
end

function Image:SetVRegPoint(a) self.vreg = a end
function Image:SetHRegPoint(a) self.hreg = a end

function Image:SetFadeAlpha(a, skipChildren)
    if not self.can_fade_alpha then return end
    if self.tint then
        self.tint[4] = (self.tint[4] or 1) * a
    end
    Widget.SetFadeAlpha(self, a, skipChildren)
end

function Image:OnMouseOver()
    if self.enabled and self.mouseovertex and self.atlas then
        self:SetTexture(self.atlas, self.mouseovertex)
    end
    Widget.OnMouseOver(self)
end

function Image:OnMouseOut()
    if self.enabled and self.mouseovertex and self.atlas and self.texture then
        self:SetTexture(self.atlas, self.texture)
    end
    Widget.OnMouseOut(self)
end

function Image:OnEnable()
    if self.mouse_over_self and self.atlas and self.texture then
        self:SetTexture(self.atlas, self.texture)
    end
end

function Image:OnDisable()
    if self.disabledtex and self.atlas then
        self:SetTexture(self.atlas, self.disabledtex)
    end
end

return Image
