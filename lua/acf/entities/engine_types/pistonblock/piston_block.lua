-- Base piston block class definition
ACF.Classes.DefineClass("ACF.Engines.PistonBlock", "ACF.Engines.BlockType", function()
    CLASS.Name        = "Piston Block Class"
    CLASS.Description = "The base class for any and all piston engines."
    CLASS.ToolDesc    = "Attempts to spawn the selected piston engine."

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
        local TypeSelector = ACF.Classes.CreateTypeSelector(SubMenu, CLASS, "EngineTypes")
        local ClassList    = TypeSelector.ComboBox

        if ClassList and ClassList.Selected then
            ACF.SetClientData("EngineBlockModel", ClassList.Selected.Model)
        end

        ACF.SetClientData("PrimaryClass", "acf_engine_custom")
        ACF.SetClientData("SecondaryClass", "acf_fueltank")
        ACF.SetClientData("FuelTank", "ACF.FuelTanks.ScalableFuelTank") -- Set default fuel tank to scalable
    end
end)    