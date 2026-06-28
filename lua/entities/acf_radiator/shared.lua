DEFINE_BASECLASS("acf_container")

ENT.PrintName      = "ACF Radiator"
ENT.WireDebugName  = "ACF Radiator"
ENT.PluralName     = "ACF Radiators"
ENT.ACF_Limit      = 20
ENT.ACF_PreventArmoring = true

ENT.IsACFRadiator = true

ACF.AutoRegisterV2(function()
    FIELD("ACF.Radiators.RadiatorType", "RadiatorType", {
        InstantiateTypeForDefault = "ACF.Radiators.Standard",
        OnlyAllowSubtypes = true
    })
    MENU_FIELD("Number", "Scale", {InstantiateTypeForDefault = "ACF.Radiators.Standard", OnlyAllowSubtypes = true})
    MENU_FIELD("Number", "RadiatorSizeX", {Min = ACF.ContainerMinSize or 6, Max = ACF.ContainerMaxSize or 96, Default = 24, Decimals = 0})
    MENU_FIELD("Number", "RadiatorSizeY", {Min = ACF.ContainerMinSize or 6, Max = ACF.ContainerMaxSize or 96, Default = 24, Decimals = 0})
    MENU_FIELD("Number", "RadiatorSizeZ", {Min = ACF.ContainerMinSize or 6, Max = ACF.ContainerMaxSize or 96, Default = 24, Decimals = 0})

end, "Radiator", "Radiators")

ENT.ACF_StaticWireInputs = {
    "Active (If set to a non-zero value, it'll activate this radiator.)",
    "Thermostat (Ranges from 0-1 to fully open. It'll attempt to cool down the linked engine.)"
}

ENT.ACF_StaticWireOutputs = {
    "Activated (Whether the radiator is active or not.)",
    "Temperature (The internal temperature of the refrigerant fluid contained within, in Degrees Celcius.)",
    "Amount (How much refrigerant fluid is this radiator carrying, in kilograms.)",
    "Capacity (How much refrigerant fluid can this radiator contain, in kilograms.)",
    "Leaking (If this radiator is leaking its contents.)",
    "Entity (The radiator entity itself.) [ENTITY]",
}