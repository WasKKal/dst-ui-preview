-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- vision_dst.lua — DST widget 树 → 绘制列表（draw list）
--
-- 与 Roblox 版 vision 输出同构的 JSON 绘制列表，供 render_hires /
-- render_html 渲染。坐标转换：DST 为 y 向上、锚点=父级参考点；
-- 绘制列表为屏幕坐标（左上原点、y 向下）。
--
-- 锚点语义（与引擎一致）：
--   Widget:SetHAnchor/SetVAnchor —— 位置相对【父级】的哪个边/中心计量
--     ANCHOR_LEFT/TOP   → 父级左/上边（坐标沿正向累加）
--     ANCHOR_MIDDLE     → 父级中心
--     ANCHOR_RIGHT/BOTTOM → 父级右/下边（坐标沿负向累加）
--   Image:SetHRegPoint/SetVRegPoint、Text:SetHAlign/SetVAlign
--     —— 内容盒的哪个点落在位置上（默认 MIDDLE=居中）
-- ============================================================

Vision = {}
Vision.viewport = __DST.viewport

local function hAnchorName(a)
    if a == ANCHOR_MIDDLE then return "Center" end
    if a == ANCHOR_RIGHT then return "Right" end
    return "Left" -- ANCHOR_LEFT(1)
end

local function vAnchorName(a)
    if a == ANCHOR_MIDDLE then return "Center" end
    if a == ANCHOR_BOTTOM then return "Bottom" end
    return "Top" -- ANCHOR_TOP(1)
end

function __DST.hasTexture(ref)
    return ref ~= nil and __DST.texmap[ref] ~= nil
end

-- 按绘制顺序（先序）遍历，产出每个 widget 的屏幕矩形
-- 返回 { {widget=, x=, y=, w=, h=, visible=}, ... }
function Vision.rects()
    local out = {}
    local root = __DST.root
    if not root then return out end
    local VW = Vision.viewport.w
    local VH = Vision.viewport.h

    local function walk(w, px, py, psize, psx, psy, parentVis)
        if w.dead then return end
        local vis = parentVis and (w.shown ~= false)
        local hf = __DST.anchorFactor(w.hanchor)
        local vf = __DST.anchorFactor(w.vanchor)
        local offx = (hf - 0.5) * psize.w
        local offy = (0.5 - vf) * psize.h
        local wx = px + psx * (offx + (w.pos and w.pos.x or 0))
        local wy = py + psy * (offy + (w.pos and w.pos.y or 0))
        local smx, smy = __DST.scalemodeFactor(w)
        local sx = psx * (w.scale and w.scale.x or 1) * smx
        local sy = psy * (w.scale and w.scale.y or 1) * smy
        local cw = (w.contentSize and w.contentSize.w) or 0
        local ch = (w.contentSize and w.contentSize.h) or 0

        if vis then
            local ww = cw * math.abs(sx)
            local wh = ch * math.abs(sy)
            if ww > 0.01 and wh > 0.01 then
                local bx0, by0, bx1, by1 = __DST.contentRect(w, wx, wy, ww, wh)
                out[#out + 1] = {
                    widget = w,
                    x = bx0 + VW / 2,
                    y = VH / 2 - by1,
                    w = bx1 - bx0,
                    h = by1 - by0,
                    visible = true,
                }
            end
        end

        if not vis then return end
        for _, c in ipairs(w.childList or {}) do
            walk(c, wx, wy, { w = cw, h = ch }, sx, sy, vis)
        end
    end

    walk(root, 0, 0, { w = VW, h = VH }, 1, 1, true)
    return out
end

-- 生成单个 widget 的绘制操作（无内容返回 nil）
local function buildOp(w)
    local cls = w.className or "Widget"
    local VW = Vision.viewport.w
    local VH = Vision.viewport.h
    local wx, wy, sx, sy = __DST.worldTransform(w)
    local cw = (w.contentSize and w.contentSize.w) or 0
    local ch = (w.contentSize and w.contentSize.h) or 0
    local ww = cw * math.abs(sx)
    local wh = ch * math.abs(sy)
    if ww <= 0.01 and wh <= 0.01 and cls ~= "Text" and cls ~= "TextEdit" then
        return nil
    end

    local op = {
        class = cls,
        name = w.name or "",
        rotation = w.rotation or 0,
        zindex = 1,
    }

    -- 位置/尺寸（内容盒 → 屏幕坐标）
    if cls == "Text" or cls == "TextEdit" then
        -- 文本：无显式区域时由渲染器测量（textAutoBox），先给锚点
        op.x = wx + VW / 2
        op.y = VH / 2 - wy
        op.w = ww
        op.h = wh
    else
        local bx0, by0, bx1, by1 = __DST.contentRect(w, wx, wy, ww, wh)
        op.x = bx0 + VW / 2
        op.y = VH / 2 - by1
        op.w = bx1 - bx0
        op.h = by1 - by0
    end

    if cls == "Image" or cls == "ThreeSlice" then
        local ref = nil
        if cls == "Image" then
            if not w.texture then return nil end
            ref = (w.atlas or "") .. ":" .. w.texture
        else
            ref = (w.atlas or "") .. ":" .. (w.tex_mid or w.tex_beg or "")
        end
        op.image = true
        op.imageRef = ref
        op.texLabel = ref
        op.placeholder = not __DST.hasTexture(ref)
        local t = w.tint or { 1, 1, 1, 1 }
        op.imageColor = { r = t[1] or 1, g = t[2] or 1, b = t[3] or 1 }
        op.imageAlpha = t[4] or 1
        if op.placeholder then __DST.stats.placeholders = __DST.stats.placeholders + 1 end
    elseif cls == "UIAnim" then
        op.image = true
        op.placeholder = true
        op.texLabel = (w.bank or "?") .. ":" .. (w.build or "?")
        op.imageColor = { r = 0.55, g = 0.55, b = 0.55 }
        op.imageAlpha = 0.35
        __DST.stats.placeholders = __DST.stats.placeholders + 1
    elseif cls == "Text" or cls == "TextEdit" then
        local txt = w.string or ""
        if txt == "" then return nil end
        local c = w.colour or { 1, 1, 1, 1 }
        op.text = txt
        op.textColor = { r = c[1] or 1, g = c[2] or 1, b = c[3] or 1 }
        op.textAlpha = c[4] or 1
        op.textSize = w.size or 30
        op.font = w.font or DEFAULTFONT
        op.xa = hAnchorName(w.halign)
        op.ya = vAnchorName(w.valign)
        op.textAutoBox = (w.region == nil)
        op.wrapped = w.wordwrap and true or false
        if type(op.font) == "string" and op.font:find("outline") then
            op.textStroke = { r = 0.12, g = 0.12, b = 0.12, a = 0.95 }
        end
    end

    return op
end

-- 构建绘制列表（先序：父先于子，子绘制在父之上）
function Vision.buildDrawList()
    local ops = {}
    local seq = 0
    local root = __DST.root
    if not root then return ops end

    local function walk(w)
        if w.dead then return end
        if w.shown ~= false then
            local op = buildOp(w)
            if op then
                seq = seq + 1
                op.seq = seq
                op.zindex = seq
                ops[#ops + 1] = op
            end
            for _, c in ipairs(w.childList or {}) do
                walk(c)
            end
        end
    end

    walk(root)
    return ops
end

-- 统计信息（供报告）
function Vision.stats()
    local rects = Vision.rects()
    local byClass = {}
    for _, r in ipairs(rects) do
        local c = r.widget.className or "Widget"
        byClass[c] = (byClass[c] or 0) + 1
    end
    return { total = #rects, byClass = byClass }
end

return Vision
