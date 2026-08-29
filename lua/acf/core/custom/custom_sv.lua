local ACF = ACF
local Custom = ACF.Custom

local PI    = math.pi
local Clamp = math.Clamp
local floor = math.floor
local min   = math.min
local abs   = math.abs

    --- A Torque curve builder (shared by all engine layouts); Basically expands a normalised TorqueCurve array into a Nm lookup table.
    --- It computes two tables (torque, friction) and fetches the powerband (min, max) based on said torque table.
    --- It also generates a redline value based on the remaining fraction (default 40% of remaining torque) of torque past the powerband.
    --- @param table TorqueCurve: flat array {mult0, mult1, ...} 0-1, evenly spaced over RPM.
    --- @param number MaxTorque: pre-computed maximum or peak torque the engine can possibly generate.
    --- @param number MaxRPM: the upper theorical RPM limit at which point it generates exactly 0 torque.
    --- @param number IdleRPM: RPM at which the engine just idles. 
    --- @param number Displacement: engine displacement in Liters.
    --- @param number? Steps: number of steps to compute. Defaults to 200.
    --- @return table {T_Curve:table, F_Curve:table, Steps:number, Sample:function, PeakPower:table, PeakTorque:table, PowerBand:table, RedlineRPM:number}
function Custom.BuildTorqueCurve(TorqueCurve, MaxTorque, MaxRPM, IdleRPM, Displacement, Steps)
    -- Constants
    local POWER_BAND_THRESHOLD = 0.8 -- Fraction of peak power that defines the band edges
    local REDLINE_TORQUE_FRAC  = 0.4 -- Fraction of remaining torque past its peak where we setup the redline RPM limiter
    local FRICTION_RPM_EXP     = 0.6 -- Reference exponent of total rotating assembly friction that increases with RPM. 

    local FRICTION_FMEP_BAR    = 0.52 -- Reference Friction Mean Effective Pressure in bar, at idleRPM. 
                                    -- This increases proportionally with RPM and inversely with oil temperature,
                                    -- and we make a reference value by scaling with displacement and idle rpm. 
                                    -- Props to https://x-engineer.org/mechanical-efficiency-friction-mean-effective-pressure-fmep/
    local FRICTION_TORQUE_REF  = (FRICTION_FMEP_BAR * 1e5) * (Displacement * 1e-3) / (4 * PI) -- ≈ 7.45 Nm for a 1.8L, 850RPM idle, NA engine, be it any layout.
    local FRICTION_K_FRIC      = FRICTION_TORQUE_REF / (IdleRPM ^ FRICTION_RPM_EXP * Displacement)

    local TWO_PI_OVER_60       = 2 * PI / 60

    -- Variables
    Steps = Steps or 200
    local N       = #TorqueCurve
    local T_Curve = {} -- Torque Curve
    local F_Curve = {} -- Friction Curve

    local PeakPower       = 0
    -- Wait, didn't you already get this from the func args? Well yes but not, we gotta account for the TorqueCurve discontinuities, 
    -- in which the inputted MaxTorque at the peak of the TorqueCurve does not quite match our expanded PeakTorque (its close though).
    local PeakTorque      = 0
    local PeakTorqueIdx   = 0
    local PeakPowerAtRPM  = 0
    local PeakTorqueAtRPM = 0

    -- First pass, compute the curve and define peaks 
    for I = 0, Steps do
        local Pos   = (I / Steps) * (N - 1)
        local Idx0  = floor(Pos)
        local Idx1  = min(Idx0 + 1, N - 1)
        local blend = Pos - Idx0
        local Val0  = TorqueCurve[Idx0 + 1] or 0
        local Val1  = TorqueCurve[Idx1 + 1] or 0
        T_Curve[I]  = MaxTorque * (Val0 + blend * (Val1 - Val0)) -- torque curve
        F_Curve[I]  = FRICTION_K_FRIC * (T_Curve[I] ^ FRICTION_RPM_EXP) * Displacement -- friction curve

        -- Get the i-th points
        local RPM_I    = MaxRPM * I / Steps
        local Torque_I = T_Curve[I]
        local Power_I  = Torque_I * (RPM_I * TWO_PI_OVER_60) * 0.001

        -- Get peak torque and at RPM
        if Torque_I > PeakTorque then
            PeakTorqueIdx   = I
            PeakTorque      = Torque_I
            PeakTorqueAtRPM = RPM_I
        end

        -- Get peak power and at RPM
        if Power_I > PeakPower then
            PeakPower      = Power_I
            PeakPowerAtRPM = RPM_I
        end
    end

    -- Second pass, find the redline RPM (not MaxRPM as that's the mechanical limit, this one is set before that so the engine doesn't break)
    local Threshold    = PeakPower * POWER_BAND_THRESHOLD

    local PowerbandMin = PeakPowerAtRPM
    local PowerbandMax = PeakPowerAtRPM

    local DoRedline    = REDLINE_TORQUE_FRAC and REDLINE_TORQUE_FRAC < 1.0
    local TorqueThresh = PeakTorque * REDLINE_TORQUE_FRAC
    local RedlineRPM   = 0

    for I = 0, Steps do
        local RPM_I   = MaxRPM * I / Steps
        local Power_I = T_Curve[I] * (RPM_I * TWO_PI_OVER_60) / 1000

        if Power_I >= Threshold then
            if RPM_I < PowerbandMin then PowerbandMin = RPM_I end
            if RPM_I > PowerbandMax then PowerbandMax = RPM_I end
        end

        -- Redline found, set it to be this value
        if DoRedline and I >= PeakTorqueIdx and T_Curve[I] >= TorqueThresh then
            RedlineRPM = RPM_I
        end
    end

    -- A function to get an interpolated sample out of our built torque/friction curve.
    local function Sample(RPM)
        RPM         = Clamp(RPM, 0, MaxRPM)
        local Frac  = (RPM / MaxRPM) * Steps
        local Idx0  = floor(Frac)
        local Idx1  = min(Idx0 + 1, Steps)
        local blend = Frac - Idx0
        local Tq0   = T_Curve[Idx0] or 0
        local Fr0   = F_Curve[Idx0] or 0
        local Tq1   = T_Curve[Idx1] or 0
        local Fr1   = F_Curve[Idx1] or 0
        return {Tq0 + blend * (Tq1 - Tq0), Fr0 + blend * (Fr1 - Fr0)}
    end

    return {
        T_Curve    = T_Curve,
        F_Curve    = F_Curve,
        Steps      = Steps,
        Sample     = Sample,
        PeakPower  = {InKW = PeakPower, InHP = PeakPower * ACF.KwToHp, AtRPM = PeakPowerAtRPM},
        PeakTorque = {InNm = PeakTorque, InFtLb = PeakTorque * ACF.NmToFtLb, AtRPM = PeakTorqueAtRPM},
        PowerBand  = {Band = abs(PowerbandMax - PowerbandMin), Min = PowerbandMin, Max = PowerbandMax},
        RedlineRPM = RedlineRPM
    }
