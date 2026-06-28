-- Base radiator class
ACF.Classes.DefineClass("ACF.Radiators.RadiatorType", function()
    CLASS.Name = "Radiator class"
    CLASS.Description = "An entity designed to exchange heat."
    CLASS.Model = "models/holograms/cube.mdl"

    MENU_FIELD("ACF.Radiators.RadiatorType", "RadiatorType", {"Standard", "Block", "Intercooler"})
end)