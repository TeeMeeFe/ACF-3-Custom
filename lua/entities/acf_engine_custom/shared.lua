DEFINE_BASECLASS("acf_base_scalable")

ENT.PrintName      = "ACF Custom Engine"
ENT.WireDebugName  = "ACF Custom Engine"
ENT.PluralName     = "ACF Custom Engines"
--ENT.ACF_Limit      = 2
ENT.ACF_PreventArmoring = true

ENT.IsACFCustomEngine = true

ACF.AutoRegisterV2(function()
    MENU_FIELD("ACF.Engines.BlockType", "BlockType", {"PistonBlock", "TurbineBlock", "ElectricBlock"})
    --[[MENU_FIELD("ACF.Engines.PistonBlock", "PistonBlock", {
        "InlineBlock",
        "FlatBlock",
        "V-TypeBlock",
        "WR-TypeBlock",
        "RotaryBlock",
        "RadialBlock",
        "SingleMonoBlock",
        "ParallelTwinBlock"
    })
    MENU_FIELD("ACF.Engines.TurbineBlock", "TurbineBlock", {
        "GasTurbine",
        "GroundGasTurbine",
        "PulseJet",
        "RamJet"
    })
    MENU_FIELD("ACF.Engines.ElectricBlock", "ElectricBlock", { "GenericElectricalMotor" })]]--

    --MENU_FIELD("Number", "EnginePistons", {Min = ACF.MinPistons, Max = ACF.MaxPistons, Default = ACF.DEFAULT_NUM_PISTONS, Decimals = 0})
    --MENU_FIELD("Number", "EngineBore",    {Min = 1, Max = 24, Default = 1, Decimals = 2})
   -- MENU_FIELD("Number", "EngineStroke",  {Min = 1, Max = 24, Default = 1, Decimals = 2})
    --LINKED_ENTITY_FIELD("engine_custom", {AcceptableClasses = {acf_battery = false, acf_radiator = false}})
    --LINKED_ARRAY_FIELD("fueltanks", {AcceptableClasses = {acf_fueltank = true}})
end, "engine_custom")