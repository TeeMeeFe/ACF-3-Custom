local ACF = ACF
local Compute = ACF.Compute or {}
ACF.Compute = Compute

local istable = istable
local Clamp   = math.Clamp
local PI      = math.pi
local floor   = math.floor
local sqrt    = math.sqrt
local max     = math.max
local pow     = math.pow

-- Gets the compression ratio bounds, keyed by ignition type, as well as their reference value.
function Compute.GetCRBounds()
    return {
        glow  = { min = 16, max = 22, ref = 18 }, -- diesel: compression-ignition requirement
        spark = { min = 7,  max = 16, ref = 9 },  -- petrol/other: knock-limited range
        default = spark
    }
end

-- MARK: CLASS.Compute
function Compute.PistonBlock(SUPER, LayoutFactors, Params)
    if not SUPER then return end -- TODO: Maybe another check here if its a class?
    if not Params and istable(Params) then return end
    if not LayoutFactors and istable(LayoutFactors) then return end

    -- Base class layout factors
    local Gamma        = Params.Gamma
    local LHV_KWH      = Params.LHV_KWH
    local ETA_FRIC     = Params.ETA_FRIC
    local BMEP_Scale   = Params.BMEP_Scale
    -- Base class mass calcs
    local PistonMass_K = Params.PistonMass_K
    local RodMass_K    = Params.RodMass_K
    local CrankMass_K  = Params.CrankMass_K
    local BlockMass_K  = Params.BlockMass_K
    local HeadMass_K   = Params.HeadMass_K
    local REF_BSFC     = Params.REF_BSFC
    -- Super class layout factors 
    local Bore         = Params.Bore      -- In centimeters
    local Stroke       = Params.Stroke    -- In centimeters
    local Clearance    = Params.Clearance -- In centimeters
    local Pistons      = Params.Pistons
    local PistonSpeed  = Params.PistonSpeed or Params.DEFAULT_PISTON_SPEED -- In meters per second

    -- Pre-validation steps.
    -- Stroke, if its a wankel we want it to be max 3cm of eccentricity.
    -- TODO: The number 3 is the actual class maximum, probably should fetch from there instead of hardcoding this.
    Stroke = Params.Layout == "Wankel" and Clamp(Stroke, 1, 3) or Stroke

    -- Clearance, must be positive and less than stroke
    Clearance = Clamp(Clearance, 0.05, Stroke - 0.01)

    -- 1. Compression ratio (dimensionless, cm cancel)
    -- Clamp Compression Ratio to a realistic value based on the engine's ignitionType/fuel type.
    local CRFunc   = Compute.GetCRBounds()
    local CRBounds = CRFunc[Params.IgnitionType] or CRFunc.default
    local CR_raw   = 1 + Stroke / Clearance
    local CR       = Clamp(CR_raw, CRBounds.min, CRBounds.max)
    if CR ~= CR_raw then Clearance = Stroke / (CR - 1) end

    -- 2. Swept volume and displacement 
    -- V_swept (cm³) = π/4 × bore² × stroke
    -- V_total (cm³) = V_swept × Pistons 
    -- V_total (L)   = V_total × 0.001  
    local V_swept_cm3 = (PI * 0.25) * Bore * Bore * Stroke
    local V_total_cm3 = V_swept_cm3 * Pistons
    local V_total_L   = V_total_cm3 * 0.001

    -- 3. Compute base engine mass based on its block and recipient masses
    local Area = V_swept_cm3 / Stroke

    local PistonsMass = Area * Pistons * PistonMass_K
    local RodsMass    = V_total_cm3 * RodMass_K
    local CrankMass   = V_total_cm3 * CrankMass_K
    local BlockMass   = V_total_cm3 * BlockMass_K * SUPER.CubicReductionFactor
    local HeadMass    = V_total_cm3 * HeadMass_K * SUPER.CubicReductionFactor

    local ModelMass = PistonsMass + RodsMass + CrankMass + BlockMass + HeadMass

    -- Otto cycle thermal efficiency scaled by Compression Ratio effects.
    -- η_otto = 1 − (1/CR)^(γ-1)
    local eta_otto = 1 - (1 / CR) ^ (Gamma - 1)

    -- 4. Peak torque via BMEP, scaled by CR's thermodynamic effect
    -- Higher CR extracts more mechanical work from the same combustion event 
    -- The multiplier is normalized against CR_TORQUE_REF (9.0) so TorqueScale
    -- keeps meaning "BMEP potential at CR 9". CR only scales output up
    -- or down from that baseline, it doesn't add a second independent torque knob.
    local eta_otto_ref   = 1 - (1 / CRFunc[Params.IgnitionType].ref) ^ (Gamma - 1)
    local CR_torque_mult = eta_otto / eta_otto_ref
    -- T = BMEP_Pa × V_total_m³ / (4π)    [4-stroke cycle]
    local BMEP_Pa        = Params.TorqueScale * BMEP_Scale * 1e5
    -- Calculate peak torque, scale by CR and apply volumetric efficiency layout bonus/penalty
    local PeakTorque = ((BMEP_Pa * (V_total_L * 1e-3) / (4 * PI)) * CR_torque_mult) * (1 + (LayoutFactors.VEBonus or 0))

    -- 5. RPM Limit from mean piston speed
    -- RPM_max = 60 × v_piston / (2 × stroke_m)
    -- stroke_m = Stroke × 0.01  →  inline
    local LimitRPM = floor(60 * PistonSpeed / (2 * Stroke * 0.01))

    -- 6. Idle RPM from bore/stroke ratio + layout
    -- Base_Idle = 800 × √(bore/stroke)  [dimensionless ratio]
    -- BalanceFactor: smoother engines can idle lower; rougher need more RPM
    -- IdleRPMMult: layout-specific adjustment (Wankel idles higher; boxer lower)
    local Base_Idle = 800 * sqrt(Bore / Stroke)
    local Bal_Idle  = Base_Idle / max(LayoutFactors.BalanceFactor, 0.5)
    local IdleRPM   = Clamp(floor(Bal_Idle * (LayoutFactors.IdleRPMMult or 1.0)), 300, 2200)

    -- 7. BSFC from Otto efficiency + CR + type
    -- η_otto = 1 − (1/CR)^(γ-1)
    -- η_real = CLASS.ETA_FRIC × η_otto
    -- BSFC   = 1 / (η_real × CLASS.LHV_KWH)  [kg/kWh, theoretical]
    -- Corrected by type ratio and layout BSFC multiplier:
    -- BSFC_eff = BSFC_theoretical × (typeBSFC / REF_BSFC) × BSFCMult
    local BSFC_base = 1 / (ETA_FRIC * eta_otto * LHV_KWH)
    local typeCorr  = (Params.Efficiency or REF_BSFC) / REF_BSFC
    local BSFC_eff  = BSFC_base * typeCorr * (LayoutFactors.BSFCMult or 1.0)

    -- 8. Heat generation coefficient 
    -- Proportional to displacement; inversely proportional to CR.
    -- Higher CR → better thermal efficiency → less waste heat.
    local heatCoeff = PistonMass_K * V_total_L * (CRBounds.ref / CR)

    -- 9. Flywheel inertia
    -- I = Pistons × m_piston × stroke_m² × k_crank
    -- m_piston (kg) = PistonMass_K × bore_cm²
    -- Combined (inline): Pistons × PistonMass_K × bore² × stroke² × 1e-3
    -- Scaled by InertiaFactor for layout differences.
    local I_base = Pistons * PistonMass_K * Bore * Bore * Stroke * Stroke * 0.1 -- 0.1 as 0.001 was having no inertia at all
    local Inertia = I_base * (LayoutFactors.InertiaFactor or 1.0)

    -- 10. Torque curve
    -- local IsWankel = Params.Layout == "Wankel"
    -- local IdleFrac = IdleRPM / max(LimitRPM, 1)
    -- local VECurve = BuildVECurve(
    --     Params.HeadType        or "ohc",
    --     Params.CamProfile      or "stock",
    --     Params.RunnerLength_cm or 22,
    --     --Params.ExhaustType     or "stock",
    --     Params.FuelDelivery    or "injection",
    --     Params.IgnitionType,
    --     LimitRPM,
    --     IsWankel, IdleFrac, CR)

    -- 11. Build the torque curve
    local ct = ACF.Custom.BuildTorqueCurve(Params.TorqueCurve, PeakTorque, LimitRPM, IdleRPM, V_total_L)

    -- 12. Compute model's size according to its displacement 
    local Scale = 1.08 * pow(V_total_L, 0.30)

    return {
        -- Identity
        Layout             = Params.Layout,
        IsPiston           = true,
        IsWankel           = Params.Layout == "Wankel",
        BankAngle          = Params.BankAngle,
        BankCount          = Params.BankCount,
        -- Inputs (for HUD / get status)
        Bore               = Bore,
        Stroke             = Stroke,
        Clearance          = Clearance,
        Pistons            = Pistons,
        ModelScale         = Scale,
        ScaledMass         = ModelMass,
        Sign               = Params.Sign .. Pistons, -- Sign of the engine, e.g: "I4", "V8", "Radial 7"
        -- Derived geometry
        CompressionRatio   = CR,
        SweptVolPerCyl     = V_swept_cm3 * 0.001,    -- In liters
        Displacement       = {InCubicCentimeters = V_total_cm3, InLiters = V_total_L},
        -- Performance
        LimitRPM           = LimitRPM,
        IdleRPM            = IdleRPM,
        BSFC               = BSFC_eff,
        HeatCoeff          = heatCoeff,
        FlywheelInertia    = Inertia,
        -- Layout character
        BalanceFactor      = LayoutFactors.BalanceFactor or 1.0,
        TorqueSmoothness   = LayoutFactors.TorqueSmoothness or 1.0,
        FiringIrregularity = LayoutFactors.FiringIrregularity or 0.0,
        -- Ignition frequency: 4-stroke piston fires once every 2 revolutions, Wankel overrides this.
        SparksPerRev       = LayoutFactors.SparksPerRev or 0.5,
        -- Connecting-rod / crankshaft geometry
        -- RodRatio = rod length / crank radius.  Higher ratio = less side thrust.
        -- Empirical: 1.5 + (bore/stroke) × 0.4  (oversquare engines have shorter rods)
        RodRatio           = 1.5 + (Bore / Stroke) * 0.4,
        -- Big-end bearing journal diameter (empirical: bore × 0.27)
        BigEndDiam         = Bore * 0.27,
        -- Oil sump tilt sensitivity by layout.
        -- Warn: Degrees of tilt before pressure begins to drop
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
end