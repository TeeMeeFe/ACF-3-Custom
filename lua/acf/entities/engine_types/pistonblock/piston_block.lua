local ACF     = ACF
local istable = istable
local PI      = math.pi
local abs     = math.abs
local clamp   = math.Clamp
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
--  ── Geo table shape (identical for all engine types) ──────────────────────
--
--  All Compute() methods must return a geo table with these keys so that
--  Combustion.lua and all downstream modules are layout-agnostic:
--
--    -- Geometry identity
--    Layout, BankAngle, BankCount, IsPiston, IsWankel, IsTurbine, IsElectric
--    -- Input parameters (stored for HUD / GetStatus)
--    BoreCm, StrokeCm, ClearanceCm, Pistons
--    -- Derived geometry (piston only; nil for non-piston)
--    CompressionRatio, SweptVolPerCyl, Displacement
--    -- Performance (all types)
--    PeakTorque, RedlineRPM, IdleRPM
--    BSFC, HeatCoeff, FlywheelInertia
--    TorqueSmoothness, BalanceFactor, FiringIrregularity
--    -- Torque curve (all types)
--    maxTorque, maxRPM, steps, curve
--    -- Sample method (closure over curve)
--    Sample(rpm) → Nm
--
-- ===========================================================================

ACF.Classes.DefineClass("ACF.Engines.PistonBlock", "ACF.Engines.BaseEngineBlock", function()
    CLASS.Name          = "Piston Block Class"
    CLASS.Description   = "The base class for any and all piston engines."
    CLASS.ToolDesc      = "Attempts to spawn the selected piston engine."
    CLASS.DefaultModel  = "models/holograms/cube.mdl"
    -- TODO: Some of these attributes should be defined per fuel type
    CLASS.Gamma         = 1.4       -- heat capacity ratio (diatomic air)
    CLASS.LHV_KWH       = 12.222222 -- 44000 / 3600 petrol lower heating value (kWh/kg).
    CLASS.ETA_FRIC      = 0.55      -- Otto → shaft efficiency fraction
    CLASS.BMEP_Scale    = 40        -- bar per unit of TorqueScale
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
    -- Default piston speed limit if TypeDef does not specify one
    CLASS.DEFAULT_PISTON_SPEED = 20 -- m/s
    -- Wankel: power strokes per rotor per shaft revolution
    --CLASS.WANKEL_POWER_STROKES = 3  -- TODO: This shouldn't be here IMHO

    MENU_FIELD("ACF.Engines.PistonBlock", "EngineType", {
        "InlineEngine",
        "BoxerEngine",
        "VTypeEngine",
        "WRTypeEngine",
        "RotaryEngine",
        "RadialEngine",
        "SingleMonoEngine",
        "ParallelTwinEngine"
    })

    -- ──────────────────────────────────────────────────────────
    --  Torque curve builder (shared by all layouts)
    -- ──────────────────────────────────────────────────────────
    --- Expand a normalised TorqueCurve array into a Nm lookup table.
    --- typeCurve: flat array {mult0, mult1, ...} 0-1, evenly spaced over RPM.
    --- @return table  {Curve:table, Steps:number, Sample:function, PeakPower:table, PeakTorque:table, PowerBand:table}
    local function BuildCurve(typeCurve, peakTorque, maxRPM, steps)
        local POWER_BAND_THRESHOLD = 0.80   -- fraction of peak power that defines the band edges
        local TWO_PI_OVER_60       = 2 * PI / 60
        local KWTOHP               = ACF.KwToHp
        local NMTOFTLB             = ACF.NmToFtLb

        steps = steps or 200
        local n      = #typeCurve
        local curve  = {}

        local peakKW          = 0
        local peakPowerAtRPM  = 0
        local peakTorqueAtRPM = 0

        local rpmStep = maxRPM / steps

        -- Compute the curve and define peaks 
        for i = 0, steps do
            local pos   = (i / steps) * (n - 1)
            local idx0  = floor(pos)
            local idx1  = min(idx0 + 1, n - 1)
            local blend = pos - idx0
            local v0    = typeCurve[idx0 + 1] or 0
            local v1    = typeCurve[idx1 + 1] or 0
            curve[i]    = peakTorque * (v0 + blend * (v1 - v0))

            local torque = curve[i]
            local rpm    = rpmStep * i

            if torque >= peakTorque then
                peakTorqueAtRPM = rpm
            end

            local power = torque * (rpm * TWO_PI_OVER_60) * 0.001

            if power > peakKW then
                peakKW         = power
                peakPowerAtRPM = rpm
            end
        end

        local function Sample(rpm)
            rpm         = clamp(rpm, 0, maxRPM)
            local frac  = (rpm / maxRPM) * steps
            local idx0  = floor(frac)
            local idx1  = min(idx0 + 1, steps)
            local blend = frac - idx0
            local v0    = curve[idx0] or 0
            local v1    = curve[idx1] or 0
            return v0 + blend * (v1 - v0)
        end

        -- Calculate Powerband
        local powerbandMin = 0
        local powerbandMax = 0

        local threshold = peakKW * POWER_BAND_THRESHOLD

        for i = 0, steps do
            local rpm = rpmStep * i
            local torque = curve[i]

            local power = torque * (rpm * TWO_PI_OVER_60) * 0.001

            if power > threshold then
                if powerbandMin == 0 then
                    powerbandMin = rpm
                end

                powerbandMax = rpm
            end
        end

        return {
            Curve       = curve,
            Steps       = steps,
            Sample      = Sample,
            PeakPower   = {InKW = peakKW, InHP = peakKW * KWTOHP, AtRPM = peakPowerAtRPM},
            PeakTorque  = {InNm = peakTorque, InFtLb = peakTorque * NMTOFTLB, AtRPM = peakTorqueAtRPM},
            PowerBand   = {Band = abs(powerbandMax - powerbandMin), Min = powerbandMin, Max = powerbandMax}
        }
    end


    --- Must be overridden by each concrete layout.
    --- Returns a flat table of multipliers — see header for field list.
    function CLASS.GetLayoutFactors(Params)
        error("PistonBlock:GetLayoutFactors() must be overridden by layout subclass")
    end

    --- Concrete layouts call this after setting their own GetLayoutFactors.
    function CLASS.Compute(SuperClass, LayoutFactors, Params)
        if not SuperClass then return end
        if not Params and istable(Params) then return end
        if not LayoutFactors and istable(LayoutFactors) then return end

        --- Cubic smoothstep: 0 at edge0, 1 at edge1, smooth S-curve between.
        local function smoothstep(edge0, edge1, x)
            local t = clamp((x - edge0) / (edge1 - edge0 + 1e-9), 0, 1)
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

        -- Volumetric Efficiency constants. From these we build the curve. Still needs tuning...
        local VE_SAMPLES          = 24    -- resolution of the sampled output array
        local VE_RISE_SHARP_WIDTH = 0.05
        local VE_PRE_IDLE_WIDTH   = 0.06
        local VE_IDLE_FRACTION    = 0.35
        local V_SOUND             = ACF.SpeedOfSound    -- m/s  (20°C air, close enough for intake calc)
        local RES_BONUS           = 0.06   -- max Gaussian VE bonus from intake resonance
        local RES_WIDTH           = 0.15   -- Gaussian σ in RPM-fraction units
        local SCAV_BONUS          = 0.04   -- max header-scavenging VE bonus
        local SCAV_PEAK           = 0.70   -- RPM fraction of peak scavenging
        local SCAV_WIDTH          = 0.20   -- Gaussian σ
        local CARB_KICK_IN        = 0.82   -- RPM fraction where carb venturi saturation begins
        local CARB_PENALTY        = 0.07   -- VE fraction lost at redline (carburetor only)
        local RUNNER_REF_CM       = 22.0   -- Default intake runner reference in centimeters
        local RUNNER_SHIFT_K      = 0.0025 -- RPM-fraction shift per cm of runner length difference

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
        --- Replaces the hand-authored TorqueCurve array on TypeDef.
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
        local function BuildVECurve(headType, camProfile, runnerLen_cm, fuelDelivery, ignType, redlineRPM, isWankel, idleFrac)

            idleFrac = clamp(idleFrac or 0, 0, 0.35)

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
                    pts[i] = clamp(ve, 0, 1)
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
            local rise_end = math.max(base.rise_end + hmod.rise_shift, idleFrac + VE_RISE_SHARP_WIDTH)

            local base_fall_width = base.fall_end - base.fall_start
            local fall_start      = base.fall_start + hmod.fall_shift + cam.shift + runner_shift
            local fall_width      = base_fall_width / hmod.fall_k / cam.fall_k
            local fall_end        = fall_start + fall_width
            -- Safety clamp: fall can never begin before the rise has finished,
            -- which would otherwise invert the curve for extreme head/cam/runner combos.
            if fall_start <= rise_end then
                fall_start = rise_end + 0.05
                fall_end   = fall_start + fall_width
            end
            -- ── Intake resonance: Helmholtz RPM from runner length ─
            local resonance_frac = 0.55   -- fallback if no runner data
            if runnerLen_cm and runnerLen_cm > 0 then
                local res_rpm    = (V_SOUND / (4 * runnerLen_cm * 0.01)) * 60
                resonance_frac   = clamp(res_rpm / redlineRPM, 0.1, 1.2)
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

                pts[i] = clamp(ve, 0, 1)
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
        Clearance_cm = clamp(Clearance_cm, 0.05, Stroke_cm - 0.01)

        -- ── 1. Compression ratio (dimensionless — cm cancel) ──
        local CR = 1 + Stroke_cm / Clearance_cm

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
        local BlockMass   = V_total_cm3 * CLASS.BlockMass_K * SuperClass.CubicReductionFactor
        local HeadMass    = V_total_cm3 * CLASS.HeadMass_K * SuperClass.CubicReductionFactor

        local ModelMass = PistonsMass + RodsMass + CrankMass + BlockMass + HeadMass

        -- local ModelMass = BaseMass * (V_total_L ^ (3 * SuperClass.CubicReductionFactor))

        -- ── 4. Peak torque via BMEP ───────────────────────────
        -- T = BMEP_Pa × V_total_m³ / (4π)    [4-stroke cycle]
        local BMEP_Pa    = Params.TorqueScale * CLASS.BMEP_Scale * 1e5
        -- Wankel rotary: each rotor provides WANKEL_POWER_STROKES combustion
        -- events per shaft revolution instead of the 0.5 of a 4-stroke piston.
        -- BMEP formula stays the same (it's per-displacement), but we apply
        -- the firing-frequency bonus to effective peak torque via VEBonus.
        -- The key difference is captured in BSFCMult and IdleRPMMult.
        -- Apply volumetric efficiency layout bonus/penalty
        local peakTorque = (BMEP_Pa * (V_total_L * 1e-3) / (4 * PI)) * (1 + (LayoutFactors.VEBonus or 0))

        -- ── 5. Redline from mean piston speed ─────────────────
        -- RPM_max = 60 × v_piston / (2 × stroke_m)
        -- stroke_m = Stroke_cm × 0.01  →  inline
        local redlineRPM = floor(60 * PistonSpeed / (2 * Stroke_cm * 0.01))

        -- ── 6. Idle RPM from bore/stroke ratio + layout ───────
        -- base_idle = 800 × √(bore/stroke)  [dimensionless ratio]
        -- BalanceFactor: smoother engines can idle lower; rougher need more RPM
        -- IdleRPMMult: layout-specific adjustment (Wankel idles higher; boxer lower)
        local base_idle = 800 * sqrt(Bore_cm / Stroke_cm)
        local bal_idle  = base_idle / max(LayoutFactors.BalanceFactor, 0.5)
        local idleRPM   = clamp(floor(bal_idle * (LayoutFactors.IdleRPMMult or 1.0)), 300, 2200)

        -- ── 7. BSFC from Otto efficiency + CR + type ──────────
        -- η_otto = 1 − (1/CR)^(γ-1)
        -- η_real = CLASS.ETA_FRIC × η_otto
        -- BSFC   = 1 / (η_real × CLASS.LHV_KWH)          [kg/kWh, theoretical]
        -- Corrected by type ratio and layout BSFC multiplier:
        -- BSFC_eff = BSFC_theoretical × (typeBSFC / REF_BSFC) × BSFCMult
        local eta_otto  = 1 - (1 / CR) ^ (CLASS.Gamma  - 1)
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
        local idleFrac = idleRPM / max(redlineRPM, 1)
        local VECurve = BuildVECurve(
            Params.HeadType        or "ohc",
            Params.CamProfile      or "stock",
            Params.RunnerLength_cm or 22,
            --Params.ExhaustType     or "stock",
            Params.FuelDelivery    or "injection",
            Params.IgnitionType,
            redlineRPM,
            isWankel, idleFrac)

        -- ── 11. Torque curve ──────────────────────────────────────────
        local ct = BuildCurve(VECurve, peakTorque, redlineRPM)

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
            RedlineRPM         = redlineRPM,
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
            -- Curve
            TorqueCurve        = {Curve = ct.Curve, Steps = ct.Steps},
            VECurve            = VECurve,
            Sample             = ct.Sample,
            PeakPower          = ct.PeakPower,
            PeakTorque         = ct.PeakTorque,
            PowerBand          = ct.PowerBand,
            }
        return geometric
    end

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
        local TypeSelector = ACF.Classes.CreateTypeSelector(SubMenu, CLASS, "EngineType")
        local ClassList    = TypeSelector.ComboBox

        if ClassList and ClassList.Selected then
            local TypeName = ACF.Classes.GetTypeName(ClassList.Selected)
            ACF.SetClientData("EngineType", TypeName)
        end

        -- Set the tool's operations 
        ACF.SetClientData("PrimaryClass", "acf_engine_custom")
        ACF.SetClientData("SecondaryClass", "acf_fueltank")
        ACF.SetClientData("FuelTank", "Scalable") -- Set default fuel tank to scalable

        ACF.SetToolMode("acf_menu", "Spawner", "Engine") -- Just in case
    end
end)    