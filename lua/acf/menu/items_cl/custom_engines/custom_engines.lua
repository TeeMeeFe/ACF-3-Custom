local function CreateMenu(Menu)
    ACF.SetClientData("PrimaryClass", "N/A")
    ACF.SetClientData("SecondaryClass", "N/A")

    ACF.SetToolMode("acf_menu", "Spawner", "engine_custom")

    Menu:AddTitle("Custom Engine Settings")
    Menu:AddHelp("Create a custom engine from scratch.")

    local EntityClassDef = ACF.Classes.GetTypeByName("acf_engine_custom")
    local TypeSelector = ACF.Classes.CreateTypeSelector(Menu, EntityClassDef, "BlockType")
    local ClassList = TypeSelector.ComboBox

    PrintTable({ClassList})
end

ACF.AddMenuItem(299, "#acf.menu.entities", "Custom Engines", "car", CreateMenu)