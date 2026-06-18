-- Base turbine block class definition
ACF.Classes.DefineClass("ACF.Engines.TurbineBlock", "ACF.Engines.BlockType", function()
    CLASS.Name = "Turbine Block Class"
    CLASS.Description = "The base class for any and all types of turbines."
    MENU_FIELD("ACF.Engines.TurbineBlock", "TurbineTypes", {
        "GasTurbine",
        "GroundGasTurbine",
        "PulseJet",
        "RamJet"
    })
end)    