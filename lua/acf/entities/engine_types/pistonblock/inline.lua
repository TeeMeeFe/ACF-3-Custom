local ACF         = ACF
local Classes     = ACF.Classes
local TankSize    = Vector()

local GetType = Classes.GetTypeByName

ACF.Classes.DefineClass("ACF.Engines.InlineEngine", "ACF.Engines.PistonBlock", function()
    CLASS.Name                 = "Inline Engine"
    CLASS.Description          = "A piston engine in a inlined configuration"
    CLASS.Model                = "models/engines/inline4s.mdl"
    CLASS.Layout               = "Inline"
    CLASS.IsScalable           = true
    CLASS.CubicReductionFactor = 0.85 -- Inverse ratio of empty mass volume an engine has, so it doesn't scale like if it was a solid piece.
    CLASS.Sign                 = "I"
    -- These attributes would be private if we had actual scaffolding for that
    local __INLINE_BAL = { [2] = 0.72, [3] = 0.78, [4] = 0.84, [5] = 0.88, [6] = 0.96, [7] = 0.98, [8] = 1.00 }
    local __INLINE_IDL = { [2] = 1.08, [3] = 1.05, [4] = 1.00, [5] = 0.97, [6] = 0.92, [7] = 0.90, [8] = 0.88 }

    FIELD("Number", "CustomEnginePistons",   {Min = 2,    Max = 6,  Default = 4,   Decimals = 0})
    FIELD("Number", "CustomEngineBore",      {Min = 1,    Max = 20, Default = 4.0, Decimals = 2}) -- in Centimeters
    FIELD("Number", "CustomEngineStroke",    {Min = 1,    Max = 20, Default = 4.2, Decimals = 2}) -- in Centimeters
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
        local BASE = BASE

        -- Append the layout and sign fields
        Params.Layout = CLASS.Layout
        Params.Sign   = CLASS.Sign

        -- The base class has the implementation of this method, so we redict this info there instead
        local Computed = BASE.Compute(CLASS, Layout, Params)

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

        -- Fuel config labels and stuff 
        local FuelConfig = SubMenu:AddCollapsible("Fuel System Configuration", nil, "icon16/shape_square_edit.png")
        local EngineClass = FuelConfig:AddComboBox()
        EngineClass:AddChoice("Diesel Engine", "ACF.EngineTypes.GenericDiesel")
        EngineClass:AddChoice("Petrol Engine", "ACF.EngineTypes.GenericPetrol")
        EngineClass:SetValue("Petrol Engine") -- Filthy fucking hack, i hate this
        timer.Simple(0, function() if IsValid(EngineClass) then EngineClass:OnSelect(nil, nil, "ACF.EngineTypes.GenericPetrol") end end) -- smh

        local FuelType = FuelConfig:AddComboBox()
        --=========================================================================--
        -- RIGHT BELOW THIS CODE IS STRAIGHT UP COPIED FROM engines.lua MENU CODE  --
        --=========================================================================--

        -- Shape selector. The combo value is the ContainerShapes class FQN written straight into the
        -- "Shape" field; no string->class translation needed at spawn time.
        local FuelShape = FuelConfig:AddComboBox()
        FuelShape:AddChoice("Box", "ACF.ContainerShapes.Box")
        FuelShape:AddChoice("Sphere", "ACF.ContainerShapes.Sphere")
        FuelShape:AddChoice("Cylinder", "ACF.ContainerShapes.Cylinder")

        -- Set default shape
        local DefaultShape = ACF.GetClientData("Shape")
        if not GetType(DefaultShape) then DefaultShape = "ACF.ContainerShapes.Box" end
        ACF.SetClientData("Shape", DefaultShape, true)
        FuelShape:ChooseOptionID(DefaultShape == "ACF.ContainerShapes.Sphere" and 2 or DefaultShape == "ACF.ContainerShapes.Cylinder" and 3 or 1)
        timer.Simple(0, function() if IsValid(FuelShape) then FuelShape:OnSelect(nil, nil, DefaultShape) end end) -- Frown

        local Min = ACF.ContainerMinSize
        local Max = ACF.ContainerMaxSize
        local FuelPreview

        -- Set default fuel tank size values before creating sliders to prevent nil value errors
        local DefaultFuelSizeX = ACF.GetClientNumber("FuelSizeX", (Min + Max) / 2)
        local DefaultFuelSizeY = ACF.GetClientNumber("FuelSizeY", (Min + Max) / 2)
        local DefaultFuelSizeZ = ACF.GetClientNumber("FuelSizeZ", (Min + Max) / 2)
        ACF.SetClientData("FuelSizeX", DefaultFuelSizeX, true)
        ACF.SetClientData("FuelSizeY", DefaultFuelSizeY, true)
        ACF.SetClientData("FuelSizeZ", DefaultFuelSizeZ, true)

        local function UpdateSize()
            -- MARCH: STEVE REMOVE THIS ONCE YOU FIX IT (Or leave it if you are fine with this)
            ACF.SetClientData("Size", TankSize, true)
        end

        local SizeX = FuelConfig:AddSlider("#acf.menu.fuel.tank_length", Min, Max)
        SizeX:SetClientData("FuelSizeX", "OnValueChanged")
        SizeX:DefineSetter(function(Panel, _, _, Value)
            local X = math.Round(Value)

            Panel:SetValue(X)

            TankSize.x = X

            FuelType:UpdateFuelText()

            if FuelPreview then
                FuelPreview:SetModelScale(TankSize * 12)
            end

            UpdateSize()
            return X
        end)

        local SizeY = FuelConfig:AddSlider("#acf.menu.fuel.tank_width", Min, Max)
        SizeY:SetClientData("FuelSizeY", "OnValueChanged")
        SizeY:DefineSetter(function(Panel, _, _, Value)
            local Y = math.Round(Value)

            Panel:SetValue(Y)

            TankSize.y = Y

            FuelType:UpdateFuelText()

            if FuelPreview then
                FuelPreview:SetModelScale(TankSize * 12)
            end

            UpdateSize()
            return Y
        end)

        local SizeZ = FuelConfig:AddSlider("#acf.menu.fuel.tank_height", Min, Max)
        SizeZ:SetClientData("FuelSizeZ", "OnValueChanged")
        SizeZ:DefineSetter(function(Panel, _, _, Value)
            local Z = math.Round(Value)

            Panel:SetValue(Z)

            TankSize.z = Z

            FuelType:UpdateFuelText()

            if FuelPreview then
                FuelPreview:SetModelScale(TankSize * 12)
            end

            UpdateSize()
            return Z
        end)

        local FuelBase = FuelConfig:AddCollapsible("#acf.menu.fuel.tank_info", nil, "icon16/cup_edit.png")
        local FuelDesc = FuelBase:AddLabel()
        FuelPreview = FuelBase:AddModelPreview(nil, true, "Secondary")
        local FuelInfo = FuelBase:AddLabel()

        function FuelShape:OnSelect(_, _, Data)
            ACF.SetClientData("Shape", Data)

            -- Update preview model based on shape
            local ShapeClass = GetType(Data) or GetType("ACF.ContainerShapes.Box")
            FuelPreview:UpdateModel(ShapeClass.Model, "models/props_canal/metalcrate001d")

            FuelType:UpdateFuelText()
        end

        -- We don't work with a preset list of engines, these are created on the run instead.
        function EngineClass:OnSelect(_, _, Data)
            if self.Selected == Data then return end

            --self.ListData.Index = Index
            self.Selected = Data

            local FuelData

            -- Shitty hack to get the type of fuel used for these engine Classes
            if Data == "ACF.EngineTypes.GenericPetrol" then
                FuelData = "ACF.FuelTypes.Petrol"
            elseif Data == "ACF.EngineTypes.GenericDiesel" then
                FuelData = "ACF.FuelTypes.Diesel"
            end

            local FuelDescription = GetType(FuelData)
            local Fuel = {FuelData = FuelDescription}

            ACF.SetClientData("EngineClass", Data)
            ACF.LoadSortedList(FuelType, Fuel, "ID")
        end

        function FuelType:OnSelect(Index, _, Data)
            if self.Selected == Data then return end

            self.ListData.Index = Index
            self.Selected = Data

            --PrintTable({self.ListData.Index, self.Selected, Classes.GetTypeName(Data)})
            ACF.SetClientData("FuelType", Classes.GetTypeName(Data))

            self:UpdateFuelText()
        end

        function FuelType:UpdateFuelText()
            if not self.Selected then return end

            local TextFunc = self.Selected.FuelTankText
            local FuelText = ""

            local Wall = ACF.ContainerArmor * ACF.MmToInch -- Wall thickness in inches
            local Shape = GetType(ACF.GetClientData("Shape")) or GetType("ACF.ContainerShapes.Box")

            -- Calculate volume and area using shape calculations
            local Volume, Area = Shape.ShapeCalculation(TankSize, Wall)

            local Capacity	= Volume * ACF.gCmToKgIn -- Internal volume available for fuel in liters
            local EmptyMass	= Area * Wall * ACF.InchToCmCu * ACF.SteelDensity -- Total wall volume * cu in to cc * density of steel (kg/cc)
            local Mass		= EmptyMass + Capacity * self.Selected.Density -- Weight of tank + weight of fuel

            if TextFunc then
                FuelText = FuelText .. TextFunc(Capacity, Mass, EmptyMass)
            else
                local Text = language.GetPhrase("acf.menu.fuel.tank_stats")
                local Liters = math.Round(Capacity, 2)
                local Gallons = math.Round(Capacity * ACF.LToGal, 2)

                FuelText = FuelText .. Text:format(ACF.ContainerArmor, Liters, Gallons, ACF.GetProperMass(Mass), ACF.GetProperMass(EmptyMass))
            end

            FuelDesc:SetText("Scalable Fuel Tank\n\nShape: " .. (Shape.Name or "Box"))
            FuelInfo:SetText(FuelText)
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