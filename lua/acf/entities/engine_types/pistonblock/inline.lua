ACF.Classes.DefineClass("ACF.Engines.InlineEngine", "ACF.Engines.PistonBlock", function()
    CLASS.Name         = "Inline Engine"
    CLASS.Description  = "A piston engine in a inlined configuration"
    CLASS.Model        = "models/engines/inline4s.mdl"
    CLASS.Layout       = "Inline"
    CLASS.IsScalable   = true
    CLASS.Mass         = 100 -- Relative to the Base model size
    CLASS.Sign         = "I"
    -- These attributes would be private if we had actual scaffolding for that
    local __INLINE_BAL = { [2] = 0.72, [3] = 0.78, [4] = 0.84, [5] = 0.88, [6] = 0.96, [7] = 0.98, [8] = 1.00 }
    local __INLINE_IDL = { [2] = 1.08, [3] = 1.05, [4] = 1.00, [5] = 0.97, [6] = 0.92, [7] = 0.90, [8] = 0.88 }

    FIELD("Number", "CustomEnginePistons",   {Min = 2,    Max = 8,  Default = 4,   Decimals = 0})
    FIELD("Number", "CustomEngineBore",      {Min = 0.1,  Max = 10, Default = 4.0, Decimals = 2}) -- in Centimeters
    FIELD("Number", "CustomEngineStroke",    {Min = 0.1,  Max = 10, Default = 4.2, Decimals = 2}) -- in Centimeters
    FIELD("Number", "CustomEngineClearance", {Min = 0.05, Max = 4,  Default = 0.5, Decimals = 2}) -- in Centimeters

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

    function CLASS.Compute(_, Layout, Params)
        Params.Layout = CLASS.Layout -- Append the layout field
        Params.Sign   = CLASS.Sign

        -- The base class has the implementation of this method, so we redict this info there instead
        local BaseClass = ACF.Classes.GetBaseClass(CLASS)
        local Computed = BaseClass.Compute(CLASS, Layout, Params)

        return Computed
    end

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
        local ToString = tostring
        local Round = math.Round
        local Floor = math.floor
        local PI = math.pi

        local CRLabel
        local VSweptLabel
        local VTotalLabel

        -- Variables to fetch any options from our Class Fields
        local PistonOpts    = ACF.Classes.GetTypeFieldByName(CLASS, "CustomEnginePistons").Options
        local BoreOpts      = ACF.Classes.GetTypeFieldByName(CLASS, "CustomEngineBore").Options
        local StrokeOpts    = ACF.Classes.GetTypeFieldByName(CLASS, "CustomEngineStroke").Options
        local ClearanceOpts = ACF.Classes.GetTypeFieldByName(CLASS, "CustomEngineClearance").Options

        -- Local functions just to update our labels
        local function UpdateCRLabel(Stroke, Clearance)
            local __Stroke = Stroke or ACF.GetClientNumber("CustomEngineStroke", StrokeOpts.Default)
            local __Clearance = Clearance or ACF.GetClientNumber("CustomEngineClearance", ClearanceOpts.Default)

            local String = ToString(Round(1 + __Stroke / __Clearance, 2))

            CRLabel:SetText("Compression Ratio: " .. String)
        end

        -- Volume Swept-Displacement Panels
        local function UpdateVSDLabels(Pistons, Bore, Stroke)
            local __Pistons = Floor(Pistons or ACF.GetClientNumber("CustomEnginePistons", PistonOpts.Default))
            local __Bore    = Bore or ACF.GetClientNumber("CustomEngineBore", BoreOpts.Default)
            local __Stroke  = Stroke or ACF.GetClientNumber("CustomEngineStroke", StrokeOpts.Default)

            -- ── Swept volume and displacement ──────────────────
            -- V_swept (cm³) = π/4 × bore² × stroke
            -- V_displ (L)   = V_swept × pistons × 0.001
            -- The values above are also rounded to the nearest 2 decimals
            local V_swept = ToString(Round((PI / 4) * __Bore * __Bore * __Stroke, 2))
            local V_displ = ToString(Round(V_swept * __Pistons * 0.001, 2))

            VSweptLabel:SetText("Swept Volume (cm³): " .. V_swept)
            VTotalLabel:SetText("Displacement (L): " .. V_displ)
        end

        local EngineName = SubMenu:AddTitle()
        local EngineDesc = SubMenu:AddLabel()
        EngineName:SetText(CLASS.Name)
        EngineDesc:SetText(CLASS.Description)

        local EngineConfig = SubMenu:AddCollapsible("Engine Block Configuration", nil, "icon16/shape_square_edit.png")
        VSweptLabel = SubMenu:AddLabel("")
        VTotalLabel = SubMenu:AddLabel("")
        UpdateVSDLabels()

        local Pistons = EngineConfig:AddSlider("Number of Pistons", PistonOpts.Min, PistonOpts.Max, PistonOpts.Decimals)
        Pistons:SetValue(ACF.GetClientNumber("CustomEnginePistons", NestedData.CustomEnginePistons or PistonOpts.Default))
        Pistons:SetClientData("CustomEnginePistons", "OnValueChanged")
        Pistons:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(Round(Value, PistonOpts.Decimals or 0))
            UpdateVSDLabels(Value)
            PushData()
        end)

        local Bore = EngineConfig:AddSlider("Piston Bore Size (cm)", BoreOpts.Min, BoreOpts.Max, BoreOpts.Decimals)
        Bore:SetValue(ACF.GetClientNumber("CustomEngineBore", NestedData.CustomEngineBore or BoreOpts.Default))
        Bore:SetClientData("CustomEngineBore", "OnValueChanged")
        Bore:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(Round(Value, BoreOpts.Decimals or 2))
            UpdateVSDLabels(nil, Value)
            PushData()
        end)

        local Stroke = EngineConfig:AddSlider("Piston Stroke Size (cm)", StrokeOpts.Min, StrokeOpts.Max, StrokeOpts.Decimals)
        Stroke:SetValue(ACF.GetClientNumber("CustomEngineStroke", NestedData.CustomEngineStroke or StrokeOpts.Default))
        Stroke:SetClientData("CustomEngineStroke", "OnValueChanged")

        local Clearance = EngineConfig:AddSlider("Piston TDC Clearance (cm)", ClearanceOpts.Min, ClearanceOpts.Max, ClearanceOpts.Decimals)
        Clearance:SetValue(ACF.GetClientNumber("CustomEngineClearance", NestedData.CustomEngineClearance or ClearanceOpts.Default))
        Clearance:SetClientData("CustomEngineClearance", "OnValueChanged")
        Clearance:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(Round(Value, ClearanceOpts.Decimals or 2))
            UpdateCRLabel(nil, Value)
            PushData()
        end)

        Stroke:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(Round(Value, StrokeOpts.Decimals or 2))
            Clearance:SetMax(Value - 0.01)

            local ClearVal = Clearance:GetValue()
            if ClearVal >= Value then Clearance:SetValue(Value - 0.01) end
            UpdateCRLabel(Value, nil)
            UpdateVSDLabels(nil, nil, Value)
            PushData()
        end)

        CRLabel = EngineConfig:AddLabel("Compression Ratio: " .. ToString(Round(1 + NestedData.CustomEngineStroke / NestedData.CustomEngineClearance, 2)))
        UpdateCRLabel()

        local FuelConfig = SubMenu:AddCollapsible("Fuel System Configuration", nil, "icon16/shape_square_edit.png")
        local EntityClassDef = ACF.Classes.GetTypeByName("acf_fueltank")
        local FuelTypeSelector = ACF.Classes.CreateTypeSelector(FuelConfig, EntityClassDef, "FuelType")
        local ClassList = FuelTypeSelector.ComboBox

        if ClassList and ClassList.Selected then
            local TypeName = ACF.Classes.GetTypeName(ClassList.Selected)
            ACF.SetClientData("FuelType", TypeName)
        end
    end
