-- This file copies the health.lua overlay element just to add its own cause march didn't really think...
-- about future proofing his work a little bit better, so instead we have to do it ourselves (oh boomer!)
local ACF = ACF
local Overlay = ACF.Overlay

-- Data slots are as follows:
--   [1]: Label
--   [2]: Value 
--   [3]: Min Value
--   [4]: Max Value
--   [5]: Unit?
--   [6]: Decimals?
--   [7]: Min Color?
--   [8]: Max Color?

PrintTable({Overlay})

local PROGRESS_EMPTY = Color(66, 96, 116)
local PROGRESS_FULL  = Color(112, 191, 243)

-- A zero maximum is a real state -- an ammo crate too small for a whole round, a drained
-- supply crate -- and dividing by it yields NaN, which prints as "nan%" and makes the bar
-- geometry NaN too, since comparisons against NaN are false and math.Clamp lets it through.
local function SafeClampedRatio(Value, Minimum, Maximum)
    if not Maximum or Maximum <= Minimum then return 0 end

    local Ratio = (Value - Minimum) / (Maximum - Minimum)

    return math.max(0, math.min(1, Ratio))
end

local function GetPropertiesSimpleProgress(Slot)
    local Value      = Slot.Data[2]
    local MinValue   = Slot.Data[3] or 0
    local MaxValue   = Slot.Data[4] or 1
    local Unit       = Slot.NumData >= 5 and Slot.Data[5] or ""
    local Decimals   = Slot.NumData >= 6 and Slot.Data[6] or 0

    local MinColor   = Slot.NumData >= 7 and Slot.Data[7] or PROGRESS_EMPTY
    local MaxColor   = Slot.NumData >= 8 and Slot.Data[8] or PROGRESS_FULL

    local Ratio      = SafeClampedRatio(Value, MinValue, MaxValue)
    return ("%." .. Decimals .. "f%s"):format(Value, Unit), Ratio, MinColor, MaxColor
end

local function Render(Slot, TextMethod)
    -- Our horizontal positions here are dependent on the final size of everything.
    -- So those will be adjusted in PostRender, and we'll allocate our size here.

    local W1, H1 = Overlay.GetTextSize(Overlay.PROGRESS_BAR_TEXT, Slot.Data[1])
    local ProgressText = TextMethod(Slot)
    local W2, H2 = Overlay.GetTextSize(Overlay.PROGRESS_BAR_TEXT, ProgressText)
    H2 = H2 + 4
    Overlay.AppendSlotSize(W1 + W2 + 32, math.max(H1, H2))
    Overlay.PushWidths(W1, W2)
end

local ColorCache = Color(255, 255, 255)
local function LerpColor(T, A, B)
    local R1, G1, B1, A1 = A:Unpack()
    local R2, G2, B2, A2 = B:Unpack()
    ColorCache:SetUnpacked(
        Lerp(T, R1, R2),
        Lerp(T, G1, G2),
        Lerp(T, B1, B2),
        Lerp(T, A1, A2)
    )
    ColorCache:SetBrightness(1)
    return ColorCache:Copy()
end

local FakeScanlines = Material("vgui/gradient_down")

local ClipDir_1 = Vector(1, 0, 0)
local ClipDir_2 = Vector(-1, 0, 0)
local function Linear(x) return x end
local function RenderBar(Slot, TextMethod)
    local TotalW = Overlay.GetOverlaySize()

    local Text = Slot.Data[1]
    local InnerText, Ratio, MinC, MaxC, ColorInterp = TextMethod(Slot)
    Ratio = math.Clamp(Ratio, 0, 1)
    ColorInterp = ColorInterp or Linear

    local ValueX = Overlay.GetKVValueX()
    local _, H1 = Overlay.GetTextSize(Overlay.PROGRESS_BAR_TEXT, Text)
    local _, H2 = Overlay.GetTextSize(Overlay.PROGRESS_BAR_TEXT, InnerText)

    Overlay.SimpleText(Text, Overlay.KEY_TEXT_FONT, Overlay.GetKVKeyX(), 0, Overlay.COLOR_TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    Overlay.DrawKVDivider()
    local X, Y = ValueX, 0
    local W, H = (TotalW / 2) - 32, math.max(H1, H2)

    local CV = Overlay.GetOverlayOffset()
    local ClipTextRatio = (CV[1] + X) + (W * Ratio)

    Overlay.PushCustomClipPlane(ClipDir_1, ClipTextRatio)
    Overlay.SimpleText(InnerText, Overlay.PROGRESS_BAR_TEXT, X + (W / 2), Y + (H / 2) - 1, Overlay.COLOR_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    Overlay.PopCustomClipPlane()

    local ColorRatio = ColorInterp(Ratio)

    local BarColor = LerpColor(ColorRatio, MinC, MaxC)
    Overlay.DrawRect(X, Y, W * Ratio, H, BarColor)
    Overlay.SetMaterial(FakeScanlines)
    local BarScanlinesColor = BarColor:Copy()
    BarScanlinesColor:SetBrightness(0.8)
    local Now = RealTime() % 1
    Overlay.DrawTexturedRectUV(X, Y, W * Ratio, H, 0, Now, 0, Now + 8, BarScanlinesColor)
    Overlay.NoTexture()

    local BackColor = LerpColor(ColorRatio, MinC, MaxC)
    BackColor:SetBrightness(0.3)
    Overlay.DrawOutlinedRect(X, Y, W, H, BackColor, 2)

    local BackTextColor = LerpColor(ColorRatio, MinC, MaxC)
    BackTextColor:SetSaturation(0.3)
    BackTextColor:SetBrightness(1)

    Overlay.PushCustomClipPlane(ClipDir_2, -ClipTextRatio)
    Overlay.SimpleText(InnerText, Overlay.PROGRESS_BAR_TEXT, X + (W / 2), Y + (H / 2) - 1, Overlay.COLOR_TEXT_DARK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    Overlay.PopCustomClipPlane()
end

-- Absolute fucking cringe, but ehh whatever
timer.Simple(0.1, function()
    local CUSTOM_PROGRESS_BAR = {}
    function CUSTOM_PROGRESS_BAR.Render(_, Slot) Render(Slot, GetPropertiesSimpleProgress) end
    function CUSTOM_PROGRESS_BAR.PostRender(_, Slot) RenderBar(Slot, GetPropertiesSimpleProgress) end
    Overlay.DefineElementType("CustomProgressBar", CUSTOM_PROGRESS_BAR)
end)