end

-- Put this slop here so i don't loose it and for quick access
--- Cubic smoothstep: 0 at edge0, 1 at edge1, smooth S-curve between.
-- local function smoothstep(edge0, edge1, x)
--     local t = Clamp((x - edge0) / (edge1 - edge0 + 1e-9), 0, 1)
--     return t * t * (3 - 2 * t)
-- end

-- -- ── Valve-train modifiers ──────────────────────────────────
-- -- Relative nudges applied on top of the selected base shape (PETROL_SHAPE
-- -- or DIESEL_SHAPE) — NOT a base shape themselves. "ohc" is the zero-shift
-- -- reference (most common modern configuration), so its modifier is a
-- -- no-op; the others are expressed as deltas from it.
-- --   rise_shift: added to the base's rise_end.
-- --   fall_shift: added to the base's fall_start.
-- --   fall_k:     divides the base's fall width (>1 steeper/narrower,
-- --               <1 shallower/wider) — same convention as CAM_MOD.fall_k.
-- -- Applying the same relative nudge to either base means a pushrod head
-- -- shifts a diesel curve earlier/narrower by the same proportion it would
-- -- shift a petrol curve — valve gear affects breathing character somewhat
-- -- even under compression ignition, just less dominantly than fuel type.
-- local HEAD_SHAPE = {
--     pushrod = { rise_shift = -0.05, fall_shift = -0.08, fall_k = 0.8667 },
--     ohc     = { rise_shift =  0.00, fall_shift =  0.00, fall_k = 1.0000 },
--     dohc    = { rise_shift =  0.05, fall_shift =  0.07, fall_k = 1.1304 },
--     none    = { rise_shift = -0.02, fall_shift = -0.03, fall_k = 0.9630 },
-- }

