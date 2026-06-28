local ACF     = ACF
local Classes = ACF.Classes

local function CreateMenu(Menu)
    ACF.SetClientData("PrimaryClass", "N/A")
    ACF.SetClientData("SecondaryClass", "N/A")

    ACF.SetToolMode("acf_menu", "Spawner", "acf_engine_custom")

    Menu:AddTitle("Custom Engine Settings")
    Menu:AddHelp("Create a custom engine from scratch.")

    local EntityClassDef = Classes.GetTypeByName("acf_engine_custom")
    Classes.CreateTypeSelector(Menu, EntityClassDef, "BlockType")
end

ACF.AddMenuItem(299, "#acf.menu.entities", "Custom Engines", "car_add", CreateMenu)