end)

do -- Custom attachment shit that i thought it was being added automagically but no
    ACF.SetCustomAttachment("models/engines/inline4l.mdl", "driveshaft", Vector(-15, 0, 10), Angle(0, 180, 90))
    ACF.SetCustomAttachment("models/engines/inline4m.mdl", "driveshaft", Vector(-9, 0, 6), Angle(0, 180, 90))
    ACF.SetCustomAttachment("models/engines/inline4s.mdl", "driveshaft", Vector(-6, 0, 4), Angle(0, 180, 90))

    local Models = {
        { Model = "models/engines/inline4l.mdl", Scale = 2.5 },
        { Model = "models/engines/inline4m.mdl", Scale = 1.5 },
        { Model = "models/engines/inline4s.mdl", Scale = 1 },
    }

    for _, Data in ipairs(Models) do
        local Scale = Data.Scale

        ACF.AddHitboxes(Data.Model, {
            Shaft = {
                Pos       = Vector(0.5, 0, 4.75) * Scale,
                Scale     = Vector(23, 7.5, 9) * Scale,
                Sensitive = true
            },
            Pistons = {
                Pos   = Vector(1.25, 0, 13.25) * Scale,
                Scale = Vector(18.25, 5.25, 8) * Scale
            }
        })
    end
end