-- -- shift:  added to fall_start and fall_end (positive → peak shifts to higher RPM).
-- -- fall_k: divides the fall width.  > 1 → steeper rolloff (narrower band);
-- --                                  < 1 → shallower rolloff (wider band).
-- local CAM_MOD = {
--     economy = { shift = -0.08, fall_k = 0.80 },
--     stock   = { shift =  0.00, fall_k = 1.00 },
--     sport   = { shift =  0.06, fall_k = 1.30 },
--     race    = { shift =  0.12, fall_k = 1.80 },
--     none    = { shift =  0.00, fall_k = 1.00 },
-- }

-- -- ── Base combustion-character curves ──────────────────────
-- -- These are the two fundamentally different torque-delivery shapes,
-- -- selected by IgnitionType. Everything else (HEAD_SHAPE, CAM_MOD,
-- -- runner length) is a MODIFIER applied on top of whichever base is
-- -- selected — valve gear and cam tuning nudge the curve, but they don't
-- -- change which combustion regime it belongs to.
-- --
-- -- PETROL_SHAPE (spark ignition, Otto cycle):
-- --   Torque delivery is governed by breathing dynamics — cylinder fill
-- --   improves through low-mid RPM as intake resonance and valve overlap
-- --   become effective, peaks, then degrades from valve float and reduced
-- --   time-per-cycle at high RPM. A gradual bell curve.
-- --
-- -- DIESEL_SHAPE (compression ignition):
-- --   Torque delivery is governed by turbo boost availability and injector
-- --   fuel-quantity/smoke limits, not breathing dynamics.
-- --     • Full torque arrives fast and early (turbo diesels are known for
-- --       near-peak torque just above idle) → rise_end sits much lower
-- --       than petrol.
-- --     • Torque then holds nearly FLAT across most of the operating range
-- --       → fall_start sits much later than petrol, giving a plateau
-- --       roughly twice as wide.
-- --     • The falloff is a STEEP, NARROW cliff rather than a gradual
-- --       rolloff — less crank-angle time per cycle to inject/burn the
-- --       full charge at high RPM, and turbo boost collapses quickly once
-- --       exhaust energy drops.
-- local PETROL_SHAPE = { rise_end = 0.45, fall_start = 0.70, fall_end = 0.96 }
-- local DIESEL_SHAPE = { rise_end = 0.28, fall_start = 0.86, fall_end = 1.00 }

-- -- Volumetric Efficiency constants as fractions from which we build the curve. Still needs tuning...
-- local VE_SAMPLES          = 24   -- resolution of the sampled output array
-- local VE_RISE_SHARP_WIDTH = 0.05 -- fraction of the curve at which engines start picking up in torque
-- local VE_PRE_IDLE_WIDTH   = 0.06 -- width as fraction of the curve where the engine generates almost no torque(before idleRPM)
-- local VE_IDLE_FRACTION    = 0.35 -- fraction of torque generated at idle 
-- local V_SOUND             = ACF.SpeedOfSound    -- m/s  (20°C air, close enough for intake calc)
-- local RES_BONUS           = 0.06   -- max Gaussian VE bonus from intake resonance
-- local RES_WIDTH           = 0.15   -- Gaussian σ in RPM-fraction units
-- -- local SCAV_BONUS          = 0.04   -- max header-scavenging VE bonus
-- -- local SCAV_PEAK           = 0.70   -- RPM fraction of peak scavenging
-- -- local SCAV_WIDTH          = 0.20   -- Gaussian σ
-- local CARB_KICK_IN        = 0.82   -- RPM fraction where carb venturi saturation begins
-- local CARB_PENALTY        = 0.07   -- VE fraction lost at redline (carburetor only)
-- local RUNNER_REF_CM       = 22.0   -- Default intake runner reference in centimeters
-- local RUNNER_SHIFT_K      = 0.0025 -- RPM-fraction shift per cm of runner length difference
-- local CR_REF_PETROL       = 9.0    -- matches CR petrol reference
-- local CR_REF_DIESEL       = 18.0   -- typical modern turbodiesel CR
-- local CR_RISE_SHIFT_K     = 0.0075 -- RPM-fraction shift per CR-unit of deviation

