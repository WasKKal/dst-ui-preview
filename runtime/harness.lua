-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- harness.lua — 无头 harness：实例化屏幕、推进虚拟时钟、
--               派发点击、捕获动画帧、输出 JSON 报告。
-- ============================================================

Harness = {}
Harness.clicks = {}
Harness.className = nil       -- 入口类名（--class 指定）
Harness.ownerKind = "stub"    -- stub | none

function Harness.ownerStub()
    return __DST.universalStub("owner")
end

-- 把 require 的返回值变成屏幕实例
-- 支持：类（可调用表）/ 工厂函数 / 类名字表
function Harness.instantiate(value, owner)
    if value == nil then return nil end
    local t = type(value)

    if t == "function" then
        local ok, inst = pcall(value, owner)
        if not ok then
            __DST.error("入口函数执行失败: " .. tostring(inst))
            return nil
        end
        if type(inst) == "table" then return inst end
        return nil
    end

    if t == "table" then
        local mt = getmetatable(value)
        if mt and mt.__call then
            -- 类：直接实例化
            local ok, inst = pcall(value, owner)
            if not ok then
                __DST.error("入口类实例化失败: " .. tostring(inst))
                return nil
            end
            return inst
        end
        -- 类名字表：取 --class 指定的，或第一个类
        if Harness.className and value[Harness.className] then
            return Harness.instantiate(value[Harness.className], owner)
        end
        for _, v in pairs(value) do
            local vmt = getmetatable(v)
            if type(v) == "table" and vmt and vmt.__call then
                return Harness.instantiate(v, owner)
            end
        end
        -- 普通表：可能本身就是实例（极少见）
        return value
    end
    return nil
end

