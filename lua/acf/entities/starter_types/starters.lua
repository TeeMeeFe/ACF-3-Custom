ACF.Classes.DefineClass("ACF.CustomEngines.Starters", function() end)

ACF.Classes.DefineClass("ACF.CustomEngines.ElectricMotor", "ACF.CustomEngines.Starters", function(CLASS, BASE)
    CLASS.Name         = "Electric Starter Motor"
    CLASS.Description  = "An electric motor meant to be used to start engines of varying sizes and layouts"
    CLASS.CanMenuSpawn = false
    CLASS.Model        = "models/acf/core/t_drive_e.mdl"-- "models/engines/emotor-standalone-tiny.mdl"
    CLASS.SoundPath    = "acf_custom/starter/ignition_loop.wav"
    CLASS.MaxDisplacement = ACF.MaxDispForElecStarter
    CLASS.RotorMass_K  = 0.0028  -- kg per cm³
    CLASS.BlockMass_K  = 0.018   -- kg per cm³
    CLASS.StatorMass_K = 0.058   -- kg per cm³

    -- Minimum cranking RPM needed for combustion to fire reliably:
    -- Petrol (spark): ~100 RPM, spark can ignite at low compression heat.
    -- Diesel (glow):  ~180 RPM, needs higher compression heat for self-ignition; 
    -- Cranking too slowly won't reach ignition temperature even with glow plug assist.
    local CRANK_RPM_PETROL = 100
    local CRANK_RPM_DIESEL = 180

    --- Given the fact that this class is exclusively used for engine starters, this works differently from its sibling class.
    --- This one instead just computes one thing, torque base, used to scale up based on displacement, to a maximum defined in this class.
    --- @param Params:table ;The table with the engine parameters.
    --- @return number|nil ;The minimum torque needed to start the engine, or nil if we exceed the maximum displacement.
    function CLASS.Compute(_, _, Params)
        local Displacement = istable(Params.Displacement) and Params.Displacement.InLiters or Params.Displacement
        if not Displacement then return end

        local MaxDisplacement = CLASS.MaxDisplacement
        if Displacement > MaxDisplacement then return end

        local IdleRPM      = Params.IdleRPM
        local IgnitionType = Params.IgnitionType

        -- Assembly friction calibration
        -- T_fric = K_FRIC × μ_norm × RPM ^ ACF.FrictionalRPMExponent × Displacement
        -- Calibrated: 7.4 Nm at idle (850 RPM), 90 °C, 1.8 L
        local K_FRIC = 7.4 / (IdleRPM ^ ACF.FrictionalRPMExponent * Displacement)

        local CrankRPM = (IgnitionType == "glow") and CRANK_RPM_DIESEL or CRANK_RPM_PETROL
        -- Torque the electric motor generates when at stall (0 RPM)
        local TorqueStall = K_FRIC * (CrankRPM ^ ACF.FrictionalRPMExponent) * Displacement

        -- Get the mass too, its computed by the base class so we selectively take and calculate it ourselves. 
        local BlockMass  = Displacement * CLASS.BlockMass_K
        local RotorMass  = Displacement * CLASS.RotorMass_K
        local StatorMass = Displacement * CLASS.StatorMass_K

        local ModelMass = BlockMass + RotorMass + StatorMass

        return {
            TorqueStall = TorqueStall,
            ScaledMass = ModelMass,
            CrankRPM = CrankRPM
        }
    end
    -- I gotta do something about this shit, it cannot update
    function CLASS.CreateMenu(SubMenu, Context)
        Context.IdleRPM = 850 -- Hardcoded estimate
        Context.IgnitionType = Context.EngineType.IgnitionType

        local Computed = CLASS.Compute(_, _, Context)

        SubMenu:AddModelPreview(CLASS.Model, true, "Tertiary")
        SubMenu:AddLabel(
            "Torque: " .. math.Round(Computed.TorqueStall, 2) .. "Nm \n" ..
            "Mass: " .. math.Round(Computed.ScaledMass, 2) .. "Kg \n" ..
            "RPM: " .. Computed.CrankRPM)
    end
end)