-- ============================================================
--  ACF Engine Entity — Client
--  lua/entities/acf_engine/cl_init.lua
--
--  Reads NW vars set by EngineInterface:_FlushNWVars() and
--  draws an instrument-panel HUD when the player looks at the
--  engine within range.
--
--  All values are read from NW floats/bools — no simulation
--  logic runs on the client.
-- ============================================================

include("shared.lua")

-- ──────────────────────────────────────────────────────────
--  HUD constants
-- ──────────────────────────────────────────────────────────

local HUD_RANGE   = 200    -- units  max distance to show HUD
local HUD_W       = 280    -- pixels panel width
local HUD_H       = 340    -- pixels panel height
local HUD_PAD     = 8

local COL_BG      = Color(10,  10,  10,  200)
local COL_BORDER  = Color(60,  60,  60,  255)
local COL_TITLE   = Color(220, 220, 220, 255)
local COL_LABEL   = Color(160, 160, 160, 255)
local COL_VALUE   = Color(255, 255, 255, 255)
local COL_WARN    = Color(255, 180, 0,   255)
local COL_DANGER  = Color(255, 60,  60,  255)
local COL_OK      = Color(60,  200, 100, 255)
local COL_BAR_BG  = Color(40,  40,  40,  255)
local COL_BAR_COOL = Color(60, 140, 255, 255)
local COL_BAR_OIL  = Color(200, 140, 40, 255)
local COL_BAR_WEAR = Color(200, 60,  60,  255)
local COL_BAR_EGT  = Color(255, 100, 30,  255)

-- ──────────────────────────────────────────────────────────
--  Helper: draw a labelled bar
-- ──────────────────────────────────────────────────────────

local function DrawBar(x, y, w, h, frac, col, label, valueStr)
    -- Background
    draw.RoundedBox(2, x, y, w, h, COL_BAR_BG)
    -- Fill
    local fw = math.Clamp(frac, 0, 1) * (w - 2)
    if fw > 0 then
        draw.RoundedBox(2, x + 1, y + 1, fw, h - 2, col)
    end
    -- Label
    draw.SimpleText(label,     "DermaDefault", x + 4,         y + h / 2, COL_LABEL, TEXT_ALIGN_LEFT,   TEXT_ALIGN_CENTER)
    draw.SimpleText(valueStr,  "DermaDefault", x + w - 4,     y + h / 2, COL_VALUE, TEXT_ALIGN_RIGHT,  TEXT_ALIGN_CENTER)
end

-- ──────────────────────────────────────────────────────────
--  Helper: row of label + value
-- ──────────────────────────────────────────────────────────

