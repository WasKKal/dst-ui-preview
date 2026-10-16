-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 WasKKal · DST UI Preview
-- ============================================================
-- bootstrap.lua — DST UI 预览运行时 · 全局设施
--
-- 为「无头预览 Don't Starve Together mod UI」提供：
--   · Class（Klei 风格类系统，含未知方法兜底）
--   · Vector3 / ANCHOR_* / SCALEMODE_* / CONTROL_* / *FONT 常量
--   · TheSim / TheInput / TheFrontEnd / ThePlayer 等全局桩
--   · require mock（按 DST 模块名解析 widgets/*）
--   · 虚拟时钟 + 任务队列（DoTaskInTime/DoPeriodicTask）
--   · 补间动画（MoveTo/ScaleTo/RotateTo/TintTo 的真实插值）
--   · Lua 侧 JSON 编码器（供 harness 输出报告）
--
-- 兼容两个运行时：lupa（Lua 5.5）与 luau CLI（共享裸全局环境）。
-- ============================================================

__DST = {
    vclock = 0,
    tasks = {},        -- {time=, period=, fn=, cancelled=}
    updaters = {},     -- StartUpdating 注册的 widget
    tweens = {},       -- 活动补间
    warnings = {},
    errors = {},
    root = nil,        -- 当前屏幕（harness 渲染的根）
    viewport = { w = 1280, h = 720 },
    texmap = {},       -- "atlas:tex" -> {w=, h=}（由驱动注入；无纹理时走占位）
    defaultTexSize = { w = 100, h = 100 },
    stats = { images = 0, texts = 0, widgets = 0, placeholders = 0 },
}

local function warn(msg)
    if #__DST.warnings < 200 then
        __DST.warnings[#__DST.warnings + 1] = tostring(msg)
    end
end
__DST.warn = warn

local function err(msg)
    __DST.errors[#__DST.errors + 1] = tostring(msg)
end
__DST.error = err

-- ------------------------------------------------------------
-- 兼容 shim：unpack / getfenv / string.utf8*
-- ------------------------------------------------------------
unpack = table.unpack or unpack   -- 裸全局：widget 模块按 DST(Lua 5.1) 惯例直接调用 unpack
local unpack = unpack
getfenv = getfenv or function() return _G end
setfenv = setfenv or function() end

local function safeSet(t, k, v)
    if rawget(t, k) == nil then
        pcall(rawset, t, k, v)
    end
end
safeSet(string, "utf8len", function(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end)
safeSet(string, "utf8sub", function(s, i, j)
    local bytes = {}
    local n = 0
    for p = 1, #s do
        local b = s:byte(p)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
        bytes[n] = bytes[n] or {}
        table.insert(bytes[n], p)
    end
    i = math.max(i or 1, 1)
    j = math.min(j or n, n)
    if i > j then return "" end
    return s:sub(bytes[i][1], bytes[j][#bytes[j]])
end)
safeSet(string, "split", function(s, sep)
    sep = sep or " "
    local out = {}
    for piece in tostring(s):gmatch("([^" .. sep .. "]+)") do out[#out + 1] = piece end
    return out
end)
safeSet(table, "typecheckedgetfield", function(t, k, ty)
    local v = t[k]
    if ty and type(v) ~= ty then return nil end
    return v
end)

-- ------------------------------------------------------------
-- Vector3（DST 语义：y 向上，z 朝向观察者）
-- ------------------------------------------------------------
Vector3 = {}                      -- 裸全局（widget 模块按 DST 惯例直接引用 Vector3(...)）
local Vector3 = Vector3           -- 本地别名（本文件内高频使用）
Vector3.__index = Vector3
Vector3.__add = function(a, b) return Vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
Vector3.__sub = function(a, b) return Vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
Vector3.__unm = function(a) return Vector3(-a.x, -a.y, -a.z) end
Vector3.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
Vector3.__tostring = function(a) return string.format("(%g,%g,%g)", a.x, a.y, a.z) end
Vector3.__call = function(_, x, y, z)
    -- 直接建表，切勿再调用 Vector3(...)（那会经 __call 无限递归）
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vector3)
end
function Vector3.new(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vector3)
end
function Vector3:Get() return self.x, self.y, self.z end
function Vector3:GetX() return self.x end
function Vector3:GetY() return self.y end
function Vector3:GetZ() return self.z end
function Vector3:LengthSq() return self.x * self.x + self.y * self.y + self.z * self.z end
function Vector3:Length() return math.sqrt(self:LengthSq()) end
function Vector3:DistSq(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function Vector3:Dist(o) return math.sqrt(self:DistSq(o)) end
setmetatable(Vector3, Vector3)
GLOBAL_Vector3 = Vector3

-- ------------------------------------------------------------
-- 常量（数值与 DST constants.lua 一致）
-- ------------------------------------------------------------
ANCHOR_MIDDLE = 0
ANCHOR_LEFT = 1
ANCHOR_RIGHT = 2
ANCHOR_TOP = 1
ANCHOR_BOTTOM = 2

SCALEMODE_NONE = 0
SCALEMODE_FILLSCREEN = 1
SCALEMODE_PROPORTIONAL = 2
SCALEMODE_FIXEDPROPORTIONAL = 3
SCALEMODE_FIXEDSCREEN_NONDYNAMIC = 4

RESOLUTION_X = 1280
RESOLUTION_Y = 720
MAX_FE_SCALE = 3
MAX_HUD_SCALE = 1.25
TILE_SCALE = 4

-- fonts.lua 的字体别名
DEFAULTFONT = "opensans"
DIALOGFONT = "opensans"
TITLEFONT = "bp100"
UIFONT = "bp50"
BUTTONFONT = "buttonfont"
NEWFONT = "spirequal"
NEWFONT_SMALL = "spirequal_small"
NEWFONT_OUTLINE = "spirequal_outline"
NEWFONT_OUTLINE_SMALL = "spirequal_outline_small"
NUMBERFONT = "stint-ucr"
SMALLNUMBERFONT = "stint-small"
TALKINGFONT = "talkingfont"
CHATFONT = "bellefair"
CHATFONT_OUTLINE = "bellefair_outline"
HEADERFONT = "hammerhead"
BODYTEXTFONT = "stint-ucr"
CODEFONT = "ptmono"

-- 常用 CONTROL_*（完整集见 constants.lua）
CONTROL_PRIMARY = 0
CONTROL_SECONDARY = 1
CONTROL_ATTACK = 2
CONTROL_INSPECT = 3
CONTROL_ACTION = 4
CONTROL_PAUSE = 13
CONTROL_MAP = 14
CONTROL_ACCEPT = 29
CONTROL_CANCEL = 30
CONTROL_SCROLLBACK = 31
CONTROL_SCROLLFWD = 32
CONTROL_PREVVALUE = 33
CONTROL_NEXTVALUE = 34
CONTROL_OPEN_INVENTORY = 45
CONTROL_OPEN_CRAFTING = 46
CONTROL_MENU_BACK = 83
CONTROL_MENU_START = 84
CONTROL_CUSTOM_START = 100

-- 焦点方向（menu.lua 等使用）
MOVE_UP = "up"
MOVE_DOWN = "down"
MOVE_LEFT = "left"
MOVE_RIGHT = "right"

-- TextEdit 原始按键（近似值，仅预览用途）
KEY_ENTER = 40
KEY_TAB = 43
KEY_BACKSPACE = 42
KEY_ESCAPE = 41
KEY_DELETE = 76
KEY_HOME = 74
KEY_END = 77
KEY_LEFT = 80
KEY_RIGHT = 79

-- 菜单/UI 常用色（UICOLOURS 子集，0-1）
UICOLOURS = {
    BLACK = { 0, 0, 0, 1 },
    WHITE = { 1, 1, 1, 1 },
    RED = { 0.6, 0.1, 0.1, 1 },
    BLUE = { 0.2, 0.4, 0.7, 1 },
    GREEN = { 0.2, 0.6, 0.3, 1 },
    GOLD = { 0.9, 0.75, 0.4, 1 },
    GOLD_CLICKABLE = { 0.87, 0.72, 0.45, 1 },
    GOLD_FOCUS = { 1, 0.9, 0.6, 1 },
    GOLD_UNIMPORTANT = { 0.5, 0.45, 0.35, 1 },
    GREY = { 0.5, 0.5, 0.5, 1 },
    DARKGREY = { 0.25, 0.25, 0.25, 1 },
    LIGHTGREY = { 0.75, 0.75, 0.75, 1 },
    EGGSHELL = { 0.9, 0.88, 0.8, 1 },
    SALMON = { 0.9, 0.6, 0.5, 1 },
}

-- ------------------------------------------------------------
-- easing（DST easing.lua 常用子集）
-- ------------------------------------------------------------
easing = {}                    -- 裸全局（widget 的 MoveTo/ScaleTo 等直接引用 easing）
local easing = easing
local function lerp(a, b, t) return a + (b - a) * t end
easing.linear = function(t) return t end
easing.inQuad = function(t) return t * t end
easing.outQuad = function(t) return t * (2 - t) end
easing.inOutQuad = function(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
end
easing.inCubic = function(t) return t * t * t end
easing.outCubic = function(t) t = t - 1; return t * t * t + 1 end
easing.inOutCubic = function(t)
    if t < 0.5 then return 4 * t * t * t end
    return 4 * (t - 1) * (t - 1) * (t - 1) + 1
end
easing.inQuart = function(t) return t * t * t * t end
easing.outQuart = function(t) t = t - 1; return 1 - t * t * t * t end
easing.inOutQuart = function(t)
    if t < 0.5 then return 8 * t * t * t * t end
    return 1 - 8 * (t - 1) * (t - 1) * (t - 1) * (t - 1)
end
easing.inQuint = function(t) return t ^ 5 end
easing.outQuint = function(t) t = t - 1; return 1 + t ^ 5 end
easing.inOutQuint = function(t)
    if t < 0.5 then return 16 * t ^ 5 end
    return 1 + 16 * (t - 1) ^ 5
end
easing.inSine = function(t) return 1 - math.cos(t * math.pi / 2) end
easing.outSine = function(t) return math.sin(t * math.pi / 2) end
easing.inOutSine = function(t) return 0.5 * (1 - math.cos(math.pi * t)) end
easing.inExponential = function(t) return t == 0 and 0 or math.pow(2, 10 * (t - 1)) end
easing.outExponential = function(t) return t == 1 and 1 or 1 - math.pow(2, -10 * t) end
easing.inOutExponential = function(t)
    if t < 0.5 then return 0.5 * math.pow(2, 10 * (2 * t - 1)) end
    return 0.5 * (2 - math.pow(2, -10 * (2 * t - 1)))
end
easing.inCircular = function(t) return 1 - math.sqrt(1 - t * t) end
easing.outCircular = function(t) t = t - 1; return math.sqrt(1 - t * t) end
easing.inOutCircular = function(t)
    if t < 0.5 then return 0.5 * (1 - math.sqrt(1 - 4 * t * t)) end
    return 0.5 * (1 + math.sqrt(1 - (-2 * t + 2) ^ 2))
end
easing.outBounce = function(t)
    if t < 1 / 2.75 then return 7.5625 * t * t
    elseif t < 2 / 2.75 then t = t - 1.5 / 2.75; return 7.5625 * t * t + 0.75
    elseif t < 2.5 / 2.75 then t = t - 2.25 / 2.75; return 7.5625 * t * t + 0.9375
    else t = t - 2.625 / 2.75; return 7.5625 * t * t + 0.984375 end
end
easing.inBack = function(t)
    local s = 1.70158
    return t * t * ((s + 1) * t - s)
end
easing.outBack = function(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end
easing.inOutBack = function(t)
    local s = 1.70158 * 1.525
    if t < 0.5 then return 0.5 * (4 * t * t * ((s + 1) * 2 * t - s)) end
    return 0.5 * ((2 * t - 2) ^ 2 * ((s + 1) * (2 * t - 2) + s) + 2)
end
easing.outElastic = function(t)
    if t == 0 or t == 1 then return t end
    return math.pow(2, -10 * t) * math.sin((t - 0.075) * (2 * math.pi) / 0.3) + 1
end

-- ------------------------------------------------------------
-- 虚拟时钟 / 任务 / 补间
-- ------------------------------------------------------------
function __DST.after(t, fn)
    local task = { time = __DST.vclock + (t or 0), fn = fn }
    __DST.tasks[#__DST.tasks + 1] = task
    return task
end

function __DST.every(t, fn)
    local task = { time = __DST.vclock + (t or 0), period = t or 0, fn = fn }
    __DST.tasks[#__DST.tasks + 1] = task
    return task
end

function __DST.cancelTask(task)
    if task then task.cancelled = true end
end

-- 推进虚拟时钟 dt 秒：跑到期任务 → 更新补间 → 调 StartUpdating 的 OnUpdate
function __DST.pump(dt)
    dt = dt or 1 / 30
    __DST.vclock = __DST.vclock + dt

    -- 到期任务
    local tasks = __DST.tasks
    local i = 1
    while i <= #tasks do
        local t = tasks[i]
        if t.cancelled then
            table.remove(tasks, i)
        elseif t.time <= __DST.vclock then
            if t.period then t.time = t.time + t.period else table.remove(tasks, i) end
            local ok, e = pcall(t.fn)
            if not ok then err("任务回调错误: " .. tostring(e)) end
            if t.period and not t.cancelled then i = i + 1 end
        else
            i = i + 1
        end
    end

    -- 补间
    local tweens = __DST.tweens
    local j = 1
    while j <= #tweens do
        local tw = tweens[j]
        local k = tw.dur > 0 and math.min(1, (__DST.vclock - tw.start) / tw.dur) or 1
        local e = tw.ease and tw.ease(k) or k
        tw.apply(lerp(tw.from, tw.to, e))
        if k >= 1 then
            table.remove(tweens, j)
            if tw.fn then local ok, err2 = pcall(tw.fn); if not ok then err("补间回调: " .. tostring(err2)) end end
        else
            j = j + 1
        end
    end

    -- StartUpdating
    for _, w in ipairs(__DST.updaters) do
        if w.shown and w.OnUpdate then
            local ok, e = pcall(w.OnUpdate, w, dt)
            if not ok then err(w.name .. ":OnUpdate 错误: " .. tostring(e)) end
        end
    end
end

-- 注册补间：apply(v) 把插值结果写回 widget
function __DST.tween(dur, from, to, ease, apply, fn)
    __DST.tweens[#__DST.tweens + 1] = {
        start = __DST.vclock, dur = math.max(dur or 0, 0.0001),
        from = from, to = to, ease = ease or easing.linear, apply = apply, fn = fn,
    }
end

-- ------------------------------------------------------------
-- 实体桩：DST 的每个 widget 背后有一个 entity（ECS）。
-- 预览只需要它「存在且可调用」：已知 API 给出真实行为，
-- 未知的【大写开头】成员记录警告后空转，保证 mod 代码不崩。
-- ------------------------------------------------------------
local function noopEntityMethod(owner, k)
    return function(...)
        warn(string.format("[%s] 未.mock 的实体调用: %s", owner, k))
    end
end

local function makeSubTable(owner, methods)
    local t = {}
    for k, fn in pairs(methods) do t[k] = fn end
    return setmetatable(t, {
        __index = function(_, k)
            if type(k) == "string" and k:match("^%u") then
                return noopEntityMethod(owner .. "." .. tostring(k), k)
            end
            return nil
        end,
    })
end

function __DST.Entity(widget, name)
    local ent = { widget = widget, name = name, tags = {}, listeners = {} }

    local entity = makeSubTable("entity", {
        SetName = function(_, n) ent.name = n end,
        AddUITransform = function() end,
        AddImageWidget = function() end,
        AddTextWidget = function() end,
        AddTextEditWidget = function() end,
        AddAnimState = function() end,
        AddTransform = function() end,
        AddTag = function(_, tag) ent.tags[tag] = true end,
        RemoveTag = function(_, tag) ent.tags[tag] = nil end,
        HasTag = function(_, tag) return ent.tags[tag] == true end,
        SetParent = function() end,
        Hide = function() end,
        Show = function() end,
        IsValid = function() return true end,
        SetClickable = function(_, v) if widget then widget.clickable = v and true or false end end,
        CallPrefabConstructionComplete = function() end,
        MoveToFront = function() if widget then widget:MoveToFront() end end,
        MoveToBack = function() if widget then widget:MoveToBack() end end,
        SetColorParams = function() end,
    })
    ent.entity = entity

    ent.UITransform = makeSubTable("UITransform", {
        SetPosition = function() end, GetPosition = function() return 0, 0, 0 end,
        GetLocalPosition = function() return 0, 0, 0 end,
        GetWorldPosition = function()
            if widget then
                local x, y = __DST.worldTransform(widget)
                return x, y, 0
            end
            return 0, 0, 0
        end,
        SetScale = function() end, GetScale = function() return 1, 1, 1 end,
        GetWorldScale = function() return 1, 1, 1 end,
        SetHAnchor = function() end, SetVAnchor = function() end,
        SetScaleMode = function() end, SetRotation = function() end,
        GetRotation = function() return 0 end, UpdateTransform = function() end,
    })
    ent.ImageWidget = makeSubTable("ImageWidget", {
        SetTexture = function() end, GetSize = function() return 0, 0 end,
        SetSize = function() end, SetTint = function() end, SetHAnchor = function() end,
        SetVAnchor = function() end,
    })
    ent.TextWidget = makeSubTable("TextWidget", {
        SetFont = function() end, SetString = function() end, GetString = function() return "" end,
        SetColour = function() end, SetSize = function() end,
        GetRegionSize = function() return 0, 0 end, SetRegionSize = function() end,
        ResetRegionSize = function() end, SetHAnchor = function() end, SetVAnchor = function() end,
        EnableWordWrap = function() end, ShowEditCursor = function() end,
    })
    ent.TextEditWidget = makeSubTable("TextEditWidget", {
        SetString = function() end, OnTextInput = function() end, OnKeyDown = function() end,
        OnKeyUp = function() end, HasOverflow = function() return false end,
    })
    ent.AnimState = makeSubTable("AnimState", {
        SetBank = function() end, SetBuild = function() end, PlayAnimation = function() end,
        PushAnimation = function() end, SetPercent = function() end, Pause = function() end,
        Resume = function() end, Hide = function() end, Show = function() end,
        SetMultColour = function() end, UsePointFiltering = function() end,
    })
    ent.uianim = { SetBank = function() end, SetBuild = function() end }

    -- 任务（DoTaskInTime / DoPeriodicTask）接入虚拟时钟
    ent.DoTaskInTime = function(_, t, fn)
        return __DST.after(t, fn)
    end
    ent.DoPeriodicTask = function(_, t, fn)
        return __DST.every(t, fn)
    end

    -- 事件（ListenForEvent / PushEvent）
    ent.ListenForEvent = function(_, event, fn, source)
        ent.listeners[event] = ent.listeners[event] or {}
        table.insert(ent.listeners[event], { fn = fn, source = source })
        return fn
    end
    ent.RemoveEventCallback = function(_, event, fn, source)
        local ls = ent.listeners[event]
        if not ls then return end
        for i, e in ipairs(ls) do
            if e.fn == fn then table.remove(ls, i); break end
        end
    end
    ent.PushEvent = function(_, event, ...)
        local ls = ent.listeners[event]
        if ls then
            for _, e in ipairs(ls) do
                pcall(e.fn, ...)
            end
        end
    end

    ent.AddTag = function(_, tag) ent.tags[tag] = true end
    ent.RemoveTag = function(_, tag) ent.tags[tag] = nil end
    ent.HasTag = function(_, tag) return ent.tags[tag] == true end
    ent.Kill = function() end
    ent.IsValid = function() return true end
    ent.DoSimTaskInTime = ent.DoTaskInTime
    ent.DoSimPeriodicTask = ent.DoPeriodicTask

    return setmetatable(ent, {
        __index = function(t, k)
            if type(k) == "string" and k:match("^%u") then
                return noopEntityMethod("entity:" .. k, k)
            end
            return nil
        end,
    })
end

-- ------------------------------------------------------------
-- Class（Klei 风格；未知【大写开头】的成员调用记警告后安全返回）
-- ------------------------------------------------------------
local function makeNoopIndex(owner_name)
    return function(t, k)
        if type(k) == "string" and k:match("^%u") then
            return function(self, ...)
                warn(string.format("[%s] 未.mock 的调用: %s()", owner_name, k))
            end
        end
        return nil
    end
end

function Class(parent, ctor)
    if ctor == nil then
        if type(parent) == "function" then
            ctor, parent = parent, nil
        else
            ctor = function() end
        end
    end
    assert(type(ctor) == "function", "Class 需要函数构造函数")
    local cls = {}
    cls.__index = cls
    cls._ctor = ctor
    cls._base = parent
    -- 注意：__index（父类链）与 __call（实例化）必须在【同一个】元表里，
    -- 否则后一个 setmetatable 会覆盖前一个，子类实例将找不到父类方法。
    local base_index = parent or makeNoopIndex("Widget")
    return setmetatable(cls, {
        __index = base_index,
        __call = function(c, ...)
            local self = setmetatable({}, c)
            local ok, e = pcall(ctor, self, ...)
            if not ok then error("构造 " .. tostring(self.name or "?") .. " 失败: " .. tostring(e), 0) end
            __DST.stats.widgets = __DST.stats.widgets + 1
            return self
        end,
    })
end

-- ------------------------------------------------------------
-- require mock：按 DST 模块名解析
--   __DST_MODS[name] 可以是：
--     · 源码字符串（--mod 注册的用户模块）→ load 执行并缓存返回值
--     · 函数/表（驱动注册的内置 widget 类）→ 直接返回
-- ------------------------------------------------------------
__DST_MODS = {}
local MODCACHE = {}
local MODULE_HINT = "（预览工具内置 widgets/widget,image,text,button,imagebutton,screen,threeslice,spinner,menu,textedit,uianim）"
local REQUIRE_LOAD = load or loadstring
function require(name)
    local n = tostring(name)
    if MODCACHE[n] ~= nil then return MODCACHE[n] end
    local v = __DST_MODS[n]
    if v == nil then v = __DST_MODS[n:gsub("^widgets/", "")] end
    if v == nil then
        error("require 未支持的模块: " .. n .. " " .. MODULE_HINT, 2)
    end
    local r
    if type(v) == "string" then
        local f, err = REQUIRE_LOAD(v, "@" .. n)
        if not f then error("加载模块 " .. n .. " 失败: " .. tostring(err), 2) end
        r = f()
        if r == nil then r = true end
    else
        r = v
    end
    MODCACHE[n] = r
    MODCACHE[n:gsub("^widgets/", "")] = r
    return r
end

-- ------------------------------------------------------------
-- 通用「万能桩」：任何访问/调用都返回自身（用于 ThePlayer 等）
-- ------------------------------------------------------------
local function universalStub(name)
    local s
    s = setmetatable({}, {
        __index = function(_, k) return s end,
        __call = function() return s end,
        __tostring = function() return "stub:" .. tostring(name) end,
        __concat = function(a, b) return tostring(a) .. tostring(b) end,
        __len = function() return 0 end,
    })
    return s
end
__DST.universalStub = universalStub

ThePlayer = universalStub("ThePlayer")
TheWorld = universalStub("TheWorld")
TheNet = universalStub("TheNet")
TheShard = universalStub("TheShard")

-- ------------------------------------------------------------
-- TheSim / TheInput / TheFrontEnd
-- ------------------------------------------------------------
TheSim = {
    GetRealTime = function() return __DST.vclock end,
    GetTick = function() return math.floor(__DST.vclock * 30) end,
    GetTime = function() return __DST.vclock end,
    SetUIRoot = function() end,
    GetUIRoot = function() return nil end,
    GetScreenSize = function() return __DST.viewport.w, __DST.viewport.h end,
    GetWindowSize = function() return __DST.viewport.w, __DST.viewport.h end,
    GetPlatform = function() return "DSTPREVIEW" end,
    IsDST = function() return true end,
    IsConsole = function() return false end,
    GetClipboardData = function() return "" end,
    StartStat = function() end,
    StopStat = function() end,
    SetProfilerEnabled = function() end,
}

TheInput = {
    ControllerAttached = function() return false end,
    GetControllerID = function() return 0 end,
    GetScreenPosition = function() return 0, 0 end,
    IsMouseAttached = function() return true end,
    EnableMouseControls = function() end,
    EnableDebugToggle = function() end,
    GetLocalizedControl = function() return "" end,
    IsPasteKey = function() return false end,
    AddMoveHandler = function() return { Remove = function() end } end,
    AddKeyHandler = function() return { Remove = function() end } end,
    AddMouseButtonHandler = function() return { Remove = function() end } end,
    AddTextInputHandler = function() return { Remove = function() end } end,
    RemoveMoveHandler = function() end,
}

TheFrontEnd = {
    isprimary = true,
    GetSound = function() return { PlaySound = function() end, PlaySoundWithParams = function() end } end,
    GetFadeLevel = function() return 0 end,
    Fade = function() end,
    GetActiveScreen = function() return __DST.root end,
    ShowScreen = function(self, screen) __DST.root = screen; return screen end,
    PushScreen = function(self, screen) __DST.root = screen; return screen end,
    PopScreen = function() end,
    ClearScreens = function() end,
    SetForceProcessTextInput = function() end,
    OnUpdate = function() end,
}

-- ------------------------------------------------------------
-- 杂项全局
-- ------------------------------------------------------------
function resolvefilepath(p) return p end
function IsConsole() return false end
function IsSteamDeck() return false end
function JapaneseOnPS4() return false end
function IsAnyFestivalEventActive() return false end
function ApplyLocalWordFilter(s) return s end
function GetModConfigData() return nil end
function ModIndex() return nil end
function KnownModIndex_load() return nil end
function Profile() return setmetatable({}, { __index = function() return function() end end }) end
function PopCount() return 0 end

STRINGS = setmetatable({}, {
    __index = function(t, k)
        return setmetatable({}, { __index = function() return "" end })
    end,
})

-- 场景断言辅助（由 scenario 使用）
function check(name, cond)
    __DST.checks = __DST.checks or { pass = 0, fail = 0 }
    if cond then
        __DST.checks.pass = __DST.checks.pass + 1
        print(string.format("[check] PASS  %s", tostring(name)))
    else
        __DST.checks.fail = __DST.checks.fail + 1
        print(string.format("[check] FAIL  %s", tostring(name)))
    end
    return cond and true or false
end
function assertTrue(name, cond) return check(name, cond) end
function fail(msg)
    check(msg, false)
end

-- GLOBAL 表：让 `local X = GLOBAL.X` 的 mod 代码可用
GLOBAL = {
    Class = Class, require = require, Vector3 = Vector3, unpack = unpack,
    TheSim = TheSim, TheInput = TheInput, TheFrontEnd = TheFrontEnd,
    ThePlayer = ThePlayer, TheWorld = TheWorld, TheNet = TheNet,
    easing = easing, STRINGS = STRINGS, UICOLOURS = UICOLOURS,
    resolvefilepath = resolvefilepath,
}

math.randomseed(1)

-- ------------------------------------------------------------
-- Lua 侧 JSON 编码器（供 harness 输出报告）
-- ------------------------------------------------------------
local function json_escape(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
    s = s:gsub('\t', '\\t'):gsub('%c', function(c) return string.format('\\u%04x', string.byte(c)) end)
    return s
end

local function json_encode(v, indent, level)
    indent = indent or 0
    level = level or 1
    local tv = type(v)
    if tv == "nil" then return "null"
    elseif tv == "boolean" then return v and "true" or "false"
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if math.floor(v) == v and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.10g", v)
    elseif tv == "string" then return '"' .. json_escape(v) .. '"'
    elseif tv == "table" then
        -- 判断数组（1..n 连续整数键）
        local n = 0
        for k in pairs(v) do
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                if k > n then n = k end
            else
                n = -1; break
            end
        end
        if n ~= -1 then
            if n == 0 then return "[]" end
            local parts = {}
            for i = 1, n do parts[i] = json_encode(v[i], indent, level + 1) end
            if indent > 0 then
                local pad = string.rep(" ", indent * level)
                local pad2 = string.rep(" ", indent * (level - 1))
                return "[\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. pad2 .. "]"
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        if #keys == 0 then return "{}" end
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = '"' .. json_escape(k) .. '":' .. json_encode(v[k], indent, level + 1)
        end
        if indent > 0 then
            local pad = string.rep(" ", indent * level)
            local pad2 = string.rep(" ", indent * (level - 1))
            return "{\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. pad2 .. "}"
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
__DST.json = json_encode

print(string.format("[bootstrap] DST UI 预览运行时就绪 (vclock=%.2f, viewport=%dx%d)",
    __DST.vclock, __DST.viewport.w, __DST.viewport.h))
