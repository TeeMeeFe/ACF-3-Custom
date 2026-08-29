local ACF = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.CustomEngines.RotaryEngine", "ACF.CustomEngines.PistonBlock", function(CLASS, BASE)
    CLASS.Name                 = "Rotary Engine"
    CLASS.Description          = "A Wankel type engine"
    CLASS.Model                = "models/engines/wankel_%s_med.mdl"
    CLASS.Layout               = "Wankel"
    CLASS.IsScalable           = true
    CLASS.IsWankel             = true
    CLASS.CubicReductionFactor = 0.75 -- Inverse ratio of empty mass volume an engine has, so it doesn't scale like if it was a solid piece.
    CLASS.Sign                 = "R"
    CLASS.WankelPowerStrokes   = 3

    MENU_FIELD("String", "CustomEngineModel",     {Default = "models/engines/wankel_4_med.mdl"})
    MENU_FIELD("Number", "CustomEnginePistons",   {Min = 2,    Max = 4,  Default = 4,   Decimals = 0})
    -- Bore = rotor generating radius (R), Stroke = eccentricity (e)
    MENU_FIELD("Number", "CustomEngineBore",      {Min = 1,    Max = 20, Default = 4.0, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineStroke",    {Min = 0.5,  Max = 3,  Default = 1.0, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineClearance", {Min = 0.05, Max = 4,  Default = 0.5, Decimals = 2}) -- in Centimeters

    -- Wankels have no valves at all. Leaving these commented just for demonstration purposes.
    -- MENU_FIELD("String", "CustomEngineCylinderHead", {Default = "Pushrod"})
    -- MENU_FIELD("String", "CustomEngineCamshaftType", {Default = "Stock"})

    function CLASS.GetLayoutFactors(Pistons)
        if not Pistons then return end -- Rotors in this case

        return {
            InertiaFactor      = 0.35 + Pistons * 0.03, -- grows slightly with rotor count
            BalanceFactor      = 1.00,            -- no reciprocating mass, inherently smooth
            TorqueSmoothness   = 1.00,
            BSFCMult           = 1.15,            -- apex seal leakage penalty
            IdleRPMMult        = 1.60,            -- rotary idles at higher RPM
            VEBonus            = -0.12,           -- seal leakage reduces VE
            FiringIrregularity = 0.0,             -- always even firing
            -- Each rotor fires 3 times per shaft revolution (3 chambers, 120° apart)
            SparksPerRev       = CLASS.WankelPowerStrokes,
        }
    end

     function CLASS.Compute(_, Layout, Params, ...)
        local Args = unpack({...}) -- Unpack any extra args and store them here

        -- Append the layout, sign fields and the rest of the args
        Params.Layout       = CLASS.Layout
        Params.Sign         = CLASS.Sign
        Params.Efficiency   = Args.Efficiency
        Params.IgnitionType = Args.IgnitionType
        Params.PistonSpeed  = Args.PistonSpeed
        Params.TorqueScale  = Args.TorqueScale
        Params.TorqueCurve  = Args.TorqueCurve
        -- Params.HeadShape    = ACF.GetClientData("CustomEngineCylinderHead", Classes.GetTypeFieldByName(CLASS, "CustomEngineCylinderHead").Options.Default)
        -- Params.Cam_mod      = ACF.GetClientData("CustomEngineCamshaftType", Classes.GetTypeFieldByName(CLASS, "CustomEngineCamshaftType").Options.Default)

        -- The base class has the implementation of this method, so we redict this info there instead
        local Computed = BASE.Compute(CLASS, Layout, Params)

        return Computed
    end

    function CLASS.CreateMenu() end -- Must do to prevent a stack overflow somehow
end)