-- Base electric block class definition
ACF.Classes.DefineClass("ACF.Engines.ElectricBlock", "ACF.Engines.BlockType", function()
    CLASS.Name        = "Electric Block Class"
    CLASS.Description = "The base class for any and all types of electric motors."
    CLASS.ToolDesc    = "Attempts to spawn the selected electric motor."

    MENU_FIELD("ACF.Engines.ElectricBlock", "ElectricTypes", { "GenericElectricalMotor" })
end)    