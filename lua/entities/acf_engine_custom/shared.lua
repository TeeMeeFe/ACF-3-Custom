DEFINE_BASECLASS("acf_base_scalable")

ENT.PrintName      = "ACF Custom Engine"
ENT.WireDebugName  = "ACF Custom Engine"
ENT.PluralName     = "ACF Custom Engines"
ENT.ACF_Limit      = 20
ENT.ACF_PreventArmoring = true

ENT.IsACFCustomEngine = true

ACF.AutoRegisterV2(function()
    MENU_FIELD("ACF.Engines.BlockType", "BlockType", {InstantiateTypeForDefault = "ACF.Engines.InlineEngine", OnlyAllowSubtypes = false})
    MENU_FIELD("ACF.FuelTypes.FuelType", "FuelType", {InstantiateTypeForDefault = "ACF.FuelTypes.CustomPetrol", OnlyAllowSubtypes = true})
    --FIELD("ACF.Engines.Model", "EngineBlockModel", {Model = "models/holograms/cube.mdl"})
    --LINKED_ENTITY_FIELD("engine_custom", {AcceptableClasses = {acf_battery = false, acf_radiator = false}})
    --LINKED_ARRAY_FIELD("fueltanks", {AcceptableClasses = {acf_fueltank = true}})
end, "Custom Engine", "Custom Engines")

ENT.ACF_StaticWireInputs = {
    "Active (If set to a non-zero value, it'll attempt to start the engine.)",
    "Throttle (On a range from 0 to 100, defines how much power will be given to the engine.)"
}

ENT.ACF_StaticWireOutputs = {
    "RPM (Current rotations per minute of the engine.)",
    "Torque (Current torque, in nM, output by the engine.)",
    "Power (Current power, in kW, output by the engine.)",
    "Fuel Use (Amount of fuel, in liters per minute, being consumed by the engine.)",
    "State (Current state of the engine, whether its off, starting, running or stalling)",
    "Mass (Total mass detected on the vehicle by the engine.)",
    "Physical Mass (Physical mass detected on the vehicle by the engine.)",
    "Entity (The engine itself.) [ENTITY]",
}
