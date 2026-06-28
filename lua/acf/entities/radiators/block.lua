ACF.Classes.DefineClass("ACF.Radiators.Block", "ACF.Radiators.RadiatorType", function()
    CLASS.Name = "Block Radiator"
    CLASS.Description = "For when a standard radiator is just not enough..."
    CLASS.Model = "models/radiators/Radiator_big.mdl"

    MENU_FIELD("Number", "RadiatorSizeX", {Min = ACF.ContainerMinSize or 6, Max = ACF.ContainerMaxSize or 96, Default = 24, Decimals = 0})
    MENU_FIELD("Number", "RadiatorSizeY", {Min = ACF.ContainerMinSize or 6, Max = ACF.ContainerMaxSize or 96, Default = 24, Decimals = 0})
    MENU_FIELD("Number", "RadiatorSizeZ", {Min = ACF.ContainerMinSize or 6, Max = ACF.ContainerMaxSize or 96, Default = 24, Decimals = 0})

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
        local SizeXOpts = ACF.Classes.GetTypeFieldByName(CLASS, "RadiatorSizeX").Options
        local SizeYOpts = ACF.Classes.GetTypeFieldByName(CLASS, "RadiatorSizeY").Options
        local SizeZOpts = ACF.Classes.GetTypeFieldByName(CLASS, "RadiatorSizeZ").Options

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
    end
end)