-- --- Two-segment idle-anchored rise.  Guarantees ve(IdleFrac) == VE_IDLE_FRACTION
-- --- exactly, regardless of how far away rise_end sits — a single smoothstep
-- --- from a below-idle zero point cannot make that guarantee (its value at
-- --- idle depends on where idle happens to fall within the window, which
-- --- varies unpredictably with head/cam/runner parameters and can land at
-- --- or near zero, leaving the engine unable to sustain its own idle).
-- ---
-- --- Segment A: zero_start → IdleFrac,  rises 0 → VE_IDLE_FRACTION
-- --- Segment B: IdleFrac   → rise_end,  rises VE_IDLE_FRACTION → 1.0
-- local function IdleAnchoredRise(t, IdleFrac, rise_end)
--     local zero_start = max(0, IdleFrac - VE_PRE_IDLE_WIDTH)

--     if t <= zero_start then
--         return 0
--     elseif t <= IdleFrac then
--         return VE_IDLE_FRACTION * smoothstep(zero_start, IdleFrac, t)
--     else
--         return VE_IDLE_FRACTION
--             + (1 - VE_IDLE_FRACTION) * smoothstep(IdleFrac, rise_end, t)
--     end
-- end

-- --- Computes a normalised volumetric-efficiency curve (0–1 values, peak = 1)
-- --- from physical valve-train, intake, exhaust, and fuel-delivery parameters.
-- --- Replaces the hand-authored TorqueCurve array that was before.
-- ---
-- --- Physical contributions (all additive on top of the base VE shape):
-- ---   HeadType      → base plateau position and rolloff steepness
-- ---   CamProfile    → RPM shift of the plateau and rolloff tightness
-- ---   RunnerLength  → Gaussian resonance bonus at the Helmholtz RPM
-- ---   ExhaustType   → header scavenging bonus in the upper-mid band
-- ---   FuelDelivery  → carburetor venturi saturation penalty above 82% redline
-- ---   IgnitionType  → glow/diesel: additional high-RPM VE suppression
-- ---   IsWankel      → replaces valve-train shape with Wankel port-timing model
-- ---
-- --- Returns a flat array of VE_SAMPLES normalised values evenly spaced 0→redline.
-- local function BuildVECurve(headType, camProfile, runnerLen_cm, fuelDelivery, ignType, redlineRPM, IsWankel, IdleFrac, CR)

--     IdleFrac = Clamp(IdleFrac or 0, 0, 0.35)

--     -- ── Wankel port-timing model (overrides valve-train entirely) ──
--     if IsWankel then
--         -- Characteristics: fast rise right at idle, broad plateau, moderate
--         -- rolloff at high RPM. No per-cam adjustment — port timing is fixed
--         -- by the rotor geometry.
--         local rise_end = max(0.22, IdleFrac + VE_RISE_SHARP_WIDTH)
--         local pts = {}
--         for i = 1, VE_SAMPLES do
--             local t  = (i - 1) / (VE_SAMPLES - 1)
--             local ve = IdleAnchoredRise(t, IdleFrac, rise_end)
--                     * (1 - smoothstep(0.73, 0.99, t))
--             -- Resonance bonus at ~65% redline (short runner)
--             local dr = (t - 0.65) / 0.16
--             ve = ve * (1 + 0.05 * exp(-0.5 * dr * dr))
--             pts[i] = Clamp(ve, 0, 1)
--         end
--         -- Normalise
--         local peak = 0
--         for _, v in ipairs(pts) do if v > peak then peak = v end end
--         if peak > 0 then for i = 1, #pts do pts[i] = pts[i] / peak end end
--         return pts
--     end

