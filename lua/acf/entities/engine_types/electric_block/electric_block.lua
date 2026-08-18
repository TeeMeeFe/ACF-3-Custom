-- Base electric block class definition
ACF.Classes.DefineClass("ACF.CustomEngines.ElectricBlock", "ACF.CustomEngines.BaseEngineBlock", function(CLASS)
    CLASS.Name        = "Electric Block Class"
    CLASS.Description = "The base class for any and all types of electric motors."
    CLASS.ToolDesc    = "Attempts to spawn the selected electric motor."

    MENU_FIELD("ACF.CustomEngines.BaseEngineBlock", "BlockType", { "ACF.CustomEngines.GenericElectricalMotor" })
end)    