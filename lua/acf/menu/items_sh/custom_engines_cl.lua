local ACF     = ACF
local Classes = ACF.Classes
local GetType = Classes.GetTypeByName
local PAGE    = "acf_engine_custom"

local ENGINE_BLOCK_BASE = "ACF.CustomEngines.BaseEngineBlock"

local function Build(Menu, Contexts)
    Menu:AddTitle("Custom Engine Settings")
    Menu:AddHelp("Create a custom engine from scratch.")

    -- Engine "classes" are the direct children of the base engine (PistonBlock, TurbineBlock, ElectricBlock);
    -- Their items are the concrete engine types under each.
    local Entries = Classes.GetChildren(GetType(ENGINE_BLOCK_BASE))
    local Engine = Contexts.Engine

    local EngineBlockClass = Menu:AddComboBox()
    EngineBlockClass:SetName("EngineBlockClass")

    local SubPanel = Menu:AddPanel("ACF_Panel")

    ACF.Menu.LoadClassCombo(EngineBlockClass, Entries, "Name", nil, PAGE, "engine")

    function EngineBlockClass:OnSelect(Index, _, Data)
        if self.Selected == Data then return end

        self.ListData.Index = Index
        self.Selected = Data

        ACF.Menu.SaveClassCombo(PAGE, "group", Data)
        Engine:Set("Group", Classes.GetTypeName(Data))

        Menu:ClearTemporal(SubPanel)
        Menu:StartTemporal(SubPanel)

        if Data.CreateMenu then
            -- Equivalently ClassData.CreateMenu(ClassData, ListData, Menu, Base, UseLegacyRatios)
            Data.CreateMenu(SubPanel, Data, Engine)
        end

        Menu:EndTemporal(SubPanel)
    end
end

ACF.Menu.RegisterPage({
    ID       = "acf_engine_custom",
    Category = "#acf.menu.entities",
    Name     = "Custom Engines",
    Icon     = "car_add",
    Order    = 299,

    Contexts = { Engine = "acf_engine_custom" },

    -- Not yet my baby <3
    -- Actions = {
    --     { Bind = nil, Context = nil, Preview = false, Desc = "Select an option from the menu."},
    -- },

    Actions = {
        { Bind = "left",       Context = "Engine", Preview = true, Desc = "Spawn a new custom engine, or update the one you're aiming at." },
        { Bind = "shift+left", Context = "Fuel",   Preview = true, Desc = "Spawn a new fuel tank, or update the one you're aiming at." },
        { Bind = "right",      Commit = "link", Desc = "Select entities, then an engine/tank/radiator, to link them (hold R to unlink)." },
    },

    Build = Build,
})
