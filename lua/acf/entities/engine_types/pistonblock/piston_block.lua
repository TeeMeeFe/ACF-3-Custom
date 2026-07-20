local ACF     = ACF
local Classes = ACF.Classes
local istable = istable
local PI      = math.pi
local abs     = math.abs
local Clamp   = math.Clamp
local Round   = math.Round
local floor   = math.floor
local exp     = math.exp
local min     = math.min
local max     = math.max
local pow     = math.pow
local sqrt    = math.sqrt

-- ===========================================================================
--  Base piston block class definition 
--
--  ── Virtual method: GetLayoutFactors(params) ─────────────────
--
--  Each layout overrides this to return a flat table of multipliers
--  applied on top of the shared piston geometry math:
--
--    InertiaFactor     – multiplier on flywheel inertia
--    BalanceFactor     – crankshaft balance quality [0-1]; lower means
--                        minimum stable idle RPM is higher
--    TorqueSmoothness  – torque delivery evenness [0-1]; affects misfire
--                        sensitivity and idle roughness
--    BSFCMult          – correction on top of Otto-cycle BSFC
--    IdleRPMMult       – scales the bore/stroke-derived idle RPM
--    VEBonus           – volumetric efficiency offset [-0.1 .. +0.1]
--    FiringIrregularity– fractional deviation from even firing [0-1]
--
--  ── Entity parameters (set in entity's instance module: spawning.lua) ─────
--
--  Piston engines:
--    Layout      string  "inline"|"boxer"|"v"|"wr"|"wankel"|...etc 
--    Bore        number  cylinder bore radius (cm)
--    Stroke      number  piston stroke (cm)
--    Clearance   number  TDC dead space (cm)
--    Pistons     number  cylinder count (rotors for Wankel)
--    BankAngle   number  degrees between banks (V, WR)
--    BankCount   number  number of banks (WR only; V is always 2)
--
-- ===========================================================================

Classes.DefineClass("ACF.Engines.PistonBlock", "ACF.Engines.BaseEngineBlock", function()
    CLASS.Name          = "Piston Block Class"
    CLASS.Description   = "The base class for any and all piston engines."
    CLASS.ToolDesc      = "Attempts to spawn the selected piston engine."
    CLASS.DefaultModel  = "models/holograms/cube.mdl"
    -- TODO: Some of these attributes should be defined per fuel type
    CLASS.Gamma         = 1.4       -- heat capacity ratio (diatomic air)
    CLASS.LHV_KWH       = 12.222222 -- 44000 / 3600 petrol lower heating value (kWh/kg).
    CLASS.ETA_FRIC      = 0.55      -- Otto → shaft efficiency fraction
    CLASS.BMEP_Scale    = 40        -- Brake Mean Effective Pressure in bar per unit of TorqueScale
    -- Inline engine calibrated mass coefficients
    CLASS.PistonMass_K  = 0.0005    -- kg per cm²
    CLASS.RodMass_K     = 0.0009    -- kg per cm²
    CLASS.CrankMass_K   = 0.0028    -- kg per cm³
    CLASS.BlockMass_K   = 0.05      -- kg per cm³
    CLASS.HeadMass_K    = 0.018     -- kg per cm³
    -- Base heat coefficient calibrated for 1.0 L, CR 9 petrol engine
    CLASS.HeatBase      = 0.012
    -- Reference BSFC for type-correction ratio
    CLASS.REF_BSFC      = 0.304     -- kg/kWh  (GenericPetrol)
    -- Default piston speed limit if Params does not specify one
    CLASS.DEFAULT_PISTON_SPEED = 20 -- m/s
    -- Wankel: power strokes per rotor per shaft revolution
    --CLASS.WANKEL_POWER_STROKES = 3  -- TODO: This shouldn't be here IMHO

    MENU_FIELD("ACF.Engines.PistonBlock", "EngineType", {
        "ACF.Engines.InlineEngine",
        "ACF.Engines.BoxerEngine",
        "ACF.Engines.VTypeEngine",
        "ACF.Engines.WRTypeEngine",
        "ACF.Engines.RotaryEngine",
        "ACF.Engines.RadialEngine",
        "ACF.Engines.SingleMonoEngine",
        "ACF.Engines.ParallelTwinEngine"
    })

    -- ── Compression ratio bounds, keyed by ignition type ───────
    -- Diesel's range is a hard physical requirement (compression
    -- ignition needs enough heat from compression alone to self-ignite,
    -- which only happens in a narrow high-CR band); petrol's range is
    -- knock-limited (RON/octane) and much wider, but still bounded.
    local CR_BOUNDS = {
        glow  = { min = 16.0, max = 22.0 },   -- diesel: compression-ignition requirement
        spark = { min = 7.0,  max = 13.0 },   -- petrol/other: knock-limited range
    }
    local CR_BOUNDS_DEFAULT = CR_BOUNDS.spark

    -- Reference CR for the thermodynamic torque-scaling multiplier below
    local CR_TORQUE_REF = 9.0

    -- ──────────────────────────────────────────────────────────
    --  Torque curve builder (shared by all layouts)
    -- ──────────────────────────────────────────────────────────
    --- Basically expands a normalised VE array into a Nm lookup table.
    --- @param table typeCurve: flat array {mult0, mult1, ...} 0-1, evenly spaced over RPM.
    --- @param number peakTorque: pre-computed maximum or peak torque the engine can possibly generate.
    --- @param number maxRPM: the upper theorical RPM limit at which point it generates exactly 0 torque.
    --- @param number idleRPM: RPM at which the engine just idles. 
    --- @param number dispL: engine displacement in Liters.
    --- @param number? steps: number of steps to compute. Defaults to 200.
    --- @return table  {Curve:table, Steps:number, Sample:function, PeakPower:table, PeakTorque:table, PowerBand:table}
    local function BuildCurve(typeCurve, peakTorque, maxRPM, idleRPM, dispL, steps)
        -- Constants
        local POWER_BAND_THRESHOLD = 0.8 -- Fraction of peak power that defines the band edges
        local REDLINE_TORQUE_FRAC  = 0.4 -- Fraction of remaining torque past its peak where we setup the redline RPM limiter
        local FRICTION_RPM_EXP     = 0.6 -- Reference exponent of total rotating assembly friction that increases with RPM. 

        local FRICTION_FMEP_BAR    = 0.52 -- Reference Friction Mean Effective Pressure in bar, at idleRPM. 
                                          -- This increases proportionally with RPM and inversely with oil temperature,
                                          -- and we make a reference value by scaling with displacement and idle rpm. 
                                          -- Props to https://x-engineer.org/mechanical-efficiency-friction-mean-effective-pressure-fmep/
        local FRICTION_TORQUE_REF  = (FRICTION_FMEP_BAR * 1e5) * (dispL * 1e-3) / (4 * PI) -- ≈ 7.45 Nm for a 1.8L, 850RPM idle, NA engine, be it any layout.
        local FRICTION_K_FRIC      = FRICTION_TORQUE_REF / (idleRPM ^ FRICTION_RPM_EXP * dispL)

        local TWO_PI_OVER_60       = 2 * PI / 60
        local KWTOHP               = ACF.KwToHp
        local NMTOFTLB             = ACF.NmToFtLb

        -- Variables
        steps = steps or 200
        local n       = #typeCurve
        local t_curve = {}
        local f_curve = {}

        local peakPowerKW     = 0
        local peakTorqueIdx   = 0
        local peakPowerAtRPM  = 0
        local peakTorqueAtRPM = 0

        -- First pass, compute the curve and define peaks 
        for i = 0, steps do
            local pos   = (i / steps) * (n - 1)
            local idx0  = floor(pos)
            local idx1  = min(idx0 + 1, n - 1)
            local blend = pos - idx0
            local v0    = typeCurve[idx0 + 1] or 0
            local v1    = typeCurve[idx1 + 1] or 0
            t_curve[i]  = peakTorque * (v0 + blend * (v1 - v0)) -- torque curve
            f_curve[i]  = FRICTION_K_FRIC * (t_curve[i] ^ FRICTION_RPM_EXP) * dispL -- friction curve

            -- Get the i-th points
            local rpm_i    = maxRPM * i / steps
            local torque_i = t_curve[i]
            local power_i  = torque_i * (rpm_i * TWO_PI_OVER_60) * 0.001

            -- Get peak torque and at RPM
            if torque_i >= peakTorque then
                peakTorqueAtRPM = rpm_i
                peakTorqueIdx   = i
            end

            -- Get peak power and at RPM
            if power_i > peakPowerKW then
                peakPowerKW    = power_i
                peakPowerAtRPM = rpm_i
            end
        end

         -- Second pass, find the redline RPM (not maxRPM as that's the mechanical limit, this one is set before that so it doesn't explode)
        local threshold    = peakPowerKW * POWER_BAND_THRESHOLD

        local powerbandMin = peakPowerAtRPM
        local powerbandMax = peakPowerAtRPM

        local doRedline    = REDLINE_TORQUE_FRAC and REDLINE_TORQUE_FRAC < 1.0
        local torqueThresh = peakTorque * REDLINE_TORQUE_FRAC
        local redlineRPM   = 0

        for i = 0, steps do
            local rpm_i   = maxRPM * i / steps
            local power_i = t_curve[i] * (rpm_i * TWO_PI_OVER_60) / 1000

            if power_i >= threshold then
                if rpm_i < powerbandMin then powerbandMin = rpm_i end
                if rpm_i > powerbandMax then powerbandMax = rpm_i end
            end

            if doRedline and i >= peakTorqueIdx and t_curve[i] >= torqueThresh then
                redlineRPM = rpm_i
            end
        end

        local function sample(rpm)
            rpm         = Clamp(rpm, 0, maxRPM)
            local frac  = (rpm / maxRPM) * steps
            local idx0  = floor(frac)
            local idx1  = min(idx0 + 1, steps)
            local blend = frac - idx0
            local t0    = t_curve[idx0] or 0
            local f0    = f_curve[idx0] or 0
            local t1    = t_curve[idx1] or 0
            local f1    = f_curve[idx1] or 0
            return {t0 + blend * (t1 - t0), f0 + blend * (f1 - f0)}
        end

        return {
            T_Curve    = t_curve,
            F_Curve    = f_curve,
            Steps      = steps,
            Sample     = sample,
            PeakPower  = {InKW = peakPowerKW, InHP = peakPowerKW * KWTOHP, AtRPM = peakPowerAtRPM},
            PeakTorque = {InNm = peakTorque, InFtLb = peakTorque * NMTOFTLB, AtRPM = peakTorqueAtRPM},
            PowerBand  = {Band = abs(powerbandMax - powerbandMin), Min = powerbandMin, Max = powerbandMax},
            RedlineRPM = redlineRPM
        }
    end

    --- Concrete layouts call this after setting their own GetLayoutFactors.
    function CLASS.Compute(SUPER, LayoutFactors, Params)
        if not SUPER then return end -- TODO: Maybe another check here if its a class?
        if not Params and istable(Params) then return end
        if not LayoutFactors and istable(LayoutFactors) then return end

        --- Cubic smoothstep: 0 at edge0, 1 at edge1, smooth S-curve between.
        local function smoothstep(edge0, edge1, x)
            local t = Clamp((x - edge0) / (edge1 - edge0 + 1e-9), 0, 1)
            return t * t * (3 - 2 * t)
        end

        -- ── Valve-train modifiers ──────────────────────────────────
        -- Relative nudges applied on top of the selected base shape (PETROL_SHAPE
        -- or DIESEL_SHAPE) — NOT a base shape themselves. "ohc" is the zero-shift
        -- reference (most common modern configuration), so its modifier is a
        -- no-op; the others are expressed as deltas from it.
        --   rise_shift: added to the base's rise_end.
        --   fall_shift: added to the base's fall_start.
        --   fall_k:     divides the base's fall width (>1 steeper/narrower,
        --               <1 shallower/wider) — same convention as CAM_MOD.fall_k.
        -- Applying the same relative nudge to either base means a pushrod head
        -- shifts a diesel curve earlier/narrower by the same proportion it would
        -- shift a petrol curve — valve gear affects breathing character somewhat
        -- even under compression ignition, just less dominantly than fuel type.
        local HEAD_SHAPE = {
            pushrod = { rise_shift = -0.05, fall_shift = -0.08, fall_k = 0.8667 },
            ohc     = { rise_shift =  0.00, fall_shift =  0.00, fall_k = 1.0000 },
            dohc    = { rise_shift =  0.05, fall_shift =  0.07, fall_k = 1.1304 },
            none    = { rise_shift = -0.02, fall_shift = -0.03, fall_k = 0.9630 },
        }

        -- shift:  added to fall_start and fall_end (positive → peak shifts to higher RPM).
        -- fall_k: divides the fall width.  > 1 → steeper rolloff (narrower band);
        --                                  < 1 → shallower rolloff (wider band).
        local CAM_MOD = {
            economy = { shift = -0.08, fall_k = 0.80 },
            stock   = { shift =  0.00, fall_k = 1.00 },
            sport   = { shift =  0.06, fall_k = 1.30 },
            race    = { shift =  0.12, fall_k = 1.80 },
            none    = { shift =  0.00, fall_k = 1.00 },
        }

        -- ── Base combustion-character curves ──────────────────────
        -- These are the two fundamentally different torque-delivery shapes,
        -- selected by IgnitionType. Everything else (HEAD_SHAPE, CAM_MOD,
        -- runner length) is a MODIFIER applied on top of whichever base is
        -- selected — valve gear and cam tuning nudge the curve, but they don't
        -- change which combustion regime it belongs to.
        --
        -- PETROL_SHAPE (spark ignition, Otto cycle):
        --   Torque delivery is governed by breathing dynamics — cylinder fill
        --   improves through low-mid RPM as intake resonance and valve overlap
        --   become effective, peaks, then degrades from valve float and reduced
        --   time-per-cycle at high RPM. A gradual bell curve.
        --
        -- DIESEL_SHAPE (compression ignition):
        --   Torque delivery is governed by turbo boost availability and injector
        --   fuel-quantity/smoke limits, not breathing dynamics.
        --     • Full torque arrives fast and early (turbo diesels are known for
        --       near-peak torque just above idle) → rise_end sits much lower
        --       than petrol.
        --     • Torque then holds nearly FLAT across most of the operating range
        --       → fall_start sits much later than petrol, giving a plateau
        --       roughly twice as wide.
        --     • The falloff is a STEEP, NARROW cliff rather than a gradual
        --       rolloff — less crank-angle time per cycle to inject/burn the
        --       full charge at high RPM, and turbo boost collapses quickly once
        --       exhaust energy drops.
        local PETROL_SHAPE = { rise_end = 0.45, fall_start = 0.70, fall_end = 0.96 }
        local DIESEL_SHAPE = { rise_end = 0.28, fall_start = 0.86, fall_end = 1.00 }

        -- Volumetric Efficiency constants as fractions from which we build the curve. Still needs tuning...
        local VE_SAMPLES          = 24   -- resolution of the sampled output array
        local VE_RISE_SHARP_WIDTH = 0.05 -- fraction of the curve at which engines start picking up in torque
        local VE_PRE_IDLE_WIDTH   = 0.06 -- width as fraction of the curve where the engine generates almost no torque(before idleRPM)
        local VE_IDLE_FRACTION    = 0.35 -- fraction of torque generated at idle 
        local V_SOUND             = ACF.SpeedOfSound    -- m/s  (20°C air, close enough for intake calc)
        local RES_BONUS           = 0.06   -- max Gaussian VE bonus from intake resonance
        local RES_WIDTH           = 0.15   -- Gaussian σ in RPM-fraction units
        -- local SCAV_BONUS          = 0.04   -- max header-scavenging VE bonus
        -- local SCAV_PEAK           = 0.70   -- RPM fraction of peak scavenging
        -- local SCAV_WIDTH          = 0.20   -- Gaussian σ
        local CARB_KICK_IN        = 0.82   -- RPM fraction where carb venturi saturation begins
        local CARB_PENALTY        = 0.07   -- VE fraction lost at redline (carburetor only)
        local RUNNER_REF_CM       = 22.0   -- Default intake runner reference in centimeters
        local RUNNER_SHIFT_K      = 0.0025 -- RPM-fraction shift per cm of runner length difference
        local CR_REF_PETROL       = 9.0    -- matches CR petrol reference
        local CR_REF_DIESEL       = 18.0   -- typical modern turbodiesel CR
        local CR_RISE_SHIFT_K     = 0.0075 -- RPM-fraction shift per CR-unit of deviation

        --- Two-segment idle-anchored rise.  Guarantees ve(idleFrac) == VE_IDLE_FRACTION
        --- exactly, regardless of how far away rise_end sits — a single smoothstep
        --- from a below-idle zero point cannot make that guarantee (its value at
        --- idle depends on where idle happens to fall within the window, which
        --- varies unpredictably with head/cam/runner parameters and can land at
        --- or near zero, leaving the engine unable to sustain its own idle).
        ---
        --- Segment A: zero_start → idleFrac,  rises 0 → VE_IDLE_FRACTION
        --- Segment B: idleFrac   → rise_end,  rises VE_IDLE_FRACTION → 1.0
        local function IdleAnchoredRise(t, idleFrac, rise_end)
            local zero_start = max(0, idleFrac - VE_PRE_IDLE_WIDTH)

            if t <= zero_start then
                return 0
            elseif t <= idleFrac then
                return VE_IDLE_FRACTION * smoothstep(zero_start, idleFrac, t)
            else
                return VE_IDLE_FRACTION
                    + (1 - VE_IDLE_FRACTION) * smoothstep(idleFrac, rise_end, t)
            end
        end

        --- Computes a normalised volumetric-efficiency curve (0–1 values, peak = 1)
        --- from physical valve-train, intake, exhaust, and fuel-delivery parameters.
        --- Replaces the hand-authored TorqueCurve array that was before.
        ---
        --- Physical contributions (all additive on top of the base VE shape):
        ---   HeadType      → base plateau position and rolloff steepness
        ---   CamProfile    → RPM shift of the plateau and rolloff tightness
        ---   RunnerLength  → Gaussian resonance bonus at the Helmholtz RPM
        ---   ExhaustType   → header scavenging bonus in the upper-mid band
        ---   FuelDelivery  → carburetor venturi saturation penalty above 82% redline
        ---   IgnitionType  → glow/diesel: additional high-RPM VE suppression
        ---   isWankel      → replaces valve-train shape with Wankel port-timing model
        ---
        --- Returns a flat array of VE_SAMPLES normalised values evenly spaced 0→redline.
        local function BuildVECurve(headType, camProfile, runnerLen_cm, fuelDelivery, ignType, redlineRPM, isWankel, idleFrac, CR)

            idleFrac = Clamp(idleFrac or 0, 0, 0.35)

            -- ── Wankel port-timing model (overrides valve-train entirely) ──
            if isWankel then
                -- Characteristics: fast rise right at idle, broad plateau, moderate
                -- rolloff at high RPM. No per-cam adjustment — port timing is fixed
                -- by the rotor geometry.
                local rise_end = max(0.22, idleFrac + VE_RISE_SHARP_WIDTH)
                local pts = {}
                for i = 1, VE_SAMPLES do
                    local t  = (i - 1) / (VE_SAMPLES - 1)
                    local ve = IdleAnchoredRise(t, idleFrac, rise_end)
                            * (1 - smoothstep(0.73, 0.99, t))
                    -- Resonance bonus at ~65% redline (short runner)
                    local dr = (t - 0.65) / 0.16
                    ve = ve * (1 + 0.05 * exp(-0.5 * dr * dr))
                    pts[i] = Clamp(ve, 0, 1)
                end
                -- Normalise
                local peak = 0
                for _, v in ipairs(pts) do if v > peak then peak = v end end
                if peak > 0 then for i = 1, #pts do pts[i] = pts[i] / peak end end
                return pts
            end

            -- IgnitionType selects the fundamental combustion-character curve —
            -- petrol's gradual bell shape or diesel's early-plateau-then-cliff
            -- shape. HeadType no longer selects a shape outright; it MODIFIES
            -- whichever base was selected (see HEAD_SHAPE comment above).
            local base = (ignType == "glow") and DIESEL_SHAPE or PETROL_SHAPE
            local hmod = HEAD_SHAPE[headType] or HEAD_SHAPE.ohc
            local cam  = CAM_MOD[camProfile]  or CAM_MOD.stock

            -- Runner length shifts the plateau onset: long runners bias toward low RPM,
            -- short runners bias toward high RPM.
            local runner_shift = (RUNNER_REF_CM - (runnerLen_cm or RUNNER_REF_CM)) * RUNNER_SHIFT_K

            -- Rise completes at the (base + head modifier) plateau point, UNLESS
            -- idle sits close enough to it that the guaranteed sharp post-idle
            -- window would overrun it. In that case the sharp window wins so the
            -- rise never inverts (this only matters for unusually high-idle layouts).
            -- CR shift: higher-than-reference CR pulls rise_end earlier (faster
            -- climb to full torque); lower-than-reference CR pushes it later.
            local cr_ref   = (ignType == "glow") and CR_REF_DIESEL or CR_REF_PETROL
            local cr_shift = -CR_RISE_SHIFT_K * ((CR or cr_ref) - cr_ref)
            local rise_end = math.max(
                base.rise_end + hmod.rise_shift + cr_shift,
                idleFrac + VE_RISE_SHARP_WIDTH)

            local base_fall_width = base.fall_end - base.fall_start
            local fall_start      = base.fall_start + hmod.fall_shift + cam.shift + runner_shift
            local fall_width      = base_fall_width / hmod.fall_k / cam.fall_k
            local fall_end        = fall_start + fall_width
            -- Safety Clamp: fall can never begin before the rise has finished,
            -- which would otherwise invert the curve for extreme head/cam/runner combos.
            if fall_start <= rise_end then
                fall_start = rise_end + 0.05
                fall_end   = fall_start + fall_width
            end
            -- ── Intake resonance: Helmholtz RPM from runner length ─
            local resonance_frac = 0.55   -- fallback if no runner data
            if runnerLen_cm and runnerLen_cm > 0 then
                local res_rpm    = (V_SOUND / (4 * runnerLen_cm * 0.01)) * 60
                resonance_frac   = Clamp(res_rpm / redlineRPM, 0.1, 1.2)
            end

            -- ── Sample the curve ───────────────────────────────────
            local pts = {}
            for i = 1, VE_SAMPLES do
                local t = (i - 1) / (VE_SAMPLES - 1)   -- 0 to 1

                -- VE = 0 well below idle; guaranteed VE_IDLE_FRACTION exactly at
                -- idle; continues to rise_end; smooth fall after.
                local ve = IdleAnchoredRise(t, idleFrac, rise_end)
                    * (1 - smoothstep(fall_start, fall_end, t))

                -- Intake resonance Gaussian bonus (scales with base VE so it
                -- doesn't add a bump where the engine is otherwise dead)
                local dr = (t - resonance_frac) / RES_WIDTH
                ve = ve + ve * RES_BONUS * exp(-0.5 * dr * dr)

                --[[
                -- Header scavenging (upper-mid band bonus)
                if exhaustType == "header" then
                    local ds = (t - SCAV_PEAK) / SCAV_WIDTH
                    ve = ve + ve * SCAV_BONUS * exp(-0.5 * ds * ds)
                end
                ]]--
                -- Carburetor high-RPM penalty (venturi saturation)
                if fuelDelivery == "carburetor" and t > CARB_KICK_IN then
                    local pen = ((t - CARB_KICK_IN) / (1 - CARB_KICK_IN)) * CARB_PENALTY
                    ve = ve * (1 - pen)
                end

                pts[i] = Clamp(ve, 0, 1)
            end

            -- Normalise so peak = 1.0 (peak torque is set by BMEP, not by this array)
            local peak = 0
            for _, v in ipairs(pts) do if v > peak then peak = v end end
            if peak > 0 then for i = 1, #pts do pts[i] = pts[i] / peak end end

            return pts
        end

        -- ── Layout factors ────────────────────────────────────
        local Bore_cm      = Params.Bore
        local Stroke_cm    = Params.Stroke
        local Clearance_cm = Params.Clearance
        local Pistons      = Params.Pistons
        local PistonSpeed  = Params.PistonSpeed or CLASS.DEFAULT_PISTON_SPEED

        -- Validate clearance — must be positive and less than stroke
        Clearance_cm = Clamp(Clearance_cm, 0.05, Stroke_cm - 0.01)

        -- ── 1. Compression ratio (dimensionless — cm cancel) ──
        -- Clamped to a realistic range for the engine's ignition type.
        local crBounds = CR_BOUNDS[Params.IgnitionType] or CR_BOUNDS_DEFAULT
        local CR_raw   = 1 + Stroke_cm / Clearance_cm
        local CR       = Clamp(CR_raw, crBounds.min, crBounds.max)
        if CR ~= CR_raw then Clearance_cm = Stroke_cm / (CR - 1) end

        -- ── 2. Swept volume and displacement 
        -- V_swept (cm³) = π/4 × bore² × stroke
        -- V_total (cm³) = V_swept × Pistons  -- In cubic centimeters
        -- V_total (L)   = V_total × 0.001    -- In liters
        local V_swept_cm3 = (PI * 0.25) * Bore_cm * Bore_cm * Stroke_cm
        local V_total_cm3 = V_swept_cm3 * Pistons
        local V_total_L   = V_total_cm3 * 0.001

        -- ── 3. Compute base engine mass based on its block and recipient masses ───
        local Area = V_swept_cm3 / Stroke_cm

        local PistonsMass = Area * Pistons * CLASS.PistonMass_K
        local RodsMass    = V_total_cm3 * CLASS.RodMass_K
        local CrankMass   = V_total_cm3 * CLASS.CrankMass_K
        local BlockMass   = V_total_cm3 * CLASS.BlockMass_K * SUPER.CubicReductionFactor
        local HeadMass    = V_total_cm3 * CLASS.HeadMass_K * SUPER.CubicReductionFactor

        local ModelMass = PistonsMass + RodsMass + CrankMass + BlockMass + HeadMass

        -- Otto cycle thermal efficiency scaled by Compression Ratio effects.
        -- η_otto = 1 − (1/CR)^(γ-1)
        local eta_otto = 1 - (1 / CR) ^ (CLASS.Gamma - 1)

        -- ── 4. Peak torque via BMEP, scaled by CR's thermodynamic effect  ──────
        -- Higher CR extracts more mechanical work from the same combustion event 
        -- The multiplier is normalized against CR_TORQUE_REF (9.0) so TorqueScale
        -- keeps meaning "BMEP potential at CR 9". CR only scales output up
        -- or down from that baseline, it doesn't add a second independenttorque knob.
        local eta_otto_ref   = 1 - (1 / CR_TORQUE_REF) ^ (CLASS.Gamma - 1)
        local CR_torque_mult = eta_otto / eta_otto_ref
        -- T = BMEP_Pa × V_total_m³ / (4π)    [4-stroke cycle]
        local BMEP_Pa        = Params.TorqueScale * CLASS.BMEP_Scale * 1e5
        -- Calculate peak torque, scale by CR and apply volumetric efficiency layout bonus/penalty
        local peakTorque = ((BMEP_Pa * (V_total_L * 1e-3) / (4 * PI)) * CR_torque_mult) * (1 + (LayoutFactors.VEBonus or 0))

        -- ── 5. RPM Limit from mean piston speed ─────────────────
        -- RPM_max = 60 × v_piston / (2 × stroke_m)
        -- stroke_m = Stroke_cm × 0.01  →  inline
        local limitRPM = floor(60 * PistonSpeed / (2 * Stroke_cm * 0.01))

        -- ── 6. Idle RPM from bore/stroke ratio + layout ───────
        -- base_idle = 800 × √(bore/stroke)  [dimensionless ratio]
        -- BalanceFactor: smoother engines can idle lower; rougher need more RPM
        -- IdleRPMMult: layout-specific adjustment (Wankel idles higher; boxer lower)
        local base_idle = 800 * sqrt(Bore_cm / Stroke_cm)
        local bal_idle  = base_idle / max(LayoutFactors.BalanceFactor, 0.5)
        local idleRPM   = Clamp(floor(bal_idle * (LayoutFactors.IdleRPMMult or 1.0)), 300, 2200)

        -- ── 7. BSFC from Otto efficiency + CR + type ──────────
        -- η_otto = 1 − (1/CR)^(γ-1)
        -- η_real = CLASS.ETA_FRIC × η_otto
        -- BSFC   = 1 / (η_real × CLASS.LHV_KWH)          [kg/kWh, theoretical]
        -- Corrected by type ratio and layout BSFC multiplier:
        -- BSFC_eff = BSFC_theoretical × (typeBSFC / REF_BSFC) × BSFCMult
        local BSFC_base = 1 / (CLASS.ETA_FRIC * eta_otto * CLASS.LHV_KWH)
        local typeCorr  = (Params.Efficiency or CLASS.REF_BSFC) / CLASS.REF_BSFC
        local BSFC_eff  = BSFC_base * typeCorr * (LayoutFactors.BSFCMult or 1.0)

        -- ── 8. Heat generation coefficient ────────────────────
        -- Proportional to displacement; inversely proportional to CR.
        -- Higher CR → better thermal efficiency → less waste heat.
        local heatCoeff = CLASS.PistonMass_K * V_total_L * (9.0 / CR)

        -- ── 9. Flywheel inertia ───────────────────────────────
        -- I = Pistons × m_piston × stroke_m² × k_crank
        -- m_piston (kg) = PistonMass_K × bore_cm²
        -- Combined (inline): Pistons × PistonMass_K × bore² × stroke² × 1e-3
        -- Scaled by InertiaFactor for layout differences.
        local I_base = Pistons * CLASS.PistonMass_K * Bore_cm * Bore_cm * Stroke_cm * Stroke_cm * 0.1 -- 0.1 as 0.001 was having no inertia at all
        local inertia = I_base * (LayoutFactors.InertiaFactor or 1.0)

        -- ── 10. Torque curve — derived from physical parameters ───
        -- HeadType/CamProfile/etc; Are read from Params and are provided when the engine is first instanced.
        -- These parameters are yet not calculated by the client when it first attempts to spawn the engine
        -- So defaults are provided in their places instead. 
        -- TorqueCurve is no longer hand-made but instead the shape is fully computed.
        local isWankel = Params.Layout == "Wankel"
        local idleFrac = idleRPM / max(limitRPM, 1)
        local VECurve = BuildVECurve(
            Params.HeadType        or "ohc",
            Params.CamProfile      or "stock",
            Params.RunnerLength_cm or 22,
            --Params.ExhaustType     or "stock",
            Params.FuelDelivery    or "injection",
            Params.IgnitionType,
            limitRPM,
            isWankel, idleFrac, CR)

        -- ── 11. Torque curve ──────────────────────────────────────────
        local ct = BuildCurve(VECurve, peakTorque, limitRPM, idleRPM, V_total_L)

        -- ── 12. Compute model's size according to its displacement ────
        local Scale = 1.08 * pow(V_total_L, 0.30)

        -- ── 13. Assemble geometric table ──────────────────────────────
        local geometric = {
            -- Identity
            Layout             = Params.Layout,
            IsPiston           = true,
            IsWankel           = Params.Layout == "Wankel",
            BankAngle          = Params.BankAngle,
            BankCount          = Params.BankCount,
            -- Inputs (for HUD / GetStatus)
            BoreCm             = Bore_cm,
            StrokeCm           = Stroke_cm,
            ClearanceCm        = Clearance_cm,
            Pistons            = Pistons,
            ModelScale         = Scale,
            ScaledMass         = ModelMass,
            Sign               = Params.Sign .. Pistons, -- Sign of the engine, e.g: "I4", "V8", "Radial 7"
            -- Derived geometry
            CompressionRatio   = CR,
            SweptVolPerCyl     = V_swept_cm3 * 0.001,    -- In liters
            Displacement       = {InCubicCentimeters = V_total_cm3, InLiters = V_total_L},
            -- Performance
            LimitRPM           = limitRPM,
            IdleRPM            = idleRPM,
            BSFC               = BSFC_eff,
            HeatCoeff          = heatCoeff,
            FlywheelInertia    = inertia,
            -- Layout character
            BalanceFactor      = LayoutFactors.BalanceFactor or 1.0,
            TorqueSmoothness   = LayoutFactors.TorqueSmoothness or 1.0,
            FiringIrregularity = LayoutFactors.FiringIrregularity or 0.0,
            -- Ignition frequency: 4-stroke piston fires once every 2 revolutions.
            -- Wankel overrides this via GetLayoutFactors.SparksPerRev.
            SparksPerRev       = LayoutFactors.SparksPerRev or 0.5,
            -- Connecting-rod / crankshaft geometry
            -- RodRatio = rod length / crank radius.  Higher ratio = less side thrust.
            -- Empirical: 1.5 + (bore/stroke) × 0.4  (oversquare engines have shorter rods)
            RodRatio           = 1.5 + (Bore_cm / Stroke_cm) * 0.4,
            -- Big-end bearing journal diameter (empirical: bore × 0.27)
            BigEndDiam_cm      = Bore_cm * 0.27,
            -- Oil sump tilt sensitivity by layout.
            -- Layouts that override via LayoutFactors.OilSumpTiltWarn/Starve get their value;
            -- all others fall back to the baseline inline/single wet-sump defaults.
            -- Warn: Degrees of tilt before pressure drops
            -- Starve: Degrees of tilt for full starvation
            OilSumpTilt        = {Warn = LayoutFactors.OilSumpTiltWarn or 50, Starve = LayoutFactors.OilSumpTiltStarve or 90},
            -- Computed curves
            Curve              = {Torque = ct.T_Curve, Friction = ct.F_Curve, Steps = ct.Steps},
            VECurve            = VECurve,
            Sample             = ct.Sample,
            PeakPower          = ct.PeakPower,
            PeakTorque         = ct.PeakTorque,
            PowerBand          = ct.PowerBand,
            RedlineRPM         = ct.RedlineRPM,
            }
        return geometric
    end

    --====================================================================================--
    -- MENU CODE  
    --====================================================================================--
    -- I would have done this in a separate utility file named menues_cl.lua, however 
    -- several issues arised with this methodology that prevented me from doing so, not
    -- that i'm done with that idea but the fact that hot-updates don't quite work 
    -- (i am forced to retry in console everytime i need to make or test a change) threw 
    -- me off of that way. So instead menus will have to be done within the file/class that
    -- defines them.

    do
        local GetType = Classes.GetTypeByName
        local TankSize = Vector()

        function CLASS.CreateMenu(SubMenu, NestedData, PushData)
            local TypeSelector = Classes.CreateTypeSelector(SubMenu, CLASS, "EngineType")
            local ClassList    = TypeSelector.ComboBox

            local SubPanel = SubMenu:AddPanel("ACF_Panel")

            local function BuildMenu(SUPER, SuperMenu)
                local EngineDescLabel
                local BankAnglePanel
                local BankAmountPanel

                -- Variables to fetch any options from our Class Fields
                local ModelOpts     = Classes.GetTypeFieldByName(SUPER, "CustomEngineModel").Options
                local PistonOpts    = Classes.GetTypeFieldByName(SUPER, "CustomEnginePistons").Options
                local BoreOpts      = Classes.GetTypeFieldByName(SUPER, "CustomEngineBore").Options
                local StrokeOpts    = Classes.GetTypeFieldByName(SUPER, "CustomEngineStroke").Options
                local ClearanceOpts = Classes.GetTypeFieldByName(SUPER, "CustomEngineClearance").Options

                -- Clamps a raw compression ratio (derived from stroke/clearance) into the realistic range
                -- for the given fuel type, and back-corrects clearance to match if clamping changed it.
                local function ClampCR(Stroke, Clearance)
                    local __Stroke = Stroke or ACF.GetClientData("CustomEngineStroke", StrokeOpts.Default)
                    local __Clearance = Clearance or ACF.GetClientNumber("CustomEngineClearance", ClearanceOpts.Default)
                    local EngineType = ACF.GetClientData("EngineClass", "ACF.EngineTypes.GenericPetrol")
                    local FuelType = EngineType == "ACF.EngineTypes.GenericPetrol" and "spark" or "glow"

                    local CorrectedClearance = __Clearance
                    local Bounds = CR_BOUNDS[FuelType] or CR_BOUNDS_DEFAULT

                    local CR_raw = 1 + __Stroke / __Clearance
                    local CR     = Clamp(CR_raw, Bounds.min, Bounds.max)
                    if CR ~= CR_raw then CorrectedClearance = __Stroke / (CR - 1) end

                    -- Get the clamped limits
                    local Min = __Stroke / (Bounds.min - 1)
                    local Max = __Stroke / (Bounds.max - 1)

                    return CorrectedClearance, Min, Max
                end

                -- Local functions just to update our labels
                local function UpdatePreview(Panel, Data)
                    Panel:UpdateModel(Data)
                end

                local function UpdateEngineStats(Panel, Pistons, Bore, Stroke, Clearance)
                    local __Pistons   = Round(Pistons or ACF.GetClientNumber("CustomEnginePistons", PistonOpts.Default))
                    local __Bore      = Bore or ACF.GetClientNumber("CustomEngineBore", BoreOpts.Default)
                    local __Stroke    = Stroke or ACF.GetClientNumber("CustomEngineStroke", StrokeOpts.Default)
                    local __Clearance = Clearance or ACF.GetClientNumber("CustomEngineClearance", ClearanceOpts.Default)

                    -- ── Swept volume and displacement ──────────────────
                    -- V_swept (cm³) = π/4 × bore² × stroke
                    -- V_displ (L)   = V_swept × pistons × 0.001
                    -- The values above are also rounded to the nearest 2 decimals
                    local V_swept = Round((PI / 4) * __Bore * __Bore * __Stroke, 2)
                    local V_displ = Round(V_swept * __Pistons * 0.001, 2)
                    local CRatio  = Round(1 + __Stroke / __Clearance, 2)

                    local Label = ("Compression Ratio: %s:1\
                                    \nSwept Volume per piston: %s cm³\
                                    \nDisplacement: %s L"):format(CRatio, V_swept, V_displ)

                    Panel:SetText(Label)
                end

                local BankAngle = Classes.GetTypeFieldByName(SUPER, "CustomEngineBankAngle")
                local BankAngleOpts = BankAngle and BankAngle.Options

                local BankAmount = Classes.GetTypeFieldByName(SUPER, "CustomEngineBankAmount")
                local BankAmountOpts = BankAmount and BankAmount.Options

                local EngineBase = SuperMenu:AddCollapsible("#acf.menu.engines.engine_info", nil, "icon16/monitor_edit.png")
                local EngineName = EngineBase:AddTitle()
                local EngineDesc = EngineBase:AddLabel()

                EngineName:SetText(SUPER.Name)
                EngineDesc:SetText(SUPER.Description)

                local EnginePreview = EngineBase:AddModelPreview(nil, true, "Primary")
                local EngineStats = EngineBase:AddTitle()
                EngineStats:SetText("Engine Stats")
                EngineDescLabel = EngineBase:AddLabel()

                UpdateEngineStats(EngineDescLabel)
                UpdatePreview(EnginePreview, ACF.GetClientData("CustomEngineModel", ModelOpts.Default))

                local EngineConfig = SuperMenu:AddCollapsible("Engine Block Configuration", nil, "icon16/shape_square_edit.png")

                local Pistons = EngineConfig:AddSlider("Number of Pistons", PistonOpts.Min, PistonOpts.Max, PistonOpts.Decimals)
                Pistons:SetValue(ACF.GetClientNumber("CustomEnginePistons", NestedData.CustomEnginePistons or PistonOpts.Default))
                Pistons:SetClientData("CustomEnginePistons", "OnValueChanged")
                Pistons:DefineSetter(function(Panel, _, _, Value)
                    if PistonOpts.IsEvenNumber then
                        -- Enforce even cylinder count
                        Value = max(2, (Value % 2 == 0) and Value or Value - 1)
                    end
                    Panel:SetValue(Round(Value, PistonOpts.Decimals or 0))

                    -- Set the engine's preview model too
                    local ClassModel = SUPER.Model

                    NestedData.CustomEngineModel = (ClassModel):format(Round(Value, PistonOpts.Decimals or 0) or ModelOpts.Default)
                    ACF.SetClientData("CustomEngineModel", NestedData.CustomEngineModel)

                    UpdatePreview(EnginePreview, NestedData.CustomEngineModel)
                    UpdateEngineStats(EngineDescLabel, Value)
                    PushData()
                end)

                local Bore = EngineConfig:AddSlider("Piston Bore Size (cm)", BoreOpts.Min, BoreOpts.Max, BoreOpts.Decimals)
                Bore:SetValue(ACF.GetClientNumber("CustomEngineBore", NestedData.CustomEngineBore or BoreOpts.Default))
                Bore:SetClientData("CustomEngineBore", "OnValueChanged")
                Bore:DefineSetter(function(Panel, _, _, Value)
                    Panel:SetValue(Round(Value, BoreOpts.Decimals or 2))
                    UpdateEngineStats(EngineDescLabel, nil, Value)
                    PushData()
                end)

                local Stroke = EngineConfig:AddSlider("Piston Stroke Size (cm)", StrokeOpts.Min, StrokeOpts.Max, StrokeOpts.Decimals)
                Stroke:SetValue(ACF.GetClientNumber("CustomEngineStroke", NestedData.CustomEngineStroke or StrokeOpts.Default))
                Stroke:SetClientData("CustomEngineStroke", "OnValueChanged")

                local Clearance = EngineConfig:AddSlider("Piston TDC Clearance (cm)", ClearanceOpts.Min, ClearanceOpts.Max, ClearanceOpts.Decimals)
                Clearance:SetValue(ACF.GetClientNumber("CustomEngineClearance", NestedData.CustomEngineClearance or ClearanceOpts.Default))
                Clearance:SetClientData("CustomEngineClearance", "OnValueChanged")
                Clearance:DefineSetter(function(Panel, _, _, Value)
                    local CorrectedCR = ClampCR(Stroke:GetValue(), Value)

                    Panel:SetValue(Round(CorrectedCR, ClearanceOpts.Decimals or 2))
                    UpdateEngineStats(EngineDescLabel, nil, nil, nil, Value)
                    PushData()
                end)

                Stroke:DefineSetter(function(Panel, _, _, Value)
                    Panel:SetValue(Round(Value, StrokeOpts.Decimals or 2))

                    local _, CRMin, CRMax = ClampCR(Value, Clearance:GetValue())
                    Clearance:SetMinMax(CRMax, CRMin)

                    UpdateEngineStats(EngineDescLabel, nil, nil, Value, nil)
                    PushData()
                end)

                if BankAngleOpts then
                    BankAnglePanel = EngineConfig:AddSlider("Bank Angle", BankAngleOpts.Min, BankAngleOpts.Max, BankAngleOpts.Decimals)
                    BankAnglePanel:SetValue(ACF.GetClientNumber("CustomEngineBankAngle", NestedData.CustomEngineBankAngle or BankAngleOpts.Default))
                    BankAnglePanel:SetClientData("CustomEngineBankAngle", "OnValueChanged")
                    BankAnglePanel:DefineSetter(function(Panel, _, _, Value)
                        Panel:SetValue(Value)
                    end)
                end

                if BankAmountOpts then
                    BankAmountPanel = EngineConfig:AddSlider("Bank Amount", BankAmountOpts.Min, BankAmountOpts.Max, BankAmountOpts.Decimals)
                    BankAmountPanel:SetValue(ACF.GetClientNumber("CustomEngineBankAmount", NestedData.CustomEngineBankAmount or BankAmountOpts.Default))
                    BankAmountPanel:SetClientData("CustomEngineBankAmount", "OnValueChanged")
                    BankAmountPanel:DefineSetter(function(Panel, _, _, Value)
                        Panel:SetValue(Value)
                    end)
                end
            end

            function ClassList:OnSelect(Index, _, Data)
                if self.Selected == Data then return end

                self.ListData.Index = Index
                self.Selected = Data

                local TypeName = Classes.GetTypeName(ClassList.Selected)

                ACF.SetClientData("EngineType", TypeName)
                ACF.SetClientData("EngineClassData", ClassList.Selected)

                SubMenu:ClearTemporal(SubPanel)
                SubMenu:StartTemporal(SubPanel)

                BuildMenu(ClassList.Selected, SubPanel)

                SubMenu:EndTemporal(SubPanel)
            end

            ACF.SetClientData("PrimaryClass", "acf_engine_custom")
            ACF.SetClientData("SecondaryClass", "acf_fueltank")
            ACF.SetClientData("FuelTank", "Scalable") -- Set default fuel tank to scalable

            ACF.SetToolMode("acf_menu", "Spawner", "Engine") -- Just in case

            -- Fuel config labels and stuff 
            local FuelConfig = SubMenu:AddCollapsible("Fuel System Configuration", nil, "icon16/shape_square_edit.png")
            local EngineClass = FuelConfig:AddComboBox()
            EngineClass:AddChoice("Diesel Engine", "ACF.EngineTypes.GenericDiesel")
            EngineClass:AddChoice("Petrol Engine", "ACF.EngineTypes.GenericPetrol")
            EngineClass:SetValue("Petrol Engine") -- Filthy fucking hack, i hate this
            timer.Simple(0, function() if IsValid(EngineClass) then EngineClass:OnSelect(nil, nil, "ACF.EngineTypes.GenericPetrol") end end) -- smh

            local FuelType = FuelConfig:AddComboBox()
            --=========================================================================--
            -- RIGHT BELOW THIS CODE IS STRAIGHT UP COPIED FROM engines.lua MENU CODE  --
            --=========================================================================--
            -- Shape selector. The combo value is the ContainerShapes class FQN written straight into the
            -- "Shape" field; no string->class translation needed at spawn time.
            local FuelShape = FuelConfig:AddComboBox()
            FuelShape:AddChoice("Box", "ACF.ContainerShapes.Box")
            FuelShape:AddChoice("Sphere", "ACF.ContainerShapes.Sphere")
            FuelShape:AddChoice("Cylinder", "ACF.ContainerShapes.Cylinder")

            -- Set default shape
            local DefaultShape = ACF.GetClientData("Shape")
            if not GetType(DefaultShape) then DefaultShape = "ACF.ContainerShapes.Box" end
            ACF.SetClientData("Shape", DefaultShape, true)
            FuelShape:ChooseOptionID(DefaultShape == "ACF.ContainerShapes.Sphere" and 2 or DefaultShape == "ACF.ContainerShapes.Cylinder" and 3 or 1)
            timer.Simple(0, function() if IsValid(FuelShape) then FuelShape:OnSelect(nil, nil, DefaultShape) end end) -- Frown

            local Min = ACF.ContainerMinSize
            local Max = ACF.ContainerMaxSize
            local FuelPreview

            -- Set default fuel tank size values before creating sliders to prevent nil value errors
            local DefaultFuelSizeX = ACF.GetClientNumber("FuelSizeX", (Min + Max) / 2)
            local DefaultFuelSizeY = ACF.GetClientNumber("FuelSizeY", (Min + Max) / 2)
            local DefaultFuelSizeZ = ACF.GetClientNumber("FuelSizeZ", (Min + Max) / 2)
            ACF.SetClientData("FuelSizeX", DefaultFuelSizeX, true)
            ACF.SetClientData("FuelSizeY", DefaultFuelSizeY, true)
            ACF.SetClientData("FuelSizeZ", DefaultFuelSizeZ, true)

            local function UpdateSize()
                -- MARCH: STEVE REMOVE THIS ONCE YOU FIX IT (Or leave it if you are fine with this)
                ACF.SetClientData("Size", TankSize, true)
            end

            local SizeX = FuelConfig:AddSlider("#acf.menu.fuel.tank_length", Min, Max)
            SizeX:SetClientData("FuelSizeX", "OnValueChanged")
            SizeX:DefineSetter(function(Panel, _, _, Value)
                local X = Round(Value)

                Panel:SetValue(X)

                TankSize.x = X

                FuelType:UpdateFuelText()

                if FuelPreview then
                    FuelPreview:SetModelScale(TankSize * 12)
                end

                UpdateSize()
                return X
            end)

            local SizeY = FuelConfig:AddSlider("#acf.menu.fuel.tank_width", Min, Max)
            SizeY:SetClientData("FuelSizeY", "OnValueChanged")
            SizeY:DefineSetter(function(Panel, _, _, Value)
                local Y = Round(Value)

                Panel:SetValue(Y)

                TankSize.y = Y

                FuelType:UpdateFuelText()

                if FuelPreview then
                    FuelPreview:SetModelScale(TankSize * 12)
                end

                UpdateSize()
                return Y
            end)

            local SizeZ = FuelConfig:AddSlider("#acf.menu.fuel.tank_height", Min, Max)
            SizeZ:SetClientData("FuelSizeZ", "OnValueChanged")
            SizeZ:DefineSetter(function(Panel, _, _, Value)
                local Z = Round(Value)

                Panel:SetValue(Z)

                TankSize.z = Z

                FuelType:UpdateFuelText()

                if FuelPreview then
                    FuelPreview:SetModelScale(TankSize * 12)
                end

                UpdateSize()
                return Z
            end)

            local FuelBase = FuelConfig:AddCollapsible("#acf.menu.fuel.tank_info", nil, "icon16/cup_edit.png")
            local FuelDesc = FuelBase:AddLabel()
            FuelPreview = FuelBase:AddModelPreview(nil, true, "Secondary")
            local FuelInfo = FuelBase:AddLabel()

            function FuelShape:OnSelect(_, _, Data)
                ACF.SetClientData("Shape", Data)

                -- Update preview model based on shape
                local ShapeClass = GetType(Data) or GetType("ACF.ContainerShapes.Box")
                FuelPreview:UpdateModel(ShapeClass.Model, "models/props_canal/metalcrate001d")

                FuelType:UpdateFuelText()
            end

            -- We don't work with a preset list of engines, these are created on the run instead.
            function EngineClass:OnSelect(_, _, Data)
                if self.Selected == Data then return end

                self.Selected = Data

                local FuelData

                -- Shitty hack to get the type of fuel used for these engine Classes
                if Data == "ACF.EngineTypes.GenericPetrol" then
                    FuelData = "ACF.FuelTypes.Petrol"
                elseif Data == "ACF.EngineTypes.GenericDiesel" then
                    FuelData = "ACF.FuelTypes.Diesel"
                end

                local FuelDescription = GetType(FuelData)
                local Fuel = {FuelData = FuelDescription}

                ACF.SetClientData("EngineClass", Data)
                ACF.LoadSortedList(FuelType, Fuel, "ID")

                -- Call to Clamp the panel whenever we change fuel types
                -- local _, CRMin, CRMax = ClampCR()
                -- Clearance:SetMinMax(CRMax, CRMin)
            end

            function FuelType:OnSelect(Index, _, Data)
                if self.Selected == Data then return end

                self.ListData.Index = Index
                self.Selected = Data

                ACF.SetClientData("FuelType", Classes.GetTypeName(Data))

                self:UpdateFuelText()
            end

            function FuelType:UpdateFuelText()
                if not self.Selected then return end

                local TextFunc = self.Selected.FuelTankText
                local FuelText = ""

                local Wall = ACF.ContainerArmor * ACF.MmToInch -- Wall thickness in inches
                local Shape = GetType(ACF.GetClientData("Shape")) or GetType("ACF.ContainerShapes.Box")

                -- Calculate volume and area using shape calculations
                local Volume, Area = Shape.ShapeCalculation(TankSize, Wall)

                local Capacity	= Volume * ACF.gCmToKgIn -- Internal volume available for fuel in liters
                local EmptyMass	= Area * Wall * ACF.InchToCmCu * ACF.SteelDensity -- Total wall volume * cu in to cc * density of steel (kg/cc)
                local Mass		= EmptyMass + Capacity * self.Selected.Density -- Weight of tank + weight of fuel

                if TextFunc then
                    FuelText = FuelText .. TextFunc(Capacity, Mass, EmptyMass)
                else
                    local Text = language.GetPhrase("acf.menu.fuel.tank_stats")
                    local Liters = Round(Capacity, 2)
                    local Gallons = Round(Capacity * ACF.LToGal, 2)

                    FuelText = FuelText .. Text:format(ACF.ContainerArmor, Liters, Gallons, ACF.GetProperMass(Mass), ACF.GetProperMass(EmptyMass))
                end

                FuelDesc:SetText("Scalable Fuel Tank\n\nShape: " .. (Shape.Name or "Box"))
                FuelInfo:SetText(FuelText)
            end
        end
    end
end)    