ACF.Classes.DefineClass("ACF.Engines.InlineEngine", "ACF.Engines.PistonBlock", function()
    CLASS.Name         = "Inline Engine"
    CLASS.Description  = "A piston engine in a inlined configuration"
    -- These attributes would be private if we had actual scaffolding for that
    local __INLINE_BAL = { [2] = 0.72, [3] = 0.78, [4] = 0.84, [5] = 0.88, [6] = 0.96, [7] = 0.98, [8] = 1.00 }
    local __INLINE_IDL = { [2] = 1.08, [3] = 1.05, [4] = 1.00, [5] = 0.97, [6] = 0.92, [7] = 0.90, [8] = 0.88 }

    FIELD("Number", "EnginePistons",   {Min = 2,    Max = 8,  Default = 4,   Decimals = 0})
    FIELD("Number", "EngineBore",      {Min = 0.1,  Max = 10, Default = 4.0, Decimals = 2}) -- in Centimeters
    FIELD("Number", "EngineStroke",    {Min = 0.1,  Max = 10, Default = 4.2, Decimals = 2}) -- in Centimeters
    FIELD("Number", "EngineClearance", {Min = 0.05, Max = 4,  Default = 0.5, Decimals = 2}) -- in Centimeters

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
        --local toString = tostring
        local round = math.Round
        --local PI = math.pi

        --local CRLabel
        --local VSweptLabel
        --local VTotalLabel

        --local V_swept
        local EngineName = SubMenu:AddTitle()
        local EngineDesc = SubMenu:AddLabel()
        EngineName:SetText(CLASS.Name)
        EngineDesc:SetText(CLASS.Description)
        local EngineConfig = SubMenu:AddCollapsible("Engine Block Configuration", nil, "icon16/shape_square_edit.png")

        local PistonOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EnginePistons").Options
        local Pistons = EngineConfig:AddSlider("Number of Pistons", PistonOpts.Min, PistonOpts.Max, PistonOpts.Decimals)
        Pistons:SetValue(ACF.GetClientNumber("EnginePistons", NestedData.EnginePistons or PistonOpts.Default))
        Pistons:SetClientData("EnginePistons", "OnValueChanged")
        Pistons:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(round(Value, PistonOpts.Decimals or 0))
            --V_total = round(V_swept * Value * 0.001, 2)
            --VTotalLabel:SetText("Displacement: " .. toString(V_total) .. " L")
            PushData()
        end)

        local BoreOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EngineBore").Options
        local Bore = EngineConfig:AddSlider("Piston Bore Size (cm)", BoreOpts.Min, BoreOpts.Max, BoreOpts.Decimals)
        Bore:SetValue(ACF.GetClientNumber("EngineBore", NestedData.EngineBore or BoreOpts.Default))
        Bore:SetClientData("EngineBore", "OnValueChanged")
        Bore:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(round(Value, BoreOpts.Decimals or 2))

            --V_swept = round((PI / 4) * Value * Value * NestedData.EngineStroke, 2)
            --VSweptLabel:SetText("Swept Volume: " .. toString(V_swept) .. " cm³")
            --V_total = round(V_swept * NestedData.EnginePistons * 0.001, 2)
            --VTotalLabel:SetText("Displacement: " .. toString(V_total) .. " L")
            PushData()
        end)

        local StrokeOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EngineStroke").Options
        local Stroke = EngineConfig:AddSlider("Piston Stroke Size (cm)", StrokeOpts.Min, StrokeOpts.Max, StrokeOpts.Decimals)
        Stroke:SetValue(ACF.GetClientNumber("EngineStroke", NestedData.EngineStroke or StrokeOpts.Default))
        Stroke:SetClientData("EngineStroke", "OnValueChanged")

        local ClearanceOpts = ACF.Classes.GetTypeFieldByName(CLASS, "EngineClearance").Options
        local Clearance = EngineConfig:AddSlider("Piston TDC Clearance (cm)", ClearanceOpts.Min, ClearanceOpts.Max, ClearanceOpts.Decimals)
        Clearance:SetValue(ACF.GetClientNumber("EngineClearance", NestedData.EngineClearance or ClearanceOpts.Default))
        Clearance:SetClientData("EngineClearance", "OnValueChanged")
        Clearance:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(round(Value, ClearanceOpts.Decimals or 2))
            --CRLabel:SetText("Compression Ratio: " .. toString(round(1 + NestedData.EngineStroke / Value, 2)))
            PushData()
        end)

        Stroke:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(round(Value, StrokeOpts.Decimals or 2))
            Clearance:SetMax(Value - 0.01)

            local ClearVal = Clearance:GetValue()
            if ClearVal >= Value then Clearance:SetValue(Value - 0.01) end
            --CRLabel:SetText("Compression Ratio: " .. toString(round(1 + Value / NestedData.EngineClearance, 2)))

            --V_swept = round((PI / 4) * NestedData.EngineBore * NestedData.EngineBore * Value, 2)
            --VSweptLabel:SetText("Swept Volume: " .. toString(V_swept) .. " cm³")
            --V_total = round(V_swept * NestedData.EnginePistons * 0.001, 2)
            --VTotalLabel:SetText("Displacement: " .. toString(V_total) .. " L")
            PushData()
        end)

        --CRLabel = EngineConfig:AddLabel("Compression Ratio: ")
        --CRLabel:SetText("Compression Ratio: " .. toString(round(1 + NestedData.EngineStroke / NestedData.EngineClearance, 2)))

        -- ── Swept volume and displacement ──────────────────
        -- V_swept (cm³) = π/4 × bore² × stroke
        -- V_total (L)   = V_swept × pistons × 0.001
        --V_swept = round((PI / 4) * NestedData.EngineBore * NestedData.EngineBore * NestedData.EngineStroke, 2)
        --V_total = round(V_swept * NestedData.EnginePistons * 0.001, 2)

       -- VSweptLabel = SubMenu:AddLabel("Swept Volume: " .. toString(V_swept) .. " cm³")
       --VTotalLabel = SubMenu:AddLabel("Displacement: " .. toString(V_total) .. " L")
    end
end)