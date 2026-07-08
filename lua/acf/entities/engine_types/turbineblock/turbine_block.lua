-- Base turbine block class definition
ACF.Classes.DefineClass("ACF.Engines.TurbineBlock", "ACF.Engines.BaseEngineBlock", function()
    CLASS.Name = "Turbine Block Class"
    CLASS.Description = "The base class for any and all types of turbines."
    CLASS.ToolDesc    = "Attempts to spawn the selected turbine."

    MENU_FIELD("ACF.Engines.TurbineBlock", "TurbineTypes", {
        "GasTurbine",
        "GroundGasTurbine",
        "PulseJet",
        "RamJet"
    })
end)    