local function DrawRow(x, y, label, valueStr, col)
    draw.SimpleText(label,    "DermaDefault", x,       y, COL_LABEL, TEXT_ALIGN_LEFT,  TEXT_ALIGN_TOP)
    draw.SimpleText(valueStr, "DermaDefault", x + 160, y, col or COL_VALUE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

-- ──────────────────────────────────────────────────────────
--  DrawEntityInfo  (called by the ACF HUD system)
-- ──────────────────────────────────────────────────────────

function ENT:DrawEntityInfo(pos2d, dist)
    if dist > HUD_RANGE then return end
    if not pos2d then return end

    local sx  = pos2d.x - HUD_W / 2
    local sy  = pos2d.y - HUD_H / 2

    -- Read NW vars
    local running   = self:GetNWBool ("ACF_Run",      false)
    local rpm       = self:GetNWFloat("ACF_RPM",      0)
    local torque    = self:GetNWFloat("ACF_Torque",   0)
    local power     = self:GetNWFloat("ACF_Power",    0)
    local wear      = self:GetNWFloat("ACF_Wear",     0)
    local fuel      = self:GetNWFloat("ACF_Fuel",     0)
    local coolT     = self:GetNWFloat("ACF_CoolTemp", 20)
    local oilT      = self:GetNWFloat("ACF_OilTemp",  20)
    local coolLvl   = self:GetNWFloat("ACF_CoolLvl",  1)
    local oilBar    = self:GetNWFloat("ACF_OilBar",   0)
    local oilOK     = self:GetNWBool ("ACF_OilOK",    true)
    local overheat  = self:GetNWBool ("ACF_Overheat", false)
    local boost     = self:GetNWFloat("ACF_Boost",    0)
    local lambda    = self:GetNWFloat("ACF_Lambda",   1)
    local egt       = self:GetNWFloat("ACF_EGT",      20)
    local batV      = self:GetNWFloat("ACF_BatV",     12)
    local batSOC    = self:GetNWFloat("ACF_BatSOC",   1)
    local bigEndK   = self:GetNWBool ("ACF_BigEndK",  false)
    local preIgnite = self:GetNWBool ("ACF_PreIgnite",false)
    local glowRdy   = self:GetNWBool ("ACF_GlowRdy",  true)
    local surge     = self:GetNWBool ("ACF_Surge",    false)

    -- Panel background
    draw.RoundedBox(6, sx, sy, HUD_W, HUD_H, COL_BG)
    draw.RoundedBoxEx(6, sx, sy, HUD_W, 24, COL_BORDER, true, true, false, false)

    -- Title
    local name  = self:GetNWString("ACF_EngineName", self.PrintName or "Engine")
    local state = running and "RUNNING" or "STOPPED"
    local sCol  = running and COL_OK or COL_LABEL
    draw.SimpleText(name,  "DermaDefaultBold", sx + HUD_W / 2, sy + 12, COL_TITLE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local y = sy + 30
    local x = sx + HUD_PAD

    -- Status row
    DrawRow(x, y, "State",  state, sCol)
    DrawRow(x + 140, y, "Boost", string.format("%.2f bar", boost), boost > 0.1 and COL_WARN or COL_LABEL)
    y = y + 16

    -- RPM / Torque / Power
    DrawRow(x, y, "RPM",    string.format("%d", rpm))
    y = y + 14
    DrawRow(x, y, "Torque", string.format("%.0f Nm", torque))
    DrawRow(x + 140, y, "Power",  string.format("%.1f kW", power))
    y = y + 18

    -- Thermal bars
    local coolFrac = math.Clamp((coolT - 20) / (120 - 20), 0, 1)
    local coolCol  = coolT > 105 and COL_DANGER or (coolT > 88 and COL_WARN or COL_BAR_COOL)
    DrawBar(x, y, HUD_W - HUD_PAD * 2, 14, coolFrac, coolCol,
        "Coolant", string.format("%.0f°C", coolT))
    y = y + 18

    local oilFrac  = math.Clamp((oilT - 20) / (160 - 20), 0, 1)
    local oilCol   = oilT > 130 and COL_DANGER or (oilT > 90 and COL_WARN or COL_BAR_OIL)
    DrawBar(x, y, HUD_W - HUD_PAD * 2, 14, oilFrac, oilCol,
        "Oil", string.format("%.0f°C | %.1f bar", oilT, oilBar))
    y = y + 18

    local egtFrac  = math.Clamp((egt - 20) / (1100 - 20), 0, 1)
    local egtCol   = egt > 1000 and COL_DANGER or (egt > 900 and COL_WARN or COL_BAR_EGT)
    DrawBar(x, y, HUD_W - HUD_PAD * 2, 14, egtFrac, egtCol,
        "EGT", string.format("%.0f°C", egt))
    y = y + 18

    -- Wear bar
    local wearCol = wear > 0.85 and COL_DANGER or (wear > 0.5 and COL_WARN or COL_OK)
    DrawBar(x, y, HUD_W - HUD_PAD * 2, 14, wear, COL_BAR_WEAR,
        "Wear", string.format("%.0f%%", wear * 100))
    y = y + 18

    wearCol = wearCol -- What's this used for anyway?
    -- Coolant level + fuel
    DrawRow(x, y, "Coolant lvl", string.format("%.0f%%", coolLvl * 100),
        coolLvl < 0.15 and COL_DANGER or (coolLvl < 0.5 and COL_WARN or COL_VALUE))
    DrawRow(x + 140, y, "Fuel", string.format("%.0f L", fuel))
    y = y + 14

    -- Battery
    DrawRow(x, y, "Battery",
        string.format("%.1f V  %.0f%%", batV, batSOC * 100),
        batV < 10 and COL_DANGER or (batV < 11.5 and COL_WARN or COL_VALUE))
    y = y + 14

    -- Lambda
    local lamCol = (lambda < 0.7 or lambda > 1.3) and COL_DANGER
                or (lambda < 0.85 or lambda > 1.1) and COL_WARN or COL_OK
    DrawRow(x, y, "Lambda", string.format("λ %.3f", lambda), lamCol)
    y = y + 16

    -- Warning flags
    local flags = {}
    if overheat   then flags[#flags + 1] = {t = "OVERHEAT",    c = COL_DANGER} end
    if not oilOK  then flags[#flags + 1] = {t = "OIL STARVED", c = COL_DANGER} end
    if bigEndK    then flags[#flags + 1] = {t = "ROD KNOCK",   c = COL_DANGER} end
    if preIgnite  then flags[#flags + 1] = {t = "PRE-IGNITION",c = COL_WARN}   end
    if surge      then flags[#flags + 1] = {t = "SURGE",       c = COL_WARN}   end
    if not glowRdy and not running then
        flags[#flags + 1] = {t = "GLOWS HEATING", c = COL_WARN}
    end

    for _, f in ipairs(flags) do
        draw.SimpleText(f.t, "DermaDefaultBold", sx + HUD_W / 2, y, f.c,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        y = y + 14
    end
end

-- ──────────────────────────────────────────────────────────
--  Trace highlight when targeted
-- ──────────────────────────────────────────────────────────

function ENT:Think()
    -- Client-side think: nothing needed (no simulation runs here)
end

function ENT:Initialize()
    -- Nothing needed client-side
end