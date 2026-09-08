DEFINE_BASECLASS("acf_container")

ENT.PrintName      = "ACF Radiator"
ENT.WireDebugName  = "ACF Radiator"
ENT.PluralName     = "ACF Radiators"
ENT.ACF_Limit      = 20
ENT.ACF_PreventArmoring = true

ENT.IsACFRadiator = true

ACF.Entities.AutoRegisterV2(function(CLASS)
    MENU_FIELD("ACF.Radiators.BaseRadiator", "RadiatorType", {
        InstantiateTypeForDefault = "ACF.Radiators.Standard",
        OnlyAllowSubtypes = true
    })
    MENU_FIELD("Number", "RadiatorScale", {Min = 0.5, Max = 2.5, Default = 1, Decimals = 1})
    MENU_FIELD("Number", "CoolantMix",    {Min = 0, Max = 1, Default = 0.5, Decimals = 2})
    MENU_FIELD("Number", "Density",       {Min = 0, Max = 99, Default = 1, Decimals = 3})
    MENU_FIELD("Number", "SpecificHeat",  {Min = 0, Max = 9999, Default = 1, Decimals = 3})
    MENU_FIELD("Number", "BoilingPoint",  {Min = -273.15, Max = 999, Default = 100, Decimals = 2})
    MENU_FIELD("Number", "FreezingPoint", {Min = -273.15, Max = 999, Default = 0, Decimals = 2})

    MENU_FIELD("Number", "ThermostatTemp", {Min = 70, Max = 110, Default = 90, Decimals = 0})

    -- MENU_FIELD("Number", "RadiatorSizeX", {Min = 24, Max = 96, Default = 42, Decimals = 0})
    -- MENU_FIELD("Number", "RadiatorSizeY", {Min = 6,  Max = 15, Default = 12, Decimals = 0})
    -- MENU_FIELD("Number", "RadiatorSizeZ", {Min = 12, Max = 48, Default = 30, Decimals = 0})
    function CLASS:VerifyData() end
end, "Radiator", "Radiators")

ENT.ACF_StaticWireInputs = {
    "Active (If set to a non-zero value, it'll activate this radiator.)",
    "Thermostat (Allows the engine to be cooled down if set to a non-zero value.)",
}

ENT.ACF_StaticWireOutputs = {
    "Activated (Whether the radiator is active or not.)",
    "Thermostat Active (Whether the thermostat is active or not.)",
    "Fan Active (Whether the radiator's fan is active or not, the thermostat has to be active for this to work.)",
    "Temperature (The temperature of the refrigerant fluid contained within, in Degrees Celcius.)",
    "Core Temperature (The internal temperature of the radiator, in Degrees Celcius.)",
    "Amount (How much refrigerant fluid is this radiator carrying, in kilograms.)",
    "Capacity (How much refrigerant fluid can this radiator contain, in kilograms.)",
    "Leaking (If this radiator is leaking its contents.)",
    "Entity (The radiator entity itself.) [ENTITY]",
}
-- Returns the radiator instance backing this entity.
function ENT:GetRadiator()
    return self:ACF_GetUserVar("RadiatorType")
end
