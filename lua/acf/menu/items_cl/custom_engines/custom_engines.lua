local function CreateMenu(Menu)
    ACF.SetToolMode("acf_menu", "Spawner", "engine")
    ACF.SetClientData("PrimaryClass", "acf_engine_custom")
    ACF.SetClientData("SecondaryClass", "acf_fueltank")
    ACF.SetClientData("FuelTank", "ACF.FuelTanks.ScalableFuelTank") -- Set default fuel tank to scalable

    ACF.SetToolMode("acf_menu", "Spawner", "Engine")

    Menu:AddTitle("Custom Engine Settings")
    Menu:AddHelp("Create a custom engine from scratch.")

    local EntityClassDef = ACF.Classes.GetTypeByName("acf_engine_custom")
    ACF.Classes.CreateTypeSelector(Menu, EntityClassDef, "BlockType")
end

ACF.AddMenuItem(299, "#acf.menu.entities", "Custom Engines", "car", CreateMenu)