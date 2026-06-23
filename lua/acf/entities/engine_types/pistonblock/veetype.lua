ACF.Classes.DefineClass("ACF.Engines.VTypeEngine", "ACF.Engines.PistonBlock", function()
    CLASS.Name         = "V-Type Engine"
    CLASS.Description  = "A piston engine in a V configuration"
    CLASS.Model        = "models/engines/v8s.mdl"

    function CLASS.GetLayoutFactors()
    end

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
    end
end)