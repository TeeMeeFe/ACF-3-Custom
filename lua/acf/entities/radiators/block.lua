local ACF = ACF
local Classes = ACF.Classes

local Round = math.Round

Classes.DefineClass("ACF.Radiators.Block", "ACF.Radiators.BaseRadiator", function(CLASS)
    CLASS.Name        = "Block Radiator"
    CLASS.Description = "For when a standard radiator is just not enough..."
    CLASS.Model       = "models/radiators/Radiator_big.mdl"
    CLASS.IsBlock     = true -- This is a class that's sizeable on a X,Y,Z basis.

    function CLASS.CreateMenu(SubMenu, NestedData, ContextData)
        local ClassData = Classes.GetTypeByName("acf_radiator")

        local SizeXOpts = Classes.GetTypeFieldByName(ClassData, "RadiatorSizeX").Options
        local SizeYOpts = Classes.GetTypeFieldByName(ClassData, "RadiatorSizeY").Options
        local SizeZOpts = Classes.GetTypeFieldByName(ClassData, "RadiatorSizeZ").Options

        local RadSize = Vector(
            ContextData:Get("RadiatorSizeZ") or SizeZOpts.Default,
            ContextData:Get("RadiatorSizeY") or SizeYOpts.Default,
            ContextData:Get("RadiatorSizeZ") or SizeZOpts.Default
        )

        local BasePreview = SubMenu:AddCollapsible("Radiator Info", nil, "icon16/monitor_edit.png")
        local RadiatorName = BasePreview:AddTitle()
        local RadiatorDesc = BasePreview:AddLabel()
        RadiatorName:SetText(CLASS.Name)
        RadiatorDesc:SetText(CLASS.Description)

        local PreviewSettings = {
            FOV       = 90,
            Height    = 120,
            AngOffset = Angle(0, -90, 0),
        }

        local RadiatorPreview = BasePreview:AddModelPreview(nil, true, "Primary")
        RadiatorPreview:UpdateModel(CLASS.Model)
        RadiatorPreview:UpdateSettings(PreviewSettings)

        local function UpdatePreview()
            if RadiatorPreview then
                RadiatorPreview:SetModelScale(RadSize * 12)
            end
        end

        local SizeX = BasePreview:AddSlider("Length", SizeXOpts.Min, SizeXOpts.Max)
        SizeX:SetValue(ContextData:Get("RadiatorSizeX") or SizeXOpts.Default)
        function SizeX:OnValueChanged(Value)
            local X = Round(Value)
            ContextData:Set("RadiatorSizeX", X)

            RadSize.x = X

            UpdatePreview()
        end

        local SizeY = BasePreview:AddSlider("Width", SizeYOpts.Min, SizeYOpts.Max)
        SizeY:SetValue(ContextData:Get("RadiatorSizeY") or SizeYOpts.Default)
        function SizeY:OnValueChanged(Value)
            local Y = Round(Value)
            ContextData:Set("RadiatorSizeY", Y)

            RadSize.y = Y

            UpdatePreview()
        end

        local SizeZ = BasePreview:AddSlider("Height", SizeZOpts.Min, SizeZOpts.Max)
        SizeZ:SetValue(ContextData:Get("RadiatorSizeZ") or SizeZOpts.Default)
        function SizeZ:OnValueChanged(Value)
            local Z = Round(Value)
            ContextData:Set("RadiatorSizeZ", Z)

            RadSize.z = Z

            UpdatePreview()
        end
    end
end)