local ACF = ACF
local Classes = ACF.Classes
local Custom  = ACF.Custom

local PI  = math.pi
local pow = math.pow

-- Base electric block class definition
Classes.DefineClass("ACF.CustomEngines.ElectricBlock", "ACF.CustomEngines.BaseEngineBlock", function(CLASS)
    CLASS.Name         = "Electric Block Class"
    CLASS.Description  = "The base class for any and all types of electric motors."
    CLASS.ToolDesc     = "Attempts to spawn the selected electric motor."
    CLASS.Layout       = "Electric"
    CLASS.BMEP_Scale   = 40      -- Brake Mean Effective Pressure in bar per unit of TorqueScale
    CLASS.RotorMass_K  = 0.0028  -- kg per cm³
    CLASS.BlockMass_K  = 0.018   -- kg per cm³
    CLASS.StatorMass_K = 0.058   -- kg per cm³

    MENU_FIELD("ACF.CustomEngines.BaseEngineBlock", "BlockType", {
        "ACF.CustomEngines.GenericElectricalMotor",
        "ACF.CustomEngines.StarterMotor"
    })

    function CLASS.GetLayoutFactors()
        return {}  -- Not used
    end

    function CLASS.Compute(SUPER, Params, LayoutFactors)
        if not SUPER then return end -- TODO: Maybe another check here if its a class?
        if not Params and istable(Params) then return end
        if not LayoutFactors and istable(LayoutFactors) then return end

        local V_total_L  = Params.Displacement
        local BMEP_Pa    = (Params.TorqueScale or 0.5) * BMEP_SCALE * 1e5
        local PeakTorque = BMEP_Pa * (V_total_L * 1e-3) / (4 * PI)

        -- MaxRPM from TypeDef (electric motors can spin very fast)
        local MaxRPM     = Params.LimitRPM or 10000
        local IdleRPM    = 0 -- floor(MaxRPM * 0.02)   -- 2% of max (almost instant off idle)

        -- No BSFC (motor efficiency used instead by CustomEngineTypes class)
        local BSFC = 0

        -- Minimal internal heat (windings + iron losses, much less than combustion)
        local HeatCoeff = 0.001

        -- Rotor inertia: much lower than piston engine equivalent
        local Inertia = 0.03 -- kg per m²

        -- Model Mass: less parts than a piston engine, thus lighter weight
        local BlockMass = V_total_L * CLASS.BlockMass_K
        local RotorMass = V_total_L * CLASS.RotorMass_K
        local StatorMass = V_total_L * CLASS.StatorMass_K

        local ModelMass = BlockMass + RotorMass + StatorMass

        -- Model Scale: The same as piston block engines (For now)
        local Scale = 1.08 * pow(V_total_L, 0.30)

        local ct = Custom.BuildTorqueCurve(Params.TorqueCurve, PeakTorque, MaxRPM, nil, typeDef.PowerbandWidth)

        return {
            Layout             = CLASS.Layout,
            IsPiston           = false,
            IsWankel           = false,
            IsTurbine          = false,
            IsElectric         = true,
            BankAngle          = nil,
            BankCount          = nil,
            Bore               = nil,
            Stroke             = nil,
            Clearance          = nil,
            Pistons            = 0,
            CompressionRatio   = nil,
            SweptVolPerCyl     = nil,
            Displacement       = V_total_L,
            -- Electric motors have no valve/piston over-rev risk, so LimitRPM and RedlineRPM are the same value. 
            LimitRPM           = MaxRPM,
            IdleRPM            = IdleRPM,
            BSFC               = BSFC,
            HeatCoeff          = HeatCoeff,
            FlywheelInertia    = Inertia,
            BalanceFactor      = 1.00,
            TorqueSmoothness   = 1.00,
            FiringIrregularity = 0.00,
            ModelScale         = Scale,
            ScaledMass         = ModelMass,
            -- Power output and powerband
            Sample             = ct.Sample,
            PeakPower          = ct.PeakPower,
            PeakTorque         = ct.PeakTorque,
            PowerBand          = ct.PowerBand,
            RedlineRPM         = ct.RedlineRPM,
        }
    end

    function CLASS.CreateMenu() end
end)    