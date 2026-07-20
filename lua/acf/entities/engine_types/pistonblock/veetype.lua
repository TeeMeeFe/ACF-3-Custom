local ACF     = ACF
local Classes = ACF.Classes

local abs     = math.abs
local max     = math.max
local Clamp   = math.Clamp

Classes.DefineClass("ACF.Engines.VTypeEngine", "ACF.Engines.PistonBlock", function()
    CLASS.Name                 = "V-Type Engine"
    CLASS.Description          = "A piston engine in a V configuration"
    CLASS.Model                = "models/engines/v%ss.mdl"
    CLASS.Layout               = "V-Type"
    CLASS.IsScalable           = true
    CLASS.CubicReductionFactor = 0.75 -- Inverse ratio of empty mass volume an engine has, so it doesn't scale like if it was a solid piece.
    CLASS.Sign                 = "V"

    MENU_FIELD("String", "CustomEngineModel",     {Default = "models/engines/v8s.mdl"})
    MENU_FIELD("Number", "CustomEnginePistons",   {Min = 4,    Max = 12, Default = 8,   Decimals = 0, IsEvenNumber = true})
    MENU_FIELD("Number", "CustomEngineBore",      {Min = 1,    Max = 20, Default = 4.0, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineStroke",    {Min = 1,    Max = 20, Default = 4.2, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineClearance", {Min = 0.05, Max = 4,  Default = 0.5, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineBankAngle", {Min = 60,   Max = 120, Default = 90, Decimals = 0}) -- in Degrees

    MENU_FIELD("String", "CustomEngineCylinderHead", {Default = "Pushrod"})
    MENU_FIELD("String", "CustomEngineCamshaftType", {Default = "Stock"})

    -- Two banks of cylinders at BankAngle degrees.  Common angles:
    --   60° V6  — compact but inherently uneven without shared crank pins
    --   72° V10 — even firing by geometry
    --   90° V8  — even with flat-plane crank; cross-plane is irregular
    --  120° V6  — equivalent to inline 6 in firing balance
    --
    -- FiringIrregularity is computed from the deviation of BankAngle
    -- from the even-firing ideal (720/N degrees).  A 90° V8 has zero
    -- irregularity (bank angle equals even interval); a 60° V6 does not.
    --
    -- InertiaFactor grows with BankAngle: a wider V requires more crank
    -- journal offset mass and a heavier, wider block.
    function CLASS.GetLayoutFactors(Pistons, Angle)
        if not Pistons then return end

        -- Enforce even cylinder count (two equal banks)
        Pistons = max(2, (Pistons % 2 == 0) and Pistons or Pistons - 1)

        local even_interval = 720 / Pistons           -- ideal even firing interval (°)
        -- Firing irregularity: normalised deviation of bank angle from ideal
        local irr = Clamp(abs(Angle - even_interval) / 720, 0, 1)

        -- Balance and smoothness degrade with irregularity
        local bal    = max(0.80, 1.0 - irr * 0.30)
        local smooth = max(0.75, 1.0 - irr * 0.40)

        -- Inertia: wider V → longer crankshaft journals → more mass
        local I_factor = 1.0 + Angle / 1800 -- 90° → 1.05; 60° → 1.033

        -- Idle RPM: uneven V-types need slightly higher idle to stay stable
        local idle_mult = 0.95 - irr * 0.10

        return {
            InertiaFactor      = I_factor,
            BalanceFactor      = bal,
            TorqueSmoothness   = smooth,
            BSFCMult           = 1.00,
            IdleRPMMult        = idle_mult,
            VEBonus            = -0.01, -- slightly longer intake runners
            FiringIrregularity = irr,
            -- V engines: sump sits below the V valley, slightly offset from
            -- the engine centreline → reduced tilt tolerance vs inline.
            OilSumpTiltWarn    = 47,
            OilSumpTiltStarve  = 88,
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