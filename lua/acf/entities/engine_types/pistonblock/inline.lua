local ACF         = ACF
local Classes     = ACF.Classes

Classes.DefineClass("ACF.Engines.InlineEngine", "ACF.Engines.PistonBlock", function()
    CLASS.Name                 = "Inline Engine"
    CLASS.Description          = "A piston engine in a inlined configuration"
    CLASS.Model                = "models/engines/inline%ss.mdl"
    CLASS.Layout               = "Inline"
    CLASS.IsScalable           = true
    CLASS.CubicReductionFactor = 0.75 -- Inverse ratio of empty mass volume an engine has, so it doesn't scale like if it was a solid piece.
    CLASS.Sign                 = "I"
    -- These attributes would be private if we had actual scaffolding for that
    local __INLINE_BAL = { [2] = 0.72, [3] = 0.78, [4] = 0.84, [5] = 0.88, [6] = 0.96, [7] = 0.98, [8] = 1.00 }
    local __INLINE_IDL = { [2] = 1.08, [3] = 1.05, [4] = 1.00, [5] = 0.97, [6] = 0.92, [7] = 0.90, [8] = 0.88 }

    MENU_FIELD("String", "CustomEngineModel",     {Default = "models/engines/inline4s.mdl"})
    MENU_FIELD("Number", "CustomEnginePistons",   {Min = 2,    Max = 6,  Default = 4,   Decimals = 0})
    MENU_FIELD("Number", "CustomEngineBore",      {Min = 1,    Max = 20, Default = 4.0, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineStroke",    {Min = 1,    Max = 20, Default = 4.2, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineClearance", {Min = 0.05, Max = 4,  Default = 0.5, Decimals = 2}) -- in Centimeters

    MENU_FIELD("String", "CustomEngineCylinderHead", {Default = "Pushrod"})
    MENU_FIELD("String", "CustomEngineCamshaftType", {Default = "Stock"})

    function CLASS.GetLayoutFactors(Pistons)
        if not Pistons then return end

        local bal = __INLINE_BAL[Pistons] or math.Clamp(0.72 + (Pistons - 3) * 0.05, 0.72, 1.00)
        local idl = __INLINE_IDL[Pistons] or math.Clamp(1.08 - (Pistons - 3) * 0.045, 0.88, 1.08)

        return {
            InertiaFactor      = 1.0 + 0.02 * Pistons, -- more pistons → more rotating mass
            BalanceFactor      = bal,
            TorqueSmoothness   = bal,            -- smoothness tracks balance for inline
            BSFCMult           = 1.00,
            IdleRPMMult        = idl,
            VEBonus            = 0.0,
            FiringIrregularity = 0.0,            -- always even firing
        }
    end

    function CLASS.Compute(_, Layout, Params, ...)
        local BASE = BASE
        local Args = unpack({...}) -- Unpack any extra args and store them here

        -- Append the layout, sign fields and the rest of the args
        Params.Layout       = CLASS.Layout
        Params.Sign         = CLASS.Sign
        Params.Efficiency   = Args.Efficiency
        Params.IgnitionType = Args.IgnitionType
        Params.PistonSpeed  = Args.PistonSpeed
        Params.TorqueScale  = Args.TorqueScale
        -- Params.HeadShape    = ACF.GetClientData("CustomEngineCylinderHead", Classes.GetTypeFieldByName(CLASS, "CustomEngineCylinderHead").Options.Default)
        -- Params.Cam_mod      = ACF.GetClientData("CustomEngineCamshaftType", Classes.GetTypeFieldByName(CLASS, "CustomEngineCamshaftType").Options.Default)

        -- The base class has the implementation of this method, so we redict this info there instead
        local Computed = BASE.Compute(CLASS, Layout, Params)

        return Computed
    end

    function CLASS.CreateMenu() end -- Must do to prevent a stack overflow somehow
end)
