-- ============================================================
-- widgets/uianim.lua — UIAnim（预览 stub）
--
-- 真实 UIAnim 播放 spine/klei 动画（anim/*.zip），预览环境无法
-- 还原动画内容，降级为「带 bank:build 标注的占位块」，
-- 尺寸取默认纹理尺寸，保证布局结构正确。
-- ============================================================

UIAnim = Class(Widget, function(self, bank, build, anim)
    Widget._ctor(self, "UIAnim")
    self.className = "UIAnim"
    self.bank = bank
    self.build = build
    self.anim = anim
    self.animname = anim
    self.percent = 0
    self.paused = false
    self.tint = { 1, 1, 1, 1 }
    self.contentSize.w = __DST.defaultTexSize.w
    self.contentSize.h = __DST.defaultTexSize.h
end)

function UIAnim:SetBank(bank) self.bank = bank end
function UIAnim:SetBuild(build) self.build = build end
function UIAnim:GetBank() return self.bank end
function UIAnim:GetBuild() return self.build end
function UIAnim:SetPercent(p) self.percent = p end
function UIAnim:GetPercent() return self.percent end
function UIAnim:Pause() self.paused = true end
function UIAnim:Resume() self.paused = false end
function UIAnim:PlayAnimation(anim, loop) self.animname = anim end
function UIAnim:PushAnimation(anim, loop) self.animname = anim end
function UIAnim:SetAnimName(anim) self.animname = anim end
function UIAnim:GetAnimName() return self.animname end
function UIAnim:SetTint(r, g, b, a)
    if type(r) == "number" then self.tint = { r, g or 1, b or 1, a or 1 } else self.tint = { r[1], r[2], r[3], r[4] } end
end
function UIAnim:SetSize(w, h) self.contentSize.w = w; self.contentSize.h = h end

return UIAnim
