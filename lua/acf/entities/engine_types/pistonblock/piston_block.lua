-- Base piston block class definition
ACF.Classes.DefineClass("ACF.Engines.PistonBlock", "ACF.Engines.BlockType", function()
    CLASS.Name = "Piston Block Class"
    CLASS.Description = "The base class for any and all piston engines."
    FIELD("ACF.Engines.PistonBlock", "EngineTypes", {
        "InlineEngine",
        "BoxerEngine",
        "V-TypeEngine",
        "WR-TypeEngine",
        "RotaryEngine",
        "RadialEngine",
        "SingleMonoEngine",
        "ParallelTwinEngine"
    })

    function CLASS.CreateMenu(SubMenu, NestedData, PushData)
        ACF.Classes.CreateTypeSelector(SubMenu, CLASS, "EngineTypes")
    end
end)    