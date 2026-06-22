-- Base piston block class definition
ACF.Classes.DefineClass("ACF.Engines.PistonBlock", "ACF.Engines.BlockType", function()
    CLASS.Name         = "Piston Block Class"
    CLASS.Description  = "The base class for any and all piston engines."
    CLASS.ToolDesc     = "Attempts to spawn the selected piston engine."
    CLASS.DefaultModel = "models/holograms/cube.mdl"

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
            local TypeName = ACF.Classes.GetTypeName(ClassList.Selected)
            ACF.SetClientData("EngineBlockModel", TypeName)
        end

        -- Set the tool's operations 
        ACF.SetClientData("PrimaryClass", "acf_engine_custom")
        ACF.SetClientData("SecondaryClass", "acf_fueltank")
        ACF.SetClientData("FuelTank", "ACF.FuelTanks.ScalableFuelTank") -- Set default fuel tank to scalable
    end
end)    