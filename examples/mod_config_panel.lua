-- ============================================================
-- mod_config_panel.lua — 典型 DST mod 配置面板
--
-- 覆盖：Image 背景、Text 标题/说明、ImageButton（带 focus 纹理切换）、
--       Spinner 下拉、自绘 Checkbox、Button 应用按钮、TextEdit 输入框。
--
-- 预览：
--   python3 scripts/run_dst_ui.py --screen examples/mod_config_panel.lua \
--       --textures examples/textures --style both --out /workspace/config_panel.png
-- 交互（点第 1 个复选框 + 点「应用到世界」）：
--   ... --click 340,242 --click 510,600
-- ============================================================
local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"
local Button = require "widgets/button"
local ImageButton = require "widgets/imagebutton"
local Spinner = require "widgets/spinner"
local TextEdit = require "widgets/textedit"

-- 图集：真实游戏里 images/global_redux.xml 提供 button/checkbox 等控件纹理
local ATLAS = "images/global_redux.xml"
local LABEL_X = -300          -- 左列（说明文字）
local CTRL_X  = 90            -- 右列（控件）

local function MakeCheckboxRow(parent, y, label, desc, checked, onchange)
    local row = parent:AddChild(Widget("checkbox_row"))
    row:SetPosition(0, y)
    row:SetSize(700, 52)

    local box = row:AddChild(ImageButton(ATLAS, "checkbox_default.tex", "checkbox_focus.tex",
                                         "checkbox_disabled.tex", "checkbox_default.tex",
                                         "checkbox_selected.tex"))
    box:ForceImageSize(32, 32)
    box:SetPosition(LABEL_X, 0, 0)

    local mark = row:AddChild(Image("images/global_redux.xml", "checkbox_checked.tex"))
    mark:SetSize(30, 30)
    mark:SetPosition(LABEL_X, 0, 0.1)
    mark:SetTint(0.45, 0.85, 0.4, 1)
    mark:SetClickable(false)

    local name = row:AddChild(Text(UIFONT, 24, label))
    name:SetPosition(LABEL_X + 42, 8, 0)
    name:SetHAlign(ANCHOR_LEFT)

    local sub = row:AddChild(Text(UIFONT, 18, desc))
    sub:SetPosition(LABEL_X + 42, -13, 0)
    sub:SetHAlign(ANCHOR_LEFT)
    sub:SetColour(0.62, 0.6, 0.55, 1)

    local state = checked
    local function refresh() if state then mark:Show() else mark:Hide() end end
    refresh()

    box.onclick = function()
        state = not state
        refresh()
        if onchange then onchange(state) end
    end
    return row
end

local ModConfigPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "ModConfigPanel")
    self.owner = owner
    self.options = {
        { name = "自动捡取", desc = "自动拾取附近的资源", value = true },
        { name = "显示血量条", desc = "在角色头顶显示血量", value = false },
        { name = "快速制作", desc = "跳过制作动画", value = true },
    }

    -- 背板
    local panel = self:AddChild(Image(ATLAS, "panel_backdrop.tex"))
    panel:SetSize(820, 600)
    panel:SetPosition(0, -10)
    panel:SetTint(0.16, 0.15, 0.13, 0.98)

    -- 标题区
    local title = self:AddChild(Text(TITLEFONT, 44, "模组设置 · 自动拾取"))
    title:SetPosition(0, 235)
    title:SetColour(0.95, 0.85, 0.6, 1)

    local subtitle = self:AddChild(Text(UIFONT, 20, "修改后需重启世界生效"))
    subtitle:SetPosition(0, 197)
    subtitle:SetColour(0.72, 0.7, 0.64, 1)

    local line = self:AddChild(Image(ATLAS, "divider.tex"))
    line:SetSize(740, 2)
    line:SetPosition(0, 174)
    line:SetTint(0.5, 0.45, 0.34, 0.85)

    -- 三行开关
    local y = 118
    for _, opt in ipairs(self.options) do
        MakeCheckboxRow(self, y, opt.name, opt.desc, opt.value, function(v)
            opt.value = v
            print(string.format("[config] %s = %s", opt.name, tostring(v)))
            subtitle:SetString(string.format("%s 已%s", opt.name, v and "开启" or "关闭"))
        end)
        y = y - 56
    end

    -- Spinner：拾取半径
    local spin_label = self:AddChild(Text(UIFONT, 24, "拾取半径"))
    spin_label:SetPosition(LABEL_X, y, 0)
    spin_label:SetHAlign(ANCHOR_LEFT)

    local spinner = self:AddChild(Spinner({
        { text = "小", data = 1 },
        { text = "中", data = 2 },
        { text = "大", data = 3 },
    }, 220, 44, { font = UIFONT, size = 22 }))
    spinner:SetPosition(CTRL_X + 110, y)
    spinner:SetSelectedIndex(2)
    self.spinner = spinner

    y = y - 62

    -- TextEdit：好友白名单
    local edit_label = self:AddChild(Text(UIFONT, 24, "好友白名单"))
    edit_label:SetPosition(LABEL_X, y, 0)
    edit_label:SetHAlign(ANCHOR_LEFT)

    local edit = self:AddChild(TextEdit(UIFONT, 22, "Wilson, Willow"))
    edit:SetRegionSize(300, 40)              -- Text/TextEdit 的 SetSize 是字号，盒子用 SetRegionSize
    edit:SetPosition(CTRL_X + 150, y)
    edit.idle_text_color = { 1, 1, 1, 1 }    -- 真实 mod 常见写法（DST 默认黑色）
    edit.edit_text_color = { 1, 0.95, 0.7, 1 }
    edit:SetColour(1, 1, 1, 1)
    edit:SetTextLengthLimit(60)
    self.edit = edit

    -- 底部按钮（DST 常见写法：Image 做底板 + Button 只管文字与点击）
    local apply_bg = self:AddChild(Image(ATLAS, "button_long.tex"))
    apply_bg:SetSize(240, 54)
    apply_bg:SetPosition(-130, -240)

    local apply = self:AddChild(Button())
    apply:SetSize(240, 54)
    apply:SetPosition(-130, -240)
    apply:SetText("应用到世界")
    apply.onclick = function()
        title:SetString("设置已保存 ✓")
        title:SetColour(0.6, 0.9, 0.5, 1)
    end

    local reset = self:AddChild(ImageButton(ATLAS, "button_medium_locked.tex",
                                            "button_medium_hover.tex", nil,
                                            "button_medium_pressed.tex"))
    reset:SetPosition(140, -240)
    reset.onclick = function()
        spinner:SetSelectedIndex(2)
        subtitle:SetString("已恢复默认设置")
    end

    self.panel = panel
end)

return ModConfigPanel
