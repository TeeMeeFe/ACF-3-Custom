DEFINE_BASECLASS("acf_base_scalable")

ENT.PrintName      = "ACF Custom Engine"
ENT.WireDebugName  = "ACF Custom Engine"
ENT.PluralName     = "ACF Custom Engines"
ENT.ACF_Limit      = 20
ENT.ACF_PreventArmoring = true

ENT.IsACFCustomEngine = true

ACF.AutoRegisterV2(function()
    MENU_FIELD("ACF.Engines.BlockType", "BlockType", {"PistonBlock", "TurbineBlock", "ElectricBlock"})
    --FIELD("ACF.Engines.Model", "EngineBlockModel", {Model = "models/holograms/cube.mdl"})
    --LINKED_ENTITY_FIELD("engine_custom", {AcceptableClasses = {acf_battery = false, acf_radiator = false}})
    --LINKED_ARRAY_FIELD("fueltanks", {AcceptableClasses = {acf_fueltank = true}})
end, "engine_custom")