local PI = math.pi
local clamp = math.Clamp
local floor = math.floor
local min = math.min
local max = math.max
local sqrt = math.sqrt

-- Base piston block class definition
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

    FIELD("ACF.Engines.PistonBlock", "EngineTypes", {
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
    --- @return table  {curve, steps, maxTorque, maxRPM, Sample}
    local function BuildCurve(typeCurve, peakTorque, maxRPM, steps)
        steps = steps or 20
        local n      = #typeCurve
        local curve  = {}
        for i = 0, steps do
            local pos   = (i / steps) * (n - 1)
            local idx0  = floor(pos)
            local idx1  = min(idx0 + 1, n - 1)
            local blend = pos - idx0
            local v0    = typeCurve[idx0 + 1] or 0
            local v1    = typeCurve[idx1 + 1] or 0
            curve[i]    = peakTorque * (v0 + blend * (v1 - v0))
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

        return { curve = curve,
                 steps = steps,
                 maxTorque = peakTorque,
                 maxRPM = maxRPM,
                 Sample = Sample }
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

        -- Insane coping cause i fucked up with my clanker spewing shit like this, will fix this in another time
        -- TypeDef would be the fuel type being used, taken from old engine code. We're using petrol here
        local TypeDef = {
            PistonSpeed = 20,
            TorqueScale = 1,
            TorqueCurve = { 0.4, 0.65, 0.85, 1, 0.9, 0.6 },
            Efficiency  = 0.304
        }
        -- ── Layout factors ────────────────────────────────────
        if not LayoutFactors then return end

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
        -- V_total (L)   = V_swept × Pistons × 0.001
        local V_swept_cm3 = (PI / 4) * Bore_cm * Bore_cm * Stroke_cm
        local V_total_L   = V_swept_cm3 * Pistons * 0.001

        -- Wankel rotary: each rotor provides WANKEL_POWER_STROKES combustion
        -- events per shaft revolution instead of the 0.5 of a 4-stroke piston.
        -- BMEP formula stays the same (it's per-displacement), but we apply
        -- the firing-frequency bonus to effective peak torque via VEBonus.
        -- The key difference is captured in BSFCMult and IdleRPMMult.
        -- ── 3. Peak torque via BMEP ───────────────────────────
        -- T = BMEP_Pa × V_total_m³ / (4π)    [4-stroke cycle]
        local BMEP_Pa    = TypeDef.TorqueScale * CLASS.BMEP_Scale * 1e5
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

        -- ── 9. Torque curve ───────────────────────────────────
        local ct = BuildCurve(TypeDef.TorqueCurve, peakTorque, redlineRPM)

        -- ── 10. Assemble geometric table ────────────────────────────
        local geometric = {
            -- Identity
            --Layout             = Params.Layout or "inline",
            IsPiston           = true,
            --IsWankel           = Params.Layout == "wankel",
            --IsTurbine          = false,
            --IsElectric         = false,
            BankAngle          = Params.BankAngle,
            BankCount          = Params.BankCount,
            -- Inputs (for HUD / GetStatus)
            BoreCm             = Bore_cm,
            StrokeCm           = Stroke_cm,
            ClearanceCm        = Clearance_cm,
            Pistons            = Pistons,
            -- Derived geometry
            CompressionRatio   = CR,
            SweptVolPerCyl     = V_swept_cm3 * 0.001,   -- L
            Displacement       = V_total_L,             -- L
            -- Performance
            PeakTorque         = peakTorque,
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
            OilSumpTiltWarn    = LayoutFactors.OilSumpTiltWarn   or 50,  -- ° tilt before pressure drops
            OilSumpTiltStarve  = LayoutFactors.OilSumpTiltStarve or 90,  -- ° tilt for full starvation
            -- Curve
            maxTorque          = ct.maxTorque,
            maxRPM             = ct.maxRPM,
            steps              = ct.steps,
            curve              = ct.curve,
            Sample             = ct.Sample,
            }
        return geometric
    end

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
        local TypeSelector = ACF.Classes.CreateTypeSelector(SubMenu, CLASS, "EngineTypes")
        local ClassList    = TypeSelector.ComboBox

        if ClassList and ClassList.Selected then
            local TypeName = ACF.Classes.GetTypeName(ClassList.Selected)
            ACF.SetClientData("CustomEngineClass", TypeName)
        end

        -- Set the tool's operations 
        ACF.SetClientData("PrimaryClass", "acf_engine_custom")
        ACF.SetClientData("SecondaryClass", "acf_fueltank")
        ACF.SetClientData("FuelTank", "ACF.FuelTanks.ScalableFuelTank") -- Set default fuel tank to scalable
    end
end)    