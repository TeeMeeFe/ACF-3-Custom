ACF.Classes.DefineClass("ACF.Engines.PistonBlock.EngineTypes.InlineEngine", "ACF.Engines.PistonBlock", function()
    CLASS.Name         = "Inline Engine"
    CLASS.Description  = "A piston engine in a inlined configuration"
    -- These attributes would be private if we had actual scaffolding for that
    local __INLINE_BAL = { [2] = 0.72, [3] = 0.78, [4] = 0.84, [5] = 0.88, [6] = 0.96, [7] = 0.98, [8] = 1.00 }
    local __INLINE_IDL = { [2] = 1.08, [3] = 1.05, [4] = 1.00, [5] = 0.97, [6] = 0.92, [7] = 0.90, [8] = 0.88 }

    FIELD("Number", "EnginePistons",   {Min = 2,    Max = 8,  Default = 4,   Decimals = 0})
    FIELD("Number", "EngineBore",      {Min = 0.1,  Max = 10, Default = 4.0, Decimals = 2}) -- in Centimeters
    FIELD("Number", "EngineStroke",    {Min = 0.1,  Max = 10, Default = 4.2, Decimals = 2}) -- in Centimeters
    FIELD("Number", "EngineClearance", {Min = 0.05, Max = 1,  Default = 0.5, Decimals = 2}) -- in Centimeters

    function CLASS.GetLayoutFactors()
        local N = CLASS.EnginePistons
        if not N then return end

        local bal = __INLINE_BAL[N] or math.Clamp(0.72 + (N - 3) * 0.05, 0.72, 1.00)
        local idl = __INLINE_IDL[N] or math.Clamp(1.08 - (N - 3) * 0.045, 0.88, 1.08)

        PrintTable({N, bal, idl})
        return {
            InertiaFactor      = 1.0 + 0.02 * N, -- more pistons → more rotating mass
            BalanceFactor      = bal,
            TorqueSmoothness   = bal,            -- smoothness tracks balance for inline
            BSFCMult           = 1.00,
            IdleRPMMult        = idl,
            VEBonus            = 0.0,
            FiringIrregularity = 0.0,            -- always even firing
        }
    end

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
        local EngineName = SubMenu:AddTitle()
        local EngineDesc = SubMenu:AddLabel()
        EngineName:SetText(CLASS.Name)
        EngineDesc:SetText(CLASS.Description)
        local EngineConfig = SubMenu:AddCollapsible("Engine Configuration", nil, "icon16/shape_square_edit.png")

        local PistonOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EnginePistons").Options
        local Pistons = EngineConfig:AddSlider("Number of Pistons", PistonOpts.Min, PistonOpts.Max, PistonOpts.Decimals)
        Pistons:SetValue(NestedData.EnginePistons or PistonOpts.Default or 4)
        function Pistons:OnValueChanged(Value)
            NestedData.EnginePistons = math.Round(Value, PistonOpts.Decimals or 0)
            PushData()
        end

        local BoreOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EngineBore").Options
        local Bore = EngineConfig:AddSlider("Piston Bore Size (cm)", BoreOpts.Min, BoreOpts.Max, BoreOpts.Decimals)
        Bore:SetValue(NestedData.EngineBore or BoreOpts.Default)
        function Bore:OnValueChanged(Value)
            NestedData.EngineBore = math.Round(Value, BoreOpts.Decimals or 2)
            PushData()
        end

        local StrokeOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EngineStroke").Options
        local Stroke = EngineConfig:AddSlider("Piston Stroke Size (cm)", StrokeOpts.Min, StrokeOpts.Max, StrokeOpts.Decimals)
        Stroke:SetValue(NestedData.EngineStroke or StrokeOpts.Default)

        local ClearanceOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EngineClearance").Options
        local Clearance = EngineConfig:AddSlider("Piston TDC Clearance (cm)", ClearanceOpts.Min, ClearanceOpts.Max, ClearanceOpts.Decimals)
        Clearance:SetValue(NestedData.EngineClearance or ClearanceOpts.Default)

        function Stroke:OnValueChanged(Value)
            NestedData.EngineStroke = math.Round(Value, StrokeOpts.Decimals or 2)
            Clearance:SetMax(Value - 0.01)

            local ClearVal = Clearance:GetValue()
            if ClearVal >= Value then Clearance:SetValue(Value - 0.01) end
            PushData()
        end

        function Clearance:OnValueChanged(Value)
            NestedData.EngineClearance = math.Round(Value, ClearanceOpts.Decimals or 2)
            PushData()
        end

        SubMenu:AddLabel("Engine Displacement: ")
    end
end)