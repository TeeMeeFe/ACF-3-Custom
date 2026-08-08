local ACF = ACF
local Classes = ACF.Classes

local lerp  = Lerp
local abs   = math.abs
local Round = math.Round

Classes.DefineClass("ACF.Radiators.Standard", "ACF.Radiators.BaseRadiator", function()
    CLASS.Name = "Standard Radiator"
    CLASS.Description = "A radiator for cooling down any Naturally Aspirated engines."
    CLASS.Model = "models/radiators/Radiator_med.mdl"
    CLASS.BaseEmptyMass = 20  -- Mass when empty, In kilograms.
    CLASS.BaseCapacity  = 6.5 -- This radiator base capacity at scale 1, In liters.

    -- Private fields, if we had the scaffolding for them..
    -- Specific Caloric Capacity of our fluids, aka how much energy they need to heat up. Higher is better.
    local WaterCp = 4186 -- In Kilojoules per Kilogram
    local GlycolCp = 2380
    -- Densities computed at 20°C, ρ(rho) is the symbol used to compute density in g/cm³ or Kg/L.
    local Rho_Water = 0.998
    local Rho_Glycol = 1.113

    -- Look-Up Tables, computed at 1 atm, of pressure.
    -- Mixture | °C
    local BoilingCurve = {
        {0.00, 100.0}, -- Pure Water
        {0.10, 101.5},
        {0.20, 103.0},
        {0.30, 104.8},
        {0.40, 106.5},
        {0.50, 108.0},
        {0.60, 111.0},
        {0.70, 116.0},
        {0.80, 124.0},
        {0.90, 145.0},
        {1.00, 197.3}  -- Pure Glycol, also the highest boiling point at this mixture
    }
    local FreezingCurve = {
        {0.00,   0}, -- Pure Water
        {0.10,  -4},
        {0.20,  -8},
        {0.30, -15},
        {0.40, -24},
        {0.50, -37},
        {0.60, -52}, -- Lowest freezing point at this mixture
        {0.70, -48},
        {0.80, -36},
        {0.90, -20},
        {1.00, -13}  -- Pure Glycol
    }
    -- A function that returns an interpolated value from a lookup table with {x, y} pairs.
    local function LookupLerp(LUT, X)
        local Count = #LUT

        if X <= LUT[1][1] then
            return LUT[1][2]
        end

        if X >= LUT[Count][1] then
            return LUT[Count][2]
        end

        for I = 1, Count - 1 do
            local A = LUT[I]
            local B = LUT[I + 1]

            if X >= A[1] and X <= B[1] then
                local T = (X - A[1]) / (B[1] - A[1])

                return A[2] + (B[2] - A[2]) * T
            end
        end

        return LUT[Count][2]
    end

    function CLASS.CreateMenu(SubMenu, NestedData, Context)
        local ClassData = Classes.GetTypeByName("acf_radiator")

        local BasePreview = SubMenu:AddCollapsible("Radiator Info", nil, "icon16/monitor_edit.png")
        local RadiatorName = BasePreview:AddTitle()
        local RadiatorDesc = BasePreview:AddLabel()
        RadiatorName:SetText(CLASS.Name)
        RadiatorDesc:SetText(CLASS.Description)

        -- Should this go as a field instead?
        local PreviewSettings = {
            FOV       = 120,
            Height    = 120,
            AngOffset = Angle(0, -90, 0),
        }

        local RadiatorPreview = BasePreview:AddModelPreview(nil, true, "Primary")
        RadiatorPreview:UpdateModel(CLASS.Model)
        RadiatorPreview:UpdateSettings(PreviewSettings)

        local CapacityLabel
        local MixtureLabel
        local CoolCapLabel
        local DensityLabel
        local ConductLabel
        local TmlMassLabel
        local BoilingLabel
        local FreezingLabel

        local ScaleOpts = Classes.GetTypeFieldByName(ClassData, "RadiatorScale").Options
        local MixOpts = Classes.GetTypeFieldByName(ClassData, "CoolantMix").Options

        local function UpdatePreviewSize(Scale)
            if not IsValid(RadiatorPreview) then return end
            RadiatorPreview:SetModelScale(Scale, true)
        end

        local function UpdateLabels()
            -- Coolant mix as a ratio of 0 to 1, from full water to full glycol mixtures
            local CMix = Context.Class.CoolantMix or MixOpts.Default
            Context.Instance.CoolantMix = CMix

            local MisteryText
            if CMix <= 0 then
                MisteryText = "Pure 100% Water"
            elseif CMix < 1 then
                MisteryText = ("Water: %s%s, Glycol: %s%s"):format(Round(abs(1 - CMix) * 100), "%", Round(CMix * 100), "%")
            else
                MisteryText = "Pure 100% Glycol"
            end

            local RadScale = Context.Class.RadiatorScale or ScaleOpts.Default
            Context.Instance.RadiatorScale = RadScale

            local RadiatorCapacity = CLASS.BaseCapacity * RadScale ^ 2.15
            local CoolantCaloricCapacity = WaterCp + (GlycolCp - WaterCp) * CMix
            local CoolantDensity = Rho_Water + (Rho_Glycol - Rho_Water) * CMix
            local CoolantConductivity = lerp(CMix, 0.6, 0.25) -- W/(m·°C)
            local RadiatorThermalMass = RadiatorCapacity * CoolantCaloricCapacity * CoolantDensity * 0.001
            local BoilingPoint = LookupLerp(BoilingCurve, CMix)
            local FreezingPoint = LookupLerp(FreezingCurve, CMix)

            CapacityLabel:SetText(("Capacity: %s Liters"):format(Round(RadiatorCapacity, 1)))
            MixtureLabel:SetText(MisteryText)

            CoolCapLabel:SetText(("Specific Heat: %s kJ/kg·°C"):format(Round(CoolantCaloricCapacity, 2)))
            Context.Class.SpecificHeat = CoolantCaloricCapacity
            Context.Instance.SpecificHeat = CoolantCaloricCapacity

            DensityLabel:SetText(("Fluid Density: %s kg/L"):format(Round(CoolantDensity, 2)))
            Context.Class.Density = CoolantDensity
            Context.Instance.Density = CoolantDensity

            ConductLabel:SetText(("Conductivity:  %s W/m·°C"):format(Round(CoolantConductivity, 2)))
            TmlMassLabel:SetText(("Total Thermal Mass: %s J/°C."):format(Round(RadiatorThermalMass, 2)))

            BoilingLabel:SetText(("Boiling Point: %s °C"):format(Round(BoilingPoint, 2)))
            Context.Class.BoilingPoint = BoilingPoint
            Context.Instance.BoilingPoint = BoilingPoint

            FreezingLabel:SetText(("Freezing Point: %s °C"):format(Round(FreezingPoint, 2)))
            Context.Class.FreezingPoint = FreezingPoint
            Context.Instance.FreezingPoint = FreezingPoint
        end

        local ScaleSlider = BasePreview:AddSlider("Scale", ScaleOpts.Min, ScaleOpts.Max, ScaleOpts.Decimals)
        ScaleSlider:SetValue(Context.Class.RadiatorScale or ScaleOpts.Default)
        function ScaleSlider:OnValueChanged(Value)
            Context.Class.RadiatorScale = Value
            UpdateLabels()
            UpdatePreviewSize(Value)
        end

        CapacityLabel = BasePreview:AddLabel()

        local CoolantMix = BasePreview:AddSlider("Coolant Mix", MixOpts.Min, MixOpts.Max, MixOpts.Decimals)
        CoolantMix:SetValue(Context.Class.CoolantMix or MixOpts.Default)
        function CoolantMix:OnValueChanged(Value)
            Context.Class.CoolantMix = Value
            UpdateLabels()
        end

        MixtureLabel = BasePreview:AddLabel()

        -- Gotta create these at the end cause otherwise they would end up way above where i want them.
        local StatsMenu = SubMenu:AddCollapsible("Radiator Stats", nil, "icon16/monitor_edit.png")
        CoolCapLabel    = StatsMenu:AddLabel()
        DensityLabel    = StatsMenu:AddLabel()
        ConductLabel    = StatsMenu:AddLabel()
        TmlMassLabel    = StatsMenu:AddLabel()
        BoilingLabel    = StatsMenu:AddLabel()
        FreezingLabel   = StatsMenu:AddLabel()

        UpdateLabels()
        UpdatePreviewSize(Context.Class.RadiatorScale or ScaleOpts.Default)
    end
end)