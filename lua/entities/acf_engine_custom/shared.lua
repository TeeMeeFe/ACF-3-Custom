DEFINE_BASECLASS("acf_base_scalable")

ENT.PrintName      = "ACF Custom Engine"
ENT.WireDebugName  = "ACF Custom Engine"
ENT.PluralName     = "ACF Custom Engines"
ENT.ACF_Limit      = 20
ENT.ACF_PreventArmoring = true

ENT.IsACFCustomEngine = true

ACF.Entities.AutoRegisterV2(function()
    MENU_FIELD("ACF.Engines.BaseEngineBlock", "BlockType", {InstantiateTypeForDefault = "ACF.Engines.PistonBlock", OnlyAllowSubtypes = true})

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
    "State (Current state of the engine, whether its off, starting, running or stalling) [STRING]",
    "Coolant Temp (Current Coolant Temperature of the engine, in degrees Celcius.)",
    "Oil Temp (Current Oil Temperature of the engine, in degrees Celcius.)",
    "Mass (Total mass detected on the vehicle by the engine.)",
    "Physical Mass (Physical mass detected on the vehicle by the engine.)",
    "Entity (The engine itself.) [ENTITY]",
}


-- This doesn't work, as we only get the inmediate BlockType class defined above,
-- but not its children till the very last one with all the field info we need :(
-- Returns the blocktype instance backing this entity.
function ENT:GetBlockType()
    return self:ACF_GetUserVar("BlockType")
end