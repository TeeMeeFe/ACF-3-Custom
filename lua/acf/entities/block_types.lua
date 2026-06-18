-- ============================================================
--  TODO: Uber sloppy file which i have yet to sanitize so it doesn't suck
--  This file is the base class from which the rest of the engines will
--  inherit from. It is required by other modules which will 
--  eventually be created. All downstream modules read from a data bus
--  without knowing which layout produced it.
--
--  ── Class hierarchy ───────────────────────────────────────────
--
--     BlockType           (abstract base — defines interface contract)
--     ├── PistonBlock     (all reciprocating engines, shared physics)
--     │    ├── InlineEngine        layout="inline"
--     │    ├── BoxerEngine         layout="boxer"
--     │    ├── V-TypeEngine        layout="v"         BankAngle required
--     │    ├── WR-TypeEngine       layout="wr"        BankAngle + BankCount
--     │    ├── RotaryEngine        layout="wankel"    Rotary geometry
--     |    ├── RadialEngine        layout="radial"    Radial engines
--     |    ├── SingleMonoEngine    layout="single"    Requires Balance shafts
--     |    └── ParallelTwinEngine  layout="twin"      Requires Balance shafts 
--     ├── TurbineBlock    (layout="turbine")    non-piston superclass
--     └── ElectricBlock   (layout="electric")   non-piston superclass
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
--  ── Entity parameters (set in shared.lua / spawner) ──────────
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
--  Non-piston engines:
--    Layout      string  "turbine"|"electric"
--    (No Bore/Stroke/Clearance — TypeDef provides all performance data)
--
--  ── Geo table shape (identical for all types) ─────────────────
--
--  All Compute() methods return a geo table with these keys so that
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
-- ============================================================

