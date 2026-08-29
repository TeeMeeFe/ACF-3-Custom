local ACF     = ACF
local Classes = ACF.Classes
local Custom  = ACF.Custom

local istable = istable
local PI      = math.pi
local Clamp   = math.Clamp
local Round   = math.Round
local floor   = math.floor
local max     = math.max
local pow     = math.pow
local sqrt    = math.sqrt

local PAGE    = "acf_engine_custom"

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

    -- Reference CR for the thermodynamic torque-scaling multiplier
    local CR_TORQUE_REF = 9.0

    -- MARK: CLASS.Compute
    function CLASS.Compute(SUPER, LayoutFactors, Params)
        if not SUPER then return end -- TODO: Maybe another check here if its a class?
        if not Params and istable(Params) then return end
        if not LayoutFactors and istable(LayoutFactors) then return end

        -- Layout factors 
        local Bore        = Params.Bore      -- In centimeters
        local Stroke      = Params.Stroke    -- In centimeters
        local Clearance   = Params.Clearance -- In centimeters
        local Pistons     = Params.Pistons
        local PistonSpeed = Params.PistonSpeed or CLASS.DEFAULT_PISTON_SPEED -- In meters per second

        -- Pre-validation steps.
        -- Stroke, if its a wankel we want it to be max 3cm of eccentricity.
        -- TODO: The number 3 is the actual class maximum, probably should fetch from there instead of hardcoding this.
        Stroke = Params.Layout == "Wankel" and Clamp(Stroke, 1, 3) or Stroke

        -- Clearance, must be positive and less than stroke
        Clearance = Clamp(Clearance, 0.05, Stroke - 0.01)

        -- 1. Compression ratio (dimensionless, cm cancel)
        -- Clamp Compression Ratio to a realistic value based on the engine's ignitionType/fuel type.
        local CRBounds = CR_BOUNDS[Params.IgnitionType] or CR_BOUNDS_DEFAULT
        local CR_raw   = 1 + Stroke / Clearance
        local CR       = Clamp(CR_raw, CRBounds.min, CRBounds.max)
        if CR ~= CR_raw then Clearance = Stroke / (CR - 1) end

        -- 2. Swept volume and displacement 
        -- V_swept (cm³) = π/4 × bore² × stroke
        -- V_total (cm³) = V_swept × Pistons 
        -- V_total (L)   = V_total × 0.001  
        local V_swept_cm3 = (PI * 0.25) * Bore * Bore * Stroke
        local V_total_cm3 = V_swept_cm3 * Pistons
        local V_total_L   = V_total_cm3 * 0.001

        -- 3. Compute base engine mass based on its block and recipient masses
        local Area = V_swept_cm3 / Stroke

        local PistonsMass = Area * Pistons * CLASS.PistonMass_K
        local RodsMass    = V_total_cm3 * CLASS.RodMass_K
        local CrankMass   = V_total_cm3 * CLASS.CrankMass_K
        local BlockMass   = V_total_cm3 * CLASS.BlockMass_K * SUPER.CubicReductionFactor
        local HeadMass    = V_total_cm3 * CLASS.HeadMass_K * SUPER.CubicReductionFactor

        local ModelMass = PistonsMass + RodsMass + CrankMass + BlockMass + HeadMass

        -- Otto cycle thermal efficiency scaled by Compression Ratio effects.
        -- η_otto = 1 − (1/CR)^(γ-1)
        local eta_otto = 1 - (1 / CR) ^ (CLASS.Gamma - 1)

        -- 4. Peak torque via BMEP, scaled by CR's thermodynamic effect
        -- Higher CR extracts more mechanical work from the same combustion event 
        -- The multiplier is normalized against CR_TORQUE_REF (9.0) so TorqueScale
        -- keeps meaning "BMEP potential at CR 9". CR only scales output up
        -- or down from that baseline, it doesn't add a second independent torque knob.
        local eta_otto_ref   = 1 - (1 / CR_TORQUE_REF) ^ (CLASS.Gamma - 1)
        local CR_torque_mult = eta_otto / eta_otto_ref
        -- T = BMEP_Pa × V_total_m³ / (4π)    [4-stroke cycle]
        local BMEP_Pa        = Params.TorqueScale * CLASS.BMEP_Scale * 1e5
        -- Calculate peak torque, scale by CR and apply volumetric efficiency layout bonus/penalty
        local PeakTorque = ((BMEP_Pa * (V_total_L * 1e-3) / (4 * PI)) * CR_torque_mult) * (1 + (LayoutFactors.VEBonus or 0))

        -- 5. RPM Limit from mean piston speed
        -- RPM_max = 60 × v_piston / (2 × stroke_m)
        -- stroke_m = Stroke × 0.01  →  inline
        local LimitRPM = floor(60 * PistonSpeed / (2 * Stroke * 0.01))

        -- 6. Idle RPM from bore/stroke ratio + layout
        -- Base_Idle = 800 × √(bore/stroke)  [dimensionless ratio]
        -- BalanceFactor: smoother engines can idle lower; rougher need more RPM
        -- IdleRPMMult: layout-specific adjustment (Wankel idles higher; boxer lower)
        local Base_Idle = 800 * sqrt(Bore / Stroke)
        local Bal_Idle  = Base_Idle / max(LayoutFactors.BalanceFactor, 0.5)
        local IdleRPM   = Clamp(floor(Bal_Idle * (LayoutFactors.IdleRPMMult or 1.0)), 300, 2200)

        -- 7. BSFC from Otto efficiency + CR + type
        -- η_otto = 1 − (1/CR)^(γ-1)
        -- η_real = CLASS.ETA_FRIC × η_otto
        -- BSFC   = 1 / (η_real × CLASS.LHV_KWH)  [kg/kWh, theoretical]
        -- Corrected by type ratio and layout BSFC multiplier:
        -- BSFC_eff = BSFC_theoretical × (typeBSFC / REF_BSFC) × BSFCMult
        local BSFC_base = 1 / (CLASS.ETA_FRIC * eta_otto * CLASS.LHV_KWH)
        local typeCorr  = (Params.Efficiency or CLASS.REF_BSFC) / CLASS.REF_BSFC
        local BSFC_eff  = BSFC_base * typeCorr * (LayoutFactors.BSFCMult or 1.0)

        -- 8. Heat generation coefficient 
        -- Proportional to displacement; inversely proportional to CR.
        -- Higher CR → better thermal efficiency → less waste heat.
        local heatCoeff = CLASS.PistonMass_K * V_total_L * (9.0 / CR)

        -- 9. Flywheel inertia
        -- I = Pistons × m_piston × stroke_m² × k_crank
        -- m_piston (kg) = PistonMass_K × bore_cm²
        -- Combined (inline): Pistons × PistonMass_K × bore² × stroke² × 1e-3
        -- Scaled by InertiaFactor for layout differences.
        local I_base = Pistons * CLASS.PistonMass_K * Bore * Bore * Stroke * Stroke * 0.1 -- 0.1 as 0.001 was having no inertia at all
        local Inertia = I_base * (LayoutFactors.InertiaFactor or 1.0)

        -- 10. Torque curve
        -- local IsWankel = Params.Layout == "Wankel"
        -- local IdleFrac = IdleRPM / max(LimitRPM, 1)
        -- local VECurve = BuildVECurve(
        --     Params.HeadType        or "ohc",
        --     Params.CamProfile      or "stock",
        --     Params.RunnerLength_cm or 22,
        --     --Params.ExhaustType     or "stock",
        --     Params.FuelDelivery    or "injection",
        --     Params.IgnitionType,
        --     LimitRPM,
        --     IsWankel, IdleFrac, CR)

        -- 11. Build the torque curve
        local ct = Custom.BuildTorqueCurve(Params.TorqueCurve, PeakTorque, LimitRPM, IdleRPM, V_total_L)

        -- 12. Compute model's size according to its displacement 
        local Scale = 1.08 * pow(V_total_L, 0.30)

        return {
            -- Identity
            Layout             = Params.Layout,
            IsPiston           = true,
            IsWankel           = Params.Layout == "Wankel",
            BankAngle          = Params.BankAngle,
            BankCount          = Params.BankCount,
            -- Inputs (for HUD / get status)
            Bore               = Bore,
            Stroke             = Stroke,
            Clearance          = Clearance,
            Pistons            = Pistons,
            ModelScale         = Scale,
            ScaledMass         = ModelMass,
            Sign               = Params.Sign .. Pistons, -- Sign of the engine, e.g: "I4", "V8", "Radial 7"
            -- Derived geometry
            CompressionRatio   = CR,
            SweptVolPerCyl     = V_swept_cm3 * 0.001,    -- In liters
            Displacement       = {InCubicCentimeters = V_total_cm3, InLiters = V_total_L},
            -- Performance
            LimitRPM           = LimitRPM,
            IdleRPM            = IdleRPM,
            BSFC               = BSFC_eff,
            HeatCoeff          = heatCoeff,
            FlywheelInertia    = Inertia,
            -- Layout character
            BalanceFactor      = LayoutFactors.BalanceFactor or 1.0,
            TorqueSmoothness   = LayoutFactors.TorqueSmoothness or 1.0,
            FiringIrregularity = LayoutFactors.FiringIrregularity or 0.0,
            -- Ignition frequency: 4-stroke piston fires once every 2 revolutions, Wankel overrides this.
            SparksPerRev       = LayoutFactors.SparksPerRev or 0.5,
            -- Connecting-rod / crankshaft geometry
            -- RodRatio = rod length / crank radius.  Higher ratio = less side thrust.
            -- Empirical: 1.5 + (bore/stroke) × 0.4  (oversquare engines have shorter rods)
            RodRatio           = 1.5 + (Bore / Stroke) * 0.4,
            -- Big-end bearing journal diameter (empirical: bore × 0.27)
            BigEndDiam         = Bore * 0.27,
            -- Oil sump tilt sensitivity by layout.
            -- Warn: Degrees of tilt before pressure begins to drop
            -- Starve: Degrees of tilt for full starvation
            OilSumpTilt        = {Warn = LayoutFactors.OilSumpTiltWarn or 50, Starve = LayoutFactors.OilSumpTiltStarve or 90},
            -- Computed curves
            Curve              = {Torque = ct.T_Curve, Friction = ct.F_Curve, Steps = ct.Steps},
            VECurve            = VECurve,
            Sample             = ct.Sample,
            PeakPower          = ct.PeakPower,
            PeakTorque         = ct.PeakTorque,
            PowerBand          = ct.PowerBand,
            RedlineRPM         = ct.RedlineRPM,
        }
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

            local Stroke = Ctx:Get("CustomEngineStroke")
            local Clearance = Ctx:Get("CustomEngineClearance")
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
                local ModelOpts     = Classes.GetTypeFieldByName(SUPER, "CustomEngineModel").Options
                local PistonOpts    = Classes.GetTypeFieldByName(SUPER, "CustomEnginePistons").Options
                local BoreOpts      = Classes.GetTypeFieldByName(SUPER, "CustomEngineBore").Options
                local StrokeOpts    = Classes.GetTypeFieldByName(SUPER, "CustomEngineStroke").Options
                local ClearanceOpts = Classes.GetTypeFieldByName(SUPER, "CustomEngineClearance").Options

                -- Local functions just to update our labels
                local function UpdatePreview(Panel)
                    local ClassModel = SUPER.Model
                    local Pistons = Clamp(Engine:Get("CustomEnginePistons"), PistonOpts.Min, PistonOpts.Max)

                    Engine:Set("CustomEnginePistons", Pistons)
                    Engine:Set("CustomEngineModel", (ClassModel):format(Round(Pistons, 0)))

                    local Model = Engine:Get("CustomEngineModel") or ModelOpts.Default
                    Panel:UpdateModel(Model)
                end

                local function UpdateEngineStats(Panel, Pistons, Bore, Stroke, Clearance)
                    local __Pistons   = Round(Pistons or Engine:Get("CustomEnginePistons") or PistonOpts.Default)
                    local __Bore      = Bore or Engine:Get("CustomEngineBore") or BoreOpts.Default
                    local __Stroke    = Stroke or Engine:Get("CustomEngineStroke") or StrokeOpts.Default
                    local __Clearance = Clearance or Engine:Get("CustomEngineClearance") or ClearanceOpts.Default

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
                end

                local BankAngle = Classes.GetTypeFieldByName(SUPER, "CustomEngineBankAngle")
                local BankAngleOpts = BankAngle and BankAngle.Options

                local BankAmount = Classes.GetTypeFieldByName(SUPER, "CustomEngineBankAmount")
                local BankAmountOpts = BankAmount and BankAmount.Options

                local EngineBase = SuperMenu:AddCollapsible("#acf.menu.engines.engine_info", nil, "icon16/monitor_edit.png")
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
                PistonsPanel:SetValue(Engine:Get("CustomEnginePistons") or PistonOpts.Default)
                function PistonsPanel:OnValueChanged(Value)
                    Value = Round(Value, PistonOpts.Decimals or 0)

                    if PistonOpts.IsEvenNumber then
                        -- Enforce even cylinder count
                        Value = max(2, (Value % 2 == 0) and Value or Value - 1)
                    end

                    self:SetValue(Value)
                    Engine:Set("CustomEnginePistons", Value)

                    UpdatePreview(EnginePreview)
                    UpdateEngineStats(EngineDescLabel, Value)
                end

                local BorePanel = EngineConfig:AddSlider("Piston Bore Size (cm)", BoreOpts.Min, BoreOpts.Max, BoreOpts.Decimals)
                BorePanel:SetValue(Engine:Get("CustomEngineBore") or BoreOpts.Default)
                function BorePanel:OnValueChanged(Value)
                    Value = Round(Value, BoreOpts.Decimals or 2)

                    self:SetValue(Value)
                    Engine:Set("CustomEngineBore", Value)

                    UpdateEngineStats(EngineDescLabel, nil, Value)
                end

                local StrokePanel = EngineConfig:AddSlider("Piston Stroke Size (cm)", StrokeOpts.Min, StrokeOpts.Max, StrokeOpts.Decimals)
                StrokePanel:SetValue(Engine:Get("CustomEngineStroke") or StrokeOpts.Default)

                ClearancePanel = EngineConfig:AddSlider("Piston TDC Clearance (cm)", ClearanceOpts.Min, ClearanceOpts.Max, ClearanceOpts.Decimals)
                ClearancePanel:SetValue(Engine:Get("CustomEngineClearance") or ClearanceOpts.Default)
                function ClearancePanel:OnValueChanged(Value)
                    Value = Round(Value, ClearanceOpts.Decimals or 2)

                    self:SetValue(Value)
                    Engine:Set("CustomEngineClearance", Value)

                    UpdateEngineStats(EngineDescLabel, nil, nil, nil, Value)
                end

                function StrokePanel:OnValueChanged(Value)
                    Value = Round(Value, StrokeOpts.Decimals or 2)

                    self:SetValue(Value)
                    Engine:Set("CustomEngineStroke", Value)

                    UpdateEngineStats(EngineDescLabel, nil, nil, Value, nil)

                    CLASS.ClampCR(Engine)
                end

                if BankAngleOpts then
                    BankAnglePanel = EngineConfig:AddSlider("Bank Angle", BankAngleOpts.Min, BankAngleOpts.Max, BankAngleOpts.Decimals)
                    BankAnglePanel:SetValue(Engine:Get("CustomEngineBankAngle") or BankAngleOpts.Default)
                    function BankAnglePanel:OnValueChanged(Value)
                        Engine:Set("CustomEngineBankAngle", Value)
                        self:SetValue(Value)
                    end
                end

                if BankAmountOpts then
                    BankAmountPanel = EngineConfig:AddSlider("Bank Amount", BankAmountOpts.Min, BankAmountOpts.Max, BankAmountOpts.Decimals)
                    BankAmountPanel:SetValue(Engine:Get("CustomEngineBankAmount") or BankAmountOpts.Default)
                    function BankAmountPanel:OnValueChanged(Value)
                        Engine:Set("CustomEngineBankAmount", Value)
                        self:SetValue(Value)
                    end
                end

                UpdatePreview(EnginePreview)
                UpdateEngineStats(EngineDescLabel)
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
end)    