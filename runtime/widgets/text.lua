-- ============================================================
-- widgets/text.lua — Text（预览 mock）
--
-- 真实引擎的 TextWidget 由 C++ 测量文字；预览用 Lua 侧宽度估算器
-- （按字形的经验宽度表），用于 GetRegionSize / 截断 / 自动缩字号。
-- 绘制列表交给 Python 渲染器用真实字体测量（textAutoBox），
-- 因此估算误差只影响「依赖测量的布局代码」，不影响最终字形。
-- ============================================================

local function utf8len(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

local function utf8sub(s, i, j)
    local starts = {}
    local n = 0
    for p = 1, #s do
        local b = s:byte(p)
        if b < 0x80 or b >= 0xC0 then n = n + 1; starts[n] = p end
    end
    i = math.max(i or 1, 1)
    j = math.min(j or n, n)
    if i > j then return "" end
    local e = starts[j] - 1
    local nextStart = starts[j + 1]
    if nextStart then e = nextStart - 1 else e = #s end
    return s:sub(starts[i], e)
end

-- 经验宽度表（相对字号的倍数）
local NARROW = { i = 1, l = 1, j = 1, t = 1, f = 1, r = 1, ["."] = 1, [","] = 1,
    ["'"] = 1, [" "] = 1, ["!"] = 1, [":"] = 1, [";"] = 1, ["|"] = 1, ["("] = 1, [")"] = 1,
    ["["] = 1, ["]"] = 1, ["I"] = 1 }
local WIDE = { m = 1, w = 1, M = 1, W = 1, ["@"] = 1 }

local function charWidth(ch, size)
    local o = ch:byte()
    if o >= 0x80 then return size * 1.0 end          -- CJK / 全角
    if NARROW[ch] then return size * 0.30 end
    if WIDE[ch] then return size * 0.85 end
    return size * 0.52
end

local function measureWidth(str, size)
    local w = 0
    for i = 1, #str do
        w = w + charWidth(str:sub(i, i), size)
    end
    return w
end

local function lineCount(str)
    local n = 1
    for _ in str:gmatch("\n") do n = n + 1 end
    return n
end

Text = Class(Widget, function(self, font, size, text, colour)
    Widget._ctor(self, "Text")
    self.className = "Text"

    self.font = font or DEFAULTFONT
    self:SetSize(size or 30)
    self:SetColour(colour or { 1, 1, 1, 1 })
    self.halign = ANCHOR_MIDDLE
    self.valign = ANCHOR_MIDDLE
    self.region = nil            -- 显式区域（SetRegionSize）
    self.wordwrap = false
    self.string = ""
    __DST.stats.texts = __DST.stats.texts + 1

    if text ~= nil then
        self:SetString(text)
    end
end)

function Text:__tostring()
    return string.format("%s - %s", self.name, self.string or "")
end

function Text:SetColour(r, g, b, a)
    if type(r) == "number" then
        self.colour = { r, g or 1, b or 1, a or 1 }
    else
        self.colour = { r[1], r[2], r[3], r[4] }
    end
end

function Text:GetColour()
    return { self.colour[1], self.colour[2], self.colour[3], self.colour[4] }
end

function Text:SetFont(font) self.font = font end
function Text:GetFont() return self.font end

function Text:SetSize(sz)
    self.size = sz
    self.contentSize.w = self.region and self.region.w or 0
    self.contentSize.h = self.region and self.region.h or 0
end

function Text:GetSize() return self.size end

function Text:SetString(str)
    self.string = str ~= nil and tostring(str) or ""
end

function Text:GetString() return self.string or "" end

function Text:SetRegionSize(w, h)
    self.region = { w = w, h = h }
    self.contentSize.w = w
    self.contentSize.h = h
end

function Text:GetRegionSize()
    if self.region then return self.region.w, self.region.h end
    local size = self.size or 30
    local lines = lineCount(self:GetString())
    local w = 0
    for line in (self:GetString() .. "\n"):gmatch("([^\n]*)\n") do
        w = math.max(w, measureWidth(line, size))
    end
    return w, size * 1.25 * lines
end

function Text:ResetRegionSize()
    self.region = nil
    self.contentSize.w = 0
    self.contentSize.h = 0
end

function Text:SetHAlign(a) self.halign = a; self.hreg = a end
function Text:SetVAlign(a) self.valign = a; self.vreg = a end

function Text:EnableWordWrap(enable) self.wordwrap = enable and true or false end
function Text:EnableWhitespaceWrap(enable) self.whitespacewrap = enable and true or false end
function Text:SetHorizontalSqueeze(s) self.squeeze = s end

-- 按 maxwidth / maxchars 截断（估算宽度驱动；ellipses 默认 "..."）
function Text:SetTruncatedString(str, maxwidth, maxchars, ellipses)
    str = str ~= nil and str:match("^[^\n\v\f\r]*") or ""
    if type(ellipses) ~= "string" then
        ellipses = ellipses and "..." or ""
    end
    local size = self.size or 30
    local cut = false
    if maxchars ~= nil and utf8len(str) > maxchars then
        str = utf8sub(str, 1, maxchars)
        cut = true
    end
    if maxwidth ~= nil then
        -- 预留省略号宽度，避免削完仍溢出
        local limit = cut and (maxwidth - measureWidth(ellipses, size)) or maxwidth
        while utf8len(str) > 1 and measureWidth(str, size) > limit do
            str = utf8sub(str, 1, utf8len(str) - 1)
            cut = true
        end
    end
    -- 只有真正截断才追加省略号（未截断时原样显示）
    if #str == 0 then
        self:SetString("")
    else
        self:SetString(str .. (cut and ellipses or ""))
    end
    return not cut
end

-- 多行截断（简化实现：逐行截断到 maxlines）
function Text:SetMultilineTruncatedString(str, maxlines, maxwidth, maxcharsperline, ellipses)
    if str == nil or #str <= 0 then
        self:SetString("")
        return 1
    end
    maxlines = maxlines or 1
    local ell = (ellipses == true and "...") or (type(ellipses) == "string" and ellipses) or ""
    local lines = {}
    for line in (str .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    local out = {}
    local n = math.min(#lines, maxlines)
    local dropped = #lines > maxlines          -- 有行被丢弃也算截断
    local size = self.size or 30
    for i = 1, n do
        local line = lines[i]
        local cut = false
        if maxcharsperline and utf8len(line) > maxcharsperline then
            line = utf8sub(line, 1, maxcharsperline)
            cut = true
        end
        if maxwidth then
            local limit = cut and (maxwidth - measureWidth(ell, size)) or maxwidth
            while utf8len(line) > 1 and measureWidth(line, size) > limit do
                line = utf8sub(line, 1, utf8len(line) - 1)
                cut = true
            end
        end
        if cut and i == n then line = line .. ell end
        out[#out + 1] = line
    end
    if dropped and #ell > 0 and #out > 0 then
        local last = out[#out]
        if last:sub(-#ell) ~= ell then out[#out] = last .. ell end
    end
    self:SetString(table.concat(out, "\n"))
    return #out
end

-- 自动缩字号到 max_width（允许放大时可超过原字号）
function Text:SetAutoSizingString(str, max_width, allow_scaling_up)
    self:SetString(str)
    self:ResetRegionSize()
    self.target_font_size = self:GetSize()
    local w = select(1, self:GetRegionSize())
    local scale = allow_scaling_up and (max_width / w) or math.min(1, max_width / w)
    if scale ~= 1 then
        self:SetSize(self.target_font_size * scale)
    end
end

function Text:RemoveAutoSizing()
    if self.target_font_size then
        self:SetSize(self.target_font_size)
        self.target_font_size = nil
    end
end

function Text:UpdateOriginalSize() self.original_size = self.size end

function Text:SetAlpha(a) self.colour[4] = a end
function Text:UpdateAlpha(a) self.colour[4] = a end

function Text:SetFadeAlpha(a, skipChildren)
    if not self.can_fade_alpha then return end
    self.colour[4] = (self.colour[4] or 1) * a
    Widget.SetFadeAlpha(self, a, skipChildren)
end

return Text