ACF.Classes.DefineClass("ACF.Engines.BlockType", function()
-- ──────────────────────────────────────────────────────────
--  Shared physical constants
-- ──────────────────────────────────────────────────────────
    CLASS.Name          = "Block Type Class"
    CLASS.Description   = "The base class for any and all types of engine blocks."
    -- TODO: Some of these attributes should be defined per fuel type
    CLASS.GAMMA         = 1.4       -- heat capacity ratio (diatomic air)
    CLASS.LHV_KWH       = 12.222222 -- 44000 / 3600 petrol lower heating value (kWh/kg).
    CLASS.ETA_FRIC      = 0.55      -- Otto → shaft efficiency fraction
    CLASS.BMEP_SCALE    = 40        -- bar per unit of TorqueScale
    -- Inline calibrated piston mass: 0.5 g per cm² of bore area
    CLASS.PISTON_MASS_K = 0.0005    -- kg per cm² of bore cross-section
    -- Base heat coefficient calibrated for 1.0 L, CR 9 petrol engine
    CLASS.HEAT_BASE     = 0.012
    -- Reference BSFC for type-correction ratio
    CLASS.REF_BSFC      = 0.304     -- kg/kWh  (GenericPetrol)
    -- Default piston speed limit if TypeDef does not specify one
    CLASS.DEFAULT_PISTON_SPEED = 20 -- m/s
    -- Wankel: power strokes per rotor per shaft revolution
    CLASS.WANKEL_POWER_STROKES = 3  -- TODO: This shouldn't be here IMHO

    -- ──────────────────────────────────────────────────────────
    --  Torque curve builder (shared by all layouts)
    -- ──────────────────────────────────────────────────────────

    --- Expand a normalised TorqueCurve array into a Nm lookup table.
    --- typeCurve: flat array {mult0, mult1, ...} 0-1, evenly spaced over RPM.
    --- @return table  {curve, steps, maxTorque, maxRPM, Sample}
    local function BuildCurve(typeCurve, peakTorque, maxRPM, steps)
        steps = steps or 200
        local n      = #typeCurve
        local curve  = {}
        for i = 0, steps do
            local pos   = (i / steps) * (n - 1)
            local idx0  = math.floor(pos)
            local idx1  = math.min(idx0 + 1, n - 1)
            local blend = pos - idx0
            local v0    = typeCurve[idx0 + 1] or 0
            local v1    = typeCurve[idx1 + 1] or 0
            curve[i]    = peakTorque * (v0 + blend * (v1 - v0))
        end

        local function Sample(rpm)
            rpm         = math.Clamp(rpm, 0, maxRPM)
            local frac  = (rpm / maxRPM) * steps
            local idx0  = math.floor(frac)
            local idx1  = math.min(idx0 + 1, steps)
            local blend = frac - idx0
            local v0    = curve[idx0] or 0
            local v1    = curve[idx1] or 0
            return v0 + blend * (v1 - v0)
        end

        return { curve = curve, steps = steps,
                maxTorque = peakTorque, maxRPM = maxRPM,
                Sample = Sample }
    end

    --- Must be overridden by each concrete layout.
    --- Returns a flat table of multipliers — see header for field list.
    function CLASS:GetLayoutFactors(params)
        error("EngineBlock:GetLayoutFactors() must be overridden by layout subclass")
    end

    --- Shared piston geometry computation.
    --- Concrete layouts call this after setting their own GetLayoutFactors.
    function CLASS:Compute(typeDef, params)
        local bore_cm      = params.Bore      or 4.0
        local stroke_cm    = params.Stroke    or 4.2
        local clearance_cm = params.Clearance or 0.5
        local pistons      = params.Pistons   or 4
        local pistonSpeed  = typeDef.PistonSpeed or CLASS.DEFAULT_PISTON_SPEED

        -- Validate clearance — must be positive and less than stroke
        clearance_cm = math.Clamp(clearance_cm, 0.05, stroke_cm - 0.01)

        -- ── Layout factors ────────────────────────────────────
        local f = CLASS:GetLayoutFactors(params)

        -- ── 1. Compression ratio (dimensionless — cm cancel) ──
        local CR = 1 + stroke_cm / clearance_cm

        -- ── 2. Swept volume and displacement ──────────────────
        -- V_swept (cm³) = π/4 × bore² × stroke
        -- V_total (L)   = V_swept × pistons × 0.001
        local V_swept_cm3 = (PI / 4) * bore_cm * bore_cm * stroke_cm
        local V_total_L   = V_swept_cm3 * pistons * 0.001

        -- Wankel rotary: each rotor provides WANKEL_POWER_STROKES combustion
        -- events per shaft revolution instead of the 0.5 of a 4-stroke piston.
        -- BMEP formula stays the same (it's per-displacement), but we apply
        -- the firing-frequency bonus to effective peak torque via VEBonus.
        -- The key difference is captured in BSFCMult and IdleRPMMult.

        -- ── 3. Peak torque via BMEP ───────────────────────────
        -- T = BMEP_Pa × V_total_m³ / (4π)    [4-stroke cycle]
        local BMEP_Pa    = typeDef.TorqueScale * BMEP_SCALE * 1e5
        local peakTorque = BMEP_Pa * (V_total_L * 1e-3) / (4 * PI)

        -- Apply volumetric efficiency layout bonus/penalty
        peakTorque = peakTorque * (1 + (f.VEBonus or 0))

        -- ── 4. Redline from mean piston speed ─────────────────
        -- RPM_max = 60 × v_piston / (2 × stroke_m)
        -- stroke_m = stroke_cm × 0.01  →  inline
        local redlineRPM = math.floor(60 * pistonSpeed / (2 * stroke_cm * 0.01))

        -- ── 5. Idle RPM from bore/stroke ratio + layout ───────
        -- base_idle = 800 × √(bore/stroke)  [dimensionless ratio]
        -- BalanceFactor: smoother engines can idle lower; rougher need more RPM
        -- IdleRPMMult: layout-specific adjustment (Wankel idles higher; boxer lower)
        local base_idle = 800 * math.sqrt(bore_cm / stroke_cm)
        local bal_idle  = base_idle / math.max(f.BalanceFactor, 0.5)
        local idleRPM   = math.Clamp(math.floor(bal_idle * (f.IdleRPMMult or 1.0)), 300, 2200)

        -- ── 6. BSFC from Otto efficiency + CR + type ──────────
        -- η_otto = 1 − (1/CR)^(γ-1)
        -- η_real = ETA_FRIC × η_otto
        -- BSFC   = 1 / (η_real × LHV_KWH)          [kg/kWh, theoretical]
        -- Corrected by type ratio and layout BSFC multiplier:
        --   BSFC_eff = BSFC_theoretical × (typeBSFC / REF_BSFC) × BSFCMult
        local eta_otto  = 1 - (1 / CR) ^ (GAMMA - 1)
        local BSFC_base = 1 / (ETA_FRIC * eta_otto * LHV_KWH)
        local typeCorr  = (typeDef.Efficiency or REF_BSFC) / REF_BSFC
        local BSFC_eff  = BSFC_base * typeCorr * (f.BSFCMult or 1.0)

        -- ── 7. Heat generation coefficient ────────────────────
        -- Proportional to displacement; inversely proportional to CR.
        -- Higher CR → better thermal efficiency → less waste heat.
        local heatCoeff = HEAT_BASE * V_total_L * (9.0 / CR)

        -- ── 8. Flywheel inertia ───────────────────────────────
        -- I = pistons × m_piston × stroke_m² × k_crank
        -- m_piston (kg) = PISTON_MASS_K × bore_cm²
        -- Combined (inline): pistons × PISTON_MASS_K × bore² × stroke² × 1e-3
        -- Scaled by InertiaFactor for layout differences.
        local I_base = pistons * PISTON_MASS_K * bore_cm * bore_cm * stroke_cm * stroke_cm * 1e-3
        local inertia = I_base * (f.InertiaFactor or 1.0)

        -- ── 9. Torque curve ───────────────────────────────────
        local ct = BuildCurve(typeDef.TorqueCurve, peakTorque, redlineRPM)

        -- ── 10. Assemble geo table ────────────────────────────
        local geo = {
            -- Identity
            Layout             = params.Layout or "inline",
            IsPiston           = true,
            IsWankel           = params.Layout == "wankel",
            IsTurbine          = false,
            IsElectric         = false,
            BankAngle          = params.BankAngle,
            BankCount          = params.BankCount,
            -- Inputs (for HUD / GetStatus)
            BoreCm             = bore_cm,
            StrokeCm           = stroke_cm,
            ClearanceCm        = clearance_cm,
            Pistons            = pistons,
            -- Derived geometry
            CompressionRatio   = CR,
            SweptVolPerCyl     = V_swept_cm3 * 0.001,   -- L
            Displacement       = V_total_L,               -- L
            -- Performance
            PeakTorque         = peakTorque,
            RedlineRPM         = redlineRPM,
            IdleRPM            = idleRPM,
            BSFC               = BSFC_eff,
            HeatCoeff          = heatCoeff,
            FlywheelInertia    = inertia,
            -- Layout character
            BalanceFactor      = f.BalanceFactor or 1.0,
            TorqueSmoothness   = f.TorqueSmoothness or 1.0,
            FiringIrregularity = f.FiringIrregularity or 0.0,
            -- Ignition frequency: 4-stroke piston fires once every 2 revolutions.
            -- Wankel overrides this via GetLayoutFactors.SparksPerRev.
            SparksPerRev       = f.SparksPerRev or 0.5,
            -- Connecting-rod / crankshaft geometry
            -- RodRatio = rod length / crank radius.  Higher ratio = less side thrust.
            -- Empirical: 1.5 + (bore/stroke) × 0.4  (oversquare engines have shorter rods)
            RodRatio           = 1.5 + (bore_cm / stroke_cm) * 0.4,
            -- Big-end bearing journal diameter (empirical: bore × 0.27)
            BigEndDiam_cm      = bore_cm * 0.27,
            -- Oil sump tilt sensitivity by layout.
            -- Layouts that override via f.OilSumpTiltWarn/Starve get their value;
            -- all others fall back to the baseline inline/single wet-sump defaults.
            OilSumpTiltWarn    = f.OilSumpTiltWarn   or 50,  -- ° tilt before pressure drops
            OilSumpTiltStarve  = f.OilSumpTiltStarve or 90,  -- ° tilt for full starvation
            -- Curve
            maxTorque          = ct.maxTorque,
            maxRPM             = ct.maxRPM,
            steps              = ct.steps,
            curve              = ct.curve,
            Sample             = ct.Sample,
            }
        return geo
    end
end)