--     -- IgnitionType selects the fundamental combustion-character curve —
--     -- petrol's gradual bell shape or diesel's early-plateau-then-cliff
--     -- shape. HeadType no longer selects a shape outright; it MODIFIES
--     -- whichever base was selected (see HEAD_SHAPE comment above).
--     local base = (ignType == "glow") and DIESEL_SHAPE or PETROL_SHAPE
--     local hmod = HEAD_SHAPE[headType] or HEAD_SHAPE.ohc
--     local cam  = CAM_MOD[camProfile]  or CAM_MOD.stock

--     -- Runner length shifts the plateau onset: long runners bias toward low RPM,
--     -- short runners bias toward high RPM.
--     local runner_shift = (RUNNER_REF_CM - (runnerLen_cm or RUNNER_REF_CM)) * RUNNER_SHIFT_K

--     -- Rise completes at the (base + head modifier) plateau point, UNLESS
--     -- idle sits close enough to it that the guaranteed sharp post-idle
--     -- window would overrun it. In that case the sharp window wins so the
--     -- rise never inverts (this only matters for unusually high-idle layouts).
--     -- CR shift: higher-than-reference CR pulls rise_end earlier (faster
--     -- climb to full torque); lower-than-reference CR pushes it later.
--     local cr_ref   = (ignType == "glow") and CR_REF_DIESEL or CR_REF_PETROL
--     local cr_shift = -CR_RISE_SHIFT_K * ((CR or cr_ref) - cr_ref)
--     local rise_end = math.max(
--         base.rise_end + hmod.rise_shift + cr_shift,
--         IdleFrac + VE_RISE_SHARP_WIDTH)

--     local base_fall_width = base.fall_end - base.fall_start
--     local fall_start      = base.fall_start + hmod.fall_shift + cam.shift + runner_shift
--     local fall_width      = base_fall_width / hmod.fall_k / cam.fall_k
--     local fall_end        = fall_start + fall_width
--     -- Safety Clamp: fall can never begin before the rise has finished,
--     -- which would otherwise invert the curve for extreme head/cam/runner combos.
--     if fall_start <= rise_end then
--         fall_start = rise_end + 0.05
--         fall_end   = fall_start + fall_width
--     end
--     -- ── Intake resonance: Helmholtz RPM from runner length ─
--     local resonance_frac = 0.55   -- fallback if no runner data
--     if runnerLen_cm and runnerLen_cm > 0 then
--         local res_rpm    = (V_SOUND / (4 * runnerLen_cm * 0.01)) * 60
--         resonance_frac   = Clamp(res_rpm / redlineRPM, 0.1, 1.2)
--     end

--     -- ── Sample the curve ───────────────────────────────────
--     local pts = {}
--     for i = 1, VE_SAMPLES do
--         local t = (i - 1) / (VE_SAMPLES - 1)   -- 0 to 1

--         -- VE = 0 well below idle; guaranteed VE_IDLE_FRACTION exactly at
--         -- idle; continues to rise_end; smooth fall after.
--         local ve = IdleAnchoredRise(t, IdleFrac, rise_end)
--             * (1 - smoothstep(fall_start, fall_end, t))

--         -- Intake resonance Gaussian bonus (scales with base VE so it
--         -- doesn't add a bump where the engine is otherwise dead)
--         local dr = (t - resonance_frac) / RES_WIDTH
--         ve = ve + ve * RES_BONUS * exp(-0.5 * dr * dr)

--         --[[
--         -- Header scavenging (upper-mid band bonus)
--         if exhaustType == "header" then
--             local ds = (t - SCAV_PEAK) / SCAV_WIDTH
--             ve = ve + ve * SCAV_BONUS * exp(-0.5 * ds * ds)
--         end
--         ]]--
--         -- Carburetor high-RPM penalty (venturi saturation)
--         if fuelDelivery == "carburetor" and t > CARB_KICK_IN then
--             local pen = ((t - CARB_KICK_IN) / (1 - CARB_KICK_IN)) * CARB_PENALTY
--             ve = ve * (1 - pen)
--         end

--         pts[i] = Clamp(ve, 0, 1)
--     end

--     -- Normalise so peak = 1.0 (peak torque is set by BMEP, not by this array)
--     local peak = 0
--     for _, v in ipairs(pts) do if v > peak then peak = v end end
--     if peak > 0 then for i = 1, #pts do pts[i] = pts[i] / peak end end

--     return pts
-- end