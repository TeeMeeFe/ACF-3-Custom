local ACF     = ACF
local istable = istable
local PI      = math.pi
local abs     = math.abs
local clamp   = math.Clamp
local floor   = math.floor
local exp     = math.exp
local min     = math.min
local max     = math.max
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

ACF.Classes.DefineClass("ACF.Engines.PistonBlock", "ACF.Engines.BlockType", function()
    CLASS.Name          = "Piston Block Class"
    CLASS.Description   = "The base class for any and all piston engines."
    CLASS.ToolDesc      = "Attempts to spawn the selected piston engine."
    CLASS.DefaultModel  = "models/holograms/cube.mdl"
    -- TODO: Some of these attributes should be defined per fuel type
    CLASS.Gamma         = 1.4       -- heat capacity ratio (diatomic air)
    CLASS.LHV_KWH       = 12.222222 -- 44000 / 3600 petrol lower heating value (kWh/kg).
    CLASS.ETA_FRIC      = 0.55      -- Otto → shaft efficiency fraction
    CLASS.BMEP_Scale    = 40        -- bar per unit of TorqueScale
    -- Inline calibrated piston mass: 0.5 g per cm² of bore area
    CLASS.PistonMass_K  = 0.0005    -- kg per cm² of bore cross-section
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

        -- ── Valve-train shape parameters ─────────────────────────
        -- All values are RPM fractions (0–1, relative to redline).
        -- rise_end:    RPM fraction where the VE plateau begins.
        -- fall_start:  RPM fraction where the rolloff begins.
        -- fall_end:    RPM fraction where VE reaches zero.
        local HEAD_SHAPE = {
            pushrod = { rise_end = 0.40, fall_start = 0.62, fall_end = 0.92 },
            ohc     = { rise_end = 0.45, fall_start = 0.70, fall_end = 0.96 },
            dohc    = { rise_end = 0.50, fall_start = 0.77, fall_end = 1.00 },
            none    = { rise_end = 0.43, fall_start = 0.67, fall_end = 0.94 },
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

        local VE_SAMPLES        = 24     -- resolution of the sampled output array
        local VE_RISE_START     = 0.02   -- rpm fraction where VE begins to rise from idle
        local V_SOUND           = ACF.SpeedOfSound    -- m/s  (15°C air, close enough for intake calc)
        local RES_BONUS         = 0.06   -- max Gaussian VE bonus from intake resonance
        local RES_WIDTH         = 0.15   -- Gaussian σ in RPM-fraction units
        local SCAV_BONUS        = 0.04   -- max header-scavenging VE bonus
        local SCAV_PEAK         = 0.70   -- RPM fraction of peak scavenging
        local SCAV_WIDTH        = 0.20   -- Gaussian σ
        local CARB_KICK_IN      = 0.82   -- RPM fraction where carb venturi saturation begins
        local CARB_PENALTY      = 0.07   -- VE fraction lost at redline (carburetor only)
        local DIESEL_LIMIT_S    = 0.70   -- RPM fraction where diesel VE starts to be throttled
        local DIESEL_LIMIT_E    = 0.86   -- RPM fraction where diesel VE suppression is full
        local DIESEL_SUPPRESS   = 0.35   -- Max fractional VE loss at the diesel RPM limit

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
        local function BuildVECurve(headType, camProfile, runnerLen_cm,
                                    exhaustType, fuelDelivery, ignType,
                                    redlineRPM, isWankel)

            -- ── Wankel port-timing model (overrides valve-train entirely) ──
            if isWankel then
                -- Wankel ports open/close by rotor position rather than a cam.
                -- Characteristics: fast rise, broad plateau, moderate rolloff at high RPM.
                -- Short intake runners (13B ≈ 14 cm) produce a mid-high resonance bonus.
                local pts = {}
                for i = 1, VE_SAMPLES do
                    local t  = (i - 1) / (VE_SAMPLES - 1)
                    local ve = smoothstep(0.01, 0.22, t)
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

            -- ── Valve-train base shape ─────────────────────────────
            local head = HEAD_SHAPE[headType] or HEAD_SHAPE.ohc
            local cam  = CAM_MOD[camProfile]  or CAM_MOD.stock

            -- Cam shift moves both the fall onset and the zero point
            local fall_start  = head.fall_start + cam.shift
            local fall_width  = (head.fall_end - head.fall_start) / cam.fall_k
            local fall_end    = fall_start + fall_width
            local rise_end    = head.rise_end   -- rise is not shifted by cam

            -- ── Intake resonance: Helmholtz RPM from runner length ─
            local resonance_frac = 0.55   -- fallback if no runner data
            if runnerLen_cm and runnerLen_cm > 0 then
                local res_rpm    = (V_SOUND / (4 * runnerLen_cm * 0.01)) * 60
                resonance_frac   = math.Clamp(res_rpm / redlineRPM, 0.1, 1.2)
            end

            -- ── Sample the curve ───────────────────────────────────
            local pts = {}
            for i = 1, VE_SAMPLES do
                local t = (i - 1) / (VE_SAMPLES - 1)   -- 0 to 1

                -- Base VE: smooth rise × smooth fall (trapezoidal with rounded edges)
                local ve = smoothstep(VE_RISE_START, rise_end, t)
                        * (1 - smoothstep(fall_start, fall_end, t))

                -- Intake resonance Gaussian bonus (scales with base VE so it
                -- doesn't add a bump where the engine is otherwise dead)
                local dr = (t - resonance_frac) / RES_WIDTH
                ve = ve + ve * RES_BONUS * math.exp(-0.5 * dr * dr)

                -- Header scavenging (upper-mid band bonus)
                if exhaustType == "header" then
                    local ds = (t - SCAV_PEAK) / SCAV_WIDTH
                    ve = ve + ve * SCAV_BONUS * math.exp(-0.5 * ds * ds)
                end

                -- Carburetor high-RPM penalty (venturi saturation)
                if fuelDelivery == "carburetor" and t > CARB_KICK_IN then
                    local pen = ((t - CARB_KICK_IN) / (1 - CARB_KICK_IN)) * CARB_PENALTY
                    ve = ve * (1 - pen)
                end

                -- Diesel/glow ignition: high-RPM VE suppression
                -- (cetane burn-rate and glow-plug thermal limit cap effective RPM)
                if ignType == "glow" then
                    local suppress = smoothstep(DIESEL_LIMIT_S, DIESEL_LIMIT_E, t)
                    ve = ve * (1 - suppress * DIESEL_SUPPRESS)
                end

                pts[i] = math.Clamp(ve, 0, 1)
            end

            -- Normalise so peak = 1.0 (peak torque is set by BMEP, not by this array)
            local peak = 0
            for _, v in ipairs(pts) do if v > peak then peak = v end end
            if peak > 0 then for i = 1, #pts do pts[i] = pts[i] / peak end end

            return pts
        end

        -- Insane coping cause i fucked up with my clanker spewing shit like this, will fix this in another time
        -- TypeDef would be the fuel type being used, taken from old engine code. We're using petrol here
        local TypeDef = {
            PistonSpeed = 20,
            TorqueScale = 0.25,
            --TorqueCurve = { 0, 0.1, 0.2, 0.4, 0.65, 0.85, 1, 0.9, 0.6 },
            Efficiency  = 0.304
        }
        -- ── Layout factors ────────────────────────────────────

        local Bore_cm      = Params.Bore
        local Stroke_cm    = Params.Stroke
        local Clearance_cm = Params.Clearance
        local Pistons      = Params.Pistons
        local PistonSpeed  = TypeDef.PistonSpeed or CLASS.DEFAULT_PISTON_SPEED

        -- Validate clearance — must be positive and less than stroke
        Clearance_cm = clamp(Clearance_cm, 0.05, Stroke_cm - 0.01)

        -- ── 1. Compression ratio (dimensionless — cm cancel) ──
        local CR = 1 + Stroke_cm / Clearance_cm

        -- ── 2. Swept volume and displacement ──────────────────
        -- V_swept (cm³) = π/4 × bore² × stroke
        -- V_total (cm³) = V_swept × Pistons  -- In cubic centimeters
        -- V_total (L)   = V_total × 0.001    -- In liters
        local V_swept_cm3 = (PI / 4) * Bore_cm * Bore_cm * Stroke_cm
        local V_total_cm3 = V_swept_cm3 * Pistons
        local V_total_L   = V_total_cm3 * 0.001

        -- ── 3. Peak torque via BMEP ───────────────────────────
        -- T = BMEP_Pa × V_total_m³ / (4π)    [4-stroke cycle]
        local BMEP_Pa    = TypeDef.TorqueScale * CLASS.BMEP_Scale * 1e5
        -- Wankel rotary: each rotor provides WANKEL_POWER_STROKES combustion
        -- events per shaft revolution instead of the 0.5 of a 4-stroke piston.
        -- BMEP formula stays the same (it's per-displacement), but we apply
        -- the firing-frequency bonus to effective peak torque via VEBonus.
        -- The key difference is captured in BSFCMult and IdleRPMMult.
        -- Apply volumetric efficiency layout bonus/penalty
        local peakTorque = (BMEP_Pa * (V_total_L * 1e-3) / (4 * PI)) * (1 + (LayoutFactors.VEBonus or 0))

        -- ── 4. Redline from mean piston speed ─────────────────
        -- RPM_max = 60 × v_piston / (2 × stroke_m)
        -- stroke_m = Stroke_cm × 0.01  →  inline
        local redlineRPM = floor(60 * PistonSpeed / (2 * Stroke_cm * 0.01))

        -- ── 5. Idle RPM from bore/stroke ratio + layout ───────
        -- base_idle = 800 × √(bore/stroke)  [dimensionless ratio]
        -- BalanceFactor: smoother engines can idle lower; rougher need more RPM
        -- IdleRPMMult: layout-specific adjustment (Wankel idles higher; boxer lower)
        local base_idle = 800 * sqrt(Bore_cm / Stroke_cm)
        local bal_idle  = base_idle / max(LayoutFactors.BalanceFactor, 0.5)
        local idleRPM   = clamp(floor(bal_idle * (LayoutFactors.IdleRPMMult or 1.0)), 300, 2200)

        -- ── 6. BSFC from Otto efficiency + CR + type ──────────
        -- η_otto = 1 − (1/CR)^(γ-1)
        -- η_real = CLASS.ETA_FRIC × η_otto
        -- BSFC   = 1 / (η_real × CLASS.LHV_KWH)          [kg/kWh, theoretical]
        -- Corrected by type ratio and layout BSFC multiplier:
        --   BSFC_eff = BSFC_theoretical × (typeBSFC / REF_BSFC) × BSFCMult
        local eta_otto  = 1 - (1 / CR) ^ (CLASS.Gamma  - 1)
        local BSFC_base = 1 / (CLASS.ETA_FRIC * eta_otto * CLASS.LHV_KWH)
        local typeCorr  = (TypeDef.Efficiency or CLASS.REF_BSFC) / CLASS.REF_BSFC
        local BSFC_eff  = BSFC_base * typeCorr * (LayoutFactors.BSFCMult or 1.0)

        -- ── 7. Heat generation coefficient ────────────────────
        -- Proportional to displacement; inversely proportional to CR.
        -- Higher CR → better thermal efficiency → less waste heat.
        local heatCoeff = CLASS.PistonMass_K * V_total_L * (9.0 / CR)

        -- ── 8. Flywheel inertia ───────────────────────────────
        -- I = Pistons × m_piston × stroke_m² × k_crank
        -- m_piston (kg) = PistonMass_K × bore_cm²
        -- Combined (inline): Pistons × PistonMass_K × bore² × stroke² × 1e-3
        -- Scaled by InertiaFactor for layout differences.
        local I_base = Pistons * CLASS.PistonMass_K * Bore_cm * Bore_cm * Stroke_cm * Stroke_cm * 1e-3
        local inertia = I_base * (LayoutFactors.InertiaFactor or 1.0)

        -- ── 9. Torque curve — derived from physical parameters ───
        -- HeadType/CamProfile/etc. are read from params (item-level override)
        -- then fall back to typeDef (engine-type default).
        -- TorqueCurve is no longer hand-authored; the shape is fully computed.
        local isWankel = (Params.Layout == "Wankel")
        local VECurve = BuildVECurve(
            Params.HeadType        or TypeDef.HeadType        or "ohc",
            Params.CamProfile      or TypeDef.CamProfile      or "stock",
            Params.RunnerLength_cm or TypeDef.RunnerLength_cm or 22,
            Params.ExhaustType     or TypeDef.ExhaustType     or "stock",
            Params.FuelDelivery    or TypeDef.FuelDelivery    or "injection",
            TypeDef.IgnitionType   or "spark",
            redlineRPM,
            isWankel)

        -- ── 10. Torque curve ───────────────────────────────────
        local ct = BuildCurve(VECurve, peakTorque, redlineRPM)

        -- ── 11. Assemble geometric table ────────────────────────────
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
        ACF.SetClientData("FuelTank", "ACF.FuelTanks.ScalableFuelTank") -- Set default fuel tank to scalable
    end
end)    