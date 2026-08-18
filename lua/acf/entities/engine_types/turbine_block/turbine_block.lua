-- Base turbine block class definition
ACF.Classes.DefineClass("ACF.CustomEngines.TurbineBlock", "ACF.CustomEngines.BaseEngineBlock", function()
    CLASS.Name = "Turbine Block Class"
    CLASS.Description = "The base class for any and all types of turbines."
    CLASS.ToolDesc    = "Attempts to spawn the selected turbine."

    MENU_FIELD("ACF.CustomEngines.BaseEngineBlock", "BlockType", {
        "ACF.CustomEngines.GasTurbine",
        "ACF.CustomEngines.GroundGasTurbine",
        "ACF.CustomEngines.PulseJet",
        "ACF.CustomEngines.RamJet"
    })
end)    