ACF.Classes.DefineClass("ACF.Radiators.Intercooler", "ACF.Radiators.RadiatorType", function()
    CLASS.Name = "Standard Intercooler"
    CLASS.Description = "A radiator meant to cool down engine intake gas temperature."
    CLASS.Model = "models/radiators/Radiator_small.mdl"

    MENU_FIELD("Number", "Scale", {Min = 0.5, Max = 1, Default = 1, Decimals = 2})

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
        local RadiatorOpts = ACF.Classes.GetTypeFieldByName(CLASS, "Scale").Options

        local BasePreview = SubMenu:AddCollapsible("Radiator Info", nil, "icon16/monitor_edit.png")
        local RadiatorName = BasePreview:AddTitle()
        local RadiatorDesc = BasePreview:AddLabel()
        RadiatorName:SetText(CLASS.Name)
        RadiatorDesc:SetText(CLASS.Description)

        -- Should this go as a field instead?
        local PreviewSettings = {
            FOV       = 150,
            Height    = 120,
            AngOffset = Angle(0, -90, 0),
        }

        local RadiatorPreview = BasePreview:AddModelPreview(nil, true, "Primary")
        RadiatorPreview:UpdateModel(CLASS.Model)
        RadiatorPreview:UpdateSettings(PreviewSettings)
        --local EngineStats = BasePreview:AddLabel()

        local Min = RadiatorOpts.Min
        local Max = RadiatorOpts.Max
        local Decimals = RadiatorOpts.Decimals
        local ScaleSlider = SubMenu:AddSlider("Scale", Min, Max, Decimals)
        ScaleSlider:SetValue(ACF.GetClientData("RadiatorScale", RadiatorOpts.Default))
        ScaleSlider:SetClientData("RadiatorScale", "OnValueChanged")
        ScaleSlider:DefineSetter(function(Panel, _, _, Value)
            Panel:SetValue(Value)
        end)
    end
end)