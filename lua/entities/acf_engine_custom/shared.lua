DEFINE_BASECLASS("acf_base_scalable")

ENT.PrintName      = "ACF Custom Engine"
ENT.WireDebugName  = "ACF Custom Engine"
ENT.PluralName     = "ACF Custom Engines"
ENT.ACF_Limit      = 20
ENT.ACF_PreventArmoring = true

ENT.IsACFCustomEngine = true

ACF.Entities.AutoRegisterV2(function()
    MENU_FIELD("ACF.CustomEngines.BaseEngineBlock", "BlockType", {OnlyAllowSubtypes = true, InstantiateTypeForDefault = "ACF.CustomEngines.InlineEngine"})

    MENU_FIELD("String", "CustomEngineModel",     {Default = "models/engines/v8s.mdl"})
    MENU_FIELD("Number", "CustomEnginePistons",   {Min = 4,    Max = 12, Default = 8,   Decimals = 0, IsEvenNumber = true})
    MENU_FIELD("Number", "CustomEngineBore",      {Min = 1,    Max = 20, Default = 4.0, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineStroke",    {Min = 1,    Max = 20, Default = 4.2, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineClearance", {Min = 0.05, Max = 4,  Default = 0.5, Decimals = 2}) -- in Centimeters
    MENU_FIELD("Number", "CustomEngineBankAngle", {Min = 60,   Max = 120, Default = 90, Decimals = 0}) -- in Degrees

    MENU_FIELD("String", "CustomEngineCylinderHead", {Default = "Pushrod"})
    MENU_FIELD("String", "CustomEngineCamshaftType", {Default = "Stock"})
    -- Nothing to validate: the Engine field is constrained to ACF.Engines.* subtypes by the serializer.
    function CLASS:VerifyData() end
end, "Custom Engine", "Custom Engines")

ENT.ACF_StaticWireInputs = {
    "Active (If set to a non-zero value, it'll attempt to start the engine.)",
    "Throttle (On a range from 0 to 1, defines how much power will be given to the engine.)"
}

ENT.ACF_StaticWireOutputs = {
    "RPM (Current rotations per minute of the engine.)",
    "Torque (Current torque, in nM, output by the engine.)",
    "Power (Current power, in kW, output by the engine.)",
    "Fuel Use (Amount of fuel, in liters per minute, being consumed by the engine.)",
    "State (Current state of the engine, whether its off, starting, running or stalling.) [STRING]",
    "Coolant Temp (Current Coolant Temperature of the engine, in degrees Celcius.)",
    "Oil Temp (Current Oil Temperature of the engine, in degrees Celcius.)",
    "Mass (Total mass detected on the vehicle by the engine.)",
    "Physical Mass (Physical mass detected on the vehicle by the engine.)",
    "Entity (The engine itself.) [ENTITY]",
}

function ENT:GetEngineType()
    return self:ACF_GetUserVar("BlockType")
end