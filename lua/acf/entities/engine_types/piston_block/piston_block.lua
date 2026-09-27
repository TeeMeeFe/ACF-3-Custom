local ACF     = ACF
local Classes = ACF.Classes
local GetType = Classes.GetTypeByName
local Compute = ACF.Compute

local PI      = math.pi
local Clamp   = math.Clamp
local Round   = math.Round
local max     = math.max
local pow     = math.pow

local PAGE    = "acf_engine_custom"
local STARTER_TYPE_BASE = "ACF.CustomEngines.Starters"

-- ===========================================================================
--  Base piston block class definition 
--
--  Each layout overrides this to return a flat table of multipliers
--  applied on top of the shared piston geometry math:
--
--    InertiaFactor     – multiplier on flywheel inertia
--    BalanceFactor     – crankshaft balance quality [0-1]; lower means
--                        minimum stable idle RPM is higher
--    TorqueSmoothness  – torque delivery evenness [0-1]; affects misfire
--                        sensitivity and idle roughness
--    BSFCMult          – correction on top of Otto-cycle BSFC
--    IdleRPMMult       – scales the bore/stroke-derived idle RPM
--    VEBonus           – volumetric efficiency offset [-0.1 .. +0.1]
--    FiringIrregularity– fractional deviation from even firing [0-1]
--
-- == Entity parameters (set in entity's instance module: spawning.lua) ======
--
--  Piston engines:
--    Layout      string  "inline"|"boxer"|"v"|"wr"|"wankel"|...etc 
--    Bore        number  cylinder bore radius (cm)
--    Stroke      number  piston stroke (cm)
--    Clearance   number  TDC dead space (cm)
--    Pistons     number  cylinder count (rotors for Wankel)
--    BankAngle   number  degrees between banks (V, WR)
--    BankCount   number  number of banks (WR only; V is always 2)
--
-- ===========================================================================

-- MARK: Class definition
Classes.DefineClass("ACF.CustomEngines.PistonBlock", "ACF.CustomEngines.BaseEngineBlock", function(CLASS)
    CLASS.Name          = "Piston Block Class"
    CLASS.Description   = "The base class for any and all piston engines."
    CLASS.ToolDesc      = "Attempts to spawn the selected piston engine."  -- Unused. Kept here just in case.
    -- TODO: Some of these attributes should be defined per fuel type
    CLASS.Gamma         = 1.4       -- heat capacity ratio (diatomic air)
    CLASS.LHV_KWH       = 12.222222 -- 44000 / 3600 petrol lower heating value (kWh/kg).
    CLASS.ETA_FRIC      = 0.55      -- Otto → shaft efficiency fraction
    CLASS.BMEP_Scale    = 40        -- Brake Mean Effective Pressure in bar per unit of TorqueScale
    -- Inline engine calibrated mass coefficients
    CLASS.PistonMass_K  = 0.0005    -- kg per cm²
    CLASS.RodMass_K     = 0.0009    -- kg per cm²
    CLASS.CrankMass_K   = 0.0028    -- kg per cm³
    CLASS.BlockMass_K   = 0.05      -- kg per cm³
    CLASS.HeadMass_K    = 0.018     -- kg per cm³
    -- Base heat coefficient calibrated for 1.0 L, CR 9 petrol engine
    CLASS.HeatBase      = 0.012
    -- Reference BSFC for type-correction ratio
    CLASS.REF_BSFC      = 0.304     -- kg/kWh  (GenericPetrol)
    -- Default piston speed limit if Params does not specify one
    CLASS.DEFAULT_PISTON_SPEED = 20 -- m/s

    MENU_FIELD("ACF.CustomEngines.BaseEngineBlock", "BlockType", {
        "ACF.CustomEngines.InlineEngine",
        "ACF.CustomEngines.BoxerEngine",
        "ACF.CustomEngines.VTypeEngine",
        "ACF.CustomEngines.WRTypeEngine",
        "ACF.CustomEngines.RotaryEngine",
        "ACF.CustomEngines.RadialEngine",
        "ACF.CustomEngines.SingleMonoEngine",
        "ACF.CustomEngines.ParallelTwinEngine"
    })

    -- Compression ratio bounds, keyed by ignition type.
    local CR_BOUNDS = {
        glow  = { min = 16.0, max = 22.0 },   -- diesel: compression-ignition requirement
        spark = { min = 7.0,  max = 16.0 },   -- petrol/other: knock-limited range
    }
    local CR_BOUNDS_DEFAULT = CR_BOUNDS.spark

    -- The function for this class lives at lua/acf/core/custom/compute
    function CLASS.Compute(SUPER, LayoutFactors, Params)
        Params.Gamma        = CLASS.Gamma
        Params.LHV_KWH      = CLASS.LHV_KWH
        Params.ETA_FRIC     = CLASS.ETA_FRIC
        Params.BMEP_Scale   = CLASS.BMEP_Scale
        Params.PistonMass_K = CLASS.PistonMass_K
        Params.RodMass_K    = CLASS.RodMass_K
        Params.CrankMass_K  = CLASS.CrankMass_K
        Params.BlockMass_K  = CLASS.BlockMass_K
        Params.HeadMass_K   = CLASS.HeadMass_K
        Params.HeatBase     = CLASS.HeatBase
        Params.REF_BSFC     = CLASS.REF_BSFC
        Params.DEFAULT_PISTON_SPEED = CLASS.DEFAULT_PISTON_SPEED

        return Compute.PistonBlock(SUPER, LayoutFactors, Params)
    end

    --====================================================================================--
    -- MENU CODE  
    --====================================================================================--
    -- I would have done this in a separate utility file named menues_cl.lua, however 
    -- several issues arised with this methodology that prevented me from doing so, not
    -- that i'm done with that idea but the fact that hot-updates don't quite work 
    -- (i am forced to retry in console everytime i need to make or test a change) threw 
    -- me off of that way. So instead menus will have to be done within the file/class that
    -- defines them.

    do -- MARK: Menu code
        local ClearancePanel -- Clearance panel, happens that we need to make this one a global

        -- Clamps a raw compression ratio (derived from stroke/clearance) into the realistic range
        -- for the given fuel type, and back-corrects clearance to match if clamping changed it.
        function CLASS.ClampCR(Ctx)
            if not Ctx then return end
            if not IsValid(ClearancePanel) then return end

            local Stroke = Ctx:Get("Stroke")
            local Clearance = Ctx:Get("Clearance")
            local EngineData = Ctx:Get("EngineType")
            local FuelType = EngineData.IgnitionType

            local CorrectedClearance = Clearance
            local Bounds = CR_BOUNDS[FuelType] or CR_BOUNDS_DEFAULT

            local CR_raw = 1 + Stroke / Clearance
            local CR     = Clamp(CR_raw, Bounds.min, Bounds.max)
            if CR ~= CR_raw then CorrectedClearance = Stroke / (CR - 1) end

            -- Get the clamped limits
            local Min = Stroke / (Bounds.min - 1)
            local Max = Stroke / (Bounds.max - 1)

            -- Set the limits on the panel
            ClearancePanel:SetMinMax(Max, Min)
            ClearancePanel:SetValue(CorrectedClearance)
        end

        function CLASS.CreateMenu(SubMenu, NestedData, ContextData)
            local EngineClass = SubMenu:AddComboBox()
            local Engine = ContextData.Engine

            local SubPanel = SubMenu:AddPanel("ACF_Panel")

            local function BuildMenu(SUPER, SuperMenu)
                local EngineDescLabel
                local BankAnglePanel
                local BankAmountPanel

                -- Variables to fetch any options from our Class Fields
                local ModelOpts     = Classes.GetTypeFieldByName(SUPER, "Model").Options
                local PistonOpts    = Classes.GetTypeFieldByName(SUPER, "Pistons").Options
                local BoreOpts      = Classes.GetTypeFieldByName(SUPER, "Bore").Options
                local StrokeOpts    = Classes.GetTypeFieldByName(SUPER, "Stroke").Options
                local ClearanceOpts = Classes.GetTypeFieldByName(SUPER, "Clearance").Options

                -- Local functions just to update our labels
                local function UpdatePreview(Panel, Displacement)
                    local ClassModel = SUPER.Model
                    local Pistons = Clamp(Engine:Get("Pistons"), PistonOpts.Min, PistonOpts.Max)

                    Engine:Set("Pistons", Pistons)
                    Engine:Set("Model", (ClassModel):format(Round(Pistons, 0)))

                    local Model = Engine:Get("Model") or ModelOpts.Default
                    Panel:UpdateModel(Model)

                    local Scale = 1.08 * pow(Displacement, 0.30)
                    Panel:SetModelScale(Scale, true)
                end

                local function UpdateEngineStats(Panel, Pistons, Bore, Stroke, Clearance)
                    local __Pistons   = Round(Pistons or Engine:Get("Pistons") or PistonOpts.Default)
                    local __Bore      = Bore or Engine:Get("Bore") or BoreOpts.Default
                    local __Stroke    = Stroke or Engine:Get("Stroke") or StrokeOpts.Default
                    local __Clearance = Clearance or Engine:Get("Clearance") or ClearanceOpts.Default

                    -- ── Swept volume and displacement ──────────────────
                    -- V_swept (cm³) = π/4 × bore² × stroke
                    -- V_displ (L)   = V_swept × pistons × 0.001
                    -- The values above are also rounded to the nearest 2 decimals
                    local V_swept = Round((PI / 4) * __Bore * __Bore * __Stroke, 2)
                    local V_displ = Round(V_swept * __Pistons * 0.001, 2)
                    local CRatio  = Round(1 + __Stroke / __Clearance, 2)

                    local Label = ("Compression Ratio: %s:1\
                                    \nSwept Volume per piston: %s cm³\
                                    \nDisplacement: %s L"):format(CRatio, V_swept, V_displ)

                    Panel:SetText(Label)

                    return V_displ, V_swept, CRatio
                end

                local BankAngle = Classes.GetTypeFieldByName(SUPER, "BankAngle")
                local BankAngleOpts = BankAngle and BankAngle.Options

                local BankAmount = Classes.GetTypeFieldByName(SUPER, "BankAmount")
                local BankAmountOpts = BankAmount and BankAmount.Options

                local EngineBase = SuperMenu:AddCollapsible("#acf.menu.engines.engine_info", nil, "icon16/monitor.png")
                local EngineName = EngineBase:AddTitle()
                local EngineDesc = EngineBase:AddLabel()

                EngineName:SetText(SUPER.Name)
                EngineDesc:SetText(SUPER.Description)

                local EnginePreview = EngineBase:AddModelPreview(nil, true, "Primary")
                local EngineStats = EngineBase:AddTitle()
                EngineStats:SetText("Engine Stats")
                EngineDescLabel = EngineBase:AddLabel()

                local EngineConfig = SuperMenu:AddCollapsible("Engine Block Configuration", nil, "icon16/shape_square_edit.png")

                local PistonsPanel = EngineConfig:AddSlider("Number of Pistons", PistonOpts.Min, PistonOpts.Max, PistonOpts.Decimals)
                PistonsPanel:SetValue(Engine:Get("Pistons") or PistonOpts.Default)
                function PistonsPanel:OnValueChanged(Value)
                    Value = Round(Value, PistonOpts.Decimals or 0)

                    if PistonOpts.IsEvenNumber then
                        -- Enforce even cylinder count
                        Value = max(2, (Value % 2 == 0) and Value or Value - 1)
                    end

                    self:SetValue(Value)
                    Engine:Set("Pistons", Value)

                    local Displacement = UpdateEngineStats(EngineDescLabel, Value)
                    UpdatePreview(EnginePreview, Displacement)
                end

                local BorePanel = EngineConfig:AddSlider("Piston Bore Size (cm)", BoreOpts.Min, BoreOpts.Max, BoreOpts.Decimals)
                BorePanel:SetValue(Engine:Get("Bore") or BoreOpts.Default)
                function BorePanel:OnValueChanged(Value)
                    Value = Round(Value, BoreOpts.Decimals or 2)

                    self:SetValue(Value)
                    Engine:Set("Bore", Value)

                    local Displacement = UpdateEngineStats(EngineDescLabel, nil, Value)
                    UpdatePreview(EnginePreview, Displacement)
                end

                local StrokePanel = EngineConfig:AddSlider("Piston Stroke Size (cm)", StrokeOpts.Min, StrokeOpts.Max, StrokeOpts.Decimals)
                StrokePanel:SetValue(Engine:Get("Stroke") or StrokeOpts.Default)

                ClearancePanel = EngineConfig:AddSlider("Piston TDC Clearance (cm)", ClearanceOpts.Min, ClearanceOpts.Max, ClearanceOpts.Decimals)
                ClearancePanel:SetValue(Engine:Get("Clearance") or ClearanceOpts.Default)
                function ClearancePanel:OnValueChanged(Value)
                    Value = Round(Value, ClearanceOpts.Decimals or 2)

                    self:SetValue(Value)
                    Engine:Set("Clearance", Value)

                    local Displacement = UpdateEngineStats(EngineDescLabel, nil, nil, nil, Value)
                    UpdatePreview(EnginePreview, Displacement)
                end

                function StrokePanel:OnValueChanged(Value)
                    Value = Round(Value, StrokeOpts.Decimals or 2)

                    self:SetValue(Value)
                    Engine:Set("Stroke", Value)

                    UpdateEngineStats(EngineDescLabel, nil, nil, Value, nil)

                    CLASS.ClampCR(Engine)
                end

                if BankAngleOpts then
                    BankAnglePanel = EngineConfig:AddSlider("Bank Angle", BankAngleOpts.Min, BankAngleOpts.Max, BankAngleOpts.Decimals)
                    BankAnglePanel:SetValue(Engine:Get("BankAngle") or BankAngleOpts.Default)
                    function BankAnglePanel:OnValueChanged(Value)
                        Engine:Set("BankAngle", Value)
                        self:SetValue(Value)
                    end
                end

                if BankAmountOpts then
                    BankAmountPanel = EngineConfig:AddSlider("Bank Amount", BankAmountOpts.Min, BankAmountOpts.Max, BankAmountOpts.Decimals)
                    BankAmountPanel:SetValue(Engine:Get("BankAmount") or BankAmountOpts.Default)
                    function BankAmountPanel:OnValueChanged(Value)
                        Engine:Set("BankAmount", Value)
                        self:SetValue(Value)
                    end
                end

                local Displacement = UpdateEngineStats(EngineDescLabel)
                UpdatePreview(EnginePreview, Displacement)

                local StarterConfig = SuperMenu:AddCollapsible("Starter Info", nil, "icon16/shape_square_edit.png")
                local StarterTypes = StarterConfig:AddComboBox()
                local StarterPanel = StarterConfig:AddPanel("ACF_Panel")

                function StarterTypes:OnSelect(Index, _, Data)
                    if self.Selected == Data then return end

                    self.ListData.Index = Index
                    self.Selected = Data

                    Engine:Set("StarterType", Data)
                    ACF.Menu.SaveClassCombo(PAGE, "starter", Data)

                    StarterConfig:ClearTemporal(StarterPanel)
                    StarterConfig:StartTemporal(StarterPanel)

                    local CustomMenu = Data.CreateMenu
                    local Ctx = Engine.Instance
                    Ctx.Displacement = Displacement

                    if CustomMenu then
                        CustomMenu(StarterPanel, Ctx)
                    end

                    StarterConfig:EndTemporal(StarterPanel)
                end

                ACF.Menu.LoadClassCombo(StarterTypes, Classes.GetChildren(GetType(STARTER_TYPE_BASE)), "Name", nil, PAGE, "starter")
            end

            function EngineClass:OnSelect(Index, _, Data)
                if self.Selected == Data then return end

                self.ListData.Index = Index
                self.Selected = Data

                Engine:Set("BlockType", Data)

                ACF.Menu.SaveClassCombo(PAGE, "engine", Data)

                SubMenu:ClearTemporal(SubPanel)
                SubMenu:StartTemporal(SubPanel)

                BuildMenu(Data, SubPanel)

                SubMenu:EndTemporal(SubPanel)
            end

            ACF.Menu.LoadClassCombo(EngineClass, Classes.GetChildren(CLASS), "Name", nil, PAGE, "engine")
        end
    end

    -- -- Custom attachment bullshit
    -- function CLASS.SetCustomAttachments()
    --     -- Inline engines
    --     ACF.SetCustomAttachments("models/engines/inline2s.mdl",
    --         {Name = "driveshaft", Pos = Vector(-6, 0, 4), Ang = Angle(0, 180, 90)},
    --         {Name = "starter", Pos = Vector(-3.785, -6, 4.875), Ang = Angle(0, 0, 90)}
    --     )
    --     ACF.SetCustomAttachments("models/engines/inline3s.mdl",
    --         {Name = "driveshaft", Pos = Vector(-6, 0, 4.4), Ang = Angle(0, 180, 90)},
    --         {Name = "starter", Pos = Vector(-3.6, -6, 4.875), Ang = Angle(0, 0, 90)}
    --     )
    --     ACF.SetCustomAttachments("models/engines/inline4s.mdl",
    --         {Name = "driveshaft", Pos = Vector(-6, 0, 4), Ang = Angle(0, 180, 90)},
    --         {Name = "starter", Pos = Vector(-5.75, -6, 4.875), Ang = Angle(0, 0, 90)}
    --     )
    --     ACF.SetCustomAttachments("models/engines/inline5s.mdl",
    --         {Name = "driveshaft", Pos = Vector(-10, 0, 4.4), Ang = Angle(0, 180, 90)},
    --         {Name = "starter", Pos = Vector(-9.5, -6, 4.875), Ang = Angle(0, 0, 90)}
    --     )
    --     ACF.SetCustomAttachments("models/engines/inline6s.mdl",
    --         {Name = "driveshaft", Pos = Vector(-12, 0, 4.4), Ang = Angle(0, 180, 90)},
    --         {Name = "starter", Pos = Vector(-10.125, -6, 4.875), Ang = Angle(0, 0, 90)}
    --     )
    -- end
end)    