-- 默认入口：require 用户模块 → 实例化 → 设为根
function Harness.runEntry(modname)
    local ok, err = pcall(function()
        local entry = require(modname)
        local inst = Harness.instantiate(entry, Harness.ownerStub())
        if inst then __DST.root = inst end
    end)
    if not ok then
        __DST.error("入口失败: " .. tostring(err))
    end
    if __DST.root then
        print(string.format("[harness] 根屏幕: %s (%s)，子控件 %d",
            __DST.root.name, __DST.root.className, #(__DST.root.childList or {})))
    else
        __DST.error("未能确定根屏幕（模块未返回类/函数，且未调用 TheFrontEnd:ShowScreen）")
    end
end

-- ------------------------------------------------------------
-- 虚拟时钟推进 + 动画帧捕获
-- ------------------------------------------------------------
Harness.capture = { active = false, interval = 0.1, max = 120, frames = {}, next = 0 }

function Harness.startCapture(interval, max)
    Harness.capture.active = true
    Harness.capture.interval = interval or 0.1
    Harness.capture.max = max or 120
    Harness.capture.frames = {}
    Harness.capture.next = 0
end

function Harness.stopCapture()
    Harness.capture.active = false
end

function Harness.captureTick()
    local c = Harness.capture
    if not c.active then return end
    if #c.frames >= c.max then return end
    if __DST.vclock + 1e-9 >= c.next then
        c.frames[#c.frames + 1] = { t = __DST.vclock, draws = Vision.buildDrawList() }
        c.next = __DST.vclock + c.interval
    end
end

function Harness.pump(seconds, dt)
    seconds = seconds or 0
    dt = dt or 1 / 30
    local steps = math.max(1, math.ceil(seconds / dt))
    for _ = 1, steps do
        __DST.pump(dt)
        Harness.captureTick()
    end
end

-- ------------------------------------------------------------
-- 命中测试与点击派发
-- ------------------------------------------------------------
function Harness.hitTest(x, y)
    local list = Vision.rects()
    for i = #list, 1, -1 do
        local e = list[i]
        local w = e.widget
        if e.visible and (w.clickable or w.onclick or w.className == "ImageButton") then
            if x >= e.x and x <= e.x + e.w and y >= e.y and y <= e.y + e.h then
                return w, e
            end
        end
    end
    return nil
end

-- 找最近的可点击控件（含 0 尺寸的），用于点击未命中时给出「忘了 SetSize」提示
local function nearestClickable(x, y)
    local best, bestd = nil, nil
    local VW, VH = Vision.viewport.w, Vision.viewport.h
    local function walk(w)
        if w.dead or w.shown == false then return end
        if w.clickable or w.onclick or w.className == "ImageButton" or w.className == "Button" then
            local wx, wy = __DST.worldTransform(w)
            local sx, sy = wx + VW / 2, VH / 2 - wy
            local d = math.sqrt((sx - x) ^ 2 + (sy - y) ^ 2)
            if not bestd or d < bestd then best, bestd = w, d end
        end
        for _, c in ipairs(w.childList or {}) do walk(c) end
    end
    if __DST.root and __DST.root ~= nil then walk(__DST.root) end
    return best, bestd
end

-- 模拟一次鼠标点击：命中 → 获得焦点 → 按下/抬起（触发 onclick）
function Harness.click(x, y)
    local w, e = Harness.hitTest(x, y)
    if not w then
        print(string.format("[harness] 点击 (%d, %d)：未命中", x, y))
        local near, d = nearestClickable(x, y)
        if near and d and d < 60 then
            local cw = (near.contentSize and near.contentSize.w) or 0
            local ch = (near.contentSize and near.contentSize.h) or 0
            print(string.format(
                "[harness] 提示：附近有可点击控件 %s（%s），尺寸 %.0fx%.0f，距点击点 %.0fpx —— "
                .. "尺寸为 0 时游戏中同样点不到，记得 SetSize() 或改用 ImageButton(带纹理尺寸)",
                tostring(near.name), near.className, cw, ch, d))
        end
        Harness.clicks[#Harness.clicks + 1] = { x = x, y = y, hit = false }
        return false
    end
    print(string.format("[harness] 点击 (%d, %d) -> %s [%s] %.0fx%.0f",
        x, y, tostring(w.name), w.className, e.w, e.h))
    Harness.clicks[#Harness.clicks + 1] = {
        x = x, y = y, hit = true, name = w.name, class = w.className,
    }

    w:SetFocus()
    w:OnControl(CONTROL_ACCEPT, true)
    Harness.pump(1 / 30)
    w:OnControl(CONTROL_ACCEPT, false)
    Harness.pump(1 / 30)

    -- 非 Button 体系的自定义 onclick（Button 已由 OnControl 触发）
    if w.onclick and w.className ~= "Button" and w.className ~= "ImageButton" then
        pcall(w.onclick)
        Harness.pump(1 / 30)
    end
    return true
end

-- 悬停（获得/失去焦点，触发 hover 纹理切换）
function Harness.hover(x, y)
    local w = Harness.hitTest(x, y)
    if w then
        w:SetFocus()
    end
    return w
end

-- ------------------------------------------------------------
-- 报告
-- ------------------------------------------------------------
function Harness.summary()
    local st = Vision.stats()
    print(string.format("[harness] widget %d（%s）| 时钟 %.2fs | 点击 %d | 警告 %d | 错误 %d",
        __DST.stats.widgets, __DST.json(st.byClass, 0), __DST.vclock,
        #Harness.clicks, #__DST.warnings, #__DST.errors))
end

function Harness.emitReport()
    local rep = {
        ok = (#__DST.errors == 0),
        viewport = { w = __DST.viewport.w, h = __DST.viewport.h },
        draws = Vision.buildDrawList(),
        widgets = {
            count = __DST.stats.widgets,
            images = __DST.stats.images,
            texts = __DST.stats.texts,
            placeholders = __DST.stats.placeholders,
            byClass = Vision.stats().byClass,
        },
        clicks = Harness.clicks,
        warnings = __DST.warnings,
        errors = __DST.errors,
        checks = __DST.checks or { pass = 0, fail = 0 },
        texmap = __DST.texmap,
        seconds = __DST.vclock,
    }
    if #Harness.capture.frames > 0 then
        rep.frames = Harness.capture.frames
        rep.frameInterval = Harness.capture.interval
    end
    local js = __DST.json(rep, 0)
    if __DST.emit_stdout then
        print("--DSTUI_JSON_BEGIN--")
        print(js)
        print("--DSTUI_JSON_END--")
    else
        print(string.format("[harness] 报告：draws %d | widget %d | 占位 %d | 点击 %d | 警告 %d | 错误 %d",
            #rep.draws, __DST.stats.widgets, __DST.stats.placeholders,
            #Harness.clicks, #__DST.warnings, #__DST.errors))
    end
    __REPORT_JSON = js
end

return Harness
